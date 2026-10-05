/// 系统通知的**平台无关门面**。
///
/// 为什么需要这一层：
/// 真实实现依赖 `dart:js_util`，它**只在 Web 平台存在**。如果直接 import，
/// `flutter test`（跑在 VM 上）会编译失败、非 Web 构建也会挂。
/// 所以用条件导入把实现拆成两份：
///   - `notify_web.dart`  → 真实现（调 window.siniNotify）
///   - `notify_stub.dart` → 空实现（非 Web 平台，全部安全降级）
///
/// 调用方只 `import 'notify.dart'`，不感知平台差异。
library;

import 'notify_stub.dart'
    if (dart.library.js_util) 'notify_web.dart' as impl;

/// 通知权限状态
enum NotifyPermission { granted, denied, defaultState }

/// 浏览器是否支持系统通知（非 Web 平台恒为 false）
bool get notifySupported => impl.notifySupported;

/// 当前通知权限
NotifyPermission get notifyPermission => impl.notifyPermission;

/// 用户是否正看着页面（非 Web 恒为 true，即"当作可见"，少弹通知）
bool get pageVisible => impl.pageVisible;

/// 申请通知权限（必须在用户点击事件里调用）
Future<NotifyPermission> requestNotifyPermission() =>
    impl.requestNotifyPermission();

/// 弹一条系统通知，返回是否真的弹出
bool showSystemNotification({
  required String title,
  required String body,
  String tag = 'sini-proactive',
  String? iconPath,
}) =>
    impl.showSystemNotification(
      title: title,
      body: body,
      tag: tag,
      iconPath: iconPath,
    );

/// 改网页标题（切到别的标签页时的"有人找你"提示）
void setDocumentTitle(String title) => impl.setDocumentTitle(title);
