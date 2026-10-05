/// Web：借浏览器内置的 TextDecoder 解 GB18030。
///
/// 为什么要绕到浏览器：Dart 标准库只有 UTF-8，而 GBK/GB18030 的映射表
/// 自己塞进包里要几百 KB。WHATWG Encoding 标准强制要求浏览器支持
/// "gb18030"，所以这条路在本项目（纯 Web 运行）是零成本且准确的。
library;

import 'dart:js_util' as jsu;
import 'dart:typed_data';

/// 解不出来返回 null（调用方自行降级），不抛异常。
String? decodeGbk(Uint8List bytes) {
  try {
    final ctor = jsu.getProperty<Object?>(jsu.globalThis, 'TextDecoder');
    if (ctor == null) return null;
    final decoder = jsu.callConstructor(ctor, <Object?>['gb18030']);
    final out = jsu.callMethod(decoder, 'decode', <Object?>[bytes]);
    return out is String ? out : null;
  } catch (_) {
    return null;
  }
}
