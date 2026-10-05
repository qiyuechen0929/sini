import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'persona_avatar.dart';

/// 空状态：大标题 + 副标题
class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    // of（不是 read）：自己订阅状态，切人格时即使外层没重建也能自己刷新
    final state = AppStateScope.of(context);
    final persona = state.activePersona;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (persona != null) ...[
                PersonaAvatar(persona: persona, size: 56, showSparkle: true),
                const SizedBox(height: 18),
              ],
              Text(
                '今天想和${persona?.name ?? 'AI'}聊点什么？',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '聊得越久，我会越像你熟悉的那个人。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: p.textSecondary, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
