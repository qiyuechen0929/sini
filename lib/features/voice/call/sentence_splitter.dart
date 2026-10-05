/// 把 LLM 流式吐出来的文本切成「适合一句一句念」的片段。
///
/// 语音通话不能等整段回复写完再合成 —— 那样要等十几秒。所以模型吐到哪儿，
/// 我们就在句子边界切一刀，立刻把这一句送去合成。这个类负责判断
/// 「现在这个位置算不算一句话说完了」。
///
/// 三条规则：
///  1. 遇到句末标点（。！？；…!?）且缓冲长度够 → 切。
///  2. 缓冲太长还没遇到句末标点 → 在最近的逗号/顿号处切，避免一句念不完；
///     连逗号都没有就硬切（长英文、没有标点的口语）。
///  3. 短于 [minChars] 的片段不单独成句，继续攒着 —— 否则「嗯。」「好。」
///     会变成一堆几毫秒的碎片，合成开销大、听感也碎。
library;

class SentenceSplitter {
  SentenceSplitter({this.minChars = 6, this.maxChars = 48});

  /// 短于这个长度的片段不单独成句
  final int minChars;

  /// 超过这个长度强制在逗号处（或硬切）断开
  final int maxChars;

  static const String _enders = '。！？；!?;…';
  static const String _softBreaks = '，,、';

  final StringBuffer _buf = StringBuffer();

  /// 喂入增量文本，返回这次可以立刻送合成的句子（可能 0~n 句）。
  List<String> feed(String delta) {
    if (delta.isEmpty) return const [];
    _buf.write(delta);
    final out = <String>[];
    while (true) {
      final s = _take();
      if (s == null) break;
      out.add(s);
    }
    return out;
  }

  /// 文本流结束：把剩下的尾巴作为最后一句吐出（没有就返回 null）。
  String? flush() {
    final rest = _buf.toString().trim();
    _buf.clear();
    return rest.isEmpty ? null : rest;
  }

  String? _take() {
    final text = _buf.toString();
    if (text.isEmpty) return null;

    // 规则 1：找第一个「够长的句末标点」
    for (var i = 0; i < text.length; i++) {
      if (_enders.contains(text[i]) && i + 1 >= minChars) {
        return _cut(i + 1);
      }
    }
    // 规则 2：太长了还没句末标点，退而求其次在逗号处断
    if (text.length >= maxChars) {
      var cut = -1;
      for (var i = maxChars - 1; i >= minChars; i--) {
        if (i < text.length && _softBreaks.contains(text[i])) {
          cut = i + 1;
          break;
        }
      }
      if (cut > 0) return _cut(cut);
      return _cut(maxChars); // 连逗号都没有：硬切
    }
    return null;
  }

  String _cut(int end) {
    final text = _buf.toString();
    final head = text.substring(0, end).trim();
    final tail = text.substring(end);
    _buf
      ..clear()
      ..write(tail);
    return head;
  }
}
