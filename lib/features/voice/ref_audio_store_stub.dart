/// 非 Web（Android / iOS / 桌面）的参考音频存储：写进 App 文档目录的文件。
///
/// Web 版走 IndexedDB，这里走文件系统，但对上层接口完全一致。
/// 隐私边界不变：**只存本机，绝不上传**。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

Future<Directory> _dir() async {
  final root = await getApplicationDocumentsDirectory();
  final d = Directory('${root.path}/sini_voices');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

Future<void> save(String personaId, Uint8List wavBytes) async {
  final d = await _dir();
  await File('${d.path}/${_safe(personaId)}.wav').writeAsBytes(wavBytes);
}

Future<Uint8List?> load(String personaId) async {
  try {
    final d = await _dir();
    final f = File('${d.path}/${_safe(personaId)}.wav');
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<void> delete(String personaId) async {
  try {
    final d = await _dir();
    final f = File('${d.path}/${_safe(personaId)}.wav');
    if (await f.exists()) await f.delete();
  } catch (_) {
    // 删不掉就算了，别让「撤销授权」失败
  }
}
