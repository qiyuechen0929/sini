import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_sheet.dart';
import '../../../core/widgets/sini_status_pill.dart';
import '../../../data/llm_provider.dart';
import '../../../theme.dart';

/// 模型管理：多个模型配置，可增删改、设为默认
class ModelManagePage extends StatelessWidget {
  const ModelManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final configs = state.modelConfigs;

    return SiniScaffold(
      title: '模型管理',
      actions: [
        IconButton(
          tooltip: '添加模型',
          icon: Icon(Icons.add_rounded, size: 22, color: p.textPrimary),
          onPressed: () => Navigator.of(context).pushNamed('/settings/model/edit'),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xxxl),
        children: [
          if (configs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xxxl),
              child: Column(
                children: [
                  Icon(Icons.dashboard_customize_outlined, size: 40, color: p.textTertiary),
                  const SizedBox(height: Spacing.md),
                  Text(
                    '还没有配置模型',
                    style: TextStyle(fontSize: SiniText.bodyMd, color: p.textSecondary),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    '选择供应商，填一个 API Key 就能实时拉取可用模型',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: SiniText.labelMd, color: p.textTertiary),
                  ),
                ],
              ),
            ),
          for (final cfg in configs)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: _ModelCard(cfg: cfg),
            ),
          const SizedBox(height: Spacing.lg),
          SiniButton(
            label: '添加模型',
            leadingIcon: Icons.add_rounded,
            onTap: () => Navigator.of(context).pushNamed('/settings/model/edit'),
            style: SiniButtonStyle.primary,
            expand: true,
            height: 48,
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            '所有配置与 API Key 都保存在本机浏览器存储中，清除浏览器数据会一并丢失。',
            style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatefulWidget {
  final ModelConfig cfg;
  const _ModelCard({required this.cfg});

  @override
  State<_ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<_ModelCard> {
  bool _testing = false;

  Future<void> _testConnection(BuildContext context) async {
    setState(() => _testing = true);
    // 用当前 key 真实发一条最小请求，验证能不能调通 / 报什么错
    final res = await chatComplete(
      cfg: widget.cfg,
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
      maxTokens: 8,
    );
    setState(() => _testing = false);
    if (!context.mounted) return;
    final ok = res.ok;
    await showSiniSheet<void>(
      context: context,
      title: ok ? '连接成功 ✅' : '连接失败',
      subtitle: ok
          ? 'API Key 有效，模型可正常调用。\n返回预览：${res.head ?? ''}'
          : '错误：${res.error}\n\n'
              '若为「401 未授权」，说明该 API Key 无效 / 已过期 / 与所选供应商不匹配，请重新填写。',
      danger: !ok,
      primary: ('知道了', () => Navigator.of(context).pop()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final cfg = widget.cfg;
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
              Expanded(
                child: Text(
                  cfg.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: SiniText.titleMd,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
              ),
              if (cfg.isDefault)
                SiniStatusPill(label: '默认', tone: SiniStatusTone.success),
              if (cfg.isImage)
                SiniStatusPill(label: '图片生成', tone: SiniStatusTone.info),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              SiniStatusPill(label: cfg.providerName, tone: SiniStatusTone.info),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child: Text(
                  cfg.modelId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: SiniText.labelMd, color: p.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Key ${cfg.maskedKey}',
            style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              if (!cfg.isDefault)
                _action(
                  context,
                  icon: Icons.check_circle_outline_rounded,
                  label: '设为默认',
                  onTap: () => AppStateScope.of(context).setDefaultModelConfig(cfg.id),
                ),
              const SizedBox(width: Spacing.md),
              _action(
                context,
                icon: Icons.edit_outlined,
                label: '编辑',
                onTap: () => Navigator.of(context)
                    .pushNamed('/settings/model/edit', arguments: cfg),
              ),
              const SizedBox(width: Spacing.md),
              _action(
                context,
                icon: Icons.delete_outline_rounded,
                label: '删除',
                danger: true,
                onTap: () => _confirmDelete(context, cfg),
              ),
              const SizedBox(width: Spacing.md),
              _action(
                context,
                icon: _testing ? Icons.hourglass_top_rounded : Icons.cable_outlined,
                label: _testing ? '测试中' : '测试连接',
                onTap: _testing ? () {} : () => _testConnection(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final color = danger ? const Color(0xFFB42318) : p.textSecondary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(fontSize: SiniText.labelMd, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ModelConfig cfg) async {
    await showSiniSheet<void>(
      context: context,
      title: '删除模型配置？',
      subtitle: '「${cfg.name}」及其 API Key 将从本机移除。',
      danger: true,
      primary: ('删除', () {
        Navigator.of(context).pop();
        AppStateScope.of(context).deleteModelConfig(cfg.id);
      }),
      secondary: ('取消', () => Navigator.of(context).pop()),
    );
  }
}
