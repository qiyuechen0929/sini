import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_status_pill.dart';
import '../../../theme.dart';
import '../../../app_state.dart';

class VideoCallPage extends StatefulWidget {
  const VideoCallPage({super.key});

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds += 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _duration {
    final m = (_seconds / 60).floor().toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final persona = AppStateScope.of(context).activePersona;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // 数字人画面占位（实际接 LiveKit 流）
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0xFF1A2A3A), Color(0xFF050505)],
                  radius: 1.2,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFFE7D9D1),
                            const Color(0xFFB7C4D8),
                            if (persona != null)
                              Color.fromARGB(
                                  255,
                                  persona.gradientSeed[3],
                                  persona.gradientSeed[4],
                                  persona.gradientSeed[5])
                            else const Color(0xFFB7C4D8),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 60,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        persona?.name.characters.first ?? '?',
                        style: const TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),
                    Text(persona?.name ?? 'AI',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const SizedBox(height: Spacing.xs),
                    Text(_duration,
                        style: TextStyle(
                            fontSize: SiniText.bodyMd,
                            color: Colors.white.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            ),
          ),

          // 顶部 AI 标识 + 副标题
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Row(
                  children: [
                    SiniStatusPill(
                      label: 'AI 数字人格',
                      tone: SiniStatusTone.info,
                      icon: Icons.auto_awesome,
                    ),
                    const Spacer(),
                    Container(
                      width: 96,
                      height: 128,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(Radii.lg),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.person_rounded, color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 字幕
          Positioned(
            left: 0,
            right: 0,
            bottom: 140,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm + 2),
                margin: const EdgeInsets.symmetric(horizontal: Spacing.xxl),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  '"嗯…你刚才说的我记住了。"',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: SiniText.bodyMd,
                      color: Colors.white.withValues(alpha: 0.95),
                      height: 1.4),
                ),
              ),
            ),
          ),

          // 控制条
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _circle(Icons.mic_off_rounded, Colors.white24),
                    _circle(Icons.videocam_off_rounded, Colors.white24),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFB42318),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                    _circle(Icons.volume_up_rounded, Colors.white24),
                    _circle(Icons.more_horiz_rounded, Colors.white24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(IconData icon, Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}
