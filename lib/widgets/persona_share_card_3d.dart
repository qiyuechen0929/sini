import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'persona_avatar.dart';

/// 卡片可选配色：第 0 档是 TA 本命色（头像渐变），其余是精选配色，
/// 「随机配色」按钮在这几档里转（精选而不是纯随机，避免撞出脏色）。
const List<({String name, Color c1, Color c2})> kCardPalettes = [
  (name: '本命色', c1: Color(0xFF000000), c2: Color(0xFF000000)), // 占位，运行时用 gradientSeed 替换
  (name: '紫青', c1: Color(0xFF6C5CE7), c2: Color(0xFF00CEC9)),
  (name: '深海', c1: Color(0xFF0984E3), c2: Color(0xFF74B9FF)),
  (name: '森绿', c1: Color(0xFF00B894), c2: Color(0xFF55EFC4)),
  (name: '玫红', c1: Color(0xFFE84393), c2: Color(0xFFFF7675)),
  (name: '暮紫', c1: Color(0xFFA29BFE), c2: Color(0xFF6C5CE7)),
  (name: '金橙', c1: Color(0xFFE17055), c2: Color(0xFFFAB1A0)),
  (name: '夜蓝', c1: Color(0xFF355C7D), c2: Color(0xFFC06C84)),
];

/// 按 paletteIndex 取某张卡的配色；null / 0 = TA 本命色
({Color c1, Color c2}) cardColors(Persona persona, int? paletteIndex) {
  if (paletteIndex == null || paletteIndex <= 0) {
    return (
      c1: Color.fromARGB(255, persona.gradientSeed[0],
          persona.gradientSeed[1], persona.gradientSeed[2]),
      c2: Color.fromARGB(255, persona.gradientSeed[3],
          persona.gradientSeed[4], persona.gradientSeed[5]),
    );
  }
  final p = kCardPalettes[paletteIndex.clamp(1, kCardPalettes.length - 1)];
  return (c1: p.c1, c2: p.c2);
}

/// 3D 旋转的「人格养成卡」：
/// - 正面：头像、名字、关系、性格维度条、养成统计（聊了多少条 / 记忆多少条 / 养了多少天）
/// - 背面：性格摘要、口头禅、一句原话样本、「导入可复活 TA」
/// - 可玩性：左右拖拽自由旋转，松手自动吸附到正/反面；点一下直接翻面；
///   不碰它时卡片自己缓缓摆动，还有一道高光扫过 + 微粒环绕。
class PersonaShareCard3D extends StatefulWidget {
  final Persona persona;
  final int messageCount;
  final int daysKnown;

  /// 配色档位（kCardPalettes 下标；null / 0 = TA 本命色）
  final int? paletteIndex;
  const PersonaShareCard3D({
    super.key,
    required this.persona,
    required this.messageCount,
    required this.daysKnown,
    this.paletteIndex,
  });

  @override
  State<PersonaShareCard3D> createState() => _PersonaShareCard3DState();
}

