import 'package:flutter_test/flutter_test.dart';

import 'package:sini/utils/chart_spec.dart';

void main() {
  test('合法 chart JSON 解析成 ChartSpec', () {
    final spec = ChartSpec.tryParse('''
{"type":"bar","title":"开支","labels":["吃","玩","租"],
 "series":[{"name":"元","data":[100,200,3000]}]}''');
    expect(spec, isNotNull);
    expect(spec!.type, 'bar');
    expect(spec.labels.length, 3);
    expect(spec.series.first.values, [100, 200, 3000]);
  });

  test('非法 JSON / 长度不匹配 / 未知类型返回 null（兜底显示代码块）', () {
    expect(ChartSpec.tryParse('不是json'), isNull);
    expect(
        ChartSpec.tryParse(
            '{"type":"bar","labels":["a","b"],"series":[{"name":"x","data":[1]}]}'),
        isNull);
    expect(
        ChartSpec.tryParse(
            '{"type":"radar","labels":["a"],"series":[{"name":"x","data":[1]}]}'),
        isNull);
  });

  test('stripChartBlocks 剥掉完整块与流式残块', () {
    expect(stripChartBlocks('看这个：\n\`\`\`chart\n{"a":1}\n\`\`\`\n怎么样'),
        matches(RegExp(r'^看这个：\s*怎么样$')));
    expect(stripChartBlocks('先说话\`\`\`chart\n{" partial'), '先说话');
    expect(stripChartBlocks('普通回复'), '普通回复');
  });

  test('tryParseChartBlock 只认 chart 语言标记', () {
    expect(tryParseChartBlock('dart', 'void main() {}'), isNull);
    expect(tryParseChartBlock('chart', '{"type":"pie","labels":["a"],"series":[{"name":"x","data":[1]}]}'),
        isNotNull);
  });
}
