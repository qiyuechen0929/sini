/// 聊天记录导入的**标准中间表示**。
///
/// 不管用户上传的是微信 / QQ / Telegram 的哪种导出格式，
/// 解析器都要先落成这里的 [ChatMessage] —— 后面的统计、人格提取、
/// 记忆抽取全部只认这个模型。这样"支持新平台"就只是多写一个解析器，
/// 下游一行都不用改。
library;

/// 一条标准消息。
class ChatMessage {
  /// 发送者显示名（群聊里就是各自昵称）
  final String sender;
  /// 正文（已去掉多余空白；纯图片/语音等占位已被过滤或标注）
  final String text;
  /// 时间；解析不出来时为 null
  final DateTime? time;
  /// 是否由「用户本人」发出。解析阶段若格式里带 IsSender 就直接定，
  /// 否则先全 false，等用户确认"哪一方是我"之后再统一标注。
  final bool isSelf;

  const ChatMessage({
    required this.sender,
    required this.text,
    this.time,
    this.isSelf = false,
  });

  ChatMessage copyWith({bool? isSelf}) => ChatMessage(
        sender: sender,
        text: text,
        time: time,
        isSelf: isSelf ?? this.isSelf,
      );

  /// 字符数（按 Unicode 码点算，emoji 记 1）
  int get charCount => text.runes.length;

  /// 是否是一条"真实说话"的消息（不是 [图片] [表情] 这类占位）
  bool get isMeaningfulText => text.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'sender': sender,
        'text': text,
        'time': time?.toIso8601String(),
        'isSelf': isSelf,
      };

  static ChatMessage fromJson(Map<String, dynamic> j) => ChatMessage(
        sender: j['sender'] as String? ?? '',
        text: j['text'] as String? ?? '',
        time: DateTime.tryParse(j['time'] as String? ?? ''),
        isSelf: j['isSelf'] as bool? ?? false,
      );
}

/// 一次解析的产物：消息 + 「这是谁导出的、按什么格式读的」。
class ParsedChat {
  final List<ChatMessage> messages;
  /// 识别（或用户指定）的平台：通用 / 微信 / QQ / Telegram
  final String platform;
  /// 文件格式：TXT / CSV / JSON
  final String format;
  /// 解析置信度 0~1，用于在多个候选解析器之间挑最好的那个
  final double confidence;
  /// 给人看的一句话说明（"按 MemoTrace 导出的 CSV 解析"）
  final String note;
  /// 解析过程中跳过的行数（让用户知道丢了多少）
  final int skipped;

  const ParsedChat({
    required this.messages,
    required this.platform,
    required this.format,
    this.confidence = 1,
    this.note = '',
    this.skipped = 0,
  });

  bool get isEmpty => messages.isEmpty;
  int get length => messages.length;

  /// 出现过的发送者，按消息数从多到少。
  List<String> get participants {
    final count = <String, int>{};
    for (final m in messages) {
      count[m.sender] = (count[m.sender] ?? 0) + 1;
    }
    final list = count.keys.toList()
      ..sort((a, b) => count[b]!.compareTo(count[a]!));
    return list;
  }

  /// 时间跨度文案，如 "2020.03 — 2026.09"
  String get spanText {
    DateTime? lo;
    DateTime? hi;
    for (final m in messages) {
      final t = m.time;
      if (t == null) continue;
      if (lo == null || t.isBefore(lo)) lo = t;
      if (hi == null || t.isAfter(hi)) hi = t;
    }
    if (lo == null || hi == null) return '';
    String f(DateTime d) =>
        '${d.year}.${d.month.toString().padLeft(2, '0')}';
    return f(lo) == f(hi) ? f(lo) : '${f(lo)} — ${f(hi)}';
  }

  DateTime? get startTime {
    DateTime? lo;
    for (final m in messages) {
      final t = m.time;
      if (t == null) continue;
      if (lo == null || t.isBefore(lo)) lo = t;
    }
    return lo;
  }

  DateTime? get endTime {
    DateTime? hi;
    for (final m in messages) {
      final t = m.time;
      if (t == null) continue;
      if (hi == null || t.isAfter(hi)) hi = t;
    }
    return hi;
  }

  /// 消息数最多的发送者（群聊里用来给"TA 可能是谁"一个默认值）
  String get dominantSender => participants.isEmpty ? '' : participants.first;

  /// 把某个人标成"我"，其余为"TA"。这是人格保真的前提——
  /// 分不清谁是谁，学出来的风格就是两个人的混合体。
  ParsedChat withSelf(String selfName) => ParsedChat(
        messages: messages
            .map((m) => m.copyWith(isSelf: m.sender == selfName))
            .toList(),
        platform: platform,
        format: format,
        confidence: confidence,
        note: note,
        skipped: skipped,
      );
}
