import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Gradient;

import 'package:flutter/material.dart';

/// 图片生成中的占位卡片（ChatGPT 风格但更玩闹）：
/// - 深色画布上游动的极光渐变 + 环绕粒子 + 扫光
/// - 提示词打字机展示 + 轮播的「正在做什么」状态文案 + 计时
/// - 可玩性：点一下画布，粒子会在点击处爆开，同时整套配色换一组
class ImageGenCard extends StatefulWidget {
  final String prompt;
  const ImageGenCard({super.key, required this.prompt});

  @override
  State<ImageGenCard> createState() => _ImageGenCardState();
}

class _ImageGenCardState extends State<ImageGenCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 7))
        ..repeat();

  /// 状态轮播
  static const _phases = [
    '正在构思构图…',
    '正在铺底色…',
    '正在晕染光影…',
    '正在刻画细节…',
    '最后调一调氛围…',
    '马上就好，别催…',
  ];
  Timer? _phaseTimer;
  int _phase = 0;
  DateTime _start = DateTime.now();
  Timer? _tickTimer;
  String _elapsed = '0.0s';

  /// 提示词打字机
  Timer? _typeTimer;
  int _typedChars = 0;

  /// 配色方案（点击换组）
  int _palette = 0;
  static const _palettes = [
    [Color(0xFF6C5CE7), Color(0xFF00CEC9), Color(0xFFFD79A8)],
    [Color(0xFF0984E3), Color(0xFF74B9FF), Color(0xFFA29BFE)],
    [Color(0xFFE17055), Color(0xFFFDCB6E), Color(0xFFD63031)],
    [Color(0xFF00B894), Color(0xFF55EFC4), Color(0xFF00CEC9)],
    [Color(0xFFE84393), Color(0xFFFF7675), Color(0xFFFAB1A0)],
  ];

  /// 点击爆开的粒子（可玩性核心）：出生点 + 方向，寿命 0.9s
  final _bursts = <_Burst>[];

  @override
  void initState() {
    super.initState();
    _phaseTimer = Timer.periodic(const Duration(milliseconds: 2300), (_) {
      if (mounted) setState(() => _phase = (_phase + 1) % _phases.length);
    });
    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final d = DateTime.now().difference(_start);
      setState(() => _elapsed =
          '${d.inSeconds}.${(d.inMilliseconds % 1000) ~/ 100}s');
    });
    _typeTimer = Timer.periodic(const Duration(milliseconds: 34), (_) {
      if (!mounted) return;
      if (_typedChars < widget.prompt.length) {
        setState(() => _typedChars++);
      } else {
        _typeTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _phaseTimer?.cancel();
    _tickTimer?.cancel();
    _typeTimer?.cancel();
    super.dispose();
  }

  void _burstAt(Offset local) {
    final rnd = math.Random();
    final colors = _palettes[_palette % _palettes.length];
    for (int i = 0; i < 14; i++) {
      final angle = rnd.nextDouble() * math.pi * 2;
      _bursts.add(_Burst(
        origin: local,
        dir: Offset(math.cos(angle), math.sin(angle)),
        speed: 40 + rnd.nextDouble() * 130,
        color: colors[i % colors.length],
        born: DateTime.now(),
        size: 1.6 + rnd.nextDouble() * 2.6,
      ));
    }
    // 清掉超过 1s 的旧粒子
    _bursts.removeWhere((b) =>
        DateTime.now().difference(b.born).inMilliseconds > 1000);
    setState(() => _palette = (_palette + 1) % _palettes.length);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _palettes[_palette % _palettes.length];
    final typed = widget.prompt.isEmpty
        ? '一张属于你们的图…'
        : widget.prompt.substring(0, _typedChars.clamp(0, widget.prompt.length));
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: GestureDetector(
        onTapUp: (d) => _burstAt(d.localPosition),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => CustomPaint(
            painter: _AuroraPainter(
              t: _ctrl.value,
              colors: colors,
              bursts: _bursts,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              constraints: const BoxConstraints(minHeight: 210),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶行：状态 + 计时
                  Row(
                    children: [
                      _pulseDot(colors[1], _ctrl.value),
                      const SizedBox(width: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        child: Text(
                          _phases[_phase],
                          key: ValueKey(_phase),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .2,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(_elapsed,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .55),
                            fontSize: 11,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          )),
                    ],
                  ),
                  const Spacer(),
                  // 提示词打字机
                  Text(
                    typed,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .82),
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 底部不确定进度条：一道流光
                  LayoutBuilder(builder: (context, c) {
                    final w = c.maxWidth;
                    final head =
                        ((_ctrl.value * 1.6) % 1.0) * (w + 80) - 80;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        height: 4,
                        color: Colors.white.withValues(alpha: .12),
                        child: Stack(children: [
                          Positioned(
                            left: head,
                            top: 0,
                            bottom: 0,
                            width: 80,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [
                                  colors[1].withValues(alpha: 0),
                                  colors[1],
                                  colors[2].withValues(alpha: 0),
                                ]),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  Text(
                    '点一下画布可以换配色 ✦',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .38),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pulseDot(Color color, double t) {
    final s = 7.0 + 3.0 * math.sin(t * math.pi * 2);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .7), blurRadius: s),
        ],
      ),
    );
  }
}

class _Burst {
  final Offset origin;
  final Offset dir;
  final double speed;
  final Color color;
  final DateTime born;
  final double size;
  _Burst({
    required this.origin,
    required this.dir,
    required this.speed,
    required this.color,
    required this.born,
    required this.size,
  });
}

/// 极光画布：几团径向渐变按李萨如轨迹游动 + 环绕粒子 + 点击爆开的火花
class _AuroraPainter extends CustomPainter {
  final double t; // 0..1 循环
  final List<Color> colors;
  final List<_Burst> bursts;
  _AuroraPainter({
    required this.t,
    required this.colors,
    required this.bursts,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // 底色
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0B0E1A));

    // 极光团（加色混合，李萨如轨迹，两圈周期错开避免循环跳变）
    final tt = t * math.pi * 2;
    final blobs = [
      (0.28, 0.34, 0.85, colors[0], tt, 1.0),
      (0.72, 0.30, 0.75, colors[1], tt * 2 + 1.3, 1.4),
      (0.50, 0.78, 0.90, colors[2], tt * 3 + 2.6, 0.8),
    ];
    final paint = Paint()..blendMode = BlendMode.plus;
    for (final (bx, by, br, c, phase, speed) in blobs) {
      final x = size.width * (bx + 0.10 * math.sin(phase) * speed);
      final y = size.height * (by + 0.10 * math.cos(phase * 0.8));
      final radius = size.width * br * 0.42;
      paint.shader = ui.Gradient.radial(
        Offset(x, y),
        radius,
        [c.withValues(alpha: .55), c.withValues(alpha: 0)],
      );
      canvas.drawRect(rect, paint);
    }

    // 环绕粒子：24 颗，各自轨道 + 相位
    final dot = Paint();
    for (int i = 0; i < 24; i++) {
      final p = i / 24 * math.pi * 2;
      final rx = size.width * (0.38 + 0.08 * math.sin(i * 2.1));
      final ry = size.height * (0.34 + 0.07 * math.cos(i * 1.7));
      final x = size.width / 2 + rx * math.cos(p + tt * (0.5 + 0.1 * (i % 3)));
      final y = size.height / 2 + ry * math.sin(p + tt * (0.5 + 0.1 * (i % 3)));
      final c = colors[i % colors.length];
      final alpha = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(p * 3 + tt * 2));
      dot.color = c.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), 1.4 + (i % 3) * 0.7, dot);
      dot.color = c.withValues(alpha: alpha * 0.25);
      canvas.drawCircle(Offset(x, y), 3.4 + (i % 3) * 0.7, dot);
    }

    // 点击爆开的火花
    final now = DateTime.now();
    for (final b in bursts) {
      final age = now.difference(b.born).inMilliseconds / 1000.0;
      if (age > 1) continue;
      final eased = 1 - math.pow(1 - age, 2).toDouble();
      final pos = b.origin + b.dir * b.speed * eased;
      final alpha = (1 - age).toDouble();
      dot.color = b.color.withValues(alpha: alpha);
      canvas.drawCircle(pos, b.size * (1 - age * 0.5), dot);
      dot.color = b.color.withValues(alpha: alpha * 0.3);
      canvas.drawCircle(pos, b.size * 2.2 * (1 - age * 0.4), dot);
    }

    // 顶部高光扫过
    final sweepX = (t * 1.4 % 1.0) * (size.width + 160) - 160;
    paint.blendMode = BlendMode.plus;
    paint.shader = ui.Gradient.linear(
      Offset(sweepX, 0),
      Offset(sweepX + 160, size.height),
      [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: .07),
        Colors.white.withValues(alpha: 0),
      ],
    );
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.colors != colors ||
      oldDelegate.bursts != bursts;
}
