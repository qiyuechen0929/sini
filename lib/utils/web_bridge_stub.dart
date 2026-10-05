/// 非 Web（Android / iOS / 桌面）实现。
///
/// - 存文件：写进 App 文档目录，并把**完整路径**返回给调用方去提示用户。
/// - 开外链：走一个极小的 MethodChannel，由原生侧用系统 Intent / openURL 打开。
///   （没引 `url_launcher`：这台机器外网不通、拉不到新包，而这件事只需要几行原生代码。）
/// - 内嵌 HTML 预览：原生没有 platform view 的等价物，返回 null 让调用方降级。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const MethodChannel _native = MethodChannel('sini/native');

/// 文件名里不能出现的字符（Android/iOS 文件系统都别用）
String _sanitize(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();

Future<String?> saveFileBytes(
  String fileName,
  List<int> bytes,
  String mime,
) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/似你导出');
    if (!await outDir.exists()) await outDir.create(recursive: true);
    final safe = _sanitize(fileName);
    final path = '${outDir.path}/${safe.isEmpty ? '似你导出' : safe}';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  } catch (e) {
    return null;
  }
}

Future<void> openExternalUrl(String url) async {
  try {
    await _native.invokeMethod<void>('openUrl', {'url': url});
  } on MissingPluginException {
    // 原生侧没实现（比如桌面端）——静默降级，不要因为一个跳转把界面搞崩
  } catch (_) {
    // 没有可打开该链接的应用等情况，同样静默
  }
}

String? registerHtmlPreviewView(String htmlContent) => null;
