import 'dart:typed_data' show Uint8List;
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:share_plus/share_plus.dart';

import '../core/design/tokens.dart';
import '../core/widgets/sini_button.dart';
import '../theme.dart';
import '../utils/export_file.dart'
    show downloadBinaryFile, saveAndNotify;
import '../utils/usage_store.dart';

/// 用量小票导出：收银小票样式的 PNG + 打印机吐票动画。
/// [showReceiptExportSheet] 是入口；[UsageReceipt] 是票面本身（导出图就是这个）。

class ReceiptData {
  final String rangeLabel;
  final String dateLabel;
  final int totalTokens;
  final int promptTokens;
  final int completionTokens;
  final int calls;
  final List<({String name, int tokens, int calls})> byPersona;
  final List<({String name, int tokens, int calls})> byModel;
  const ReceiptData({
    required this.rangeLabel,
    required this.dateLabel,
    required this.totalTokens,
    required this.promptTokens,
    required this.completionTokens,
    required this.calls,
    required this.byPersona,
    required this.byModel,
  });
}

/// 入口：弹出「打印中 → 完成」的小票导出面板
Future<void> showReceiptExportSheet(
  BuildContext context,
  AppPalette p,
  ReceiptData data,
) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ReceiptExportSheet(p: p, data: data),
  );
}

class _ReceiptExportSheet extends StatefulWidget {
  final AppPalette p;
  final ReceiptData data;
  const _ReceiptExportSheet({required this.p, required this.data});

  @override
  State<_ReceiptExportSheet> createState() => _ReceiptExportSheetState();
}

class _ReceiptExportSheetState extends State<_ReceiptExportSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..forward();
  bool _done = false;
  Uint8List? _png;
  final _captureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      if (_ctrl.value >= 1 && !_done) {
        setState(() => _done = true);
        // 等成票渲染完一帧再截图，后面保存 / 分享都用这张
        WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final boundary = _captureKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ImageByteFormat.png);
    _png = data?.buffer.asUint8List();
  }

  /// 保存：手机存相册；Web 下载
  Future<void> _saveToGallery() async {
    if (_png == null) return;
    if (kIsWeb) {
      await saveAndNotify(
        context,
        () => downloadBinaryFile('似你_用量小票.png', _png!, 'image/png'),
        webMessage: '小票已开始下载（浏览器没有相册，存哪你说了算）',
      );
      return;
    }
    try {
      final r = await ImageGallerySaver.saveImage(_png!,
          quality: 95, name: 'sini_usage_receipt');
      final ok = r is Map && r['isSuccess'] == true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? '小票已保存到相册 📸' : '保存相册失败，试试用分享另存'),
        duration: const Duration(milliseconds: 2200),
      ));
    } catch (_) {
      if (!mounted) return;
      await saveAndNotify(
        context,
        () => downloadBinaryFile('似你_用量小票.png', _png!, 'image/png'),
      );
    }
  }

  /// 分享到微信 / QQ / 朋友圈等（系统分享面板）
  Future<void> _share() async {
    if (_png == null || !mounted) return;
    try {
      await Share.shareXFiles(
        [XFile.fromData(_png!, name: '似你_用量小票.png', mimeType: 'image/png')],
        text: '我在「似你」和 TA 聊了 ${widget.data.calls} 次，'
            '消耗 ${formatTokens(widget.data.totalTokens)} tokens，小票在此 ↓',
        subject: '似你 · 用量小票',
      );
    } catch (_) {
      if (!mounted) return;
      await saveAndNotify(
        context,
        () => downloadBinaryFile('似你_用量小票.png', _png!, 'image/png'),
        webMessage: '当前环境不支持直接分享，已改为下载',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xxl),
      // 票面高（人格/模型条目多时）会把按钮顶出屏幕，包一层滚动兜底
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: SingleChildScrollView(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 打印机动画区 / 完成后的成票 ──
            if (!_done) ...[
              const SizedBox(height: 6),
              _PrintingAnimation(
                  ctrl: _ctrl, data: widget.data, p: widget.p),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _ctrl.value,
                  minHeight: 6,
                  backgroundColor:
                      widget.p.border.withValues(alpha: .5),
                  valueColor:
                      const AlwaysStoppedAnimation(Color(0xFF10A37F)),
                ),
              ),
              const SizedBox(height: 10),
              Text('正在打印你的用量小票… ${(_ctrl.value * 100).round()}%',
                  style: TextStyle(
                      fontSize: 12.5, color: widget.p.textSecondary)),
            ] else ...[
              // 完成：完整票面（这个就是要导出的图）
              RepaintBoundary(
                key: _captureKey,
                child: UsageReceipt(data: widget.data),
              ),
              const SizedBox(height: Spacing.md),
              Row(children: [
                Expanded(
                  child: SiniButton(
                    label: '保存到相册',
                    leadingIcon: Icons.photo_album_outlined,
                    style: SiniButtonStyle.secondary,
                    onTap: _saveToGallery,
                    height: 46,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: SiniButton(
                    label: '分享',
                    leadingIcon: Icons.share_rounded,
                    onTap: _share,
                    height: 46,
                  ),
                ),
              ]),
              const SizedBox(height: Spacing.xs),
              Text(kIsWeb
                  ? 'Web 端「保存到相册」= 下载到本地；发朋友圈右键存图即可'
                  : '长按图片也可以直接保存或转发',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10.5, color: widget.p.textTertiary)),
            ],
          ],
        ),
        ),
      ),
      ),
    );
  }
}

