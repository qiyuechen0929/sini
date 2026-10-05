/// 参考音频预处理：让「重新生成」真的有提升，而不是重复抽签。
///
/// 依据来自 ZipVoice 官方说明：参考音频**太长会发散、太短会不稳**，
/// 理想是 3~10 秒干净人声；样本里的静音段和过低响度都会拉低音色还原度。
/// 所以第二次生成前把样本处理干净：去首尾静音 → 截到能量最集中的一段 →
/// 响度归一化。
///
/// 这里的每一步都会记进 [ReferencePrep.notes]，**让用户看得见"这次做了什么"**——
/// 否则"重新生成更好"就只是一句空话。
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 预处理结果
class ReferencePrep {
  final Float32List samples;
  final int sampleRate;

  /// 处理前的时长（秒）
  final double originalSeconds;

  /// 处理后的时长（秒）
  final double preparedSeconds;

  /// 处理前后的峰值，用于说明响度变化
  final double peakBefore;
  final double peakAfter;

  /// 对用户可见的处理说明（比如「裁到能量最集中的 8.0 秒」）
  final List<String> notes;

  /// 需要注意的提醒（比如「样本偏短，效果可能不稳定」）
  final List<String> warnings;

  const ReferencePrep({
    required this.samples,
    required this.sampleRate,
    required this.originalSeconds,
    required this.preparedSeconds,
    required this.peakBefore,
    required this.peakAfter,
    required this.notes,
    required this.warnings,
  });

  bool get changed => notes.isNotEmpty;
}

/// 目标时长窗口（ZipVoice 官方建议 3~10 秒）
const double kRefMinSeconds = 3.0;
const double kRefMaxSeconds = 10.0;

/// 预处理参考音频。
///
/// 整个过程是纯计算（无 IO、无平台依赖），可直接单测。
ReferencePrep prepareReference(
  Float32List input,
  int sampleRate, {
  double minSeconds = kRefMinSeconds,
  double maxSeconds = kRefMaxSeconds,
}) {
  final notes = <String>[];
  final warnings = <String>[];
  if (input.isEmpty || sampleRate <= 0) {
    return ReferencePrep(
      samples: input,
      sampleRate: sampleRate,
      originalSeconds: 0,
      preparedSeconds: 0,
      peakBefore: 0,
      peakAfter: 0,
      notes: const [],
      warnings: const ['这段音频是空的'],
    );
  }

  final originalSeconds = input.length / sampleRate;

  // ── 1. 去掉首尾静音 ────────────────────────────────────────
  final speechRange = _speechRange(input, sampleRate);
  var work = speechRange == null
      ? Float32List.fromList(input)
      : Float32List.fromList(
          Float32List.sublistView(input, speechRange.$1, speechRange.$2));
  if (speechRange != null) {
    final removed = originalSeconds - work.length / sampleRate;
    if (removed > 0.3) {
      final head = speechRange.$1 / sampleRate;
      final tail = (input.length - speechRange.$2) / sampleRate;
      notes.add('去掉了首尾静音（开头 ${head.toStringAsFixed(1)}s / 结尾 ${tail.toStringAsFixed(1)}s）');
    }
  }

  // ── 2. 太长就截到能量最集中的一段 ──────────────────────────
  final maxSamples = (maxSeconds * sampleRate).round();
  if (work.length > maxSamples) {
    final start = _busiestWindow(work, maxSamples);
    work = Float32List.fromList(work.sublist(start, start + maxSamples));
    notes.add('裁到能量最集中的 ${maxSeconds.toStringAsFixed(0)}s'
        '（原 ${originalSeconds.toStringAsFixed(1)}s）');
  }

  // ── 3. 响度归一化 ─────────────────────────────────────────
  final peakBefore = _peak(work);
  var prepared = work;
  if (peakBefore > 0.001) {
    if (peakBefore < 0.85) {
      const target = 0.95;
      final gain = target / peakBefore;
      prepared = Float32List(work.length);
      for (var i = 0; i < work.length; i++) {
        prepared[i] = work[i] * gain;
      }
      notes.add('响度归一化（峰值 ${peakBefore.toStringAsFixed(2)} → '
          '${(peakBefore * gain).toStringAsFixed(2)}）');
    } else if (peakBefore > 0.999) {
      // 已经贴着 0dB，说明可能被削波过，轻微回退一点更安全
      prepared = Float32List(work.length);
      for (var i = 0; i < work.length; i++) {
        prepared[i] = work[i] * 0.95;
      }
      notes.add('样本可能削波，已轻微回退音量');
    }
  }

  // ── 4. 质量提醒（不阻止使用，但要如实告诉用户）──────────────
  final preparedSeconds = prepared.length / sampleRate;
  if (preparedSeconds < minSeconds) {
    warnings.add('样本只有 ${preparedSeconds.toStringAsFixed(1)} 秒，'
        '偏短（建议 ${minSeconds.toStringAsFixed(0)} 秒以上），音色可能不稳定');
  }
  final noiseRatio = _noiseRatio(prepared, sampleRate);
  if (noiseRatio != null && noiseRatio > 0.25) {
    warnings.add('背景噪声偏大，建议换一段更安静的录音');
  }

  return ReferencePrep(
    samples: prepared,
    sampleRate: sampleRate,
    originalSeconds: originalSeconds,
    preparedSeconds: preparedSeconds,
    peakBefore: peakBefore,
    peakAfter: _peak(prepared),
    notes: notes,
    warnings: warnings,
  );
}

