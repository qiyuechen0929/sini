/// 模型挂载门面：让「模型文件」在运行环境里真的能被读到。
///
/// 为什么需要这一层：
///  - **Web**：sherpa-onnx 跑在 WebAssembly 里，它看到的是 Emscripten 的
///    **虚拟文件系统**，不是你的磁盘。HTTP 上放着模型不等于 WASM 里能读到，
///    必须逐个挂载（用 JS `fetch` + `FS.createDataFile` 写进 MEMFS）。
///    这里就是踩过的坑：不挂载的话创建 TTS 会报
///    `--zipvoice-tokens: 'models/...' does not exist`。
///  - **手机/桌面**：有真实文件系统，直接用路径就行，所以是空实现。
library;

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'model_mount_stub.dart'
    if (dart.library.js_interop) 'model_mount_web.dart' as impl;

/// ZipVoice 模型目录在「当前运行环境的文件系统」里的表示。
///
/// Web 是挂载后的绝对路径（`/sini-models`），其他平台是工程内的相对/绝对路径。
String get voiceModelDir => impl.kModelDir;

/// ASR（Whisper）模型目录在「当前运行环境的文件系统」里的表示。
///
/// Web 是挂载后的绝对路径（`/sini-asr`）。
String get asrModelDir => impl.kAsrModelDir;

/// 把 ZipVoice 模型挂进运行环境的文件系统（幂等，重复调用不会重复挂）。
///
/// 只在 Web 上真正做事；其他平台直接返回。
Future<void> ensureVoiceModelsMounted({void Function(String)? onStatus}) async {
  // Web 上挂载依赖 sherpa-onnx 的 WASM 已经初始化好（Module 才有 FS）
  await sherpa.initBindingsAsync();
  await impl.ensureMounted(onStatus: onStatus);
}

/// 把 Whisper 识别模型挂进运行环境的文件系统（幂等）。
///
/// 与 ZipVoice 共用同一个 WASM 运行时，只是挂在 `/sini-asr` 下。
Future<void> ensureAsrModelsMounted({void Function(String)? onStatus}) async {
  await sherpa.initBindingsAsync();
  await impl.ensureAsrMounted(onStatus: onStatus);
}
