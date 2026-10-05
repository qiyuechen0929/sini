/// 聊天记录的**本地统计层**（不调 LLM，纯 Dart）。
///
/// 为什么要有这一层：让"像不像"建立在**客观事实**上，而不是让大模型凭感觉编。
/// 这里算出来的东西有两个用途：
///  1. 直接展示给用户（平均 6 个字、几乎不用句号、爱用～）——可验证、可解释；
///  2. 作为上下文喂给 LLM，让它基于真实统计下判断，而不是猜。
///
/// 全部统计默认针对「TA」（即非本人一方）——学的是 TA 的说话方式。
library;

import '../../../models.dart' show StyleExchange;
import 'chat_models.dart';
import 'chat_parser.dart' show isNoiseText;

/// 高频词 / 口头禅候选（n-gram），带上"出现在多少条不同消息里"。
/// 用文档频率而非总频次排序：口头禅是**习惯性**的，
/// "嗯嗯"出现在 300 条不同消息里，比某个词在一句话里重复 300 次更能说明问题。
class WordCandidate {
  final String word;
  final int docFreq;
  const WordCandidate(this.word, this.docFreq);
  @override
  String toString() => '$word($docFreq)';
}

class ChatStats {
  final int total;
  final int selfCount;
  final int taCount;
  final String selfName;
  final String taName;
  final int participants;

  final DateTime? start;
  final DateTime? end;
  final int days;

  /// TA 的平均字数、最长一条
  final double taAvgChars;
  final int taMaxChars;

  /// TA 消息长度分布占比（短 ≤4 / 中 5-20 / 长 >20）
  final double shortRatio;
  final double midRatio;
  final double longRatio;

  /// 标点习惯：含该标点的消息占 TA 消息的比例
  final double periodRate;   // 。
  final double bangRate;     // ！
  final double questionRate; // ？
  final double tildeRate;    // ～ ~
  final double ellipsisRate; // … / ... / 。。。
  final double emojiRate;
  final double laughRate;    // 哈哈 / 嘿嘿 / hhh / 233
  final double newlineRate;  // 一条消息里换过行

  /// 高频词候选（已按文档频率排序、已去过冗余子串）
  final List<WordCandidate> topWords;

  /// TA 的回复延迟中位数（秒）；样本不足为 null
  final int? medianReplySeconds;

  /// TA 最活跃的时段（小时，最多 3 个）
  final List<int> activeHours;

  /// 高频短消息（≤6 字），口头禅的强信号
  final List<WordCandidate> shortPhrases;

  const ChatStats({
    required this.total,
    required this.selfCount,
    required this.taCount,
    required this.selfName,
    required this.taName,
    required this.participants,
    this.start,
    this.end,
    this.days = 0,
    this.taAvgChars = 0,
    this.taMaxChars = 0,
    this.shortRatio = 0,
    this.midRatio = 0,
    this.longRatio = 0,
    this.periodRate = 0,
    this.bangRate = 0,
    this.questionRate = 0,
    this.tildeRate = 0,
    this.ellipsisRate = 0,
    this.emojiRate = 0,
    this.laughRate = 0,
    this.newlineRate = 0,
    this.topWords = const [],
    this.medianReplySeconds,
    this.activeHours = const [],
    this.shortPhrases = const [],
  });

