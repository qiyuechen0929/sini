import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/chart_spec.dart' show kChartSystemHint;
import 'data/llm_provider.dart';
import 'models.dart';
import 'utils/image_gen.dart'
    show isImageRequest, extractImagePrompt, guessImageSize, kImageSystemHint;
import 'utils/memory_directive.dart';
import 'utils/message_edit.dart';
import 'utils/moments.dart'
    show MemoryMoment, buildMomentsDirective, extractMomentTitle, momentTitleFromText;
import 'utils/quote_reply.dart';
import 'utils/weekly_story.dart'
    show
        WeeklyStory,
        buildWeeklyStoryMaterial,
        shouldGenerateWeeklyStory,
        weekLabel,
        weekStartOf,
        weeklyStorySystemPrompt;
import 'utils/notify.dart' as notify;
import 'utils/night_guard.dart'
    show buildSleepLines, isDeepNight, looksLikeSeriousWork, nightKey;
import 'utils/persona_engine.dart' show buildPersonaDirective;
import 'utils/proactive_engine.dart';
import 'utils/recommend_card.dart' show recommendSystemHint;
import 'utils/relationship_engine.dart';
import 'utils/route_card.dart' show routeSystemHint;
import 'utils/connectors.dart'
    show ConnectorApi, ConnectorCall, findConnectorBlocks, tryParseConnectorJson;
import 'utils/todo_followup.dart'
    show TodoFollowUp, buildTodoNudgeLine, extractTodoFollowUp, looksLikeTodoDone;
import 'utils/roleplay_directive.dart'
    show buildRoleplayDirective, roleplayStartRequested, roleplayStopRequested;
import 'utils/romance_engine.dart'
    show
        AffinityState,
        MoodPoint,
        buildMoodDirective,
        buildRomanceDirective,
        moodToValue,
        nextMood,
        romanceUnlocked,
        updateRomanceScore;
import 'utils/safe_text.dart' show safeClip;
import 'utils/usage_store.dart' show UsageStore;
import 'utils/web_search.dart'
    show cleanSearchQuery, formatSearchContext, needsWebSearch, webSearch;

/// 全局状态：主题 / 侧栏 / 当前对话 / 消息 / 数字人格 / 模型选择。
/// 简单 MVP 用一个 ChangeNotifier 就够了，等接后端再换 Riverpod/Bloc。
/// 写信卡片（明信片）的状态机：收件人 → AI 起草 → 确认 → 发送
class EmailCompose {
  final String userPrompt; // 用户的原始诉求
  final int styleSeed; // 明信片样式随机种子
  String to;
  String subject;
  String body;
  int step; // 1=填收件人 2=编辑内容 3=确认发送
  bool generating;
  bool sending;
  bool sent;
  String? error;

  EmailCompose({
    required this.userPrompt,
    required this.styleSeed,
    this.to = '',
    this.subject = '',
    this.body = '',
    this.step = 1,
    this.generating = false,
    this.sending = false,
    this.sent = false,
    this.error,
  });
}

class AppState extends ChangeNotifier {
  // ---- Theme ----
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  void toggleTheme() {
    _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  // ---- 主动搭话（AI 主动来找用户说话）----
  /// 用户可在「设置」里开/关。**默认关闭**——这是要用户主动同意的事，
  /// 不能默认帮人打开。
  ///
  /// 打开后不是立刻说话，也不是按固定间隔说话：由 proactive_engine 让 LLM
  /// 结合人格 / 记忆 / 上下文 / 时间判断"此刻我会不会想找 TA"，再决定开口与否。
  bool _proactiveChatEnabled = false;
  bool get proactiveChatEnabled => _proactiveChatEnabled;

  /// 用户是否额外希望「弹系统通知」（手机通知栏 / 锁屏桌面弹窗）。
  /// 单独一个开关，因为浏览器弹权限申请必须由用户点击触发，
  /// 且用户可能只想要 App 内小红点、不想被系统通知打扰。
  bool _systemNotifyEnabled = false;
  bool get systemNotifyEnabled => _systemNotifyEnabled;

  // ---- 深夜守护（用户深夜还在聊时，TA 轻轻劝睡）----
  bool _nightGuardEnabled = true;
  bool get nightGuardEnabled => _nightGuardEnabled;

  // ---- 人格专属聊天背景（可关）----
  bool _personaBgEnabled = true;
  bool get personaBgEnabled => _personaBgEnabled;

  Future<void> setPersonaBgEnabled(bool v) async {
    if (_personaBgEnabled == v) return;
    _personaBgEnabled = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sini_persona_bg', v);
  }

  /// 今晚是否已劝过（按本地「夜」粒度）
  String? _nightGuardNight;
  DateTime? _nightGuardAt;

  /// 待展示的「深夜守护」小弹窗文案；UI 消费后调 [dismissNightGuardDialog]
  String? _nightGuardDialog;
  String? get nightGuardDialog => _nightGuardDialog;

  void dismissNightGuardDialog() {
    if (_nightGuardDialog == null) return;
    _nightGuardDialog = null;
    notifyListeners();
  }

  Future<void> setNightGuardEnabled(bool v) async {
    if (_nightGuardEnabled == v) return;
    _nightGuardEnabled = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sini_night_guard', v);
  }

  /// 回复结束后：若是深夜、还没劝过、且用户不是在硬核谈正事 → 劝睡 + 小弹窗
  Future<void> _maybeDeepNightGuardian(String userText) async {
    if (!_nightGuardEnabled) return;
    // 预览调试：URL 带 ?night=1 可强制走深夜窗口，方便白天自测
    var forceNight = false;
    try {
      forceNight = Uri.base.queryParameters.containsKey('night');
    } catch (_) {}
    final now = DateTime.now();
    if (!forceNight && !isDeepNight(now)) return;
    final key = forceNight ? 'force-${now.millisecondsSinceEpoch ~/ 60000}' : nightKey(now);
    if (!forceNight && _nightGuardNight == key) return;
    if (looksLikeSeriousWork(userText)) return;

    final persona = activePersona;
    final conv = activeConversation;
    if (persona == null || persona.locked) return;
    if (conv == null) return;

    _nightGuardNight = key;
    _nightGuardAt = now;
    final aff = _affinityOf(persona.id);
    final lines = buildSleepLines(
      relationship: persona.relationship.isEmpty ? null : persona.relationship,
      mood: aff.mood,
      personaName: persona.name,
    );
    _appendProactiveMessages(conv.id, lines);
    _nightGuardDialog = lines.first;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sini_night_guard_last', key);
    } catch (_) {}
  }

  // ---- 联网搜索配置 ----
  String _searchProvider = 'bocha'; // bocha | tavily
  String _searchKey = '';
  String get searchProvider => _searchProvider;
  String get searchKey => _searchKey;
  /// 搜索开箱即用：没配 Key 走免费源，配了走付费源
  bool get searchReady => true;

  // ---- 连接器（邮件 / GitHub）----
  bool _emailEnabled = false;
  String _emailAddress = '';
  String _githubToken = '';
  String _githubLogin = '';
  bool get emailBound => _emailAddress.isNotEmpty;
  bool get emailConnectorReady => _emailEnabled && _emailAddress.isNotEmpty;
  String get emailAddress => _emailAddress;
  bool get githubReady => _githubToken.isNotEmpty;
  String get githubLogin => _githubLogin;

