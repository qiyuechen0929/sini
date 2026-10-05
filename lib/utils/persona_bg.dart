import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models.dart';

/// 人格专属聊天背景：从头像同源的 gradientSeed 派生柔和氛围底色。
/// 默认可关（设置里「人格专属背景」）。

/// 从 seed 取一对用于背景的颜色（压暗、提灰，保证文字可读）
({Color a, Color b}) personaBgColors(Persona p, {required bool isDark}) {
  final seed = p.gradientSeed.length >= 6
      ? p.gradientSeed
      : const [91, 140, 255, 127, 168, 255];
  Color c(int r, int g, int b) => Color.fromARGB(255, r, g, b);
  final rawA = c(seed[0], seed[1], seed[2]);
  final rawB = c(seed[3], seed[4], seed[5]);
  if (isDark) {
    // 深色：只保留一点色相，压低饱和与亮度，避免抢气泡
    return (
      a: Color.lerp(const Color(0xFF0A0E1A), rawA, 0.18)!,
      b: Color.lerp(const Color(0xFF05070F), rawB, 0.22)!,
    );
  }
  return (
    a: Color.lerp(const Color(0xFFF4F6FA), rawA, 0.14)!,
    b: Color.lerp(const Color(0xFFE8ECF4), rawB, 0.16)!,
  );
}

/// 聊天区背景：底色 + 两团柔光 + 极淡网格，风格接近深夜/清晨的氛围感
class PersonaChatBackground extends StatelessWidget {
  final Persona persona;
  final Widget child;
  const PersonaChatBackground({
    super.key,
    required this.persona,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = personaBgColors(persona, isDark: dark);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF070B14) : const Color(0xFFF5F7FB),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.a,
            Color.lerp(colors.a, dark ? const Color(0xFF070B14) : colors.b, 0.55)!,
            dark ? const Color(0xFF070B14) : colors.b,
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: CustomPaint(
        painter: _PersonaGlowPainter(
          a: colors.a,
          b: colors.b,
          isDark: dark,
          seed: persona.gradientSeed,
        ),
        child: child,
      ),
    );
  }
}

class _PersonaGlowPainter extends CustomPainter {
  final Color a;
  final Color b;
  final bool isDark;
  final List<int> seed;
  _PersonaGlowPainter({
    required this.a,
    required this.b,
    required this.isDark,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = seed.isEmpty ? 210 : seed[0];
    // 大柔光
    void glow(Offset o, double r, Color c, {double opacity = 1}) {
      final rect = Rect.fromCircle(center: o, radius: r);
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [c.withValues(alpha: 0.55 * opacity), c.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    glow(Offset(size.width * 0.18, size.height * 0.12), size.width * 0.55,
        Color.fromARGB(255, seed.length > 2 ? seed[0] : 91,
            seed.length > 2 ? seed[1] : 140, seed.length > 2 ? seed[2] : 255),
        opacity: isDark ? 0.35 : 0.22);
    glow(Offset(size.width * 0.88, size.height * 0.35), size.width * 0.48,
        Color.fromARGB(255, seed.length > 5 ? seed[3] : 127,
            seed.length > 5 ? seed[4] : 168, seed.length > 5 ? seed[5] : 255),
        opacity: isDark ? 0.28 : 0.18);
    glow(Offset(size.width * 0.5, size.height * 0.95), size.width * 0.7, a,
        opacity: isDark ? 0.2 : 0.12);

    // 几颗漂浮光点（固定伪随机，刷新不闪）
    final rnd = math.Random(h ^ 7);
    for (var i = 0; i < 8; i++) {
      final o = Offset(
        size.width * (0.1 + rnd.nextDouble() * 0.8),
        size.height * (0.15 + rnd.nextDouble() * 0.7),
      );
      final r = 1.2 + rnd.nextDouble() * 2.4;
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..color = (isDark ? const Color(0xFFB8D0FF) : const Color(0xFF6B8CFF))
              .withValues(alpha: isDark ? 0.22 : 0.18),
      );
    }

    // 极淡网格（只在暗色下隐约可见）
    if (isDark) {
      final grid = Paint()
        ..color = const Color(0xFF7FA8FF).withValues(alpha: 0.035)
        ..strokeWidth = 0.6;
      const step = 48.0;
      for (var x = 0.0; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      }
      for (var y = 0.0; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PersonaGlowPainter old) =>
      old.a != a || old.b != b || old.isDark != isDark;
}
