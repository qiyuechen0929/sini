import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../../theme.dart';

/// 统一输入框：圆角 12、聚焦品牌绿描边、行高 1.4
class SiniTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? label;
  final int minLines;
  final int maxLines;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool obscureText;
  final Widget? suffixIcon;
  final void Function(String)? onChanged;
  final TextInputType? keyboardType;

  const SiniTextField({
    super.key,
    this.controller,
    this.hintText,
    this.label,
    this.minLines = 1,
    this.maxLines = 1,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
    this.focusNode,
    this.obscureText = false,
    this.suffixIcon,
    this.onChanged,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: Spacing.xs, bottom: Spacing.xs),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: SiniText.labelMd,
                fontWeight: FontWeight.w500,
                color: p.textSecondary,
              ),
            ),
          ),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          minLines: minLines,
          maxLines: maxLines,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: TextStyle(
            fontSize: SiniText.bodyMd,
            color: p.textPrimary,
            height: 1.4,
          ),
          cursorColor: p.brand,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.md + 2,
              vertical: Spacing.md,
            ),
            filled: true,
            fillColor: p.itemHover,
            hintText: hintText,
            hintStyle: TextStyle(
              color: p.textTertiary,
              fontSize: SiniText.bodyMd,
            ),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
              borderSide: BorderSide(color: p.brand, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
