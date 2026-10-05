/// 非 Web 平台的系统通知实现：全部安全降级（什么都不做，也不抛异常）。
///
/// 桌面 / 移动端原生通知需要额外的原生插件（如 flutter_local_notifications），
/// 本项目当前形态是 Flutter Web，所以这里保持空实现即可。
library;

import 'notify.dart' show NotifyPermission;

bool get notifySupported => false;
NotifyPermission get notifyPermission => NotifyPermission.denied;
bool get pageVisible => true;

Future<NotifyPermission> requestNotifyPermission() async =>
    NotifyPermission.denied;

bool showSystemNotification({
  required String title,
  required String body,
  String tag = 'sini-proactive',
  String? iconPath,
}) =>
    false;

void setDocumentTitle(String title) {}
