import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// 数字人格头像：用名字首字 + 渐变背景。渐变色由 seed 数组稳定生成，
/// 避免同一个 persona 每次刷新都换色。
class PersonaAvatar extends StatelessWidget {
  final Persona persona;
  final double size;
  final bool showSparkle; // 是否加一个小的"AI"标记，区分真人
  const PersonaAvatar({
    super.key,
    required this.persona,
    this.size = 32,
    this.showSparkle = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final c1 = Color.fromARGB(255, persona.gradientSeed[0], persona.gradientSeed[1], persona.gradientSeed[2]);
    final c2 = Color.fromARGB(255, persona.gradientSeed[3], persona.gradientSeed[4], persona.gradientSeed[5]);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c1, c2],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            persona.name.characters.first,
            style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1A1A),
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (showSparkle)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: BoxDecoration(
                color: p.brand,
                shape: BoxShape.circle,
                border: Border.all(color: p.mainBg, width: 1.5),
              ),
              child: Icon(
                Icons.auto_awesome,
                size: size * 0.22,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

/// 用户头像：纯色圆 + 首字
class UserAvatar extends StatelessWidget {
  final String name;
  final double size;
  const UserAvatar({super.key, required this.name, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: p.brand,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '你' : name.characters.first,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
