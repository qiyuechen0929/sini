import 'dart:typed_data';

/// 解码后的音频：单声道 float32 采样 + 采样率。
///
/// 单独一个文件是为了避免「门面 ↔ 平台实现」互相 import 造成的循环依赖。
class DecodedAudio {
  final Float32List samples;
  final int sampleRate;

  const DecodedAudio({required this.samples, required this.sampleRate});

  double get durationSeconds =>
      sampleRate == 0 ? 0 : samples.length / sampleRate;
}
