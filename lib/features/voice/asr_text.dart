/// 识别结果清洗（纯 Dart，不依赖 WASM / 浏览器，方便单测）。
///
/// 单独拆出来是因为 `asr_engine.dart` 依赖 sherpa-onnx 和 js_interop，
/// 在 VM 上（`flutter test`）跑不了；而这段清洗逻辑是纯字符串处理，
/// 恰恰是最容易写错、最该有测试的部分。
library;

/// Whisper 在「没人说话 / 只有噪声」时最容易瞎编的几句话。
///
/// 这是它训练语料的残留：字幕组的片尾、YouTube 口播、感谢语。通话里如果不过滤，
/// 用户一停顿字幕就会冒出「谢谢观看」，看着像见鬼。命中就整段丢弃。
const List<String> kWhisperHallucinations = [
  '谢谢观看', '感谢观看', '谢谢大家', '谢谢各位', '感谢您的观看',
  '字幕由', '字幕组', '字幕志愿者', '请不吝点赞', '点赞订阅',
  '订阅转发', '订阅频道', '转发打赏', '打赏支持', '明镜与点点',
  '点点栏目', '下集再见', '下期再见', '我们下期', 'amara.org',
  'www.', '.com', 'http://',
];

/// 清洗识别结果：去掉纯标点、去掉 Whisper 的经典幻觉句。
///
/// 增量识别（实时字幕）时噪声段特别容易出幻觉，所以每次出字都要过一遍。
String sanitizeAsrText(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  // 只剩标点 / 空白
  if (!RegExp(r'[\u4e00-\u9fa5A-Za-z0-9]').hasMatch(t)) return '';
  final lower = t.toLowerCase();
  for (final h in kWhisperHallucinations) {
    if (lower.contains(h.toLowerCase())) {
      // 判定「整段就是在念这句幻觉」而不是「顺带提到」：
      // 文本长度和幻觉句在同一量级就丢掉。用倍数而不是固定字数，
      // 否则「字幕由 Amara.org 社区提供」这种带前后缀的变体会漏掉。
      if (t.length <= h.length * 2 + 6) return '';
    }
  }
  return t;
}
