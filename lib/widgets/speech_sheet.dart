import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/speech_input.dart';

/// 弹出 ChatGPT 式语音输入面板，返回识别出的文本（取消则返回 null）。
///
/// 交互：
/// - 弹层自动开始录音，实时把识别文字显示在下方
/// - 中央麦克风圆按钮：点击结束并返回文本
/// - 「取消」：丢弃识别内容关闭
Future<String?> showVoiceInputSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    isScrollControlled: false,
    isDismissible: false, // 防误触，用明确的取消/完成
    enableDrag: false,
    useSafeArea: true,
    builder: (_) => const _VoiceSheet(),
  );
}

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet>
    with SingleTickerProviderStateMixin {
  final _stt = SpeechInput();
  late final AnimationController _pulse;
  String _text = '';
  bool _listening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    // 弹层出现后自动开始录音
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!_stt.available) {
      setState(() => _error = '当前平台不支持语音输入，可改用键盘');
      return;
    }
    setState(() {
      _error = null;
      _listening = true;
    });
    await _stt.start(
      onPartial: (t) {
        if (mounted) setState(() => _text = t);
      },
      onFinal: (t) {
        if (mounted && t.trim().isNotEmpty) setState(() => _text = t);
      },
      onError: (m) {
        if (mounted) setState(() => _error = m);
      },
    );
  }

  void _finish() {
    _stt.stop();
    Navigator.of(context).pop(_text.trim().isEmpty ? null : _text.trim());
  }

  void _cancel() {
    _stt.cancel();
    Navigator.of(context).pop(null);
  }

  @override
  void dispose() {
    _stt.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final hasText = _text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                decoration: BoxDecoration(
                  color: p.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: p.border.withValues(alpha: 0.6), width: 0.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error != null
                          ? '语音输入'
                          : (hasText ? '正在聆听…' : '请开始说话'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 脉冲麦克风按钮
                    GestureDetector(
                      onTap: _error != null ? _cancel : _finish,
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) => CustomPaint(
                          size: const Size(96, 96),
                          painter: _PulsePainter(
                            progress: _pulse.value,
                            color: p.textPrimary,
                            active: _listening && _error == null,
                          ),
                          child: SizedBox(
                            width: 96,
                            height: 96,
                            child: Center(
                              child: Icon(
                                _error != null
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                size: 30,
                                color: p.inverseOn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 实时转写 / 错误提示
                    if (_error != null)
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(0xFFB42318),
                          height: 1.5,
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: SingleChildScrollView(
                          child: Text(
                            hasText ? _text : '说点什么，我会转成文字…',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.55,
                              color: hasText ? p.textPrimary : p.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _Btn(
                            label: '取消',
                            p: p,
                            filled: false,
                            onTap: _cancel,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Btn(
                            label: '完成',
                            p: p,
                            filled: true,
                            onTap: _finish,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 中心实心圆 + 外圈扩散脉冲光环。
class _PulsePainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool active;
  _PulsePainter({
    required this.progress,
    required this.color,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final baseR = size.width * 0.30;

    // 实心圆底
    canvas.drawCircle(
      center,
      baseR,
      Paint()..color = color,
    );

    if (!active) return;

    // 两圈错开的扩散光环
    for (int i = 0; i < 2; i++) {
      final t = (progress + i * 0.5) % 1.0;
      final r = baseR + t * baseR * 0.9;
      final opacity = (1.0 - t) * 0.35;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // 声波竖条（模拟音量跳动）
    final bars = 5;
    final barPaint = Paint()..color = color.withValues(alpha: 0.55);
    for (int i = 0; i < bars; i++) {
      final h = (math.sin((progress * 2 * math.pi) + i) + 1) / 2;
      final barH = baseR * (0.25 + h * 0.5);
      final x = center.dx + (i - (bars - 1) / 2) * (baseR * 0.28);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, center.dy + baseR + 10),
            width: 3,
            height: barH,
          ),
          const Radius.circular(2),
        ),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.progress != progress || old.active != active;
}

class _Btn extends StatelessWidget {
  final String label;
  final AppPalette p;
  final bool filled;
  final VoidCallback onTap;
  const _Btn({
    required this.label,
    required this.p,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? p.textPrimary : p.itemHover,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: filled ? p.inverseOn : p.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
