/// 平台桥门面：只把「只有浏览器/只有原生才能做的事」包成一层，
/// 让业务代码不用直接 import `dart:html` / `dart:io`。
///
/// 为什么需要它：`dart:html` 在 Android 上是**编译不过**的（不是运行时报错，
/// 是根本编不出来），而这几件事在 Web 和原生上做法完全不同：
///
/// | 能力 | Web | Android / iOS |
/// | --- | --- | --- |
/// | 存文件 | Blob + a[download] 触发下载 | 写进 App 文档目录，返回路径给 UI 提示 |
/// | 开外链 | window.open | 原生 Intent / UIApplication.open |
/// | 内嵌 HTML 预览 | platformViewRegistry + iframe | 不支持，返回 null 让调用方降级 |
///
/// 拆成 门面 + `_web` + `_stub` 三件套，和项目里 `notify*.dart` 一个套路。
library;

import 'web_bridge_stub.dart'
    if (dart.library.js_interop) 'web_bridge_web.dart' as impl;

/// 触发一次文件保存/下载。
///
/// Web 上就是浏览器下载（返回 null，界面上不需要额外提示）；
/// 原生上写进 App 文档目录并**返回完整路径**，调用方应该把它提示给用户，
/// 否则用户点了「下载」会以为没反应。
Future<String?> saveFileBytes(
  String fileName,
  List<int> bytes,
  String mime,
) =>
    impl.saveFileBytes(fileName, bytes, mime);

/// 用系统默认方式打开一个外部链接（地图、网页等）。
Future<void> openExternalUrl(String url) => impl.openExternalUrl(url);

/// 把一段 HTML 注册成可内嵌的 platform view，返回 viewType。
///
/// 只有 Web 支持（用 iframe）。其它平台返回 null，调用方应降级成
/// 「保存成 .html 文件」或者纯文本预览。
String? registerHtmlPreviewView(String htmlContent) =>
    impl.registerHtmlPreviewView(htmlContent);
