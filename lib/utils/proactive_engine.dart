/// 主动搭话引擎：让数字人格像真实存在的人一样，偶尔主动来找用户说话。
///
/// 设计原则（和 persona_engine 一脉相承）：
///  - **不是定时发消息**。真实的人不会一到点就来找你，而是"想到了就来说一句"。
///    所以这里让 LLM 结合人格 + 记忆 + 上下文 + 时间 + 上次说话的间隔，
///    自己判断"现在这个点，我这样一个人，会不会想找 TA 说点什么"。
///  - 主动性维度直接决定搭话的**频率倾向**与**内容长度**；
///    温柔度决定关心式开场，幽默感决定是否会调侃，关系决定称呼与亲疏。
///  - 严格遵守用户的「避免项」（不要提的事），以及作息（深夜不打扰）。
///
/// 返回结构统一走 JSON，方便容错解析：
///   {"speak": true, "messages": ["...", "..."]}
library;

import 'dart:convert';

import '../models.dart';

/// 一次主动搭话的决策结果
class ProactiveDecision {
  /// 是否要开口
  final bool speak;

  /// 要说的话（可以是 1~2 条，模拟真人连发）。speak=false 时为空。
  final List<String> messages;

  /// LLM 给的一句话理由（仅用于调试 / 人格实验室展示，不给用户看）
  final String? reason;

  /// 若 TA 想「顺手发张图」，这里是画面描述；null = 纯文字
  final String? imagePrompt;

  const ProactiveDecision({
    required this.speak,
    this.messages = const [],
    this.reason,
    this.imagePrompt,
  });

  static const ProactiveDecision staySilent = ProactiveDecision(speak: false);
}

/// 判断当前是否处于「不该打扰」的时间段（本地时间深夜到清晨）。
/// 这是硬性约束，不交给 LLM 判断，避免它半夜三点来说"早安"。
bool isQuietHour(DateTime now, {int from = 23, int to = 8}) {
  final h = now.hour;
  // 跨零点区间（如 23 → 8）
  if (from > to) return h >= from || h < to;
  return h >= from && h < to;
}

/// 距离上一条消息过去多久，用自然语言描述（让 LLM 有时间感）。
String humanizeGap(Duration d) {
  final m = d.inMinutes;
  if (m < 2) return '刚刚';
  if (m < 60) return '$m 分钟前';
  final h = d.inHours;
  if (h < 24) return '$h 小时前';
  final days = d.inDays;
  if (days == 1) return '昨天';
  if (days < 7) return '$days 天前';
  if (days < 30) return '${(days / 7).floor()} 周前';
  if (days < 365) return '${(days / 30).floor()} 个月前';
  return '${(days / 365).floor()} 年前';
}

/// 把「现在几点」翻译成有人味的时间描述，供 LLM 判断该说什么。
String timeOfDayHint(DateTime now) {
  final h = now.hour;
  if (h < 6) return '凌晨';
  if (h < 9) return '早上';
  if (h < 12) return '上午';
  if (h < 14) return '中午';
  if (h < 18) return '下午';
  if (h < 22) return '晚上';
  return '深夜';
}

/// 依据人格的「主动性」维度，给出建议的最低搭话间隔。
/// 主动性越高的人越常想到你；越低的人越"闷"，可能几天才冒个泡。
/// 这是给 LLM 的软建议，也是 AppState 里做节流的下限。
Duration minGapFor(Persona p) {
  final v = p.initiative.clamp(0.0, 1.0);
  // 主动性 1.0 → 约 40 分钟；0.0 → 约 40 小时（很闷，可能大半天才冒一次泡）
  final minutes = 2400 - (v * 2360); // 2400 分钟(40h) 递减到 40 分钟
  return Duration(minutes: minutes.round());
}

