/// 多平台 / 多格式聊天记录解析器。
///
/// 设计取向：**不做「精确匹配某一种导出格式」**，因为现实里同一平台有十几款
/// 导出工具（MemoTrace / chatlog / 各类 fork），字段名和排版各不相同，
/// 穷举必然漏。这里改成「多个解析器各自尝试 + 打分竞争」，谁解析出来的结果
/// 最像真实聊天（消息覆盖率高、时间戳全、有来有回）就用谁：
///
///   JSON 解析器 ─┐
///   CSV  解析器 ─┼─→ 打分 → 取最高分
///   TXT  解析器 ─┘
///
/// TXT 又内部尝试 4 种行格式（时间+名字换行、[时间] 名字: 内容、名字+时间换行、
/// 名字: 内容），同样按覆盖率和时间戳比例决胜。这样即使遇到没见过的导出变体，
/// 也大概率能被其中一种命中。
///
/// 平台提示（微信 / QQ / Telegram）只做**加权**，不做硬限制——
/// 用户选错平台也不至于解析不出来。
library;

import 'dart:convert';

import 'chat_models.dart';

/// 解析入口：返回最佳结果；完全解析不出返回 null。
///
/// [platformHint] / [formatHint] 都只是**加权**，不是硬限制——
/// 用户选错平台或格式时，正确的那份结果仍然能被挑出来（只是分数低一点）。
/// 传 '通用' / '自动' 表示不干预。
ParsedChat? parseChatText(
  String raw, {
  String platformHint = '通用',
  String formatHint = '自动',
}) {
  if (raw.trim().isEmpty) return null;

  final candidates = <ParsedChat>[
    ..._parseJson(raw, platformHint),
    ..._parseCsv(raw, platformHint),
    ..._parseTxt(raw, platformHint),
  ]..removeWhere((c) => c.messages.isEmpty);

  if (candidates.isEmpty) return null;

  // 用户明确选了格式 / 平台 → 给匹配的候选加权
  double bonus(ParsedChat c) {
    var b = 0.0;
    if (formatHint != '自动' && c.format == formatHint) b += 0.15;
    if (platformHint != '通用' && c.platform == platformHint) b += 0.1;
    return b;
  }

  candidates.sort((a, b) =>
      (b.confidence + bonus(b)).compareTo(a.confidence + bonus(a)));
  final best = candidates.first;

  // 置信度太低说明只是勉强凑出几条，不如让用户看到「解析失败」并换格式重试
  if (best.confidence + bonus(best) < 0.25) return null;
  return best;
}

// ═══════════════════════════ 公共工具 ═══════════════════════════

/// 时间戳正则（覆盖 2023-01-01 12:00:00 / 2023/1/1 12:00 / 2023年1月1日 12:00 /
/// ISO 的 2023-01-01T12:00:00 等主流写法）
final RegExp _timeRe = RegExp(
  r'(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})日?'
  r'[T\s]+(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?',
);

/// 从任意字符串里抠出时间；抠不到返回 null。
DateTime? parseChatTime(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;

  final m = _timeRe.firstMatch(t);
  if (m != null) {
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    final h = int.tryParse(m.group(4)!) ?? 0;
    final mi = int.tryParse(m.group(5)!) ?? 0;
    final se = int.tryParse(m.group(6) ?? '') ?? 0;
    if (y != null && mo != null && d != null && mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
      return DateTime(y, mo, d, h.clamp(0, 23), mi.clamp(0, 59), se.clamp(0, 59));
    }
  }

  // 纯数字时间戳（秒 / 毫秒）
  if (RegExp(r'^\d{10}$').hasMatch(t)) {
    return DateTime.fromMillisecondsSinceEpoch(int.parse(t) * 1000);
  }
  if (RegExp(r'^\d{13}$').hasMatch(t)) {
    return DateTime.fromMillisecondsSinceEpoch(int.parse(t));
  }

  // ISO 8601（Telegram 的 2023-01-01T12:00:00，无秒也认）
  final iso = DateTime.tryParse(t);
  if (iso != null) return iso;
  return null;
}