  /// 给 LLM 看的事实摘要（紧凑，省 token）
  String toPromptBlock() {
    final b = StringBuffer();
    b.writeln('总消息 ${_n(total)} 条：其中「$selfName」（用户本人）${_n(selfCount)} 条，'
        '「$taName」（要模仿的对象）${_n(taCount)} 条。');
    if (days > 0) {
      b.writeln('时间跨度：${_d(start)} 至 ${_d(end)}，共约 $days 天。');
    }
    if (taCount > 0) {
      b.writeln('TA 的消息平均 ${taAvgChars.toStringAsFixed(1)} 个字，'
          '最长一条 $taMaxChars 字；'
          '长度分布：很短(≤4字) ${_p(shortRatio)}、中等 ${_p(midRatio)}、长(>20字) ${_p(longRatio)}。');
    }
    final habits = <String>[];
    if (periodRate < 0.15) habits.add('极少用句号(${_p(periodRate)})');
    if (periodRate >= 0.15) habits.add('用句号(${_p(periodRate)})');
    if (bangRate > 0.1) habits.add('常用感叹号(${_p(bangRate)})');
    if (questionRate > 0.12) habits.add('常发问句(${_p(questionRate)})');
    if (tildeRate > 0.05) habits.add('爱用波浪号～(${_p(tildeRate)})');
    if (ellipsisRate > 0.05) habits.add('爱用省略号(${_p(ellipsisRate)})');
    if (emojiRate > 0.05) habits.add('常用表情符号(${_p(emojiRate)})');
    if (laughRate > 0.05) habits.add('常笑(${_p(laughRate)})');
    if (newlineRate > 0.05) habits.add('会分行发(${_p(newlineRate)})');
    if (habits.isNotEmpty) b.writeln('标点与表达习惯：${habits.join('；')}。');

    if (medianReplySeconds != null) {
      b.writeln('TA 回复用户的中位间隔约 ${_gap(medianReplySeconds!)}。');
    }
    if (activeHours.isNotEmpty) {
      b.writeln('TA 最活跃时段：${activeHours.map((h) => '$h:00-${h + 1}:00').join('、')}。');
    }
    if (shortPhrases.isNotEmpty) {
      b.writeln('高频短句（≤6字，出现次数多）：'
          '${shortPhrases.take(18).map((c) => '"${c.word}"(${c.docFreq})').join('、')}');
    }
    if (topWords.isNotEmpty) {
      b.writeln('高频词候选（按"出现在多少条消息里"排序）：'
          '${topWords.take(50).map((c) => '${c.word}(${c.docFreq})').join('、')}');
    }
    return b.toString();
  }

