import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_sheet.dart';
import '../../../core/widgets/sini_status_pill.dart';
import '../../../core/widgets/sini_scaffold.dart' show SiniSectionLabel, SiniListTile;
import '../../../theme.dart';

class ConsentPage extends StatelessWidget {
  const ConsentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return SiniScaffold(
      title: '授权与隐私',
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
        children: [
          // AI 标识
          const SiniSectionLabel('AI 标识'),
          Container(
            decoration: BoxDecoration(
              color: p.itemHover,
              borderRadius: BorderRadius.circular(Radii.xl),
            ),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
            child: Column(
              children: [
                SwitchListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  title: Text('始终显示"AI 生成"标识',
                      style: TextStyle(fontSize: SiniText.bodySm, color: p.textPrimary)),
                  subtitle: Text('视频通话、语音、聊天界面',
                      style: TextStyle(fontSize: SiniText.labelMd, color: p.textTertiary)),
                  value: true,
                  onChanged: (_) {},
                  activeThumbColor: p.brand,
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xl),

          // 数据授权
          const SiniSectionLabel('数据授权'),
          Container(
            decoration: BoxDecoration(
              color: p.itemHover,
              borderRadius: BorderRadius.circular(Radii.xl),
            ),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: Spacing.xs),
            child: Column(
              children: [
                SiniListTile(
                  icon: Icons.graphic_eq_rounded,
                  title: '声音克隆授权',
                  subtitle: '已获得 0 项授权',
                  trailing: SiniStatusPill(label: '未授权', tone: SiniStatusTone.neutral),
                  onTap: () => Navigator.of(context).pushNamed('/voice/clone'),
                ),
                _divider(p),
                SiniListTile(
                  icon: Icons.face_retouching_natural_rounded,
                  title: '肖像授权',
                  subtitle: '已获得 0 项授权',
                  trailing: SiniStatusPill(label: '未授权', tone: SiniStatusTone.neutral),
                  onTap: () {},
                ),
                _divider(p),
                SiniListTile(
                  icon: Icons.history_edu_outlined,
                  title: '聊天记录训练授权',
                  subtitle: '是否允许用你的聊天记录优化模型',
                  trailing: SiniStatusPill(label: '已关闭', tone: SiniStatusTone.success),
                  onTap: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xl),

          // 数据操作
          const SiniSectionLabel('数据操作'),
          Container(
            decoration: BoxDecoration(
              color: p.itemHover,
              borderRadius: BorderRadius.circular(Radii.xl),
            ),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: Spacing.xs),
            child: Column(
              children: [
                SiniListTile(
                  icon: Icons.download_outlined,
                  title: '导出我的所有数据',
                  subtitle: '对话、Persona、Memory、授权记录',
                  onTap: () {},
                ),
                _divider(p),
                SiniListTile(
                  icon: Icons.delete_outline_rounded,
                  title: '一键彻底删除',
                  subtitle: '所有对话、Persona、克隆样本',
                  danger: true,
                  onTap: () => _confirmDeleteAll(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xxxl),
          Center(
            child: Text('似你 · v0.1.0',
                style: TextStyle(fontSize: SiniText.labelMd, color: p.textTertiary)),
          ),
        ],
      ),
    );
  }

  Widget _divider(AppPalette p) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: Spacing.xxxl),
      color: p.border,
    );
  }

  void _confirmDeleteAll(BuildContext context) {
    showSiniSheet(
      context: context,
      title: '彻底删除所有数据？',
      subtitle: '此操作不可撤销。所有对话、Persona、记忆、声音样本、授权记录都将被永久删除。',
      primary: ('我已知晓风险，删除', () => Navigator.of(context).pop()),
      secondary: ('取消', () => Navigator.of(context).pop()),
    );
  }
}