/// 媒体 / 表情 这类占位消息：对学说话方式毫无价值，留着只会污染统计。
final RegExp _placeholderRe =
    RegExp(r'^[\[\(（【<].{1,12}[\]\)）】>]$');

/// 系统提示、撤回、入群、红包播报等噪声行。
final List<RegExp> _systemRes = [
  RegExp(r'^.{0,12}(撤回|撤回了)一条?消息'),
  RegExp(r'^你已添加了.{0,20}现在可以开始聊天了'),
  RegExp(r'^以下是新消息'),
  RegExp(r'^以上是打招呼的内容'),
  RegExp(r'^.{0,12}邀请.{0,12}加入了?群聊'),
  RegExp(r'^.{0,12}通过了你?的好友验证'),
  RegExp(r'^.{0,12}领取了.{0,12}的红包'),
  RegExp(r'^.{0,12}拍了拍.{0,12}'),
  RegExp(r'^.{0,12}(开启了|关闭了)朋友验证'),
  RegExp(r'^(该内容已被发布者删除|消息已发出，但被对方拒收了)'),
  RegExp(r'^\[系统消息\]'),
  RegExp(r'^-\s*(图片|视频|语音|文件|链接|位置|表情)\s*-$'), // 部分 Telegram 文本导出
];

/// 导出文件自带的分隔线与表头。QQ 消息管理器导出的 TXT 开头就是
/// `====== 消息记录 ======` 这类行，落在消息中间会把上一条消息污染掉。
final RegExp _dividerRe = RegExp(
  r'^\s*[-=_*~·—－]{4,}\s*$'
  r'|^\s*[=＝\-—*]{2,}\s*.*(消息记录|聊天记录|聊天历史|消息列表|导出时间|消息数量).*$'
  r'|^\s*(消息记录|聊天记录|聊天历史)\s*$',
);

bool isNoiseText(String t) {
  final s = t.trim();
  if (s.isEmpty) return true;
  if (_placeholderRe.hasMatch(s)) return true;
  if (_dividerRe.hasMatch(s)) return true;
  for (final r in _systemRes) {
    if (r.hasMatch(s)) return true;
  }
  return false;
}

/// 发送者名字是否可信：防止把正文里带冒号的一行误判成「名字: 内容」。
bool _looksLikeName(String s) {
  final n = s.trim();
  if (n.isEmpty || n.length > 24) return false;
  if (_timeRe.hasMatch(n)) return false;
  if (n.contains('\n')) return false;
  // 名字里不该出现这些
  if (RegExp(r'[，。！？；、,\.!\?;:：]').hasMatch(n.replaceAll(RegExp(r'[（(].*?[)）]'), ''))) {
    return false;
  }
  // 至少要有中文 / 字母 / 数字
  return RegExp(r'[\u4e00-\u9fa5A-Za-z0-9]').hasMatch(n);
}

/// 去重 + 过滤噪声 + 清洗显示名，所有解析器出口共用。
List<ChatMessage> _clean(List<ChatMessage> input) {
  final out = <ChatMessage>[];
  String? lastKey;
  for (final m in input) {
    final text = m.text.trim();
    if (text.isEmpty || isNoiseText(text)) continue;
    final name = cleanSenderName(m.sender, isSelf: m.isSelf);
    if (name.isEmpty) continue;
    // 完全相同（同一秒、同一人、同一内容）视为导出重复，去掉
    final key = '$name|${m.time?.toIso8601String() ?? ''}|$text';
    if (key == lastKey) continue;
    lastKey = key;
    out.add(ChatMessage(sender: name, text: text, time: m.time, isSelf: m.isSelf));
  }
  return out;
}

