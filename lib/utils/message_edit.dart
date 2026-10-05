import '../models.dart';

/// 「消息撤回 / 编辑重发」的消息裁剪逻辑（纯函数，便于单测）。
///
/// 约定：一轮 = 一条用户消息 + 紧随其后的若干条助手回复。
/// - **撤回**：把整轮拿掉，回到「这句话还没说」的状态。
/// - **编辑重发**：用新文本原地替换那条用户消息，后面的助手回复同样拿掉，然后重新问一遍。
///
/// 为什么连助手回复一起拿掉：这条回复是针对旧说法生成的，留着会变成
/// 「答非所问」的孤儿气泡，而且会让模型以为自己说过那些话。

/// 对话标题的截断规则（列表里显示的短标题）。撤回 / 编辑后需要按同一规则重算。
String shortConversationTitle(String text) {
  final label = text.trim();
  if (label.isEmpty) return '新对话';
  return label.length > 24 ? '${label.substring(0, 24)}…' : label;
}

/// 找到 [msgId] 对应的**用户消息**下标；找不到或那条不是用户消息时返回 -1。
int userMessageIndex(List<Message> messages, String msgId) {
  final i = messages.indexWhere((m) => m.id == msgId);
  if (i == -1 || !messages[i].isUser) return -1;
  return i;
}

/// 第 [index] 条消息之后还剩多少条（撤回前用来提示「会一起收回 N 条」）。
int messagesAfterTurn(List<Message> messages, int index) {
  if (index < 0 || index >= messages.length) return 0;
  return messages.length - index - 1;
}

/// 这一轮的结束下标（不含）：从 index+1 开始，直到遇到下一条用户消息。
int _turnEnd(List<Message> messages, int index) {
  var end = index + 1;
  while (end < messages.length && !messages[end].isUser) {
    end++;
  }
  return end;
}

/// 撤回：删掉第 [index] 条用户消息及它引出的助手回复。
/// 下标越界时原样返回。
List<Message> cutTurn(List<Message> messages, int index) {
  if (index < 0 || index >= messages.length) return messages;
  final end = _turnEnd(messages, index);
  return [...messages.sublist(0, index), ...messages.sublist(end)];
}

/// 编辑重发：第 [index] 条用户消息换成 [newText]（时间戳刷新为现在），
/// 它引出的助手回复照旧删掉。下标越界时原样返回。
List<Message> replaceTurn(
  List<Message> messages,
  int index,
  String newText, {
  DateTime? now,
}) {
  if (index < 0 || index >= messages.length) return messages;
  final end = _turnEnd(messages, index);
  return [
    ...messages.sublist(0, index),
    messages[index].copyWith(
      content: newText,
      createdAt: now ?? DateTime.now(),
    ),
    ...messages.sublist(end),
  ];
}

/// 撤回 / 编辑后，如果对话标题原本就取自这条被改动的消息，标题要跟着变
/// （否则列表里会留着一句已经不存在的话）。返回新的标题。
String titleAfterEdit(String title, String oldText, List<Message> after) {
  if (title != shortConversationTitle(oldText)) return title;
  final firstUser = after.where((m) => m.isUser).firstOrNull;
  if (firstUser == null) return '新对话';
  return shortConversationTitle(firstUser.content);
}