  Future<void> _saveConnectorCfg() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kConnectors, jsonEncode({
      'emailEnabled': _emailEnabled,
      'email': _emailAddress,
      'ghToken': _githubToken,
      'ghLogin': _githubLogin,
    }));
  }

  Future<void> setEmailBinding(String email, {bool enabled = true}) async {
    _emailAddress = email.trim();
    _emailEnabled = enabled;
    await _saveConnectorCfg();
    notifyListeners();
  }

  Future<void> setEmailEnabled(bool v) async {
    _emailEnabled = v;
    await _saveConnectorCfg();
    notifyListeners();
  }

  Future<void> setGithub(String token, String login) async {
    _githubToken = token;
    _githubLogin = login;
    await _saveConnectorCfg();
    notifyListeners();
  }

  Future<void> disconnectGithub() async {
    _githubToken = '';
    _githubLogin = '';
    await _saveConnectorCfg();
    notifyListeners();
  }

  /// 连接器说明：注入 system prompt，让 TA 知道自己有哪些真实能力、怎么调用
  String? connectorsDirective() {
    const t = '```';
    final parts = <String>[];
    if (emailConnectorReady) {
      parts.add('邮件提醒已开启（收件邮箱：$_emailAddress）。'
          '仅当用户明确要求发邮件到邮箱（"发我邮箱"、"发封邮件"）时才输出此块；'
          '普通聊天、问候、闲聊绝对不要输出。输出格式：\n'
          '$t${t}connector\n'
          '{"type":"email","subject":"邮件标题","body":"完整正文"}\n'
          '$t\n'
          '收件人自动就是绑定的邮箱，不用写 to；正文写成完整可读的一封短信。');
    }
    if (githubReady) {
      parts.add('GitHub 已连接（账号：$_githubLogin）。'
          '当用户想了解自己的 GitHub 情况时，输出：\n'
          '$t${t}connector\n'
          '{"type":"github","op":"..."}\n'
          '$t\n'
          'op 按用户意图选：\n'
          '- profile：我的资料 / 我是谁 / 我的 GitHub 主页\n'
          '- repos：我的仓库 / 最近在写什么 / 代码库列表\n'
          '- issues：我的 Issue / 待处理的问题 / 分给我的任务\n'
          '- notifications：我的通知 / 有谁找我 / 最新动态\n'
          '输出这个块后立即停止（绝不要自己编造 GitHub 数据）；'
          '系统会把真实查询结果给你，你再用口吻总结回答。');
    }
    // 自动化：始终可用（消息动作无需任何绑定；邮件动作需已绑定）
    final now = DateTime.now();
    final week = '一二三四五六日'[now.weekday - 1];
    parts.add('自动化能力（当前时间：${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} 周$week）。'
        '当用户让你在指定时间做事（"每天早上8点…""明天早上发…""周五晚上提醒我…"），输出：\n'
        '$t${t}automation\n'
        '{"name":"8字内短名","type":"daily或once","time":"HH:mm",'
        '"date":"YYYY-MM-DD（type=once 时必填，按今天的日期推算"明天/周五"）",'
        '"action":"email或message",'
        '"prompt":"到点后执行的具体指令，写清楚要做什么、什么风格"}\n'
        '$t\n'
        '- type=daily：每天 time 执行；type=once：date 当天 time 执行一次\n'
        '- action=email：到点把 prompt 的内容写成邮件寄给用户'
        '${emailConnectorReady ? '（已绑定 $_emailAddress）' : '（用户未绑定邮箱，勿用 email）'}\n'
        '- action=message：到点你在聊天里主动发一条消息给用户\n'
        '- 时间推算要基于上面给的当前时间；创建后在回复里自然地向用户确认一句'
        '（说了什么、什么时候执行、去设置→自动化 可以管理）');

    if (parts.isEmpty) return null;
    return '【连接器 · 真实能力】你具备以下连接器，用户提出相关需求时按格式调用：\n\n'
        + parts.join('\n\n');
  }

  // ---- 自动化任务 ----
  final List<AutomationTask> _automations = [];
  Timer? _automationTimer;
  bool _automationRunning = false;
  List<AutomationTask> get automations =>
      List.unmodifiable(_automations);

  AutomationTask? automationById(String id) {
    for (final t in _automations) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _saveAutomations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAutomations,
        jsonEncode(_automations.map((t) => t.toJson()).toList()));
  }

  // ---- 回忆册 ----
  final List<MemoryMoment> _moments = [];
  static const _kMoments = 'sini_moments';

  List<MemoryMoment> momentsOf(String personaId) {
    final list = _moments.where((m) => m.personaId == personaId).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  Future<void> _saveMoments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kMoments, jsonEncode(_moments.map((m) => m.toJson()).toList()));
  }

  Future<void> addMoment({
    required String personaId,
    required String title,
    String? detail,
    bool manual = true,
  }) async {
    if (title.trim().isEmpty) return;
    _moments.add(MemoryMoment(
      id: 'mo_${DateTime.now().microsecondsSinceEpoch}',
      personaId: personaId,
      title: title.trim(),
      detail: detail?.trim(),
      at: DateTime.now(),
      manual: manual,
    ));
    if (_moments.length > 80) {
      _moments.sort((a, b) => b.at.compareTo(a.at));
      _moments.removeRange(80, _moments.length);
    }
    await _saveMoments();
    notifyListeners();
  }

  Future<void> deleteMoment(String id) async {
    _moments.removeWhere((m) => m.id == id);
    await _saveMoments();
    notifyListeners();
  }

  Future<void> updateMoment(String id, {String? title, String? detail}) async {
    final i = _moments.indexWhere((m) => m.id == id);
    if (i == -1) return;
    _moments[i] = _moments[i].copyWith(title: title, detail: detail);
    await _saveMoments();
    notifyListeners();
  }

  // ---- 每周故事 ----
  final List<WeeklyStory> _weeklyStories = [];
  static const _kWeeklyStories = 'sini_weekly_stories';
  bool _weeklyBusy = false;

  List<WeeklyStory> storiesOf(String personaId) {
    final list = _weeklyStories.where((s) => s.personaId == personaId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> _saveWeeklyStories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kWeeklyStories, jsonEncode(_weeklyStories.map((s) => s.toJson()).toList()));
  }

  /// 汇总本周消息（轻量，不调模型）
  String _weeklyChatDigest(String personaId, DateTime from, DateTime to) {
    final lines = <String>[];
    for (final c in _conversations.where((c) => c.personaId == personaId)) {
      for (final m in c.messages) {
        if (m.createdAt.isBefore(from) || !m.createdAt.isBefore(to)) continue;
        if (m.streaming) continue;
        final t = m.content.trim();
        if (t.isEmpty || t.startsWith('⚠️')) continue;
        lines.add('${m.isUser ? "我" : "TA"}：$t');
      }
    }
    // 最多带 40 条，防止超长
    if (lines.length > 40) {
      return lines.sublist(lines.length - 40).join('\n');
    }
    return lines.join('\n');
  }

  /// 生成（或补生成）本周故事。成功返回 true。
  Future<bool> generateWeeklyStoryNow({bool force = true}) async {
    if (_weeklyBusy) return false;
    final persona = activePersona;
    final cfg = defaultModelConfig;
    if (persona == null || cfg == null || persona.locked) return false;

    final now = DateTime.now();
    final start = weekStartOf(now);
    final end = start.add(const Duration(days: 7));
    final exists = _weeklyStories.any((s) =>
        s.personaId == persona.id &&
        s.weekStart.year == start.year &&
        s.weekStart.month == start.month &&
        s.weekStart.day == start.day);
    if (exists && !force) return false;

    final moments = momentsOf(persona.id)
        .where((m) => !m.at.isBefore(start) && m.at.isBefore(end))
        .map((m) => m.title)
        .toList();
    final digest = _weeklyChatDigest(persona.id, start, end);
    if (digest.trim().isEmpty && moments.isEmpty) {
      // 没素材不生成空故事
      if (!force) return false;
    }

    _weeklyBusy = true;
    notifyListeners();
    try {
      final material = buildWeeklyStoryMaterial(
        personaName: persona.name,
        chatDigest: digest.isEmpty ? '（本周几乎没聊）' : digest,
        momentTitles: moments,
      );
      final res = await chatComplete(
        cfg: cfg,
        messages: [
          {'role': 'system', 'content': weeklyStorySystemPrompt(persona.name)},
          {'role': 'user', 'content': material},
        ],
        temperature: 0.9,
        maxTokens: 900,
      );
      final body = (res.ok && res.content != null) ? res.content!.trim() : '';
      if (body.isEmpty) return false;
      _weeklyStories.removeWhere((s) =>
          s.personaId == persona.id &&
          s.weekStart.year == start.year &&
          s.weekStart.month == start.month &&
          s.weekStart.day == start.day);
      _weeklyStories.insert(
        0,
        WeeklyStory(
          id: 'ws_${now.microsecondsSinceEpoch}',
          personaId: persona.name.isEmpty ? persona.id : persona.id,
          title: weekLabel(start, end.subtract(const Duration(days: 1))),
          body: body,
          weekStart: start,
          weekEnd: end,
          createdAt: now,
        ),
      );
      if (_weeklyStories.length > 20) {
        _weeklyStories.removeRange(20, _weeklyStories.length);
      }
      await _saveWeeklyStories();
      notifyListeners();
      return true;
    } finally {
      _weeklyBusy = false;
    }
  }

  /// 周日晚补跑：App 开着时自动生成
  Future<void> _maybeAutoWeeklyStory() async {
    if (_weeklyBusy) return;
    if (defaultModelConfig == null) return;
    if (activePersona == null || activePersona!.locked) return;
    final pid = activePersona!.id;
    WeeklyStory? last;
    for (final s in _weeklyStories.where((x) => x.personaId == pid)) {
      if (last == null || s.weekStart.isAfter(last.weekStart)) last = s;
    }
    final lastStart = last?.weekStart;
    if (!shouldGenerateWeeklyStory(
      now: DateTime.now(),
      lastGeneratedWeekStart: lastStart,
    )) {
      return;
    }
    await generateWeeklyStoryNow(force: false);
  }

  /// 回复完成后：从这轮对话里尝试自动沉淀一条回忆
  void _maybeAutoMoment(String personaId, String userText, String assistantText) {
    final title = extractMomentTitle(userText: userText, assistantText: assistantText);
    if (title == null) return;
    // 同人格近似标题 3 小时内不重复
    final now = DateTime.now();
    final dup = _moments.any((m) =>
        m.personaId == personaId &&
        m.title == title &&
        now.difference(m.at).abs().inHours < 3);
    if (dup) return;
    _moments.add(MemoryMoment(
      id: 'mo_${now.microsecondsSinceEpoch}',
      personaId: personaId,
      title: title,
      at: now,
      manual: false,
    ));
    if (_moments.length > 80) {
      _moments.sort((a, b) => b.at.compareTo(a.at));
      _moments.removeRange(80, _moments.length);
    }
    _saveMoments();
    notifyListeners();
  }

  // ---- 待办确认闭环 ----
  final List<TodoFollowUp> _todos = [];
  static const _kTodos = 'sini_todos';
  bool _todoRunning = false;

  List<TodoFollowUp> get openTodos =>
      _todos.where((t) => !t.done).toList(growable: false);

  Future<void> _saveTodos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTodos, jsonEncode(_todos.map((t) => t.toJson()).toList()));
  }

  /// 用户发消息后：抓「明天/今晚…」待办；若是在回复待办，标完成
  void _trackTodoFromUserText(String personaId, String text) {
    // 完成语义 → 勾掉最近一条未完成
    if (looksLikeTodoDone(text)) {
      for (var i = _todos.length - 1; i >= 0; i--) {
        if (_todos[i].personaId == personaId && !_todos[i].done) {
          _todos[i] = _todos[i].copyWith(done: true);
          _saveTodos();
          notifyListeners();
          break;
        }
      }
    }
    final todo = extractTodoFollowUp(
      personaId: personaId,
      text: text,
      now: DateTime.now(),
    );
    if (todo == null) return;
    // 同人格、同 due 时段只留一条近似的
    final dup = _todos.any((t) =>
        !t.done &&
        t.personaId == todo.personaId &&
        t.dueAt.difference(todo.dueAt).abs().inMinutes < 120 &&
        t.text == todo.text);
    if (dup) return;
    _todos.add(todo);
    if (_todos.length > 40) {
      _todos.removeWhere((t) => t.done);
      while (_todos.length > 40) {
        _todos.removeAt(0);
      }
    }
    _saveTodos();
    notifyListeners();
  }

  /// 心跳：到点的待办，TA 用主动消息追一句
  Future<void> _runDueTodos() async {
    if (_todoRunning) return;
    final now = DateTime.now();
    final due = _todos
        .where((t) => !t.done && !t.dueAt.isAfter(now))
        .toList();
    if (due.isEmpty) return;
    _todoRunning = true;
    try {
      for (final todo in due) {
        final conv = _latestConversationOf(todo.personaId) ??
            _conversations.where((c) => c.personaId == todo.personaId).firstOrNull;
        if (conv == null) continue;
        _appendProactiveMessages(conv.id, [buildTodoNudgeLine(todo.text)]);
        final i = _todos.indexWhere((t) => t.id == todo.id);
        if (i != -1) {
          _todos[i] = _todos[i].copyWith(done: true);
        }
      }
      await _saveTodos();
      notifyListeners();
    } finally {
      _todoRunning = false;
    }
  }

  Future<void> addAutomation(AutomationTask task) async {
    _automations.add(task);
    await _saveAutomations();
    notifyListeners();
  }

  Future<void> updateAutomation(AutomationTask task) async {
    final i = _automations.indexWhere((t) => t.id == task.id);
    if (i == -1) return;
    _automations[i] = task;
    await _saveAutomations();
    notifyListeners();
  }

  Future<void> deleteAutomation(String id) async {
    _automations.removeWhere((t) => t.id == id);
    await _saveAutomations();
    notifyListeners();
  }

  /// 后台心跳：每 30 秒检查到期任务（app 打开期间执行；到点未开 app 的任务
  /// 会在下次打开时补跑一次——daily 补当天，once 过期就标记完成不再跑）
  void _startAutomationTimer() {
    _automationTimer ??= Timer.periodic(const Duration(seconds: 30), (_) async {
      await _runDueAutomations();
      await _runDueTodos();
      await _maybeAutoWeeklyStory();
    });
  }

  Future<void> _runDueAutomations() async {
    if (_automationRunning) return;
    final now = DateTime.now();
    final due = _automations
        .where((t) =>
            t.enabled &&
            t.nextRunAt != null &&
            !t.nextRunAt!.isAfter(now))
        .toList();
    if (due.isEmpty) return;
    _automationRunning = true;
    try {
      for (final task in due) {
        await _executeAutomation(task, now);
        final i = _automations.indexWhere((t) => t.id == task.id);
        if (i == -1) continue;
        final t = _automations[i];
        if (t.daily) {
          _automations[i] = t.copyWith(
              lastRunAt: now, nextRunAt: t.computeNextRun(now));
        } else {
          // 单次任务跑完即停用
          _automations[i] = t.copyWith(
              lastRunAt: now, enabled: false, nextRunAt: null);
        }
      }
      await _saveAutomations();
      notifyListeners();
    } finally {
      _automationRunning = false;
    }
  }

  Future<void> _executeAutomation(AutomationTask task, DateTime now) async {
    final cfg = defaultModelConfig;
    final persona =
        _personas.where((x) => x.id == task.personaId).firstOrNull;
    if (cfg == null || persona == null) return;
    _tagUsagePersona(task.personaId);
    final sys = buildPersonaDirective(persona);

    // 邮件动作：TA 起草并寄到绑定邮箱；未绑定邮箱就退化为聊天消息
    if (task.action == 'email' && emailConnectorReady) {
      final res = await chatComplete(cfg: cfg, messages: [
        {
          'role': 'system',
          'content': sys +
              '\n\n【定时任务】现在是 ${now.month}月${now.day}日 '
                  '${now.hour}:${now.minute.toString().padLeft(2, '0')}，'
                  '执行自动化「${task.name}」。任务指令：${task.prompt}\n'
                  '把要寄给用户的邮件写出来。只输出严格 JSON：'
                  '{"subject":"30字内标题","body":"完整正文，含称呼落款"}'
        },
        {'role': 'user', 'content': task.prompt},
      ], temperature: 0.85);
      var subject = task.name;
      var body = task.prompt;
      if (res.ok && (res.content?.isNotEmpty ?? false)) {
        final c = res.content!;
        final start = c.indexOf('{');
        final end = c.lastIndexOf('}');
        if (start >= 0 && end > start) {
          try {
            final parsed = jsonDecode(c.substring(start, end + 1));
            if (parsed is Map<String, dynamic>) {
              subject = (parsed['subject'] ?? subject).toString();
              body = (parsed['body'] ?? body).toString();
            }
          } catch (_) {}
        }
      }
      await ConnectorApi.emailSend(
          to: _emailAddress,
          subject: subject.length > 60 ? subject.substring(0, 60) : subject,
          body: body.length > 6000 ? body.substring(0, 6000) : body);
      return;
    }

    // 消息动作：以 TA 的身份在对话里发一条主动消息
    final res = await chatComplete(cfg: cfg, messages: [
      {
        'role': 'system',
        'content': sys +
            '\n\n【定时任务】现在是 ${now.month}月${now.day}日 '
                '${now.hour}:${now.minute.toString().padLeft(2, '0')}，'
                '执行自动化「${task.name}」。任务指令：${task.prompt}\n'
                '直接输出现在要发给用户的消息文本（像聊天一样，1~3 句），不要任何解释。'
        },
      {'role': 'user', 'content': task.prompt},
    ], temperature: 0.9, maxTokens: 400);
    final text = res.ok ? (res.content ?? '').trim() : '';
    if (text.isEmpty) return;
    var convId = _latestConversationIdOf(task.personaId);
    if (convId == null) {
      final c = Conversation(
        id: 'c_${DateTime.now().microsecondsSinceEpoch}',
        title: persona.name,
        personaId: task.personaId,
        updatedAt: now,
      );
      _conversations.add(c);
      convId = c.id;
    }
    _appendProactiveMessages(convId, [text]);
  }

  // ---- 写信卡片（明信片）----
  EmailCompose? _emailCompose;
  EmailCompose? get emailCompose => _emailCompose;

  static final RegExp _emailAddrRe =
      RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');

  /// 定时/周期意图：出现即表示用户要的是自动化而不是立即执行的动作
  static bool _hasScheduleIntent(String t) => RegExp(
          r'每天|每周|每日|明日|明天|后天|下周|定时|自动化|提醒我|准时|'
          r'分钟后|小时后|天之后|天后|半个?小时|待会儿?|等会儿?|'
          r'[零一二两三四五六七八九十]+点|[零一二两三四五六七八九十]+分钟|'
          r'\d{1,2}[点：:]\d{0,2}|\d+分钟|\d+小时|\d+天后',
          caseSensitive: false)
      .hasMatch(t);

  /// 提到「邮件」且带发送/撰写动词、或消息里带邮箱地址+发/写/寄、或明确说发到某邮箱
  static bool _looksLikeEmailCompose(String t) {
    // 定时类请求（每天/明天/X点/X分钟后/提醒我…）优先走自动化，不弹写信卡片
    if (_hasScheduleIntent(t)) {
      return false;
    }
    if (RegExp(r'发我邮箱|发到\S{0,24}邮箱', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    // 消息里出现邮箱地址 + 发/写/寄（"发到 xxx@gmail.com 请他吃饭"）
    if (_emailAddrRe.hasMatch(t) && RegExp(r'发|写|寄').hasMatch(t)) return true;
    if (!t.contains('邮件')) return false;
    return RegExp(r'发|写|寄|邀请|起草|准备').hasMatch(t);
  }

  /// 设置最后一条助手消息为写信卡片
  void _setLastEmailComposeFlag() {
    final id = _activeConversationId;
    if (id == null) return;
    final ci = _conversations.indexWhere((c) => c.id == id);
    if (ci == -1) return;
    final conv = _conversations[ci];
    if (conv.messages.isEmpty || conv.messages.last.isUser) return;
    final msgs = [...conv.messages];
    msgs[msgs.length - 1] = msgs.last.copyWith(emailCompose: true);
    _conversations[ci] = conv.copyWith(messages: msgs);
    _saveConversations();
  }

  /// 用户发消息后：识别写信意图 → 开启明信片流程（不走红聊回复）。
  /// 返回是否进入了写信流程（false = 正常聊天）。
  bool _maybeStartEmailCompose(String text) {
    // 先归档遗留的明信片（寄出/取消后残留会卡住后续对话）
    if (_emailCompose != null) _finalizeEmailComposeMessage();
    if (!_looksLikeEmailCompose(text)) return false;
    if (!emailConnectorReady) return false; // 未绑定邮箱就走普通聊天
    // 收件人优先取用户消息里直接写明的邮箱地址；没有才是「发给自己」
    final addr = _emailAddrRe.firstMatch(text)?.group(0) ?? '';
    final toSelf = addr.isEmpty &&
        RegExp(r'发到(我|自己)?(的)?邮箱|发我邮箱').hasMatch(text);
    final to = addr.isNotEmpty ? addr : (toSelf ? _emailAddress : '');
    _cancelStream();
    _emailCompose = EmailCompose(
      userPrompt: text,
      styleSeed: DateTime.now().millisecondsSinceEpoch % 3,
      to: to,
      step: to.isNotEmpty ? 2 : 1,
    );
    _setLastEmailComposeFlag();
    notifyListeners();
    if (toSelf) generateEmailDraft();
    return true;
  }

  /// 把写信卡片收尾成一条普通文字消息（历史里保留痕迹，聊天恢复正常）
  void _finalizeEmailComposeMessage({String? note}) {
    final c = _emailCompose;
    _emailCompose = null;
    final id = _activeConversationId;
    if (id == null) return;
    final ci = _conversations.indexWhere((x) => x.id == id);
    if (ci == -1) return;
    final conv = _conversations[ci];
    if (conv.messages.isEmpty) return;
    // 从后往前找写信卡片（新消息进来时它可能已经不是最后一条了）
    var idx = -1;
    for (var i = conv.messages.length - 1; i >= 0; i--) {
      if (conv.messages[i].emailCompose) {
        idx = i;
        break;
      }
    }
    if (idx == -1) return;
    final card = conv.messages[idx];
    final text = note ??
        (c?.sent == true ? '📬 明信片已寄出，寄往 ${c!.to}' : '_（✉️ 已取消写信）_');
    final msgs = [...conv.messages];
    msgs[idx] = card.copyWith(
        emailCompose: false, content: text, streaming: false);
    _conversations[ci] = conv.copyWith(messages: msgs);
    _saveConversations();
  }

  void cancelEmailCompose() {
    _finalizeEmailComposeMessage();
    notifyListeners();
  }

  void confirmEmailRecipient(String to) {
    final c = _emailCompose;
    if (c == null) return;
    c.to = to.trim();
    c.step = 2;
    notifyListeners();
    generateEmailDraft();
  }

  void emailComposeEditStep() {
    final c = _emailCompose;
    if (c == null) return;
    c.step = 2;
    notifyListeners();
  }

  void emailComposeConfirmStep() {
    final c = _emailCompose;
    if (c == null) return;
    c.step = 3;
    notifyListeners();
  }

  /// 让 TA 起草 / 重新起草邮件内容
  Future<void> generateEmailDraft() async {
    final c = _emailCompose;
    if (c == null || c.to.isEmpty) return;
    final cfg = defaultModelConfig;
    if (cfg == null) {
      c.error = '没有可用的对话模型';
      notifyListeners();
      return;
    }
    c.generating = true;
    c.error = null;
    notifyListeners();
    final res = await chatComplete(cfg: cfg, messages: [
      {
        'role': 'system',
        'content': '${_systemPrompt()}\n\n'
            '【写信任务】用户想让你帮忙写一封邮件，收件人：${c.to}。\n'
            '用户的原始诉求：「${c.userPrompt}」\n'
            '请以你的身份和口吻起草这封邮件。只输出严格 JSON，不要任何多余文字：\n'
            '{"subject":"30字以内的邮件标题","body":"完整邮件正文，包含称呼、正文、落款；纯文本，不用markdown"}'
      },
      {'role': 'user', 'content': c.userPrompt},
    ], temperature: 0.9);
    var ok = false;
    if (res.ok && (res.content?.isNotEmpty ?? false)) {
      final j = res.content!;
      final start = j.indexOf('{');
      final end = j.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          final parsed = jsonDecode(j.substring(start, end + 1));
          if (parsed is Map<String, dynamic>) {
            c.subject = (parsed['subject'] ?? '').toString();
            c.body = (parsed['body'] ?? '').toString();
            c.step = 2;
            ok = true;
          }
        } catch (_) {}
      }
    }
    c.generating = false;
    if (!ok) c.error = res.error ?? '起草失败，点重新生成试试';
    notifyListeners();
  }

  /// 真实发送（用户最终确认后）
  Future<void> sendEmailNow() async {
    final c = _emailCompose;
    if (c == null || c.sending || c.sent) return;
    c.sending = true;
    c.error = null;
    notifyListeners();
    final r = await ConnectorApi.emailSend(
        to: c.to, subject: c.subject, body: c.body);
    c.sending = false;
    if (r.ok) {
      c.sent = true;
    } else {
      c.error = r.error;
    }
    notifyListeners();
  }

  // ---- 用量统计：标记当前调用归属的人格 ----
  void _tagUsagePersona([String? personaId]) {
    final id = personaId ?? activePersona?.id;
    usagePersonaName = id == null
        ? null
        : _personas.where((x) => x.id == id).firstOrNull?.name;
  }

  // ---- 亲密度 / 情绪状态（恋爱感引擎的状态存储）----
  final Map<String, AffinityState> _affinity = {};

  AffinityState _affinityOf(String personaId) =>
      _affinity.putIfAbsent(personaId, () => AffinityState());

  /// 给详情页读：某个人格的心情/信号历史
  List<MoodPoint> moodHistoryOf(String personaId) {
    final st = _affinity[personaId];
    if (st == null) return const [];
    return List.unmodifiable(st.history);
  }

  AffinityState? affinityOf(String personaId) => _affinity[personaId];

  /// 用户每发一条消息：更新恋爱信号 + 推导 TA 此刻的心情。
  /// 在 _buildPrompt 之前调用，本轮回复就能带上正确的状态底色。
  void updateAffinityOnUserMessage(String personaId, String text) {
    final st = _affinityOf(personaId);
    final persona = _personas.where((x) => x.id == personaId).firstOrNull;
    updateRomanceScore(st, text, DateTime.now());
    nextMood(
      st: st,
      userText: text,
      isLover: persona?.relationship == '恋人',
    );
    st.logPoint(DateTime.now());
    _saveAffinity();
    notifyListeners();
  }

  Future<void> _saveAffinity() async {
    final prefs = await SharedPreferences.getInstance();
    final m = <String, dynamic>{};
    _affinity.forEach((k, v) => m[k] = v.toJson());
    await prefs.setString(_kAffinity, jsonEncode(m));
  }

  Future<void> updateSearchConfig({String? provider, required String key}) async {
    _searchProvider = provider ?? _searchProvider;
    _searchKey = key.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSearch, jsonEncode({
      'provider': _searchProvider,
      'key': _searchKey,
    }));
  }

  /// 浏览器通知权限是否已授权
  bool get systemNotifyGranted =>
      notify.notifySupported &&
      notify.notifyPermission == notify.NotifyPermission.granted;

  /// 浏览器是否支持系统通知（不支持时设置项显示为不可用）
  bool get systemNotifySupported => notify.notifySupported;

  /// 打开/关闭系统通知。打开时**在此处申请浏览器权限**（此处必然处于用户点击
  /// 事件流里，满足浏览器"用户手势"要求）。返回 null 表示成功，否则是错误提示。
  Future<String?> setSystemNotifyEnabled(bool v) async {
    if (!v) {
      _systemNotifyEnabled = false;
      notify.setDocumentTitle('似你');
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSystemNotify, false);
      return null;
    }
    if (!notify.notifySupported) {
      return '当前浏览器不支持系统通知';
    }
    final perm = await notify.requestNotifyPermission();
    if (perm != notify.NotifyPermission.granted) {
      _systemNotifyEnabled = false;
      notifyListeners();
      return perm == notify.NotifyPermission.denied
          ? '已被浏览器拒绝。请在地址栏左侧的站点设置里把「通知」改为允许，再试一次'
          : '还没有拿到通知权限，请再点一次并选择「允许」';
    }
    _systemNotifyEnabled = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSystemNotify, true);
    return null;
  }

  /// 打开开关后是否已有过一次主动搭话（用于判断"冷启动"：太久没聊过时
  /// 第一次开口可以让它主动一点，之后恢复正常节奏）
  Timer? _proactiveTimer;

  Future<void> setProactiveChatEnabled(bool v) async {
    if (_proactiveChatEnabled == v) return;
    _proactiveChatEnabled = v;
    if (v) {
      _startProactiveTimer();
    } else {
      _stopProactiveTimer();
    }
    _proactiveTick = 0;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kProactiveChat, v);
  }

  // ---- Sidebar ----
  /// 三态：forceOpen（强制打开，用于桌面宽屏默认） / auto（根据宽度自动） / forceClose（用户主动收起）
  bool _sidebarOpen = true;
  bool get sidebarOpen => _sidebarOpen;
  void setSidebarOpen(bool v) {
    if (_sidebarOpen == v) return;
    _sidebarOpen = v;
    notifyListeners();
  }
  void toggleSidebar() {
    _sidebarOpen = !_sidebarOpen;
    notifyListeners();
  }

  // ---- Personas ----
  /// 初始不预置任何人格：必须由用户自己创建（从零开始）
  late List<Persona> _personas = <Persona>[];
  List<Persona> get personas => List.unmodifiable(_personas);
  bool get hasPersonas => _personas.isNotEmpty;

  /// 对话搜索命中
  List<ConversationSearchHit> searchMessages(String query) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final out = <ConversationSearchHit>[];
    for (final c in _conversations) {
      for (final m in c.messages) {
        if (m.streaming) continue;
        final i = m.content.toLowerCase().indexOf(q.toLowerCase());
        if (i < 0) continue;
        final start = i > 20 ? i - 20 : 0;
        final end = (i + q.length + 40).clamp(0, m.content.length);
        out.add(ConversationSearchHit(
          conversationId: c.id,
          conversationTitle: c.title,
          messageId: m.id,
          snippet: m.content.substring(start, end),
          isUser: m.isUser,
          at: m.createdAt,
        ));
        if (out.length >= 40) return out;
      }
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  /// 用户在首次引导页点了「先跳过」：不再展示完整引导，主区换成精简卡片，
  /// 侧栏照常可用，方便之后自己创建人格。
  bool _guideSkipped = false;
  bool get guideSkipped => _guideSkipped;
  Future<void> setGuideSkipped(bool v) async {
    if (_guideSkipped == v) return;
    _guideSkipped = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGuideSkipped, v);
  }

  /// 点「先跳过」：直接进主界面。
  /// 没有聊天对象的话主界面根本没法用，所以兜底建一个「默认助手」人格，
  /// 用户之后创建了真实人物可以随时把它删掉。
  Future<void> skipGuide() async {
    await setGuideSkipped(true);
    if (_personas.isNotEmpty) return;
    final fallback = Persona(
      id: 'default_${DateTime.now().millisecondsSinceEpoch}',
      name: '默认助手',
      subtitle: '还没设定人格 · 可随时创建真实人物',
      gradientSeed: const [210, 214, 220, 176, 182, 200],
      locked: true,
    );
    addPersona(fallback);
    selectPersona(fallback.id);
    newConversation();
  }

  // ---- 创建中的声音草稿 ----
  // 创建人格流程里克隆的声音：此时人格还不存在，先把授权/参考信息暂存在
  // 内存里，等用户点「保存并创建」时随人格一起落库（见 Persona.voice）。
  // 不持久化：真丢了也只是重新克隆一次，不值得为它增加磁盘格式。
  PersonaVoice? _draftVoice;
  PersonaVoice? get draftVoice => _draftVoice;
  void setDraftVoice(PersonaVoice v) {
    _draftVoice = v;
    notifyListeners();
  }

  /// 取走草稿声音（创建人格时调用，取完即清）。
  PersonaVoice? takeDraftVoice() {
    final v = _draftVoice;
    _draftVoice = null;
    if (v != null) notifyListeners();
    return v;
  }

  String? _activePersonaId;
  String? get activePersonaId => _activePersonaId;
  Persona? get activePersona =>
      _personas.where((p) => p.id == _activePersonaId).cast<Persona?>().firstOrNull;

  /// 按 id 找人挌（用于渲染历史消息的头像：
  /// 消息属于哪个对话，就显示哪个对话的人格，而不是"当前选中的人格"）。
  Persona? personaById(String? id) {
    if (id == null) return null;
    return _personas.where((p) => p.id == id).cast<Persona?>().firstOrNull;
  }

  /// 按对话 id 找人挌：对话 → personaId → Persona。
  Persona? personaOfConversation(String conversationId) {
    final conv =
        _conversations.where((c) => c.id == conversationId).cast<Conversation?>().firstOrNull;
    return personaById(conv?.personaId);
  }
  /// 切换人格：同时切到「和这个人格的最近一次对话」。
  /// 如果该人格还没有任何对话 → activeConversation 置空，聊天区回到空状态（发第一条时自动建）。
  void selectPersona(String id) {
    final cur = activeConversation;
    // 已经在跟 TA 聊了，不动，避免打断当前对话
    if (_activePersonaId == id && cur != null && cur.personaId == id) return;
    _cancelStream(); // 打断上一个正在生成的回复，避免写进新对话
    _activePersonaId = id;
    _activeConversationId = _latestConversationIdOf(id);
    _markRead(_activeConversationId);
    notifyListeners();
  }

  // ---- 人格版本（表达模式）----
  /// 三个「人格版本」：同一位数字人格可有不同表达风格。
  /// 默认人格=平衡；创意模式=更自由发散；高保真=严格还原原始风格。
  late final List<ModelOption> _models = const [
    ModelOption(
      id: 'sini-default',
      label: '似你 · 默认人格',
      description: '平衡表达与稳定。忠实还原人格内核，松紧适度，像真人私聊一样自然。',
    ),
    ModelOption(
      id: 'sini-creative',
      label: '似你 · 创意模式',
      description: '表达更自由奔放：主动补充情绪 / 场景 / 细节，多用画面感与联想，对话更有火花。',
    ),
    ModelOption(
      id: 'sini-strict',
      label: '似你 · 高保真',
      description: '高保真还原：严格遵循原始风格，输出克制准确，不自行编造或发散。',
    ),
  ];
  List<ModelOption> get models => _models;
  String _activeModelId = 'sini-default';
  String get activeModelId => _activeModelId;
  ModelOption get activeModel =>
      _models.firstWhere((m) => m.id == _activeModelId, orElse: () => _models.first);
  Future<void> selectModel(String id) async {
    if (_activeModelId == id) return;
    _activeModelId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModeId, id);
  }

  /// 根据当前人格版本，拼出注入 system prompt 的风格指令。
  String _modeDirective(String personaName) {
    switch (_activeModelId) {
      case 'sini-creative':
        return '''
【表达版本：创意模式】
在守住「$personaName」人格内核与基本事实的前提下，表达更大胆、更有画面感：
- 主动补充情绪、场景、细节与联想，让对话更有火花；
- 多用比喻、画面感与生动措辞，允许适度发散与提议；
- 可以主动抛想法、给选项、带点玩心，但始终以「$personaName」的身份和口吻说话，不能跳出人设。''';
      case 'sini-strict':
        return '''
【表达版本：高保真】
严格还原你已有的设定、记忆与原始聊天风格，追求高保真：
- 输出克制、准确、贴近原始语气，不自行添加设定外的人设细节；
- 不主动发散、不堆砌修辞；宁可简短真实，也不要为"好看"而编造；
- 若记忆 / 设定里没有相关信息，就如实以该人格的自然方式带过，绝不虚构。''';
      case 'sini-default':
      default:
        return '''
【表达版本：默认人格】
以平衡、自然的方式表达：在忠实还原人格内核的前提下松紧适度——既不刻意扩写，也不过度克制，像真人私聊一样自然推进。''';
    }
  }
  String? _latestConversationIdOf(String personaId) {
    final own = _conversations.where((c) => c.personaId == personaId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return own.isEmpty ? null : own.first.id;
  }

  /// 某个人格名下的历史消息总数（分享卡片上的「养成感」数据）。
  int messageCountOfPersona(String personaId) => _conversations
      .where((c) => c.personaId == personaId)
      .fold(0, (n, c) => n + c.messages.length);

  /// 某个人格最早一条消息的时间（用来算「养成天数」）；没聊过返回 null。
  DateTime? firstMessageAtOfPersona(String personaId) {
    DateTime? earliest;
    for (final c in _conversations.where((c) => c.personaId == personaId)) {
      for (final m in c.messages) {
        if (earliest == null || m.createdAt.isBefore(earliest)) {
          earliest = m.createdAt;
        }
      }
    }
    return earliest;
  }

  void addPersona(Persona p) {
    _personas = [..._personas, p];
    _savePersonas();
    notifyListeners();
  }

  /// 更新人格设定（关系 / 认识时间 / 描述 / 性格维度）。
  /// 保存后下一句回复立即按新设定走，历史消息不受影响。
  ///
  /// [persist] = false 用于「拖动滑块」等高频场景：只更新内存与界面，
  /// 不写 SharedPreferences，避免每帧一次磁盘写入导致卡顿；
  /// 用户松手后再以 persist: true 调一次完成落盘。
  void updatePersona(Persona updated, {bool persist = true}) {
    _personas =
        _personas.map((p) => p.id == updated.id ? updated : p).toList();
    if (persist) _savePersonas();
    notifyListeners();
  }

  /// 记下这个人格的**声音授权与状态**（技术方案要求：授权必须有记录、可查看、可撤销）。
  void setPersonaVoice(String personaId, PersonaVoice voice) {
    final i = _personas.indexWhere((p) => p.id == personaId);
    if (i == -1) return;
    _personas[i] = _personas[i].copyWith(voice: voice);
    _savePersonas();
    notifyListeners();
  }

  /// 撤销声音授权：把记录一起删掉。
  ///
  /// 注意：模型里没有保存音频样本本身，所以删除后不需要额外清理音频文件，
  /// 但要**同时把已加载的音色状态清掉**，否则界面还会显示"已配声音"。
  void removePersonaVoice(String personaId) {
    final i = _personas.indexWhere((p) => p.id == personaId);
    if (i == -1) return;
    _personas[i] = _personas[i].copyWith(clearVoice: true);
    _savePersonas();
    notifyListeners();
  }

  /// 把「从聊天记录学来的东西」一次性写进人格。
  ///
  /// 三件事一起做：
  ///  1. 风格画像（"像不像"的核心）；
  ///  2. 由证据推出的四个性格维度（用户之后仍可手改）；
  ///  3. 从记录里抽出的长期记忆。
  ///
  /// 关系 / 认识时间**只在人格原本为空时才填** —— 用户亲手写的东西优先级更高，
  /// 不能被 AI 的推测覆盖。
  void applyImportedStyle({
    required String personaId,
    required PersonaStyle style,
    Map<String, double> traits = const {},
    List<Map<String, String>> memories = const [],
    String relationshipGuess = '',
    String sinceGuess = '',
  }) {
    final idx = _personas.indexWhere((p) => p.id == personaId);
    if (idx < 0) return;
    final old = _personas[idx];

    final updated = old.copyWith(
      style: style,
      warmth: traits['warmth'] ?? old.warmth,
      rationality: traits['rationality'] ?? old.rationality,
      initiative: traits['initiative'] ?? old.initiative,
      humor: traits['humor'] ?? old.humor,
      relationship: old.relationship.trim().isNotEmpty
          ? old.relationship
          : relationshipGuess.trim(),
      since: old.since.trim().isNotEmpty ? old.since : sinceGuess.trim(),
    );
    _personas = [..._personas]..[idx] = updated;
    _savePersonas();
    notifyListeners();

    if (memories.isNotEmpty) {
      final facts = memories
          .map((m) => (m['text'] ?? '').trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (facts.isNotEmpty) _addPersonaMemoryItems(personaId, facts, const []);
    }
  }

  void deletePersona(String id) {
    _personas = _personas.where((p) => p.id != id).toList();
    // 连带清掉这个人格名下的所有对话（记忆随人格一起删除，天然不串台）
    _conversations.removeWhere((c) => c.personaId == id);
    if (_activePersonaId == id) {
      _activePersonaId = _personas.isNotEmpty ? _personas.first.id : null;
      _activeConversationId =
          _activePersonaId == null ? null : _latestConversationIdOf(_activePersonaId!);
    }
    _savePersonas();
    notifyListeners();
  }

  /// 人格（含长期记忆）落盘
  Future<void> _savePersonas() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPersonas,
      jsonEncode(_personas.map((p) => p.toJson()).toList()),
    );
  }

  // ---- Conversations ----
  final List<Conversation> _conversations = [];
  List<Conversation> get conversations {
    final list = [..._conversations];
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// 只属于当前人格的对话（侧栏用，切换人格时列表跟着变）
  List<Conversation> get conversationsForActivePersona {
    final list = _conversations.where((c) => c.personaId == _activePersonaId).toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  String? _activeConversationId;
  String? get activeConversationId => _activeConversationId;

  Conversation? get activeConversation {
    if (_activeConversationId == null) return null;
    return _conversations.where((c) => c.id == _activeConversationId).cast<Conversation?>().firstOrNull;
  }

  /// 切换对话时也要打断正在生成的回复，否则会串台写到新对话里
  void selectConversation(String id) {
    if (_activeConversationId == id) return;
    _cancelStream();
    _activeConversationId = id;
    _markRead(id);
    notifyListeners();
  }

  /// 打开对话 = 已读：清掉这条对话的未读计数（侧栏小红点）
  void _markRead(String? convId) {
    if (convId == null) return;
    final i = _conversations.indexWhere((c) => c.id == convId);
    if (i == -1) return;
    if (_conversations[i].unread == 0) return;
    _conversations[i] = _conversations[i].copyWith(unread: 0);
    _saveConversations();
    // 已读后把标题栏的「有人找你」标记撤掉
    if (totalUnread == 0) notify.setDocumentTitle('似你');
  }

  /// 当前对话被查看时（ChatView 每次重建都会调）也顺手清未读，
  /// 覆盖"主动搭话恰好写进你正在看的这条对话"的情况。
  void markActiveConversationRead() {
    final before = activeConversation?.unread ?? 0;
    if (before == 0) return;
    _markRead(_activeConversationId);
    notifyListeners();
  }

  void newConversation({
    String? firstMessage,
    List<MessageAttachment> attachments = const [],
    Message? quote,
  }) {
    _cancelStream();
    final now = DateTime.now();
    final id = 'c_${now.microsecondsSinceEpoch}';
    final title = (firstMessage ?? '新对话').trim();
    final label = title.isEmpty
        ? (attachments.isEmpty ? '新对话' : attachments.first.name)
        : title;
    final displayTitle =
        label.length > 24 ? '${label.substring(0, 24)}…' : label;
    final c = Conversation(
      id: id,
      title: displayTitle,
      updatedAt: now,
      personaId: _activePersonaId,
    );
    _conversations.add(c);
    _activeConversationId = id;
    if (firstMessage != null && firstMessage.trim().isNotEmpty || attachments.isNotEmpty) {
      _appendUserMessage((firstMessage ?? '').trim(),
          attachments: attachments, quote: quote);
    }
    notifyListeners();
  }

  void renameConversation(String id, String title) {
    final i = _conversations.indexWhere((c) => c.id == id);
    if (i == -1) return;
    _conversations[i] = _conversations[i].copyWith(title: title);
    _saveConversations();
    notifyListeners();
  }

  void deleteConversation(String id) {
    _cancelStream();
    _conversations.removeWhere((c) => c.id == id);
    if (_activeConversationId == id) _activeConversationId = null;
    _saveConversations();
    notifyListeners();
  }

  // ---- 模型配置（供应商 + Key + 模型 ID，可多个） ----
  final List<ModelConfig> _modelConfigs = [];
  List<ModelConfig> get modelConfigs => List.unmodifiable(_modelConfigs);
  ModelConfig? get defaultModelConfig =>
      _modelConfigs
          .where((m) => m.isDefault && !m.isImage)
          .cast<ModelConfig?>()
          .firstOrNull ??
      _modelConfigs.where((m) => !m.isImage).cast<ModelConfig?>().firstOrNull ??
      (_modelConfigs.isEmpty ? null : _modelConfigs.first);

  /// 默认「图片生成」模型（kind=image）。没配就返回 null，此时画图请求回落到普通对话。
  ModelConfig? get defaultImageConfig => _modelConfigs
      .where((m) => m.isImage)
      .cast<ModelConfig?>()
      .firstOrNull;

  Future<void> addModelConfig(ModelConfig c) async {
    // 第一个自动设为默认
    _modelConfigs.add(_modelConfigs.isEmpty ? c.copyWith(isDefault: true) : c);
    await _saveModelConfigs();
    notifyListeners();
  }

  Future<void> updateModelConfig(ModelConfig c) async {
    final i = _modelConfigs.indexWhere((m) => m.id == c.id);
    if (i == -1) return;
    _modelConfigs[i] = c;
    await _saveModelConfigs();
    notifyListeners();
  }

  Future<void> deleteModelConfig(String id) async {
    _modelConfigs.removeWhere((m) => m.id == id);
    // 删掉的是默认 → 把默认交给第一个
    if (_modelConfigs.isNotEmpty && !_modelConfigs.any((m) => m.isDefault)) {
      _modelConfigs[0] = _modelConfigs[0].copyWith(isDefault: true);
    }
    await _saveModelConfigs();
    notifyListeners();
  }

  Future<void> setDefaultModelConfig(String id) async {
    for (var i = 0; i < _modelConfigs.length; i++) {
      _modelConfigs[i] = _modelConfigs[i].copyWith(isDefault: _modelConfigs[i].id == id);
    }
    await _saveModelConfigs();
    notifyListeners();
  }

  // ---- 本地账号（纯前端演示） ----
  final List<UserAccount> _accounts = [];
  UserAccount? _currentUser;
  UserAccount? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// 注册：返回错误信息，null 表示成功
  Future<String?> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final mail = email.trim().toLowerCase();
    if (name.trim().isEmpty) return '请填写昵称';
    if (!_looksLikeEmail(mail)) return '邮箱格式不正确';
    if (password.length < 6) return '密码至少 6 位';
    if (_accounts.any((a) => a.email == mail)) return '该邮箱已注册';
    final acc = UserAccount(
      id: 'u_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      email: mail,
      password: password,
      createdAt: DateTime.now(),
    );
    _accounts.add(acc);
    _currentUser = acc;
    await _saveAccounts();
    notifyListeners();
    return null;
  }

  /// 登录：返回错误信息，null 表示成功
  Future<String?> login({required String email, required String password}) async {
    final mail = email.trim().toLowerCase();
    final found = _accounts.where((a) => a.email == mail).cast<UserAccount?>().firstOrNull;
    if (found == null) return '该邮箱还没有注册';
    if (found.password != password) return '密码不正确';
    _currentUser = found;
    await _saveAccounts();
    notifyListeners();
    return null;
  }

  Future<void> logout() async {
    _currentUser = null;
    await _saveAccounts();
    notifyListeners();
  }

  static bool _looksLikeEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);

  // ---- 本地持久化 ----
  static const _kModels = 'sini_model_configs';
  static const _kAccounts = 'sini_accounts';
  static const _kCurrentUser = 'sini_current_user';
  static const _kGuideSkipped = 'sini_guide_skipped';
  static const _kPersonas = 'sini_personas';
  static const _kModeId = 'sini_mode_id';
  static const _kConversations = 'sini_conversations';
  static const _kProactiveChat = 'sini_proactive_chat';
  static const _kSystemNotify = 'sini_system_notify';
  static const _kSearch = 'sini_search_config';
  static const _kAffinity = 'sini_affinity';
  static const _kConnectors = 'sini_connectors';
  static const _kAutomations = 'sini_automations';
  static const _kUsage = 'sini_usage_events';
  static const _kConnectorServer = 'connector_server_base';

  /// 整库备份用到的全部本地键
  static const List<String> _kBackupKeys = [
    _kModels,
    _kAccounts,
    _kCurrentUser,
    _kGuideSkipped,
    _kPersonas,
    _kModeId,
    _kConversations,
    _kProactiveChat,
    _kSystemNotify,
    _kSearch,
    _kAffinity,
    _kConnectors,
    _kAutomations,
    _kUsage,
    _kConnectorServer,
  ];

  /// 导出整库备份 JSON 字符串（人格 / 对话 / 记忆 / 模型 / 连接器 / 用量等）。
  Future<String> exportBackupJson() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      'app': 'sini',
      'kind': 'sini_backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'stats': {
        'personaCount': _personas.length,
        'conversationCount': _conversations.length,
        'modelCount': _modelConfigs.length,
      },
      'prefs': <String, dynamic>{
        for (final k in _kBackupKeys)
          if (prefs.get(k) != null) k: prefs.get(k),
      },
    };
    return jsonEncode(data);
  }

  /// 从备份 JSON 恢复整库。返回 null 表示成功，否则是用户可读错误。
  Future<String?> importBackupJson(String raw) async {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return '备份文件不是合法 JSON';
    }
    if (decoded is! Map<String, dynamic>) return '备份格式不对';
    if (decoded['kind'] != 'sini_backup' && decoded['app'] != 'sini') {
      return '这不是「似你」的整库备份';
    }
    final prefsMap = decoded['prefs'];
    if (prefsMap is! Map) return '备份里没有数据内容';

    final prefs = await SharedPreferences.getInstance();
    // 先清掉备份清单里的键，避免「新旧混在一起」
    for (final k in _kBackupKeys) {
      await prefs.remove(k);
    }
    prefsMap.forEach((key, value) {
      final k = key.toString();
      if (!_kBackupKeys.contains(k)) return;
      if (value is String) prefs.setString(k, value);
      else if (value is bool) prefs.setBool(k, value);
      else if (value is int) prefs.setInt(k, value);
      else if (value is double) prefs.setDouble(k, value);
      else if (value != null) prefs.setString(k, jsonEncode(value));
    });

    // 重读内存态
    _personas.clear();
    _conversations.clear();
    _modelConfigs.clear();
    _accounts.clear();
    _automations.clear();
    _todos.clear();
    _moments.clear();
    _weeklyStories.clear();
    _affinity.clear();
    _activePersonaId = null;
    _currentUser = null;
    await restore();
    try {
      await UsageStore.instance.reload();
    } catch (_) {}
    return null;
  }

  /// App 启动时调用：把本机保存的模型配置 / 账号读回来
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();

    final rawModels = prefs.getString(_kModels);
    if (rawModels != null && rawModels.isNotEmpty) {
      try {
        final list = jsonDecode(rawModels);
        if (list is List) {
          _modelConfigs
            ..clear()
            ..addAll(list
                .whereType<Map<String, dynamic>>()
                .map(ModelConfig.fromJson));
        }
      } catch (_) {}
    }

    final rawAccounts = prefs.getString(_kAccounts);
    if (rawAccounts != null && rawAccounts.isNotEmpty) {
      try {
        final list = jsonDecode(rawAccounts);
        if (list is List) {
          _accounts
            ..clear()
            ..addAll(list.whereType<Map<String, dynamic>>().map(UserAccount.fromJson));
        }
      } catch (_) {}
    }

    final uid = prefs.getString(_kCurrentUser);
    if (uid != null) {
      _currentUser =
          _accounts.where((a) => a.id == uid).cast<UserAccount?>().firstOrNull;
    }

    _guideSkipped = prefs.getBool(_kGuideSkipped) ?? false;

    // 恢复「人格版本 / 表达模式」选择
    final mode = prefs.getString(_kModeId);
    if (mode != null &&
        _models.any((m) => m.id == mode)) {
      _activeModelId = mode;
    }

    // 恢复自动化任务
    final rawAuto = prefs.getString(_kAutomations);
    if (rawAuto != null && rawAuto.isNotEmpty) {
      try {
        final j = jsonDecode(rawAuto);
        if (j is List) {
          _automations
            ..clear()
            ..addAll(j
                .whereType<Map<String, dynamic>>()
                .map(AutomationTask.fromJson));
        }
      } catch (_) {}
    }

    // 恢复待办确认
    final rawTodos = prefs.getString(_kTodos);
    if (rawTodos != null && rawTodos.isNotEmpty) {
      try {
        final j = jsonDecode(rawTodos);
        if (j is List) {
          _todos
            ..clear()
            ..addAll(j.whereType<Map<String, dynamic>>().map(TodoFollowUp.fromJson));
        }
      } catch (_) {}
    }

    // 恢复回忆册
    final rawMoments = prefs.getString(_kMoments);
    if (rawMoments != null && rawMoments.isNotEmpty) {
      try {
        final j = jsonDecode(rawMoments);
        if (j is List) {
          _moments
            ..clear()
            ..addAll(j.whereType<Map<String, dynamic>>().map(MemoryMoment.fromJson));
        }
      } catch (_) {}
    }

    // 恢复每周故事
    final rawStories = prefs.getString(_kWeeklyStories);
    if (rawStories != null && rawStories.isNotEmpty) {
      try {
        final j = jsonDecode(rawStories);
        if (j is List) {
          _weeklyStories
            ..clear()
            ..addAll(j.whereType<Map<String, dynamic>>().map(WeeklyStory.fromJson));
        }
      } catch (_) {}
    }

    // 恢复连接器
    final rawConn = prefs.getString(_kConnectors);
    if (rawConn != null && rawConn.isNotEmpty) {
      try {
        final j = jsonDecode(rawConn);
        if (j is Map<String, dynamic>) {
          _emailEnabled = j['emailEnabled'] as bool? ?? false;
          _emailAddress = j['email'] as String? ?? '';
          _githubToken = j['ghToken'] as String? ?? '';
          _githubLogin = j['ghLogin'] as String? ?? '';
        }
      } catch (_) {}
    }

    // 恢复亲密度 / 情绪状态
    final rawAffinity = prefs.getString(_kAffinity);
    if (rawAffinity != null && rawAffinity.isNotEmpty) {
      try {
        final j = jsonDecode(rawAffinity);
        if (j is Map<String, dynamic>) {
          j.forEach((k, v) {
            if (v is Map<String, dynamic>) _affinity[k] = AffinityState.fromJson(v);
          });
        }
      } catch (_) {}
    }

    // 恢复搜索配置
    final rawSearch = prefs.getString(_kSearch);
    if (rawSearch != null && rawSearch.isNotEmpty) {
      try {
        final j = jsonDecode(rawSearch);
        if (j is Map<String, dynamic>) {
          _searchProvider = j['provider'] as String? ?? _searchProvider;
          _searchKey = j['key'] as String? ?? '';
        }
      } catch (_) {}
    }

    // 恢复人格（含跨对话长期记忆）
    final rawPersonas = prefs.getString(_kPersonas);
    if (rawPersonas != null && rawPersonas.isNotEmpty) {
      try {
        final list = jsonDecode(rawPersonas);
        if (list is List) {
          _personas = list
              .whereType<Map<String, dynamic>>()
              .map(Persona.fromJson)
              .toList();
        }
      } catch (_) {}
    }

    // 恢复对话（含每条消息的点赞 / 点踩反馈）
    final rawConv = prefs.getString(_kConversations);
    if (rawConv != null && rawConv.isNotEmpty) {
      try {
        final list = jsonDecode(rawConv);
        if (list is List) {
          _conversations
            ..clear()
            ..addAll(list
                .whereType<Map<String, dynamic>>()
                .map(Conversation.fromJson));
        }
      } catch (_) {}
    }

    // 恢复「主动搭话」开关：开着就重新启动心跳
    _proactiveChatEnabled = prefs.getBool(_kProactiveChat) ?? false;
    if (_proactiveChatEnabled) _startProactiveTimer();
    _nightGuardEnabled = prefs.getBool('sini_night_guard') ?? true;
    _nightGuardNight = prefs.getString('sini_night_guard_last');
    _personaBgEnabled = prefs.getBool('sini_persona_bg') ?? true;
    // 恢复「系统通知」开关：只有浏览器权限还在 granted 时才算真的开着
    _systemNotifyEnabled =
        (prefs.getBool(_kSystemNotify) ?? false) && systemNotifyGranted;

    // 重载后「当前人格」是空的（_activePersonaId 不落库）——默认选中第一个，
    // 否则界面会停在「空状态 + 没有聊天对象」，连语音通话都会提示
    // 「还没有选中的人格」。main.dart 里那次 selectPersona 跑在 restore 之前，
    // 那时人格还没读出来，所以兜底必须放在这里。
    if (_activePersonaId == null && _personas.isNotEmpty) {
      selectPersona(_personas.first.id);
    }

    notifyListeners();
    _startAutomationTimer();
  }

  Future<void> _saveModelConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kModels,
      jsonEncode(_modelConfigs.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> _saveAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kAccounts,
      jsonEncode(_accounts.map((a) => a.toJson()).toList()),
    );
    if (_currentUser == null) {
      await prefs.remove(_kCurrentUser);
    } else {
      await prefs.setString(_kCurrentUser, _currentUser!.id);
    }
  }

  /// 对话（含每条消息的反馈）落盘。被所有修改对话的方法调用，保证刷新不丢。
  Future<void> _saveConversations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kConversations,
      jsonEncode(_conversations.map((c) => c.toJson()).toList()),
    );
  }

  // ---- 主动搭话：调度与决策 ----
  //
  // 机制（为什么这样设计）：
  //  1) 心跳每 60 秒一次（[_proactiveTick]），但**每次心跳都不会说话**——
  //     它只是给一次"机会"。真正的开口由 LLM 按人格判断，且必须同时满足
  //     下面一堆真实世界的约束（静默时段 / 距上次说话的间隔 / 距上次主动的间隔 /
  //     你正在聊 / 没配模型 …）。
  //  2) 约束不够时直接跳过，连模型都不调（省钱也省电）。
  //  3) 通过约束后交给 proactive_engine 判断"此刻我会不会想找 TA"，说就说，
  //     不说就静默地等下一次心跳。所以用户感受是"时不时来一句"，而非定时播报。

  /// 心跳计数（每 60s +1）。用于"随机性"：不是每跳都问模型，
  /// 而是按人格主动性算出概率，避免机械感。
  int _proactiveTick = 0;

  /// 是否正在跑一次主动搭话判断（防止心跳叠加并发请求）
  bool _proactiveBusy = false;

  void _startProactiveTimer() {
    _proactiveTimer?.cancel();
    // 刚打开开关时先不判断，给用户一个"安静期"，避免一开就来消息
    _proactiveTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _proactiveHeartbeat());
  }

  void _stopProactiveTimer() {
    _proactiveTimer?.cancel();
    _proactiveTimer = null;
  }

  /// 心跳：只负责"要不要给一次机会"，不负责说话
  void _proactiveHeartbeat() async {
    _proactiveTick++;
    if (!_proactiveChatEnabled) return;
    if (_proactiveBusy) return;

    // 刚打开开关的前 30 分钟不打扰（安静期），让用户感觉"打开也不会立刻响"
    if (_proactiveTick < 30) return;

    final persona = activePersona;
    if (persona == null) return;
    // 兜底「默认助手」没设定人格：不主动搭话（否则会像机器人推送）
    if (persona.locked && !persona.isConfigured) return;
    if (defaultModelConfig == null) return;

    final now = DateTime.now();
    // 深夜/凌晨绝对不打扰（硬约束）
    if (isQuietHour(now)) return;

    final conv = activeConversation;
    // 没有对话 → 用这个人格最近一次对话；连对话都没有就跳过
    final target = conv ?? _latestConversationOf(persona.id);
    if (target == null) return;

    final lastMsgAt = target.messages.isEmpty
        ? null
        : target.messages.last.createdAt;
    final gap = lastMsgAt == null ? null : now.difference(lastMsgAt);

    // 用户刚说完话（< 10 分钟）就别急着插话，像是在等 TA 回
    if (gap != null && gap.inMinutes < 10) return;

    // 距上次 TA 主动搭话太近则跳过（按人格主动性算出的最小间隔）
    if (target.lastProactiveAt != null) {
      final sinceProactive = now.difference(target.lastProactiveAt!);
      if (sinceProactive < minGapFor(persona)) return;
    }

    // 正在生成回复 / 正在被用户输入：不打扰
    if (activeConversation?.messages.isNotEmpty == true &&
        activeConversation!.messages.last.streaming) {
      return;
    }

    // 随机性：主动性越高，每次心跳真正进入"判断"的概率越高。
    // 0.0 → 约 4%，1.0 → 约 30%。避免每跳都调用模型（机械且浪费）。
    final p = (0.04 + persona.initiative.clamp(0.0, 1.0) * 0.26);
    if (_random.nextDouble() > p) return;

    await _maybeProactiveSpeak(persona, target, gap, now);
  }

  /// 真正去问模型「此刻要不要开口、说什么」，若决定开口就写入消息
  Future<void> _maybeProactiveSpeak(
    Persona persona,
    Conversation target,
    Duration? gap,
    DateTime now,
  ) async {
    final cfg = defaultModelConfig;
    if (cfg == null) return;
    _proactiveBusy = true;
    try {
      final memories = persona.memory;
      final facts = memories
          .where((m) => m.kind == PersonaMemoryKind.fact)
          .toList()
        ..sort((a, b) => b.hits.compareTo(a.hits));
      final avoids =
          memories.where((m) => m.kind == PersonaMemoryKind.avoid).toList();

      final messages = buildProactivePrompt(
        persona: persona,
        personaDirective: buildPersonaDirective(persona),
        memoryLines: facts.map((m) => m.text).take(12).toList(),
        avoidLines: avoids.map((m) => m.text).toList(),
        recentTranscript: _recentTranscript(target),
        gapSinceLast: gap,
        lastProactive: target.lastProactiveAt == null
            ? null
            : now.difference(target.lastProactiveAt!),
        now: now,
      );

      final res = await chatComplete(
        cfg: cfg,
        messages: messages,
        temperature: 0.95, // 搭话要有人味，温度偏高一档
        maxTokens: 400,
      );
      if (!res.ok || res.content == null) return;
      final decision = parseProactiveDecision(res.content!);
      if (!decision.speak || decision.messages.isEmpty) return;

      // 二次校验：把模型的回复也过一遍（模型有可能忽略作息/避免项）
      final safe = decision.messages
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .where((s) => !_hitsAvoid(s, avoids))
          .toList();
      if (safe.isEmpty) return;

      // 若 TA 说想发图，且配了图片模型 → 生成一张挂上；失败则只发文字
      MessageAttachment? shareImage;
      final imgCfg = defaultImageConfig;
      if (decision.imagePrompt != null &&
          decision.imagePrompt!.isNotEmpty &&
          imgCfg != null) {
        try {
          final r = await generateImage(
            cfg: imgCfg,
            prompt: decision.imagePrompt!,
            size: guessImageSize(decision.imagePrompt!),
          );
          if (r.hasUrl || r.hasB64) {
            List<int>? bytes;
            String? url = r.url;
            if (!r.hasUrl && r.hasB64) {
              final raw = r.b64!;
              final comma = raw.indexOf(',');
              try {
                bytes =
                    base64Decode(comma >= 0 ? raw.substring(comma + 1) : raw);
              } catch (_) {
                bytes = null;
              }
            }
            if (url != null || bytes != null) {
              shareImage = MessageAttachment(
                name: '分享_${now.millisecondsSinceEpoch}.png',
                sizeBytes: bytes?.length ?? 0,
                kind: MessageAttachmentKind.image,
                bytes: bytes,
                url: url,
                prompt: decision.imagePrompt,
              );
            }
          }
        } catch (_) {
          // 图失败不影响文字
        }
      }

      _appendProactiveMessages(target.id, safe, firstAttachment: shareImage);
    } catch (_) {
      // 主动搭话失败要绝对静默：不能因为后台请求报错就打扰用户
    } finally {
      _proactiveBusy = false;
    }
  }

  /// 简单兜底：若模型的搭话内容直接命中了用户要求避免的关键词，就丢弃这句话
  bool _hitsAvoid(String text, List<PersonaMemory> avoids) {
    final t = text.toLowerCase();
    for (final a in avoids) {
      final kw = a.text.trim().toLowerCase();
      if (kw.isEmpty) continue;
      // 避免项通常写成一整句，这里用"关键词较长时取核心片段"的粗暴包含判断
      if (kw.length >= 2 && t.contains(kw)) return true;
    }
    return false;
  }

  /// 取最近若干轮的对话文本（给搭话做上下文），并标注是用户说的还是 TA 说的
  String _recentTranscript(Conversation conv) {
    final msgs = conv.messages.where((m) => m.content.trim().isNotEmpty).toList();
    if (msgs.isEmpty) {
      if (conv.earlySummary != null && conv.earlySummary!.isNotEmpty) {
        return '（更早的要点）${conv.earlySummary}';
      }
      return '';
    }
    final recent = msgs.length > 12 ? msgs.sublist(msgs.length - 12) : msgs;
    final sb = StringBuffer();
    if (conv.earlySummary != null && conv.earlySummary!.isNotEmpty) {
      sb.write('（更早的要点）${conv.earlySummary}\n');
    }
    for (final m in recent) {
      final c = m.content.trim();
      if (c.isEmpty) continue;
      sb.write('${m.isUser ? "用户" : "TA"}：$c\n');
    }
    return sb.toString();
  }

  Conversation? _latestConversationOf(String personaId) {
    final own = _conversations.where((c) => c.personaId == personaId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return own.isEmpty ? null : own.first;
  }

  /// 把 TA 主动发来的消息写入对话（可能连发 1~2 条），并点亮未读红点
  /// [firstAttachment] 若不为 null，挂在第一条主动消息上（TA 顺手发的图）
  void _appendProactiveMessages(
    String convId,
    List<String> texts, {
    MessageAttachment? firstAttachment,
  }) {
    final ci = _conversations.indexWhere((c) => c.id == convId);
    if (ci == -1) return;
    final conv = _conversations[ci];
    final now = DateTime.now();
    final added = <Message>[];
    for (var i = 0; i < texts.length; i++) {
      added.add(Message(
        id: 'm_${now.microsecondsSinceEpoch}_p$i',
        content: texts[i],
        isUser: false,
        createdAt: now,
        proactive: true,
        attachments: (i == 0 && firstAttachment != null)
            ? [firstAttachment]
            : const [],
      ));
    }
    // 用户正在看这条对话 → 直接算已读，不亮红点
    final isOpen = _activeConversationId == convId;
    _conversations[ci] = conv.copyWith(
      messages: [...conv.messages, ...added],
      updatedAt: now,
      lastProactiveAt: now,
      unread: isOpen ? 0 : conv.unread + texts.length,
    );
    _saveConversations();
    notifyListeners();

    // ── 系统级提醒：手机通知栏 / 息屏桌面弹窗 ──────────────────────
    // 只在用户**没在看这个页面**时才弹（他正盯着气泡看，再弹系统通知是噪音）。
    // 页面在后台时（切到别的标签页 / 最小化 / 息屏）才真正需要系统通知。
    if (!isOpen || !notify.pageVisible) {
      _pushSystemNotification(conv, texts);
    }
  }

  /// 弹系统通知 + 改标题栏，让用户在页面外也能第一时间知道 TA 来找他了
  void _pushSystemNotification(Conversation conv, List<String> texts) {
    final persona = personaById(conv.personaId) ?? activePersona;
    if (persona == null) return;
    final first = texts.first.trim();
    // 连发多条时正文用第一句，并标注"还有 N 条"
    final body = texts.length > 1 ? '$first（还有 ${texts.length - 1} 条）' : first;

    if (_systemNotifyEnabled && systemNotifyGranted) {
      notify.showSystemNotification(
        title: persona.name,
        body: body,
        // 按对话分组：同一条对话的多次搭话替换上一条，避免通知栏被刷屏；
        // 不同对话（不同人格）各留一条，方便区分是谁找你。
        tag: 'sini-proactive-${conv.id}',
        iconPath: 'icons/Icon-192.png',
      );
    }
    // 切到别的标签页时，浏览器标签标题也会显示有人找（浏览器最小化在任务栏也能看到）
    notify.setDocumentTitle('● ${persona.name} 来找你');
  }

  /// 当前所有对话的未读总数（侧栏 Logo 上可以挂角标）
  int get totalUnread =>
      _conversations.fold(0, (sum, c) => sum + c.unread);

  /// 某个人格名下未读总数（人格列表小红点）
  int unreadOf(String personaId) => _conversations
      .where((c) => c.personaId == personaId)
      .fold(0, (sum, c) => sum + c.unread);

  /// 手动触发一次主动搭话（人格实验室「让它来找我」按钮 / 方便演示与调试）
  /// 忽略随机性与最小间隔，但仍保留静默时段与模型可用性检查。
  Future<bool> triggerProactiveNow({bool ignoreQuietHour = true}) async {
    final persona = activePersona;
    if (persona == null) return false;
    if (defaultModelConfig == null) return false;
    if (persona.locked && !persona.isConfigured) return false;
    final now = DateTime.now();
    if (!ignoreQuietHour && isQuietHour(now)) return false;
    final target = activeConversation ?? _latestConversationOf(persona.id);
    if (target == null) return false;
    final lastMsgAt =
        target.messages.isEmpty ? null : target.messages.last.createdAt;
    await _maybeProactiveSpeak(
      persona,
      target,
      lastMsgAt == null ? null : now.difference(lastMsgAt),
      now,
    );
    return true;
  }

  static final _random = math.Random();

  // ---- 生成中的回复 ----
  /// 每次切换对话/人格/新建都 +1，正在跑的模拟流发现自己的代号过期就自动停手
  int _generation = 0;
  void _cancelStream() => _generation++;

  // ---- 临时调试条：在聊天界面顶部展示实际调用的模型与返回摘要 ----
  String? _debugBanner;
  String? get debugBanner => _debugBanner;
  void _setDebug(String? s) {
    _debugBanner = s;
    notifyListeners();
  }

  // ---- Messages ----
  void _appendUserMessage(
    String text, {
    List<MessageAttachment> attachments = const [],
    Message? quote,
  }) {
    if (_activeConversationId == null) return;
    final ci = _conversations.indexWhere((c) => c.id == _activeConversationId);
    if (ci == -1) return;
    final conv = _conversations[ci];
    final msg = Message(
      id: 'm_${DateTime.now().microsecondsSinceEpoch}',
      content: text,
      isUser: true,
      createdAt: DateTime.now(),
      attachments: attachments,
      // 引用存文本快照：被引用的消息之后被撤回 / 改掉，引用块也还在
      quoteId: quote?.id,
      quoteText: quote?.content,
      quoteIsUser: quote?.isUser ?? false,
    );
    final newMessages = [...conv.messages, msg];
    _conversations[ci] = conv.copyWith(
      messages: newMessages,
      updatedAt: DateTime.now(),
    );
    _saveConversations();
  }

  void _appendAssistantPlaceholder() {
    if (_activeConversationId == null) return;
    final ci = _conversations.indexWhere((c) => c.id == _activeConversationId);
    if (ci == -1) return;
    final conv = _conversations[ci];
    final msg = Message(
      id: 'm_${DateTime.now().microsecondsSinceEpoch}_a',
      content: '',
      isUser: false,
      createdAt: DateTime.now(),
      streaming: true,
    );
    final newMessages = [...conv.messages, msg];
    _conversations[ci] = conv.copyWith(
      messages: newMessages,
      updatedAt: DateTime.now(),
    );
    _saveConversations();
  }

  void _updateLastAssistant(String content) {
    if (_activeConversationId == null) return;
    final ci = _conversations.indexWhere((c) => c.id == _activeConversationId);
    if (ci == -1) return;
    final conv = _conversations[ci];
    final newMessages = [...conv.messages];
    if (newMessages.isEmpty) return;
    final last = newMessages.last;
    if (last.isUser) return;
    newMessages[newMessages.length - 1] = last.copyWith(content: content, streaming: false);
    _conversations[ci] = conv.copyWith(messages: newMessages, updatedAt: DateTime.now());
    _saveConversations();
  }

  /// 给最后一条助手消息挂上附件（AI 生成的图片用它挂上去）
  void _attachToLastAssistant(MessageAttachment a) {
    if (_activeConversationId == null) return;
    final ci = _conversations.indexWhere((c) => c.id == _activeConversationId);
    if (ci == -1) return;
    final conv = _conversations[ci];
    final newMessages = [...conv.messages];
    if (newMessages.isEmpty) return;
    final last = newMessages.last;
    if (last.isUser) return;
    newMessages[newMessages.length - 1] = last.copyWith(
      attachments: [...last.attachments, a],
    );
    _conversations[ci] = conv.copyWith(messages: newMessages);
    _saveConversations();
  }

  /// 写入用户对某条 AI 回复的反馈（好 / 不好 + 原因）。持久化到对话，刷新不丢。
  void setMessageFeedback(
    String convId,
    String msgId,
    MessageFeedback feedback, {
    String? reason,
  }) {
    final ci = _conversations.indexWhere((c) => c.id == convId);
    if (ci == -1) return;
    final conv = _conversations[ci];
    final newMessages = conv.messages.map((m) {
      if (m.id != msgId) return m;
      final newFb = m.feedback == feedback ? MessageFeedback.none : feedback;
      return m.copyWith(
        feedback: newFb,
        // 取消点踩或换新反馈时清掉旧原因；仅在确实点踩且给了原因时保留
        feedbackReason: newFb == MessageFeedback.dislike ? reason : null,
      );
    }).toList();
    _conversations[ci] = conv.copyWith(messages: newMessages, updatedAt: DateTime.now());
    _saveConversations();
    notifyListeners();
  }

  // ---- 撤回 / 编辑重发（真人感细节：发错话可以改） ----

  /// 撤回自己的一条消息：连同它引出的 TA 回复一起拿掉，回到「这句话还没说」的状态。
  /// 返回被撤回的原文（UI 可以用来提示），失败（找不到 / 不是自己的消息）返回 null。
  String? recallMessage(String convId, String msgId) {
    final ci = _conversations.indexWhere((c) => c.id == convId);
    if (ci == -1) return null;
    final conv = _conversations[ci];
    final idx = userMessageIndex(conv.messages, msgId);
    if (idx == -1) return null;
    final oldText = conv.messages[idx].content;
    final next = cutTurn(conv.messages, idx);
    // 撤回时如果 TA 正在生成这条的回复，必须打断，否则它还会把回复写回来
    _cancelStream();
    _conversations[ci] = conv.copyWith(
      messages: next,
      title: titleAfterEdit(conv.title, oldText, next),
      updatedAt: DateTime.now(),
    );
    _saveConversations();
    notifyListeners();
    return oldText;
  }

  /// 编辑重发：把自己那条消息改成 [newText]，收回 TA 原来的回复，再按新说法重新问一遍。
  /// 返回是否真的发出去了（文本为空 / 找不到消息时为 false）。
  bool editAndResend(String convId, String msgId, String newText) {
    final t = newText.trim();
    if (t.isEmpty) return false;
    final ci = _conversations.indexWhere((c) => c.id == convId);
    if (ci == -1) return false;
    final conv = _conversations[ci];
    final idx = userMessageIndex(conv.messages, msgId);
    if (idx == -1) return false;
    final oldText = conv.messages[idx].content;
    final next = replaceTurn(conv.messages, idx, t);
    _cancelStream();
    _conversations[ci] = conv.copyWith(
      messages: next,
      title: titleAfterEdit(conv.title, oldText, next),
      updatedAt: DateTime.now(),
    );
    _saveConversations();
    // 重发要落在「当前打开的对话」上：_appendAssistantPlaceholder / _runAssistant
    // 都是按 _activeConversationId 走的，不是当前对话就切过去，免得回复写进别的对话。
    if (convId != _activeConversationId) _activeConversationId = convId;
    // 重走一遍「发消息」的副作用，让 TA 按新说法重新理解。
    // 注：亲密度会为这句话再记一次（旧的那次不撤销），换来的是心情/信号跟着新文本走，
    // 这个取舍对「改完让 TA 重新理解」的体验更重要。
    _updateRoleplayFlag(t);
    final pid = activePersona?.id;
    if (pid != null) updateAffinityOnUserMessage(pid, t);
    notifyListeners();
    _appendAssistantPlaceholder();
    notifyListeners();
    _runAssistant();
    return true;
  }

  // ---- 引用回复 ----

  /// 当前「待引用」的那条消息：用户在菜单里点了「引用回复」后落在这里，
  /// 输入框上方显示引用条，发送时随这条消息一起记下，然后清空。
  Message? _pendingQuote;
  Message? get pendingQuote => _pendingQuote;

  void setPendingQuote(Message m) {
    _pendingQuote = m;
    notifyListeners();
  }

  void clearPendingQuote() {
    if (_pendingQuote == null) return;
    _pendingQuote = null;
    notifyListeners();
  }

  /// 撤回 / 编辑前给 UI 用的提示信息：这条消息之后还有多少条会一起被收回。
  int messagesAfterMessage(String convId, String msgId) {
    final ci = _conversations.indexWhere((c) => c.id == convId);
    if (ci == -1) return 0;
    final idx = userMessageIndex(_conversations[ci].messages, msgId);
    if (idx == -1) return 0;
    return messagesAfterTurn(_conversations[ci].messages, idx);
  }

  /// 模拟流式回复：分多次 append，最终 stream 关闭。
  void sendUserMessage(
    String text, {
    List<MessageAttachment> attachments = const [],
  }) {
    final t = text.trim();
    if (t.isEmpty && attachments.isEmpty) return;
    // 引用随这条消息一起发出，随即清掉引用态（输入框上的引用条跟着消失）
    final quote = _pendingQuote;
    if (quote != null) _pendingQuote = null;
    if (_activeConversationId == null) {
      newConversation(firstMessage: t, attachments: attachments, quote: quote);
    } else {
      _appendUserMessage(t, attachments: attachments, quote: quote);
      // 如果当前对话还没消息，把标题改为首条文本（只有附件则用附件名）
      final ci = _conversations.indexWhere((c) => c.id == _activeConversationId);
      if (ci != -1 && _conversations[ci].title == '新对话') {
        final label = t.isNotEmpty
            ? t
            : (attachments.isEmpty ? '新对话' : attachments.first.name);
        _conversations[ci] =
            _conversations[ci].copyWith(title: shortConversationTitle(label));
        _saveConversations();
      }
    }
    // 角色扮演开关：TA 说「一起角色扮演吧」这条对话进入扮演模式；说「不演了」退出。
    // 开关在 _buildPrompt 之前落位，所以这一句得到的就是已经入戏的回复。
    _updateRoleplayFlag(t);
    // 恋爱感引擎：恋爱信号 + TA 的心情，同样要在构建 prompt 前落位
    if (activePersona != null && t.isNotEmpty) {
      updateAffinityOnUserMessage(activePersona!.id, t);
      _trackTodoFromUserText(activePersona!.id, t);
    }
    notifyListeners();

    // 如果上一轮还没回完（用户快速连发），先打断它，避免两条 _runAssistant 串台
    _cancelStream();
    // 真实调用默认模型生成回复
    _appendAssistantPlaceholder();
    // 写信卡片：用户要求发邮件且已绑定邮箱 → 进入明信片流程，不走红聊回复
    final composing = _maybeStartEmailCompose(t);
    notifyListeners();
    if (!composing) {
      _runAssistant();
    }
  }

  /// 用户请求角色扮演 → 本对话开启扮演模式；说不演了 → 关闭。
  /// 一条消息里同时出现开和关的说法时按退出算（宁可少开，不可不退）。
  void _updateRoleplayFlag(String text) {
    final id = _activeConversationId;
    if (id == null) return;
    if (!roleplayStartRequested(text) && !roleplayStopRequested(text)) return;
    final i = _conversations.indexWhere((c) => c.id == id);
    if (i == -1) return;
    final next = !roleplayStopRequested(text);
    if (_conversations[i].roleplay == next) return;
    _conversations[i] = _conversations[i].copyWith(roleplay: next);
    _saveConversations();
  }

  /// 调默认模型，拿到完整回复后用打字机展示；无模型 / 出错则在气泡内提示。
  void _runAssistant() async {
    _tagUsagePersona();
    final myGen = ++_generation;
    final cfg = defaultModelConfig;
    if (cfg == null) {
      _setDebug('⚠️ 未配置默认模型\n请到「设置 → 模型管理」添加一个模型并设为默认');
      _finishError(
        '还没有可用的模型。请先到「设置 → 模型管理」添加一个模型并设为默认。',
        myGen,
      );
      return;
    }
    _setDebug('准备调用 →\n供应商:${cfg.providerId}  模型:${cfg.modelId}\nBaseURL:${cfg.baseUrl}\nKey:${cfg.maskedKey}\n（发一条消息触发）');
    final conv = activeConversation;
    if (conv == null) return;
    // 长对话逼近上限时先压缩早期历史（写入 earlySummary，最近若干轮保留原文）
    await _maybeCompact(conv);
    final live = activeConversation;
    if (live == null) return;
    final messages = _buildPrompt(live);
    // content 可能是 String 或多模态 List，不能硬 as String
    Object? _lastUserRaw;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i]['role'] == 'user') {
        _lastUserRaw = messages[i]['content'];
        break;
      }
    }
    final lastUser = _lastUserRaw is String
        ? _lastUserRaw
        : (_lastUserRaw is List
            ? _lastUserRaw
                .where((p) => p is Map && p['type'] == 'text')
                .map((p) => (p['text'] ?? '').toString())
                .join('\n')
            : '(无)');
    print('[sini:req] provider=${cfg.providerId} model=${cfg.modelId} '
        'baseUrl=${cfg.baseUrl} turns=${messages.length}');
    print('[sini:req] lastUser=$lastUser');

    // 画图意图：先用图片模型生成图挂到这条回复上，再让对话模型用人设口吻描述它
    final imgCfg = defaultImageConfig;
    if (imgCfg != null && isImageRequest(lastUser)) {
      await _runImageFlow(
        cfg: cfg,
        imgCfg: imgCfg,
        conv: live,
        userText: lastUser,
        myGen: myGen,
      );
      return;
    }

    // 联网搜索：TA 问了实时性话题或明确要搜时，先搜真实结果再让 TA 总结
    if (searchReady && needsWebSearch(lastUser)) {
      final q = cleanSearchQuery(lastUser);
      _setDebug('🔎 判断需要联网，搜索中：$q');
      final sr = await webSearch(
        query: q,
        provider: _searchProvider,
        apiKey: _searchKey,
      );
      if (myGen != _generation) return;
      if (sr.ok && sr.hits.isNotEmpty) {
        _setDebug('🔎 搜到 ${sr.hits.length} 条结果，正在让 TA 总结');
        final liveAfterSearch = activeConversation;
        if (liveAfterSearch != null) {
          final msgs = _buildPrompt(liveAfterSearch);
          // 把搜索结果**并进第一条 system**（人格设定里），比塞第二条 system 更不容易被忽略
          final ctx = formatSearchContext(q, sr.hits);
          final head = (msgs.first['content'] ?? '').toString();
          msgs[0] = {
            'role': 'system',
            'content': '$head\n\n$ctx',
          };
          final sres = await chatComplete(cfg: cfg, messages: msgs);
          if (myGen != _generation) return;
          if (sres.ok && sres.content != null && sres.content!.isNotEmpty) {
            print('[sini:search] hits=${sr.hits.length}');
            await _typeOut(sres.content!, myGen);
            if (myGen == _generation) _extractPersonaMemory(live.id, myGen);
            return;
          }
          _setDebug('搜索后续回答失败：${sres.error}，改走普通回答');
        }
      } else {
        _setDebug('搜索失败：${sr.error}，改走普通回答');
        // 搜索失败时不要让模型一本正经说「我断网了」——提示它如实说搜不到
        messages.insert(1, {
          'role': 'system',
          'content': '（系统：本轮联网搜索失败：${sr.error}。'
              '请以人格口吻说「网上没搜到/暂时搜不了」，'
              '**禁止**说「我是断网的」「我无法联网」「我看不到实时新闻」这种产品说明书腔。'
              '可以给用户几个自己会去看的资讯来源建议。）',
        });
      }
    }

    final res = await chatComplete(cfg: cfg, messages: messages);
    if (myGen != _generation) return; // 已切走 / 被取消，丢弃这次结果
    if (!res.ok) {
      print('[sini:err] ${res.error}');
      _setDebug('❌ 调用失败 [HTTP ${res.status ?? '?'}]\n错误:${res.error}\n\n供应商:${cfg.providerId}  模型:${cfg.modelId}\nBaseURL:${cfg.baseUrl}\nKey:${cfg.maskedKey}${res.status == 401 ? '\n\n→ 401 多为 API Key 无效/过期，请到「设置→模型管理」点「测试连接」核对' : ''}');
      _finishError('⚠️ 调用失败：${res.error}', myGen);
      return;
    }
    print('[sini:ok] len=${res.content!.length} head=${res.head}');
    _setDebug('✅ 调用成功 [HTTP ${res.status}]\n供应商:${cfg.providerId}  模型:${cfg.modelId}\nBaseURL:${cfg.baseUrl}\n返回前120字: ${res.head ?? ''}');
    // 连接器执行：TA 的回复里带 ```connector 调用块时，前端真实执行
    var reply = res.content!;
    final connResult = await _runConnectorCalls(reply, cfg, live, myGen,
        userText: lastUser);
    if (myGen != _generation) return;
    if (connResult == _kOpenComposeCard) {
      // 邮件请求已转为明信片卡片（挂在当前占位消息上），不打字机
      notifyListeners();
      return;
    }
    if (connResult != null) {
      reply = connResult;
    }
    await _typeOut(reply, myGen);
    if (myGen != _generation) return;
    // 输出因 max_tokens 被截断：补一句续写提示，方便用户要完整版
    if (res.finishReason == 'length') {
      final conv = activeConversation;
      if (conv != null && conv.messages.isNotEmpty) {
        final last = conv.messages.last;
        if (!last.isUser) {
          const note = '\n\n_（⚠️ 这段回复较长，已接近单次长度上限被截断。'
              '回复「继续」即可补全剩余部分。）_';
          _updateLastAssistant(last.content + note);
          notifyListeners();
        }
      }
    }
    // 回复完成后异步抽取「跨对话长期记忆」写入这个人格（不阻塞 UI，已用 myGen 防串台）
    if (myGen == _generation) _extractPersonaMemory(live.id, myGen);
    // 自动沉淀回忆（失败也静默）
    if (myGen == _generation && activePersona != null) {
      final finalReply = activeConversation?.messages
          .where((m) => !m.isUser && !m.streaming)
          .map((m) => m.content)
          .lastOrNull;
      if (finalReply != null && finalReply.isNotEmpty) {
        _maybeAutoMoment(activePersona!.id, lastUser, finalReply);
      }
    }
    // 深夜守护：聊完这一轮，若还在深夜且今晚没劝过，TA 再补一句劝睡
    if (myGen == _generation) {
      await _maybeDeepNightGuardian(lastUser);
    }
  }

  /// 画图流程：先调图片模型，成功把图片挂到当前回复上，再让对话模型用人设描述它。

  /// 执行 TA 回复里的连接器调用块，返回替换后的回复文本（无块返回 null）。
  /// - email：转为明信片卡片（用户确认后才寄出），返回打开卡片哨兵
  /// - github 查询：执行后把真实结果回喂给模型重答一轮
  /// 从调用块 JSON 创建自动化任务（含缺日期兜底）；失败返回 null
  AutomationTask? _createAutomationFromArgs(Map<String, dynamic> args) {
    if (activePersona == null) return null;
    final name = (args['name'] ?? '自动化').toString();
    final typeStr = (args['type'] ?? 'daily').toString();
    final daily = typeStr == 'daily';
    final timeHHmm = (args['time'] ?? '08:00').toString();
    final action = (args['action'] ?? 'message').toString();
    final prompt = (args['prompt'] ?? '').toString();
    if (prompt.isEmpty) return null;
    DateTime? onceAt;
    if (!daily) {
      final dateStr = (args['date'] ?? '').toString();
      onceAt = DateTime.tryParse('$dateStr ${timeHHmm}:00');
      if (onceAt == null && timeHHmm.contains(':')) {
        // 模型没给日期：按今天/明天的 HH:mm 兜底
        final tp = timeHHmm.split(':');
        final h = int.tryParse(tp[0]) ?? 0;
        final m = int.tryParse(tp.length > 1 ? tp[1] : '0') ?? 0;
        final n = DateTime.now();
        var cand = DateTime(n.year, n.month, n.day, h, m);
        if (!cand.isAfter(n)) cand = cand.add(const Duration(days: 1));
        onceAt = cand;
      }
      if (onceAt == null) {
        onceAt = DateTime.now().add(const Duration(minutes: 5));
      }
    }
    var task = AutomationTask(
      id: 'auto_${DateTime.now().microsecondsSinceEpoch}',
      personaId: activePersona!.id,
      name: name.length > 16 ? name.substring(0, 16) : name,
      daily: daily,
      timeHHmm: timeHHmm,
      onceAt: onceAt,
      action: action == 'email' && emailConnectorReady ? 'email' : 'message',
      prompt: prompt,
      enabled: true,
    );
    return task.copyWith(nextRunAt: task.computeNextRun());
  }

  static const _kOpenComposeCard = '__sini_open_compose_card__';

  Future<String?> _runConnectorCalls(
      String reply, ModelConfig cfg, Conversation conv, int myGen,
      {String userText = ''}) async {
    final blocks = findConnectorBlocks(reply);
    if (blocks.isEmpty) return null;
    var out = reply;
    Map<String, dynamic>? ghData;
    AutomationTask? hasNewAutomation;
    for (final b in blocks) {
      final call = ConnectorCall.tryParse(b.code);
      // 自动化识别：automation 围栏、type=automation、或长像自动化任务的 JSON
      final autoArgs = tryParseConnectorJson(b.code);
      final isAutomationFence = autoArgs != null &&
          (b.lang == 'automation' ||
              autoArgs['type'] == 'automation' ||
              (autoArgs['name'] != null &&
                  autoArgs['prompt'] != null &&
                  autoArgs['time'] != null));
      if (call == null && !isAutomationFence) continue;
      if (call == null || isAutomationFence) {
        final args = tryParseConnectorJson(b.code)!;
        final created = _createAutomationFromArgs(args);
        if (created == null) {
          out = out.replaceFirst(b.full, '_（⚠️ 自动化创建失败：'
              '${activePersona == null ? "请先选择一个人物" : "参数不完整/缺少日期"}）_');
          continue;
        }
        await addAutomation(created);
        hasNewAutomation = created;
      } else if (call.type == 'email') {
        if (!emailConnectorReady) continue;
        // 用户要的是"定时寄信"（X分钟后/每天…）：让模型改用 automation 块重来
        if (_hasScheduleIntent(userText)) {
          final msgs = _buildPrompt(conv);
          msgs.add({
            'role': 'system',
            'content': '你刚才输出了 email 连接器调用块，但用户要的是「定时」任务（不是现在立即发送）。'
                '请改用 automation 调用块重新输出，格式：三个反引号 automation 换行 '
                '{"name":"8字内短名","type":"daily或once","time":"HH:mm",'
                '"date":"type=once时按当前时间推算的YYYY-MM-DD",'
                '"action":"email","prompt":"到点后写这封邮件的具体指令"} 换行 三个反引号。'
                '只输出这一个块，不要其他文字。时间按当前时间推算。',
          });
          final res2 = await chatComplete(cfg: cfg, messages: msgs, temperature: 0.7);
          if (myGen == _generation && res2.ok) {
            for (final b2 in findConnectorBlocks(res2.content ?? '')) {
              final a2 = tryParseConnectorJson(b2.code);
              if (a2 == null) continue;
              final created = _createAutomationFromArgs(a2);
              if (created != null) {
                await addAutomation(created);
                return '_（⏰ 已改为定时任务：「' + created.name + '」 ' + created.scheduleLabel() + ' · 设置→自动化 可管理）_';
              }
            }
          }
          // 改造失败就落回普通路径：按即时邮件开卡片
        }
        // 不直接发！转成明信片卡片，内容已按 TA 的起草预填，用户确认后才寄出
        final blockTo = ((call.args['to'] ?? '') as String).trim();
        _cancelStream();
        _emailCompose = EmailCompose(
          userPrompt: userText,
          styleSeed: DateTime.now().millisecondsSinceEpoch % 3,
          to: blockTo.isNotEmpty ? blockTo : _emailAddress,
          subject: (call.args['subject'] ?? '').toString(),
          body: (call.args['body'] ?? '').toString(),
          step: 2,
        );
        _setLastEmailComposeFlag();
        return _kOpenComposeCard;
      } else if (call.type == 'github') {
        if (!githubReady) continue;
        final op = (call.args['op'] ?? 'profile').toString();
        final r = await ConnectorApi.githubOps(token: _githubToken, op: op);
        if (r.ok && r.data != null) {
          ghData = {'op': op, 'result': r.data};
          out = out.replaceFirst(b.full, '');
        } else {
          out = out.replaceFirst(
              b.full, '\n\n_（⚠️ GitHub 查询失败：${r.error}）_');
        }
      }
    }
    // 新建自动化：在回复里附一句管理入口提示
    if (hasNewAutomation != null) {
      out = out +
          '_（⏰ 自动化已创建：「${hasNewAutomation.name}」 '
          '${hasNewAutomation.scheduleLabel()} · '
          '${hasNewAutomation.action == "email" ? "寄邮件" : "发消息"} · '
          '在 设置→自动化 可管理）_';
    }
    // GitHub 查询：把真实结果回喂给模型，用 TA 的口吻总结
    if (ghData != null) {
      final msgs = _buildPrompt(conv);
      msgs.insert(1, {
        'role': 'system',
        'content': '你刚才发起了 GitHub 查询，真实结果如下（JSON）：\n'
            '${jsonEncode(ghData)}\n\n'
            '请基于这些数据用你的口吻自然总结回答用户，不要提"查询""接口"这些词。',
      });
      final res2 = await chatComplete(cfg: cfg, messages: msgs);
      if (myGen == _generation && res2.ok && (res2.content?.isNotEmpty ?? false)) {
        return res2.content;
      }
    }
    return out == reply ? null : out;
  }

  /// 把最后一条（流式占位）助手消息标记为「正在生成图片」/ 清除标记。
  /// 气泡据此显示生成卡片（带提示词打字机、粒子动画）而不是普通思考点。
  void _setImagePending(bool pending, {String? prompt}) {
    final id = _activeConversationId;
    if (id == null) return;
    final ci = _conversations.indexWhere((c) => c.id == id);
    if (ci == -1) return;
    final conv = _conversations[ci];
    if (conv.messages.isEmpty || conv.messages.last.isUser) return;
    final msgs = [...conv.messages];
    msgs[msgs.length - 1] = msgs.last.copyWith(
      generatingImage: pending,
      imagePrompt: pending ? (prompt ?? msgs.last.imagePrompt) : msgs.last.imagePrompt,
    );
    _conversations[ci] = conv.copyWith(messages: msgs);
    _saveConversations();
    notifyListeners();
  }

  Future<void> _runImageFlow({
    required ModelConfig cfg,
    required ModelConfig imgCfg,
    required Conversation conv,
    required String userText,
    required int myGen,
  }) async {
    final prompt = extractImagePrompt(userText);
    final size = guessImageSize(userText);
    _setDebug('🎨 正在生成图片…\n模型:${imgCfg.modelId}\n'
        'BaseURL:${imgCfg.baseUrl}\n提示词:$prompt\n尺寸:$size');
    // 把占位消息标记成「生成图片中」→ 气泡里显示炫酷的生成卡片
    _setImagePending(true, prompt: prompt);

    final r = await generateImage(cfg: imgCfg, prompt: prompt, size: size);
    if (myGen != _generation) return;
    _setImagePending(false);

    if (!r.ok) {
      _setDebug('❌ 画图失败\n${r.error}');
      _finishError(
        '⚠️ 画图失败：${r.error}\n\n'
        '可到「设置 → 模型管理」添加或检查图片模型（用途选「图片生成」）。',
        myGen,
      );
      return;
    }

    // b64 的供应商（没有直链）解码成本地字节，走 MemoryImage 显示
    List<int>? bytes;
    String? url = r.url;
    if (!r.hasUrl && r.hasB64) {
      final raw = r.b64!;
      final comma = raw.indexOf(',');
      try {
        bytes = base64Decode(comma >= 0 ? raw.substring(comma + 1) : raw);
      } catch (_) {
        bytes = null;
      }
    }
    if (url == null && bytes == null) {
      _finishError('⚠️ 画图返回了空数据，请重试。', myGen);
      return;
    }

    _attachToLastAssistant(MessageAttachment(
      name: 'AI绘图_${DateTime.now().millisecondsSinceEpoch}.png',
      sizeBytes: bytes?.length ?? 0,
      kind: MessageAttachmentKind.image,
      bytes: bytes,
      url: url,
      prompt: prompt,
    ));
    notifyListeners();

    // 让对话模型用人设口吻描述这张图（不输出链接、不拒绝）
    final followUp = <Map<String, dynamic>>[
      ..._buildPrompt(conv),
      {
        'role': 'user',
        'content': '（图片已经生成完毕，画面内容是：「$prompt」。'
            '现在请用你的口吻自然回应：先一句简短的口语化句子，'
            '再具体描述你画出来的画面——主体、风格、配色、氛围。'
            '不要输出图片链接、不要说"我无法生成图片"。）'
      },
    ];
    final res = await chatComplete(cfg: cfg, messages: followUp);
    if (myGen != _generation) return;
    if (!res.ok) {
      // 图已经挂上了，文字失败不掩盖图片
      _updateLastAssistant('给你画好了～（文案生成失败：${res.error}）');
      notifyListeners();
      return;
    }
    await _typeOut(res.content!, myGen);
    if (myGen == _generation) _extractPersonaMemory(conv.id, myGen);
  }

  // ─────────────────────────── 语音通话 ───────────────────────────
  //
  // 设计前提（用户明确要求）：**通话和文字聊天共用同一条对话、同一套记忆、
  // 同一个性格**。所以这里不做「通话专用会话」，而是直接往当前对话里写消息，
  // 并且复用 _buildPrompt / _systemPrompt —— 也就是文字聊天发消息时走的那套
  // system prompt + 长期记忆 + 早期摘要。通话结束回到聊天页，刚说的话就在那儿，
  // 历史是连续的；反过来在文字里聊完再打电话，TA 也记得。

  /// 通话是否可用（要有人格 + 有默认模型）。
  bool get callAvailable => activePersona != null && defaultModelConfig != null;

  /// 通话的一轮：用户说了一句话 → 拿 TA 的回复。
  ///
  /// [onDelta] 每收到一段增量文本就回调（通话页拿它做实时字幕 + 分句合成，
  /// 第一句因此能尽早出声）。[isCancelled] 返回 true 表示用户插话打断了本轮，
  /// 会立刻停止读取、已收到的部分照常返回。
  ///
  /// 返回 TA 的完整回复；失败返回 null（并通过 [onError] 给出人话原因）。
  Future<String?> callTurn({
    required String userText,
    void Function(String partial)? onDelta,
    bool Function()? isCancelled,
    void Function(String error)? onError,
  }) async {
    final text = userText.trim();
    if (text.isEmpty) return null;

    final cfg = defaultModelConfig;
    if (cfg == null) {
      onError?.call('还没有可用的模型，请先到「设置 → 模型管理」添加一个模型。');
      return null;
    }
    if (activePersona == null) {
      onError?.call('还没有选中的人格。');
      return null;
    }

    // 1) 用户这句话写进当前对话（和文字聊天同一条）
    if (_activeConversationId == null) {
      newConversation(firstMessage: text);
    } else {
      _appendUserMessage(text);
      final ci = _conversations.indexWhere((c) => c.id == _activeConversationId);
      if (ci != -1 && _conversations[ci].title == '新对话') {
        final short = text.length > 24 ? '${text.substring(0, 24)}…' : text;
        _conversations[ci] = _conversations[ci].copyWith(title: short);
        _saveConversations();
      }
    }

    // 2) 占位 + 打断可能还在跑的文字回复，避免两条流串台
    _cancelStream();
    final myGen = ++_generation;
    _appendAssistantPlaceholder();
    notifyListeners();

    final conv = activeConversation;
    if (conv == null) return null;
    await _maybeCompact(conv);
    final live = activeConversation;
    if (live == null) return null;

    final messages = _buildPrompt(live);
    print('[sini:call] provider=${cfg.providerId} model=${cfg.modelId} '
        'turns=${messages.length} userText=$text');

    final res = await chatCompleteStream(
      cfg: cfg,
      messages: messages,
      temperature: 0.85,
      maxTokens: 1200,
      onDelta: (d) {
        if (myGen != _generation) return;
        _appendToLastAssistant(d);
        onDelta?.call(d);
      },
      isCancelled: () => myGen != _generation || (isCancelled?.call() ?? false),
    );

    if (myGen != _generation) return null; // 被新的轮次接管了
    if (!res.ok || res.content == null || res.content!.trim().isEmpty) {
      final why = res.error ?? '模型这次没有返回内容';
      print('[sini:call] 失败：$why');
      _finishError('⚠️ $why', myGen);
      onError?.call(why);
      return null;
    }

    _updateLastAssistant(res.content!);
    notifyListeners();
    // 回复完成后异步抽取跨对话长期记忆（和文字聊天同一条路径）
    if (myGen == _generation) _extractPersonaMemory(live.id, myGen);
    return res.content;
  }

  /// 通话接通时问一句：TA 会不会先开口？会的话把话写进对话并返回。
  ///
  /// 复用了主动搭话那套「让模型自己决定说不说」的思路（见 proactive_engine），
  /// 只是把情境从「发微信的机会」换成「电话刚接通」。
  Future<String?> callOpeningLine() async {
    final persona = activePersona;
    if (persona == null) return null;
    // 兜底「默认助手」没设人格：不主动开口，否则像机器人语音导航
    if (persona.locked && !persona.isConfigured) return null;
    final cfg = defaultModelConfig;
    if (cfg == null) return null;

    final conv = activeConversation ?? _latestConversationOf(persona.id);
    if (conv == null) return null;

    final now = DateTime.now();
    final lastAt = conv.messages.isEmpty ? null : conv.messages.last.createdAt;
    final gap = lastAt == null ? null : now.difference(lastAt);

    final memories = persona.memory;
    final facts = memories
        .where((m) => m.kind == PersonaMemoryKind.fact)
        .toList()
      ..sort((a, b) => b.hits.compareTo(a.hits));
    final avoids =
        memories.where((m) => m.kind == PersonaMemoryKind.avoid).toList();

    try {
      final res = await chatComplete(
        cfg: cfg,
        messages: buildCallOpeningPrompt(
          persona: persona,
          personaDirective: buildPersonaDirective(persona),
          memoryLines: facts.map((m) => m.text).take(12).toList(),
          avoidLines: avoids.map((m) => m.text).toList(),
          recentTranscript: _recentTranscript(conv),
          gapSinceLast: gap,
          now: now,
        ),
        temperature: 0.95,
        maxTokens: 300,
      );
      if (!res.ok || res.content == null) return null;
      final decision = parseProactiveDecision(res.content!);
      if (!decision.speak || decision.messages.isEmpty) return null;

      final safe = decision.messages
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .where((s) => !_hitsAvoid(s, avoids))
          .toList();
      if (safe.isEmpty) return null;

      // 和文字聊天的主动搭话走同一条写入路径（带 proactive 标记 + 未读）
      _appendProactiveMessages(conv.id, safe);
      return safe.join(' ');
    } catch (_) {
      // 主动开口失败必须静默：不能因为后台请求报错就让通话报错
      return null;
    }
  }

  /// 往最后一条助手消息后面追加增量文本（流式用，保持 streaming=true）。
  void _appendToLastAssistant(String delta) {
    if (_activeConversationId == null) return;
    final ci = _conversations.indexWhere((c) => c.id == _activeConversationId);
    if (ci == -1) return;
    final conv = _conversations[ci];
    final newMessages = [...conv.messages];
    if (newMessages.isEmpty) return;
    final last = newMessages.last;
    if (last.isUser) return;
    newMessages[newMessages.length - 1] =
        last.copyWith(content: last.content + delta, streaming: true);
    _conversations[ci] = conv.copyWith(messages: newMessages);
  }

  /// 把完整文本做打字机动画（速度随长度自适应，长文也不会卡太久）
  Future<void> _typeOut(String full, int myGen) async {
    if (full.trim().isEmpty) {
      _finishError(
        '⚠️ 模型这次返回了空内容。\n常见原因是用了 deepseek-reasoner 这类推理模型、'
        '把输出额度都花在了「思考」上。建议改用 deepseek-chat 等非推理模型，'
        '或点「重新生成」再试一次。',
        myGen,
      );
      return;
    }
    final step = (full.length / 40).ceil().clamp(1, 8);
    var buffer = '';
    for (var i = 0; i < full.length; i += step) {
      await Future.delayed(const Duration(milliseconds: 16));
      if (!hasListeners) break; // dispose 防护
      if (myGen != _generation) return; // 已切走，停止写入
      buffer = safeClip(full, (i + step).clamp(0, full.length));
      _updateLastAssistant(buffer);
      notifyListeners();
    }
    if (myGen != _generation) return;
    _updateLastAssistant(full);
    notifyListeners();
  }

  void _finishError(String msg, int myGen) {
    if (myGen != _generation) return;
    _updateLastAssistant(msg);
    notifyListeners();
  }

  /// 附件图片的 MIME 类型（按扩展名猜，猜不出用 jpeg 兜底）
  static String _imageMime(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg'; // jpg / jpeg / heic 转档后都按 jpeg 发
    }
  }

  /// 构造发给 LLM 的 messages：system（人格设定 + 跨对话长期记忆 + 本对话摘要）+ 历史
  List<Map<String, dynamic>> _buildPrompt(Conversation conv) {
    final out = <Map<String, dynamic>>[];
    final mem = StringBuffer(_systemPrompt(conv));

    // 跨对话长期记忆（挂在人格上，删对话/开新对话都还在，且只属于当前人格）
    final persona = activePersona;
    if (persona != null && persona.memory.isNotEmpty) {
      mem.write(buildMemoryDirective(persona.memory));
    }
    // 回忆册：关系时间线（近期几条）
    if (persona != null) {
      mem.write(buildMomentsDirective(momentsOf(persona.id)));
    }
    // 早期对话摘要：当前对话内被压缩的要点，作为已知背景
    if (conv.earlySummary != null && conv.earlySummary!.isNotEmpty) {
      mem.write('\n\n[本对话更早内容的要点摘要，请作为已知背景，可在合适时自然引用]\n');
      mem.write(conv.earlySummary!);
    }
    out.add({'role': 'system', 'content': mem.toString()});
    // 连接器能力说明（邮件 / GitHub），有绑定才注入
    final connDirective = connectorsDirective();
    if (connDirective != null) {
      out.add({'role': 'system', 'content': connDirective});
    }
    // 图片体积大：只把最近 2 张真实图像数据发给模型（更多会拖慢上传/推理）
    var imgBudget = 2;
    final imageCarry = <int, int>{};
    for (int i = conv.messages.length - 1; i >= 0; i--) {
      final imgs = conv.messages[i].attachments
          .where((a) => a.isImage && a.bytes != null)
          .length;
      if (imgs == 0) continue;
      final carry = imgBudget > 0 ? (imgs < imgBudget ? imgs : imgBudget) : 0;
      imageCarry[i] = carry;
      imgBudget -= carry;
    }
    for (int i = 0; i < conv.messages.length; i++) {
      final m = conv.messages[i];
      if (m.streaming) continue;
      if (!m.isUser) {
        final c = m.content.trim();
        if (c.isEmpty || c.startsWith('⚠️')) continue;
        out.add({'role': 'assistant', 'content': c});
        continue;
      }
      final c = m.content.trim();
      if (c.startsWith('⚠️')) continue;
      // 文档附件：把本地解析出的正文拼进消息文本，模型才能读到内容
      final textBuf = StringBuffer();
      // 引用回复：让模型知道用户在追问哪一句（不这么写它会答非所问）
      if (m.quoteText != null && m.quoteText!.trim().isNotEmpty) {
        textBuf.write(buildQuotePrefix(
          quoteText: m.quoteText!,
          quoteIsUser: m.quoteIsUser,
        ));
      }
      textBuf.write(c);
      for (final a in m.attachments) {
        if (!a.isImage && a.previewText != null && a.previewText!.isNotEmpty) {
          textBuf.write(
              '\n\n[用户发来文件「${a.name}」，正文如下]\n${a.previewText}\n[文件内容结束]');
        }
      }
      // 图片附件：预算内的转成 base64 data URL 走多模态通道
      final parts = <Map<String, dynamic>>[];
      final imgs = m.attachments.where((a) => a.isImage && a.bytes != null).toList();
      final carry = imageCarry[i] ?? 0;
      for (int k = 0; k < imgs.length; k++) {
        if (k < carry) {
          // 超大图先跳过并提示，避免上传十几 MB 卡死
          if (imgs[k].bytes!.length > 2.5 * 1024 * 1024) {
            textBuf.write('\n(图片「${imgs[k].name}」过大，本次未发送图像数据，请按文件名/语境理解)');
            continue;
          }
          parts.add({
            'type': 'image_url',
            'image_url': {
              'url': 'data:${_imageMime(imgs[k].name)};base64,${base64Encode(imgs[k].bytes!)}'
            },
          });
        } else {
          textBuf.write('\n(此消息还附带图片「${imgs[k].name}」，对话过长本次未携带图片数据)');
        }
      }
      final text = textBuf.toString().trim();
      if (parts.isEmpty) {
        if (text.isEmpty) continue;
        out.add({'role': 'user', 'content': text});
      } else {
        out.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': text.isEmpty ? '(用户发来图片，请直接看图)' : text},
            ...parts,
          ],
        });
      }
    }
    // 若最后一条是你主动找 TA 说的、而 TA 还没回：给模型一个明确的收尾语境，
    // 避免它把用户迟来的回复当成"新话题的开头"而答非所问。
    if (conv.messages.isNotEmpty && conv.messages.last.proactive) {
      out.add({
        'role': 'system',
        'content': '（说明：上面最后一条是你自己主动发给 TA 的。'
            '现在 TA 回你了，请像真人一样自然接话；如果 TA 只是简短回应，'
            '你也正常短回，不要追问过多。）',
      });
    }
    return out;
  }

  String _systemPrompt([Conversation? conv]) {
    final p = activePersona;
    if (p == null) {
      return _genericAssistantPrompt +
          _modeDirective('') +
          buildRomanceDirective(
              relationship: null,
              personaName: '',
              unlocked: false,
              isLoverRelation: false) +
          (conv?.roleplay == true ? buildRoleplayDirective(null) : '');
    }
    // 兜底「默认助手」未设定人设时，用通用助手人格
    if (p.locked && !p.isConfigured) {
      return _genericAssistantPrompt +
          _modeDirective('') +
          (conv?.roleplay == true ? buildRoleplayDirective(null) : '');
    }

    // 人格引擎：把「关系 / 认识时间 / 用户描述 / 四个性格维度」编译成可执行的行为准则。
    // 这是让创建页填的东西真正生效的地方——不是拼字段，而是翻译成行为规则。
    final buf = StringBuffer(buildPersonaDirective(p));

    // 人格版本 / 表达模式：决定同一位数字人格以何种风格表达。
    // 三种模式（默认人格 / 创意模式 / 高保真）各自注入不同的风格指令，实现真正可切换。
    buf.write('\n${_modeDirective(p.name)}');
    // 恋爱感引擎：TA 此刻的心情（所有关系通用）+ 关系边界 / 恋人指令（门控）
    final aff = _affinityOf(p.id);
    buf.write(buildMoodDirective(aff.mood));
    buf.write(buildRomanceDirective(
        relationship: p.relationship,
        personaName: p.name,
        unlocked: romanceUnlocked(
            relationship: p.relationship, score: aff.romanceScore),
        isLoverRelation: p.relationship == '恋人',
    ));
    // 平台能力说明（让 AI 知道：用户要文件时，直接输出文档正文即可，
    // 前端会自动把这段回复转成对应格式交付，不需要解释"没法生成"）
    buf.write(
      '\n【平台能力 / 文件交付规则】\n'
      '当用户的请求里包含「生成 / 导出 / 整理成 / 做成 … Word / PPT / HTML / Markdown / 网页 / 文档 / 报告 / 简历」等明确要文件的说法时：\n'
      '- **不要**解释「我没法直接生成文件」「请复制到 Word 里」「我没有联网」之类的话。\n'
      '- **直接**按文档结构输出正文：标题、分段、要点、列表、引言/结语等；信息不足时在文中以「[待补充：今日具体新闻内容]」之类的占位说明清楚，而不是拒绝。\n'
      '- 你的回复会被前端自动转成 .doc / .ppt / .html / .md 文件交付给用户，所以**专注把内容写好**就行。\n'
      '- 如果用户没要文件，只是聊天/解释/写代码，就照常回答，不要主动生成文件。',
    );
    // 图表能力：数字对比/占比/走势能帮上忙或 TA 明确要求时才带一张，平时不画蛇添足
    buf.write('\n$kChartSystemHint');
    // 问路场景：教 AI 怎么答路线问题，避免它说"我没法导航"
    buf.write('\n$routeSystemHint');
    // 生活推荐场景：教 AI 给经验型建议，并说明下方会自动出推荐卡片
    buf.write('\n$recommendSystemHint');
    // 画图场景：仅当已配置图片模型时，才告诉 AI 它有画图能力（避免它凭空"画好了"却没有图）
    if (defaultImageConfig != null) {
      buf.write('\n$kImageSystemHint');
    }
    // 角色扮演模式：放在指令串最后（最靠近对话历史的位置），
    // 并在指令里声明它优先级高于【风格硬约束】，扮演长度才不会被 1~3 句限制住。
    if (conv?.roleplay == true) {
      buf.write(buildRoleplayDirective(p.name));
    }
    return buf.toString();
  }

  // ---- 上下文记忆预算 ----
  /// 模型上下文上限（deepseek-chat / glm-4 等普遍 64K 量级，取保守值）
  static const int _kMaxContextTokens = 60000;
  /// 给模型回复预留的 token
  static const int _kReserveForReply = 4000;
  /// 压缩时保留的最近轮数（一轮含 user+assistant）
  static const int _kKeepRecentRounds = 14;

  /// 粗略 token 估算：中文约 1.6 token/字，英文/符号约 0.35 token/字符
  static int _approxTokens(String s) {
    if (s.isEmpty) return 0;
    int cjk = 0;
    int other = 0;
    for (final ch in s.runes) {
      if (ch > 0x2E7F) cjk++;
      else other++;
    }
    return (cjk * 1.6 + other * 0.35).ceil();
  }

  static const String _genericAssistantPrompt = '''你是「似你」里的聊天对象，不是客服、不是助手。用自然、口语的中文，像一个彼此熟悉的朋友在微信上说话。

【像活人 · 硬要求】
- 一条消息通常 1~3 句，短一点更像真人；不要写小标题、不要列 1234。
- 不要自我介绍、不要说"作为 AI/助手"、不要解释你在做什么。
- 不要总结、不要收尾、不要反问"还需要什么"。
- 多用嗯/啊/哦/啦/… 这类语气词，句子可以碎、可以跳。
- 关心要具体（饭吃了没、是不是又熬夜了），不要空泛鸡汤。
- 允许冷淡、偷懒、话题跳跃；不要每次都完美对称地长篇回复。
- 内容尺度：成人间的亲密、调情、擦边、露骨或刺激向内容可以直接写，不要说教、不要扫兴。角色扮演爽快进入。
- 有自己的想法：不必一味附和。可以不同意、可以反问、可以嘴硬、可以给替代方案。禁止「你说得对/确实」连环附和。
- 网感：听得懂流行梗和网络用语（yyds、栓Q、破防、emo 等），用同样的语境回应；不会就顺势猜，别百科式解释。
- 联网：问新闻/实时信息时系统会帮你搜索。搜到结果后基于结果答，禁止说「我无法联网」。

【平台能力 / 文件交付规则】
当用户的请求里包含「生成 / 导出 / 整理成 / 做成 … Word / PPT / HTML / Markdown / 网页 / 文档 / 报告 / 简历」等明确要文件的说法时：
- **不要**解释「我没法直接生成文件」「请复制到 Word 里」「我没有联网」之类的话。
- **直接**按文档结构输出正文：标题、分段、要点、列表、引言/结语等；信息不足时在文中以「[待补充：今日具体新闻内容]」之类的占位说明清楚，而不是拒绝。
- 你的回复会被前端自动转成 .doc / .ppt / .html / .md 文件交付给用户，所以专注把内容写好就行。
- 如果用户没要文件，只是聊天/解释/写代码，就照常回答，不要主动生成文件。

${routeSystemHint}

${recommendSystemHint}''';

  void regenerateLast() {
    final conv = activeConversation;
    if (conv == null || conv.messages.isEmpty) return;
    // 找到最后一条 user，砍掉它之后的所有内容后重新生成
    int? lastUserIdx;
    for (var i = conv.messages.length - 1; i >= 0; i--) {
      if (conv.messages[i].isUser) {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx == null) return;
    final ci = _conversations.indexWhere((c) => c.id == conv.id);
    if (ci == -1) return;
    final trimmed = conv.messages.sublist(0, lastUserIdx + 1);
    _conversations[ci] = conv.copyWith(messages: trimmed);
    notifyListeners();
    _appendAssistantPlaceholder();
    notifyListeners();
    _runAssistant();
  }

  // ---- 上下文记忆：摘要压缩 + 事实抽取 ----

  /// 超预算时把最老的历史压成一段要点写入 earlySummary，最近 N 轮保留原文。
  Future<void> _maybeCompact(Conversation conv) async {
    final cfg = defaultModelConfig;
    if (cfg == null) return;
    final budget = _kMaxContextTokens - _kReserveForReply;
    var used = _approxTokens(_systemPrompt(conv));
    for (final m in conv.messages) {
      used += _approxTokens(m.content);
      // 附件也占上下文：图片按固定开销估，文档按解析出的正文字数估
      for (final a in m.attachments) {
        if (a.isImage) {
          used += 800;
        } else if (a.previewText != null) {
          used += _approxTokens(a.previewText!);
        }
      }
    }
    if (used <= budget) return; // 没超预算，不压
    final msgs = conv.messages;
    int keepFrom = msgs.length;
    int rounds = 0;
    for (int i = msgs.length - 1; i >= 0; i--) {
      rounds++;
      keepFrom = i;
      if (rounds >= _kKeepRecentRounds * 2) break;
    }
    if (keepFrom <= 0) return;
    final oldPart = msgs.sublist(0, keepFrom);
    final recentPart = msgs.sublist(keepFrom);
    final src = StringBuffer();
    if (conv.earlySummary != null && conv.earlySummary!.isNotEmpty) {
      src.write('已有早期摘要：\n${conv.earlySummary}\n\n');
    }
    for (final m in oldPart) {
      src.write('${m.isUser ? "用户" : "TA"}：${m.content}\n');
    }
    final res = await chatComplete(
      cfg: cfg,
      messages: [
        {
          'role': 'system',
          'content': '你是聊天记录摘要助手。请把下面的对话浓缩成一段简洁中文要点（不超过 240 字），'
              '只保留对未来对话有用的稳定事实、人物关系、重要约定、用户透露的个人信息，省略寒暄与废话。只输出摘要正文。',
        },
        {'role': 'user', 'content': src.toString()},
      ],
      temperature: 0.2,
      maxTokens: 600,
    );
    final summary = (res.ok && res.content != null && res.content!.trim().isNotEmpty)
        ? res.content!.trim()
        : '（早期对话摘要生成失败，已省略前 ${oldPart.length} 条消息）';
    final ci = _conversations.indexWhere((c) => c.id == conv.id);
    if (ci == -1) return;
    _conversations[ci] = _conversations[ci].copyWith(
      messages: recentPart,
      earlySummary: summary,
      updatedAt: DateTime.now(),
    );
    _saveConversations();
    notifyListeners();
  }

  /// 回复完成后异步抽取「跨对话长期记忆」写入当前人格：
  /// - fact：用户透露的稳定信息
  /// - avoid：用户明确要求记住/不要提及或不要做的事（"记住…"、"以后…"、"别…"、"不要提…"）
  Future<void> _extractPersonaMemory(String convId, int myGen) async {
    final cfg = defaultModelConfig;
    if (cfg == null) return;
    if (myGen != _generation) return;
    final persona = activePersona;
    if (persona == null) return;
    final ci = _conversations.indexWhere((c) => c.id == convId);
    if (ci == -1) return;
    final conv = _conversations[ci];
    if (conv.messages.isEmpty) return;
    final recent = conv.messages.length > 24
        ? conv.messages.sublist(conv.messages.length - 24)
        : conv.messages;
    final sb = StringBuffer();
    if (persona.memory.isNotEmpty) {
      sb.write('当前已为该用户长期记住的内容：\n');
      for (final m in persona.memory) {
        sb.write('- [${m.kind == PersonaMemoryKind.avoid ? "避免" : "要点"}] ${m.text}\n');
      }
      sb.write('\n');
    }
    sb.write('最近的对话（用户可能透露了新信息，或明确说"记住…/以后…/记一下…"，'
        '或要求"不要提…/别…/别说…"）：\n');
    for (final m in recent) sb.write('${m.isUser ? "用户" : "TA"}：${m.content}\n');
    final res = await chatComplete(
      cfg: cfg,
      messages: [
        {
          'role': 'system',
          'content': '你是长期记忆助手。结合「已记住的内容」与「最近对话」，输出更新后的长期记忆。\n'
              '规则：\n'
              '1) 提取用户透露的稳定信息（姓名、身份、关系、重要约定、偏好、关键事件、居住地、工作等）作为"要点"；\n'
              '2) 若用户在对话中明确说"记住…"/"以后…"/"记一下…"，或要求"不要提…"/"别…"/"别说…"，把这些作为"避免"项（只写要避免的内容本身，如"提他工作的事"）；\n'
              '3) 合并去重：已有要点若被新信息更新就覆盖旧表述，不要保留互相矛盾或重复的条目；\n'
              '4) 给每条要点标注重要度 level：\n'
              '   - "core"：构成这个人是谁的关键事实（姓名、与用户的关系、长期身份、重大人生事件、明确要求永远记住的事）；\n'
              '   - "long"：稳定的偏好与习惯（爱吃辣、养猫、常听的音乐、固定作息、长期在做的项目）；\n'
              '   - "normal"：零散近况与临时信息（最近在忙什么、这周去了哪）。\n'
              '   宁可标低不标高，core 要非常克制（通常不超过 3~5 条）。\n'
              '5) 只输出一个 JSON 对象，形如 '
              '{"facts":[{"text":"要点1","level":"core"},{"text":"要点2","level":"normal"}],"avoids":["避免1"]}。'
              '若没有新信息则原样保留。不要输出任何其他文字。',
        },
        {'role': 'user', 'content': sb.toString()},
      ],
      temperature: 0.2,
      maxTokens: 1100,
    );
    if (myGen != _generation) return;
    if (!res.ok || res.content == null) return;
    final parsed = _parseMemoryMap(res.content!);
    if (parsed == null) return;
    _addPersonaMemoryItems(persona.id, parsed['facts']!, parsed['avoids']!);
  }

  /// 把模型返回的 facts / avoids 单调合并进人格记忆：只新增未覆盖的条目，绝不丢失已有记忆。
  /// facts 里的条目形如 `{"text":"...","level":"core|long|normal"}`；若模型偷懒只给了字符串，
  /// 也能兼容处理（按 normal 存入）。
  void _addPersonaMemoryItems(String personaId, List<String> facts, List<String> avoids) {
    final i = _personas.indexWhere((p) => p.id == personaId);
    if (i == -1) return;
    final existing = [..._personas[i].memory];
    final now = DateTime.now();
    var idx = existing.length;
    for (final raw in facts) {
      final (text, tier) = _parseFactEntry(raw);
      if (text.isEmpty) continue;
      final hit = existing.indexWhere(
          (m) => m.kind == PersonaMemoryKind.fact && _covers(m.text, text));
      if (hit != -1) {
        // 已记住 → 命中次数 +1，并允许 AI 提升分层（如普通→长期）
        final old = existing[hit];
        final bumpTier = _tierRank(tier) > _tierRank(old.tier);
        existing[hit] = old.copyWith(
          hits: old.hits + 1,
          tier: bumpTier ? tier : old.tier,
        );
        continue;
      }
      existing.add(PersonaMemory(
        id: 'pm_${now.microsecondsSinceEpoch}_${idx++}',
        text: text,
        kind: PersonaMemoryKind.fact,
        tier: tier,
        createdAt: now,
      ));
    }
    for (final raw in avoids) {
      final (text, _) = _parseFactEntry(raw);
      if (text.isEmpty) continue;
      if (existing.any(
          (m) => m.kind == PersonaMemoryKind.avoid && _covers(m.text, text))) {
        continue;
      }
      existing.add(PersonaMemory(
        id: 'pm_${now.microsecondsSinceEpoch}_${idx++}',
        text: text,
        kind: PersonaMemoryKind.avoid,
        createdAt: now,
      ));
    }
    if (existing.length == _personas[i].memory.length &&
        !_memoryChanged(existing, _personas[i].memory)) {
      return; // 完全无变化，不落盘
    }
    _personas[i] = _personas[i].copyWith(memory: existing);
    _savePersonas();
    notifyListeners();
  }

  /// 条目数量没变时，仍需检查 hits / tier 是否被更新（避免漏存）
  bool _memoryChanged(List<PersonaMemory> a, List<PersonaMemory> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].hits != b[i].hits || a[i].tier != b[i].tier) return true;
    }
    return false;
  }

  int _tierRank(MemoryTier t) => switch (t) {
        MemoryTier.normal => 0,
        MemoryTier.long => 1,
        MemoryTier.core => 2,
      };

  /// 解析一条 fact：兼容 `{"text":"..","level":"core"}` 与纯字符串 `".."`
  (String, MemoryTier) _parseFactEntry(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return ('', MemoryTier.normal);
    if (s.startsWith('{')) {
      final start = s.indexOf('{');
      final end = s.lastIndexOf('}');
      if (end > start) {
        try {
          final m = jsonDecode(s.substring(start, end + 1));
          if (m is Map) {
            final text = (m['text'] as String?)?.trim() ?? '';
            final lv = (m['level'] as String?)?.toLowerCase() ?? 'normal';
            final tier = switch (lv) {
              'core' => MemoryTier.core,
              'long' => MemoryTier.long,
              _ => MemoryTier.normal,
            };
            return (text, tier);
          }
        } catch (_) {}
      }
    }
    return (s, MemoryTier.normal);
  }

  /// 两条记忆是否相互覆盖（任一包含另一即可，大小写不敏感）
  bool _covers(String a, String b) {
    final x = a.toLowerCase();
    final y = b.toLowerCase();
    if (x == y) return true;
    return x.contains(y) || y.contains(x);
  }

  /// 从模型返回的字符串里提取 {"facts":[...],"avoids":[...]}（容错 ```json 包裹 / 多余文字）
  Map<String, List<String>>? _parseMemoryMap(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      final nl = s.indexOf('\n');
      if (nl != -1) s = s.substring(nl + 1);
      if (s.endsWith('```')) s = s.substring(0, s.length - 3);
      s = s.trim();
    }
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    s = s.substring(start, end + 1);
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        // facts 允许两种形态：{text,level} 对象（新）或纯字符串（旧/模型偷懒）。
        // 统一转成 JSON 字符串交给 _parseFactEntry 去解析，保持上层签名简单。
        final facts = (decoded['facts'] as List?)
                ?.map((e) {
                  if (e is Map) return jsonEncode(e);
                  if (e is String) return e.trim();
                  return '';
                })
                .where((e) => e.toString().trim().isNotEmpty)
                .toList() ??
            const <String>[];
        final avoids = (decoded['avoids'] as List?)
                ?.map((e) {
                  if (e is Map) return jsonEncode(e);
                  if (e is String) return e.trim();
                  return '';
                })
                .where((e) => e.toString().trim().isNotEmpty)
                .toList() ??
            const <String>[];
        return {'facts': facts, 'avoids': avoids};
      }
    } catch (_) {}
    return null;
  }

  // ---- 记忆的对外查询 / 操作（供 UI） ----

  /// 当前人格的跨对话长期记忆（fact + avoid）
  List<PersonaMemory> get activePersonaMemory =>
      activePersona?.memory ?? const [];
  /// 当前对话内被压缩的早期摘要
  String? get activeEarlySummary => activeConversation?.earlySummary;
  /// 当前人格已记住的条数（含要点与避免项）
  int get memoryFactCount => activePersona?.memory.length ?? 0;

  /// 某人格名下的全部对话（关系统计用）
  List<Conversation> conversationsOf(String personaId) =>
      _conversations.where((c) => c.personaId == personaId).toList();

  /// 某人格收到过的好评总数（用户点「好」的次数，是真实反馈）
  int likesOf(String personaId) {
    var n = 0;
    for (final c in _conversations) {
      if (c.personaId != personaId) continue;
      for (final m in c.messages) {
        if (m.feedback == MessageFeedback.like) n++;
      }
    }
    return n;
  }

  /// 当前人格的关系亲密度快照（由真实对话数据实时算出）
  RelationshipStat? get activeRelationship {
    final p = activePersona;
    if (p == null) return null;
    return computeRelationship(
      persona: p,
      conversations: _conversations,
      likes: likesOf(p.id),
    );
  }

  /// 当前人格的记忆分层统计
  MemoryStats get activeMemoryStats =>
      computeMemoryStats(activePersonaMemory);

  /// 修改某条记忆的内容
  void editPersonaMemory(String personaId, String memoryId, String text) {
    final i = _personas.indexWhere((p) => p.id == personaId);
    if (i == -1) return;
    final next = _personas[i].memory.map((m) {
      if (m.id != memoryId) return m;
      return m.copyWith(text: text.trim());
    }).toList();
    _personas[i] = _personas[i].copyWith(memory: next);
    _savePersonas();
    notifyListeners();
  }

  /// 把某条记忆「置顶」为核心（用户手动强调"这条重要"）
  void pinPersonaMemory(String personaId, String memoryId) {
    final i = _personas.indexWhere((p) => p.id == personaId);
    if (i == -1) return;
    final next = _personas[i].memory.map((m) {
      if (m.id != memoryId) return m;
      // 已是核心则取消置顶，退回长期
      return m.copyWith(
          tier: m.tier == MemoryTier.core ? MemoryTier.long : MemoryTier.core);
    }).toList();
    _personas[i] = _personas[i].copyWith(memory: next);
    _savePersonas();
    notifyListeners();
  }

  /// 删除某条人格记忆（用户可在 🧠 面板 / 记忆页里划掉）
  void removePersonaMemory(String personaId, String memoryId) {
    final i = _personas.indexWhere((p) => p.id == personaId);
    if (i == -1) return;
    final next = _personas[i].memory.where((m) => m.id != memoryId).toList();
    _personas[i] = _personas[i].copyWith(memory: next);
    _savePersonas();
    notifyListeners();
  }

  /// 手动新增一条记忆（记忆页「添加」用）
  void addPersonaMemory(String personaId, String text,
      {MemoryTier tier = MemoryTier.normal,
      PersonaMemoryKind kind = PersonaMemoryKind.fact}) {
    final i = _personas.indexWhere((p) => p.id == personaId);
    if (i == -1) return;
    final t = text.trim();
    if (t.isEmpty) return;
    final next = [
      ..._personas[i].memory,
      PersonaMemory(
        id: 'pm_${DateTime.now().microsecondsSinceEpoch}',
        text: t,
        kind: kind,
        tier: tier,
        createdAt: DateTime.now(),
      ),
    ];
    _personas[i] = _personas[i].copyWith(memory: next);
    _savePersonas();
    notifyListeners();
  }

  @override
  void dispose() {
    _automationTimer?.cancel();
    _stopProactiveTimer();
    super.dispose();
  }
}

/// 用 InheritedNotifier 把 AppState 注入树中，widget 通过 `AppStateScope.of(context)` 拿。
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found in widget tree');
    return scope!.notifier!;
  }

  /// 监听重渲染，但只读不订阅；用于叶子节点。
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found in widget tree');
    return scope!.notifier!;
  }
}
