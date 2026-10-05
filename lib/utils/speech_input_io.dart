/// 非 Web 平台：系统语音识别（`speech_to_text`）。
library;

import 'package:speech_to_text/speech_to_text.dart';

final SpeechToText _stt = SpeechToText();
bool _inited = false;
bool _listening = false;

Future<void> startSpeech({
  required void Function(String text) onPartial,
  required void Function(String text) onFinal,
  required void Function(String message) onError,
  required String locale,
}) async {
  if (_listening) {
    await _stt.stop();
    _listening = false;
  }
  if (!_inited) {
    try {
      final ok = await _stt.initialize();
      if (!ok) {
        onError(
          '麦克风权限被拒绝，或系统语音服务不可用。\n'
          '请到系统设置 → 应用 → 似你 → 权限，允许「麦克风」；'
          '部分手机还需安装/启用「Google 语音服务」或系统听写。',
        );
        return;
      }
      _inited = true;
    } catch (e) {
      onError('初始化语音识别失败：$e\n请检查麦克风权限');
      return;
    }
  }
  try {
    // speech_to_text 在 Android 上用 zh_CN / en_US 这种下划线形式
    final loc = locale.replaceAll('-', '_');
    final locales = await _stt.locales();
    String useLoc = loc;
    if (locales.isNotEmpty) {
      final hit = locales.firstWhere(
        (e) => e.localeId == loc || e.localeId.startsWith(loc.split('_').first),
        orElse: () => locales.first,
      );
      useLoc = hit.localeId;
    }
    await _stt.listen(
      localeId: useLoc,
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      cancelOnError: true,
      onDevice: false,
      onResult: (r) {
        if (r.recognizedWords.isEmpty) return;
        if (r.finalResult) {
          onFinal(r.recognizedWords);
        } else {
          onPartial(r.recognizedWords);
        }
      },
    );
    _listening = true;
  } catch (e) {
    onError('启动语音识别失败：$e');
  }
}

void stopSpeech() {
  if (!_listening) return;
  _listening = false;
  try {
    _stt.stop();
  } catch (_) {}
}

void cancelSpeech() {
  if (!_listening) return;
  _listening = false;
  try {
    _stt.cancel();
  } catch (_) {}
}

bool speechAvailable() => true;
