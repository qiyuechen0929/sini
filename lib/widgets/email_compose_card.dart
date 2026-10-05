import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/design/tokens.dart';
import '../core/widgets/sini_button.dart';
import '../theme.dart';

/// 写信明信片：用户让 TA 发邮件时，以明信片形态完成
/// 收件人 → TA 起草（可重新生成）→ 确认 → 二次确认 → 寄出。
/// 三种纸样随机出现：航空明信片 / 牛皮纸 / 樱花粉。
class EmailComposeCard extends StatelessWidget {
  const EmailComposeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final c = state.emailCompose;
    if (c == null) return const SizedBox.shrink();
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);

    return Stack(children: [
      _PostcardPaper(styleSeed: c.styleSeed, child: _StepBody(c: c, p: p)),
      // 取消
      Positioned(
        top: 6,
        right: 6,
        child: GestureDetector(
          onTap: state.cancelEmailCompose,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .28),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
          ),
        ),
      ),
    ]);
  }
}

// ---- 纸样 ----

class _PaperTheme {
  final Color paper;
  final Color ink;
  final Color sub;
  final Color accent;
  final bool airmailBorder;
  const _PaperTheme({
    required this.paper,
    required this.ink,
    required this.sub,
    required this.accent,
    this.airmailBorder = false,
  });
}

const _kraft = _PaperTheme(
    paper: Color(0xFFD9C6A5), ink: Color(0xFF4A3823), sub: Color(0xFF7A6448), accent: Color(0xFF8C5A2B));
const _airmail = _PaperTheme(
    paper: Color(0xFFFCFAF2), ink: Color(0xFF2A2A33), sub: Color(0xFF8A8A96), accent: Color(0xFFB42318), airmailBorder: true);
const _sakura = _PaperTheme(
    paper: Color(0xFFFDEEF0), ink: Color(0xFF5C3340), sub: Color(0xFFB98A96), accent: Color(0xFFE84393));

_PaperTheme _themeOf(int seed) => switch (seed % 3) {
      0 => _airmail,
      1 => _kraft,
      _ => _sakura,
    };

class _PostcardPaper extends StatelessWidget {
  final int styleSeed;
  final Widget child;
  const _PostcardPaper({required this.styleSeed, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = _themeOf(styleSeed);
    return Container(
      decoration: BoxDecoration(
        color: t.paper,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .18),
              blurRadius: 16,
              offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: t.airmailBorder
            ? Container(
                // 航空信封红蓝斜纹边
                decoration: BoxDecoration(
                  border: Border.all(
                      width: 6,
                      color: Colors.transparent),
                ),
                foregroundDecoration: BoxDecoration(
                  border: Border.all(width: 6, color: Colors.transparent),
                ),
                child: CustomPaint(
                  foregroundPainter: _AirmailBorderPainter(),
                  child: child,
                ),
              )
            : child,
      ),
    );
  }
}