  static String _n(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _p(double v) => '${(v * 100).round()}%';

  static String _d(DateTime? d) =>
      d == null ? '未知' : '${d.year}.${d.month.toString().padLeft(2, '0')}';

  static String _gap(int s) {
    if (s < 60) return '$s 秒';
    if (s < 3600) return '${(s / 60).round()} 分钟';
    if (s < 86400) return '${(s / 3600).toStringAsFixed(1)} 小时';
    return '${(s / 86400).toStringAsFixed(1)} 天';
  }
}

// ═══════════════════════════ 主入口 ═══════════════════════════

ChatStats computeChatStats(ParsedChat chat) {
  final all = chat.messages;
  final ta = all.where((m) => !m.isSelf).toList();
  final self = all.where((m) => m.isSelf).toList();

  final taName = ta.isNotEmpty
      ? _dominantSender(ta)
      : (chat.participants.isNotEmpty ? chat.participants.first : 'TA');
  final selfName = self.isNotEmpty ? _dominantSender(self) : '我';

  final times = all.map((m) => m.time).whereType<DateTime>().toList()..sort();
  final start = times.isEmpty ? null : times.first;
  final end = times.isEmpty ? null : times.last;
  final days = (start == null || end == null)
      ? 0
      : end.difference(start).inDays.abs() + 1;

  final lens = ta.map((m) => m.charCount).toList();
  final avg = lens.isEmpty ? 0.0 : lens.reduce((a, b) => a + b) / lens.length;
  final maxLen = lens.isEmpty ? 0 : lens.reduce((a, b) => a > b ? a : b);

  double ratioOf(bool Function(ChatMessage) test) {
    if (ta.isEmpty) return 0;
    return ta.where(test).length / ta.length;
  }

  final short = ta.where((m) => m.charCount <= 4).length;
  final mid = ta.where((m) => m.charCount > 4 && m.charCount <= 20).length;
  final long = ta.where((m) => m.charCount > 20).length;
  final totalTa = ta.isEmpty ? 1 : ta.length;

  return ChatStats(
    total: all.length,
    selfCount: self.length,
    taCount: ta.length,
    selfName: selfName,
    taName: taName,
    participants: chat.participants.length,
    start: start,
    end: end,
    days: days,
    taAvgChars: avg,
    taMaxChars: maxLen,
    shortRatio: short / totalTa,
    midRatio: mid / totalTa,
    longRatio: long / totalTa,
    periodRate: ratioOf((m) => m.text.contains('。')),
    bangRate: ratioOf((m) => m.text.contains('！') || m.text.contains('!')),
    questionRate: ratioOf((m) => m.text.contains('？') || m.text.contains('?')),
    tildeRate: ratioOf((m) => m.text.contains('～') || m.text.contains('~')),
    ellipsisRate: ratioOf((m) => m.text.contains('…') || m.text.contains('...') || m.text.contains('。。。')),
    emojiRate: ratioOf((m) => containsEmoji(m.text)),
    laughRate: ratioOf((m) => _laughRe.hasMatch(m.text)),
    newlineRate: ratioOf((m) => m.text.contains('\n')),
    topWords: extractWordCandidates(ta.map((m) => m.text).toList(), maxResults: 60),
    medianReplySeconds: _medianReplyGap(all),
    activeHours: _activeHours(ta),
    shortPhrases: extractShortPhrases(ta.map((m) => m.text).toList()),
  );
}

String _dominantSender(List<ChatMessage> msgs) {
  final count = <String, int>{};
  for (final m in msgs) {
    count[m.sender] = (count[m.sender] ?? 0) + 1;
  }
  final keys = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
  return keys.isEmpty ? '' : keys.first;
}

final RegExp _laughRe = RegExp(r'(哈{2,}|嘿{2,}|嘻{2,}|h{3,}|233+|😂|🤣|😄|😆)');

/// 是否是 emoji（覆盖常见区段，够用）
bool containsEmoji(String s) {
  for (final r in s.runes) {
    if (r >= 0x1F300 && r <= 0x1FAFF) return true;
    if (r >= 0x1F000 && r <= 0x1F2FF) return true;
    if (r >= 0x2600 && r <= 0x27BF) return true;
    if (r >= 0x2190 && r <= 0x21FF) return true;
    if (r >= 0x2B00 && r <= 0x2BFF) return true;
    if (r == 0xFE0F || r == 0x200D) return true;
    if (r >= 0x1F1E6 && r <= 0x1F1FF) return true;
  }
  return false;
}

/// TA 回复用户的中位间隔：找每条 TA 消息前面最近的用户消息，算差值。
int? _medianReplyGap(List<ChatMessage> all) {
  final withTime = all.where((m) => m.time != null).toList();
  if (withTime.length < 6) return null;
  withTime.sort((a, b) => a.time!.compareTo(b.time!));

  final gaps = <int>[];
  for (var i = 1; i < withTime.length; i++) {
    final prev = withTime[i - 1];
    final cur = withTime[i];
    if (prev.isSelf == cur.isSelf) continue;
    final d = cur.time!.difference(prev.time!).inSeconds;
    // 超过 12 小时的当作"新的一轮"，不算回复间隔
    if (d > 0 && d < 12 * 3600) gaps.add(d);
  }
  if (gaps.length < 5) return null;
  gaps.sort();
  return gaps[gaps.length ~/ 2];
}

List<int> _activeHours(List<ChatMessage> ta) {
  final hist = <int, int>{};
  for (final m in ta) {
    final h = m.time?.hour;
    if (h == null) continue;
    hist[h] = (hist[h] ?? 0) + 1;
  }
  if (hist.isEmpty) return const [];
  final sorted = hist.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(3).map((e) => e.key).toList()..sort();
}

// ═══════════════════════════ 高频词（n-gram）═══════════════════════════

/// 中文没有空格，这里用 1~4 元组 + 文档频率做**候选召回**，
/// 再交给 LLM 筛选——大模型判断"哪个是口头禅"比任何规则都准，
/// 所以这一层的目标是"别漏"，不是"别多"。
const Set<String> _stopChars = {
  '的', '了', '是', '在', '和', '与', '就', '都', '也', '还', '有', '我', '你', '他',
  '她', '它', '们', '这', '那', '个', '不', '吗', '呢', '吧', '啊', '呀', '哦', '嗯',
  '要', '会', '能', '把', '被', '给', '让', '对', '从', '到', '向', '于', '而', '但',
  '着', '过', '很', '太', '更', '最', '一', '二', '三', '上', '下', '里', '外', '中',
};

List<WordCandidate> extractWordCandidates(List<String> texts, {int maxResults = 60}) {
  final docFreq = <String, int>{};
  for (final raw in texts) {
    // 去掉标点、表情、数字，只留中英文
    final cleaned = raw
        .replaceAll(RegExp(r'[^\u4e00-\u9fa5A-Za-z0-9]+'), ' ')
        .trim();
    if (cleaned.isEmpty) continue;
    final seen = <String>{};
    for (final seg in cleaned.split(RegExp(r'\s+'))) {
      final r = seg.runes.toList();
      if (r.length < 1) continue;
      for (var n = 1; n <= 4; n++) {
        if (r.length < n) break;
        for (var i = 0; i + n <= r.length; i++) {
          final g = String.fromCharCodes(r.sublist(i, i + n));
          if (_isJunkGram(g, n)) continue;
          seen.add(g);
        }
      }
    }
    for (final g in seen) {
      docFreq[g] = (docFreq[g] ?? 0) + 1;
    }
  }

  var list = docFreq.entries.where((e) => e.value >= 3).toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // 去掉"碎片词"：如果某个更长的词包含它、且出现次数相当（≥80%），
  // 说明它的频次基本来自那个长词（"道了" vs "知道了"），留着只是噪声。
  //
  // 注意这里必须拿**完整候选集**比较，而不是已保留的集合 —— 否则结果会随
  // 处理顺序变化（同频次的词谁先谁后不确定），同一份数据两次跑出不同结果。
  final pool = list.take(400).toList();
  final keep = <MapEntry<String, int>>[];
  for (final e in list) {
    final isFragment = pool.any((k) =>
        k.key != e.key &&
        k.key.length > e.key.length &&
        k.key.contains(e.key) &&
        k.value >= e.value * 0.8);
    if (isFragment) continue;
    keep.add(e);
    if (keep.length >= maxResults * 2) break;
  }

  keep.sort((a, b) => b.value.compareTo(a.value));
  return keep.take(maxResults).map((e) => WordCandidate(e.key, e.value)).toList();
}

bool _isJunkGram(String g, int n) {
  if (RegExp(r'^\d+$').hasMatch(g)) return true;
  // 单字：只保留语气词/拟声词这类可能是口头禅的，虚词全丢
  if (n == 1) {
    if (!RegExp(r'[\u4e00-\u9fa5]').hasMatch(g)) return true;
    return _stopChars.contains(g) || !_interjectionChars.contains(g);
  }
  // 多字：全是虚字的丢掉
  var stop = 0;
  for (final c in g.runes) {
    if (_stopChars.contains(String.fromCharCode(c))) stop++;
  }
  return stop >= n; // 每个字都是虚词 → 无意义
}

/// 单字里可能成为口头禅的**语气词 / 笑声**。
/// 注意别把"行/好/笑"这种内容词放进来 —— 它们单看毫无意义，
/// 只会让「高频用词」那块显得很脏。
const Set<String> _interjectionChars = {
  '嗯', '哦', '啊', '哈', '呵', '嘿', '嘻', '诶', '哎', '唉', '呀', '哇', '咦', '欸',
  '呃', '唔', '嗷', '呜', '嘛', '呗', '咯', '嘞', '啦', '喽', '咳', '噫', '嗨',
};

/// 高频短句（≤6 字全条消息）：口头禅最强的信号
List<WordCandidate> extractShortPhrases(List<String> texts, {int maxResults = 24}) {
  final freq = <String, int>{};
  for (final raw in texts) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    final len = t.runes.length;
    if (len > 6) continue;
    if (RegExp(r'[。，、；：！？…]').hasMatch(t.replaceAll(RegExp(r'[!?！？~～]+$'), ''))) {
      // 允许结尾带标点，但中间不能
    }
    final key = t.replaceAll(RegExp(r'[\s]+'), '');
    if (key.isEmpty) continue;
    freq[key] = (freq[key] ?? 0) + 1;
  }
  final list = freq.entries.where((e) => e.value >= 3).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return list.take(maxResults).map((e) => WordCandidate(e.key, e.value)).toList();
}

