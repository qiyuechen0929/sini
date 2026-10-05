import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/design/tokens.dart';
import '../theme.dart';
import '../utils/chart_spec.dart';

/// AI 回复里的数据图表卡片：把 ```chart JSON 画成原生柱状 / 折线 / 饼图。
class ChartCard extends StatelessWidget {
  final ChartSpec spec;
  const ChartCard({super.key, required this.spec});

  static const _palette = [
    Color(0xFF10A37F),
    Color(0xFF6C5CE7),
    Color(0xFFE84393),
    Color(0xFF0984E3),
    Color(0xFFFDCB6E),
  ];

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: p.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.title.isNotEmpty)
            Text(spec.title,
                style: TextStyle(
                    fontSize: SiniText.bodySm + 0.5,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary)),
          if (spec.title.isNotEmpty) const SizedBox(height: Spacing.sm),
          SizedBox(
            height: 200,
            child: switch (spec.type) {
              'line' => _buildLine(p),
              'pie' => _buildPie(p),
              _ => _buildBar(p),
            },
          ),
          // 图例
          const SizedBox(height: Spacing.xs),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (int i = 0; i < spec.series.length; i++)
                if (spec.type != 'pie' ||
                    spec.series.first.values
                        .every((v) => v >= 0)) // 饼图图例在扇区旁，多系列才画这里
                  _legend(_palette[i % _palette.length],
                      spec.series[i].name.isEmpty ? '系列${i + 1}' : spec.series[i].name, p),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String name, AppPalette p) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(name,
              style: TextStyle(
                  fontSize: 10.5, color: p.textSecondary)),
        ],
      );

  Widget _buildBar(AppPalette p) {
    final groupCount = spec.labels.length;
    final seriesCount = spec.series.length;
    double maxV = 0;
    for (final s in spec.series) {
      maxV = maxV < s.values.reduce((a, b) => a > b ? a : b)
          ? s.values.reduce((a, b) => a > b ? a : b)
          : maxV;
    }
    return BarChart(BarChartData(
      maxY: maxV <= 0 ? 1 : maxV * 1.2,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (v) => FlLine(
            color: p.border.withValues(alpha: .6), strokeWidth: 0.5),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            getTitlesWidget: (v, meta) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                (v.toInt() >= 0 && v.toInt() < groupCount)
                    ? _short(spec.labels[v.toInt()])
                    : '',
                style: TextStyle(fontSize: 9.5, color: p.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
      barGroups: [
        for (int g = 0; g < groupCount; g++)
          BarChartGroupData(
            x: g,
            barRods: [
              for (int s = 0; s < seriesCount; s++)
                BarChartRodData(
                  toY: spec.series[s].values[g],
                  width: seriesCount > 1 ? 8 : 16,
                  borderRadius: BorderRadius.circular(3),
                  color: _palette[s % _palette.length],
                ),
            ],
            barsSpace: 3,
          ),
      ],
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
            '${_short(spec.labels[group.x])} ${rod.toY.toStringAsFixed(1)}',
            TextStyle(fontSize: 10, color: p.textPrimary),
          ),
        ),
      ),
    ));
  }

  Widget _buildLine(AppPalette p) {
    double maxV = 0;
    for (final s in spec.series) {
      maxV = maxV < s.values.reduce((a, b) => a > b ? a : b)
          ? s.values.reduce((a, b) => a > b ? a : b)
          : maxV;
    }
    return LineChart(LineChartData(
      minY: 0,
      maxY: maxV <= 0 ? 1 : maxV * 1.2,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (v) => FlLine(
            color: p.border.withValues(alpha: .6), strokeWidth: 0.5),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            interval: (spec.labels.length / 6).ceilToDouble().clamp(1, 99),
            getTitlesWidget: (v, meta) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                (v.toInt() >= 0 && v.toInt() < spec.labels.length)
                    ? _short(spec.labels[v.toInt()])
                    : '',
                style: TextStyle(fontSize: 9.5, color: p.textSecondary),
              ),
            ),
          ),
        ),
      ),
      lineBarsData: [
        for (int s = 0; s < spec.series.length; s++)
          LineChartBarData(
            spots: [
              for (int i = 0; i < spec.series[s].values.length; i++)
                FlSpot(i.toDouble(), spec.series[s].values[i]),
            ],
            isCurved: true,
            curveSmoothness: 0.3,
            barWidth: 2.2,
            dotData: const FlDotData(show: true),
            color: _palette[s % _palette.length],
          ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => [
            for (final sp in spots)
              LineTooltipItem(
                '${_short(spec.labels[sp.x.toInt()])} ${sp.y.toStringAsFixed(1)}',
                TextStyle(fontSize: 10, color: p.textPrimary),
              ),
          ],
        ),
      ),
    ));
  }

  Widget _buildPie(AppPalette p) {
    final values = spec.series.first.values;
    final total = values.fold<double>(0, (a, b) => a + b);
    return Row(
      children: [
        Expanded(
          child: PieChart(PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 28,
            sections: [
              for (int i = 0; i < values.length; i++)
                PieChartSectionData(
                  value: values[i] <= 0 ? 0.001 : values[i],
                  radius: 46,
                  color: _palette[i % _palette.length],
                  title: total > 0
                      ? '${(values[i] / total * 100).round()}%'
                      : '',
                  titleStyle: const TextStyle(
                      fontSize: 9.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w600),
                ),
            ],
          )),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < values.length && i < 7; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _legend(
                    _palette[i % _palette.length],
                    '${_short(spec.labels[i])} ${values[i].toStringAsFixed(1)}',
                    p),
              ),
          ],
        ),
      ],
    );
  }

  static String _short(String s) =>
      s.length <= 6 ? s : '${s.substring(0, 6)}…';
}
