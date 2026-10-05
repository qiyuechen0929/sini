/// Web 平台的系统通知实现（Web Notification API）。
///
/// 为什么用 Web Notification 而不是 App 内弹窗：
/// 用户要的是「它来找我时，手机消息栏要有提示，息屏桌面也要有弹窗」——
/// 这是**操作系统级**的通知，只有浏览器 Notification API 能做到：
///  - 页面切到后台 / 用户在看别的标签页时，通知依然会弹（走系统通知中心）；
///  - 手机 / 桌面系统的锁屏、通知栏会显示这条通知；
///  - 点通知能把页面拉回前台并聚焦到「似你」。
///
/// 实现注意（踩过的坑，务必保留）：
/// 1. Dart 的 `dart:html` 里 `Notification` 构造器是**类型化封装**，只暴露
///    dir/body/lang/tag/icon 五个参数，**没有 `requireInteraction`**——而它恰恰是
///    "桌面弹窗停住不自动消失"的关键。所以原生 JS 逻辑放在 `web/index.html`
///    的 `window.siniNotify*` 里，Dart 侧只做薄调用。
/// 2. `supported` / `permission` / `isVisible` 是 **window.siniNotify 对象上的
///    getter**，不是 window 的全局函数。必须 `getProperty(helper, 'supported')`，
///    早期写成 `callMethod(globalThis, 'supported')` 会抛错并被 catch 吞掉，
///    表现为"明明支持却提示不支持"——这个 bug 已经在真实浏览器里复现并修复过。
///
/// 局限：
///  - 浏览器要求 **用户手势** 才能申请权限，所以只能在用户点开关时申请；
///  - 页面完全关闭后网页无法自己发通知（需 Web Push + Service Worker）。
library;

import 'dart:js_util' as jsu;

import 'notify.dart' show NotifyPermission;

/// 取 window.siniNotify 对象（由 web/index.html 注入）
Object? get _helper {
  try {
    return jsu.getProperty<Object?>(jsu.globalThis, 'siniNotify');
  } catch (_) {
    return null;
  }
}

bool get notifySupported {
  final h = _helper;
  if (h == null) return false;
  try {
    return jsu.getProperty<Object?>(h, 'supported') == true;
  } catch (_) {
    return false;
  }
}

NotifyPermission get notifyPermission {
  final h = _helper;
  if (h == null) return NotifyPermission.denied;
  String s;
  try {
    s = (jsu.getProperty<Object?>(h, 'permission') as String?) ?? 'denied';
  } catch (_) {
    return NotifyPermission.denied;
  }
  switch (s) {
    case 'granted':
      return NotifyPermission.granted;
    case 'denied':
      return NotifyPermission.denied;
    default:
      return NotifyPermission.defaultState;
  }
}

bool get pageVisible {
  final h = _helper;
  if (h == null) return true; // 未知时保守认为可见（少弹通知）
  try {
    return jsu.getProperty<Object?>(h, 'isVisible') == true;
  } catch (_) {
    return true;
  }
}

Future<NotifyPermission> requestNotifyPermission() async {
  try {
    if (jsu.getProperty<Object?>(jsu.globalThis, 'siniNotifyRequest') == null) {
      return NotifyPermission.denied;
    }
    final res =
        jsu.callMethod<Object?>(jsu.globalThis, 'siniNotifyRequest', const []);
    final s = await jsu.promiseToFuture<String>(res as Object);
    switch (s) {
      case 'granted':
        return NotifyPermission.granted;
      case 'denied':
        return NotifyPermission.denied;
      default:
        return NotifyPermission.defaultState;
    }
  } catch (_) {
    return NotifyPermission.denied;
  }
}

bool showSystemNotification({
  required String title,
  required String body,
  String tag = 'sini-proactive',
  String? iconPath,
}) {
  try {
    if (jsu.getProperty<Object?>(jsu.globalThis, 'siniNotifyShow') == null) {
      return false;
    }
    final r = jsu.callMethod<Object?>(
      jsu.globalThis,
      'siniNotifyShow',
      [title, body, tag, iconPath ?? 'icons/Icon-192.png'],
    );
    return r == true;
  } catch (_) {
    return false;
  }
}

void setDocumentTitle(String title) {
  try {
    jsu.setProperty(
        jsu.getProperty<Object>(jsu.globalThis, 'document'), 'title', title);
  } catch (_) {}
}
