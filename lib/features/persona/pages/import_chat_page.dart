import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_sheet.dart';
import '../../../core/widgets/sini_status_pill.dart';
import '../../../core/widgets/sini_text_field.dart';
import '../../../theme.dart';
import '../../../app_state.dart';
import '../../../models.dart';
import '../chat_import/chat_models.dart';
import '../chat_import/chat_parser.dart';
import '../chat_import/chat_stats.dart';
import '../chat_import/persona_extractor.dart';
import '../chat_import/text_decode.dart';
import '../../voice/presets.dart';
import '../../voice/ref_audio_store.dart';
import '../../voice/pages/voice_clone_page.dart' show kDraftRefKey;

/// 数字人格的「克隆」总入口。
///
/// 页面结构是一份「素材清单」：一个性格 + 三样素材
///   · 聊天记录 —— 已可用，学会 TA 怎么说话
///   · 照片     —— 即将支持，还原 TA 长什么样
///   · 声音     —— 已可用，跳「声音克隆」页（ZipVoice 本机克隆音色）
///
/// 聊天记录这条链路是**真实**的：
///   文件 → 解码(UTF-8/GB18030) → 多解析器竞争 → 本地统计 → LLM 风格取证
///   → 写进 Persona（风格画像 + 性格维度 + 长期记忆）
/// 全程在浏览器里完成，聊天记录不上传任何服务器。
///
/// 两种语义：
/// - [createMode] = true（从「创建人物」/ 首次引导进入）：分析完生成画像，
///   确认名字后创建一位新人格并开始对话；
/// - false（从人格详情「添加素材」进入）：把分析结果应用到当前已选的人格。
class ImportChatPage extends StatefulWidget {
  final bool createMode;
  const ImportChatPage({super.key, this.createMode = false});

  @override
  State<ImportChatPage> createState() => _ImportChatPageState();
}

/// 素材清单里的一行
class _SourceItem {
  final IconData icon;
  /// 已可用 = 正常配色；未开放 = 灰一点、带「即将支持」
  final bool available;
  /// 有路由 = 整行可点，点进对应流程（目前只有「声音」→ 声音克隆页）。
  /// 写字符串而不是引 AppRoutes，是为了不让这个页面和 app_router 互相 import。
  final String? route;
  const _SourceItem(this.icon, {this.available = true, this.route});
}

class _ImportChatPageState extends State<ImportChatPage> {
  // ── 用户选择 ───────────────────────────────────────────────
  String _fileKind = '自动';
  String _platform = '自动';

  // ── 流水线状态 ─────────────────────────────────────────────
  bool _busy = false;
  double _progress = 0;
  String _stage = '';
  String? _error;
  String? _errorHint;

  String _fileName = '';
  int _fileSize = 0;
  String _encoding = '';
  ParsedChat? _chat;
  ChatStats? _stats;
  PersonaStyle? _style;
  ExtractResult? _extract;
  bool _usedLlm = false;
  /// 分析时的"我"是谁——换人就得重算统计和风格
  String _analyzedAsSelf = '';

  final TextEditingController _nameCtl = TextEditingController();

  // 与创建页同款的 6 组头像渐变（按名字取，不再一刀切）
  static const List<List<int>> _seeds = [
    [231, 217, 209, 183, 196, 216], // 暖橙
    [209, 218, 231, 178, 184, 207], // 冷蓝
    [231, 209, 219, 219, 178, 207], // 粉紫
    [219, 231, 209, 184, 207, 178], // 暖绿
    [231, 224, 209, 207, 196, 178], // 暖黄
    [216, 209, 231, 178, 196, 219], // 紫罗兰
  ];

  final _fileKinds = ['自动', 'TXT', 'JSON', 'CSV'];
  final _platforms = ['自动', '微信', 'QQ', 'Telegram'];

  /// 素材清单：左图标 + 名称 + 说明 + 右侧状态；可点的那几行带箭头
  static const List<(_SourceItem, String, String, String?, SiniStatusTone)>
      _sources = [
    (
      _SourceItem(Icons.forum_outlined),
      '聊天记录',
      'TXT / JSON / CSV · 学会 TA 怎么说话',
      '已支持',
      SiniStatusTone.success,
    ),
    (
      _SourceItem(Icons.photo_outlined, available: false),
      '照片',
      '还原 TA 的样子，用在头像和视频通话',
      '即将支持',
      SiniStatusTone.neutral,
    ),
    (
      _SourceItem(Icons.graphic_eq_rounded, available: false),
      '声音',
      '导入语音克隆音色（当前开发中，先关掉入口）',
      '开发中',
      SiniStatusTone.neutral,
    ),
  ];

