import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sini/features/voice/audio_preprocess.dart';
import 'package:sini/features/voice/voice_engine.dart';

/// 声音克隆里**纯计算**的部分（WAV 编码 + 参考音频预处理）。
///
/// 这两块最容易悄悄出错（写错 WAV 头 → 播放器不认；预处理写错 → 反而删掉人声），
/// 而且它们不依赖 sherpa-onnx 的 native/WASM，可以在 `flutter test` 里直接跑。
void main() {
  int sr = 24000;

  /// 造一段「前 [lead] 秒静音 + [tone] 秒正弦 + 后 [tail] 秒静音」的样本
  Float32List toneWith(int lead, double tone, int tail, {double amp = 0.8}) {
    final out = <double>[];
    for (var i = 0; i < (sr * lead).round(); i++) {
      out.add((math.Random(i).nextDouble() - 0.5) * 0.001); // 极低底噪
    }
    for (var i = 0; i < (sr * tone).round(); i++) {
      out.add(amp * math.sin(2 * math.pi * 220 * i / sr));
    }
    for (var i = 0; i < (sr * tail).round(); i++) {
      out.add((math.Random(i + 999).nextDouble() - 0.5) * 0.001);
    }
    return Float32List.fromList(out);
  }

  group('WAV 编码', () {
    test('头部字段正确，播放器才认（RIFF/WAVE/fmt/data + 长度）', () {
      final samples = Float32List.fromList([0.0, 0.5, -0.5, 1.0]);
      final bytes = encodeWav(samples, 24000);
      String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
      final view = ByteData.view(bytes.buffer);

      expect(tag(0), 'RIFF');
      expect(tag(8), 'WAVE');
      expect(tag(12), 'fmt ');
      expect(tag(36), 'data');
      expect(view.getUint16(20, Endian.little), 1); // PCM
      expect(view.getUint16(22, Endian.little), 1); // 单声道
      expect(view.getUint32(24, Endian.little), 24000);
      expect(view.getUint16(34, Endian.little), 16); // 16 bit
      expect(view.getUint32(40, Endian.little), samples.length * 2);
      expect(bytes.length, 44 + samples.length * 2);
      // RIFF 长度 = 整个文件 - 8
      expect(view.getUint32(4, Endian.little), bytes.length - 8);
    });

    test('超出 [-1,1] 的样本会被削波而不是溢出成爆音', () {
      final bytes = encodeWav(Float32List.fromList([2.0, -2.0]), 24000);
      final view = ByteData.view(bytes.buffer);
      expect(view.getInt16(44, Endian.little), 32767);
      expect(view.getInt16(46, Endian.little), -32767);
    });

    test('NaN 不产生垃圾数据', () {
      final bytes = encodeWav(Float32List.fromList([double.nan]), 24000);
      final view = ByteData.view(bytes.buffer);
      expect(view.getInt16(44, Endian.little), 0);
    });
  });

  group('参考音频预处理（重新生成更好的关键）', () {
    test('去掉首尾静音，并记下处理说明', () {
      final input = toneWith(2, 4, 2); // 2s 静音 + 4s 声音 + 2s 静音
      final prep = prepareReference(input, sr, maxSeconds: 10);

      expect(prep.originalSeconds, closeTo(8.0, 0.1));
      expect(prep.preparedSeconds, lessThan(6.0)); // 静音被去掉
      expect(prep.preparedSeconds, greaterThan(3.5)); // 人声保留
      expect(prep.notes.join(), contains('静音'));
    });

    test('超过上限时裁到能量最集中的一段（长样本会让音色发散）', () {
      // 前 6 秒很轻、后 6 秒很响；裁 5 秒应该落在后半段
      final quiet = List<double>.generate(
          sr * 6, (i) => 0.05 * math.sin(2 * math.pi * 200 * i / sr));
      final loud = List<double>.generate(
          sr * 6, (i) => 0.9 * math.sin(2 * math.pi * 200 * i / sr));
      final input = Float32List.fromList([...quiet, ...loud]);

      final prep = prepareReference(input, sr, maxSeconds: 5);
      expect(prep.preparedSeconds, closeTo(5.0, 0.05));
      expect(prep.notes.join(), contains('能量最集中'));

      // 裁出来的这段应该来自响的那一半：峰值接近 0.9，而不是轻的那半（0.05）。
      // 注意这里不要断言"被归一化到 1" —— 峰值已在合理区间（0.85~1）时
      // 预处理**刻意不做增益**，无意义的放大反而可能引入失真。
      var peak = 0.0;
      for (final v in prep.samples) {
        final a = v.abs();
        if (a > peak) peak = a;
      }
      expect(peak, greaterThan(0.5));
    });

    test('响度太低会被归一化抬起来', () {
      final input = toneWith(0, 4, 0, amp: 0.2);
      final prep = prepareReference(input, sr);
      expect(prep.peakBefore, lessThan(0.3));
      expect(prep.peakAfter, closeTo(0.95, 0.02));
      expect(prep.notes.join(), contains('响度归一化'));
    });

    test('样本太短会给出提醒（但不阻止使用）', () {
      final input = toneWith(0, 1.5, 0, amp: 0.8);
      final prep = prepareReference(input, sr);
      expect(prep.warnings.join(), contains('偏短'));
      expect(prep.samples.isNotEmpty, true);
    });

    test('空音频不崩，给出提醒', () {
      final prep = prepareReference(Float32List(0), sr);
      expect(prep.warnings, isNotEmpty);
      expect(prep.samples.isEmpty, true);
    });

    test('已经足够干净、长度合适的样本不动它（不做无意义的处理）', () {
      final input = toneWith(0, 5, 0, amp: 0.96);
      final prep = prepareReference(input, sr);
      expect(prep.notes, isEmpty);
      expect(prep.preparedSeconds, closeTo(5.0, 0.05));
    });
  });
}
