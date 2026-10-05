/// 聊天记录文件的文本解码（门面）。
///
/// 这里解决一个非常实际的问题：**微信 / QQ 导出的 TXT、CSV 大量是 GBK/GB18030**，
/// 直接按 UTF-8 读会得到「锟斤拷」级别的乱码，用户会以为解析器坏了。
/// 而 Dart 标准库只带 UTF-8 —— 所以走浏览器内置的 `TextDecoder`（WHATWG 编码标准
/// 强制要求支持 gb18030），见 `text_decode_web.dart`。
///
/// 解码策略（顺序很重要）：
///  1. UTF-8 BOM → 直接 UTF-8；
///  2. 严格 UTF-8 解码成功 → 就是 UTF-8（ASCII 文件也走这条）；
///  3. 失败 → 拿 GBK 与「有损 UTF-8」两个结果比烂，谁的可疑字符少就用谁
///     （防止"UTF-8 里夹了几个坏字节"被误判成 GBK）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'text_decode_stub.dart'
    if (dart.library.js_util) 'text_decode_web.dart' as impl;

class DecodedText {
  final String text;

  /// 实际使用的编码，展示给用户（"按 GB18030 读取"）
  final String encoding;

  /// 是否解得不干净（有替换字符）——UI 应据此提示用户另存为 UTF-8
  final bool lossy;

  const DecodedText(this.text, this.encoding, {this.lossy = false});
}

/// 替换字符：解码失败时留下的小黑菱形
const String _replacement = '\uFFFD';

DecodedText decodeChatFile(Uint8List bytes) {
  if (bytes.isEmpty) return const DecodedText('', 'UTF-8');

  // 1) UTF-8 BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    final body = Uint8List.sublistView(bytes, 3);
    try {
      return DecodedText(utf8.decode(body), 'UTF-8');
    } on FormatException {
      // BOM 都对了却解不动，交给下面的通用分支
    }
  }

  // 2) 严格 UTF-8
  try {
    return DecodedText(utf8.decode(bytes), 'UTF-8');
  } on FormatException {
    // 继续
  }

  // 3) GBK vs 有损 UTF-8，比谁更干净
  final lossyUtf8 = utf8.decode(bytes, allowMalformed: true);
  final gbk = impl.decodeGbk(bytes);

  if (gbk == null) {
    return DecodedText(lossyUtf8, 'UTF-8(有损)', lossy: true);
  }
  final gbkBad = _badness(gbk);
  final utf8Bad = _badness(lossyUtf8);
  if (gbkBad < utf8Bad) {
    return DecodedText(gbk, 'GB18030');
  }
  return DecodedText(lossyUtf8, 'UTF-8(有损)', lossy: true);
}

/// 「有多脏」：替换字符 + 控制字符越多分越高。
/// 用来看两种解码哪个更可能正确。
int _badness(String s) {
  var bad = 0;
  for (final r in s.runes) {
    if (r == 0xFFFD) {
      bad += 10; // 明确的解码失败
    } else if (r < 0x20 && r != 0x0A && r != 0x0D && r != 0x09) {
      bad += 3; // 文本里不该出现的控制字符
    } else if (r >= 0xE000 && r <= 0xF8FF) {
      bad += 5; // 私用区，乱码典型产物
    }
  }
  return bad;
}
