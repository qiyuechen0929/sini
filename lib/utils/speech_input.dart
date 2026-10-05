import 'speech_input_stub.dart'
    if (dart.library.io) 'speech_input_io.dart'
    if (dart.library.js_interop) 'speech_input_web.dart' as impl;

/// 语音输入（STT）跨平台门面。
/// Web：Web Speech API；Android/iOS：系统 speech_to_text。
class SpeechInput {
  bool get available => impl.speechAvailable();

  Future<void> start({
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
    required void Function(String message) onError,
    String locale = 'zh-CN',
  }) {
    return impl.startSpeech(
      onPartial: onPartial,
      onFinal: onFinal,
      onError: onError,
      locale: locale,
    );
  }

  void stop() => impl.stopSpeech();
  void cancel() => impl.cancelSpeech();
}
