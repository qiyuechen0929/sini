/// 预设参考音频的读取门面。
///
/// 同一批音频，两个平台取法不同：
///  - **Web**：随构建产物放在 `models/presets/` 下，走 HTTP（Dio），
///    并且挂 `?v=` 破浏览器缓存（见 `kPresetAudioVersion`）。
///  - **手机/桌面**：打进 asset，走 rootBundle。**不能用 URL** —— 手机上
///    `models/presets/x.wav` 这种相对路径根本不存在。
///
/// 统一返回字节，上层再交给 `decodeAudioBytes` 解码成 PCM。
library;

import 'dart:typed_data';

import 'preset_audio_stub.dart'
    if (dart.library.js_interop) 'preset_audio_web.dart' as impl;

/// 读取某个预设音色的参考音频字节。
///
/// [assetName] 是文件名（如 `wenrou.wav`）。
Future<Uint8List?> loadPresetAudioBytes(String assetName) =>
    impl.loadPresetAudioBytes(assetName);

/// 试听时给 audioplayers 用的播放源（Web 是 URL，手机是 asset）。
/// 返回 Object 是为了避免在门面里 import audioplayers 的类型。
Object presetPlaybackSource(String assetName) =>
    impl.presetPlaybackSource(assetName);
