import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 分享 / 存相册 / 导出文件的统一实现。
///
/// Android 坑：
/// - `XFile.fromData` 走系统分享时，部分机型/微信会报「多文件分享仅支持图片格式」
///   → 先落成真实临时文件再分享。
/// - 相册保存：优先 `saveFile`，失败退回 `saveImage`。
/// - 导出养成包：让用户选目录；选不到就落到「下载」目录并回显完整路径。

Future<File> writeTempFile(String name, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final f = File('${dir.path}/$safe');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

/// 系统分享：单张图片 + 文案（避免多文件/非图片触发厂商限制）。
Future<ShareResult> shareImageFile({
  required Uint8List bytes,
  required String fileName,
  required String text,
  String? subject,
}) async {
  if (kIsWeb) {
    // Web 没有临时文件路径，退回 fromData（浏览器分享）
    return SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, name: fileName, mimeType: 'image/png')],
      text: text,
      subject: subject,
    ));
  }
  final file = await writeTempFile(fileName, bytes);
  return SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'image/png', name: fileName)],
    text: text,
    subject: subject,
  ));
}

/// 保存 PNG 到系统相册。返回 null 表示成功；否则返回用户可读的失败原因。
Future<String?> savePngToGallery(Uint8List bytes, {String? name}) async {
  if (kIsWeb) return 'Web 请使用下载';
  final asciiName = 'sini_${DateTime.now().millisecondsSinceEpoch}';
  try {
    // 1) 写临时文件 → saveFile（对部分 ROM 更稳）
    final tmp = await writeTempFile('$asciiName.png', bytes);
    final r1 = await ImageGallerySaver.saveFile(tmp.path);
    if (_galleryOk(r1)) return null;
  } catch (_) {
    // 继续尝试 saveImage
  }
  try {
    final r2 = await ImageGallerySaver.saveImage(
      Uint8List.fromList(bytes),
      quality: 95,
      name: asciiName,
    );
    if (_galleryOk(r2)) return null;
    return '相册返回失败：$r2';
  } catch (e) {
    return '$e';
  }
}

bool _galleryOk(dynamic r) {
  if (r is Map) {
    return r['isSuccess'] == true || r['isSuccess'] == 'true';
  }
  return false;
}

/// 导出文本到用户指定目录。
/// 返回 (ok, message)：成功时 message 是完整路径；失败时是原因。
Future<({bool ok, String message})> exportTextToPickedDir({
  required String fileName,
  required String content,
  required String dirPath,
}) async {
  try {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content, flush: true);
    return (ok: true, message: file.path);
  } catch (e) {
    return (ok: false, message: '$e');
  }
}

/// 找一个用户可见的兜底目录（优先「下载」，其次应用文档）。
Future<Directory> fallbackExportDir() async {
  try {
    final dl = await getDownloadsDirectory();
    if (dl != null) {
      if (!await dl.exists()) await dl.create(recursive: true);
      return dl;
    }
  } catch (_) {}
  try {
    final ext = await getExternalStorageDirectory();
    if (ext != null) {
      final dl = Directory('${ext.path}/Download');
      if (!await dl.exists()) await dl.create(recursive: true);
      return dl;
    }
  } catch (_) {}
  final docs = await getApplicationDocumentsDirectory();
  final out = Directory('${docs.path}/似你导出');
  if (!await out.exists()) await out.create(recursive: true);
  return out;
}

@visibleForTesting
void debugNoop() {}
