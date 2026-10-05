/// 引用回复相关的纯逻辑（可单测）。
///
/// 引用回复 = 长按 TA 某句话 → 引用它来追问。界面上要在气泡里显示引用块，
/// 发给模型时也要让模型知道「用户在追问的是哪一句」。

import 'safe_text.dart' show safeClip;

/// 引用块 / 引用条里显示的文本：压掉换行与多余空白，超长截断。
String quotePreview(String text, {int max = 60}) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return '';
  if (t.length <= max) return t;
  return '${safeClip(t, max)}…';
}

/// 编成模型能读懂的引用前缀，拼在用户这句话前面。
///
/// 为什么不用「@某人」这类符号：模型对自然语言的关系描述更稳，
/// 而且明确写「请针对这句话回应」能显著减少答非所问。
/// 用「你 / 我自己」而不是人格名字，避免模型误以为有第三方在场。
String buildQuotePrefix({
  required String quoteText,
  required bool quoteIsUser,
}) {
  // 模型侧不截断得太狠，否则长句引用会丢信息；200 字足够覆盖绝大多数被引用的句子
  final t = quotePreview(quoteText, max: 200);
  if (t.isEmpty) return '';
  final who = quoteIsUser ? '我自己' : '你';
  return '[我引用了$who 之前说过的一句话：「$t」，请针对这句话回应]\n';
}
