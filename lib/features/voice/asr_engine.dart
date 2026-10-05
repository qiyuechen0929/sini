/// 端侧语音识别引擎：把「一段参考录音」自动转成文字。
///
/// 用途：声音克隆页第二步要求填写「这段录音说了什么」，手打既麻烦又容易错。
/// 这里用同一个 sherpa-onnx WASM 运行时（和 ZipVoice 共用）跑 Whisper-tiny
/// 多语模型，把音频**自动识别成文字**填进文本框，用户校对一下即可。
///
/// 全程本地：模型是本地文件，推理在设备上完成，不联网、不上传录音。
library;

import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'asr_bindings_stub.dart'
    if (dart.library.js_interop) 'asr_bindings_web.dart' as bindings;
import 'asr_text.dart';
import 'model_mount.dart';

export 'asr_text.dart';

/// Whisper 要求的输入采样率（与参考音频的 24kHz 不同，识别前会重采样）。
const int kAsrSampleRate = 16000;

class AsrEngine {
  AsrEngine._();

  static bool _bindingsReady = false;
  static bool _asrReady = false;
  static Future<void>? _loading;

  /// 模型是否已经加载好（用于 UI 显示状态）。
  static bool get isReady => _asrReady;

  /// 只加载一次（并发调用会复用同一个 Future）。
  static Future<void> ensureLoaded({void Function(String status)? onStatus}) {
    if (_asrReady) return Future.value();
    return _loading ??= _load(onStatus);
  }

  static Future<void> _load(void Function(String)? onStatus) async {
    onStatus?.call('正在初始化识别引擎…');
    if (!_bindingsReady) {
      await sherpa.initBindingsAsync();
      _bindingsReady = true;
      // Web 上还要额外把 OfflineRecognizer 挂到 globalThis（见 asr_bindings_web.dart
      // 里那段解释）；原生端这一步是空操作。
      await bindings.exposeExtraBindings();
    }

    onStatus?.call('正在加载识别模型（首次较慢）…');
    await ensureAsrModelsMounted(onStatus: onStatus);
    _asrReady = true;
    onStatus?.call('识别模型就绪');
  }

  /// 把 [samples]（任意采样率的单声道 float32）识别成文字。
  ///
  /// 返回识别文本（已 trim、已过滤幻觉）。识别失败会抛异常，调用方自行兜底。
  static Future<String> transcribe(
      Float32List samples, int sampleRate) async {
    if (!_asrReady) {
      throw StateError('识别模型还没加载好，请先调用 ensureLoaded()');
    }
    if (samples.isEmpty) {
      throw ArgumentError('音频是空的');
    }

    final recognizer = _recognizerOf();
    // Whisper 固定吃 16kHz，参考音频是 24kHz，先重采样
    final pcm = _resample(samples, sampleRate, kAsrSampleRate);
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: pcm, sampleRate: kAsrSampleRate);
      recognizer.decode(stream);
      return sanitizeAsrText(recognizer.getResult(stream).text);
    } finally {
      stream.free();
    }
  }

  /// 识别器只建一次。
  ///
  /// 为什么必须缓存：语音通话里要**边说边反复识别**（每 1 秒左右拿当前这段
  /// 音频重解一次，字幕才能实时冒字）。`OfflineRecognizer` 的构造要把 100MB
  /// 模型从 WASM 虚拟文件系统读出来建 session，每次重建的话光初始化就比识别
  /// 本身还慢，增量识别根本跑不动。
  static sherpa.OfflineRecognizer? _recognizer;

  static sherpa.OfflineRecognizer _recognizerOf() {
    final cached = _recognizer;
    if (cached != null) return cached;
    final dir = asrModelDir;
    final config = sherpa.OfflineRecognizerConfig(
      feat: const sherpa.FeatureConfig(), // 默认 16000 / 80，正是 Whisper 所需
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: '$dir/encoder.int8.onnx',
          decoder: '$dir/decoder.int8.onnx',
          // 留空 = 自动检测语言：中文为主，也能认英文片段，
          // 比写死 'zh' 更稳（写死会在非中文音频上直接空结果）。
          language: '',
          task: 'transcribe',
        ),
        tokens: '$dir/tokens.txt',
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
    );
    _recognizer = sherpa.OfflineRecognizer(config);
    return _recognizer!;
  }

  /// 释放识别器（切换模型 / 回收内存时用）。
  static void dispose() {
    _recognizer?.free();
    _recognizer = null;
    _asrReady = false;
    _loading = null;
  }

  /// 线性插值重采样（ASR 前端对精度不敏感，线性足够）。
  static Float32List _resample(
      Float32List input, int inRate, int outRate) {
    if (inRate == outRate) return input;
    final ratio = outRate / inRate;
    final outLen = (input.length * ratio).round();
    final out = Float32List(outLen);
    for (var i = 0; i < outLen; i++) {
      final pos = i / ratio;
      final i0 = pos.floor();
      final i1 = (i0 + 1).clamp(0, input.length - 1);
      final frac = pos - i0;
      out[i] = input[i0] * (1 - frac) + input[i1] * frac;
    }
    return out;
  }
}
