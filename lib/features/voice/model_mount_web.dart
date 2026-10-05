/// Web 平台：把模型文件挂进 Emscripten 的虚拟文件系统。
///
/// 挂载用 JS `fetch` + `FS.createDataFile`：
///  - 不能再用 `FS.createLazyFile`——它内部走同步 XHR，在主线程
///    （Flutter Web 的 canvas 就在主线程）会直接 abort：
///    "Cannot do synchronous binary XHRs outside webworkers"。
///  - fetch 是异步的，主线程安全；createDataFile 把字节写进 MEMFS，
///    模型推理时 WASM 从 FS 读，与原始方案路径一致（只是不在读时才拉）。
///
/// 文件清单来自构建产物里的 `models/<group>/manifest.json`（由部署脚本生成）。
///
/// 两组模型共用同一个 WASM 运行时：
///  - voice（ZipVoice）：挂 /sini-models，用于声音克隆（TTS）。
///  - asr（Whisper-tiny）：挂 /sini-asr，用于「一键识别」参考文本。
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// WASM 里 ZipVoice 模型挂在哪。
const String kModelDir = '/sini-models';

/// WASM 里 ASR 模型挂在哪。
const String kAsrModelDir = '/sini-asr';

/// Web 上模型文件的 HTTP 前缀（相对当前页面）
const String _voiceHttpPrefix = 'models/zipvoice';
const String _asrHttpPrefix = 'models/asr';

bool _voiceMounted = false;
bool _asrMounted = false;
bool _jsHelperInstalled = false;

/// 挂载 ZipVoice 模型（幂等）。
Future<void> ensureMounted({void Function(String)? onStatus}) async {
  await _ensureGroup(
    flag: _voiceMounted,
    dir: kModelDir,
    httpPrefix: _voiceHttpPrefix,
    onStatus: onStatus,
  );
  _voiceMounted = true;
}

/// 挂载 Whisper 识别模型（幂等）。
Future<void> ensureAsrMounted({void Function(String)? onStatus}) async {
  await _ensureGroup(
    flag: _asrMounted,
    dir: kAsrModelDir,
    httpPrefix: _asrHttpPrefix,
    onStatus: onStatus,
  );
  _asrMounted = true;
}

class _Manifest {
  final List<String> dirs;
  final List<String> files;
  const _Manifest(this.dirs, this.files);
}

Future<void> _ensureGroup({
  required bool flag,
  required String dir,
  required String httpPrefix,
  void Function(String)? onStatus,
}) async {
  if (flag) return;

  onStatus?.call('正在准备声音模型…');

  final manifest = await _loadManifest(httpPrefix);
  if (manifest == null) {
    throw StateError('读不到模型清单（$httpPrefix/manifest.json）');
  }

  final fs = _fs();
  if (fs == null) {
    throw StateError('sherpa-onnx 的 WASM 还没初始化好，无法挂载模型');
  }

  // 把抓取+写 FS 的辅助函数装到 globalThis（只装一次）
  await _installJsHelper();

  // 先建根目录（dir 形如 '/sini-asr' → 名字 'sini-asr'）
  _createPath(fs, '/', dir.substring(1));
  for (final d in manifest.dirs) {
    _createPathRecursive(fs, dir, d);
  }
  for (final file in manifest.files) {
    await _mountFile(fs, dir, httpPrefix, file);
  }

  debugPrint('[sini:voice] 已挂载 ${manifest.files.length} 个模型文件到 $dir');
  onStatus?.call('模型已就绪');
}

/// 装一个一次性 JS 辅助函数：异步 fetch 模型字节并写进 WASM 的 MEMFS。
///
/// 放在 globalThis 上是因为它依赖运行时的 `fetch` 和 `globalThis.Module`，
/// 在 Dart 侧逐个拼 JSFunction 调用不如直接一段 JS 干净。
Future<void> _installJsHelper() async {
  if (_jsHelperInstalled) return;
  final evalFn = globalContext.getProperty('eval'.toJS) as JSFunction?;
  if (evalFn == null) return;
  evalFn.callAsFunction(null, '''
globalThis.__siniMountFile = async function(parent, name, url) {
  const resp = await fetch(url);
  if (!resp.ok) throw new Error('挂载模型失败: ' + url + ' (HTTP ' + resp.status + ')');
  const buf = await resp.arrayBuffer();
  const Module = globalThis.Module;
  if (!Module || !Module.FS) throw new Error('sherpa WASM 未就绪，无法挂载 ' + url);
  Module.FS.createDataFile(parent, name, new Uint8Array(buf), true, true);
};
'''.toJS);
  _jsHelperInstalled = true;
}

/// 单个文件：fetch 字节 → FS.createDataFile（异步、主线程安全）。
Future<void> _mountFile(JSObject fs, String dir, String httpPrefix, String relPath) async {
  final slash = relPath.lastIndexOf('/');
  final parent = slash < 0 ? dir : '$dir/${relPath.substring(0, slash)}';
  final name = slash < 0 ? relPath : relPath.substring(slash + 1);

  // 确保父目录存在（嵌套路径要逐层建，目录创建是同步的、无副作用）
  _createPathRecursive(fs, '/', parent.substring(1));

  final url = '$httpPrefix/$relPath';
  final fn = globalContext.getProperty('__siniMountFile'.toJS) as JSFunction?;
  if (fn == null) {
    throw StateError('模型挂载辅助函数未安装（__siniMountFile 缺失）');
  }
  final result = fn.callAsFunction(null, parent.toJS, name.toJS, url.toJS);
  // 返回的是 Promise，等它 resolve 才算真正写进 FS
  if (result != null && result.isA<JSPromise>()) {
    await (result as JSPromise).toDart;
  }
}

Future<_Manifest?> _loadManifest(String httpPrefix) async {
  try {
    final resp = await Dio().get<String>('$httpPrefix/manifest.json');
    final data = resp.data;
    if (data == null) return null;
    final map = jsonDecode(data) as Map<String, dynamic>;
    return _Manifest(
      (map['dirs'] as List?)?.cast<String>() ?? const [],
      (map['files'] as List?)?.cast<String>() ?? const [],
    );
  } catch (e) {
    debugPrint('[sini:voice] 读模型清单失败: $e');
    return null;
  }
}

// ─────────────────── Emscripten FS 互操作 ───────────────────

JSObject? _fs() {
  final module = globalContext.getProperty('Module'.toJS);
  if (module.isUndefinedOrNull) return null;
  final fs = (module as JSObject).getProperty('FS'.toJS);
  if (fs.isUndefinedOrNull) return null;
  return fs as JSObject;
}

void _createPath(JSObject fs, String parent, String name) {
  final fn = fs.getProperty('createPath'.toJS) as JSFunction?;
  if (fn == null) return;
  try {
    fn.callAsFunction(fs, parent.toJS, name.toJS, true.toJS, true.toJS);
  } catch (_) {
    // 目录已存在时 createPath 会抛，这里忽略即可
  }
}

void _createPathRecursive(JSObject fs, String rootDir, String dir) {
  var parent = rootDir;
  for (final seg in dir.split('/')) {
    if (seg.isEmpty) continue;
    _createPath(fs, parent, seg);
    parent = '$parent/$seg';
  }
}
