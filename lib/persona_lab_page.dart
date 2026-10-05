import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';
import 'utils/persona_engine.dart';
import 'utils/proactive_engine.dart' show minGapFor;

/// 人格实验室：真实读改当前人格的设定，并**实时预览** AI 实际收到的行为指令。
///
/// 之前整页都是写死的演示数据（滑块拖不动、参数假的、"完成度 64%" 是常量）。
/// 现在：
///  - 四个维度滑块可直接拖动，改动即时写回人格（下次回复生效）；
///  - 「指令预览」能看到 persona_engine 编译出来的真实 prompt，
///    用户第一次能直观看到"我填的东西到底变成了什么"；
///  - 关系 / 认识时间 / 描述 在这里也能改，与编辑页共用同一份数据。
class PersonaLabPage extends StatefulWidget {
  const PersonaLabPage({super.key});

  @override
  State<PersonaLabPage> createState() => _PersonaLabPageState();
}

class _PersonaLabPageState extends State<PersonaLabPage> {
  bool _showPreview = false;

  /// 拖滑块时高频调用 updatePersona 会不停落盘 + 全页重建。
  /// 拖动的每一帧用 persist:false（只改内存、界面即时反馈），
  /// 松手时 onChangeEnd 再 persist:true 落盘一次。
  void _setTrait(AppState state, Persona persona,
      {double? warmth,
      double? rationality,
      double? initiative,
      double? humor,
      bool persist = false}) {
    state.updatePersona(
      persona.copyWith(
        warmth: warmth,
        rationality: rationality,
        initiative: initiative,
        humor: humor,
      ),
      persist: persist,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final persona = state.activePersona;

    return Scaffold(
      backgroundColor: p.mainBg,
      appBar: AppBar(
        backgroundColor: p.mainBg,
        elevation: 0,
        title: const Text('人格实验室'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: '编辑描述 / 关系',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => Navigator.of(context).pushNamed('/persona/edit'),
          ),
          IconButton(
            tooltip: '记忆管理',
            icon: const Icon(Icons.psychology_outlined, size: 20),
            onPressed: () => Navigator.of(context).pushNamed('/memory'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: persona == null
          ? Center(
              child: Text('请先在侧栏选择一个人格',
                  style: TextStyle(color: p.textTertiary)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _headerCard(context, persona, p, state),
                const SizedBox(height: 16),

                // 关系 / 认识时间（真实值，非写死）
                _section('关系设定', p),
                _infoCard(p, [
                  ('关系', persona.relationship.isEmpty ? '未设置' : persona.relationship),
                  ('认识时间', persona.since.trim().isEmpty ? '未设置' : persona.since.trim()),
                  ('长期记忆', '${persona.memory.length} 条'),
                ]),
                const SizedBox(height: 16),

                // 关系模型：由真实对话数据实时算出
                _section('关系模型', p),
                _relationCard(p, state),
                const SizedBox(height: 16),

                // 记忆分层统计：真实条数
                _section('记忆统计', p),
                _memoryStatsCard(p, state),
                const SizedBox(height: 16),

                // 四维度：真的能拖、真的存
                _section('性格参数', p),
                Text('拖动即刻生效，下一条回复就按新性格来',
                    style: TextStyle(
                        fontSize: SiniTextX.labelMd,
                        color: p.textTertiary)),
                const SizedBox(height: 8),
                _trait(p, '温柔度', persona.warmth, '冷静克制', '体贴柔软',
                    (v) => _setTrait(state, persona, warmth: v),
                    (v) => _setTrait(state, persona, warmth: v, persist: true)),
                _trait(p, '理性度', persona.rationality, '重感受', '重逻辑',
                    (v) => _setTrait(state, persona, rationality: v),
                    (v) =>
                        _setTrait(state, persona, rationality: v, persist: true)),
                _trait(p, '主动性', persona.initiative, '被动接话', '主动找话',
                    (v) => _setTrait(state, persona, initiative: v),
                    (v) =>
                        _setTrait(state, persona, initiative: v, persist: true)),
                _trait(p, '幽默感', persona.humor, '正经', '爱玩梗',
                    (v) => _setTrait(state, persona, humor: v),
                    (v) => _setTrait(state, persona, humor: v, persist: true)),

                const SizedBox(height: 12),
                _resetRow(state, persona, p),
                const SizedBox(height: 20),

                // 主动搭话：开关 + 手动触发一次（方便马上看到效果）
                _section('主动搭话', p),
                _proactiveCard(context, state, persona, p),
                const SizedBox(height: 20),

                // 指令预览：把"设定 → AI 实际收到的内容"摊开给用户看
                _section('指令预览', p),
                Text('这是 AI 实际收到的行为准则（由你上面的设定自动编译而来）',
                    style: TextStyle(
                        fontSize: SiniTextX.labelMd, color: p.textTertiary)),
                const SizedBox(height: 8),
                _previewCard(context, persona, p),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ── 顶部卡：头像 + 名字 + 完成度（真实计算）────────────
  Widget _headerCard(
      BuildContext context, Persona persona, AppPalette p, AppState state) {
    final pct = _completeness(persona);
    final seed = persona.gradientSeed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.fromARGB(255, seed[0], seed[1], seed[2]),
                  Color.fromARGB(255, seed[3], seed[4], seed[5]),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            alignment: Alignment.center,
            child: Text(
              persona.name.characters.first,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(persona.name,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary)),
                const SizedBox(height: 4),
                Text(
                    persona.subtitle.trim().isEmpty ? '还没有一句话印象' : persona.subtitle,
                    style: TextStyle(fontSize: 13, color: p.textSecondary)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 6,
                    backgroundColor: p.border,
                    valueColor: AlwaysStoppedAnimation(p.brand),
                  ),
                ),
                const SizedBox(height: 5),
                Text('完成度 $pct%',
                    style:
                        TextStyle(fontSize: 11.5, color: p.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 完成度：与详情页同一套算法（描述 40 + 关系 20 + 时间 15 + 维度偏离度 25）
  int _completeness(Persona p) {
    int score = 0;
    if (p.description.trim().isNotEmpty) score += 40;
    if (p.relationship.trim().isNotEmpty) score += 20;
    if (p.since.trim().isNotEmpty) score += 15;
    final d = (p.warmth - 0.5).abs() +
        (p.rationality - 0.5).abs() +
        (p.initiative - 0.5).abs() +
        (p.humor - 0.5).abs();
    score += (d / 2.0 * 25).round().clamp(0, 25) as int;
    return score.clamp(0, 100) as int;
  }

  /// 关系模型：亲密度、对话轮数、好评数、关系阶段 —— 全部由真实对话数据算出
  Widget _relationCard(AppPalette p, AppState state) {
    final rel = state.activeRelationship;
    if (rel == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${rel.percent}',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                      height: 1)),
              Text('%',
                  style: TextStyle(
                      fontSize: 13,
                      color: p.textSecondary,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('亲密度 · ${rel.stage}',
                    style: TextStyle(fontSize: 12.5, color: p.brand)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rel.intimacy,
              minHeight: 7,
              backgroundColor: p.border,
              valueColor: AlwaysStoppedAnimation(p.brand),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniStat(p, '${rel.rounds}', '对话轮数'),
              _miniStat(p, '${rel.memoryCount}', '记住的事'),
              _miniStat(p, '${rel.likes}', '收到好评'),
              _miniStat(p, rel.years == null ? '—' : '${rel.years}', '认识年数'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '亲密度随聊天实时增长：对话 45% + 记忆沉淀 30% + 好评 15% + 认识时长 10%',
            style: TextStyle(
                fontSize: 10.5, color: p.textTertiary, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(AppPalette p, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary)),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: p.textSecondary)),
        ],
      ),
    );
  }

  /// 主动搭话：开关 + 手动触发一次。让"允许 TA 主动找你"这件事在实验室里
  /// 马上能看到效果（不用等到心跳真的挑中时机）。
  Widget _proactiveCard(
      BuildContext context, AppState state, Persona persona, AppPalette p) {
    final on = state.proactiveChatEnabled;
    // 按主动性估算大致的搭话间隔，让用户有直观预期
    final gap = minGapFor(persona);
    final gapLabel = gap.inMinutes < 60
        ? '约 ${gap.inMinutes} 分钟'
        : '约 ${(gap.inMinutes / 60).toStringAsFixed(1)} 小时';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('允许 TA 主动来找我',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: p.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      on
                          ? '已开启 · 按「${persona.name}」的性格，最快 $gapLabel 才可能来一次'
                          : '开启后 TA 会像真人一样偶尔主动找你说话',
                      style: TextStyle(fontSize: 12, color: p.textTertiary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: on,
                onChanged: (v) => state.setProactiveChatEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _tryProactiveNow(context, state, persona),
              icon: Icon(Icons.waving_hand_outlined,
                  size: 15, color: p.textSecondary),
              label: Text('让它现在就来找我',
                  style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }

  /// 手动触发一次主动搭话，给出结果反馈（说了 / 这次没说）
  Future<void> _tryProactiveNow(
      BuildContext context, AppState state, Persona persona) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('正在问 TA 现在的想法…'),
      duration: Duration(seconds: 2),
    ));
    final before = state.activeConversation?.messages.length ?? 0;
    final ran = await state.triggerProactiveNow();
    if (!mounted) return;
    messenger.clearSnackBars();
    if (!ran) {
      messenger.showSnackBar(const SnackBar(
        content: Text('暂时没法搭话：需要先配置模型，并且有一个对话。'),
        duration: Duration(seconds: 3),
      ));
      return;
    }
    final after = state.activeConversation?.messages.length ?? 0;
    messenger.showSnackBar(SnackBar(
      content: Text(after > before
          ? '${persona.name} 主动开口了，回聊天看看'
          : '${persona.name} 这次觉得没什么想说的（真实的人也有说不出话的时候）'),
      duration: const Duration(seconds: 3),
    ));
  }

  /// 记忆统计：真实分层条数
  Widget _memoryStatsCard(AppPalette p, AppState state) {
    final s = state.activeMemoryStats;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _miniStat(p, '${s.total}', '总计'),
              _miniStat(p, '${s.core}', '核心'),
              _miniStat(p, '${s.long}', '长期'),
              _miniStat(p, '${s.normal}', '普通'),
              _miniStat(p, '${s.avoid}', '避免'),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/memory'),
              icon: Icon(Icons.psychology_outlined,
                  size: 15, color: p.textSecondary),
              label: Text('去管理记忆',
                  style:
                      TextStyle(fontSize: 12.5, color: p.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(AppPalette p, List<(String, String)> rows) {    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              children: [
                Text(rows[i].$1,
                    style:
                        TextStyle(fontSize: 13, color: p.textSecondary)),
                const Spacer(),
                Text(rows[i].$2,
                    style: TextStyle(
                        fontSize: 13,
                        color: p.textPrimary,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 真实可拖的性格维度；onChangeEnd 时落盘
  Widget _trait(AppPalette p, String label, double value, String lowHint,
      String highHint, void Function(double) onChanged,
      void Function(double) onChangeEnd) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(label,
                    style: TextStyle(fontSize: 13, color: p.textSecondary)),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: p.brand,
                    inactiveTrackColor: p.border,
                    thumbColor: p.textPrimary,
                    overlayColor: p.brand.withValues(alpha: 0.1),
                  ),
                  child: Slider(
                    value: value,
                    onChanged: onChanged,
                    onChangeEnd: onChangeEnd,
                  ),
                ),
              ),
              SizedBox(
                width: 30,
                child: Text('${(value * 100).round()}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: p.brand,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 60, right: 30, bottom: 6),
            child: Row(
              children: [
                Text(lowHint,
                    style:
                        TextStyle(fontSize: 10.5, color: p.textTertiary)),
                const Spacer(),
                Text(highHint,
                    style:
                        TextStyle(fontSize: 10.5, color: p.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resetRow(AppState state, Persona persona, AppPalette p) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () {
          state.updatePersona(
            persona.copyWith(
              warmth: 0.5,
              rationality: 0.5,
              initiative: 0.5,
              humor: 0.5,
            ),
            persist: true,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('已恢复中性'),
                duration: Duration(milliseconds: 1000)),
          );
        },
        icon: Icon(Icons.restart_alt_rounded, size: 16, color: p.textSecondary),
        label: Text('恢复中性',
            style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
      ),
    );
  }

  /// 指令预览：折叠面板 + 等宽可滚动文本 + 复制
  Widget _previewCard(BuildContext context, Persona persona, AppPalette p) {
    final directive = buildPersonaDirective(persona);
    // 未被设定过的人格会拿到空指令 → 说明它走的是通用助手
    final text = directive.trim().isEmpty
        ? '（这个人格还没有任何设定，目前走的是通用助手模式。\n'
            '去「编辑」补上描述和关系，这里就会出现 AI 实际收到的准则。）'
        : directive;

    return Container(
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _showPreview = !_showPreview),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.code_rounded, size: 16, color: p.textSecondary),
                  const SizedBox(width: 8),
                  Text('${text.characters.length} 字',
                      style: TextStyle(
                          fontSize: 13,
                          color: p.textPrimary,
                          fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Text(_showPreview ? '收起' : '展开查看',
                      style: TextStyle(fontSize: 12.5, color: p.brand)),
                  Icon(
                    _showPreview
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: p.brand,
                  ),
                ],
              ),
            ),
          ),
          if (_showPreview) ...[
            Divider(height: 0.5, color: p.border),
            Container(
              constraints: const BoxConstraints(maxHeight: 340),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: SelectableText(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.65,
                    color: p.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            Divider(height: 0.5, color: p.border),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('已复制指令'),
                        duration: Duration(milliseconds: 1000)),
                  );
                },
                icon: Icon(Icons.content_copy_outlined,
                    size: 15, color: p.textSecondary),
                label: Text('复制',
                    style:
                        TextStyle(fontSize: 12.5, color: p.textSecondary)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String label, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: p.textPrimary),
      ),
    );
  }
}

/// 实验室专用的小号字（避免为了这点地方去动全局 token）
class SiniTextX {
  static const double labelMd = 11.5;
}
