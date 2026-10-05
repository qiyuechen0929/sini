import 'package:flutter_test/flutter_test.dart';

import 'package:sini/utils/web_search.dart';

void main() {
  test('明确要求搜索 → 必触发', () {
    expect(needsWebSearch('帮我搜一下最近的手机推荐'), isTrue);
    expect(needsWebSearch('搜索 高铁时刻表'), isTrue);
    expect(needsWebSearch('上网查一下这个公司'), isTrue);
  });

  test('实时性话题 → 自动触发', () {
    expect(needsWebSearch('今天武汉天气怎么样'), isTrue);
    expect(needsWebSearch('最近有什么好看的新闻'), isTrue);
    expect(needsWebSearch('现在美元汇率多少'), isTrue);
    expect(needsWebSearch('今天几号了'), isTrue);
  });

  test('日常聊天 / 角色扮演 → 不触发（避免误搜）', () {
    expect(needsWebSearch('我们今天去游乐园玩好不好'), isFalse);
    expect(needsWebSearch('你觉得我最近状态怎么样'), isFalse);
    expect(needsWebSearch('（角色扮演）今天的故事从一个雨天开始'), isFalse);
    expect(needsWebSearch('我今天很累'), isFalse);
  });

  test('formatSearchContext 带标题、摘要和来源', () {
    final ctx = formatSearchContext('武汉天气', [
      const SearchHit(title: '武汉天气', url: 'https://x.com/1', snippet: '晴 25 度'),
    ]);
    expect(ctx, contains('[联网搜索结果'));
    expect(ctx, contains('武汉天气'));
    expect(ctx, contains('https://x.com/1'));
    expect(ctx, contains('不要编造'));
  });
}
