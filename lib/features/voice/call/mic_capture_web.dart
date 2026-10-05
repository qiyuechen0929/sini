/// Web 端麦克风采集实现：getUserMedia + AudioWorklet。
///
/// 与 `audio_pcm_web.dart` 同一套路：逻辑整体写在一段 JS 里注入页面，
/// Dart 只调几个入口函数、只把最终结果读回来 —— 避免在 Dart 侧逐个读
/// JS 字段（本 SDK 的 js_interop 在这上面坑很多）。
///
/// JS 侧只做两件事：
///  1. 每积累够 1024 个 16kHz 采样（约 64ms）就把 PCM 和这一段的响度 RMS
///     一起回调给 Dart。**不要每个 process() 回调一次** —— 那是 375 次/秒，
///     Dart 侧扛不住。
///  2. 把 PCM 攒在内存里，等 Dart 判定「这句说完了」再一次性取走。
///     Dart 侧因此不需要逐块搬运音频。
///
/// 采集用 `echoCancellation / noiseSuppression / autoGainControl` 全开：
/// 通话是外放 + 麦克风同时工作的，没有回声消除会把自己的声音录回去。
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'mic_capture.dart' show kMicSampleRate;

const String _helperJs = r'''
window.__siniMic = (function () {
  var MAX_SAMPLES = 16000 * 30;   // 最多留 30 秒，防止没人说话时缓冲无限涨

  var S = {
    ctx: null, stream: null, node: null, src: null,
    chunks: [], samples: 0, muted: false, onLevel: null, running: false
  };

  var WORKLET = [
    'class SiniMicCapture extends AudioWorkletProcessor {',
    '  constructor() {',
    '    super();',
    '    this.ratio = sampleRate / 16000;',
    '    this.acc = 0; this.out = []; this.sumSq = 0; this.n = 0;',
    '  }',
    '  process(inputs) {',
    '    var ch = inputs[0] && inputs[0][0];',
    '    if (!ch) return true;',
    '    for (var i = 0; i < ch.length; i++) {',
    '      var v = ch[i];',
    '      this.sumSq += v * v; this.n++;',
    '      this.acc += 1;',
    '      if (this.acc >= this.ratio) { this.acc -= this.ratio; this.out.push(v); }',
    '    }',
    '    if (this.out.length >= 1024) {',
    '      var i16 = new Int16Array(this.out.length);',
    '      for (var j = 0; j < this.out.length; j++) {',
    '        var x = Math.max(-1, Math.min(1, this.out[j]));',
    '        i16[j] = x < 0 ? x * 32768 : x * 32767;',
    '      }',
    '      var rms = this.n ? Math.sqrt(this.sumSq / this.n) : 0;',
    '      this.out = []; this.sumSq = 0; this.n = 0;',
    '      this.port.postMessage({ pcm: i16.buffer, rms: rms }, [i16.buffer]);',
    '    }',
    '    return true;',
    '  }',
    '}',
    'registerProcessor("sini-mic", SiniMicCapture);'
  ].join('\n');

  var MIC_CONSTRAINTS = {
    echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1
  };

  function pushBlock(i16) {
    S.chunks.push(i16);
    S.samples += i16.length;
    while (S.samples > MAX_SAMPLES && S.chunks.length > 1) {
      S.samples -= S.chunks.shift().length;
    }
  }

  function attach() {
    if (!S.ctx || !S.node || !S.stream) return;
    if (S.src) { try { S.src.disconnect(); } catch (e) {} }
    S.src = S.ctx.createMediaStreamSource(new MediaStream(S.stream.getAudioTracks()));
    S.src.connect(S.node);   // 不接 destination：别让自己听见自己
  }

  return {
    start: async function (onLevel) {
      S.onLevel = onLevel;
      S.chunks = []; S.samples = 0; S.muted = false;
      var Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        throw new Error('NotSupported: 当前浏览器不支持麦克风采集');
      }
      S.ctx = new Ctx();
      await S.ctx.resume();
      S.stream = await navigator.mediaDevices.getUserMedia({ audio: MIC_CONSTRAINTS });
      var blob = new Blob([WORKLET], { type: 'application/javascript' });
      var url = URL.createObjectURL(blob);
      try {
        await S.ctx.audioWorklet.addModule(url);
      } finally {
        URL.revokeObjectURL(url);
      }
      S.node = new AudioWorkletNode(S.ctx, 'sini-mic');
      S.node.port.onmessage = function (e) {
        var d = e.data || {};
        if (d.pcm && !S.muted) pushBlock(new Int16Array(d.pcm));
        if (S.onLevel) { try { S.onLevel(S.muted ? 0 : (d.rms || 0)); } catch (err) {} }
      };
      attach();
      S.running = true;
      return true;
    },

    /** 取走缓冲里的全部音频（16kHz 单声道 float32），并清空。 */
    take: function () {
      if (!S.chunks.length) return null;
      var out = new Float32Array(S.samples);
      var o = 0;
      for (var i = 0; i < S.chunks.length; i++) {
        var c = S.chunks[i];
        for (var j = 0; j < c.length; j++) { out[o++] = c[j] / 32768; }
      }
      S.chunks = []; S.samples = 0;
      return out;
    },

    drop: function () { S.chunks = []; S.samples = 0; },

    /**
     * 看一眼缓冲里的音频但**不清空**（增量识别用：边说话边反复取当前这段去识别）。
     * maxSamples 只取尾部这么多采样，避免字幕越说越慢。
     */
    peek: function (maxSamples) {
      if (!S.chunks.length) return null;
      var take = S.samples;
      var skip = 0;
      if (maxSamples && maxSamples > 0 && S.samples > maxSamples) {
        skip = S.samples - maxSamples;
        take = maxSamples;
      }
      var out = new Float32Array(take);
      var o = 0, pos = 0;
      for (var i = 0; i < S.chunks.length; i++) {
        var c = S.chunks[i];
        for (var j = 0; j < c.length; j++) {
          if (pos >= skip) { out[o++] = c[j] / 32768; }
          pos++;
        }
        if (o >= take) break;
      }
      return o === take ? out : out.subarray(0, o);
    },

    /** 静音 = 真的把音轨停掉（浏览器麦克风指示灯会灭）。 */
    mute: async function (v) {
      S.muted = !!v;
      if (!S.stream) return;
      if (S.muted) {
        S.stream.getAudioTracks().forEach(function (t) { try { t.stop(); } catch (e) {} });
        if (S.src) { try { S.src.disconnect(); } catch (e) {} S.src = null; }
        return;
      }
      if (S.stream.getAudioTracks().some(function (t) { return t.readyState === 'live'; })) return;
      var fresh = await navigator.mediaDevices.getUserMedia({ audio: MIC_CONSTRAINTS });
      var track = fresh.getAudioTracks()[0];
      if (!track || !S.stream || S.muted) { if (track) track.stop(); return; }
      S.stream.addTrack(track);
      attach();
    },

    stop: function () {
      S.onLevel = null;
      if (S.src) { try { S.src.disconnect(); } catch (e) {} S.src = null; }
      if (S.node) {
        try { S.node.port.onmessage = null; S.node.disconnect(); } catch (e) {}
        S.node = null;
      }
      if (S.stream) {
        S.stream.getTracks().forEach(function (t) { try { t.stop(); } catch (e) {} });
      }
      if (S.ctx) { try { S.ctx.close(); } catch (e) {} }
      S.stream = null; S.ctx = null;
      S.chunks = []; S.samples = 0; S.running = false;
    }
  };
})();
''';

