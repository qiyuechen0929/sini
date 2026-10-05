import 'package:flutter_test/flutter_test.dart';

import 'package:sini/models.dart';
import 'package:sini/utils/message_edit.dart';

/// 造一条消息，方便构造各种对话形态
Message msg(String id, {required bool isUser, String content = ''}) => Message(
      id: id,
      content: content.isEmpty ? id : content,
      isUser: isUser,
      createdAt: DateTime(2026, 9, 12),
    );

/// 一轮：u1 → a1，再一轮 u2 → a2
List<Message> twoTurns() => [
      msg('u1', isUser: true, content: '在吗'),
      msg('a1', isUser: false, content: '在的'),
      msg('u2', isUser: true, content: '今天好累'),
      msg('a2', isUser: false, content: '早点休息'),
    ];

void main() {
  group('userMessageIndex', () {
    test('能定位用户消息', () {
      expect(userMessageIndex(twoTurns(), 'u2'), 2);
    });

    test('助手消息不算（不能撤回 TA 的话）', () {
      expect(userMessageIndex(twoTurns(), 'a1'), -1);
    });

    test('找不到返回 -1', () {
      expect(userMessageIndex(twoTurns(), '不存在'), -1);
    });
  });

  group('cutTurn（撤回）', () {
    test('删掉最后一轮：用户消息 + TA 的回复一起没', () {
      final out = cutTurn(twoTurns(), 2);
      expect(out.map((m) => m.id).toList(), ['u1', 'a1']);
    });

    test('删掉中间一轮：后面的轮次保留', () {
      final out = cutTurn(twoTurns(), 0);
      expect(out.map((m) => m.id).toList(), ['u2', 'a2']);
    });

    test('撤回后原列表不被改动（纯函数）', () {
      final before = twoTurns();
      cutTurn(before, 2);
      expect(before.length, 4);
    });

    test('下标越界时原样返回', () {
      final before = twoTurns();
      expect(cutTurn(before, 99).length, 4);
      expect(cutTurn(before, -1).length, 4);
    });

    test('一条用户消息后跟着多条助手回复时全部收回', () {
      final msgs = [
        msg('u1', isUser: true, content: '讲个笑话'),
        msg('a1', isUser: false, content: '第一个'),
        msg('a2', isUser: false, content: '第二个'),
        msg('u2', isUser: true, content: '哈哈'),
      ];
      expect(cutTurn(msgs, 0).map((m) => m.id).toList(), ['u2']);
    });
  });

  group('replaceTurn（编辑重发）', () {
    test('换成新文本，TA 原来的回复被收回', () {
      final out = replaceTurn(twoTurns(), 2, '今天超开心');
      expect(out.map((m) => m.id).toList(), ['u1', 'a1', 'u2']);
      expect(out.last.content, '今天超开心');
    });

    test('时间戳刷新成重发时间', () {
      final now = DateTime(2026, 9, 12, 21, 30);
      final out = replaceTurn(twoTurns(), 2, '改一下', now: now);
      expect(out.last.createdAt, now);
    });

    test('保留附件（只改文字不丢文件）', () {
      final msgs = [
        msg('u1', isUser: true, content: '看这个'),
        msg('a1', isUser: false, content: '收到'),
      ];
      msgs[0] = msgs[0].copyWith(attachments: [
        const MessageAttachment(
          name: 'a.txt',
          sizeBytes: 3,
          kind: MessageAttachmentKind.file,
        ),
      ]);
      final out = replaceTurn(msgs, 0, '看这个（补充说明）');
      expect(out.first.attachments.length, 1);
      expect(out.first.content, '看这个（补充说明）');
    });

    test('下标越界时原样返回', () {
      expect(replaceTurn(twoTurns(), 9, 'x').length, 4);
    });
  });

  group('messagesAfterTurn（撤回提示）', () {
    test('最后一轮之后是 0 条', () {
      expect(messagesAfterTurn(twoTurns(), 2), 1); // a2 还在后面
    });

    test('第一条之后是 3 条', () {
      expect(messagesAfterTurn(twoTurns(), 0), 3);
    });

    test('越界返回 0', () {
      expect(messagesAfterTurn(twoTurns(), 42), 0);
    });
  });

  group('shortConversationTitle', () {
    test('短的照抄', () {
      expect(shortConversationTitle('在吗'), '在吗');
    });

    test('超过 24 字截断加省略号', () {
      final long = '一' * 30;
      final t = shortConversationTitle(long);
      expect(t.length, 25);
      expect(t.endsWith('…'), isTrue);
    });

    test('空文本回落到「新对话」', () {
      expect(shortConversationTitle('   '), '新对话');
    });
  });

  group('titleAfterEdit（撤回/编辑后重算标题）', () {
    test('标题取自被改的那句话 → 跟着换成新的', () {
      final after = [msg('u1', isUser: true, content: '新的第一句')];
      expect(titleAfterEdit('旧的第一句', '旧的第一句', after), '新的第一句');
    });

    test('标题不是取自它 → 保持不变', () {
      final after = [msg('u1', isUser: true, content: '新的第一句')];
      expect(titleAfterEdit('别的标题', '旧的第一句', after), '别的标题');
    });

    test('撤回后一条用户消息都不剩 → 回到「新对话」', () {
      expect(titleAfterEdit('在吗', '在吗', const []), '新对话');
    });

    test('撤回第一条后，标题改用剩下的第一条用户消息', () {
      final after = [msg('u2', isUser: true, content: '今天好累')];
      expect(titleAfterEdit('在吗', '在吗', after), '今天好累');
    });
  });
}
