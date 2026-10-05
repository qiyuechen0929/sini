/// 音频解码门面：把用户上传的音频文件（wav / mp3 / m4a / ogg…）解成
/// 单声道 float32 采样，供声音克隆当参考。
///
/// 为什么必须自己解码：sherpa-onnx 的 `readWave` 需要文件系统，
/// **Web 端没有实现**（会直接抛 UnsupportedError）。而用户手上的语音
/// 多半是微信语音条（m4a/amr）或 mp3，不是干净的 wav。
///
/// 实现分平台：
///  - Web：WebAudio 的 `decodeAudioData`，顺带让浏览器重采样到 24kHz
///  - 其他：纯 Dart 解析 WAV（PCM16 / Float32）
library;

import 'dart:typed_data';

import 'audio_pcm_types.dart';
import 'audio_pcm_stub.dart'
    if (dart.library.js_interop) 'audio_pcm_web.dart' as impl;

export 'audio_pcm_types.dart';

/// 声音克隆需要的采样率。web 端解码时直接让它重采样到这个值，
/// 免得再自己写一遍重采样。
const int kReferenceSampleRate = 24000;

/// 解码失败（格式不支持 / 文件损坏）返回 null，由调用方给出提示。
Future<DecodedAudio?> decodeAudioBytes(Uint8List bytes) =>
    impl.decodeAudioBytes(bytes);
