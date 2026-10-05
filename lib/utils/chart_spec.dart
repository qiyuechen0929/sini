import 'dart:convert';

/// AI 回复里内嵌图表的协议与解析。
///
/// 约定：AI 在回复正文里输出 ```chart 围栏块，内容为严格 JSON：
/// ```chart
/// {"type":"bar","title":"月度开支","labels":["吃","玩"],"series":[{"name":"元","data":[100,200]}]}
/// ```
/// 前端把围栏块渲染成原生图表卡片；解析失败原样显示代码块，不影响阅读。

const String kChartSystemHint = '''
【图表能力】
当且仅当图表能让 TA 更明白时，你可以在回复里嵌入一张数据图表：
- TA 明确要求（画个图 / 图表 / 柱状图 / 饼图 / 趋势图）时，必须带上；
- 内容涉及数字对比、占比、走势，且用图确实更直观时，可以带一张；
- 除此之外不要画蛇添足：纯聊天、观点讨论、情感交流永远不要带图；一条回复最多一张。
- 决定用图表时就不要再画一个 markdown 表格重复同样的数据——图归图，文字总结归文字。
嵌入格式：在正文中输出 ```chart 围栏块，内容为严格 JSON（不要有注释、不要有多余逗号）：
{"type":"bar|line|pie","title":"图表标题","labels":["类目一","类目二"],"series":[{"name":"系列名","data":[10,20]}]}
规则：data 全为数字且长度与 labels 一致；bar 适合对比、line 适合趋势、pie 适合占比（pie 只取第一个系列）；
说明文字写在围栏块外的正文里，不要塞进 JSON；图表下方自然接一句口头总结更像聊天。''';

/// 一张图：bar / line / pie + 标题 + 类目标签 + 一到多个数据系列
class ChartSpec {
  final String type; // bar | line | pie
  final String title;
  final List<String> labels;
  final List<ChartSeries> series;

  const ChartSpec({
    required this.type,
    required this.title,
    required this.labels,
    required this.series,
  });

  bool get isValid =>
      (type == 'bar' || type == 'line' || type == 'pie') &&
      labels.isNotEmpty &&
      series.isNotEmpty &&
      series.every((s) =>
          s.values.isNotEmpty &&
          s.values.length == labels.length &&
          s.values.every((v) => !v.isNaN));

  static ChartSpec? tryParse(String code) {
    try {
      final j = jsonDecode(code.trim());
      if (j is! Map<String, dynamic>) return null;
      final labels = (j['labels'] as List?)?.map((e) => e.toString()).toList();
      final rawSeries = j['series'] as List?;
      if (labels == null || labels.isEmpty || rawSeries == null) return null;
      final series = <ChartSeries>[];
      for (final s in rawSeries) {
        if (s is! Map<String, dynamic>) continue;
        final vals = (s['data'] as List?)
            ?.map((e) => (e is num) ? e.toDouble() : double.tryParse('$e'))
            .whereType<double>()
            .toList();
        if (vals == null || vals.isEmpty) continue;
        series.add(ChartSeries(
          name: (s['name'] ?? '').toString(),
          values: vals,
        ));
      }
      final spec = ChartSpec(
        type: (j['type'] ?? 'bar').toString().trim(),
        title: (j['title'] ?? '').toString(),
        labels: labels,
        series: series,
      );
      return spec.isValid ? spec : null;
    } catch (_) {
      return null;
    }
  }
}

class ChartSeries {
  final String name;
  final List<double> values;
  const ChartSeries({required this.name, required this.values});
}

/// 图表类围栏块的解析结果：lang == 'chart' 时用
ChartSpec? tryParseChartBlock(String lang, String code) =>
    lang == 'chart' ? ChartSpec.tryParse(code) : null;

/// 从消息正文里剥掉整个 chart 围栏块（朗读 / 语音通话用，别把 JSON 读出来）
String stripChartBlocks(String text) {
  final re = RegExp(r'```chart[\s\S]*?```', caseSensitive: false);
  final stripped = text.replaceAll(re, '').trim();
  // 流式输出中围栏块可能还没闭合：把开头残缺的部分也去掉
  if (stripped.contains('```chart')) {
    return stripped
        .substring(0, stripped.indexOf('```chart'))
        .trim();
  }
  return stripped;
}
