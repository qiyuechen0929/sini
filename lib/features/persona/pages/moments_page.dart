import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../app_state.dart';
import '../../../theme.dart';
import '../../../utils/moments.dart' show MemoryMoment;

/// 回忆册 · 炫酷翻页书
/// 3D 透视翻页 + 封面呼吸光 + 书页闪烁粒子 + 可编辑删除
class MomentsPage extends StatefulWidget {
  const MomentsPage({super.key});

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  int _page = 0;
  late final PageController _pc;

  @override
  void initState() {
    super.initState();
    _pc = PageController(viewportFraction: 0.9);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final persona = state.activePersona;
    if (persona == null) {
      return SiniScaffold(
        title: '回忆册',
        body: Center(
          child: Text('请先选择一个人物', style: TextStyle(color: p.textTertiary)),
        ),
      );
    }
    final moments = state.momentsOf(persona.id);
    final totalPages = moments.isEmpty ? 1 : moments.length + 1;

    return SiniScaffold(
      title: '回忆册',
      body: Stack(
        children: [
          // 氛围底光
          Positioned.fill(
            child: IgnorePointer(
              child: _BookGlow(p: p),
            ),
          ),
          Column(
            children: [
              _BookHeader(
                p: p,
                name: persona.name,
                count: moments.length,
                page: _page + 1,
                total: totalPages,
              ),
              Expanded(
                child: moments.isEmpty
                    ? _EmptyBook(p: p)
                    : PageView.builder(
                        controller: _pc,
                        itemCount: totalPages,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return _TitlePage(
                              p: p,
                              personaName: persona.name,
                              count: moments.length,
                            );
                          }
                          final m = moments[i - 1];
                          return _StoryPage(
                            key: ValueKey(m.id),
                            moment: m,
                            index: i,
                            p: p,
                            active: _page == i,
                            onEdit: () => _editMoment(m),
                            onDelete: () => _confirmDelete(m),
                          );
                        },
                      ),
              ),
              if (moments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: _page > 0
                            ? () => _pc.previousPage(
                                duration: const Duration(milliseconds: 380),
                                curve: Curves.easeOutBack)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        color: p.textSecondary,
                      ),
                      // 页码点
                      SizedBox(
                        height: 24,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            math.min(totalPages, 12),
                            (i) {
                              final on = i == _page;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: on ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: on ? p.brand : p.borderStrong,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _page < totalPages - 1
                            ? () => _pc.nextPage(
                                duration: const Duration(milliseconds: 380),
                                curve: Curves.easeOutBack)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                        color: p.textSecondary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editMoment(MemoryMoment m) async {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final titleCtl = TextEditingController(text: m.title);
    final detailCtl = TextEditingController(text: m.detail ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('编辑回忆',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.textPrimary)),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtl,
                  maxLines: 2,
                  style: TextStyle(fontSize: 14, color: p.textPrimary),
                  decoration: InputDecoration(
                    labelText: '标题',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: detailCtl,
                  maxLines: 3,
                  style: TextStyle(fontSize: 13.5, color: p.textPrimary),
                  decoration: InputDecoration(
                    labelText: '补充（可选）',
                    hintText: '当时发生了什么…',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('取消', style: TextStyle(color: p.textTertiary)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: p.brand),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok == true && mounted) {
      await AppStateScope.read(context).updateMoment(
        m.id,
        title: titleCtl.text.trim(),
        detail: detailCtl.text.trim().isEmpty ? null : detailCtl.text.trim(),
      );
    }
    titleCtl.dispose();
    detailCtl.dispose();
  }

  Future<void> _confirmDelete(MemoryMoment m) async {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        title: Text('删掉这段回忆？', style: TextStyle(color: p.textPrimary, fontSize: 16)),
        content: Text(m.title, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('再想想', style: TextStyle(color: p.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFB42318))),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await AppStateScope.read(context).deleteMoment(m.id);
    }
  }
}

/* ───────── 炫酷部件 ───────── */

/// 全页氛围光斑
class _BookGlow extends StatefulWidget {
  final AppPalette p;
  const _BookGlow({required this.p});

  @override
  State<_BookGlow> createState() => _BookGlowState();
}

class _BookGlowState extends State<_BookGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        return CustomPaint(
          painter: _GlowPainter(
            a: p.brand.withValues(alpha: p.isDark ? 0.18 : 0.1),
            b: const Color(0xFF7FE3FF).withValues(alpha: p.isDark ? 0.1 : 0.06),
            t: t,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _GlowPainter extends CustomPainter {
  final Color a;
  final Color b;
  final double t;
  _GlowPainter({required this.a, required this.b, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset o, double r, Color c, double o2) {
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [c.withValues(alpha: 0.5 * o2), c.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: o, radius: r)),
      );
    }

    final dx1 = size.width * (0.25 + 0.08 * math.sin(t * math.pi * 2));
    final dy1 = size.height * (0.15 + 0.05 * math.cos(t * math.pi * 2));
    final dx2 = size.width * (0.78 + 0.06 * math.cos(t * math.pi * 1.5));
    final dy2 = size.height * (0.4 + 0.08 * math.sin(t * math.pi * 1.7));
    blob(Offset(dx1, dy1), size.width * 0.5, a, 0.7 + 0.3 * t);
    blob(Offset(dx2, dy2), size.width * 0.45, b, 0.5 + 0.4 * (1 - t));
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) => old.t != t;
}

class _BookHeader extends StatelessWidget {
  final AppPalette p;
  final String name;
  final int count;
  final int page;
  final int total;
  const _BookHeader({
    required this.p,
    required this.name,
    required this.count,
    required this.page,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: p.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.brand.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_stories_rounded, size: 14, color: p.brand),
                const SizedBox(width: 6),
                Text(
                  '$name · $count 页',
                  style: TextStyle(fontSize: 12, color: p.textPrimary),
                ),
              ],
            ),
          ),
          const Spacer(),
          ShaderMask(
            shaderCallback: (r) => LinearGradient(
              colors: [p.brand, const Color(0xFF7FE3FF)],
            ).createShader(r),
            child: Text(
              '$page / $total',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBook extends StatelessWidget {
  final AppPalette p;
  const _EmptyBook({required this.p});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 160,
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [p.surface, p.itemHover, p.surface],
                ),
                border: Border.all(color: p.brand.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: p.brand.withValues(alpha: 0.2),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: p.border)),
                      ),
                    ),
                  ),
                  Expanded(child: Container()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('这本书还空着',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.textPrimary)),
          const SizedBox(height: 8),
          Text(
            '长按消息 →「记入回忆」\n或聊些值得纪念的事，自动写进册子',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: p.textTertiary, height: 1.65),
          ),
        ],
      ),
    );
  }
}