  /// 声音克隆页的路由（等价于 AppRoutes.voiceClone）
  static const String _voiceCloneRoute = '/voice/clone';

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return SiniScaffold(
      title: widget.createMode ? '克隆 TA' : '添加素材',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xxl),
        children: [
          if (widget.createMode) ...[
            _hintCard(p),
            const SizedBox(height: Spacing.xxl),
          ],

          // ── 一、素材清单：人格由这几样东西拼出来 ────────────────
          _sectionTitle(p, '可以导入什么'),
          const SizedBox(height: Spacing.sm),
          Container(
            decoration: BoxDecoration(
              color: p.itemHover,
              borderRadius: BorderRadius.circular(Radii.xl),
              border: Border.all(color: p.border, width: 1),
            ),
            // 声音那一行可点，水波纹要裁在圆角里
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < _sources.length; i++) ...[
                  if (i > 0) _sourceDivider(p),
                  _sourceTile(p, _sources[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: Spacing.xl),

          _noteCard(p),
          const SizedBox(height: Spacing.xxxl),

          // ── 二、聊天记录导入 ─────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.forum_outlined, size: 16, color: p.brand),
              const SizedBox(width: Spacing.sm),
              _sectionTitle(p, '导入聊天记录'),
              const Spacer(),
              if (_style != null) const SiniStatusPill(label: '已解析', tone: SiniStatusTone.success),
              if (_busy) const SiniStatusPill(label: '分析中', tone: SiniStatusTone.neutral),
            ],
          ),
          const SizedBox(height: Spacing.sm),

          if (_error != null) _errorCard(p),
          if (_chat == null && !_busy && _error == null) _uploadZone(p),
          if (_busy) _progressCard(p),
          if (_chat != null && !_busy) ...[
            _parsedCard(p),
            if (_style != null) ...[
              const SizedBox(height: Spacing.lg),
              _styleCard(p),
            ] else if (_error == null) ...[
              const SizedBox(height: Spacing.lg),
              _analyzePromptCard(p),
            ],
          ],

          if (_chat != null && !_busy) ...[
            const SizedBox(height: Spacing.sm),
            _secondaryLink(
              p,
              icon: Icons.refresh_rounded,
              label: '换一份聊天记录',
              onTap: () => setState(() {
                _chat = null;
                _stats = null;
                _style = null;
                _extract = null;
                _error = null;
                _errorHint = null;
                _progress = 0;
                _stage = '';
              }),
            ),
          ],

          const SizedBox(height: Spacing.xxl),

          // ── 三、补充素材：照片 / 声音都先关入口 ──────────
          _sectionTitle(p, '补充素材'),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: _upcomingCard(
                  p,
                  icon: Icons.photo_outlined,
                  title: '导入照片',
                  hint: '让 TA 有张脸',
                  onTap: () => _showUpcomingSheet('导入照片'),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: _upcomingCard(
                  p,
                  icon: Icons.graphic_eq_rounded,
                  title: '导入声音',
                  hint: '克隆 TA 的音色',
                  onTap: () => _showUpcomingSheet('导入声音'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xxl),
        ],
      ),
      // 主操作常驻底部：不管有没有导入聊天记录，都能看到并点到。
      bottomBar: _bottomBar(p),
    );
  }

  Widget _bottomBar(AppPalette p) {
    final isCreate = widget.createMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
      child: SiniButton(
        label: isCreate ? '保存并创建' : '应用到人格',
        leadingIcon: isCreate
            ? Icons.person_add_alt_1_rounded
            : Icons.auto_awesome_rounded,
        onTap: _busy ? null : _onPrimaryAction,
        style: SiniButtonStyle.primary,
        expand: true,
        height: 50,
      ),
    );
  }

  // ═══════════════════════ 真实流水线 ═══════════════════════

  /// 选文件 → 解码 → 解析 → 统计 → 风格取证。全程本地（除了最后一步调模型）。
  Future<void> _pickAndRun() async {
    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'json', 'csv', 'md', 'log'],
        allowMultiple: false,
      );
    } catch (_) {
      // 某些浏览器对 custom 扩展名支持不佳，退回不限制类型
      try {
        picked = await FilePicker.pickFiles(allowMultiple: false);
      } catch (_) {
        return; // 用户取消
      }
    }
    if (picked.isEmpty || !mounted) return;

    final f = picked.first;
    Uint8List bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (e) {
      setState(() {
        _error = '读不到文件内容';
        _errorHint = '换个文件试试，或重新导出一次。';
      });
      return;
    }
    if (!mounted) return;

    setState(() {
      _fileName = f.name;
      _fileSize = bytes.length;
    });
    await _runPipeline(bytes);
  }

  Future<void> _runPipeline(Uint8List bytes) async {
    setState(() {
      _busy = true;
      _progress = 0.08;
      _stage = '读取文件…';
      _error = null;
      _errorHint = null;
      _chat = null;
      _stats = null;
      _style = null;
      _extract = null;
    });
    await _tick();

    // ① 解码：微信 / QQ 老导出常是 GBK，这里会自动认
    final decoded = decodeChatFile(bytes);
    _encoding = decoded.encoding;
    await _tick();

    // ② 解析：多解析器竞争
    setState(() {
      _progress = 0.25;
      _stage = '解析聊天记录…';
    });
    await _tick();

    final chat = parseChatText(
      decoded.text,
      platformHint: _platform == '自动' ? '通用' : _platform,
      formatHint: _fileKind == '自动' ? '自动' : _fileKind,
    );

    if (chat == null || chat.isEmpty) {
      setState(() {
        _busy = false;
        _progress = 0;
        _stage = '';
        _error = '没能从这份文件里读出聊天消息';
        _errorHint = decoded.lossy
            ? '文件编码可能不是 UTF-8/GBK，请在导出工具或记事本里另存为 UTF-8 后重试。'
            : '可以试试换一个「文件格式」或「来源平台」再导入；'
                '如果这份导出排版比较特殊，把文件发我，我给它加一个适配。';
      });
      return;
    }

    // ③ 谁是"我"：优先用上次记住的名字（同一个人反复导入时不用每次点）
    final selfName = await _resolveSelf(chat);
    final marked = chat.withSelf(selfName);

    setState(() {
      _chat = marked;
      _progress = 0.45;
      _stage = '统计说话习惯…';
    });
    await _tick();

    await _analyze(marked, selfName);
  }

  /// 统计 + 风格取证（换"我"之后也会重跑这一段）
  Future<void> _analyze(ParsedChat chat, String selfName) async {
    final stats = computeChatStats(chat);

    final cfg = AppStateScope.read(context).defaultModelConfig;
    PersonaStyle style;
    ExtractResult? extract;
    var usedLlm = false;

    if (cfg == null) {
      // 没配模型：不假装成功，走本地统计版画像并明确告知
      style = buildStyleFromStats(chat: chat, stats: stats);
    } else {
      setState(() {
        _progress = 0.6;
        _stage = '让 AI 读 TA 的说话方式…（记录多时需要十几秒）';
      });
      await _tick();

      final r = await extractStyleWithLlm(cfg: cfg, chat: chat, stats: stats);
      extract = r;
      if (r.ok) {
        style = r.style!;
        usedLlm = true;
      } else {
        // 模型失败不能让整个导入失败——退回本地版，但如实标注
        style = buildStyleFromStats(chat: chat, stats: stats);
        setState(() {
          _error = null;
          _errorHint = 'AI 分析没成功（${r.error}），已改用本地统计生成简版画像。';
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = 1;
      _stage = '';
      _stats = stats;
      _style = style;
      _extract = extract;
      _usedLlm = usedLlm;
      _analyzedAsSelf = selfName;
      if (_nameCtl.text.trim().isEmpty) {
        _nameCtl.text = stats.taName.isEmpty ? 'TA' : stats.taName;
      }
    });
  }

  /// 猜"我"是谁：格式里带发送者标识就直接用；否则默认第一个开口的人。
  String _guessSelf(ParsedChat chat) {
    final flagged = chat.messages.where((m) => m.isSelf).toList();
    if (flagged.isNotEmpty) return flagged.first.sender;
    return chat.messages.first.sender;
  }

  /// 谁是"我"：记住的选择 > 格式里的标记 > 第一个开口的人。
  ///
  /// 聊天记录本身**不包含**"哪一方是软件主人"这个信息（纯文本复制尤其没有），
  /// 所以这个只能靠用户点一次。点过之后记下来，同一个人再导入就不用重复点了。
  static const String _kSelfNameKey = 'sini_import_self_name';

  Future<String> _resolveSelf(ParsedChat chat) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remembered = prefs.getString(_kSelfNameKey);
      if (remembered != null && chat.participants.contains(remembered)) {
        return remembered;
      }
    } catch (_) {
      // 读不到就退回启发式
    }
    return _guessSelf(chat);
  }

  Future<void> _rememberSelf(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSelfNameKey, name);
    } catch (_) {
      // 记不住也不影响本次使用
    }
  }

  /// 用户切换"哪一方是我" → 统计和风格都要按新的身份重算
  Future<void> _changeSelf(String selfName) async {
    final chat = _chat;
    if (chat == null || selfName == _analyzedAsSelf) return;
    await _rememberSelf(selfName);
    final rebuilt = chat.withSelf(selfName);
    setState(() => _chat = rebuilt);
    await _runPipelineFrom(rebuilt, selfName);
  }

  Future<void> _runPipelineFrom(ParsedChat chat, String selfName) async {
    setState(() {
      _busy = true;
      _progress = 0.45;
      _stage = '重新统计…';
      _style = null;
    });
    await _tick();
    await _analyze(chat, selfName);
  }

  /// 让出控制权，好让进度条真的动起来
  Future<void> _tick() async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  // ═══════════════════════ 主操作 ═══════════════════════

  void _onPrimaryAction() {
    if (!widget.createMode) {
      final state = AppStateScope.read(context);
      final target = state.activePersona;
      if (target == null) {
        _toast(context, '还没有可以应用素材的人格');
        return;
      }
      final style = _style;
      if (style == null) {
        _toast(context, '先导入一份聊天记录，再应用到 TA');
        return;
      }
      state.applyImportedStyle(
        personaId: target.id,
        style: style,
        traits: _extract?.traits ?? const {},
        memories: _extract?.memories ?? const [],
        relationshipGuess: _extract?.relationshipGuess ?? '',
        sinceGuess: _extract?.sinceGuess ?? '',
      );
      _toast(context, '已把「${target.name}」的说话方式更新到人格里');
      Navigator.of(context).pop();
      return;
    }

    // 创建模式：已经分析出画像 → 直接建；没有 → 问名字建一个空的
    if (_style != null) {
      final name = _nameCtl.text.trim();
      if (name.isEmpty) {
        _toast(context, '先给 TA 起个名字');
        return;
      }
      _createPersona(name);
      return;
    }
    _askNameThenCreate();
  }

  /// 没有素材时创建：只问名字，之后随时可以再补聊天记录 / 照片 / 声音
  Future<void> _askNameThenCreate() async {
    final ctl = TextEditingController();
    final ok = await showSiniSheet<bool>(
      context: context,
      title: 'TA 叫什么名字',
      subtitle: '还没有导入聊天记录，先用一个名字把 TA 建出来，之后可以随时补充素材。',
      child: SiniTextField(
        controller: ctl,
        label: '名字',
        hintText: '比如：小雨',
        autofocus: true,
      ),
      primary: ('保存并创建', () => Navigator.of(context).pop(true)),
      secondary: ('取消', () => Navigator.of(context).pop(false)),
    );
    final name = ctl.text.trim();
    ctl.dispose();
    if (ok != true || !mounted) return;
    if (name.isEmpty) {
      _toast(context, '先给 TA 起个名字');
      return;
    }
    _createPersona(name);
  }

  /// 建人格 → 选中它 → 开一个新对话 → 回到主界面（也就是和 TA 的聊天）
  Future<void> _createPersona(String name) async {
    final state = AppStateScope.of(context);
    final style = _style;
    final stats = _stats;
    final extract = _extract;

    final subtitle = stats != null && stats.taCount > 0
        ? '由聊天记录还原 · ${_fmtCount(stats.taCount)} 条 ${stats.taName} 的消息'
        : '新人格 · 还没有素材';

    final persona = Persona(
      id: 'p_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      subtitle: subtitle,
      gradientSeed: _seeds[_seedIndexFor(name)],
      relationship: extract?.relationshipGuess ?? '',
      since: extract?.sinceGuess ?? '',
      warmth: extract?.traits['warmth'] ?? 0.5,
      rationality: extract?.traits['rationality'] ?? 0.5,
      initiative: extract?.traits['initiative'] ?? 0.5,
      humor: extract?.traits['humor'] ?? 0.5,
      style: style,
      // 把"谁是 TA、谁是对方"一起存下来，供提示词钉死双方身份。
      // 不存的话模型只能自己猜，实测会把 TA 自己的名字安到用户头上。
      ownerName: _analyzedAsSelf.trim(),
      sourceName: _sourceNameOf(_chat, _analyzedAsSelf),
      // 声音：克隆草稿优先；没克隆过就给默认预设「温柔女声」，
      // 之后可随时在声音页重新克隆/更改（每个新人格都有声音可用）。
      voice: () {
        final dv = state.takeDraftVoice();
        if (dv != null) return dv;
        final preset = voicePresetById('wenrou');
        if (preset == null) return null;
        return PersonaVoice(
          sourceLabel: '预设音色 · ${preset.label}',
          referenceText: preset.promptText,
          sampleSeconds: 0,
          consentedAt: DateTime.now(),
          ready: true,
          presetId: preset.id,
        );
      }(),
    );
    state.addPersona(persona);
    state.selectPersona(persona.id);
    state.newConversation();

    // 暂存的参考音频（IndexedDB）从草稿 key 迁到正式 personaId
    final dv = persona.voice;
    if (dv != null && !dv.isPreset) {
      final draftAudio = await RefAudioStore.load(kDraftRefKey);
      if (draftAudio != null) {
        await RefAudioStore.save(persona.id, draftAudio);
        await RefAudioStore.delete(kDraftRefKey);
      }
    }

    // 长期记忆要等人格存在后再写（applyImportedStyle 内部会去重、落盘）
    final memories = extract?.memories;
    if (style != null && memories != null && memories.isNotEmpty) {
      state.applyImportedStyle(
        personaId: persona.id,
        style: style,
        traits: extract?.traits ?? const {},
        memories: memories,
        relationshipGuess: extract?.relationshipGuess ?? '',
        sinceGuess: extract?.sinceGuess ?? '',
      );
    }

    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  /// 按名字取头像渐变：同一个人任何时候都是同一套色，不同人不一样
  int _seedIndexFor(String name) {
    var h = 0;
    for (final c in name.runes) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h % _seeds.length;
  }

  static String _fmtCount(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  void _toast(BuildContext context, String msg) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: TextStyle(color: p.inverseOn, fontSize: SiniText.bodySm)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: p.textPrimary.withValues(alpha: 0.92),
          duration: const Duration(milliseconds: 1800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill)),
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        ),
      );
  }

  // ═══════════════════════ 顶部说明 ═══════════════════════

  Widget _hintCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: p.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: p.brand.withValues(alpha: 0.18), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: p.brand),
          const SizedBox(width: Spacing.sm + 2),
          Expanded(
            child: Text(
              'AI 会从记录里学习 TA 的说话方式、称呼与口头禅，生成一份人格画像，保存后就能直接和 TA 开聊。',
              style: TextStyle(fontSize: SiniText.labelMd, color: p.textSecondary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════ 素材清单 ═══════════════════════

  Widget _sourceTile(
      AppPalette p,
      (_SourceItem, String, String, String?, SiniStatusTone) item) {
    final (src, name, desc, status, tone) = item;
    final route = src.route;

    final row = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md + 2, vertical: Spacing.md + 2),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: p.mainBg,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Icon(src.icon,
                size: 19,
                color: src.available ? p.brand : p.textTertiary),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: SiniText.bodySm + 0.5,
                        fontWeight: FontWeight.w600,
                        color: src.available ? p.textPrimary : p.textSecondary)),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(
                        fontSize: SiniText.labelMd,
                        color: p.textTertiary,
                        height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          SiniStatusPill(label: status!, tone: tone),
          if (route != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 18, color: p.textTertiary),
          ],
        ],
      ),
    );

    if (route == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: () => _openSourceRoute(route), child: row),
    );
  }

  /// 点素材清单里「已支持」的那一行 —— 目前只有声音，直接进克隆页
  void _openSourceRoute(String route) {
    if (route == _voiceCloneRoute) {
      _openVoiceClone();
      return;
    }
    Navigator.of(context).pushNamed(route);
  }

  Widget _sourceDivider(AppPalette p) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: Spacing.md + 2 + 38 + Spacing.md),
      color: p.border,
    );
  }

  /// 清单下方的说明：照片 / 声音是下一步要做的事
  Widget _noteCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: p.textTertiary),
          const SizedBox(width: Spacing.sm + 2),
          Expanded(
            child: Text(
              '聊天记录与声音样本全程在你自己的浏览器里处理，不会上传到任何服务器。'
              '照片的导入能力还在开发中，先把这个位置占着。',
              style: TextStyle(
                  fontSize: SiniText.labelMd,
                  color: p.textSecondary,
                  height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════ 上传 / 进度 / 错误 ═══════════════════════

  Widget _uploadZone(AppPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.xl),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.xl),
            onTap: _pickAndRun,
            child: Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                color: p.itemHover,
                borderRadius: BorderRadius.circular(Radii.xl),
                border: Border.all(color: p.border, width: 1.2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 46, color: p.textSecondary),
                  const SizedBox(height: Spacing.lg),
                  Text('点击选择聊天记录文件',
                      style: TextStyle(
                          fontSize: SiniText.titleSm,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary)),
                  const SizedBox(height: 6),
                  Text('支持 TXT / JSON / CSV · 微信、QQ、Telegram 的导出都能认',
                      style: TextStyle(fontSize: SiniText.bodySm, color: p.textTertiary)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.xl),

        Text('文件格式',
            style: TextStyle(
                fontSize: SiniText.titleSm,
                fontWeight: FontWeight.w600,
                color: p.textPrimary)),
        const SizedBox(height: Spacing.sm),
        _chipGroup(p, _fileKinds, _fileKind, (v) => setState(() => _fileKind = v)),
        const SizedBox(height: Spacing.xl),

        Text('来源平台',
            style: TextStyle(
                fontSize: SiniText.titleSm,
                fontWeight: FontWeight.w600,
                color: p.textPrimary)),
        const SizedBox(height: Spacing.sm),
        _chipGroup(p, _platforms, _platform, (v) => setState(() => _platform = v)),
        const SizedBox(height: Spacing.sm),
        Text('选「自动」就行——解析器会自己判断。选了平台会优先按它的格式来。',
            style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary)),
      ],
    );
  }

  Widget _progressCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 18, height: 18, child: _Spinner()),
              const SizedBox(width: Spacing.sm + 2),
              Expanded(
                child: Text(_stage.isEmpty ? '处理中…' : _stage,
                    style: TextStyle(
                        fontSize: SiniText.bodySm,
                        fontWeight: FontWeight.w500,
                        color: p.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 4,
              backgroundColor: p.mainBg.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation(p.brand),
            ),
          ),
          if (_fileName.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            Text('$_fileName · ${_fmtSize(_fileSize)}',
                style: TextStyle(fontSize: SiniText.labelMd, color: p.textTertiary)),
          ],
        ],
      ),
    );
  }

  Widget _errorCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: const Color(0xFFB42318)),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(_error ?? '',
                    style: TextStyle(
                        fontSize: SiniText.bodySm,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary)),
              ),
            ],
          ),
          if (_errorHint != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(_errorHint!,
                style: TextStyle(
                    fontSize: SiniText.labelMd, color: p.textSecondary, height: 1.55)),
          ],
          const SizedBox(height: Spacing.md),
          SiniButton(
            label: '重新选文件',
            onTap: _pickAndRun,
            style: SiniButtonStyle.secondary,
            height: 40,
          ),
        ],
      ),
    );
  }

  /// 解析出来但还没分析：先让用户确认"哪一方是我"（这一步错不得）
  Widget _analyzePromptCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('准备好了，开始分析',
              style: TextStyle(
                  fontSize: SiniText.bodySm,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary)),
          const SizedBox(height: Spacing.sm),
          Text('AI 会读 TA 的用词、句长、标点和口头禅，生成一份说话方式画像。',
              style: TextStyle(fontSize: SiniText.labelMd, color: p.textSecondary, height: 1.5)),
          const SizedBox(height: Spacing.md),
          SiniButton(
            label: '开始分析',
            onTap: () {
              final chat = _chat;
              if (chat == null) return;
              _runPipelineFrom(chat, _analyzedAsSelf.isEmpty ? _guessSelf(chat) : _analyzedAsSelf);
            },
            style: SiniButtonStyle.primary,
            expand: true,
            height: 44,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════ 解析结果 ═══════════════════════

  Widget _parsedCard(AppPalette p) {
    final chat = _chat!;
    final preview = chat.messages.take(5).toList();
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 18, color: p.brand),
              const SizedBox(width: Spacing.sm),
              Text('已识别',
                  style: TextStyle(
                      fontSize: SiniText.bodySm,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary)),
              const Spacer(),
              Text('${chat.platform} · ${chat.format}',
                  style: TextStyle(fontSize: SiniText.labelMd, color: p.textTertiary)),
            ],
          ),
          const SizedBox(height: Spacing.md),

          _row(p, '消息数', '${_fmtCount(chat.length)} 条'),
          if (chat.spanText.isNotEmpty) _row(p, '时间跨度', chat.spanText),
          _row(p, '读取编码', _encoding),
          if (_fileName.isNotEmpty) _row(p, '文件', '$_fileName · ${_fmtSize(_fileSize)}'),
          if (chat.note.isNotEmpty) _row(p, '解析方式', chat.note),

          // 「哪一方是你」——这一步错了整个画像就反了（实测踩过：
          // 默认猜"第一个说话的人"，而真实记录里第一个开口的往往是被克隆的那个人），
          // 所以这里必须做得足够醒目，并且明确写出"将要克隆谁"让用户一眼核对。
          const SizedBox(height: Spacing.md),
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: p.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: p.brand.withValues(alpha: 0.18), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.help_outline_rounded, size: 16, color: p.brand),
                    const SizedBox(width: Spacing.sm),
                    Text('先确认：哪一方是你？',
                        style: TextStyle(
                            fontSize: SiniText.bodySm,
                            fontWeight: FontWeight.w600,
                            color: p.textPrimary)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('选错会把「你的」语气当成 TA 的学进去，整份画像就反了。',
                    style: TextStyle(
                        fontSize: SiniText.labelMd,
                        color: p.textSecondary,
                        height: 1.45)),
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: chat.participants.take(6).map((name) {
                    final sel = name == _analyzedAsSelf;
                    return GestureDetector(
                      onTap: () => _changeSelf(name),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.md, vertical: Spacing.sm),
                        decoration: BoxDecoration(
                          color: sel ? p.textPrimary : p.mainBg,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          sel ? '我 = $name' : name,
                          style: TextStyle(
                              fontSize: SiniText.labelMd,
                              color: sel ? p.inverseOn : p.textPrimary,
                              fontWeight: sel ? FontWeight.w600 : FontWeight.w400),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  _analyzedAsSelf.isEmpty
                      ? '→ 请先点一下哪个是你'
                      : '→ 将要克隆：${_taNameOf(chat, _analyzedAsSelf)}'
                          '（${_taCountOf(chat, _analyzedAsSelf)} 条消息）'
                          '　反了？点另一个名字即可',
                  style: TextStyle(
                      fontSize: SiniText.labelMd,
                      fontWeight: FontWeight.w600,
                      color: p.brand),
                ),
              ],
            ),
          ),

          const SizedBox(height: Spacing.md),
          _divider(p),
          const SizedBox(height: Spacing.sm),
          Text('前几条长这样',
              style: TextStyle(fontSize: SiniText.labelMd, color: p.textTertiary)),
          const SizedBox(height: 6),
          for (final m in preview)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${m.sender}：${m.text.replaceAll(RegExp(r'\s+'), ' ')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: SiniText.labelMd, color: p.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  /// 「我」以外的那个人 = 要克隆的对象
  String _taNameOf(ParsedChat chat, String self) {
    for (final n in chat.participants) {
      if (n != self) return n;
    }
    return '（只有一方，无法判断）';
  }

  /// TA 在记录里的名字。判断不出来时返回空——
  /// 别把「（只有一方，无法判断）」这种提示文案当成名字存进人格。
  String _sourceNameOf(ParsedChat? chat, String self) {
    final me = self.trim();
    if (chat == null || me.isEmpty) return '';
    final n = _taNameOf(chat, me);
    return n.startsWith('（') ? '' : n.trim();
  }

  int _taCountOf(ParsedChat chat, String self) =>
      chat.messages.where((m) => m.sender != self).length;

  /// 风格画像：让用户能看见"AI 到底学到了什么"
  Widget _styleCard(AppPalette p) {
    final s = _style!;
    final stats = _stats;
    final memCount = _extract?.memories.length ?? 0;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: p.brand),
              const SizedBox(width: Spacing.sm),
              Text('画像生成完成',
                  style: TextStyle(
                      fontSize: SiniText.bodySm,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary)),
              const Spacer(),
              SiniStatusPill(
                label: _usedLlm ? 'AI 分析' : '本地统计',
                tone: _usedLlm ? SiniStatusTone.success : SiniStatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),

          if (widget.createMode)
            SiniTextField(
              controller: _nameCtl,
              label: '识别到的名字（可修改）',
              hintText: 'TA 叫什么名字',
              onChanged: (_) => setState(() {}),
            ),
          if (widget.createMode) const SizedBox(height: Spacing.md),

          if (s.summary.isNotEmpty) ...[
            _row(p, '语言风格', s.summary),
          ],
          if (s.callUser.isNotEmpty) _row(p, '称呼', s.callUser),
          // 明确写出"画像对象是谁"——选反了的时候，用户在这里能一眼看出来
          if (stats != null)
            _row(p, '画像对象',
                '${stats.taName}（${_fmtCount(stats.taCount)} 条消息）'),
          if (stats != null && stats.days > 0) _row(p, '时间跨度', '${stats.days} 天'),

          if (s.catchphrases.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            _miniTitle(p, '口头禅'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: s.catchphrases
                  .map((c) => _tag(p, c))
                  .toList(),
            ),
          ],

          if (s.speechHabits.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            _miniTitle(p, '说话习惯'),
            const SizedBox(height: 6),
            for (final h in s.speechHabits)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('· $h',
                    style: TextStyle(
                        fontSize: SiniText.labelMd, color: p.textSecondary, height: 1.45)),
              ),
          ],

          if (s.topWords.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            _miniTitle(p, '高频用词'),
            const SizedBox(height: 6),
            Text(s.topWords.take(14).join(' · '),
                style: TextStyle(fontSize: SiniText.labelMd, color: p.textSecondary)),
          ],

          if (s.sampleLines.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            _miniTitle(p, 'TA 的原话（会作为范例教给 AI）'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: p.mainBg,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in s.sampleLines.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(l.replaceAll(RegExp(r'\s+'), ' '),
                          style: TextStyle(
                              fontSize: SiniText.labelMd,
                              color: p.textSecondary,
                              height: 1.4)),
                    ),
                ],
              ),
            ),
          ],

          if (memCount > 0) ...[
            const SizedBox(height: Spacing.sm),
            Text('顺便记下了 $memCount 条共同经历/事实，会作为 TA 的长期记忆。',
                style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary)),
          ],
          if (!_usedLlm) ...[
            const SizedBox(height: Spacing.sm),
            Text('当前是本地统计版画像。在「设置 · 模型」里配一个模型后重新导入，复刻会更像。',
                style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary)),
          ],
        ],
      ),
    );
  }

  Widget _row(AppPalette p, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary)),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(v,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: SiniText.bodySm, color: p.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _miniTitle(AppPalette p, String t) => Text(t,
      style: TextStyle(
          fontSize: SiniText.labelMd,
          fontWeight: FontWeight.w600,
          color: p.textSecondary));

  Widget _tag(AppPalette p, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: p.mainBg,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(t,
            style: TextStyle(fontSize: SiniText.labelMd, color: p.textPrimary)),
      );

  Widget _divider(AppPalette p) => Container(height: 0.5, color: p.border);

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  // ═══════════════════════ 补充素材（照片 / 声音）═══════════════════════

  /// 未开放的素材卡：占位、可点（点了说明后续会怎么接），但绝不假装导入成功
  Widget _upcomingCard(
    AppPalette p, {
    required IconData icon,
    required String title,
    required String hint,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.xl),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: p.itemHover.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(
              color: p.border,
              width: 1,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 22, color: p.textTertiary),
                  const Spacer(),
                  Icon(Icons.lock_outline_rounded, size: 13, color: p.textTertiary),
                ],
              ),
              const SizedBox(height: Spacing.md),
              Text(title,
                  style: TextStyle(
                      fontSize: SiniText.bodySm + 0.5,
                      fontWeight: FontWeight.w600,
                      color: p.textSecondary)),
              const SizedBox(height: 4),
              Text(hint,
                  style: TextStyle(
                      fontSize: SiniText.labelMd, color: p.textTertiary)),
              const SizedBox(height: Spacing.md),
              const SiniStatusPill(label: '开发中', tone: SiniStatusTone.neutral),
            ],
          ),
        ),
      ),
    );
  }

  /// 声音克隆是**真能用的**，所以这里不是占位卡：点进去就是克隆页。
  /// 已经给当前人格克隆过音色时，顺带把「上次用的是哪段样本」显示出来。
  Widget _voiceCard(AppPalette p) {
    final state = AppStateScope.of(context);
    // 创建模式：声音还是草稿（人格没建），看 AppState 的草稿；应用模式：看人格身上的
    final voice = widget.createMode
        ? state.draftVoice
        : state.activePersona?.voice;
    final hasVoice = voice != null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.xl),
        onTap: _openVoiceClone,
        child: Container(
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: p.itemHover,
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: p.brand.withValues(alpha: 0.32), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.graphic_eq_rounded, size: 22, color: p.brand),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: p.textTertiary),
                ],
              ),
              const SizedBox(height: Spacing.md),
              Text(hasVoice ? '重新克隆声音' : '导入声音',
                  style: TextStyle(
                      fontSize: SiniText.bodySm + 0.5,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary)),
              const SizedBox(height: 4),
              Text(
                  hasVoice
                      ? '当前音色：${voice.sourceLabel}'
                      : '让 TA 有声音',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: SiniText.labelMd, color: p.textTertiary)),
              const SizedBox(height: Spacing.md),
              SiniStatusPill(
                label: hasVoice
                    ? (widget.createMode ? '已克隆 · 待随人格创建' : '已克隆')
                    : '已支持',
                tone: hasVoice ? SiniStatusTone.success : SiniStatusTone.neutral,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 进声音克隆页。
  /// - 应用模式：把目标人格 id 通过路由参数带给克隆页，保存直接落到 TA。
  /// - 创建模式：人格还没建出来，带 create=1 —— 声音会暂存成草稿，
  ///   点「保存并创建」时随人格一起落库，名字以创建页填的为准。
  void _openVoiceClone() {
    if (widget.createMode) {
      Navigator.of(context).pushNamed('$_voiceCloneRoute?create=1');
      return;
    }
    final target = AppStateScope.read(context).activePersona;
    if (target == null) {
      Navigator.of(context).pushNamed(_voiceCloneRoute);
      return;
    }
    Navigator.of(context)
        .pushNamed('$_voiceCloneRoute?persona=${Uri.encodeComponent(target.id)}');
  }

  /// 还没开放的素材说明（现在只剩照片）
  void _showUpcomingSheet(String what) {
    showSiniSheet<void>(
      context: context,
      title: '$what · 开发中',
      subtitle: what.contains('声音')
          ? '声音克隆重构中，暂时先关掉入口。等稳定性调好再开放，避免半成品体验。'
          : '之后你可以上传几张 TA 的照片，AI 会还原 TA 的样子，'
              '用在头像、说话配图和视频通话里。',
      primary: ('知道了', () => Navigator.of(context).pop()),
    );
  }

  // ═══════════════════════ 小工具 ═══════════════════════

  Widget _sectionTitle(AppPalette p, String text) {
    return Text(text,
        style: TextStyle(
            fontSize: SiniText.titleSm,
            fontWeight: FontWeight.w600,
            color: p.textPrimary));
  }

  Widget _chipGroup(AppPalette p, List<String> items, String selected,
      void Function(String) onTap) {
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: items.map((s) {
        final sel = s == selected;
        return GestureDetector(
          onTap: () => onTap(s),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg, vertical: Spacing.sm + 2),
            decoration: BoxDecoration(
              color: sel ? p.textPrimary : p.itemHover,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Text(s,
                style: TextStyle(
                    fontSize: SiniText.bodySm,
                    color: sel ? p.inverseOn : p.textPrimary,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
          ),
        );
      }).toList(),
    );
  }

  Widget _secondaryLink(AppPalette p,
      {required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm, vertical: Spacing.sm + 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: p.textSecondary),
              const SizedBox(width: Spacing.sm),
              Text(label,
                  style: TextStyle(
                      fontSize: SiniText.labelLg,
                      color: p.textSecondary,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 进度小圆环：颜色跟随品牌绿（放到独立 widget 里，避免每次 build 重新建动画）
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return CircularProgressIndicator(
      strokeWidth: 2,
      valueColor: AlwaysStoppedAnimation(p.brand),
    );
  }
}