/// 打印动画：小票从上方槽位缓缓吐出 + 黄色扫描线 + 底部出票口
class _PrintingAnimation extends StatelessWidget {
  final AnimationController ctrl;
  final ReceiptData data;
  final AppPalette p;
  const _PrintingAnimation(
      {required this.ctrl, required this.data, required this.p});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 300,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // 正在吐出的小票（从槽位后面往下伸，只露出越来越长的部分）
          Positioned(
            top: 44,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: (0.15 + 0.85 * ctrl.value).clamp(0.0, 1.0),
                child: Opacity(
                  opacity: 0.96,
                  child: SizedBox(
                    width: 220,
                    child: UsageReceipt(data: data, compact: true),
                  ),
                ),
              ),
            ),
          ),
          // 扫描线（在小票区域上下来回）
          Positioned(
            left: 30,
            right: 30,
            top: 44 + 200 * _beamT(ctrl.value),
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFFFC94D).withValues(alpha: .8),
                      blurRadius: 8),
                ],
                color: const Color(0xFFFFC94D),
              ),
            ),
          ),
          // 四角取景框
          ..._corners(),
          // 出票口
          Positioned(
            bottom: 0,
            child: _PrinterSlot(p: p),
          ),
        ],
      ),
    );
  }

  double _beamT(double v) {
    // 0→1→0 来回扫两遍
    final t = (v * 2) % 1.0;
    return t < 0.5 ? t * 2 : 2 - t * 2;
  }

  List<Widget> _corners() {
    const c = Color(0xFFFFC94D);
    Widget bar(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
            color: c, borderRadius: BorderRadius.circular(2)));
    Widget corner(Alignment a, int quarterTurns) => Align(
          alignment: a,
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: SizedBox(
              width: 22,
              height: 22,
              child: Stack(children: [
                Positioned(top: 0, left: 0, child: bar(22, 3)),
                Positioned(top: 0, left: 0, child: bar(3, 22)),
              ]),
            ),
          ),
        );
    return [
      corner(const Alignment(-1, -1), 0),
      corner(const Alignment(1, -1), 1),
      corner(const Alignment(1, 1), 2),
      corner(const Alignment(-1, 1), 3),
    ];
  }
}

/// 出票口
class _PrinterSlot extends StatelessWidget {
  final AppPalette p;
  const _PrinterSlot({required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 40,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border, width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .08),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Center(
        child: Container(
          width: 110,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// 票面（导出图就是它）
class UsageReceipt extends StatelessWidget {
  final ReceiptData data;
  final bool compact;
  const UsageReceipt({super.key, required this.data, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final ts =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    const mono = 'monospace';
    Widget row(String l, String r, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(l,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: mono,
                        fontSize: 11.5,
                        fontWeight:
                            bold ? FontWeight.w700 : FontWeight.w400,
                        color: const Color(0xFF2A2A33))),
              ),
              const SizedBox(width: 6),
              Text(r,
                  style: TextStyle(
                      fontFamily: mono,
                      fontSize: 11.5,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                      color: const Color(0xFF2A2A33))),
            ],
          ),
        );
    Widget divider() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text('- ' * 26,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                  fontFamily: mono,
                  fontSize: 9,
                  color: const Color(0xFF9A9AA5))),
        );

    return Container(
      color: const Color(0xFFFCFBF7), // 热敏纸白
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Center(
            child: Text('✦ 似你 · 用量小票 ✦',
                style: TextStyle(
                    fontFamily: mono,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF2A2A33))),
          ),
          const SizedBox(height: 3),
          Center(
            child: Text(data.dateLabel,
                style: const TextStyle(
                    fontFamily: mono,
                    fontSize: 10,
                    color: Color(0xFF6F6F7A))),
          ),
          divider(),
          row('总消耗', '${formatTokens(data.totalTokens)} tok', bold: true),
          row('调用次数', '${data.calls} 次'),
          row('输入 / 输出',
              '${formatTokens(data.promptTokens)} / ${formatTokens(data.completionTokens)}'),
          divider(),
          if (data.byPersona.isNotEmpty) ...[
            Center(
              child: Text('── 各人格消耗 ──',
                  style: TextStyle(
                      fontFamily: mono,
                      fontSize: 9.5,
                      color: const Color(0xFF9A9AA5))),
            ),
            const SizedBox(height: 3),
            for (final x in data.byPersona.take(6))
              row(x.name, '${formatTokens(x.tokens)} tok'),
          ],
          if (data.byModel.isNotEmpty) ...[
            Center(
              child: Text('── 各模型消耗 ──',
                  style: TextStyle(
                      fontFamily: mono,
                      fontSize: 9.5,
                      color: const Color(0xFF9A9AA5))),
            ),
            const SizedBox(height: 3),
            for (final x in data.byModel.take(6))
              row(x.name, '${formatTokens(x.tokens)} tok'),
          ],
          if (!compact) ...[
            divider(),
            row('范围', data.rangeLabel),
            row('打印时间', ts),
            const SizedBox(height: 6),
            // 条形码装饰
            Center(
              child: SizedBox(
                height: 26,
                child: CustomPaint(
                  painter: _BarcodePainter(),
                  size: const Size(180, 26),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text('谢谢你陪 TA 聊天 ♡',
                  style: TextStyle(
                      fontFamily: mono,
                      fontSize: 10,
                      color: const Color(0xFF6F6F7A))),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// 假条形码装饰
class _BarcodePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF2A2A33);
    final rnd = List.generate(40, (i) => (i * 7 + i ~/ 3) % 4);
    double x = 0;
    for (int i = 0; i < rnd.length; i++) {
      final w = 1.0 + rnd[i] * 0.9;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      x += w + 1.6;
      if (x > size.width) break;
    }
  }

  @override
  @override
  bool shouldRepaint(covariant _BarcodePainter oldDelegate) => false;
}