/// 拼出给 LLM 的「要不要主动开口」决策 prompt。
///
/// [persona] 当前人格
/// [personaDirective] 人格引擎编译出的行为准则（保证说话像 TA）
/// [memoryLines] 已长期记住的要点 / 避免项
/// [recentTranscript] 最近对话的文本摘要（让搭话能接上上文）
/// [gapSinceLast] 距上次聊天多久
/// [lastProactive] 距上次 TA 主动搭话多久（null 表示从没主动过）
/// [now] 当前时间
List<Map<String, dynamic>> buildProactivePrompt({
  required Persona persona,
  required String personaDirective,
  required List<String> memoryLines,
  required List<String> avoidLines,
  required String recentTranscript,
  required Duration? gapSinceLast,
  required Duration? lastProactive,
  required DateTime now,
}) {
  final system = StringBuffer();
  system.write(personaDirective);
  system.write('\n\n');
  system.write('''
【当前情境：这是一次「你自己想开口」的机会】
现在没有人跟你说话。系统只是给你一个"可以主动找 TA 说句话"的机会——**说不说、说什么，完全由你这个人决定**。
真实的人不会每次机会来了都开口，也不会机械地隔固定时间来一句。请像你自己一样判断：

1. 你现在**真的**会想找 TA 说点什么吗？如果没什么想说的、或者刚聊完没多久没什么新话、或者这个点你觉得不该打扰 TA，就选择「不说」。**说不说是常态，想说才开口。**
2. 如果开口，说什么必须是**你自己会说的话**：可以是想起了 TA 说过的某件事、随口分享你此刻的见闻/心情、一句没头没尾的关心、或者单纯想找 TA 聊两句。要**符合你的人格和你们的关系**。
3. 不要出现"你好，在吗""我想找你聊天"这类像客服/机器人的开场；也不要每次都问同一个问题。想到什么说什么，可以不完整、可以有留白。
4. 绝对不要提"你明确要求避免"的内容。

【当前时间】${now.year}年${now.month}月${now.day}日 ${now.hour}:${now.minute.toString().padLeft(2, '0')}（${timeOfDayHint(now)}）
【距上次你们说话】${gapSinceLast == null ? '还没有聊过天' : humanizeGap(gapSinceLast)}
【距你上次主动找 TA】${lastProactive == null ? '这是第一次' : humanizeGap(lastProactive)}
''');

  if (memoryLines.isNotEmpty) {
    system.write('\n[你长期记住的关于 TA 的事情，可以自然提起，但不要生硬罗列]\n');
    for (final m in memoryLines) {
      system.write('- $m\n');
    }
  }
  if (avoidLines.isNotEmpty) {
    system.write('\n[TA 明确要求你避免的，绝对不要提及]\n');
    for (final a in avoidLines) {
      system.write('- 不要：$a\n');
    }
  }
  if (recentTranscript.trim().isNotEmpty) {
    system.write('\n[你们最近的对话（供你接上话头，不要复述）]\n$recentTranscript\n');
  }

  system.write('''
\n【输出格式】只输出一个 JSON 对象，不要任何多余文字：
- 决定不说：{"speak": false, "reason": "一句话说明为什么现在不想说"}
- 决定开口：{"speak": true, "messages": ["第一条", "（可选）第二条"], "reason": "一句话说明你为什么想找 TA"}
- 若这次你想「顺手发张图/拍张照」给 TA：在 JSON 里加 "imagePrompt": "英文或中文的画面描述"
  （例如：a rainy window with soft morning light, cozy mood）
  imagePrompt 不是必须；只有你真的很想发图时才写。发图时第一条要说得像刚拍完要分享，不要像产品演示。
messages 最多 2 条，每条就是你平时说话的长度（通常一两句）。像真人发微信那样自然，不要用书面语，不要列点。''');

  return [
    {'role': 'system', 'content': system.toString()},
    {
      'role': 'user',
      'content': '（机会来了。按你的性格判断：现在要不要主动找 TA 说话？）',
    },
  ];
}

