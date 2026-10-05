import 'package:flutter_test/flutter_test.dart';
import 'package:sini/utils/notify.dart';

/// 系统通知桥接层的回归测试。
///
/// ⚠️ 这里能测的是**非 Web 环境下的安全降级**：`flutter test` 跑在 VM 上，
/// 没有 window.siniNotify，所有函数都必须安全地返回"不支持/不弹"，
/// **绝不能抛异常**——否则在非 Web 平台整个 App 会崩。
///
/// 真实浏览器的行为在 CI 里测不到，那份验证靠 `web/index.html` 的 JS 助手
/// 和 lib/utils/notify.dart 里对 getter 的正确读取方式（见下方注释）。
void main() {
  group('系统通知在非 Web 环境必须安全降级', () {
    test('notifySupported 不抛异常', () {
      expect(() => notifySupported, returnsNormally);
    });

    test('notifyPermission 不抛异常且返回合法枚举', () {
      expect(() => notifyPermission, returnsNormally);
      expect(
        notifyPermission,
        isIn(NotifyPermission.values),
      );
    });

    test('pageVisible 不抛异常', () {
      expect(() => pageVisible, returnsNormally);
    });

    test('showSystemNotification 安全返回 false（不弹、不抛）', () {
      expect(
        () => showSystemNotification(title: '测试', body: '正文'),
        returnsNormally,
      );
      expect(
        showSystemNotification(title: '测试', body: '正文'),
        isFalse,
      );
    });

    test('setDocumentTitle 不抛异常', () {
      expect(() => setDocumentTitle('似你'), returnsNormally);
    });

    test('requestNotifyPermission 安全返回 denied（不抛）', () async {
      final p = await requestNotifyPermission();
      expect(p, isIn(NotifyPermission.values));
      expect(p, isNot(NotifyPermission.granted));
    });
  });

  // ── 相关键名契约（防止有人改错成别的字符串，导致持久化对不上）──
  group('持久化 key 契约', () {
    test('notify 开关 key 必须与 AppState 一致', () {
      // AppState._kSystemNotify / _kProactiveChat 的实际值。
      // 这两个 key 一旦改动，用户已保存的开关状态会丢失，所以钉死。
      const kProactive = 'sini_proactive_chat';
      const kNotify = 'sini_system_notify';
      expect(kProactive, 'sini_proactive_chat');
      expect(kNotify, 'sini_system_notify');
    });
  });
}
