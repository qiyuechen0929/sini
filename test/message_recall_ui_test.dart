import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sini/app_state.dart';
import 'package:sini/models.dart';
import 'package:sini/theme.dart';
import 'package:sini/widgets/markdown_view.dart';
import 'package:sini/widgets/message_bubble.dart';

/// 「撤回 / 编辑重发」的界面交互测试：
/// 长按自己的消息 → 菜单 → 两个动作各自真的落到对话数据上。
/// 纯裁剪逻辑在 message_edit_test.dart 里单独测。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 只渲染一条消息的气泡，避免聊天页整页的依赖
  Widget host(AppState state, String convId, Message m) => AppStateScope(
        state: state,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: MessageBubble(
                  message: m,
                  conversationId: convId,
                  persona: null,
                ),
              ),
            ),
          ),
        ),
      );

  Future<(AppState, String, Message)> setUpState(WidgetTester tester) async {
    // 默认测试视口只有 800×600，底部 sheet 的按钮会被挤出屏幕点不到
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = AppState();
    addTearDown(state.dispose);
    state.newConversation(firstMessage: '在吗');
    final conv = state.activeConversation!;
    final m = conv.messages.first;
    await tester.pumpWidget(host(state, conv.id, m));
    return (state, conv.id, m);
  }

  /// 等弹层进 / 出场动画走完，避免上一层的文字还在树里造成 finder 重名
  Future<void> settle(WidgetTester tester) =>
      tester.pumpAndSettle(const Duration(milliseconds: 50));

  Future<void> openMenu(WidgetTester tester) async {
    await tester.longPress(find.byType(SiniMarkdown));
    await settle(tester);
  }

  testWidgets('长按自己的消息 → 弹出 复制 / 编辑重发 / 撤回', (tester) async {
    await setUpState(tester);

    await openMenu(tester);

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('编辑重发'), findsOneWidget);
    expect(find.text('撤回'), findsOneWidget);
  });

  testWidgets('撤回：确认后这条消息从对话里消失', (tester) async {
    final (state, _, _) = await setUpState(tester);

    await openMenu(tester);
    await tester.tap(find.text('撤回'));
    await settle(tester);

    // 先弹确认（因为 TA 的回复会一起收回）
    expect(find.text('撤回这条消息？'), findsOneWidget);

    await tester.tap(find.text('确认撤回'));
    await settle(tester);

    expect(state.activeConversation!.messages, isEmpty,
        reason: '撤回后这条消息应该从对话里拿掉');
  });

  testWidgets('编辑重发：输入框预填原文，确认后替换成新说法', (tester) async {
    final (state, _, _) = await setUpState(tester);

    await openMenu(tester);
    await tester.tap(find.text('编辑重发'));
    await settle(tester);

    // 输入框里应该是原文，方便就地改
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '在吗');

    await tester.enterText(find.byType(TextField), '在吗？我改主意了');
    await tester.pump();
    await tester.tap(find.text('重新发送'));
    await settle(tester);

    final msgs = state.activeConversation!.messages;
    expect(msgs.first.content, '在吗？我改主意了');
    expect(msgs.first.isUser, isTrue);
  });

  testWidgets('取消撤回：消息还在', (tester) async {
    final (state, _, _) = await setUpState(tester);

    await openMenu(tester);
    await tester.tap(find.text('撤回'));
    await settle(tester);
    await tester.tap(find.text('取消'));
    await settle(tester);

    expect(state.activeConversation!.messages.length, 1);
    expect(state.activeConversation!.messages.first.content, '在吗');
  });
}
