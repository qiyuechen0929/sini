/// 非 Web（VM / 测试 / 桌面）：没有 TextDecoder，GBK 不支持。
/// 返回 null 让门面回退到「有损 UTF-8 + 提示用户另存为 UTF-8」。
library;

import 'dart:typed_data';

String? decodeGbk(Uint8List bytes) => null;
