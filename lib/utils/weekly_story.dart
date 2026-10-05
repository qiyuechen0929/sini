/// 每周故事：基于一周聊天/回忆，自动生成「这一周我们的故事」。

library;

/// 一周故事
class WeeklyStory {
  final String id;
  final String personaId;
  final String title; // 如「2026-09-08 ~ 09-14」
  final String body; // 故事正文
  final DateTime weekStart;
  final DateTime weekEnd;
  final DateTime createdAt;

  const WeeklyStory({
    required this.id,
    required this.personaId,
    required this.title,
    required this.body,
    required this.weekStart,
    required this.weekEnd,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'personaId': personaId,
        'title': title,
        'body': body,
        'weekStart': weekStart.millisecondsSinceEpoch,
        'weekEnd': weekEnd.millisecondsSinceEpoch,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  static WeeklyStory fromJson(Map<String, dynamic> j) => WeeklyStory(
        id: j['id'] as String? ?? '',
        personaId: j['personaId'] as String? ?? '',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        weekStart: DateTime.fromMillisecondsSinceEpoch(j['weekStart'] as int? ?? 0),
        weekEnd: DateTime.fromMillisecondsSinceEpoch(j['weekEnd'] as int? ?? 0),
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int? ?? 0),
      );
}

/// 本周一 00:00
DateTime weekStartOf(DateTime d) {
  final date = DateTime(d.year, d.month, d.day);
  // Dart weekday: Mon=1 .. Sun=7
  final diff = date.weekday - DateTime.monday;
  return date.subtract(Duration(days: diff));
}

String weekLabel(DateTime start, DateTime end) {
  String md(DateTime t) => '${t.month}/${t.day}';
  return '${md(start)} ~ ${md(end)}';
}

/// 是否该生成本周故事：周日晚 18:00 后，且本周还没生成过
bool shouldGenerateWeeklyStory({
  required DateTime now,
  required DateTime? lastGeneratedWeekStart,
}) {
  if (now.weekday != DateTime.sunday) return false;
  if (now.hour < 18) return false;
  final thisWeek = weekStartOf(now);
  if (lastGeneratedWeekStart != null &&
      lastGeneratedWeekStart.year == thisWeek.year &&
      lastGeneratedWeekStart.month == thisWeek.month &&
      lastGeneratedWeekStart.day == thisWeek.day) {
    return false;
  }
  return true;
}

/// 给模型的素材：本周消息摘要 + 回忆
String buildWeeklyStoryMaterial({
  required String personaName,
  required String chatDigest,
  required List<String> momentTitles,
}) {
  final b = StringBuffer()
    ..writeln('[本周素材 · 用于写「这一周我们的故事」]')
    ..writeln('人格：$personaName')
    ..writeln('--- 本周聊天摘录 ---')
    ..writeln(chatDigest);
  if (momentTitles.isNotEmpty) {
    b.writeln('--- 本周值得记住的事 ---');
    for (final t in momentTitles) {
      b.writeln('- $t');
    }
  }
  return b.toString();
}

/// system prompt：让 TA 用自己的口吻写周记
String weeklyStorySystemPrompt(String personaName) {
  return '''
你是「$personaName」。请根据下面的素材，写一篇「这一周我们的故事」。

要求：
- 用 $personaName 的说话风格（短句、口语、有情绪，不要书面总结腔）
- 不要列 1.2.3.，不要「本周总结」这种标题党
- 200～400 字，像深夜给对方写的短信/便签
- 有具体的事、小细节、一点点温度；没素材的部分就略过，不要编造大事件
- 可以带一点俏皮或关心，禁止 AI 腔（不要「综上」「希望对你有帮助」）
- 只输出正文，不要额外解释
''';
}