/// 发送者显示名清洗：
/// - QQ 导出常见 `小雨(10001)` → 去掉 QQ 号；
/// - MemoTrace / chatlog 的 Talker 列可能是 `wxid_xxx` 这类内部 id →
///   统一显示为「对方」，免得画像把称呼学成 `wxid_xiaoyu`。
String cleanSenderName(String raw, {bool isSelf = false}) {
  var n = raw.trim();
  n = n.replaceFirst(RegExp(r'[(（]\d{4,12}[)）]\s*$'), '').trim();
  if (n.isEmpty) n = raw.trim();
  if (!isSelf && _looksLikeInternalId(n)) return '对方';
  return n;
}

bool _looksLikeInternalId(String n) {
  if (RegExp(r'^(wxid_|gh_|@)', caseSensitive: false).hasMatch(n)) return true;
  // 纯字母数字（无中文、无空格）且很长 —— 基本是内部 id 而不是昵称
  if (!RegExp(r'[\u4e00-\u9fa5]').hasMatch(n) &&
      RegExp(r'^[A-Za-z0-9_.\-]{12,}$').hasMatch(n)) {
    return true;
  }
  return false;
}

double _score(List<ChatMessage> msgs, {required int totalLines, required double base}) {
  if (msgs.isEmpty) return 0;
  final withTime = msgs.where((m) => m.time != null).length / msgs.length;
  final senders = msgs.map((m) => m.sender).toSet().length;
  final multi = senders >= 2 ? 1.0 : 0.35;
  final coverage = totalLines <= 0
      ? 1.0
      : (msgs.length / totalLines).clamp(0.0, 1.0);
  return (base * 0.55 + withTime * 0.25 + multi * 0.12 + coverage * 0.08)
      .clamp(0.0, 1.0);
}

double _hintBonus(String platformHint, String platform) =>
    platformHint == platform ? 0.05 : 0.0;

// ═══════════════════════════ JSON ═══════════════════════════

List<ParsedChat> _parseJson(String raw, String hint) {
  final text = raw.trim();
  // 允许带 BOM / 前置空行
  final start = text.indexOf(RegExp(r'[\{\[]'));
  if (start < 0) return const [];
  final sliced = text.substring(start);

  dynamic data;
  try {
    data = jsonDecode(sliced);
  } catch (_) {
    return const [];
  }

  final out = <ParsedChat>[];

  // ── 形态 A：Telegram 官方 result.json ─────────────────────────
  if (data is Map && data['messages'] is List) {
    final list = data['messages'] as List;
    final msgs = <ChatMessage>[];
    var telegramish = 0;
    for (final item in list) {
      if (item is! Map) continue;
      if (item['type'] != null && item['type'] != 'message') continue;
      final from = _pickStr(item, ['from', 'from_name', 'actor']);
      final body = _flattenTelegramText(item['text']);
      if (from == null || body == null) continue;
      if (item['from_id'] != null) telegramish++;
      msgs.add(ChatMessage(
        sender: from,
        text: body,
        time: parseChatTime('${item['date']}'),
      ));
    }
    if (msgs.isNotEmpty) {
      final cleaned = _clean(msgs);
      out.add(ParsedChat(
        messages: cleaned,
        platform: 'Telegram',
        format: 'JSON',
        confidence: _score(cleaned, totalLines: msgs.length, base: 0.92) +
            _hintBonus(hint, 'Telegram') +
            (telegramish > 0 ? 0.03 : 0),
        note: telegramish > 0
            ? 'Telegram 官方导出（result.json）'
            : 'JSON · messages 数组',
      ));
    }
  }

  // ── 形态 B：通用 {messages:[...]} / {data:[...]} / 纯数组 ──────
  List<dynamic>? list;
  if (data is List) {
    list = data;
  } else if (data is Map) {
    for (final k in ['messages', 'data', 'list', 'records', 'items', '聊天记录', '消息']) {
      if (data[k] is List) {
        list = data[k] as List;
        break;
      }
    }
  }
  if (list != null && list.isNotEmpty) {
    final msgs = <ChatMessage>[];
    var selfFlagged = 0;
    for (final item in list) {
      if (item is! Map) continue;
      final sender = _pickStr(item, [
        'sender', 'from', 'name', 'nickname', 'speaker', 'talker', 'user',
        'sendername', 'from_name', '发送者', '发送人', '昵称', '名字', '好友', '聊天对象', '发送方',
      ]);
      final body = _pickStr(item, [
        'content', 'text', 'message', 'msg', 'body', 'plainText',
        '内容', '消息内容', '消息', '文本',
      ]);
      if (sender == null || body == null) continue;

      final timeRaw = _pickAny(item, [
        'time', 'date', 'timestamp', 'createTime', 'create_time', 'createdAt', 'created_at', 'sendTime', 'StrTime',
        '时间', '创建时间', '发送时间', '日期',
      ]);
      final selfRaw = _pickAny(item, ['isSelf', 'is_sender', 'IsSender', 'self', 'isMe', 'is_me', '是否发送者', '是否本人']);
      final isSelf = _truthy(selfRaw);
      if (selfRaw != null) selfFlagged++;

      msgs.add(ChatMessage(
        sender: sender,
        text: body,
        time: timeRaw == null ? null : parseChatTime('$timeRaw'),
        isSelf: isSelf,
      ));
    }
    if (msgs.isNotEmpty) {
      final cleaned = _clean(msgs);
      final plat = _guessPlatformFromKeys(list, hint);
      out.add(ParsedChat(
        messages: cleaned,
        platform: plat,
        format: 'JSON',
        confidence: _score(cleaned, totalLines: msgs.length, base: 0.88) +
            _hintBonus(hint, plat) +
            (selfFlagged > 0 ? 0.03 : 0),
        note: 'JSON · 通用消息数组${selfFlagged > 0 ? '（含发送者标识）' : ''}',
      ));
    }
  }

  return out;
}

