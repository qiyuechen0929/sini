import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../theme.dart';
import '../../../utils/usage_store.dart';
import '../../../widgets/usage_receipt.dart'
    show ReceiptData, showReceiptExportSheet;

/// 用量统计面板：各模型 Token 消耗 + 按日趋势。
/// 风格参考 DeepSeek Status 那类面板：深色 hero 卡 + 数据块 + 时间网格。
class UsagePage extends StatefulWidget {
  const UsagePage({super.key});

  @override
  State<UsagePage> createState() => _UsagePageState();
}

enum _Range { today, d7, d30, all }

class _UsagePageState extends State<UsagePage> {
  _Range _range = _Range.d7;

  @override
  void initState() {
    super.initState();
    UsageStore.instance.load();
  }

  DateTime get _rangeStart {
    final now = DateTime.now();
    switch (_range) {
      case _Range.today:
        return DateTime(now.year, now.month, now.day);
      case _Range.d7:
        return now.subtract(const Duration(days: 7));
      case _Range.d30:
        return now.subtract(const Duration(days: 30));
      case _Range.all:
        return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return SiniScaffold(
      title: '用量统计',
      body: AnimatedBuilder(
        animation: UsageStore.instance,
        builder: (context, _) {
          final events = UsageStore.instance.inRange(_rangeStart);
          final total = UsageStore.instance.totalTokens(events);
          final pt = UsageStore.instance.promptTokens(events);
          final ct = UsageStore.instance.completionTokens(events);
          final byModel = UsageStore.instance.byModel(events);
          final byPersona = UsageStore.instance.byPersona(events);
          final byDay = UsageStore.instance.byDay(events);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxl),
            children: [
              // 时间范围选择
              SegmentedButton<_Range>(
                segments: const [
                  ButtonSegment(value: _Range.today, label: Text('今天')),
                  ButtonSegment(value: _Range.d7, label: Text('7 天')),
                  ButtonSegment(value: _Range.d30, label: Text('30 天')),
                  ButtonSegment(value: _Range.all, label: Text('全部')),
                ],
                selected: {_range},
                onSelectionChanged: (s) => setState(() => _range = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: Spacing.md),

              // Hero 总量卡（深色渐变，仿状态面板风格）
              _HeroCard(
                total: total,
                prompt: pt,
                completion: ct,
                calls: events.length,
              ),
              const SizedBox(height: Spacing.lg),

              // 按日趋势
              if (byDay.isNotEmpty) ...[
                _sectionTitle('按日趋势', p),
                const SizedBox(height: Spacing.sm),
                _DayTrend(byDay: byDay, p: p),
                const SizedBox(height: Spacing.lg),
              ],

              // 各人格消耗（哪位 TA 更费钱一目了然）
              if (byPersona.length > 1 ||
                  (byPersona.isNotEmpty && byPersona.first.personaName != '未标记')) ...[
                _sectionTitle('各人格消耗', p),
                const SizedBox(height: Spacing.sm),
                ...byPersona.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ModelRow(
                          modelId: m.personaName,
                          tokens: m.tokens,
                          calls: m.calls,
                          maxTokens: byPersona.first.tokens,
                          p: p),
                    )),
                const SizedBox(height: Spacing.lg),
              ],

              // 各模型消耗
              _sectionTitle('各模型消耗', p),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text(
                  '（本机累计 ${UsageStore.instance.events.length} 条记录'
                  '${UsageStore.instance.events.isEmpty ? " · 聊一句后重进本页；若仍为 0，说明模型响应未带用量且估算未触发" : ""}）',
                  style: TextStyle(fontSize: 10.5, color: p.textTertiary),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              if (byModel.isEmpty)
                Container(
                  padding: const EdgeInsets.all(Spacing.xl),
                  decoration: BoxDecoration(
                    color: p.itemHover,
                    borderRadius: BorderRadius.circular(Radii.xl),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.insights_outlined,
                          size: 34, color: p.textTertiary),
                      const SizedBox(height: Spacing.sm),
                      Text('这个时间段还没有消耗记录',
                          style: TextStyle(
                              fontSize: SiniText.bodySm,
                              color: p.textTertiary)),
                      const SizedBox(height: 4),
                      Text('和 TA 聊几句就会出现在这里',
                          style: TextStyle(
                              fontSize: SiniText.labelMd,
                              color: p.textTertiary.withValues(alpha: .7))),
                    ],
                  ),
                )
              else
                ...byModel.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ModelRow(
                          modelId: m.modelId,
                          tokens: m.tokens,
                          calls: m.calls,
                          maxTokens: byModel.first.tokens,
                          p: p),
                    )),

              const SizedBox(height: Spacing.lg),

              // 导出用量小票
              if (events.isNotEmpty)
                SiniButton(
                  label: '导出用量小票',
                  leadingIcon: Icons.receipt_long_outlined,
                  onTap: () {
                    final now = DateTime.now();
                    final label = switch (_range) {
                      _Range.today => '今天',
                      _Range.d7 => '最近 7 天',
                      _Range.d30 => '最近 30 天',
                      _Range.all => '全部历史',
                    };
                    String fmt(DateTime d) =>
                        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                    final start = events
                        .map((e) => e.ts)
                        .reduce((a, b) => a.isBefore(b) ? a : b);
                    showReceiptExportSheet(
                      context,
                      p,
                      ReceiptData(
                        rangeLabel: label,
                        dateLabel:
                            '${fmt(start)} ~ ${fmt(now)}',
                        totalTokens: total,
                        promptTokens: pt,
                        completionTokens: ct,
                        calls: events.length,
                        byPersona: byPersona
                            .map((x) => (
                                  name: x.personaName,
                                  tokens: x.tokens,
                                  calls: x.calls
                                ))
                            .toList(),
                        byModel: byModel
                            .map((x) => (
                                  name: x.modelId,
                                  tokens: x.tokens,
                                  calls: x.calls
                                ))
                            .toList(),
                      ),
                    );
                  },
                  height: 46,
                  expand: true,
                ),
              const SizedBox(height: Spacing.lg),
              // 清空
              if (UsageStore.instance.events.isNotEmpty)
                Center(
                  child: TextButton(
                    onPressed: () => showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        backgroundColor: p.surface,
                        title: const Text('清空用量记录？'),
                        content: const Text('本机保存的消耗明细会全部删除，不影响模型配置。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: const Text('清空')),
                        ],
                      ),
                    ).then((ok) {
                      if (ok == true) UsageStore.instance.clear();
                    }),
                    child: Text('清空全部记录',
                        style: TextStyle(
                            fontSize: 12.5, color: p.textTertiary)),
                  ),
                ),
              Center(
                child: Text('统计只保存在本机 · 不含图片生成的消耗',
                    style: TextStyle(
                        fontSize: 10.5, color: p.textTertiary)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String t, AppPalette p) => Text(t,
      style: TextStyle(
          fontSize: SiniText.titleSm,
          fontWeight: FontWeight.w600,
          color: p.textPrimary));
}