// ═══════════════════════════ 语料采样 ═══════════════════════════

/// 采样 TA 的**原话**给 LLM 当风格范例。
///
/// 采样策略很关键：不能只取最长的（会显得话痨），也不能只取最近的
/// （会偏某一时期）。按长度分层 + 按时间均匀，才能反映真实语感。
List<String> sampleTaMessages(List<ChatMessage> all, {int max = 200}) {
  final ta = all.where((m) => !m.isSelf && !isNoiseText(m.text)).toList();
  if (ta.isEmpty) return const [];

  // 按长度分三层，比例 短:中:长 = 3:5:2
  final short = ta.where((m) => m.charCount <= 4).toList();
  final mid = ta.where((m) => m.charCount > 4 && m.charCount <= 20).toList();
  final long = ta.where((m) => m.charCount > 20).toList();

  final picked = <ChatMessage>[
    ..._evenly(short, (max * 0.3).round()),
    ..._evenly(mid, (max * 0.5).round()),
    ..._evenly(long, (max * 0.2).round()),
  ];

  picked.sort((a, b) {
    final ta1 = a.time, tb = b.time;
    if (ta1 == null || tb == null) return 0;
    return ta1.compareTo(tb);
  });

  // 同样的句子最多出现 2 次，避免刷屏
  final count = <String, int>{};
  final out = <String>[];
  for (final m in picked) {
    final c = count[m.text] ?? 0;
    if (c >= 2) continue;
    count[m.text] = c + 1;
    out.add(m.text);
  }
  return out;
}

