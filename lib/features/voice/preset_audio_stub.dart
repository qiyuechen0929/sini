/// 手机 / 桌面：预设音频打包成 asset，从 asset 读。
library;

import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// 与 pubspec.yaml 里声明的 asset 目录对应
const String kPresetAssetDir = 'web/models/presets';

Future<Uint8List?> loadPresetAudioBytes(String assetName) async {
  try {
    final data = await rootBundle.load('$kPresetAssetDir/$assetName');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}

Object presetPlaybackSource(String assetName) =>
    AssetSource('$kPresetAssetDir/$assetName');
