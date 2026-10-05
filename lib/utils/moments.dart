/// 回忆册 · 关系时间线
///
/// 把「一起经历过的值得记住的瞬间」沉淀成可翻阅的时刻列表。
/// 首版：手动标记 + 简单自动抽取；TA 可在合适时候自然提到。

library;

/// 一条回忆时刻
class MemoryMoment {
  final String id;
  final String personaId;
  final String title; // 一句话标题
  final String? detail; // 可选补充
  final DateTime at;
  final bool manual; // true=用户手动标记；false=自动抽取

  const MemoryMoment({
    required this.id,
    required this.personaId,
    required this.title,
    this.detail,
    required this.at,
    this.manual = false,
  });

  MemoryMoment copyWith({String? title, String? detail}) => MemoryMoment(
        id: id,
        personaId: personaId,
        title: title ?? this.title,
        detail: detail ?? this.detail,
        at: at,
        manual: manual,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'personaId': personaId,
        'title': title,
        'detail': detail,
        'at': at.millisecondsSinceEpoch,
        'manual': manual,
      };

  static MemoryMoment fromJson(Map<String, dynamic> j) => MemoryMoment(
        id: j['id'] as String? ?? '',
        personaId: j['personaId'] as String? ?? '',
        title: j['title'] as String? ?? '',
        detail: j['detail'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
        manual: j['manual'] as bool? ?? false,
      );

  /// 展示用日期
  String get dateLabel =>
      '${at.year}/${at.month.toString().padLeft(2, '0')}/${at.day.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

/// 手动标记时从原文截一句做标题
String momentTitleFromText(String text, {int max = 40}) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return '一次对话';
  if (t.length <= max) return t;
  return '${t.substring(0, max)}…';
}

/// 自动抽取：从「用户 + TA」最近消息里挑值得记的事。
/// 规则故意保守，宁可少记不要垃圾时间线。
///
/// 返回 null 表示这条不该进回忆册。
String? extractMomentTitle({
  required String userText,
  required String assistantText,
}) {
  final u = userText.trim();
  final a = assistantText.trim();
  if (u.length < 8) return null;

  // 明确的纪念性/决定性时刻
  final strong = RegExp(
    r'在一起|复合|结婚|求婚|在一起吧|'
    r'生日|纪念日|周年|毕业|录取|上岸|'
    r'搬家|换城市|离职|入职|'
    r'官宣|分手|和好|道歉|原谅|'
    r'我今天|这次考试|面试|体检|手术',
  );
  if (!strong.hasMatch(u)) return null;

  // 太短或太像指令/闲聊噪声
  if (RegExp(r'^(好的|嗯|哦|好|行|ok|OK)$').hasMatch(u)) return null;

  var title = u;
  if (title.length > 36) title = '${title.substring(0, 36)}…';
  // 若 TA 回复里有更有信息量的短句，可拼一点
  if (a.isNotEmpty && a.length <= 48) {
    // 不强制拼接，保持标题=用户侧的事件更稳
  }
  return title;
}

/// 给 system prompt 用的回忆册片段（近期 8 条）
String buildMomentsDirective(List<MemoryMoment> moments) {
  if (moments.isEmpty) return '';
  final recent = [...moments]
    ..sort((x, y) => y.at.compareTo(x.at));
  final top = recent.take(8).toList();
  final b = StringBuffer()
    ..write('\n【回忆册 · 你们之间发生过的事】\n')
    ..write('这些是你们关系里值得记住的时刻。用户提到相关话题时自然接住；'
        '平时不要主动翻出来当话题，像真人偶尔想起就提一句即可，不要盘点。\n');
  for (final m in top) {
    b.write('- ${m.dateLabel} · ${m.title}\n');
  }
  return b.toString();
}