/// 航空信封经典红蓝斜纹
class _AirmailBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const band = 6.0;
    final paint = Paint()..style = PaintingStyle.fill;
    // 外圈四条边画斜纹：简化为只画上下两条（左右细边）
    for (final edge in [Edge.top, Edge.bottom]) {
      canvas.save();
      if (edge == Edge.bottom) {
        canvas.translate(0, size.height - band);
      }
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width, band));
      const step = 14.0;
      for (double x = -band; x < size.width + band; x += step) {
        final path = Path()
          ..moveTo(x, band)
          ..lineTo(x + band, 0)
          ..lineTo(x + band * 2, 0)
          ..lineTo(x + band, band)
          ..close();
        paint.color = (x ~/ step).isEven
            ? const Color(0xFFB42318)
            : const Color(0xFF2D5FA8);
        canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
    // 左右两条实线
    paint.color = const Color(0xFF2D5FA8);
    canvas.drawRect(Rect.fromLTWH(0, 0, 2, size.height), paint);
    canvas.drawRect(Rect.fromLTWH(size.width - 2, 0, 2, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _AirmailBorderPainter oldDelegate) => false;
}

enum Edge { top, bottom }

// ---- 步骤内容 ----

class _StepBody extends StatelessWidget {
  final EmailCompose c;
  final AppPalette p;
  const _StepBody({required this.c, required this.p});

  @override
  Widget build(BuildContext context) {
    final t = _themeOf(c.styleSeed);
    final state = AppStateScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部：邮票 + 标题 + 邮戳
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('✦ 似你明信片 ✦',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.ink,
                            letterSpacing: 1)),
                    const SizedBox(height: 2),
                    Text(_stepLabel(c.step),
                        style: TextStyle(fontSize: 10.5, color: t.sub)),
                  ],
                ),
              ),
              _Stamp(theme: t),
              const SizedBox(width: 8),
              _Postmark(theme: t),
            ],
          ),
          const SizedBox(height: 10),
          // 分隔线（邮票下的虚线，像明信片中线）
          _dashes(t),
          const SizedBox(height: 10),

          if (c.sent) ...[
            // 已寄出
            const SizedBox(height: 8),
            Center(
                child: Text('📬',
                    style: TextStyle(fontSize: 40))),
            const SizedBox(height: 8),
            Center(
              child: Text('明信片已寄出',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text('寄往 ${c.to}',
                  style: TextStyle(fontSize: 11.5, color: t.sub)),
            ),
          ] else if (c.step == 1) ...[
            Text('这封明信片寄给谁？',
                style: TextStyle(fontSize: 13, color: t.ink)),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => c.to = v,
              style: TextStyle(fontSize: 13.5, color: t.ink),
              decoration: InputDecoration(
                hintText: '对方的邮箱地址（自己也可以）',
                hintStyle: TextStyle(fontSize: 12, color: t.sub),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .55),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: t.sub.withValues(alpha: .4))),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
            SiniButton(
              label: '下一步 · 让 TA 执笔',
              leadingIcon: Icons.edit_note_rounded,
              onTap: () {
                final v = c.to.trim();
                if (v.isNotEmpty) state.confirmEmailRecipient(v);
              },
              height: 44,
              expand: true,
            ),
          ] else if (c.step == 2) ...[
            if (c.generating) ...[
              const SizedBox(height: 20),
              Center(
                child: Column(children: [
                  const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(height: 10),
                  Text('TA 正在执笔…',
                      style: TextStyle(fontSize: 12.5, color: t.sub)),
                ]),
              ),
              const SizedBox(height: 20),
            ] else ...[
              TextField(
                controller: TextEditingController(text: c.subject),
                onChanged: (v) => c.subject = v,
                style: TextStyle(fontSize: 13.5, color: t.ink),
                decoration: InputDecoration(
                  labelText: '标题',
                  labelStyle: TextStyle(fontSize: 11, color: t.sub),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .55),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: t.sub.withValues(alpha: .4))),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: c.body),
                onChanged: (v) => c.body = v,
                maxLines: 7,
                minLines: 4,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: t.ink,
                    fontStyle: FontStyle.italic),
                decoration: InputDecoration(
                  labelText: '正文',
                  labelStyle: TextStyle(fontSize: 11, color: t.sub),
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .55),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: t.sub.withValues(alpha: .4))),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(c.error!,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFB42318))),
                ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: SiniButton(
                    label: '重新生成',
                    leadingIcon: Icons.refresh_rounded,
                    style: SiniButtonStyle.secondary,
                    onTap: state.generateEmailDraft,
                    height: 42,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: SiniButton(
                    label: '下一步 · 确认',
                    leadingIcon: Icons.mark_email_read_outlined,
                    onTap: state.emailComposeConfirmStep,
                    height: 42,
                  ),
                ),
              ]),
            ],
          ] else ...[
            // step3 确认
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('寄给：${c.to}',
                      style: TextStyle(fontSize: 11.5, color: t.sub)),
                  const SizedBox(height: 4),
                  Text(c.subject,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: t.ink)),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: Text(c.body,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.6,
                              color: t.ink,
                              fontStyle: FontStyle.italic)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SiniButton(
              label: c.sending ? '寄出中…' : '✉️ 确认寄出',
              onTap: c.sending ? null : state.sendEmailNow,
              height: 46,
              expand: true,
            ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(c.error!,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFB42318))),
              ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: state.emailComposeEditStep,
                child: Text('← 返回修改',
                    style: TextStyle(fontSize: 12, color: t.sub)),
              ),
            ),
          ],
          if (!c.sent) ...[
            const SizedBox(height: 4),
            Center(
              child: GestureDetector(
                onTap: state.cancelEmailCompose,
                child: Text('取消写信',
                    style: TextStyle(
                        fontSize: 11,
                        color: t.sub,
                        decoration: TextDecoration.underline)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _stepLabel(int step) => switch (step) {
        1 => 'STEP 1/3 · 填写收件人',
        2 => 'STEP 2/3 · TA 起草内容',
        _ => 'STEP 3/3 · 最后确认',
      };

  Widget _dashes(_PaperTheme t) => Text('· ' * 60,
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: TextStyle(fontSize: 10, color: t.sub.withValues(alpha: .6)));
}

/// 邮票（右上角装饰）
class _Stamp extends StatelessWidget {
  final _PaperTheme theme;
  const _Stamp({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 52,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
            color: theme.accent.withValues(alpha: .5),
            width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('✉',
              style: TextStyle(fontSize: 18, color: theme.accent)),
          const SizedBox(height: 2),
          Text('似你',
              style: TextStyle(
                  fontSize: 7.5,
                  color: theme.sub,
                  letterSpacing: 2)),
        ],
      ),
    );
  }
}

/// 圆形邮戳
class _Postmark extends StatelessWidget {
  final _PaperTheme theme;
  const _Postmark({required this.theme});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Transform.rotate(
      angle: -0.3,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: theme.sub.withValues(alpha: .55), width: 1.4),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('SI NI',
                style: TextStyle(
                    fontSize: 7,
                    letterSpacing: 1,
                    color: theme.sub.withValues(alpha: .8))),
            Text(
                '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 7.5,
                    color: theme.sub.withValues(alpha: .8))),
          ],
        ),
      ),
    );
  }
}
