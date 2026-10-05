import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../../theme.dart';

/// 统一按钮：胶囊样式，4 档语义
/// - [primary]   深底白字（主操作）
/// - [secondary] 浅灰底深字（次操作）
/// - [danger]    红色填充（删除）
/// - [ghost]     透明（弹窗里的文字按钮）
class SiniButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final SiniButtonStyle style;
  final IconData? leadingIcon;
  final double height;
  final EdgeInsetsGeometry? padding;
  final bool expand;

  const SiniButton({
    super.key,
    required this.label,
    required this.onTap,
    this.style = SiniButtonStyle.primary,
    this.leadingIcon,
    this.height = 44,
    this.padding,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final Color bg;
    final Color fg;
    switch (style) {
      case SiniButtonStyle.primary:
        bg = p.textPrimary;
        fg = p.inverseOn;
        break;
      case SiniButtonStyle.secondary:
        bg = p.itemHover;
        fg = p.textPrimary;
        break;
      case SiniButtonStyle.danger:
        bg = const Color(0xFFB42318);
        fg = Colors.white;
        break;
      case SiniButtonStyle.ghost:
        bg = Colors.transparent;
        fg = p.textSecondary;
        break;
    }
    final disabled = onTap == null;
    final child = Container(
      height: height,
      alignment: Alignment.center,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: Spacing.xl),
      decoration: BoxDecoration(
        color: disabled
            ? bg.withValues(alpha: 0.4)
            : bg,
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 18, color: fg),
            const SizedBox(width: Spacing.sm),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: SiniText.labelLg + 1,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
    final tappable = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.xl),
        onTap: onTap,
        child: child,
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: tappable) : tappable;
  }
}

enum SiniButtonStyle { primary, secondary, danger, ghost }
