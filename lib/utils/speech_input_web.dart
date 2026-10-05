import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web 端语音输入：浏览器内置 Web Speech API（SpeechRecognition）。
///
/// 用 `dart:js_interop_unsafe` 做**动态属性访问**，因此不依赖任何代码生成，
/// 也无需给 SpeechRecognition 手写 @JS 声明——不同浏览器前缀（webkit）都能兼容。

/// 当前浏览器是否支持语音识别。
bool speechAvailable() {
  return _resolveCtor() != null;
}

/// 取得 SpeechRecognition 构造函数（兼容 webkit 前缀）。
JSObject? _resolveCtor() {
  final win = globalContext;
  final a = win.getProperty('SpeechRecognition'.toJS) as JSObject?;
  if (a != null && a.isA<JSFunction>()) return a;
  final b = win.getProperty('webkitSpeechRecognition'.toJS) as JSObject?;
  if (b != null && b.isA<JSFunction>()) return b;
  return null;
}

dynamic _recognition;
bool _manualStop = false;

Future<void> startSpeech({
  required void Function(String text) onPartial,
  required void Function(String text) onFinal,
  required void Function(String message) onError,
  required String locale,
}) async {
  final ctor = _resolveCtor();
  if (ctor == null) {
    onError('当前浏览器不支持语音识别，建议改用 Chrome / Edge');
    return;
  }
  // 先清掉上一次
  cancelSpeech();

  // new SpeechRecognition()
  final rec = (ctor as JSFunction).callAsConstructor();
  _recognition = rec;
  _manualStop = false;

  String finalText = '';
  String partialText = '';

  void bind(String name, void Function(JSAny? e) handler) {
    final fn = (JSAny? e) => handler(e);
    rec.setProperty(name.toJS, fn.toJS);
  }

  bind('onstart', (e) {});

  bind('onresult', (JSAny? e) {
    if (e == null) return;
    final ev = e as JSObject;
    final resultsAny = ev.getProperty('results'.toJS);
    if (resultsAny == null) return;
    final results = resultsAny as JSObject;
    final len = (results.getProperty('length'.toJS) as JSNumber?)?.toDartInt ?? 0;
    for (int i = 0; i < len; i++) {
      final resAny = results.getProperty(i.toJS);
      if (resAny == null) continue;
      final res = resAny as JSObject;
      final altAny = res.getProperty('0'.toJS);
      final text = (altAny as JSObject?)?.getProperty('transcript'.toJS)
              .toString() ??
          '';
      final isFinal =
          (res.getProperty('isFinal'.toJS) as JSBoolean?)?.toDart ?? false;
      if (isFinal) {
        finalText += text;
      } else {
        partialText = text;
      }
    }
    final shown = (finalText + partialText).trim();
    if (shown.isNotEmpty) onPartial(shown);
  });

  bind('onerror', (JSAny? e) {
    final code =
        ((e as JSObject?)?.getProperty('error'.toJS) as JSString?)?.toDart ??
            'unknown';
    switch (code) {
      case 'not-allowed':
      case 'service-not-allowed':
        onError('麦克风权限被拒绝，请在浏览器设置里允许');
        break;
      case 'no-speech':
        onError('没有听到声音，请再试一次');
        break;
      case 'audio-capture':
        onError('找不到麦克风设备');
        break;
      case 'network':
        onError('语音识别需要联网，请检查网络');
        break;
      default:
        onError('语音识别出错（$code）');
    }
  });

  bind('onend', (JSAny? e) {
    final text = finalText.trim();
    if (text.isNotEmpty) {
      onFinal(text);
    } else if (_manualStop) {
      final tail = partialText.trim();
      if (tail.isNotEmpty) onFinal(tail);
    }
    _recognition = null;
  });

  rec.setProperty('lang'.toJS, locale.toJS);
  rec.setProperty('continuous'.toJS, true.toJS);
  rec.setProperty('interimResults'.toJS, true.toJS);
  rec.setProperty('maxAlternatives'.toJS, 1.toJS);

  try {
    (rec.getProperty('start'.toJS) as JSFunction).callAsFunction();
  } catch (err) {
    onError('无法启动语音识别：$err');
  }
}

void stopSpeech() {
  _manualStop = true;
  final rec = _recognition;
  if (rec != null) {
    try {
      (rec.getProperty('stop'.toJS) as JSFunction).callAsFunction();
    } catch (_) {}
  }
}

void cancelSpeech() {
  final rec = _recognition;
  if (rec != null) {
    try {
      (rec.getProperty('abort'.toJS) as JSFunction).callAsFunction();
    } catch (_) {}
  }
  _recognition = null;
  _manualStop = false;
}
