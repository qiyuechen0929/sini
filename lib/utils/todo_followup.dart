/// 待办确认闭环：用户随口说的「明天我…」「今晚要…」，TA 隔天会追一句。
///
/// 设计原则：
/// - 只抓**明确时间**的承诺（明天 / 今晚 / 明早…），不抓闲聊；
/// - 到点后 TA 主动问一句「那件事办了吗」，语气跟人格走，不是系统闹钟；
/// - 用户说办完了/失败了就勾掉，不追问第二遍。

library;

/// 一条待确认的事
class TodoFollowUp {
  final String id;
  final String personaId;
  final String text; // 用户原话摘要
  final DateTime dueAt;
  final bool done;
  final DateTime createdAt;

  const TodoFollowUp({
    required this.id,
    required this.personaId,
    required this.text,
    required this.dueAt,
    this.done = false,
    required this.createdAt,
  });

  TodoFollowUp copyWith({bool? done}) => TodoFollowUp(
        id: id,
        personaId: personaId,
        text: text,
        dueAt: dueAt,
        done: done ?? this.done,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'personaId': personaId,
        'text': text,
        'dueAt': dueAt.millisecondsSinceEpoch,
        'done': done,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  static TodoFollowUp fromJson(Map<String, dynamic> j) => TodoFollowUp(
        id: j['id'] as String? ?? '',
        personaId: j['personaId'] as String? ?? '',
        text: j['text'] as String? ?? '',
        dueAt: DateTime.fromMillisecondsSinceEpoch(j['dueAt'] as int? ?? 0),
        done: j['done'] as bool? ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            j['createdAt'] as int? ?? 0),
      );
}

/// 是否像「已办完 / 没办成」的闭环回复
bool looksLikeTodoDone(String userText) {
  return RegExp(
    r'办完了|搞定了|弄好了|交了|做了|完成了|搞定|弄完了|'
    r'没做成|没来得及|忘了|失败|做不了|来不及|取消了',
  ).hasMatch(userText);
}

/// 从用户消息里抽一条「有明确时间的待办」。抽不到返回 null。
/// 故意保守：只认明天/今晚/明早/明晚/后天，避免误抓。
TodoFollowUp? extractTodoFollowUp({
  required String personaId,
  required String text,
  required DateTime now,
}) {
  final t = text.trim();
  if (t.isEmpty || t.length < 6) return null;
  // 明显不是承诺
  if (RegExp(r'每天|每周|定时|自动化|帮我做个梦').hasMatch(t)) return null;
  if (!RegExp(
    r'明天|明早|明晚|今晚|今天晚上|后天',
  ).hasMatch(t)) {
    return null;
  }
  // 抽「事件」：去掉时间词前后，留一小段有意义的字
  var event = t
      .replaceAll(
        RegExp(
          r'我会|我要|我得|我要去|我准备|记得|到时候|明天早上|明天下午|明天晚上|明早|明晚|今天晚上|今晚|后天|之前|的时候',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (event.isEmpty) event = t;
  if (event.length > 36) event = '${event.substring(0, 36)}…';

  DateTime due;
  if (RegExp(r'今晚|今天晚上').hasMatch(t)) {
    due = DateTime(now.year, now.month, now.day, 22, 0);
    if (!due.isAfter(now)) due = now.add(const Duration(hours: 2));
  } else if (RegExp(r'明早|明天早上').hasMatch(t)) {
    due = DateTime(now.year, now.month, now.day + 1, 9, 30);
  } else if (RegExp(r'明晚|明天晚上').hasMatch(t)) {
    due = DateTime(now.year, now.month, now.day + 1, 21, 0);
  } else if (RegExp(r'后天').hasMatch(t)) {
    due = DateTime(now.year, now.month, now.day + 2, 10, 0);
  } else {
    // 「明天」默认次日中午
    due = DateTime(now.year, now.month, now.day + 1, 12, 0);
  }

  return TodoFollowUp(
    id: 'todo_${now.microsecondsSinceEpoch}',
    personaId: personaId,
    text: event,
    dueAt: due,
    createdAt: now,
  );
}

/// TA 追问用的短句（模板；真正的人格口吻由系统提示再包一层可选）
String buildTodoNudgeLine(String todoText) {
  return '对了，之前说的「$todoText」，办得怎么样了？';
}
