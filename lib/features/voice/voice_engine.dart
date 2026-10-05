/// 端侧声音克隆引擎：把「一段参考录音 + 那段录音的文字」变成「任意文本的语音」。
///
/// 技术选型与理由（改之前先读）：
///  - 模型：**ZipVoice-Distill**（小米 + k2-fsa 开源，Apache-2.0，123M 参数）。
///    选中它的原因是它同时满足三个硬要求：**零样本克隆**（不需要训练）、
///    **中英双语**、**小到能在手机上跑**（int8 量化后 130MB）。
///  - 推理：**sherpa-onnx**。它的 Flutter 包同时支持 web / Android / iOS，
///    所以这一份 Dart 代码在浏览器预览和真机上都能跑，不用写两套。
///  - 完全本地：模型是本地文件，推理在设备上完成，**不联网、不调用任何云服务、
///    不产生费用**。用户的声音样本也不会离开设备。
///
/// 效果预期（实测，i7 纯 CPU）：生成 2~3 秒语音约 1.6~7 秒（RTF 0.7~3.3）。
library;

import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../models.dart';
import 'audio_pcm.dart';
import 'model_mount.dart';
import 'presets.dart';
import 'ref_audio_store.dart';

/// 生成一次语音的结果。
class VoiceGenResult {
  /// 单声道 float32 采样（[-1, 1]）
  final Float32List samples;
  final int sampleRate;

  /// 本次推理用的步数（步数越多越细，也越慢）
  final int numSteps;

  /// 实际耗时
  final Duration elapsed;

  const VoiceGenResult({
    required this.samples,
    required this.sampleRate,
    required this.numSteps,
    required this.elapsed,
  });

  double get durationSeconds =>
      sampleRate == 0 ? 0 : samples.length / sampleRate;

  /// 实时率：<1 表示比实时还快。手机端判断"能不能用"的关键指标。
  double get realTimeFactor {
    final d = durationSeconds;
    if (d <= 0) return 0;
    return elapsed.inMicroseconds / 1e6 / d;
  }

  /// 编码成 16-bit PCM 的 WAV 字节。
  ///
  /// 为什么要自己编码：sherpa-onnx 的 `writeWave` 需要文件系统，
  /// 而 Web 上没有文件系统；编成字节后既能直接用 BytesSource 播放，
  /// 也能（将来）落盘保存。
  Uint8List toWavBytes() => encodeWav(samples, sampleRate);
}

/// float32 PCM → 16-bit WAV 字节（纯 Dart，无依赖，Web/移动端通用）。
Uint8List encodeWav(Float32List samples, int sampleRate, {int channels = 1}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final dataSize = samples.length * 2;
  final out = Uint8List(44 + dataSize);
  final view = ByteData.view(out.buffer);

  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out[offset + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little); // PCM 头长度
  view.setUint16(20, 1, Endian.little); // PCM
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, byteRate, Endian.little);
  view.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
  view.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  view.setUint32(40, dataSize, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    final v = samples[i];
    final clamped = v.isNaN ? 0.0 : (v < -1.0 ? -1.0 : (v > 1.0 ? 1.0 : v));
    view.setInt16(44 + i * 2, (clamped * 32767).round(), Endian.little);
  }
  return out;
}

/// ZipVoice 引擎：模型只加载一次，之后反复复用。
class VoiceEngine {
  VoiceEngine._();

  static bool _bindingsReady = false;
  static sherpa.OfflineTts? _tts;
  static Future<void>? _loading;

  /// 模型是否已经加载好（用于 UI 显示状态）。
  static bool get isReady => _tts != null;

  /// 只加载一次（并发调用会复用同一个 Future）。
  ///
  /// [onStatus] 用来给 UI 反馈进度——首次要读 190MB 模型，
  /// 手机和浏览器都可能花几秒到几十秒，没有反馈用户会以为卡死。
  static Future<void> ensureLoaded({void Function(String status)? onStatus}) {
    if (_tts != null) return Future.value();
    return _loading ??= _load(onStatus);
  }