/// Telegram 的 text 既可能是字符串，也可能是实体数组，还可能是 null（媒体消息）
String? _flattenTelegramText(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is List) {
    final buf = StringBuffer();
    for (final part in v) {
      if (part is String) {
        buf.write(part);
      } else if (part is Map && part['text'] is String) {
        buf.write(part['text']);
      }
    }
    final s = buf.toString();
    return s.isEmpty ? null : s;
  }
  return null;
}

dynamic _pickAny(Map m, List<String> keys) {
  for (final k in keys) {
    for (final entry in m.entries) {
      if (entry.key.toString().toLowerCase() == k.toLowerCase()) {
        final v = entry.value;
        if (v != null && '$v'.trim().isNotEmpty) return v;
      }
    }
  }
  return null;
}

String? _pickStr(Map m, List<String> keys) {
  final v = _pickAny(m, keys);
  if (v == null) return null;
  if (v is Map) {
    // 形如 sender: {name: "张三"} 的嵌套结构
    final nested = _pickStr(v, ['name', 'nickname', 'display', '昵称', '名字', 'uid']);
    return nested;
  }
  final s = '$v'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

bool _truthy(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = '$v'.toLowerCase().trim();
  return s == 'true' || s == '1' || s == 'yes' || s == '是' || s == 'self';
}

/// 从字段名上判断是哪家导出的
String _guessPlatformFromKeys(List<dynamic> list, String hint) {
  for (final item in list.take(20)) {
    if (item is! Map) continue;
    final keys = item.keys.map((k) => k.toString().toLowerCase()).toSet();
    if (keys.contains('issender') || keys.contains('talker')) return '微信';
    if (keys.contains('from_id')) return 'Telegram';
    if (keys.contains('uin') || keys.contains('qq')) return 'QQ';
  }
  return hint == '通用' ? '通用' : hint;
}

// ═══════════════════════════ CSV ═══════════════════════════

List<ParsedChat> _parseCsv(String raw, String hint) {
  final lines = raw.split('\n');
  if (lines.length < 2) return const [];

  // 取第一行有效内容当表头
  String? headerLine;
  for (final l in lines) {
    if (l.trim().isNotEmpty) {
      headerLine = l;
      break;
    }
  }
  if (headerLine == null) return const [];
  if (!headerLine.contains(',') && !headerLine.contains('\t')) return const [];

  final delim = (headerLine.contains('\t') && !headerLine.contains(',')) ? '\t' : ',';
  final rows = _splitCsv(raw, delim);
  if (rows.length < 2) return const [];

  final header = rows.first.map((h) => h.trim().toLowerCase().replaceAll('"', '')).toList();

  int? find(List<String> names) {
    for (final n in names) {
      final i = header.indexWhere((h) => h == n.toLowerCase());
      if (i >= 0) return i;
    }
    // 退化到包含匹配
    for (final n in names) {
      final i = header.indexWhere((h) => h.contains(n.toLowerCase()));
      if (i >= 0) return i;
    }
    return null;
  }

  final iSender = find([
    'sender', 'from', 'name', 'nickname', 'speaker', 'sendername', 'from_name', 'friend', 'talker',
    '发送者', '发送人', '昵称', '名字', '好友', '聊天对象', '发送方',
  ]);
  final iContent = find([
    'content', 'text', 'message', 'msg', 'body',
    '内容', '消息内容', '消息', '文本',
  ]);
  final iTime = find([
    'time', 'date', 'timestamp', 'createtime', 'create_time', 'strtime', 'sendtime',
    '时间', '创建时间', '发送时间', '日期',
  ]);
  final iSelf = find(['issender', 'is_sender', 'isself', 'is_self', 'is me', 'selftype', '是否发送者', '是否本人']);

  if (iContent == null) return const [];

  // 只有 Talker + IsSender（MemoTrace 的典型结构）：发送者靠 IsSender 推
  final msgs = <ChatMessage>[];
  for (final row in rows.skip(1)) {
    if (row.length <= iContent) continue;
    final body = row[iContent].trim();
    if (body.isEmpty) continue;

    final rawTime = iTime != null && row.length > iTime ? row[iTime].trim() : '';
    final time = rawTime.isEmpty ? null : parseChatTime(rawTime);

    bool isSelf = false;
    if (iSelf != null && row.length > iSelf) isSelf = _truthy(row[iSelf].trim());

    String sender;
    if (iSender != null && row.length > iSender && row[iSender].trim().isNotEmpty) {
      sender = row[iSender].trim();
      // MemoTrace：Talker 存的是"对话另一方"，自己发的消息这里会是对方 id，
      // 所以 IsSender=1 时必须改写成「我」，否则会把两个人混成一个
      if (isSelf) sender = '我';
    } else {
      sender = isSelf ? '我' : '对方';
    }

    msgs.add(ChatMessage(sender: sender, text: body, time: time, isSelf: isSelf));
  }

  if (msgs.isEmpty) return const [];

  final cleaned = _clean(msgs);
  final plat = (iSelf != null) ? '微信' : (hint == '通用' ? '通用' : hint);
  return [
    ParsedChat(
      messages: cleaned,
      platform: plat,
      format: 'CSV',
      confidence: _score(cleaned, totalLines: msgs.length, base: 0.9) +
          _hintBonus(hint, plat) +
          (iSender != null ? 0.02 : 0),
      note: 'CSV · 表头识别${iSender != null ? '（含发送者列）' : ''}',
    )
  ];
}

/// 手写 CSV 切分：支持双引号包裹与 "" 转义（不引第三方依赖）
List<List<String>> _splitCsv(String s, String delim) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == delim) {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else if (c != '\r') {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

// ═══════════════════════════ TXT ═══════════════════════════

/// 一行被识别成「消息头」的结果
class _HeadMatch {
  final String name;
  final DateTime? time;
  /// 同一行里跟在头后面的正文（没有则为空）
  final String inline;
  const _HeadMatch(this.name, this.time, this.inline);
}

List<ParsedChat> _parseTxt(String raw, String hint) {
  final lines = raw.split('\n');
  final nonEmpty = lines.where((l) => l.trim().isNotEmpty).length;
  if (nonEmpty < 3) return const [];

  final out = <ParsedChat>[];

  // 逐个「行格式」跑一遍，统一收集
  for (final style in _TxtStyle.values) {
    final msgs = style == _TxtStyle.nameTimeLines
        ? _parseTxtNameTimeLines(lines)
        : _parseTxtWithStyle(lines, style);
    if (msgs.length < 3) continue;
    final cleaned = _clean(msgs);
    if (cleaned.isEmpty) continue;

    final withTime = cleaned.where((m) => m.time != null).length / cleaned.length;
    final senders = cleaned.map((m) => m.sender).toSet().length;

    String plat;
    switch (style) {
      case _TxtStyle.timeNameBlock:
      case _TxtStyle.bracketTimeInline:
        plat = hint == '通用' ? '通用' : hint;
      case _TxtStyle.nameTimeBlock:
      case _TxtStyle.nameTimeLines:
        plat = hint == '通用' ? 'QQ' : hint;
      case _TxtStyle.nameColonInline:
        plat = hint == '通用' ? '通用' : hint;
    }

    out.add(ParsedChat(
      messages: cleaned,
      platform: plat,
      format: 'TXT',
      confidence: _score(cleaned, totalLines: nonEmpty, base: 0.78) +
          _hintBonus(hint, plat) +
          (withTime > 0.5 && senders >= 2 ? 0.05 : 0),
      note: 'TXT · ${style.label}',
    ));
  }

  return out;
}

enum _TxtStyle {
  /// `2023-01-01 12:00:00 小雨` → 正文在后续行（MemoTrace / chatlog / 老版 QQ 常见）
  timeNameBlock('时间 + 昵称，正文换行'),
  /// `[2023-01-01 12:00:00] 小雨: 正文`
  bracketTimeInline('时间 + 昵称 + 正文同行'),
  /// `小雨 2023-01-01 12:00:00` → 正文在后续行
  nameTimeBlock('昵称 + 时间，正文换行'),
  /// `小雨: 正文`（没有时间戳）
  nameColonInline('昵称: 正文'),
  /// 三行一组：`昵称` → `时间` → `正文`（新版 QQ 消息管理器导出的就是这个）
  nameTimeLines('昵称 / 时间 / 正文 分行');

  const _TxtStyle(this.label);
  final String label;
}

List<ChatMessage> _parseTxtWithStyle(List<String> lines, _TxtStyle style) {
  final msgs = <ChatMessage>[];
  String? curName;
  DateTime? curTime;
  final body = StringBuffer();

  void flush() {
    if (curName == null) return;
    final t = body.toString().trim();
    if (t.isNotEmpty) {
      msgs.add(ChatMessage(sender: curName!, text: t, time: curTime));
    }
    body.clear();
  }

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      // 空行在 block 模式下是消息分隔（但正文里也可能有空行，保守处理：不 flush）
      continue;
    }

    final head = _matchHead(trimmed, style);
    if (head != null) {
      flush();
      curName = head.name;
      curTime = head.time;
      body.write(head.inline);
    } else {
      if (curName == null) continue; // 头部之前的杂项（文件标题之类）丢弃
      // 导出文件自带的分隔线/表头不能并进正文——等 _clean 阶段就晚了，
      // 那时它已经和上一条消息粘成一条"不是噪声"的消息
      if (_dividerRe.hasMatch(trimmed)) continue;
      if (body.isNotEmpty) body.write('\n');
      body.write(trimmed);
    }
  }
  flush();
  return msgs;
}

