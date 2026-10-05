/// 非 Web 平台的语音输入占位实现。
///
/// 真机阶段（Android / iOS / 桌面）改为 `speech_to_text` 包：
/// ```dart
/// final _stt = SpeechToText();
/// speechAvailable() => await _stt.initialize();
/// startSpeech(...) => _stt.listen(onResult: (r) => ...);
/// ```
/// 本文件的函数签名保持不变，`speech_input.dart` 与 UI 无需改动。

bool speechAvailable() => false;

Future<void> startSpeech({
  required void Function(String text) onPartial,
  required void Function(String text) onFinal,
  required void Function(String message) onError,
  required String locale,
}) async {
  onError('当前平台暂不支持语音输入，请用键盘输入');
}

void stopSpeech() {}

void cancelSpeech() {}