/// 深色 hero 卡：总消耗大数字 + 输入/输出拆分
class _HeroCard extends StatelessWidget {
  final int total;
  final int prompt;
  final int completion;
  final int calls;
  const _HeroCard({
    required this.total,
    required this.prompt,
    required this.completion,
    required this.calls,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF241E52), Color(0xFF432C85), Color(0xFF1B1733)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x33432C85), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Token 消耗',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .65),
                      fontSize: 11.5,
                      letterSpacing: 1)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10A37F).withValues(alpha: .25),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$calls 次调用',
                    style: const TextStyle(
                        color: Color(0xFF7BE3C4), fontSize: 10.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(formatTokens(total),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1)),
          const SizedBox(height: 14),
          // 输入/输出占比条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                      flex: total == 0 ? 1 : prompt,
                      child: Container(color: const Color(0xFF7B6CFF))),
                  Expanded(
                      flex: total == 0 ? 1 : completion,
                      child: Container(color: const Color(0xFF10A37F))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _dot(const Color(0xFF7B6CFF)),
              const SizedBox(width: 5),
              Text('输入 ${formatTokens(prompt)}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .75),
                      fontSize: 11)),
              const SizedBox(width: 14),
              _dot(const Color(0xFF10A37F)),
              const SizedBox(width: 5),
              Text('输出 ${formatTokens(completion)}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .75),
                      fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

/// 单个模型一行：名字 + 调用次数 + 用量占比条 + token 数
class _ModelRow extends StatelessWidget {
  final String modelId;
  final int tokens;
  final int calls;
  final int maxTokens;
  final AppPalette p;
  const _ModelRow({
    required this.modelId,
    required this.tokens,
    required this.calls,
    required this.maxTokens,
    required this.p,
  });

  @override
  Widget build(BuildContext context) {
    final frac = maxTokens <= 0 ? 0.0 : tokens / maxTokens;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(modelId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: SiniText.bodySm + 0.5,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary)),
              ),
              Text('${formatTokens(tokens)} tok · $calls 次',
                  style: TextStyle(fontSize: 11.5, color: p.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(children: [
                Container(color: p.border.withValues(alpha: .5)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: frac.clamp(0.02, 1.0),
                  child: Container(
                      decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      Color(0xFF10A37F),
                      Color(0xFF6C5CE7),
                    ]),
                    borderRadius: BorderRadius.circular(3),
                  )),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// 最近 30 天按日柱状图
class _DayTrend extends StatelessWidget {
  final List<({DateTime day, int tokens})> byDay;
  final AppPalette p;
  const _DayTrend({required this.byDay, required this.p});

  @override
  Widget build(BuildContext context) {
    // 补全最近 14 天的空缺天
    final now = DateTime.now();
    final map = {for (final e in byDay) DateTime(e.day.year, e.day.month, e.day.day): e.tokens};
    final days = <DateTime>[
      for (int i = 13; i >= 0; i--)
        DateTime(now.year, now.month, now.day).subtract(Duration(days: i))
    ];
    final shown = byDay.length <= 14
        ? [for (final d in days) (day: d, tokens: map[d] ?? 0)]
        : byDay.sublist(byDay.length - 14);
    final maxV = shown.fold<int>(1, (m, e) => e.tokens > m ? e.tokens : m);

    return Container(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 6),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 120,
            child: BarChart(BarChartData(
              maxY: maxV * 1.15,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: [
                for (int i = 0; i < shown.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: shown[i].tokens.toDouble(),
                        width: 12,
                        borderRadius: BorderRadius.circular(3),
                        color: shown[i].tokens > 0
                            ? const Color(0xFF10A37F)
                            : p.border.withValues(alpha: .6),
                      ),
                    ],
                  ),
              ],
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                    '${shown[group.x].day.month}/${shown[group.x].day.day}\n${formatTokens(rod.toY.round())} tok',
                    TextStyle(fontSize: 10, color: p.textPrimary),
                  ),
                ),
              ),
            )),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${shown.first.day.month}/${shown.first.day.day}',
                  style: TextStyle(fontSize: 10, color: p.textTertiary)),
              Text('今天',
                  style: TextStyle(fontSize: 10, color: p.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }
}
