import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_sheet.dart';
import '../../../core/widgets/sini_status_pill.dart';
import '../../../theme.dart';
import '../../../models.dart';
import '../../../app_state.dart';
import '../../../widgets/persona_avatar.dart';
import '../../../widgets/persona_share_sheet.dart';
import 'widgets/mood_curve.dart';
import 'widgets/persona_completeness.dart';

class PersonaDetailPage extends StatelessWidget {
  const PersonaDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final persona = state.activePersona;
    if (persona == null) {
      return SiniScaffold(
        title: '人物',
        body: Center(
          child: Text('请先选择一个人物', style: TextStyle(color: p.textTertiary)),
        ),
      );
    }
    return SiniScaffold(
      title: persona.name,
      actions: [
        // 默认的「默认助手」不可编辑 / 不可删除
        if (!persona.locked)
          IconButton(
            tooltip: '编辑',
            icon: Icon(Icons.edit_outlined, size: 20, color: p.textPrimary),
            onPressed: () => Navigator.of(context).pushNamed('/persona/edit'),
          ),
        if (!persona.locked)
          IconButton(
            tooltip: '删除',
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: p.textPrimary),
            onPressed: () => _confirmDelete(context, persona.name, () {
              state.deletePersona(persona.id);
              Navigator.of(context).pop();
            }),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xxxl),
        children: [
          // 顶部 hero
          Center(
            child: Column(
              children: [
                PersonaAvatar(persona: persona, size: 96, showSparkle: true),
                const SizedBox(height: Spacing.md),
                Text(persona.name,
                    style: TextStyle(
                        fontSize: SiniText.displayMedium - 4,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                        letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text(persona.subtitle,
                    style: TextStyle(fontSize: SiniText.bodyMd, color: p.textSecondary)),
                const SizedBox(height: Spacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (persona.locked) ...[
                        SiniStatusPill(label: '默认', tone: SiniStatusTone.neutral),
                        const SizedBox(width: Spacing.xs),
                      ],
                      SiniStatusPill(label: 'v1', tone: SiniStatusTone.info),
                    const SizedBox(width: Spacing.xs),
                    // 完成度按实际填了多少设定来算，不再是写死的 64%
                    SiniStatusPill(
                      label: '完成度 ${_completeness(persona)}%',
                      tone: _completeness(persona) >= 60
                          ? SiniStatusTone.success
                          : SiniStatusTone.warning,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xxl),

          // 快速入口 2x2
          Row(
            children: [
              Expanded(
                child: _quickAction(
                  context,
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '开始对话',
                  onTap: () => Navigator.of(context).pushReplacementNamed('/'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: _quickAction(
                  context,
                  icon: Icons.auto_stories_outlined,
                  label: '回忆册',
                  onTap: () => Navigator.of(context).pushNamed('/moments'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: _quickAction(
                  context,
                  icon: Icons.edit_note_rounded,
                  label: '周记',
                  onTap: () => Navigator.of(context).pushNamed('/weekly-stories'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: _quickAction(
                  context,
                  icon: Icons.science_outlined,
                  label: '实验室',
                  onTap: () => Navigator.of(context).pushNamed('/lab'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: _quickAction(
                  context,
                  icon: Icons.add_photo_alternate_outlined,
                  label: '添加素材',
                  onTap: () => Navigator.of(context).pushNamed('/persona/import'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xxl),

          // ── 设定卡：关系 / 认识时间 ──────────────────
          Text('关系设定',
              style: TextStyle(
                  fontSize: SiniText.titleSm,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary)),
          const SizedBox(height: Spacing.sm),
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: p.itemHover,
              borderRadius: BorderRadius.circular(Radii.xl),
            ),
            child: Column(
              children: [
                _kv(p, '关系', persona.relationship.isEmpty ? '未设置' : persona.relationship),
                if (persona.sinceLabel.isNotEmpty) ...[
                  const SizedBox(height: Spacing.md),
                  _kv(p, '认识时间', persona.sinceLabel),
                ],
                const SizedBox(height: Spacing.md),
                _kv(p, '长期记忆',
                    '${persona.memory.length} 条' +
                        (persona.memory.isEmpty ? '（聊天中会自动积累）' : '')),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),

          // ── 情绪曲线：亲密度 / 心情历史可视化 ──
          MoodCurveCard(
            history: state.moodHistoryOf(persona.id),
            currentMood: state.affinityOf(persona.id)?.mood ?? '平静',
            currentScore: state.affinityOf(persona.id)?.romanceScore ?? 0,
          ),
          const SizedBox(height: Spacing.xxl),

          // ── 性格维度：把四档可视化，让用户看到"我调的东西生效了" ──
          Row(
            children: [
              Text('性格维度',
                  style: TextStyle(
                      fontSize: SiniText.titleSm,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary)),
              const Spacer(),
              if (!persona.locked)
                GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/persona/edit'),
                  child: Text('调整',
                      style: TextStyle(
                          fontSize: SiniText.labelLg,
                          color: p.brand,
                          fontWeight: FontWeight.w500)),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: p.itemHover,
              borderRadius: BorderRadius.circular(Radii.xl),
            ),
            child: Column(
              children: [
                _traitBar(p, '温柔度', persona.warmth, '冷静克制', '体贴柔软'),
                const SizedBox(height: Spacing.md),
                _traitBar(p, '理性度', persona.rationality, '重感受', '重逻辑'),
                const SizedBox(height: Spacing.md),
                _traitBar(p, '主动性', persona.initiative, '被动接话', '主动找话'),
                const SizedBox(height: Spacing.md),
                _traitBar(p, '幽默感', persona.humor, '正经', '爱玩梗'),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xxl),

          // ── 性格摘要（真实描述，不再是写死的示例）──────
          Text('性格摘要',
              style: TextStyle(
                  fontSize: SiniText.titleSm,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary)),
          const SizedBox(height: Spacing.sm),
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: p.itemHover,
              borderRadius: BorderRadius.circular(Radii.xl),
            ),
            child: Text(
              persona.description.trim().isEmpty
                  ? '还没有描述 TA 的性格。点「调整」补一段描述，'
                      '写着写着 TA 就会越来越像你想的那个人。'
                  : persona.description.trim(),
              style: TextStyle(
                  fontSize: SiniText.bodyMd,
                  color: persona.description.trim().isEmpty
                      ? p.textTertiary
                      : p.textPrimary,
                  height: 1.6),
            ),
          ),
          const SizedBox(height: Spacing.xxl),

          // ── 分享人格养成卡 ──────────────────
          SiniButton(
            label: '分享人格卡片',
            leadingIcon: Icons.ios_share_rounded,
            onTap: () => showPersonaShareSheet(context, persona, state),
            style: SiniButtonStyle.secondary,
            expand: true,
            height: 48,
          ),
          const SizedBox(height: Spacing.xxl),

          // 操作
          SiniButton(
            label: '去人格实验室详细调整',
            leadingIcon: Icons.tune_rounded,
            onTap: () => Navigator.of(context).pushNamed('/lab'),
            style: SiniButtonStyle.secondary,
            expand: true,
            height: 48,
          ),
        ],
      ),
    );
  }

  /// 完成度算法见 [personaCompleteness]（抽到共用文件，人格列表页也用同一套）
  int _completeness(Persona p) => personaCompleteness(p);

  Widget _kv(AppPalette p, String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(k,
              style: TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary)),
        ),
        Expanded(
          child: Text(v,
              style: TextStyle(
                  fontSize: SiniText.bodySm,
                  color: p.textPrimary,
                  height: 1.5)),
        ),
      ],
    );
  }

  /// 一条性格维度：标签 + 进度条 + 左右语义（让用户直观看到倾向）
  Widget _traitBar(
      AppPalette p, String label, double value, String lowHint, String highHint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(label,
                  style: TextStyle(
                      fontSize: SiniText.bodySm,
                      color: p.textPrimary,
                      fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: p.mainBg.withValues(alpha: 0.5),
                  valueColor: AlwaysStoppedAnimation(p.brand),
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text('${(value * 100).round()}',
                style: TextStyle(
                    fontSize: SiniText.labelMd,
                    color: p.brand,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 52),
          child: Text('${value < 0.4 ? lowHint : (value > 0.6 ? highHint : "适中")}',
              style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary)),
        ),
      ],
    );
  }

  Widget _quickAction(BuildContext context,
      {required IconData icon, required String label, required VoidCallback onTap}) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Material(
      color: p.itemHover,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: onTap,
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: p.textPrimary),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: SiniText.labelMd, color: p.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String name, VoidCallback onConfirm) {
    showSiniSheet<void>(
      context: context,
      title: '删除人物？',
      subtitle: '「$name」及其所有对话、记忆将被永久删除，无法恢复。',
      danger: true,
      primary: ('删除', () {
        Navigator.of(context).pop();
        onConfirm();
      }),
      secondary: ('取消', () => Navigator.of(context).pop()),
    );
  }
}
