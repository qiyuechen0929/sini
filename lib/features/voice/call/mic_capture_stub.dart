/// 非 Web 平台的麦克风采集占位实现。
///
/// 语音通话目前只在 Web 上跑（预览 / PWA）。移动端要接原生录音插件
/// （如 `record`），实现同样的 [MicBackend] 四个方法即可，门面和 VAD
/// 逻辑不用改。
library;

import 'dart:typed_data';

class MicBackend {
  MicBackend._();

  static bool get available => false;

  static Future<void> start(void Function(double rms) onLevel) async {
    throw UnsupportedError('语音通话目前只支持在浏览器里使用');
  }

  static Float32List? take() => null;

  static void drop() {}

  static Float32List? peek(int maxSamples) => null;

  static Future<void> mute(bool v) async {}

  static Future<void> stop() async {}

  static int get sampleRate => 16000;
}
