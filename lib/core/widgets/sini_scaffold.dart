import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../../theme.dart';

/// 二级页面统一骨架：无 elevation AppBar + 主背景色 + 返回箭头。
/// 跟现有 PersonaLabPage / SettingsPage 完全一致的视觉。
class SiniScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// 固定在底部、不随内容滚动的主操作区（内容自己带 padding）。
  /// 用于「保存并创建」这类必须一直能被点到的按钮。
  final Widget? bottomBar;

  const SiniScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomBar,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: p.mainBg,
      appBar: AppBar(
        backgroundColor: p.mainBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          title,
          style: TextStyle(
            fontSize: SiniText.titleMd,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: p.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: actions,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar == null
          ? null
          : Container(
              decoration: BoxDecoration(
                color: p.mainBg,
                border: Border(top: BorderSide(color: p.border, width: 0.5)),
              ),
              child: SafeArea(top: false, child: bottomBar!),
            ),
    );
  }
}

/// 列表 section 标题（settings 页那种 11px 大写小标题）
class SiniSectionLabel extends StatelessWidget {
  final String text;
  const SiniSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, Spacing.sm),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: SiniText.labelXs,
          fontWeight: FontWeight.w600,
          color: p.textTertiary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// 列表项圆角卡片容器（settings 页那种带 icon + 标题 + 副标题 + chevron）
class SiniListTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final Color? iconColor;
  final Color? titleColor;

  const SiniListTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final ic = iconColor ?? (danger ? const Color(0xFFB42318) : p.textSecondary);
    final tc = titleColor ?? (danger ? const Color(0xFFB42318) : p.textPrimary);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        hoverColor: p.itemHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.md,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: ic),
              const SizedBox(width: Spacing.md + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: SiniText.bodySm + 0.5,
                        fontWeight: FontWeight.w500,
                        color: tc,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: SiniText.labelMd, color: p.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: Spacing.sm),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: Spacing.sm),
                Icon(Icons.chevron_right_rounded, size: 18, color: p.textTertiary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
