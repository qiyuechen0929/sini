import 'package:flutter_test/flutter_test.dart';
import 'package:sini/models.dart';
import 'package:sini/utils/proactive_engine.dart';

/// 主动搭话引擎的纯逻辑回归测试。
/// 这些是最容易悄悄写错、又最难在 UI 上看出来的地方：
/// 静默时段边界、决策 JSON 容错、主动性→间隔的单调性。
void main() {
  group('静默时段', () {
    test('深夜到清晨静默', () {
      expect(isQuietHour(DateTime(2026, 9, 10, 2)), isTrue); // 凌晨2点
      expect(isQuietHour(DateTime(2026, 9, 10, 23)), isTrue); // 23点
      expect(isQuietHour(DateTime(2026, 9, 10, 0)), isTrue);
      expect(isQuietHour(DateTime(2026, 9, 10, 7, 59)), isTrue);
    });
    test('白天不静默（含上午8点整这个边界）', () {
      expect(isQuietHour(DateTime(2026, 9, 10, 8)), isFalse);
      expect(isQuietHour(DateTime(2026, 9, 10, 10)), isFalse);
      expect(isQuietHour(DateTime(2026, 9, 10, 22, 59)), isFalse);
    });
  });

  group('间隔人话化', () {
    test('各量级都有合理文案', () {
      expect(humanizeGap(const Duration(seconds: 30)), '刚刚');
      expect(humanizeGap(const Duration(minutes: 30)), '30 分钟前');
      expect(humanizeGap(const Duration(hours: 5)), '5 小时前');
      expect(humanizeGap(const Duration(days: 1)), '昨天');
      expect(humanizeGap(const Duration(days: 2)), '2 天前');
      expect(humanizeGap(const Duration(days: 40)), '1 个月前');
      expect(humanizeGap(const Duration(days: 400)), '1 年前');
    });
  });

  group('决策解析容错', () {
    test('明确不说', () {
      final d = parseProactiveDecision('{"speak": false, "reason": "刚聊完"}');
      expect(d.speak, isFalse);
    });
    test('说要 + 两条消息 + 代码块包裹', () {
      final d = parseProactiveDecision(
          '```json\n{"speak": true, "messages": ["想起你昨天说的面试", "紧张吗"], "reason": "关心"}\n```');
      expect(d.speak, isTrue);
      expect(d.messages, ['想起你昨天说的面试', '紧张吗']);
    });
    test('前后有杂讯也能解析出来', () {
      final d = parseProactiveDecision(
          '哈哈 {"speak": true, "messages": ["在干嘛"]} 就这样');
      expect(d.speak, isTrue);
      expect(d.messages, ['在干嘛']);
    });
    test('完全不是 JSON → 静默（绝不误发）', () {
      expect(parseProactiveDecision('模型抽风了').speak, isFalse);
      expect(parseProactiveDecision('').speak, isFalse);
    });
    test('speak=true 但消息为空 → 视为不说', () {
      expect(parseProactiveDecision('{"speak": true, "messages": []}').speak, isFalse);
      expect(
          parseProactiveDecision('{"speak": true, "messages": ["  ", ""]}').speak,
          isFalse);
    });
    test('最多两条（防刷屏）', () {
      final d = parseProactiveDecision(
          '{"speak": true, "messages": ["a","b","c","d"]}');
      expect(d.messages.length, 2);
    });
  });

  group('主动性 → 最小区间', () {
    test('主动性越高，间隔越短（严格单调）', () {
      var prev = 1e9;
      for (final v in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final p = Persona(
          id: 'x',
          name: 'n',
          subtitle: '',
          gradientSeed: const [1, 2, 3, 4, 5, 6],
          initiative: v,
        );
        final m = minGapFor(p).inMinutes.toDouble();
        expect(m, lessThan(prev), reason: '主动性 $v 的间隔应小于上一档');
        prev = m;
      }
    });
    test('极端值落在合理范围（不是 0 也不是天级）', () {
      final low = minGapFor(Persona(
          id: 'a', name: 'a', subtitle: '', gradientSeed: const [1, 2, 3, 4, 5, 6],
          initiative: 0));
      final high = minGapFor(Persona(
          id: 'b', name: 'b', subtitle: '', gradientSeed: const [1, 2, 3, 4, 5, 6],
          initiative: 1));
      expect(high.inMinutes, greaterThanOrEqualTo(30));
      expect(low.inMinutes, lessThanOrEqualTo(41 * 60));
    });
  });

  group('时间感知文案', () {
    test('各时段', () {
      expect(timeOfDayHint(DateTime(2026, 9, 10, 3)), '凌晨');
      expect(timeOfDayHint(DateTime(2026, 9, 10, 8)), '早上');
      expect(timeOfDayHint(DateTime(2026, 9, 10, 11)), '上午');
      expect(timeOfDayHint(DateTime(2026, 9, 10, 13)), '中午');
      expect(timeOfDayHint(DateTime(2026, 9, 10, 16)), '下午');
      expect(timeOfDayHint(DateTime(2026, 9, 10, 20)), '晚上');
      expect(timeOfDayHint(DateTime(2026, 9, 10, 23)), '深夜');
    });
  });
}
