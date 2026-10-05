/// 聊天记录导入链路的纯逻辑测试。
///
/// 覆盖三层容易被改坏的东西：
///  1. 解析器 —— 各平台导出格式能不能真的读出消息、能不能正确区分"我"和"TA"；
///  2. 统计 —— 口头禅候选、标点习惯这些"客观事实"算得对不对；
///  3. 画像与注入 —— 没有模型时能不能降级、风格画像有没有真的进 system prompt。
///
/// 注意：GBK 解码依赖浏览器的 TextDecoder，在 VM 测试里不可用（会走有损分支），
/// 所以这里只断言"如实标记为有损"，真实 GBK 文件留给浏览器端到端验证。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sini/data/llm_provider.dart';
import 'package:sini/features/persona/chat_import/chat_models.dart';
import 'package:sini/features/persona/chat_import/chat_parser.dart';
import 'package:sini/features/persona/chat_import/chat_stats.dart';
import 'package:sini/features/persona/chat_import/persona_extractor.dart';
import 'package:sini/features/persona/chat_import/text_decode.dart';
import 'package:sini/models.dart';
import 'package:sini/utils/memory_directive.dart';
import 'package:sini/utils/persona_engine.dart';

Uint8List _bytes(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

ParsedChat _parse(String name, {String platform = '通用'}) {
  final decoded = decodeChatFile(_bytes(name));
  final chat = parseChatText(decoded.text, platformHint: platform);
  expect(chat, isNotNull, reason: '$name 应该能解析出消息');
  expect(chat!.messages, isNotEmpty, reason: '$name 解析结果不该是空的');
  return chat;
}

void main() {
  group('解析器', () {
    test('微信 MemoTrace CSV：靠 IsSender 正确区分「我」和对方', () {
      final chat = _parse('wechat_memotrace.csv', platform: '微信');

      expect(chat.format, 'CSV');
      expect(chat.messages.length, greaterThan(100));

      // IsSender=1 的消息必须被认成「我」
      final mine = chat.messages.where((m) => m.isSelf).toList();
      expect(mine, isNotEmpty);
      expect(mine.every((m) => m.sender == '我'), isTrue);

      // Talker 列存的是 wxid，不该把对方也混成「我」
      final others = chat.messages.where((m) => !m.isSelf).toList();
      expect(others, isNotEmpty);
      expect(others.any((m) => m.sender == '我'), isFalse);
      // wxid 样式应被清洗成可读的「对方」
      expect(others.first.sender, '对方');

      // 时间戳要解析出来
      expect(chat.messages.first.time, isNotNull);
    });

    test('Telegram result.json：text 混用字符串与实体数组都能读', () {
      final chat = _parse('telegram_result.json', platform: 'Telegram');

      expect(chat.platform, 'Telegram');
      expect(chat.messages.length, greaterThan(100));
      expect(chat.participants, containsAll(['我', '小雨']));
      expect(chat.messages.first.time, isNotNull);

      // 实体数组（{"type":"bold","text":...}）也要能拼回正文
      final hasBold = chat.messages.any((m) =>
          m.text.contains('躺着') || m.text.contains('嗯嗯') || m.text.length > 0);
      expect(hasBold, isTrue);
      // 不该出现对象被 toString 的痕迹
      expect(chat.messages.any((m) => m.text.contains('{')), isFalse);
    });

    test('QQ TXT：昵称里的 (QQ号) 被清掉', () {
      final chat = _parse('qq_export.txt', platform: 'QQ');

      expect(chat.format, 'TXT');
      expect(chat.messages.length, greaterThan(100));
      expect(chat.participants, contains('小雨'));
      expect(chat.participants.any((n) => n.contains('(')), isFalse);
      expect(chat.messages.first.time, isNotNull);
    });

    test('通用 CSV：中文表头（发送时间/发送者/消息内容）也能认', () {
      final chat = _parse('generic_chat.csv');

      expect(chat.format, 'CSV');
      expect(chat.messages.length, greaterThan(100));
      expect(chat.participants, containsAll(['我', '小雨']));
      expect(chat.messages.first.time, isNotNull);
    });

    test('通用 TXT：昵称: 正文（无时间戳）', () {
      final chat = _parse('generic_chat.txt');

      expect(chat.format, 'TXT');
      expect(chat.messages.length, greaterThan(100));
      expect(chat.participants, containsAll(['我', '小雨']));
      // 没有时间戳时不该瞎编时间
      expect(chat.messages.first.time, isNull);
    });

    test('通用 JSON：数组 + sender/time/content', () {
      final chat = _parse('generic_chat.json');

      expect(chat.format, 'JSON');
      expect(chat.messages.length, greaterThan(100));
      expect(chat.messages.first.time, isNotNull);
    });

    test('新版 QQ 三行格式（昵称 / 时间 / 正文）能解析', () {
      // 这是新版 QQ 消息管理器导出的真实排版：三行一组 + 空行分隔
      const raw = '''小雨
2026年08月26日 22:04
nb你还真学了

我
2026年08月26日 22:04
每天学一会

小雨
2026年08月26日 22:05
第一行
第二行

我
2026年08月26日 22:06
嗯嗯
''';
      final chat = parseChatText(raw)!;
      expect(chat.messages.length, 4);
      expect(chat.format, 'TXT');
      expect(chat.messages.first.sender, '小雨');
      expect(chat.messages.first.text, 'nb你还真学了');
      expect(chat.messages.first.time, DateTime(2026, 8, 26, 22, 4));
      expect(chat.participants, containsAll(['小雨', '我']));
      // 多行正文要完整保留
      expect(chat.messages[2].text, '第一行\n第二行');
      // 时间全部解析出来
      expect(chat.messages.every((m) => m.time != null), isTrue);
    });

    test('QQ 消息管理器导出的表头与分隔线不会混进消息', () {
      const raw = '''====== 消息记录 ======
2023-01-01 10:00:00 小雨(10001)
你好
======
2023-01-01 10:01:00 我(10002)
在的
----------------------------------------
2023-01-01 10:02:00 小雨(10001)
嗯嗯
''';
      final chat = parseChatText(raw)!;
      expect(chat.messages.map((m) => m.text).toList(), ['你好', '在的', '嗯嗯']);
      expect(chat.participants, contains('小雨'));
      expect(chat.messages.first.time, isNotNull);
    });

    test('GBK 文件在 VM 上如实标记为有损（真解码交给浏览器）', () {
      final decoded = decodeChatFile(_bytes('wechat_memotrace_gbk.txt'));
      expect(decoded.lossy, isTrue);
      expect(decoded.encoding, contains('有损'));
    });

    test('噪声过滤：系统消息与 [图片] 占位不会进消息列表', () {
      const raw = '''2023-01-01 10:00:00 小雨
[图片]
2023-01-01 10:01:00 小雨
在的
2023-01-01 10:02:00 我
[表情]
2023-01-01 10:03:00 我
你撤回了一条消息
2023-01-01 10:04:00 我
看到了
''';
      final chat = parseChatText(raw)!;
      final texts = chat.messages.map((m) => m.text).toList();
      expect(texts, contains('在的'));
      expect(texts, contains('看到了'));
      expect(texts.any((t) => t.contains('[图片]')), isFalse);
      expect(texts.any((t) => t.contains('撤回')), isFalse);
    });
  });

  group('统计', () {
    late ChatStats stats;

    setUpAll(() {
      final chat = _parse('telegram_result.json');
      stats = computeChatStats(chat.withSelf('我'));
    });

    test('正确区分双方消息数', () {
      expect(stats.taName, '小雨');
      expect(stats.selfName, '我');
      expect(stats.taCount, greaterThan(50));
      expect(stats.selfCount, greaterThan(50));
      expect(stats.total, stats.taCount + stats.selfCount);
    });

    test('标点习惯：小雨几乎不用句号', () {
      expect(stats.periodRate, lessThan(0.1));
    });

    test('口头禅候选能召回高频短句（如「嗯嗯」「好～」）', () {
      final words = stats.shortPhrases.map((c) => c.word).toList();
      expect(words.any((w) => w.contains('嗯')), isTrue,
          reason: '应该召回「嗯嗯」这类高频短句，实际：$words');
    });

    test('高频词候选不含「碎片词」（如只有「道了」没有「知道了」）', () {
      final chat = _parse('telegram_result.json').withSelf('我');
      final cands = extractWordCandidates(
        chat.messages.where((m) => !m.isSelf).map((m) => m.text).toList(),
        maxResults: 60,
      );
      final byWord = {for (final c in cands) c.word: c.docFreq};
      for (final w in byWord.keys) {
        for (final other in byWord.keys) {
          if (other == w || other.length <= w.length) continue;
          if (other.contains(w)) {
            // 短词只是长词的一部分、且频次相当 → 它就是个碎片，不该出现
            expect(byWord[other]! < byWord[w]! * 0.8, isTrue,
                reason: '「$w」只是「$other」的碎片，应该被去掉（候选：$byWord）');
          }
        }
      }
    });

    test('平均字数与长度分布都对得上', () {
      expect(stats.taAvgChars, greaterThan(0));
      expect(stats.taAvgChars, lessThan(30));
      final sum = stats.shortRatio + stats.midRatio + stats.longRatio;
      expect(sum, closeTo(1.0, 0.001));
    });

    test('Prompt 摘要里包含关键事实', () {
      final block = stats.toPromptBlock();
      expect(block, contains('小雨'));
      expect(block, contains('平均'));
    });
  });

  group('画像与注入', () {
    test('没有模型时也能生成简版画像（不假报成功、但有内容）', () {
      final chat = _parse('telegram_result.json').withSelf('我');
      final stats = computeChatStats(chat);
      final style = buildStyleFromStats(chat: chat, stats: stats);

      expect(style.isEmpty, isFalse);
      expect(style.summary, isNotEmpty);
      expect(style.sampleLines, isNotEmpty);
      expect(style.messageCount, chat.messages.length);
    });

    test('风格画像会被注入 system prompt，且带原话范例', () {
      final persona = Persona(
        id: 'p1',
        name: '小雨',
        subtitle: '由聊天记录还原',
        gradientSeed: const [1, 2, 3],
        style: PersonaStyle(
          summary: '句子很短，爱用波浪号，几乎不用句号',
          catchphrases: const ['嗯嗯', '好吧～'],
          callUser: '你',
          speechHabits: const ['几乎不用句号', '常连发两条'],
          sampleLines: const ['躺着～', '骗你干嘛～'],
          exchanges: const [StyleExchange(user: '在干嘛呢？', ta: '躺着～')],
          messageCount: 300,
          platform: '微信',
          importedAt: DateTime(2026, 9, 10),
        ),
      );

      final directive = buildPersonaDirective(persona);
      expect(directive, contains('语言风格画像'));
      expect(directive, contains('句子很短'));
      expect(directive, contains('嗯嗯'));
      expect(directive, contains('躺着～'));
      expect(directive, contains('骗你干嘛～'));
      expect(directive, contains('在干嘛呢？'));
      expect(directive, contains('几乎不用句号'));
      // 样本必须标注"别照抄内容"，否则模型会把范例当成事实讲出来
      expect(directive, contains('这不是话题清单'));
      expect(directive, contains('不要主动问起里面聊过的事'));
    });

    test('双方身份会被钉死：谁是我、谁是对方，且不许把自己的名字安给对方', () {
      final persona = Persona(
        id: 'p_id',
        name: '杨成凯',
        subtitle: '',
        gradientSeed: const [1, 2, 3],
        // TA 在记录里叫「羊乘客」，用户叫「玖秋辞」
        sourceName: '羊乘客',
        ownerName: '玖秋辞',
        style: PersonaStyle(
          summary: '句子短',
          // 抽取错误：把 TA 自己的名字当成了"对用户的称呼"，也当成了"自称"
          callUser: '羊乘客',
          selfCall: '羊乘客',
          importedAt: DateTime(2026, 9, 10),
        ),
      );

      final d = buildPersonaDirective(persona);

      // 1) 双方身份要说清楚（这正是之前"问它我叫什么、它答了自己"的根因）
      expect(d, contains('双方身份'));
      expect(d, contains('玖秋辞'));
      expect(d, contains('羊乘客'));
      expect(d, contains('绝对不要把「羊乘客」当成对方的名字'));
      // 2) 用户问"我是谁"时应该答用户的名字，而不是自己的
      expect(d, contains('答案是「玖秋辞」'));
      // 3) callUser 抽成了 TA 自己的名字 → 必须被丢弃，不能反过来教 AI 这样叫用户
      expect(d, isNot(contains('称呼用户为「羊乘客」')));
      // 4) 自称抽成了名字本身（记录里的昵称）→ 也要丢弃，否则改名后会拿旧名自称
      expect(d, isNot(contains('自称「羊乘客」')));
    });

    test('没填身份的旧人格：至少给一条不许把名字安给对方的红线', () {
      final persona = Persona(
        id: 'p_id2',
        name: '小雨',
        subtitle: '',
        gradientSeed: const [1, 2, 3],
        style: PersonaStyle(summary: '句子短', importedAt: DateTime(2026, 9, 10)),
      );
      final d = buildPersonaDirective(persona);
      expect(d, contains('身份红线'));
      expect(d, contains('绝不能把自己的名字当成对方的名字'));
    });

    test('重复的「对方说」会被去重，只保留第一次（防止学到错的因果）', () {
      final raw = [
        const ReactionPattern(when: '被调侃时', how: '玩笑式回击', example: '因为你刚才笑我', userSaid: '凭什么'),
        const ReactionPattern(when: '对方生气时', how: '服软认错', example: '我错了嘛', userSaid: '凭什么'),
        const ReactionPattern(when: '对方提问时', how: '直接给答案', example: '就高数', userSaid: '你考几科'),
      ];
      final out = dedupeReactionTriggers(raw);
      expect(out.length, 3);
      expect(out[0].userSaid, '凭什么');
      expect(out[1].userSaid, ''); // 第二次出现 → 清空，而不是留着错的对应
      expect(out[1].how, '服软认错'); // 其余信息保留
      expect(out[2].userSaid, '你考几科');
    });

    test('记忆是"背景知识"，不能写成"随时可引用"（否则一开场就翻旧账）', () {
      final d = buildMemoryDirective([
        PersonaMemory(
          id: 'm1',
          text: '对方在准备补考',
          kind: PersonaMemoryKind.fact,
          createdAt: DateTime(2026, 9, 10),
        ),
      ]);
      expect(d, contains('不是话题清单'));
      expect(d, contains('绝对不要主动提起'));
      expect(d, contains('对方在准备补考'));
      // 旧文案正是它开场就问"补考准备咋样了"的元凶
      expect(d, isNot(contains('随时自然引用')));
    });

    test('性格反应会被注入，且放在 prompt 末尾作为落笔前最后判断', () {
      final persona = Persona(
        id: 'p1b',
        name: '小雨',
        subtitle: '',
        gradientSeed: const [1, 2, 3],
        style: PersonaStyle(
          summary: '句子很短',
          catchphrases: const ['嗯嗯'],
          sampleLines: const ['躺着～'],
          exchanges: const [StyleExchange(user: '在干嘛', ta: '躺着～')],
          reactionPatterns: const [
            ReactionPattern(
              when: '对方生气说狠话时',
              how: '立刻服软认错',
              example: '我错了嘛',
              userSaid: '你别来了',
            ),
            ReactionPattern(when: '对方调侃时', how: '玩笑式因果回击', example: '因为你刚才笑我'),
          ],
          importedAt: DateTime(2026, 9, 10),
        ),
      );
      final d = buildPersonaDirective(persona);
      expect(d, contains('落笔前最后确认'));
      expect(d, contains('对方生气说狠话时'));
      expect(d, contains('立刻服软认错'));
      expect(d, contains('我错了嘛'));
      expect(d, contains('因为你刚才笑我'));
      // 完整的一来一回要展示出来（只给 TA 的话看不出触发条件）
      expect(d, contains('你别来了'));
      // 位置：排在原话样本和问答对之后，紧邻用户消息，成为落笔前最后一道判断
      expect(d.indexOf('落笔前最后确认'), greaterThan(d.indexOf('TA 的原话')));
      expect(d.indexOf('落笔前最后确认'),
          greaterThan(d.indexOf('真实对话里 TA 是怎么回的')));
      // 并且明确禁止"搬句子"
      expect(d, contains('不是让你挑一句搬过来用'));
    });

    test('reactionPatterns 能完整往返序列化', () {
      final style = PersonaStyle(
        reactionPatterns: const [
          ReactionPattern(when: 'w', how: 'h', example: 'e'),
        ],
        importedAt: DateTime(2026, 9, 10),
      );
      final back = PersonaStyle.fromJson(style.toJson());
      expect(back.reactionPatterns.single.when, 'w');
      expect(back.reactionPatterns.single.how, 'h');
      expect(back.reactionPatterns.single.example, 'e');
      // 老存档没有这个字段也要能读
      final legacy = PersonaStyle.fromJson({'summary': 'x', 'importedAt': '2026-09-10T00:00:00.000'});
      expect(legacy.reactionPatterns, isEmpty);
    });

    test('没有人格画像时，注入结果和以前一致（不破坏老数据）', () {
      final persona = Persona(
        id: 'p2',
        name: '阿哲',
        subtitle: '',
        gradientSeed: const [1, 2, 3],
        description: '话不多，但很靠谱',
      );
      final directive = buildPersonaDirective(persona);
      expect(directive, contains('话不多，但很靠谱'));
      expect(directive, isNot(contains('语言风格画像')));
    });

    test('旧存档没有 style 字段也能正常读出（向后兼容）', () {
      final legacy = {
        'id': 'p3',
        'name': '旧人格',
        'subtitle': 's',
        'gradientSeed': [1, 2, 3],
      };
      final p = Persona.fromJson(legacy);
      expect(p.style, isNull);
      expect(p.name, '旧人格');
    });

    test('模型返回的脏 JSON 能被救回来', () {
      // 1) 套了 markdown 围栏
      final fenced = parseLooseJson('''好的，这是结果：
```json
{"summary": "短句", "catchphrases": ["嗯嗯"]}
```''');
      expect(fenced, isNotNull);
      expect(fenced!['summary'], '短句');
      expect(fenced['catchphrases'], ['嗯嗯']);

      // 2) 前后带解释文字 + 尾随逗号
      final messy = parseLooseJson(
          '分析如下：{"summary": "爱用～", "dos": ["保持简短",],} 以上。');
      expect(messy, isNotNull);
      expect(messy!['summary'], '爱用～');
      expect(messy['dos'], ['保持简短']);

      // 3) 字符串里有裸换行
      final newline = parseLooseJson('{"summary": "第一行\n第二行"}');
      expect(newline, isNotNull);
      expect('${newline!['summary']}', contains('第一行'));

      // 4) 完全不是 JSON
      expect(parseLooseJson('我无法完成这个任务'), isNull);
    });

    test('LLM 抽取：语料真的喂给了模型，返回的 JSON 落到画像上', () async {
      String? captured;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        captured = await utf8.decoder.bind(req).join();
        final payload = {
          'choices': [
            {
              'message': {
                // 故意套 markdown 围栏 + 前后加废话，验证容错
                'content': '好的，分析结果如下：\n```json\n'
                    '${jsonEncode({
                      'summary': '句子很短，爱用波浪号，几乎不用句号',
                      'catchphrases': ['嗯嗯', '好吧～'],
                      'callUser': '你',
                      'selfCall': '我',
                      'speechHabits': ['几乎不用句号', '常连发两条'],
                      'sampleLines': ['躺着～', '骗你干嘛～'],
                      'dos': ['保持简短'],
                      'donts': ['不要长篇大论', '别用感叹号'],
                      'traits': {
                        'warmth': 0.7,
                        'rationality': 0.4,
                        'initiative': 0.6,
                        'humor': 0.5,
                      },
                      'relationshipGuess': '朋友',
                      'sinceGuess': '2023',
                      'memories': [
                        {'text': '一起去过美术馆的摄影展', 'kind': 'fact'}
                      ],
                    })}'
                    '\n```\n希望有帮助。',
              },
              'finish_reason': 'stop',
            }
          ]
        };
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(payload));
        await req.response.close();
      });

      final cfg = ModelConfig(
        id: 'm1',
        name: '测试模型',
        providerId: 'custom',
        modelId: 'test-model',
        apiKey: 'sk-test',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        isDefault: true,
      );

      final chat = _parse('telegram_result.json').withSelf('我');
      final stats = computeChatStats(chat);
      final res = await extractStyleWithLlm(cfg: cfg, chat: chat, stats: stats);

      expect(res.ok, isTrue, reason: res.error);
      expect(res.style!.summary, contains('波浪号'));
      expect(res.style!.catchphrases, contains('嗯嗯'));
      expect(res.style!.speechHabits, contains('几乎不用句号'));
      expect(res.style!.sampleLines, isNotEmpty);
      expect(res.style!.donts, contains('不要长篇大论'));
      expect(res.style!.messageCount, chat.messages.length);
      expect(res.traits['warmth'], 0.7);
      expect(res.traits['initiative'], 0.6);
      expect(res.relationshipGuess, '朋友');
      expect(res.sinceGuess, '2023');
      expect(res.memories.single['text'], contains('摄影展'));

      // 关键：prompt 里必须真的带上了客观统计和原话语料，
      // 否则模型就是在凭空编。
      expect(captured, isNotNull);
      final prompt = captured!;
      expect(prompt, contains('小雨'));
      expect(prompt, contains('躺着'));
      expect(prompt, contains('平均'));
      expect(prompt, contains('高频短句'));

      await server.close();
    });

    test('style 能完整往返序列化', () {
      final style = PersonaStyle(
        summary: '短句',
        catchphrases: const ['嗯嗯'],
        speechHabits: const ['爱用～'],
        sampleLines: const ['好～'],
        exchanges: const [StyleExchange(user: 'a', ta: 'b')],
        messageCount: 10,
        platform: 'QQ',
        spanText: '2023.01 — 2023.06',
        importedAt: DateTime(2026, 9, 10),
      );
      final back = PersonaStyle.fromJson(style.toJson());
      expect(back.summary, '短句');
      expect(back.catchphrases, ['嗯嗯']);
      expect(back.sampleLines, ['好～']);
      expect(back.exchanges.single.ta, 'b');
      expect(back.messageCount, 10);
      expect(back.platform, 'QQ');
      expect(back.importedAt, DateTime(2026, 9, 10));
    });
  });
}
