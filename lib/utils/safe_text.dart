/// 安全截断字符串：绝不切在 UTF-16 代理对中间（emoji 会炸）。
library;

/// 安全截取前 [max] 个 UTF-16 code unit；若切点落在代理对中间，退一格。
String safeClip(String s, int max) {
  if (s.isEmpty || max <= 0) return '';
  if (s.length <= max) return s;
  var end = max;
  // 高代理在 [end-1] 且后面还有低代理 → 再退一位
  if (end < s.length && _isHighSurrogate(s.codeUnitAt(end - 1))) {
    end -= 1;
  }
  return s.substring(0, end);
}

bool _isHighSurrogate(int u) => u >= 0xD800 && u <= 0xDBFF;

/// 日志 / UI 用的短摘要
String safeHead(String s, int max) {
  final c = safeClip(s.replaceAll(RegExp(r'\s+'), ' ').trim(), max);
  return s.length > max ? '$c…' : c;
}