class _PersonaShareCard3DState extends State<PersonaShareCard3D>
    with TickerProviderStateMixin {
  /// 摆动 / 扫光循环
  late final AnimationController _wobble =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..repeat();

  /// 翻面 / 吸附动画
  late final AnimationController _flip =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  double _angle = 0; // 当前 Y 轴角（弧度）
  double _flipFrom = 0;
  double _flipTo = 0;
  bool _dragging = false;

  @override
  void dispose() {
    _wobble.dispose();
    _flip.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _flipFrom = _angle;
    _flipTo = target;
    _flip.forward(from: 0);
  }

  void _onDragUpdate(double dx) {
    setState(() => _angle += dx * 0.012);
  }

  void _onDragEnd() {
    final pi = math.pi;
    // 吸附到最近的整面（...-π, 0, π, 2π...），保证文字永远正向
    final target = (_angle / pi).roundToDouble() * pi;
    _animateTo(target);
  }

  void _flipOnce() {
    if (_flip.isAnimating) return;
    _animateTo(_angle + math.pi);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_wobble, _flip]),
      builder: (context, _) {
        if (_flip.isAnimating) {
          final k = Curves.easeInOutCubic.transform(_flip.value);
          _angle = _flipFrom + (_flipTo - _flipFrom) * k;
        }
        final wobble =
            _dragging || _flip.isAnimating ? 0.0 : 0.09 * math.sin(_wobble.value * math.pi * 2);
        final drawAngle = _angle + wobble;
        final showBack = math.cos(drawAngle) < 0;

        return GestureDetector(
          onTap: _flipOnce,
          onHorizontalDragStart: (_) {
            _dragging = true;
            _flip.stop();
          },
          onHorizontalDragUpdate: (d) => _onDragUpdate(d.delta.dx),
          onHorizontalDragEnd: (_) {
            _dragging = false;
            _onDragEnd();
          },
          child: AspectRatio(
            aspectRatio: 300 / 430,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0016) // 透视
                ..rotateY(drawAngle),
              child: showBack
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _CardBack(
                        persona: widget.persona,
                        colors: cardColors(widget.persona, widget.paletteIndex),
                      ),
                    )
                  : Stack(
                      children: [
                        _CardFront(
                          persona: widget.persona,
                          messageCount: widget.messageCount,
                          daysKnown: widget.daysKnown,
                          colors:
                              cardColors(widget.persona, widget.paletteIndex),
                        ),
                        // 高光扫过
                        Positioned.fill(
                          child: IgnorePointer(
                            child: _Shine(t: _wobble.value),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// 公开的静态正面卡：分享面板截图（RepaintBoundary）用，不带 3D 手势
class PersonaShareCardFront extends StatelessWidget {
  final Persona persona;
  final int messageCount;
  final int daysKnown;
  final int? paletteIndex;
  const PersonaShareCardFront({
    super.key,
    required this.persona,
    required this.messageCount,
    required this.daysKnown,
    this.paletteIndex,
  });

  @override
  Widget build(BuildContext context) {
    return _CardFront(
      persona: persona,
      messageCount: messageCount,
      daysKnown: daysKnown,
      colors: cardColors(persona, paletteIndex),
    );
  }
}

/// 高光斜扫层
class _Shine extends StatelessWidget {  final double t; // 0..1
  const _Shine({required this.t});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final x = ((t * 1.3) % 1.0) * (c.maxWidth + 180) - 180;
      return Stack(children: [
        Positioned(
          left: x,
          top: -40,
          bottom: -40,
          width: 120,
          child: Transform.rotate(
            angle: 0.35,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00FFFFFF),
                    Color(0x2EFFFFFF),
                    Color(0x00FFFFFF),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

/// 卡片共用容器
class _CardShell extends StatelessWidget {
  final Widget child;
  final List<Color> colors;
  const _CardShell({required this.child, required this.colors});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 14)),
        ],
      ),
      child: child,
    );
  }
}

class _CardFront extends StatelessWidget {
  final Persona persona;
  final int messageCount;
  final int daysKnown;
  final ({Color c1, Color c2}) colors;
  const _CardFront({
    required this.persona,
    required this.messageCount,
    required this.daysKnown,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c1 = colors.c1;
    final deep = Color.lerp(c1, const Color(0xFF101322), 0.55)!;
    return _CardShell(
      colors: [c1.withValues(alpha: .85), deep],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶行：品牌 + 关系
            Row(
              children: [
                Text('似你 · 人格养成卡',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .75),
                        fontSize: 10.5,
                        letterSpacing: 1.2)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    persona.relationship.isEmpty ? '未知关系' : persona.relationship,
                    style: const TextStyle(color: Colors.white, fontSize: 10.5),
                  ),
                ),
              ],
            ),
            const Spacer(),
            // 头像 + 名字
            Center(
              child: PersonaAvatar(persona: persona, size: 84),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(persona.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.3)),
            ),
            if (persona.subtitle.isNotEmpty) ...[
              const SizedBox(height: 3),
              Center(
                child: Text(persona.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .7),
                        fontSize: 12)),
              ),
            ],
            const SizedBox(height: 18),
            // 性格维度（养出来的性格）
            _trait('温柔', persona.warmth),
            const SizedBox(height: 7),
            _trait('理性', persona.rationality),
            const SizedBox(height: 7),
            _trait('主动', persona.initiative),
            const SizedBox(height: 7),
            _trait('幽默', persona.humor),
            const Spacer(),
            // 养成统计
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('$messageCount', '条消息'),
                  _vline(),
                  _stat('${persona.memory.length}', '条记忆'),
                  _vline(),
                  _stat('$daysKnown', '天养成'),                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('点一下翻面 →',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .45),
                      fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trait(String label, double v) {
    final value = v.clamp(0, 100).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .85), fontSize: 11)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 5,
              color: Colors.white.withValues(alpha: .18),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value / 100,
                child: Container(color: Colors.white.withValues(alpha: .92)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text('${value.round()}',
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .8),
                  fontSize: 10.5)),
        ),
      ],
    );
  }

  Widget _stat(String n, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(n,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 1),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: .6), fontSize: 9.5)),
      ],
    );
  }

  Widget _vline() => Container(
        width: 1,
        height: 22,
        color: Colors.white.withValues(alpha: .22),
      );
}

class _CardBack extends StatelessWidget {
  final Persona persona;
  final ({Color c1, Color c2}) colors;
  const _CardBack({required this.persona, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c2 = colors.c2;
    final deep = Color.lerp(c2, const Color(0xFF0B0E1A), 0.62)!;
    final style = persona.style;
    final catchphrases = style?.catchphrases.take(3).toList() ?? const [];
    final sample = (style?.sampleLines.isNotEmpty ?? false)
        ? style!.sampleLines.first
        : null;
    return _CardShell(
      colors: [deep, c2.withValues(alpha: .8)],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('TA 是谁',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .75),
                        fontSize: 10.5,
                        letterSpacing: 1.2)),
                const Spacer(),
                Text('背面',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .4),
                        fontSize: 10)),
              ],
            ),
            const SizedBox(height: 14),
            // 性格摘要
            Expanded(
              child: Text(
                persona.description.trim().isEmpty
                    ? '（TA 的主人还没写 TA 的性格摘要，但 TA 的每一句话都是养出来的。）'
                    : persona.description.trim(),
                maxLines: 7,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    fontSize: 12.5,
                    height: 1.65),
              ),
            ),
            // 口头禅
            if (catchphrases.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: catchphrases
                    .map((c) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(c,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10.5)),
                        ))
                    .toList(),
              ),
            ],
            // 一句原话
            if (sample != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('「$sample」',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .9),
                        fontSize: 12,
                        height: 1.5,
                        fontStyle: FontStyle.italic)),
              ),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '在「似你」导入这张卡的养成数据，TA 就能在你这里醒来。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 11, height: 1.4),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('← 点一下翻回正面',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .45),
                      fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }
}