_HeadMatch? _matchHead(String line, _TxtStyle style) {
  switch (style) {
    case _TxtStyle.timeNameBlock:
      // 时间在前、名字在后，同一行没有正文
      final m = _timeRe.firstMatch(line);
      if (m == null || m.start > 4) return null; // 时间必须在行首附近
      final rest = line.substring(m.end).trim();
      // 行尾可能直接跟正文（用 : 分隔），那就不是 block 模式
      if (rest.isEmpty) return null;
      final name = rest.replaceFirst(RegExp(r'^[:\-—\s]+'), '');
      if (!_looksLikeName(name)) return null;
      return _HeadMatch(name, parseChatTime(line), '');

    case _TxtStyle.bracketTimeInline:
      final m = _timeRe.firstMatch(line);
      if (m == null) return null;
      final rest = line.substring(m.end).trim();
      // 期望 "名字: 正文" / "名字：正文"
      final sep = RegExp(r'[:：]').firstMatch(rest);
      if (sep == null) return null;
      final name = rest.substring(0, sep.start).trim().replaceAll(RegExp(r'^[\]\)】\s\-—]+'), '');
      final inline = rest.substring(sep.end).trim();
      if (!_looksLikeName(name)) return null;
      if (inline.isEmpty) return null;
      return _HeadMatch(name, parseChatTime(line), inline);

    case _TxtStyle.nameTimeBlock:
      // 名字在前、时间在行尾，正文在后续行
      final m = _timeRe.firstMatch(line);
      if (m == null) return null;
      final name = line.substring(0, m.start).trim();
      if (!_looksLikeName(name)) return null;
      final after = line.substring(m.end).trim();
      if (after.isNotEmpty && !RegExp(r'^[\]\)】\s\-—]+$').hasMatch(after)) return null;
      return _HeadMatch(name, parseChatTime(line), '');

    case _TxtStyle.nameColonInline:
      final sep = RegExp(r'[:：]').firstMatch(line);
      if (sep == null || sep.start == 0) return null;
      final name = line.substring(0, sep.start).trim();
      final inline = line.substring(sep.end).trim();
      if (inline.isEmpty) return null;
      if (!_looksLikeName(name)) return null;
      // 整行长度上限，避免把正文段落当成 "名字: 内容"
      if (name.length > 16) return null;
      return _HeadMatch(name, null, inline);

    case _TxtStyle.nameTimeLines:
      // 三行格式（昵称/时间/正文各占一行）由 _parseTxtNameTimeLines 单独处理：
      // 它需要向后看一行才能判断，逐行的 _matchHead 做不到。
      return null;
  }
}