bool _injected = false;

void _ensureHelper() {
  if (_injected) return;
  final eval = globalContext.getProperty('eval'.toJS) as JSFunction;
  eval.callAsFunction(null, _helperJs.toJS);
  _injected = true;
}

JSObject? _mic() {
  final v = globalContext.getProperty('__siniMic'.toJS);
  if (v.isUndefinedOrNull) return null;
  return v as JSObject;
}

class MicBackend {
  MicBackend._();

  /// Web + 有 getUserMedia 才算可用。
  static bool get available {
    final nav = globalContext.getProperty('navigator'.toJS);
    if (nav.isUndefinedOrNull) return false;
    final md = (nav as JSObject).getProperty('mediaDevices'.toJS);
    if (md.isUndefinedOrNull) return false;
    return !(md as JSObject).getProperty('getUserMedia'.toJS).isUndefinedOrNull;
  }

  static Future<void> start(void Function(double rms) onLevel) async {
    _ensureHelper();
    final mic = _mic();
    if (mic == null) throw StateError('麦克风采集模块没有注入成功');
    final fn = mic.getProperty('start'.toJS) as JSFunction;
    final cb = ((JSAny? v) {
      var rms = 0.0;
      if (v != null && !v.isUndefinedOrNull) {
        try {
          rms = (v as JSNumber).toDartDouble;
        } catch (_) {}
      }
      onLevel(rms);
    }).toJS;
    final res = fn.callAsFunction(mic, cb);
    await (res as JSPromise).toDart;
  }

  /// 取走缓冲里的音频（16kHz float32）。没有数据返回 null。
  static Float32List? take() {
    final mic = _mic();
    if (mic == null) return null;
    final fn = mic.getProperty('take'.toJS) as JSFunction;
    final r = fn.callAsFunction(mic);
    if (r.isUndefinedOrNull) return null;
    try {
      final out = (r as JSFloat32Array).toDart;
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  static void drop() {
    final mic = _mic();
    if (mic == null) return;
    (mic.getProperty('drop'.toJS) as JSFunction).callAsFunction(mic);
  }

  /// 取缓冲尾部最多 [maxSamples] 个采样（不清空）。没有数据返回 null。
  static Float32List? peek(int maxSamples) {
    final mic = _mic();
    if (mic == null) return null;
    final fn = mic.getProperty('peek'.toJS) as JSFunction;
    final r = fn.callAsFunction(mic, maxSamples.toJS);
    if (r.isUndefinedOrNull) return null;
    try {
      final out = (r as JSFloat32Array).toDart;
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  static Future<void> mute(bool v) async {
    final mic = _mic();
    if (mic == null) return;
    final fn = mic.getProperty('mute'.toJS) as JSFunction;
    final res = fn.callAsFunction(mic, v.toJS);
    await (res as JSPromise).toDart;
  }

  static Future<void> stop() async {
    final mic = _mic();
    if (mic == null) return;
    (mic.getProperty('stop'.toJS) as JSFunction).callAsFunction(mic);
  }

  /// 采集采样率固定 16k（JS 侧已降采样），这里只是给门面一个常量对齐。
  static int get sampleRate => kMicSampleRate;
}
