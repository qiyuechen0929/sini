/// 统一的音频播放初始化：Android 上不设 AudioContext 时经常静音/无声。
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

bool _ready = false;

AudioContext _ctx() => AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gain,
        isSpeakerphoneOn: true,
        audioMode: AndroidAudioMode.normal,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {
          AVAudioSessionOptions.mixWithOthers,
          AVAudioSessionOptions.duckOthers,
        },
      ),
    );

Future<void> ensureAudioReady() async {
  if (kIsWeb) return;
  if (_ready) return;
  try {
    await AudioPlayer.global.setAudioContext(_ctx());
    _ready = true;
  } catch (e) {
    debugPrint('[sini:audio] setAudioContext: $e');
  }
}

/// 创建已配置好的播放器（全局只建少数几个即可）。
Future<AudioPlayer> createMediaPlayer() async {
  await ensureAudioReady();
  final p = AudioPlayer();
  try {
    await p.setAudioContext(_ctx());
    // 预设音色 / 克隆 wav 都是短音频，限制音量峰值避免破音
    await p.setVolume(1.0);
  } catch (_) {}
  return p;
}
