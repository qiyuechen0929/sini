/// 非 Web 平台的音频解码（纯 Dart）。
///
/// 目前只支持 **WAV**（PCM 16-bit / IEEE float32 / PCM 8-bit）。
/// 手机端要支持微信语音条那种 m4a/amr，得接原生解码器 —— 那是下一步的事，
/// 这里先把 WAV 这条路走通，并且**明确失败**而不是假装成功。
library;

import 'dart:typed_data';

import 'audio_pcm.dart';
import 'audio_pcm_types.dart';

Future<DecodedAudio?> decodeAudioBytes(Uint8List bytes) async {
  final wav = _decodeWav(bytes);
  if (wav == null) return null;
  if (wav.sampleRate == kReferenceSampleRate) return wav;
  return _resample(wav, kReferenceSampleRate);
}

DecodedAudio? _decodeWav(Uint8List bytes) {
  if (bytes.length < 44) return null;
  final data = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);

  String tag(int offset) => String.fromCharCodes(
        bytes.sublist(offset, offset + 4),
      );
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;

  int? audioFormat;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? dataOffset;
  int? dataLength;

  // 逐个 chunk 扫描（不同工具产出的 wav，chunk 顺序和额外 chunk 都不一定）
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = tag(offset);
    final size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      audioFormat = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bitsPerSample = data.getUint16(body + 14, Endian.little);
      // WAVE_FORMAT_EXTENSIBLE：真正的格式藏在扩展头最后 2 字节
      if (audioFormat == 0xFFFE && body + 26 <= bytes.length) {
        audioFormat = data.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data') {
      dataOffset = body;
      dataLength = size;
      break;
    }
    offset = body + size + (size.isOdd ? 1 : 0); // chunk 按偶数字节对齐
  }

  if (audioFormat == null ||
      channels == null ||
      sampleRate == null ||
      bitsPerSample == null ||
      dataOffset == null ||
      dataLength == null ||
      channels <= 0) {
    return null;
  }
  // data chunk 声明的长度可能不可信（有些工具写 0 或 -1），以实际剩余字节为准
  final available = bytes.length - dataOffset;
  final usable = dataLength <= 0 || dataLength > available ? available : dataLength;

  final frames = <double>[];
  if (audioFormat == 1 && bitsPerSample == 16) {
    final count = usable ~/ 2;
    for (var i = 0; i < count; i++) {
      frames.add(data.getInt16(dataOffset + i * 2, Endian.little) / 32768.0);
    }
  } else if (audioFormat == 3 && bitsPerSample == 32) {
    final count = usable ~/ 4;
    for (var i = 0; i < count; i++) {
      frames.add(data.getFloat32(dataOffset + i * 4, Endian.little));
    }
  } else if (audioFormat == 1 && bitsPerSample == 8) {
    for (var i = 0; i < usable; i++) {
      frames.add((bytes[dataOffset + i] - 128) / 128.0);
    }
  } else {
    return null; // 24-bit / ADPCM 等暂不支持
  }

  final perChannel = frames.length ~/ channels;
  if (perChannel == 0) return null;
  final mono = Float32List(perChannel);
  for (var i = 0; i < perChannel; i++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += frames[i * channels + c];
    }
    mono[i] = sum / channels;
  }
  return DecodedAudio(samples: mono, sampleRate: sampleRate);
}

/// 线性插值重采样。参考音频对音质要求不高（只是给模型提取音色），
/// 线性插值足够；且这段代码在非 Web 端才走，Web 端由浏览器重采样。
DecodedAudio _resample(DecodedAudio src, int targetRate) {
  if (src.sampleRate == targetRate || src.samples.isEmpty) return src;
  final ratio = targetRate / src.sampleRate;
  final outLength = (src.samples.length * ratio).floor();
  if (outLength <= 0) return src;
  final out = Float32List(outLength);
  for (var i = 0; i < outLength; i++) {
    final pos = i / ratio;
    final i0 = pos.floor();
    final i1 = i0 + 1 < src.samples.length ? i0 + 1 : src.samples.length - 1;
    final t = pos - i0;
    out[i] = src.samples[i0] * (1 - t) + src.samples[i1] * t;
  }
  return DecodedAudio(samples: out, sampleRate: targetRate);
}
