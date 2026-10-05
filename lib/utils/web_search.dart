import 'package:dio/dio.dart';

import 'connectors.dart' show ConnectorApi;
import 'safe_text.dart' show safeHead, safeClip;

/// 联网搜索：博查（国内结果好，默认）+ Tavily（免费额度大，备选）。
/// AI 判断需要实时信息 → 前端拦截 → 搜真实结果 → 塞回上下文让 TA 总结。

const List<String> kSearchProviders = ['bocha', 'tavily'];

String searchProviderLabel(String p) =>
    p == 'tavily' ? 'Tavily（海外/免费额度）' : '博查 Bocha（国内结果）';

class SearchHit {
  final String title;
  final String url;
  final String snippet;
  const SearchHit({required this.title, required this.url, required this.snippet});
}

class SearchResult {
  final bool ok;
  final List<SearchHit> hits;
  final String? error;
  const SearchResult(this.ok, {this.hits = const [], this.error});
}

/// 清洗并抽出真正的搜索关键词。
///
/// 坑：用户常问「你好，你知道今天AI圈有什么新闻吗」——
/// 直接丢给百度会搜到「你好」的词源。这里剥掉寒暄/疑问壳，只留主题。
String cleanSearchQuery(String raw) {
  var q = raw.trim();
  if (q.isEmpty) return q;

  // 1) 先全局剥掉寒暄/指令/疑问壳（不限于句首）
  const noise = [
    '你好', '您好', '嗨', '哈喽', 'hi', 'hello', 'hey',
    '在吗', '在不在',
    '你知道吗', '你了解吗', '你知道', '你了解',
    '跟我说说', '跟我说', '告诉我', '给我讲讲', '讲一下',
    '能说说吗', '能讲讲吗', '有什么', '有哪些', '有没有',
    '帮我搜', '帮我查', '帮我搜索', '帮我查询',
    '麻烦搜', '麻烦查', '上网查', '联网搜',
    '今天', '今日', '最近', '这几天', '这两天', '目前', '现在',
    'search for', 'please search', 'search',
  ];
  var lower = q.toLowerCase();
  for (final n in noise) {
    final nl = n.toLowerCase();
    lower = lower.replaceAll(nl, ' ');
  }
  // 用剥完后的空格结构重建（保留原大小写：用 split 再按 lower 的空位滤）
  // 简化：对原文也 replaceAll
  for (final n in noise) {
    q = q.replaceAll(n, ' ');
  }
  q = q.replaceAll(RegExp(r'[?？。！!，,、；;：:]+'), ' ');
  q = q.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (q.length > 40) q = safeClip(q, 40);
  if (q.isEmpty) return raw.trim();
  return q;
}

/// 判断是否需要联网。
bool needsWebSearch(String text) {
  final t = text.toLowerCase();
  const explicit = [
    '搜一下', '搜索', '帮我搜', '搜个', '搜下', '联网', '上网查', '查一下', '查查',
    'google', 'search',
  ];
  for (final k in explicit) {
    if (t.contains(k)) return true;
  }
  final implicitRe = RegExp(
    r'天气|新闻|头条|热点|热搜|榜|比分|赛果|汇率|股价|基金净值|油价|金价|'
    r'最新(消息|版本|进展|发布)|今天(几号|日期|星期)|现在(几点|多少)|'
    r'最近(有什么|有什么新|上新)|发布了|上线了|'
    r'什么梗|梗是|吃瓜|瓜|出圈|爆火|emo|yyds|绝绝子|栓Q|泰裤辣|尊嘟|假嘟',
  );
  return implicitRe.hasMatch(text);
}

Future<SearchResult> webSearch({
  required String query,
  required String provider,
  required String apiKey,
  int count = 6,
}) async {
  final q = cleanSearchQuery(query);
  // 先保证服务端地址已恢复（不依赖用户是否打开过连接器页）
  try {
    await ConnectorApi.loadFromPrefs();
  } catch (_) {}
  // 无论有没有 Key，都先走本地代理（百度/Bing/SearX 并行，最快）
  final proxied = await proxyWebSearch(q, count: count);
  if (proxied.ok) return proxied;
  if (apiKey.trim().isEmpty) {
    return freeWebSearch(q, count: count);
  }
  try {
    final isTavily = provider == 'tavily';
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 18),
    ));
    final res = await dio.post<dynamic>(
      isTavily ? 'https://api.tavily.com/search' : 'https://api.bochaai.com/v1/web-search',
      options: Options(headers: {
        if (!isTavily) 'Authorization': 'Bearer ${apiKey.trim()}',
      }),
      data: isTavily
          ? {
              'api_key': apiKey.trim(),
              'query': q,
              'max_results': count,
              'search_depth': 'basic',
            }
          : {
              'query': q,
              'summary': true,
              'count': count,
              'freshness': 'noLimit',
            },
    );
    final j = res.data;
    if (j is! Map<String, dynamic>) {
      return const SearchResult(false, error: '搜索返回格式异常');
    }
    final hits = <SearchHit>[];
    if (isTavily) {
      for (final r in (j['results'] as List? ?? [])) {
        if (r is Map<String, dynamic>) {
          hits.add(SearchHit(
            title: (r['title'] ?? '').toString(),
            url: (r['url'] ?? '').toString(),
            snippet: ((r['content'] ?? r['snippet']) ?? '').toString(),
          ));
        }
      }
    } else {
      final pages =
          (((j['data'] ?? const {}) as Map<String, dynamic>)['webPages']
                  as Map<String, dynamic>?)?['value'] as List? ??
              const [];
      for (final r in pages) {
        if (r is Map<String, dynamic>) {
          hits.add(SearchHit(
            title: (r['name'] ?? '').toString(),
            url: (r['url'] ?? '').toString(),
            snippet: ((r['summary'] ?? r['snippet']) ?? '').toString(),
          ));
        }
      }
    }
    if (hits.isEmpty) {
      return const SearchResult(false, error: '搜索没有返回结果');
    }
    return SearchResult(true, hits: hits);
  } on DioException catch (e) {
    final body = e.response?.data?.toString();
    return SearchResult(false,
        error: 'HTTP ${e.response?.statusCode ?? '?'}: ${safeHead(body ?? (e.message ?? '网络错误'), 160)}');
  } catch (e) {
    return SearchResult(false, error: '$e');
  }
}

