import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 圆角状态徽章：已授权绿 / 未授权灰 / 进行中蓝 / 警告橙
class SiniStatusPill extends StatelessWidget {
  final String label;
  final SiniStatusTone tone;
  final IconData? icon;

  const SiniStatusPill({
    super.key,
    required this.label,
    this.tone = SiniStatusTone.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      SiniStatusTone.success => (const Color(0xFFE7F5EF), const Color(0xFF0D6E54)),
      SiniStatusTone.warning => (const Color(0xFFFFF6E5), const Color(0xFFB25E09)),
      SiniStatusTone.danger  => (const Color(0xFFFEE4E2), const Color(0xFFB42318)),
      SiniStatusTone.info    => (const Color(0xFFE6F0FA), const Color(0xFF1849A9)),
      SiniStatusTone.neutral => (const Color(0xFFEDEDED), const Color(0xFF5D5D5D)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm + 2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: SiniText.labelSm,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

enum SiniStatusTone { success, warning, danger, info, neutral }
