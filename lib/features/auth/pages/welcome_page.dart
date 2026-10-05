import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_sheet.dart';
import '../../../theme.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: p.mainBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.xxl, Spacing.xxxl, Spacing.xxl, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: p.textPrimary,
                  borderRadius: BorderRadius.circular(Radii.lg + 4),
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 28, color: Colors.white),
              ),
              const Spacer(),
              Text(
                '似你',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                  letterSpacing: -1,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                '把你在乎的人，变成可以一直对话的数字人格。',
                style: TextStyle(
                  fontSize: SiniText.bodyLg,
                  color: p.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: Spacing.xxl),
              _featureRow(p, Icons.history_edu_outlined, '导入聊天记录', '自动提炼语言风格和习惯'),
              const SizedBox(height: Spacing.md),
              _featureRow(p, Icons.psychology_outlined, '长期记忆', '聊得越久，越懂你们的关系'),
              const SizedBox(height: Spacing.md),
              _featureRow(p, Icons.graphic_eq_rounded, '声音 · 数字人', '授权后可还原声音和形象'),
              const Spacer(flex: 2),
              SiniButton(
                label: '开始使用',
                onTap: () => Navigator.of(context).pushReplacementNamed('/'),
                style: SiniButtonStyle.primary,
                expand: true,
                height: 52,
              ),
              const SizedBox(height: Spacing.sm),
              Center(
                child: Text(
                  '无需账号 · 数据保存在本机',
                  style: TextStyle(fontSize: SiniText.labelMd, color: p.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureRow(AppPalette p, IconData icon, String title, String sub) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: p.itemHover,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Icon(icon, size: 20, color: p.textPrimary),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: SiniText.bodyMd,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary)),
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(fontSize: SiniText.labelMd, color: p.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
