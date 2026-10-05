import 'package:flutter_test/flutter_test.dart';

import 'package:sini/utils/romance_engine.dart';

void main() {
  test('恋爱语言推高信号，随时间衰减', () {
    final st = AffinityState();
    final now = DateTime.now();
    final s1 = updateRomanceScore(st, '想你了，宝贝', now);
    expect(s1, greaterThanOrEqualTo(24)); // 命中 2 词 ×12
    // 一天后衰减一半
    final s2 = updateRomanceScore(st, '帮我个忙', now.add(const Duration(hours: 24)));
    expect(s2, lessThan(s1));
  });

  test('门控：恋人关系低门槛解锁；其他关系永不解锁', () {
    expect(
        romanceUnlocked(relationship: '恋人', score: 45), isTrue);
    expect(
        romanceUnlocked(relationship: '恋人', score: 20), isFalse);
    expect(
        romanceUnlocked(relationship: '朋友', score: 100), isFalse);
    expect(romanceUnlocked(relationship: null, score: 100), isFalse);
  });

  test('心情推导：心疼 > 甜蜜/想你 > 小情绪 > 平静', () {
    final st = AffinityState();
    final now = DateTime.now();
    expect(
        nextMood(
            st: st, userText: '我今天好累好烦', isLover: true, now: now),
        '心疼你');
    expect(
        nextMood(
            st: st, userText: '想你了', isLover: true, now: now),
        '甜蜜');
    // 恋人三天没来 → 小情绪
    final st2 = AffinityState()
      ..updatedAt = now.subtract(const Duration(days: 3));
    expect(
        nextMood(
            st: st2,
            userText: '在吗',
            isLover: true,
            now: now),
        '有点小情绪');
    expect(
        nextMood(
            st: AffinityState(),
            userText: '帮我看看这段代码',
            isLover: false,
            now: now),
        '平静');
  });

  test('指令注入：未解锁时非恋人关系有边界规则，永不给恋人腔', () {
    final boundary = buildRomanceDirective(
        relationship: '朋友', personaName: '小澄', unlocked: false, isLoverRelation: false);
    expect(boundary, contains('关系边界'));
    expect(boundary, contains('不要升级'));

    final lover = buildRomanceDirective(
        relationship: '恋人', personaName: '小澄', unlocked: true, isLoverRelation: true);
    expect(lover, contains('亲密模式'));
    expect(lover, contains('不堆')); // 反 AI 腔纪律在指令里

    final restrained = buildRomanceDirective(
        relationship: '恋人', personaName: '小澄', unlocked: false, isLoverRelation: true);
    expect(restrained, contains('不会突然发嗲'));
  });
}
