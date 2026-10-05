import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Token 用量记录：每次 LLM 调用成功后记一条，持久化到本地。
/// 设置页的「用量统计」面板读这里：按模型汇总、按天看趋势。

const String _kUsageEvents = 'sini_usage_events';
const int _kMaxEvents = 1200; // 防止无限膨胀（约半年的重度使用）

class UsageEvent {
  final String providerId;
  final String modelId;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final DateTime ts;

  /// 这笔消耗当时正在对话的人格名（旧记录/无人格场景为 null，归入「未标记」）
  final String? personaName;

  const UsageEvent({
    required this.providerId,
    required this.modelId,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.ts,
    this.personaName,
  });

  Map<String, dynamic> toJson() => {
        'p': providerId,
        'm': modelId,
        'pt': promptTokens,
        'ct': completionTokens,
        'tt': totalTokens,
        't': ts.millisecondsSinceEpoch,
        if (personaName != null) 'pn': personaName,
      };

  static UsageEvent fromJson(Map<String, dynamic> j) => UsageEvent(
        providerId: j['p'] as String? ?? '',
        modelId: j['m'] as String? ?? '',
        promptTokens: j['pt'] as int? ?? 0,
        completionTokens: j['ct'] as int? ?? 0,
        totalTokens: j['tt'] as int? ?? 0,
        ts: DateTime.fromMillisecondsSinceEpoch(j['t'] as int? ?? 0),
        personaName: j['pn'] as String?,
      );
}

/// 全局单例：llm_provider 的钩子往这里投，用量页从这里读
class UsageStore extends ChangeNotifier {
  UsageStore._();
  static final UsageStore instance = UsageStore._();

  final List<UsageEvent> _events = [];
  bool _loaded = false;

  List<UsageEvent> get events => List.unmodifiable(_events);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kUsageEvents);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw);
        if (j is List) {
          _events
            ..clear()
            ..addAll(j
                .whereType<Map<String, dynamic>>()
                .map(UsageEvent.fromJson));
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> add(UsageEvent e) async {
    _events.add(e);
    if (_events.length > _kMaxEvents) {
      _events.removeRange(0, _events.length - _kMaxEvents);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kUsageEvents, jsonEncode(_events.map((x) => x.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> clear() async {
    _events.clear();
    _loaded = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUsageEvents);
  }

  /// 整库恢复后强制重读（清掉 _loaded 门闩）
  Future<void> reload() async {
    _loaded = false;
    await load();
  }

  // ---- 汇总查询 ----

  List<UsageEvent> inRange(DateTime start, [DateTime? end]) {
    return _events.where((e) =>
        e.ts.isAfter(start) && (end == null || e.ts.isBefore(end))).toList();
  }

  int totalTokens(List<UsageEvent> events) =>
      events.fold(0, (n, e) => n + e.totalTokens);

  int promptTokens(List<UsageEvent> events) =>
      events.fold(0, (n, e) => n + e.promptTokens);

  int completionTokens(List<UsageEvent> events) =>
      events.fold(0, (n, e) => n + e.completionTokens);

  /// 按模型汇总：模型名 → (tokens, 次数)，按用量降序
  List<({String modelId, int tokens, int calls})> byModel(
      List<UsageEvent> events) {
    final m = <String, ({int tokens, int calls})>{};
    for (final e in events) {
      final cur = m[e.modelId] ?? (tokens: 0, calls: 0);
      m[e.modelId] = (tokens: cur.tokens + e.totalTokens, calls: cur.calls + 1);
    }
    final list = m.entries
        .map((x) => (modelId: x.key, tokens: x.value.tokens, calls: x.value.calls))
        .toList()
      ..sort((a, b) => b.tokens.compareTo(a.tokens));
    return list;
  }

  /// 按人格汇总：人格名 → (tokens, 次数)，按用量降序
  List<({String personaName, int tokens, int calls})> byPersona(
      List<UsageEvent> events) {
    final m = <String, ({int tokens, int calls})>{};
    for (final e in events) {
      final key = e.personaName ?? '未标记';
      final cur = m[key] ?? (tokens: 0, calls: 0);
      m[key] = (tokens: cur.tokens + e.totalTokens, calls: cur.calls + 1);
    }
    final list = m.entries
        .map((x) =>
            (personaName: x.key, tokens: x.value.tokens, calls: x.value.calls))
        .toList()
      ..sort((a, b) => b.tokens.compareTo(a.tokens));
    return list;
  }

  /// 按天汇总（自然日，本地时区）：day → tokens
  List<({DateTime day, int tokens})> byDay(List<UsageEvent> events) {
    final m = <String, int>{};
    for (final e in events) {
      final key =
          '${e.ts.year}-${e.ts.month.toString().padLeft(2, '0')}-${e.ts.day.toString().padLeft(2, '0')}';
      m[key] = (m[key] ?? 0) + e.totalTokens;
    }
    final list = m.entries
        .map((x) => (
              day: DateTime.parse('${x.key} 00:00:00'),
              tokens: x.value
            ))
        .toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return list;
  }
}

/// 格式化 token 数：1234 → 1,234；12345 → 12.3k；1234567 → 1.23M
String formatTokens(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
  if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}k';
  if (n >= 1000) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
  return '$n';
}
