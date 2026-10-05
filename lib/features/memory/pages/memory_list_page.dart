import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_status_pill.dart';
import '../../../models.dart';
import '../../../theme.dart';
import '../../../utils/relationship_engine.dart';

/// 长期记忆：真实读写当前人格的 AI 抽取记忆（按 核心 / 长期 / 普通 分层）。
///
/// 这一页之前整页都是 mock 数据（"用户的名字是启粤"等假条目），
/// 现在全部接真实数据：搜索、置顶、编辑、遗忘都真实落库。
/// 「避免项」单独用一枚开关切换（它不是分层，是另一种性质）。
class MemoryListPage extends StatefulWidget {
  const MemoryListPage({super.key});

  @override
  State<MemoryListPage> createState() => _MemoryListPageState();
}

class _MemoryListPageState extends State<MemoryListPage> {
  int _tab = 0; // 0 核心 / 1 长期 / 2 普通 / 3 避免
  bool _searching = false;
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final persona = state.activePersona;

    if (persona == null) {
      return SiniScaffold(
        title: '长期记忆',
        body: Center(
          child: Text('请先在侧栏选择一个人格',
              style: TextStyle(color: p.textTertiary)),
        ),
      );
    }

    final all = persona.memory;
    final stats = computeMemoryStats(all);

