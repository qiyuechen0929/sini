import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sini/app_state.dart';
import 'package:sini/models.dart';

/// 复现「发完邮件后正常对话失效」：
/// 写信卡片 → 寄出/残留 → 再发普通消息必须恢复正常回复路径。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('写信流程结束后，普通消息要走 _runAssistant（有错误回复而不是卡住）', () async {
    final state = AppState();
    await state.setEmailBinding('2652909926@qq.com');

    // 1) 触发写信
    state.sendUserMessage('给 test@example.com 发邮件邀请周六吃饭');
    await Future.delayed(const Duration(milliseconds: 50));
    expect(state.emailCompose, isNotNull, reason: '应进入写信流程');
    final conv1 = state.activeConversation!;
    expect(conv1.messages.last.emailCompose, isTrue,
        reason: '最后一条助手消息应是写信卡片');

    // 2) 不真的发送（避免网络），直接再发一条普通消息
    //    —— 遗留的写信卡片应被自动归档，且要走正常回复路径
    state.sendUserMessage('你好');
    await Future.delayed(const Duration(milliseconds: 50));

    expect(state.emailCompose, isNull, reason: '遗留明信片应被归档');
    final conv2 = state.activeConversation!;
    // 归档后的卡片消息变成文字（未寄出 → 取消说明）
    expect(conv2.messages.any((m) => m.content.contains('已取消写信')), isTrue,
        reason: '旧卡片应被归档成文字消息');
    // 最后一条应是助手回复（无模型时的错误提示也算正常回复）
    final last = conv2.messages.last;
    expect(last.isUser, isFalse, reason: '「你好」应得到助手回复');
    expect(last.content.isNotEmpty, isTrue, reason: '回复内容不应为空');
    expect(last.content.contains('已取消写信'), isFalse,
        reason: '不应把新消息当成写信流程处理');
  });
}
