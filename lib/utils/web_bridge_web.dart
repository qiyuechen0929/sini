/// Web 端实现：Blob + `<a download>` + `window.open` + iframe platform view。
library;

import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

Future<String?> saveFileBytes(
  String fileName,
  List<int> bytes,
  String mime,
) async {
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement()
    ..href = url
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
  // 浏览器自己处理下载，UI 不需要再提示路径
  return null;
}

Future<void> openExternalUrl(String url) async {
  html.window.open(url, '_blank');
}

int _previewCounter = 0;

String? registerHtmlPreviewView(String htmlContent) {
  final bytes = utf8.encode(htmlContent);
  final blob = html.Blob([bytes], 'text/html;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final id = ++_previewCounter;
  final viewType = 'sini-html-preview-$id';
  final iframe = html.IFrameElement()
    ..src = url
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.borderRadius = '12px';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) => iframe);
  return viewType;
}
