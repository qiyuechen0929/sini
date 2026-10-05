import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/design/tokens.dart';
import '../../../../theme.dart';
import '../../../../utils/romance_engine.dart' show MoodPoint, moodEmoji, moodToValue;

/// 人格详情页「情绪曲线」：近 60 次互动的心情/信号走势。
/// 没有历史时给空态，不画假线。
class MoodCurveCard extends StatelessWidget {
  final List<MoodPoint> history;
  final String currentMood;
  final double currentScore;
  const MoodCurveCard({
    super.key,
    required this.history,
    required this.currentMood,
    required this.currentScore,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('情绪曲线',
                  style: TextStyle(
                      fontSize: SiniText.titleSm,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary)),
              const Spacer(),
              Text('${moodEmoji(currentMood)} 现在 · $currentMood',
                  style: TextStyle(fontSize: SiniText.labelMd, color: p.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '近 ${history.length} 次有记录的互动里，TA 的心情与亲密度信号',
            style: TextStyle(fontSize: SiniText.labelMd, color: p.textTertiary),
          ),
          const SizedBox(height: Spacing.md),
          if (history.length < 2)
            Container(
              height: 120,
              alignment: Alignment.center,
              child: Text(
                '再多聊几次，这里会长出 TA 的心情曲线',
                style: TextStyle(fontSize: SiniText.bodySm, color: p.textTertiary),
              ),
            )
          else
            SizedBox(
              height: 160,
              child: RepaintBoundary(
                child: _MoodLineChart(
                  history: history,
                  p: p,
                  currentScore: currentScore,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoodLineChart extends StatelessWidget {
  final List<MoodPoint> history;
  final AppPalette p;
  final double currentScore;
  const _MoodLineChart({
    required this.history,
    required this.p,
    required this.currentScore,
  });

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (int i = 0; i < history.length; i++) {
      spots.add(FlSpot(i.toDouble(), moodToValue(history[i].mood)));
    }
    final maxY = 100.0;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        backgroundColor: Colors.transparent,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: p.border,
            strokeWidth: 0.6,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= history.length) return const SizedBox.shrink();
                if (i != 0 && i != history.length - 1 && i % 2 != 0) {
                  return const SizedBox.shrink();
                }
                final d = history[i].at;
                final label =
                    '${d.month}/${d.day}';
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label,
                      style: TextStyle(fontSize: 10, color: p.textTertiary)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => p.surface,
            getTooltipItems: (spots) {
              return spots.map((s) {
                final i = s.x.toInt();
                final m = history[i];
                return LineTooltipItem(
                  '${moodEmoji(m.mood)} ${m.mood}\n${m.at.month}/${m.at.day} ${m.at.hour}:${m.at.minute.toString().padLeft(2, '0')}',
                  TextStyle(
                    color: p.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 2.5,
            color: p.brand,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                final m = history[index];
                return FlDotCirclePainter(
                  radius: index == history.length - 1 ? 4 : 2.2,
                  color: p.brand,
                  strokeWidth: 0,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: p.brand.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }
}