  static Future<void> _load(void Function(String)? onStatus) async {
    onStatus?.call('正在初始化推理引擎…');
    if (!_bindingsReady) {
      await sherpa.initBindingsAsync();
      _bindingsReady = true;
    }

    onStatus?.call('正在加载声音模型（首次较慢）…');
    // Web 上模型要先挂进 WASM 的虚拟文件系统，否则模型"存在但读不到"
    await ensureVoiceModelsMounted(onStatus: onStatus);
    final dir = voiceModelDir;
    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        zipvoice: sherpa.OfflineTtsZipVoiceModelConfig(
          tokens: '$dir/tokens.txt',
          encoder: '$dir/encoder.int8.onnx',
          decoder: '$dir/decoder.int8.onnx',
          vocoder: '$dir/vocos_24khz.onnx',
          dataDir: '$dir/espeak-ng-data',
          lexicon: '$dir/lexicon.txt',
        ),
        numThreads: 2,
        debug: false,
      ),
    );
    // 注意：Dart 版的 OfflineTtsConfig 没有 validate()，模型缺失会在构造时报错
    _tts = sherpa.OfflineTts(config);
    onStatus?.call('模型就绪');
  }

  /// 用参考音频克隆出的音色，朗读 [text]。
  ///
  /// - [referenceSamples]：参考录音的单声道 float32 采样
  /// - [referenceText]：**这段录音说的话**（必须基本一致，否则音质会明显变差）
  /// - [numSteps]：推理步数。4 = 快（首次预览用），8~16 = 更细（重新生成用）
  ///
  /// ⚠️ 这是 CPU 密集的同步调用，Web 上会阻塞 UI 线程。调用方应当先让
  /// "生成中"状态渲染出来再调它（见页面里的处理）。
  static VoiceGenResult generate({
    required Float32List referenceSamples,
    required int referenceSampleRate,
    required String referenceText,
    required String text,
    int numSteps = 4,
    double speed = 1.0,
  }) {
    final tts = _tts;
    if (tts == null) {
      throw StateError('模型还没加载好，请先调用 ensureLoaded()');
    }
    if (referenceSamples.isEmpty) {
      throw ArgumentError('参考音频是空的');
    }
    if (text.trim().isEmpty) {
      throw ArgumentError('要生成的内容是空的');
    }

    final genConfig = sherpa.OfflineTtsGenerationConfig(
      speed: speed,
      referenceAudio: referenceSamples,
      referenceSampleRate: referenceSampleRate,
      referenceText: referenceText.trim(),
      numSteps: numSteps,
      // ZipVoice 要求句子不能太短（太短会明显失真），这里给一个下限
      extra: const {'min_char_in_sentence': 10},
    );

    final sw = Stopwatch()..start();
    final audio = tts.generateWithConfig(text: text.trim(), config: genConfig);
    sw.stop();

    if (audio.samples.isEmpty) {
      throw StateError('生成失败：模型没有输出音频');
    }
    return VoiceGenResult(
      samples: audio.samples,
      sampleRate: audio.sampleRate,
      numSteps: numSteps,
      elapsed: sw.elapsed,
    );
  }

  /// 用人格配置的声音朗读 [text]（聊天页「播放」用）。
  ///
  /// - 预设音色：取内置预设参考合成，不依赖本机音频。
  /// - 克隆声音：从 IndexedDB 取本机保存的参考音频合成。
  ///
  /// 同样是 CPU 密集的同步合成，调用方先展示「生成中」再调。
  static Future<VoiceGenResult> speakText({
    required String personaId,
    required String text,
    required PersonaVoice voice,
    void Function(String status)? onStatus,
  }) async {
    await ensureLoaded(onStatus: onStatus);

    final DecodedAudio ref;
    final String refText;
    if (voice.isPreset) {
      final preset = voicePresetById(voice.presetId!);
      if (preset == null) {
        throw StateError('未知的预设音色：${voice.presetId}');
      }
      onStatus?.call('正在准备「${preset.label}」音色…');
      final d = await loadPresetRefAudio(preset);
      if (d == null) {
        throw StateError('预设音色参考音频加载失败');
      }
      ref = d;
      refText = preset.promptText;
    } else {
      final bytes = await RefAudioStore.load(personaId);
      if (bytes == null) {
        throw StateError('本机没有 TA 的参考音频，重新克隆一次即可');
      }
      final d = await decodeAudioBytes(bytes);
      if (d == null) {
        throw StateError('参考音频解码失败，请重新克隆');
      }
      ref = d;
      refText = voice.referenceText;
    }

    onStatus?.call('正在合成语音…');
    return generate(
      referenceSamples: ref.samples,
      referenceSampleRate: ref.sampleRate,
      referenceText: refText,
      text: text,
    );
  }

  static void dispose() {
    _tts?.free();
    _tts = null;
    _loading = null;
  }
}
