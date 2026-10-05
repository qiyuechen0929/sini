/// Web：预设音频随构建产物放在 `models/presets/` 下，走 HTTP 读取。
///
/// 挂 `?v=` 是为了破浏览器缓存 —— 换了音频但文件名不变时，
/// 不加版本号用户听到的还是旧的（踩过）。
library;

import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';

import 'presets.dart' show kPresetAudioVersion;

Future<Uint8List?> loadPresetAudioBytes(String assetName) async {
  try {
    final resp = await Dio().get<List<int>>(
      'models/presets/$assetName?v=$kPresetAudioVersion',
      options: Options(responseType: ResponseType.bytes),
    );
    final data = resp.data;
    if (data == null) return null;
    return Uint8List.fromList(data);
  } catch (_) {
    return null;
  }
}

Object presetPlaybackSource(String assetName) =>
    UrlSource('models/presets/$assetName?v=$kPresetAudioVersion');
