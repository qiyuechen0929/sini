import 'package:flutter_test/flutter_test.dart';

import 'package:sini/utils/usage_store.dart';

void main() {
  final now = DateTime.now();
  final events = [
    UsageEvent(
        providerId: 'deepseek',
        modelId: 'deepseek-chat',
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
        ts: now),
    UsageEvent(
        providerId: 'deepseek',
        modelId: 'deepseek-chat',
        promptTokens: 200,
        completionTokens: 100,
        totalTokens: 300,
        ts: now),
    UsageEvent(
        providerId: 'zhipu',
        modelId: 'glm-4-flash',
        promptTokens: 10,
        completionTokens: 5,
        totalTokens: 15,
        ts: now.subtract(const Duration(days: 2)),
    ),
  ];

  test('按模型汇总：用量降序 + 次数正确', () {
    final m = UsageStore.instance.byModel(events);
    expect(m.length, 2);
    expect(m.first.modelId, 'deepseek-chat');
    expect(m.first.tokens, 450);
    expect(m.first.calls, 2);
    expect(m.last.tokens, 15);
  });

  test('按天汇总与范围过滤', () {
    final days = UsageStore.instance.byDay(events);
    expect(days.length, 2);
    expect(days.last.tokens, 450);
    // 只看最近 1 天（本地过滤，语义与 UsageStore.inRange 一致）
    final start = now.subtract(const Duration(hours: 1));
    final recent = events.where((e) => e.ts.isAfter(start)).toList();
    expect(UsageStore.instance.totalTokens(recent), 450);
    expect(UsageStore.instance.promptTokens(recent), 300);
    expect(UsageStore.instance.completionTokens(recent), 150);
  });

  test('formatTokens：千分位 / k / M', () {
    expect(formatTokens(950), '950');
    expect(formatTokens(1234), '1,234');
    expect(formatTokens(45200), '45.2k');
    expect(formatTokens(3450000), '3.45M');
  });
}