/// 扉页：呼吸光封面
class _TitlePage extends StatefulWidget {
  final AppPalette p;
  final String personaName;
  final int count;
  const _TitlePage({
    required this.p,
    required this.personaName,
    required this.count,
  });

  @override
  State<_TitlePage> createState() => _TitlePageState();
}

class _TitlePageState extends State<_TitlePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final pulse = 0.5 + 0.5 * _c.value;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX((1 - v) * 0.25)
              ..scale(0.9 + 0.1 * v),
            alignment: Alignment.center,
            child: Opacity(opacity: v.clamp(0, 1), child: child),
          ),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.brand.withValues(alpha: 0.35 + 0.2 * pulse)),
              boxShadow: [
                BoxShadow(
                  color: p.brand.withValues(alpha: 0.15 + 0.15 * pulse),
                  blurRadius: 32 + 16 * pulse,
                  spreadRadius: 2,
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  p.isDark ? const Color(0xFF0E1528) : p.surface,
                  p.isDark ? const Color(0xFF151C33) : p.itemHover,
                  p.isDark ? const Color(0xFF0B1020) : p.surface,
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (r) => LinearGradient(
                    colors: [p.brand, const Color(0xFFB8D0FF), p.brand],
                  ).createShader(r),
                  child: Icon(Icons.auto_stories_rounded, size: 48, color: Colors.white),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.personaName,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: p.textPrimary,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '的 回 忆 册',
                  style: TextStyle(
                    fontSize: 14,
                    color: p.brand,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Container(width: 56, height: 1.5, color: p.borderStrong),
                const SizedBox(height: 16),
                Text(
                  '把一起经过的日子\n写成可以翻开的光',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: p.textSecondary,
                    height: 1.8,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Dot(p: p, delay: 0),
                    const SizedBox(width: 8),
                    _Dot(p: p, delay: 400),
                    const SizedBox(width: 8),
                    _Dot(p: p, delay: 800),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  widget.count == 0 ? '空白页' : '${widget.count} 段光阴 · 左右滑动开启',
                  style: TextStyle(fontSize: 12, color: p.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final AppPalette p;
  final int delay;
  const _Dot({required this.p, required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = 0.4 + 0.6 * _c.value;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.p.brand.withValues(alpha: v),
            boxShadow: [
              BoxShadow(
                color: widget.p.brand.withValues(alpha: 0.5 * v),
                blurRadius: 8,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 单页：带 3D 倾斜与闪烁
class _StoryPage extends StatefulWidget {
  final MemoryMoment moment;
  final int index;
  final AppPalette p;
  final bool active;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _StoryPage({
    super.key,
    required this.moment,
    required this.index,
    required this.p,
    required this.active,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<_StoryPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spark = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _spark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final m = widget.moment;
    final seed = m.id.hashCode.abs();
    final hue = 215.0 + ((seed % 50) - 25);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
      child: AnimatedScale(
        scale: widget.active ? 1.0 : 0.92,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: widget.active ? 1 : 0.55,
          duration: const Duration(milliseconds: 240),
          child: GestureDetector(
            onTap: widget.onEdit,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.active
                      ? p.brand.withValues(alpha: 0.4)
                      : p.border,
                ),
                boxShadow: [
                  if (widget.active)
                    BoxShadow(
                      color: p.brand.withValues(alpha: 0.18),
                      blurRadius: 28,
                      spreadRadius: 1,
                    ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    HSLColor.fromAHSL(1, hue, p.isDark ? 0.14 : 0.09, p.isDark ? 0.13 : 0.97)
                        .toColor(),
                    HSLColor.fromAHSL(1, hue + 8, p.isDark ? 0.18 : 0.1, p.isDark ? 0.1 : 0.94)
                        .toColor(),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: p.border)),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      color: p.isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.black.withValues(alpha: 0.02),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.menu_book_rounded, size: 14, color: p.brand),
                        const SizedBox(width: 8),
                        Text(
                          'P.${widget.index}',
                          style: TextStyle(
                            fontSize: 12,
                            color: p.textTertiary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.edit_outlined, size: 16, color: p.textSecondary),
                          onPressed: widget.onEdit,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.delete_outline, size: 16, color: const Color(0xFFB42318)),
                          onPressed: widget.onDelete,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.dateLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: p.textTertiary,
                              fontFamily: 'monospace',
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.title,
                                    style: TextStyle(
                                      fontSize: 17,
                                      height: 1.55,
                                      fontWeight: FontWeight.w700,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                  if (m.detail != null && m.detail!.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      m.detail!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.7,
                                        color: p.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (m.manual ? p.brand : p.textTertiary)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  m.manual ? '✨ 亲手写下' : '🌙 悄悄记下',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: m.manual ? p.brand : p.textTertiary,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (widget.active)
                                AnimatedBuilder(
                                  animation: _spark,
                                  builder: (_, __) {
                                    final s = 0.5 + 0.5 * math.sin(_spark.value * math.pi * 2);
                                    return Icon(
                                      Icons.auto_awesome,
                                      size: 16,
                                      color: p.brand.withValues(alpha: 0.4 + 0.5 * s),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
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
}