    // 当前 tab 对应的条目
    List<PersonaMemory> current;
    switch (_tab) {
      case 0:
        current = all
            .where((m) =>
                m.kind == PersonaMemoryKind.fact && m.tier == MemoryTier.core)
            .toList();
        break;
      case 1:
        current = all
            .where((m) =>
                m.kind == PersonaMemoryKind.fact && m.tier == MemoryTier.long)
            .toList();
        break;
      case 2:
        current = all
            .where((m) =>
                m.kind == PersonaMemoryKind.fact && m.tier == MemoryTier.normal)
            .toList();
        break;
      default:
        current = all.where((m) => m.kind == PersonaMemoryKind.avoid).toList();
    }
    // 搜索过滤
    final q = _query.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      current = current.where((m) => m.text.toLowerCase().contains(q)).toList();
    }
    // 命中次数高的排前面（说明反复被提到，更"牢固"）
    current.sort((a, b) {
      if (a.hits != b.hits) return b.hits.compareTo(a.hits);
      return b.createdAt.compareTo(a.createdAt);
    });

    return SiniScaffold(
      title: '长期记忆',
      actions: [
        IconButton(
          tooltip: _searching ? '关闭搜索' : '搜索',
          icon: Icon(
            _searching ? Icons.close_rounded : Icons.search_rounded,
            size: 22,
            color: p.textPrimary,
          ),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) _query.clear();
          }),
        ),
      ],
      body: Column(
        children: [
          // 概览条：真实统计
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, 0),
            child: _overview(p, stats, persona),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: SiniText.bodySm, color: p.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索记忆内容',
                  hintStyle:
                      TextStyle(fontSize: SiniText.bodySm, color: p.textTertiary),
                  prefixIcon:
                      Icon(Icons.search_rounded, size: 18, color: p.textTertiary),
                  filled: true,
                  fillColor: p.itemHover,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          // 分层 Tab（数字是真实条数）
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: p.itemHover,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Row(
                children: [
                  _tabBtn(p, '核心', stats.core, 0),
                  _tabBtn(p, '长期', stats.long, 1),
                  _tabBtn(p, '普通', stats.normal, 2),
                  _tabBtn(p, '避免', stats.avoid, 3),
                ],
              ),
            ),
          ),
          Expanded(
            child: current.isEmpty
                ? _empty(p, stats, persona)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                    itemCount: current.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Spacing.sm),
                    itemBuilder: (_, i) =>
                        _memoryCard(p, state, persona, current[i]),
                  ),
          ),
        ],
      ),
    );
  }

  /// 概览：总条数 + 关系亲密度（真实计算，跟着对话实时变）
  Widget _overview(AppPalette p, MemoryStats stats, Persona persona) {
    final state = AppStateScope.of(context);
    final rel = state.activeRelationship;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _metric(p, '${stats.total}', '已记住'),
              Container(width: 0.5, height: 30, color: p.border),
              _metric(p, '${rel?.rounds ?? 0}', '对话轮数'),
              Container(width: 0.5, height: 30, color: p.border),
              _metric(p, '${rel?.percent ?? 0}%', '亲密度'),
            ],
          ),
          if (rel != null) ...[
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                      value: rel.intimacy,
                      minHeight: 6,
                      backgroundColor: p.mainBg.withValues(alpha: 0.5),
                      valueColor: AlwaysStoppedAnimation(p.brand),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text(rel.stage,
                    style: TextStyle(
                        fontSize: SiniText.labelMd,
                        color: p.brand,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '聊得越多、记得越牢，亲密度就越高',
              style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(AppPalette p, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: SiniText.titleXl,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  TextStyle(fontSize: SiniText.labelMd, color: p.textSecondary)),
        ],
      ),
    );
  }

  Widget _tabBtn(AppPalette p, String label, int count, int i) {
    final selected = i == _tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? p.mainBg : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Text(
            count > 0 ? '$label $count' : label,
            style: TextStyle(
                fontSize: SiniText.labelLg,
                color: selected ? p.textPrimary : p.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
          ),
        ),
      ),
    );
  }

  Widget _empty(AppPalette p, MemoryStats stats, Persona persona) {
    final isFirst = stats.total == 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined, size: 40, color: p.textTertiary),
            const SizedBox(height: Spacing.md),
            Text(
              isFirst ? '还没有任何记忆' : '这一层暂时是空的',
              style: TextStyle(fontSize: SiniText.bodyMd, color: p.textSecondary),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              isFirst
                  ? '和「${persona.name}」聊几句，TA 会自动记住关于你的事'
                  : '继续聊天，相关的记忆会自动沉淀到这一层',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: SiniText.labelLg,
                  color: p.textTertiary,
                  height: 1.5),
            ),
            const SizedBox(height: Spacing.lg),
            TextButton.icon(
              onPressed: () => _addMemory(p, persona),
              icon: Icon(Icons.add_rounded, size: 18, color: p.brand),
              label: Text('手动添加一条',
                  style: TextStyle(fontSize: SiniText.labelLg, color: p.brand)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memoryCard(
      AppPalette p, AppState state, Persona persona, PersonaMemory m) {
    final tone = m.kind == PersonaMemoryKind.avoid
        ? SiniStatusTone.danger
        : switch (m.tier) {
            MemoryTier.core => SiniStatusTone.warning,
            MemoryTier.long => SiniStatusTone.info,
            MemoryTier.normal => SiniStatusTone.neutral,
          };
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
              SiniStatusPill(
                label: m.kind == PersonaMemoryKind.avoid ? '避免' : m.tier.label,
                tone: tone,
              ),
              if (m.hits > 0) ...[
                const SizedBox(width: Spacing.xs),
                SiniStatusPill(
                  label: '提到 ${m.hits} 次',
                  tone: SiniStatusTone.neutral,
                ),
              ],
              const Spacer(),
              Text(_dateLabel(m.createdAt),
                  style: TextStyle(
                      fontSize: SiniText.labelSm, color: p.textTertiary)),
            ],
          ),
          const SizedBox(height: Spacing.sm + 2),
          Text(m.text,
              style: TextStyle(
                  fontSize: SiniText.bodySm + 0.5,
                  color: p.textPrimary,
                  height: 1.5)),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              if (m.kind == PersonaMemoryKind.fact)
                _miniBtn(
                  p,
                  m.tier == MemoryTier.core
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                  m.tier == MemoryTier.core ? '已置顶' : '永久',
                  active: m.tier == MemoryTier.core,
                  onTap: () => state.pinPersonaMemory(persona.id, m.id),
                ),
              const SizedBox(width: Spacing.xs),
              _miniBtn(p, Icons.edit_outlined, '编辑',
                  onTap: () => _editMemory(p, state, persona, m)),
              const SizedBox(width: Spacing.xs),
              _miniBtn(p, Icons.visibility_off_outlined, '遗忘',
                  onTap: () => _forget(p, state, persona, m)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(
    AppPalette p,
    IconData icon,
    String label, {
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: Spacing.sm + 2, vertical: 4),
          decoration: BoxDecoration(
            color: active ? p.brand.withValues(alpha: 0.12) : p.mainBg,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: active ? p.brand : p.textSecondary),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: SiniText.labelSm,
                      color: active ? p.brand : p.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  void _editMemory(
      AppPalette p, AppState state, Persona persona, PersonaMemory m) {
    final ctl = TextEditingController(text: m.text);
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg + 2)),
        title: const Text('编辑记忆'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((v) {
      if (v != null && v.isNotEmpty) {
        state.editPersonaMemory(persona.id, m.id, v);
      }
    });
  }

  void _forget(
      AppPalette p, AppState state, Persona persona, PersonaMemory m) {
    state.removePersonaMemory(persona.id, m.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已遗忘：${m.text.length > 16 ? '${m.text.substring(0, 16)}…' : m.text}'),
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  void _addMemory(AppPalette p, Persona persona) {
    final state = AppStateScope.read(context);
    final ctl = TextEditingController();
    // 当前 tab 决定新增到哪一层
    final tier = switch (_tab) {
      0 => MemoryTier.core,
      1 => MemoryTier.long,
      2 => MemoryTier.normal,
      _ => MemoryTier.normal,
    };
    final kind = _tab == 3 ? PersonaMemoryKind.avoid : PersonaMemoryKind.fact;
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg + 2)),
        title: Text(kind == PersonaMemoryKind.avoid ? '添加避免项' : '添加记忆'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(hintText: '例如：用户喜欢喝美式，不加糖'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    ).then((v) {
      if (v != null && v.isNotEmpty) {
        state.addPersonaMemory(persona.id, v, tier: tier, kind: kind);
      }
    });
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff <= 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) return '$diff 天前';
    return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
