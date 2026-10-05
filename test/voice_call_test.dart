/// 语音通话相关的纯逻辑测试：分句、静音裁剪、VAD 状态机、流式 SSE 解析。
///
/// 这些是通话里最容易「看起来对、用起来不对」的部分，所以单独拎出来测。
/// 真实麦克风 / 音频播放没法在单测里跑，靠浏览器端验证（见 mobile_preview.html）。
///
/// 跑法（本机代理会劫持 flutter_tester，必须绕开）：
///   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
///       NO_PROXY="*" no_proxy="*" flutter test test/voice_call_test.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sini/data/llm_provider.dart';
import 'package:sini/features/voice/asr_text.dart';
import 'package:sini/features/voice/call/mic_capture.dart';
import 'package:sini/features/voice/call/sentence_splitter.dart';

void main() {
  // ═══════════════════════ 分句 ═══════════════════════

  group('SentenceSplitter', () {
    test('遇到句末标点就切，短句先攒着', () {
      final s = SentenceSplitter();
      // 「你好。」太短（< minChars 6），不单独成句
      expect(s.feed('你好。'), isEmpty);
      // 后面补齐到够长，一次吐出
      final out = s.feed('今天天气真不错，我们出去走走吧。');
      expect(out, ['你好。今天天气真不错，我们出去走走吧。']);
      expect(s.flush(), isNull);
    });

    test('流式喂入：句子边界一到就吐出来（不用等整段）', () {
      final s = SentenceSplitter();
      final out = <String>[];
      for (final piece in ['今天天气', '真不错，', '我们出去', '走走吧。', '好啊。']) {
        out.addAll(s.feed(piece));
      }
      // 第一句在「走走吧。」处就该出来，不必等「好啊。」
      expect(out, ['今天天气真不错，我们出去走走吧。']);
      expect(s.flush(), '好啊。');
    });

    test('太长又没句末标点时，在逗号处断开', () {
      final s = SentenceSplitter(minChars: 4, maxChars: 20);
      final out = s.feed('这是一段很长很长很长的话，但是一直没有句号');
      expect(out.length, 1);
      expect(out.first.endsWith('，'), isTrue);
      expect(out.first.length, lessThanOrEqualTo(20));
    });

    test('连逗号都没有时硬切，不会一直攒着', () {
      final s = SentenceSplitter(minChars: 4, maxChars: 10);
      final out = s.feed('abcdefghijklmnopqrstuvwxyz');
      expect(out, isNotEmpty);
      expect(out.first.length, 10);
    });

    test('flush 吐出剩余尾巴，空则返回 null', () {
      final s = SentenceSplitter();
      s.feed('还没说完');
      expect(s.flush(), '还没说完');
      expect(s.flush(), isNull);
    });
  });

  // ═══════════════════════ 静音裁剪 ═══════════════════════

  group('trimSilence', () {
    test('掐掉首尾静音，只留话音段（前后各留一点余量）', () {
      const sr = kMicSampleRate;
      final pcm = Float32List(sr); // 1 秒
      for (var i = (sr * 0.35).round(); i < (sr * 0.65).round(); i++) {
        pcm[i] = 0.3;
      }
      final out = trimSilence(pcm);
      expect(out.length, greaterThan(sr * 0.25));
      expect(out.length, lessThan(sr * 0.45));
    });

    test('整段都是静音 → 返回空', () {
      expect(trimSilence(Float32List(kMicSampleRate)).length, 0);
    });

    test('本来就短的片段原样返回', () {
      final short = Float32List(100);
      expect(trimSilence(short).length, 100);
    });
  });

  // ═══════════════════════ VAD ═══════════════════════

  group('VadGate', () {
    /// 按 64ms 一块喂进去，收集发生的事件（时间, 信号）
    List<(int, VadSignal)> drive(VadGate g, List<double> blocks,
        {int stepMs = 64}) {
      final out = <(int, VadSignal)>[];
      for (var i = 0; i < blocks.length; i++) {
        final t = i * stepMs;
        final s = g.push(blocks[i], t);
        if (s.event != VadEvent.none) out.add((t, s));
      }
      return out;
    }

    test('一直很安静 → 什么都不触发', () {
      final ev = drive(VadGate(), List.filled(80, 0.001));
      expect(ev, isEmpty);
    });

    test('说话 → 开口；静下来 → 收尾', () {
      final g = VadGate();
      final ev = drive(g, [
        ...List.filled(10, 0.001),
        ...List.filled(20, 0.2),
        ...List.filled(30, 0.001),
      ]);
      expect(ev.length, 2);
      expect(ev[0].$2.event, VadEvent.speechStart);
      expect(ev[0].$2.bargeIn, isFalse);
      expect(ev[1].$2.event, VadEvent.speechEnd);
      // 开口发生在进入话音段之后，收尾发生在静音之后
      expect(ev[0].$1, greaterThanOrEqualTo(10 * 64));
      expect(ev[1].$1, greaterThan(ev[0].$1));
    });

    test('AI 播报时，短暂杂音不算插话（要撑过 bargeInMs）', () {
      final g = VadGate()..aiSpeaking = true;
      // 只响了 3 块（~190ms）就没了 → 不该判定插话
      final ev = drive(g, [
        ...List.filled(3, 0.3),
        ...List.filled(20, 0.001),
      ]);
      expect(ev, isEmpty);
    });

    test('AI 播报时，持续开口 → 判定为插话且带 bargeIn 标记', () {
      final g = VadGate()..aiSpeaking = true;
      final ev = drive(g, List.filled(20, 0.3));
      expect(ev.length, 1);
      expect(ev[0].$2.event, VadEvent.speechStart);
      expect(ev[0].$2.bargeIn, isTrue);
      expect(ev[0].$1, greaterThanOrEqualTo(800));
    });

    test('持续说话超过 maxSpeechMs 会被强制收尾', () {
      final g = VadGate(tuning: const VadTuning(maxSpeechMs: 1000));
      final ev = drive(g, List.filled(60, 0.3));
      // 一直大声：会按 maxSpeechMs 反复「收尾→重新开口」，不会卡在说话中出不来
      expect(ev.length, greaterThanOrEqualTo(2));
      expect(ev[0].$2.event, VadEvent.speechStart);
      expect(ev[1].$2.event, VadEvent.speechEnd);
      expect(ev[1].$1 - ev[0].$1, greaterThanOrEqualTo(1000));
      expect(ev[1].$1 - ev[0].$1, lessThan(1200));
    });

    test('一直不上不下（高于退出阈值、低于进入阈值）时靠看门狗收尾', () {
      final g = VadGate();
      // 先正常开口（10 块安静 + 6 块大声，最后一块大声在 t=15*64=960）
      final ev = drive(g, [
        ...List.filled(10, 0.001),
        ...List.filled(6, 0.2),
      ]);
      expect(ev.single.$2.event, VadEvent.speechStart);
      const lastHotMs = 15 * 64;

      // 然后给一个「比退出阈值高、但够不到进入阈值」的持续电平：
      // 双阈值不会判静音，只能靠 watchdog 从最后一块「热」算起收尾。
      var endAtMs = -1;
      for (var i = 16; i < 80; i++) {
        final s = g.push(0.02, i * 64);
        if (s.event == VadEvent.speechEnd) {
          endAtMs = i * 64;
          break;
        }
      }
      expect(endAtMs, greaterThan(0));
      expect(endAtMs - lastHotMs, greaterThanOrEqualTo(1600));
    });

    test('噪声底不会被持续的人声顶飞（否则插话永远触发不了）', () {
      final g = VadGate()..aiSpeaking = true;
      // 连续大声 3 秒，噪声底应保持很低
      drive(g, List.filled(47, 0.4));
      expect(g.noiseFloor, lessThan(0.05));
    });
  });

  // ═══════════════════════ 识别结果清洗 ═══════════════════════

  group('sanitizeAsrText', () {
    test('正常文本原样返回', () {
      expect(sanitizeAsrText('  今天天气不错  '), '今天天气不错');
      expect(sanitizeAsrText('hello world'), 'hello world');
    });

    test('纯标点/空白丢弃', () {
      expect(sanitizeAsrText('，。！'), '');
      expect(sanitizeAsrText('   '), '');
    });

    test('Whisper 经典幻觉句丢弃（否则用户一停顿就冒出「谢谢观看」）', () {
      expect(sanitizeAsrText('谢谢观看'), '');
      expect(sanitizeAsrText('请不吝点赞订阅转发打赏'), '');
      expect(sanitizeAsrText('字幕由 Amara.org 社区提供'), '');
    });

    test('只是顺带提到这些词的长句要保留', () {
      const s = '我今天在视频网站上看到有人说谢谢观看这四个字其实挺敷衍的你知道吗';
      expect(sanitizeAsrText(s), s);
    });
  });

  // ═══════════════════════ 流式 SSE ═══════════════════════

  group('chatCompleteStream', () {
    late HttpServer server;
    late int port;

    Future<void> serve(Future<void> Function(HttpRequest req) handler) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((req) async {
        await req.drain<void>();
        await handler(req);
      });
    }

    ModelConfig cfg() => ModelConfig(
          id: 'test',
          name: 'test',
          providerId: 'custom',
          modelId: 'mock',
          apiKey: 'k',
          baseUrl: 'http://127.0.0.1:$port/v1',
        );

    tearDown(() async {
      await server.close(force: true);
    });

    void sse(HttpRequest req, String content) {
      req.response
        ..statusCode = 200
        ..headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
    }

    test('按 SSE 逐块解析，并把增量回调出去', () async {
      await serve((req) async {
        sse(req, '');
        void emit(String? content, {String? finish}) {
          final delta = <String, dynamic>{};
          if (content != null) delta['content'] = content;
          req.response.write('data: ${jsonEncode({
                'choices': [
                  {'index': 0, 'delta': delta, 'finish_reason': finish}
                ]
              })}\n\n');
        }

        emit(null);
        emit('你好');
        emit('，今天');
        emit('天气不错。');
        emit(null, finish: 'stop');
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
      });

      final deltas = <String>[];
      final res = await chatCompleteStream(
        cfg: cfg(),
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
        onDelta: deltas.add,
      );

      expect(res.ok, isTrue);
      expect(res.content, '你好，今天天气不错。');
      expect(res.finishReason, 'stop');
      // 增量是分三次来的，不是一次性给整段
      expect(deltas, ['你好', '，今天', '天气不错。']);
    });

    test('供应商忽略 stream、回了整段 JSON 时能兜底解析', () async {
      await serve((req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': '我是整段返回的'},
              'finish_reason': 'stop'
            }
          ]
        }));
        await req.response.close();
      });

      final res = await chatCompleteStream(
        cfg: cfg(),
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
      );
      expect(res.ok, isTrue);
      expect(res.content, '我是整段返回的');
    });

    test('HTTP 401 返回可读错误', () async {
      await serve((req) async {
        req.response.statusCode = 401;
        req.response.write('{"error":"bad key"}');
        await req.response.close();
      });

      final res = await chatCompleteStream(
        cfg: cfg(),
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
      );
      expect(res.ok, isFalse);
      expect(res.status, 401);
      expect(res.error, isNotNull);
    });

    test('isCancelled 为真时提前收尾，已收到的部分照常返回', () async {
      var cancelled = false;
      await serve((req) async {
        sse(req, '');
        for (final piece in ['第一句。', '第二句。', '第三句。']) {
          req.response.write('data: ${jsonEncode({
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': piece},
                    'finish_reason': null
                  }
                ]
              })}\n\n');
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        await req.response.close();
      });

      final deltas = <String>[];
      final res = await chatCompleteStream(
        cfg: cfg(),
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
        onDelta: (d) {
          deltas.add(d);
          if (deltas.length >= 1) cancelled = true;
        },
        isCancelled: () => cancelled,
      );

      expect(res.ok, isTrue);
      // 至少收到第一句；后面的因为已取消不再读取
      expect(res.content, contains('第一句。'));
      expect(res.content, isNot(contains('第三句。')));
    });
  });
}