/// 按时间均匀抽 n 条
List<ChatMessage> _evenly(List<ChatMessage> list, int n) {
  if (n <= 0 || list.isEmpty) return const [];
  if (list.length <= n) return list;
  final out = <ChatMessage>[];
  final step = list.length / n;
  for (var i = 0; i < n; i++) {
    out.add(list[(i * step).floor().clamp(0, list.length - 1)]);
  }
  return out;
}

/// 纯应答词：这类配对学不到"反应模式"（"在吗"→"嗯嗯"、"哈哈"→"嘿嘿"），
/// 却会在 few-shot 里白占位置。简短说话的**风格**信息已经由
/// 说话习惯统计 + 原话样本覆盖了，问答对要用来学"怎么接话"。
/// 注意别把"不知道""也行"这类过滤掉——它们是有态度的回答。
final RegExp _pureAckRe = RegExp(
  r'^(嗯+|哦+|啊+|哈+|嘿+|嘻+|好的|好|行|可以|在的|是啊|对|对呀|收到|在|嗯哪)'
  r'[～~。！!？?\s]*$',
);

/// 采样真实「用户说 → TA 怎么回」的问答对。
/// 这是 few-shot 里最有效的一类例子：模仿的是**反应模式**，不只是用词。
List<StyleExchange> sampleExchanges(List<ChatMessage> all, {int max = 40}) {
  final withTime = all.where((m) => m.time != null).toList();
  if (withTime.length < 4) {
    // 没有时间也要能用：按相邻顺序配对
    final out = <StyleExchange>[];
    for (var i = 0; i + 1 < all.length; i++) {
      if (all[i].isSelf && !all[i + 1].isSelf) {
        if (isNoiseText(all[i].text) || isNoiseText(all[i + 1].text)) continue;
        if (_pureAckRe.hasMatch(all[i + 1].text.trim())) continue;
        out.add(StyleExchange(user: all[i].text, ta: all[i + 1].text));
      }
    }
    return out.length <= max ? out : _evenlyEx(out, max);
  }

  withTime.sort((a, b) => a.time!.compareTo(b.time!));
  final pairs = <StyleExchange>[];
  for (var i = 0; i + 1 < withTime.length; i++) {
    final cur = withTime[i];
    final nxt = withTime[i + 1];
    if (!cur.isSelf || nxt.isSelf) continue;
    final gap = nxt.time!.difference(cur.time!).inSeconds;
    if (gap > 4 * 3600) continue; // 隔太久不算同一轮
    if (isNoiseText(cur.text) || isNoiseText(nxt.text)) continue;
    if (_pureAckRe.hasMatch(nxt.text.trim())) continue;
    // 太长的样本不适合当范例（占 token 且不像日常聊天）
    if (cur.charCount > 60 || nxt.charCount > 80) continue;
    pairs.add(StyleExchange(user: cur.text, ta: nxt.text));
  }
  return pairs.length <= max ? pairs : _evenlyEx(pairs, max);
}

List<StyleExchange> _evenlyEx(List<StyleExchange> list, int n) {
  if (list.length <= n) return list;
  final out = <StyleExchange>[];
  final step = list.length / n;
  for (var i = 0; i < n; i++) {
    out.add(list[(i * step).floor().clamp(0, list.length - 1)]);
  }
  return out;
}