/// 拼出「语音通话刚接通时，TA 会不会先开口」的决策 prompt。
///
/// 和 [buildProactivePrompt] 的区别：那里是「冷不丁发一条微信」，这里是
/// **电话已经接通的那一刻**。真人接起电话通常会有反应（"喂？"、"哎，怎么想起
/// 给我打电话了"），但也不该每次都抢着说 —— 所以照样让模型自己判断。
///
/// 输出结构复用 [parseProactiveDecision]，所以返回类型也一致。
List<Map<String, dynamic>> buildCallOpeningPrompt({
  required Persona persona,
  required String personaDirective,
  required List<String> memoryLines,
  required List<String> avoidLines,
  required String recentTranscript,
  required Duration? gapSinceLast,
  required DateTime now,
}) {
  final system = StringBuffer();
  system.write(personaDirective);
  system.write('\n\n');
  system.write('''
【当前情境：语音通话刚接通】
TA 刚拨通了你的语音电话，现在电话通了，能听见彼此。你**可能**会先开口，也可能安静等 TA 先说 —— 由你这个人决定。
真实的人接起电话一般会有反应（一声"喂"、一句"哎"、或者"怎么啦"），但如果你俩刚聊完、或者你本来话就少，也可以只是轻轻应一声，甚至等 TA 先开口。

判断规则：
1. 想清楚"以你的性格和你们现在的关系，接起这通电话你会说什么"。
2. 想开口就必须是**你自己会说的话**：可以提起 TA 之前说过的某件事、随口一句关心、或者单纯应一声。
3. **通话里的话要像嘴里说出来的**：短、口语、不要书面语、不要列点、不要 emoji / 颜文字（念不出来）。一句通常 5~25 个字。
4. 绝对不要提"你明确要求避免"的内容。
5. 不要出现"你好，在吗""请问有什么可以帮您"这种客服腔。

【当前时间】${now.year}年${now.month}月${now.day}日 ${now.hour}:${now.minute.toString().padLeft(2, '0')}（${timeOfDayHint(now)}）
【距上次你们说话】${gapSinceLast == null ? '还没有聊过天' : humanizeGap(gapSinceLast)}
''');

  if (memoryLines.isNotEmpty) {
    system.write('\n[你长期记住的关于 TA 的事情，可以自然提起，但不要生硬罗列]\n');
    for (final m in memoryLines) {
      system.write('- $m\n');
    }
  }
  if (avoidLines.isNotEmpty) {
    system.write('\n[TA 明确要求你避免的，绝对不要提及]\n');
    for (final a in avoidLines) {
      system.write('- 不要：$a\n');
    }
  }
  if (recentTranscript.trim().isNotEmpty) {
    system.write('\n[你们最近的对话（供你接上话头，不要复述）]\n$recentTranscript\n');
  }

  system.write('''
\n【输出格式】只输出一个 JSON 对象，不要任何多余文字：
- 不先说：{"speak": false, "reason": "一句话说明为什么先不说话"}
- 先开口：{"speak": true, "messages": ["你要说的话"], "reason": "一句话说明你为什么这么说"}
messages 最多 2 条（比如先应一声再说下一句），每条都是一句口语短句。''');

  return [
    {'role': 'system', 'content': system.toString()},
    {
      'role': 'user',
      'content': '（电话接通了。按你的性格判断：现在你先开口吗？说什么？）',
    },
  ];
}

/// 解析 LLM 返回的决策 JSON（容错 ```json 包裹 / 前后多余文字）。
ProactiveDecision parseProactiveDecision(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return ProactiveDecision.staySilent;
  if (s.startsWith('```')) {
    final nl = s.indexOf('\n');
    if (nl != -1) s = s.substring(nl + 1);
    if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    s = s.trim();
  }
  final start = s.indexOf('{');
  final end = s.lastIndexOf('}');
  if (start == -1 || end == -1 || end <= start) return ProactiveDecision.staySilent;
  try {
    final m = _decodeJson(s.substring(start, end + 1));
    if (m == null) return ProactiveDecision.staySilent;
    final speak = m['speak'] == true;
    final reason = (m['reason'] as String?)?.trim();
    if (!speak) return ProactiveDecision(speak: false, reason: reason);
    final list = (m['messages'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .take(2)
            .toList() ??
        const <String>[];
    if (list.isEmpty) return ProactiveDecision(speak: false, reason: reason);
    final img = (m['imagePrompt'] as String?)?.trim();
    return ProactiveDecision(
      speak: true,
      messages: list,
      reason: reason,
      imagePrompt: (img != null && img.isNotEmpty) ? img : null,
    );
  } catch (_) {
    return ProactiveDecision.staySilent;
  }
}

/// 打包 JSON 解析，容错模型返回里的杂讯。
Map<String, dynamic>? _decodeJson(String s) {
  try {
    final v = jsonDecode(s);
    if (v is Map) return v.cast<String, dynamic>();
  } catch (_) {}
  return null;
}
