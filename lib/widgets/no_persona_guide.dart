import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/design/tokens.dart';
import '../core/widgets/sini_button.dart';
import '../theme.dart';

/// 还没有任何数字人格时的主界面。
/// - 完整引导（首次启动）：图标 + 标题 + 三段说明 + 创建 / 导入 / 跳过
/// - 精简卡片（用户点过「先跳过」后）：小图标 + 一句话 + 创建 / 导入 + 重新查看指引
/// 不放输入框——没有聊天对象时给一个空输入框只会让人不知所措。
class NoPersonaGuide extends StatelessWidget {
  /// true = 精简版（已跳过引导）
  final bool compact;
  const NoPersonaGuide({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return compact ? const _CompactGuide() : const _FullGuide();
  }
}

class _FullGuide extends StatelessWidget {
  const _FullGuide();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 图标占位
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: p.itemHover,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: p.border, width: 1),
                  ),
                  child: Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 34,
                    color: p.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.xl),
              Text(
                '还没有数字人格',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                '创建一个人格，导入你们的聊天记录，\n让 TA 用你熟悉的方式继续和你说话。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: p.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: Spacing.xxl),
              _step(p, 1, '填写 TA 的基本信息与性格'),
              const SizedBox(height: Spacing.md),
              _step(p, 2, '导入聊天记录，让 AI 学会说话方式'),              const SizedBox(height: Spacing.md),
              _step(p, 3, '开始对话，TA 会越来越像那个人'),
              const SizedBox(height: Spacing.xxl),
              SiniButton(
                label: '创建数字人格',
                leadingIcon: Icons.person_add_alt_1_rounded,
                onTap: () => Navigator.of(context).pushNamed('/persona/new'),
                style: SiniButtonStyle.primary,
                expand: true,
                height: 48,
              ),
              const SizedBox(height: Spacing.sm),
              SiniButton(
                label: '我有聊天记录，直接克隆 TA',
                leadingIcon: Icons.content_copy_rounded,
                onTap: () => Navigator.of(context)
                    .pushNamed('/persona/import', arguments: 'create'),
                style: SiniButtonStyle.ghost,
                expand: true,
                height: 44,
              ),
              const SizedBox(height: Spacing.sm),
              // 跳过：直接进主界面（兜底建一个「默认助手」当聊天对象）
              Center(
                child: TextButton(
                  onPressed: () => AppStateScope.of(context).skipGuide(),
                  style: TextButton.styleFrom(
                    foregroundColor: p.textTertiary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '先跳过，直接进主界面',
                        style: TextStyle(fontSize: 13, color: p.textTertiary),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14, color: p.textTertiary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(AppPalette p, int index, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.itemHover,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: p.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                color: p.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 已跳过引导后的精简版：一张居中小卡片，重复提醒但不啰嗦
class _CompactGuide extends StatelessWidget {
  const _CompactGuide();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              color: p.itemHover.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(Radii.xl),
              border: Border.all(color: p.border, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: p.border, width: 1),
                    ),
                    child: Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 24,
                      color: p.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                Text(
                  '还没有数字人格',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  '创建或导入一个人格后，就可以在这里和 TA 聊天。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: p.textSecondary,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: Spacing.xl),
                SiniButton(
                  label: '创建数字人格',
                  leadingIcon: Icons.person_add_alt_1_rounded,
                  onTap: () => Navigator.of(context).pushNamed('/persona/new'),
                  style: SiniButtonStyle.primary,
                  expand: true,
                  height: 44,
                ),
                const SizedBox(height: Spacing.sm),
                SiniButton(
                  label: '克隆 TA',
                  leadingIcon: Icons.content_copy_rounded,
                  onTap: () => Navigator.of(context)
                      .pushNamed('/persona/import', arguments: 'create'),
                  style: SiniButtonStyle.ghost,
                  expand: true,
                  height: 42,
                ),
                const SizedBox(height: Spacing.xs),
                Center(
                  child: TextButton(
                    onPressed: () => AppStateScope.of(context).setGuideSkipped(false),
                    style: TextButton.styleFrom(
                      foregroundColor: p.textTertiary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                    child: Text(
                      '查看创建指引',
                      style: TextStyle(fontSize: 12.5, color: p.textTertiary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
