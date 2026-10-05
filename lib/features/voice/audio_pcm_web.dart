/// Web 端音频解码：用浏览器的 WebAudio `decodeAudioData`。
///
/// 这是 Web 上唯一能解 mp3 / m4a / ogg / wav 各种格式的办法，
/// 而且它支持指定 AudioContext 的采样率 —— 直接要 24kHz，
/// 浏览器会在解码时顺手重采样，省掉自己写重采样器。
///
/// 实现方式说明（别改成"逐字段读 JS 对象"）：
/// 解码逻辑整体放在一段 JS 里跑，只把**最终的单声道 Float32Array**
/// 挂到 `window.__siniPcm` 交回 Dart。原因是本 SDK 版本的 `JSNumber`
/// 没有 `toDart`、`JSUint8Array` 也没有 `buffer`，逐个读 JS 字段会处处踩坑；
/// 而采样率是我们自己要求的固定值，本来就不需要读。
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'audio_pcm.dart';
import 'audio_pcm_types.dart';

bool _helperInjected = false;

/// 注入到页面里的解码助手。
/// 关键点：多声道在 JS 里就平均成单声道，Dart 侧只拿一个 Float32Array。
const String _helperJs = r'''
window.__siniDecodeAudio = function (arrayBuffer, sampleRate, done) {
  try {
    var Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) { window.__siniPcm = null; done(); return; }
    var ctx = new Ctx({ sampleRate: sampleRate });
    ctx.decodeAudioData(arrayBuffer).then(function (buf) {
      var ch = buf.numberOfChannels;
      var len = buf.length;
      var out = new Float32Array(len);
      for (var c = 0; c < ch; c++) {
        var d = buf.getChannelData(c);
        for (var i = 0; i < len; i++) { out[i] += d[i] / ch; }
      }
      try { ctx.close(); } catch (e) {}
      window.__siniPcm = out;
      done();
    }).catch(function () {
      try { ctx.close(); } catch (e) {}
      window.__siniPcm = null;
      done();
    });
  } catch (e) {
    window.__siniPcm = null;
    done();
  }
};
''';

void _ensureHelper() {
  if (_helperInjected) return;
  final eval = globalContext.getProperty('eval'.toJS) as JSFunction;
  eval.callAsFunction(null, _helperJs.toJS);
  _helperInjected = true;
}

Future<DecodedAudio?> decodeAudioBytes(Uint8List bytes) async {
  if (bytes.isEmpty) return null;
  _ensureHelper();

  final fn =
      globalContext.getProperty('__siniDecodeAudio'.toJS) as JSFunction?;
  if (fn == null) return null;

  // toJS 会复制到 JS 堆：decodeAudioData 会「转移」传入的 ArrayBuffer，
  // 若不复制会把 Dart 侧这块内存 detach 掉。
  final jsBuffer = bytes.toJS.getProperty('buffer'.toJS) as JSArrayBuffer;

  final completer = Completer<void>();
  final done = (() {
    if (!completer.isCompleted) completer.complete();
  }).toJS;

  fn.callAsFunction(
      null, jsBuffer, kReferenceSampleRate.toJS, done);

  // 坏文件可能永远不回调，给一个上限，失败也走"提示换文件"这条路
  await completer.future.timeout(
    const Duration(seconds: 25),
    onTimeout: () {},
  );

  final pcm = globalContext.getProperty('__siniPcm'.toJS);
  if (pcm.isUndefinedOrNull) return null;
  try {
    final samples = (pcm as JSFloat32Array).toDart;
    if (samples.isEmpty) return null;
    return DecodedAudio(
      samples: samples,
      sampleRate: kReferenceSampleRate,
    );
  } catch (_) {
    return null;
  } finally {
    // 清掉全局引用，别让几百 KB 的 PCM 一直挂着
    globalContext.setProperty('__siniPcm'.toJS, null);
  }
}
