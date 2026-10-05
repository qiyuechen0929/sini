/// 非 Web（Android / iOS / 桌面）的模型挂载实现。
///
/// 有真实文件系统，但**打包进去的模型在 asset 里，不是文件**——sherpa-onnx
/// 的 Dart API 只认文件路径，读不到 asset。所以第一次用之前要把模型从
/// asset 拷贝到 App 的文档目录。
///
/// 靠 `web/models/<group>/manifest.json`（本来给 Web 挂载用的）来知道要拷哪些文件，
/// 不用在 Dart 里再维护一份清单。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 工程里的模型目录（asset 路径前缀）
const String kZipvoiceAssetDir = 'web/models/zipvoice';
const String kAsrAssetDir = 'web/models/asr';

/// 拷贝完成后落在 App 文档目录里的路径；没拷贝过就是 null。
String? _voiceDir;
String? _asrDir;

/// ZipVoice 模型目录（Web 版本是挂载路径，这里是文档目录下的真实路径）
String get kModelDir => _voiceDir ?? kZipvoiceAssetDir;

/// Whisper 模型目录
String get kAsrModelDir => _asrDir ?? kAsrAssetDir;

/// 是否已经把模型准备好了（UI 可以拿它显示「首次准备中」）
bool get modelsReady => _voiceDir != null && _asrDir != null;

Future<void> ensureMounted({void Function(String)? onStatus}) async {
  _voiceDir ??= await _prepare('zipvoice', kZipvoiceAssetDir, onStatus);
}

Future<void> ensureAsrMounted({void Function(String)? onStatus}) async {
  _asrDir ??= await _prepare('asr', kAsrAssetDir, onStatus);
}

/// 把 [assetDir] 下的模型按 manifest 拷到 App 文档目录，返回目标目录。
///
/// 幂等：目标目录里已经有一个同名 `.sini_ready` 标记就直接复用，不重复拷。
Future<String> _prepare(
  String tag,
  String assetDir,
  void Function(String)? onStatus,
) async {
  final root = await getApplicationDocumentsDirectory();
  final target = Directory('${root.path}/sini_models/$tag');
  final stamp = File('${target.path}/.sini_ready');

  if (await stamp.exists()) return target.path;
  await target.create(recursive: true);

  onStatus?.call('正在准备模型文件（首次较长）…');
  final manifestRaw = await rootBundle.loadString('$assetDir/manifest.json');
  final manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
  final dirs = (manifest['dirs'] as List? ?? const [])
      .whereType<String>()
      .toList();
  final files = (manifest['files'] as List? ?? const [])
      .whereType<String>()
      .toList();

  for (final d in dirs) {
    await Directory('${target.path}/$d').create(recursive: true);
  }

  var done = 0;
  for (final f in files) {
    final out = File('${target.path}/$f');
    if (!await out.parent.exists()) {
      await out.parent.create(recursive: true);
    }
    try {
      final data = await rootBundle.load('$assetDir/$f');
      await out.writeAsBytes(data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ));
    } catch (_) {
      // 单个文件缺失不致命（比如某些 espeak 语音），跳过继续
    }
    done++;
    if (done % 50 == 0) {
      onStatus?.call('正在准备模型文件… $done/${files.length}');
    }
  }

  await stamp.writeAsString('ok');
  return target.path;
}