/// 新版 QQ 消息管理器导出的 TXT 是「昵称 / 时间 / 正文」三行一组：
///
///     羊乘客
///     2026年08月26日 22:04
///     nb你还真学了
///     （空行）
///
/// 关键点：**必须向后看一行**——单看"羊乘客"这行，它和普通正文没有任何区别，
/// 只有确认"下一行是个纯时间戳"才能断定这是消息头。少了这一步，
/// 整份文件会被当成一堆无主文本，解析出来是空的。
List<ChatMessage> _parseTxtNameTimeLines(List<String> lines) {
  final msgs = <ChatMessage>[];
  String? curName;
  DateTime? curTime;
  final body = StringBuffer();

  void flush() {
    if (curName == null) return;
    final t = body.toString().trim();
    if (t.isNotEmpty) {
      msgs.add(ChatMessage(sender: curName!, text: t, time: curTime));
    }
    body.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i].trim();
    if (line.isEmpty) {
      i++;
      continue;
    }

    if (i + 1 < lines.length) {
      final next = lines[i + 1].trim();
      if (_isPureTime(next) && _looksLikeName(line)) {
        flush();
        curName = line;
        curTime = parseChatTime(next);
        i += 2;
        continue;
      }
    }

    if (curName == null || _dividerRe.hasMatch(line)) {
      i++; // 消息头之前的文件标题之类，丢掉
      continue;
    }
    if (body.isNotEmpty) body.write('\n');
    body.write(line);
    i++;
  }
  flush();
  return msgs;
}

/// 整行就是一个时间戳，前后没有别的内容
bool _isPureTime(String s) {
  final m = _timeRe.firstMatch(s);
  if (m == null) return false;
  final rest = s
      .replaceRange(m.start, m.end, '')
      .replaceAll(RegExp(r'[\s\[\]\(\)【】（）\-—]'), '');
  return rest.isEmpty;
}
