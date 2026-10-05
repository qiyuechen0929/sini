import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../../theme.dart';
import 'sini_button.dart';

/// iOS 风底部 Sheet：圆角 20、液态玻璃背景、drag handle。
/// 用法：
/// ```dart
/// final ok = await showSiniSheet<bool>(
///   context: context,
///   title: '重命名对话',
///   child: SiniTextField(...),
///   primary: ('保存', () => Navigator.pop(ctx, true)),
///   secondary: ('取消', () => Navigator.pop(ctx, false)),
/// );
/// ```
Future<T?> showSiniSheet<T>({
  required BuildContext context,
  String? title,
  String? subtitle,
  Widget? child,
  (String, VoidCallback)? primary,
  (String, VoidCallback)? secondary,
  (String, VoidCallback)? tertiary,
  bool dismissible = true,
  /// primary 按钮是否用危险（红色）样式——删除等破坏性操作用
  bool danger = false,
}) {
  final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    elevation: 0,
    isScrollControlled: true,
    isDismissible: dismissible,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xxl)),
    ),
    builder: (sheetCtx) {
      final mq = MediaQuery.of(sheetCtx);
      return Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xxl)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: Glass.sigmaSheet, sigmaY: Glass.sigmaSheet),
            child: Container(
              decoration: BoxDecoration(
                color: (isDark(p) ? const Color(0xFF1F1F1F) : Colors.white)
                    .withValues(alpha: 0.78),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: isDark(p) ? 0.10 : 0.65),
                    width: 1,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // drag handle
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: Spacing.md),
                          decoration: BoxDecoration(
                            color: p.textTertiary.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                        ),
                      ),
                      if (title != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: Spacing.xs, bottom: Spacing.xs),
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: SiniText.titleMd,
                              fontWeight: FontWeight.w600,
                              color: p.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                      if (subtitle != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: Spacing.xs, bottom: Spacing.lg),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: SiniText.bodySm,
                              color: p.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                      if (child != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Spacing.lg),
                          child: child,
                        ),
                      if (primary != null) ...[
                        SiniButton(
                          label: primary.$1,
                          onTap: primary.$2,
                          style: danger ? SiniButtonStyle.danger : SiniButtonStyle.primary,
                          expand: true,
                          height: 48,
                        ),
                        const SizedBox(height: Spacing.sm),
                      ],
                      if (secondary != null) ...[
                        SiniButton(
                          label: secondary.$1,
                          onTap: secondary.$2,
                          style: SiniButtonStyle.secondary,
                          expand: true,
                          height: 48,
                        ),
                      ],
                      if (tertiary != null) ...[
                        const SizedBox(height: Spacing.sm),
                        SiniButton(
                          label: tertiary.$1,
                          onTap: tertiary.$2,
                          style: SiniButtonStyle.ghost,
                          expand: true,
                          height: 44,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

bool isDark(AppPalette p) =>
    p.mainBg.computeLuminance() < 0.5;