/// 找首尾有声音的范围（20ms 一帧，低于「峰值 5%」视为静音）
(int, int)? _speechRange(Float32List samples, int sampleRate) {
  final frame = math.max(1, (sampleRate * 0.02).round());
  final frameCount = samples.length ~/ frame;
  if (frameCount < 3) return null;

  final rms = List<double>.filled(frameCount, 0);
  var peak = 0.0;
  for (var f = 0; f < frameCount; f++) {
    var sum = 0.0;
    for (var i = 0; i < frame; i++) {
      final v = samples[f * frame + i];
      sum += v * v;
    }
    rms[f] = math.sqrt(sum / frame);
    peak = math.max(peak, rms[f]);
  }
  if (peak <= 0) return null;
  final threshold = peak * 0.05;

  var first = 0;
  while (first < frameCount && rms[first] < threshold) {
    first++;
  }
  var last = frameCount - 1;
  while (last > first && rms[last] < threshold) {
    last--;
  }
  if (last <= first) return null;
  // 前后各留 100ms，避免把气口削掉
  final pad = (sampleRate * 0.1).round();
  final start = math.max(0, first * frame - pad);
  final end = math.min(samples.length, (last + 1) * frame + pad);
  return (start, end);
}

/// 在音频里找能量最集中的 [windowLength] 长度片段，返回起始下标
int _busiestWindow(Float32List samples, int windowLength) {
  if (samples.length <= windowLength) return 0;
  // 用「细粒度累加 + 滑动」避免 O(n·w) 的暴力计算
  final step = math.max(1, windowLength ~/ 32);
  var bestStart = 0;
  var bestEnergy = -1.0;
  for (var start = 0; start + windowLength <= samples.length; start += step) {
    var energy = 0.0;
    // 抽样估算能量即可（每 16 个点取一个），足够选出「哪一段最热闹」
    for (var i = start; i < start + windowLength; i += 16) {
      energy += samples[i] * samples[i];
    }
    if (energy > bestEnergy) {
      bestEnergy = energy;
      bestStart = start;
    }
  }
  return bestStart;
}

double _peak(Float32List samples) {
  var peak = 0.0;
  for (final v in samples) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  return peak;
}

/// 粗估「噪声 / 语音」能量比：取最安静 10% 的帧与整体对比。
/// 只用来给用户一句提醒，不追求精确。
double? _noiseRatio(Float32List samples, int sampleRate) {
  final frame = math.max(1, (sampleRate * 0.02).round());
  final frameCount = samples.length ~/ frame;
  if (frameCount < 10) return null;
  final rms = <double>[];
  for (var f = 0; f < frameCount; f++) {
    var sum = 0.0;
    for (var i = 0; i < frame; i++) {
      final v = samples[f * frame + i];
      sum += v * v;
    }
    rms.add(math.sqrt(sum / frame));
  }
  rms.sort();
  final quietCount = math.max(1, (frameCount * 0.1).round());
  final quiet = rms.take(quietCount).reduce((a, b) => a + b) / quietCount;
  final overall = rms.reduce((a, b) => a + b) / frameCount;
  if (overall <= 0) return null;
  return quiet / overall;
}
