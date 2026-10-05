import 'package:flutter/material.dart';

import '../theme.dart';

/// AI 正在思考时的炫酷指示器（Grok 风格）。
/// 三颗彩色圆点依次脉冲：缩放 + 透明度 + 颜色相位。
class ThinkingIndicator extends StatefulWidget {
  /// 紧凑模式（仅三圆点，用于已输出文本末尾的「续打光标」场景）
  final bool compact;
  final AppPalette p;

  const ThinkingIndicator({super.key, required this.p, this.compact = false});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  // 三颗圆点各自的颜色：橙红（品牌暖色）、紫、亮蓝
  static const _colors = [
    Color(0xFFFF6B35),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 6.0 : 8.0;
    final gap = widget.compact ? 4.0 : 6.0;
    final maxScale = widget.compact ? 1.35 : 1.55;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        final t = _ctrl.value; // 0..1 循环
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (int i = 0; i < 3; i++) _buildDot(i, t, size, gap, maxScale),
          ],
        );
      },
    );
  }

  Widget _buildDot(int i, double t, double size, double gap, double maxScale) {
    // 每颗圆点错开 1/3 个周期
    final phase = (t + i / 3) % 1.0;
    // 三角形脉冲：在 phase ∈ [0, 0.4] 内从 0 升到 1，在 [0.4, 1] 内缓降
    double pulse;
    if (phase < 0.4) {
      // 0 -> 1
      pulse = phase / 0.4;
    } else {
      // 1 -> 0 (缓出)
      final v = (phase - 0.4) / 0.6;
      pulse = 1 - (v * v);
    }
    final scale = 1.0 + (maxScale - 1.0) * pulse;
    final color = Color.lerp(
      _colors[i].withValues(alpha: 0.25),
      _colors[i],
      pulse,
    )!;

    return Padding(
      padding: EdgeInsets.only(right: i < 2 ? gap : 0),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: pulse > 0.6
              ? [
                  BoxShadow(
                    color: _colors[i].withValues(alpha: 0.45 * pulse),
                    blurRadius: 6 * pulse,
                    spreadRadius: 1 * pulse,
                  ),
                ]
              : null,
        ),
        transform: Matrix4.identity()..scale(scale),
      ),
    );
  }
}

/// AI 头像旁边的「正在思考」状态条：
/// 三个彩色脉冲圆点 + 文字「正在思考」+ 头像外圈呼吸光晕。
class ThinkingBubble extends StatefulWidget {
  final AppPalette p;
  const ThinkingBubble({super.key, required this.p});

  @override
  State<ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  static const _brand = Color(0xFFFF6B35);

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 呼吸光晕包裹头像
        AnimatedBuilder(
          animation: _glow,
          builder: (ctx, _) {
            final v = _glow.value;
            return Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _brand.withValues(alpha: 0.35 * v),
                    _brand.withValues(alpha: 0.0),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 6),
        ThinkingIndicator(p: widget.p),
        const SizedBox(width: 8),
        Text(
          '正在思考',
          style: TextStyle(
            fontSize: 12,
            color: widget.p.textTertiary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