String formatSearchContext(String query, List<SearchHit> hits) {
  final sb = StringBuffer()
    ..writeln('[联网搜索结果 · 关键词：$query · 刚刚从真实网络搜到，可信度高]')
    ..writeln('重要：你现在**可以联网**，下面就是搜到的结果。'
        '必须基于这些结果回答；绝对不要说「我无法联网」「我没有实时新闻」这类话。'
        '信息不够就基于结果给最相关的，并说明这是搜到的内容。'
        '如果是「什么梗 / 网络用语」类问题，先用一句人话说清含义和出处，再补一句使用场景。');
  for (int i = 0; i < hits.length; i++) {
    sb.writeln('${i + 1}. ${hits[i].title}');
    if (hits[i].snippet.isNotEmpty) {
      sb.writeln('   ${safeClip(hits[i].snippet.replaceAll(RegExp(r'\s+'), ' '), 320)}');
    }
    sb.writeln('   来源: ${hits[i].url}');
  }
  sb.writeln('回答完可以在末尾用 markdown 链接列出主要来源（最多 3 条），自然一点。');
  return sb.toString();
}

Future<SearchResult> proxyWebSearch(String query, {int count = 6}) async {
  final bases = <String>[];
  try {
    final origin = Uri.base.origin;
    if (origin.startsWith('http')) bases.add(origin);
  } catch (_) {}
  final configured = ConnectorApi.serverBase;
  if (configured != null && configured.isNotEmpty) bases.add(configured);

  Object? lastErr;
  for (final base in bases) {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 16),
      ));
      final res = await dio.get<dynamic>('$base/api/search',
          queryParameters: {'q': query, 'count': count});
      final j = res.data;
      if (j is Map<String, dynamic> && j['hits'] is List) {
        final hits = <SearchHit>[];
        for (final r in (j['hits'] as List)) {
          if (r is Map<String, dynamic>) {
            hits.add(SearchHit(
              title: (r['title'] ?? '').toString(),
              url: (r['url'] ?? '').toString(),
              snippet: (r['snippet'] ?? '').toString(),
            ));
          }
        }
        if (hits.isNotEmpty) return SearchResult(true, hits: hits);
        lastErr = j['error'] ?? '代理搜索没有返回结果';
      } else {
        lastErr = j is Map ? (j['error'] ?? '代理返回异常') : '代理返回异常';
      }
    } catch (e) {
      lastErr = e;
    }
  }
  return SearchResult(false,
      error: lastErr == null
          ? '没有可用的搜索代理（手机请在连接器里填电脑地址）'
          : '搜索代理失败: $lastErr');
}

const List<String> _searxInstances = [
  'https://searx.be',
  'https://searxng.site',
  'https://search.inetol.net',
  'https://priv.au',
  'https://search.bus-hit.me',
];

/// 免费搜索：并行竞速 SearXNG，失败再抓百度。
Future<SearchResult> freeWebSearch(String query, {int count = 6}) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 8),
  ));

  Future<SearchResult> trySearx(String inst) async {
    try {
      final res = await dio.get<dynamic>('$inst/search',
          queryParameters: {'q': query, 'format': 'json'});
      final j = res.data;
      if (j is Map<String, dynamic>) {
        final hits = <SearchHit>[];
        for (final r in (j['results'] as List? ?? [])) {
          if (r is Map<String, dynamic>) {
            hits.add(SearchHit(
              title: (r['title'] ?? '').toString(),
              url: (r['url'] ?? '').toString(),
              snippet: (r['content'] ?? '').toString(),
            ));
            if (hits.length >= count) break;
          }
        }
        if (hits.isNotEmpty) return SearchResult(true, hits: hits);
      }
    } catch (_) {}
    return const SearchResult(false, error: 'skip');
  }

  Future<SearchResult> tryBaidu() async {
    try {
      final res = await dio.get<String>('https://www.baidu.com/s',
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
            },
          ),
          queryParameters: {'wd': query, 'rn': count});
      final html = res.data ?? '';
      final hits = <SearchHit>[];
      final re = RegExp(
        r'<h3[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>',
        caseSensitive: false,
      );
      for (final m in re.allMatches(html)) {
        final title = _stripTags(m.group(2) ?? '');
        if (title.isEmpty) continue;
        hits.add(SearchHit(
            title: title,
            url: _unescapeHtml(m.group(1) ?? ''),
            snippet: '（来自百度）'));
        if (hits.length >= count) break;
      }
      if (hits.isNotEmpty) return SearchResult(true, hits: hits);
    } catch (_) {}
    return const SearchResult(false, error: 'baidu fail');
  }

  // 并行竞速，谁先出结果用谁
  final futures = [for (final i in _searxInstances) trySearx(i), tryBaidu()];
  final results = await Future.wait(futures);
  for (final r in results) {
    if (r.ok && r.hits.isNotEmpty) return r;
  }
  return const SearchResult(false, error: '免费搜索源暂时都不可用，可在设置里配置搜索 API Key');
}

String _stripTags(String html) => html.replaceAll(RegExp(r'<[^>]*>'), '').trim();

String _unescapeHtml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');
