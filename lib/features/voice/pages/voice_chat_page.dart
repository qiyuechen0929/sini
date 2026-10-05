/// 语音通话页：像打电话一样跟数字人格说话。
///
/// 关键点（用户明确要求）：
///  - **和文字聊天共用同一条对话、同一套记忆、同一个性格** —— 通话里说的话
///    会出现在聊天记录里，人格设定 / 长期记忆 / 早期摘要全部复用
///    （见 `AppState.callTurn`）。
///  - **TA 可能先开口**：接通后由模型根据上下文、记忆、性格自己判断要不要先说话
///    （见 `AppState.callOpeningLine`）。
///  - **声音就是创建人格时选的那个**：预设音色或克隆声音，走 `VoiceEngine`。
///
/// 交互是「免按键」：不用按住按钮，说完自动断句、自动识别、自动回复。
/// 说话时可以随时插话打断 TA（见 `CallEngine` 的打断逻辑）。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_status_pill.dart';
import '../../../app_state.dart';
import '../../../models.dart';
import '../../../theme.dart';
import '../../../widgets/persona_avatar.dart';
import '../call/call_engine.dart';
import '../call/mic_capture.dart';

class VoiceChatPage extends StatefulWidget {
  const VoiceChatPage({super.key});

  @override
  State<VoiceChatPage> createState() => _VoiceChatPageState();
}

class _VoiceChatPageState extends State<VoiceChatPage> {
  CallEngine? _engine;
  AppState? _state;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;
  final _textCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  void _boot() {
    if (!mounted) return;
    final state = AppStateScope.of(context);
    _state = state;
    // 没有人格 / 没有模型：不接通，直接说清楚缺什么
    if (state.activePersona == null) return;
    if (state.defaultModelConfig == null) return;
    if (!MicCapture.available) return;

    final engine = CallEngine(state);
    setState(() => _engine = engine);
    engine.start();
    _startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt!));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _textCtl.dispose();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = _state ?? AppStateScope.of(context);
    final engine = _engine;

    return SiniScaffold(
      title: '语音通话',
      actions: [
        if (engine != null)
          ListenableBuilder(
            listenable: engine,
            builder: (_, __) => Padding(
              padding: const EdgeInsets.only(right: Spacing.md),
              child: SiniStatusPill(
                label: _fmtDuration(_elapsed),
                tone: engine.connected
                    ? SiniStatusTone.success
                    : SiniStatusTone.neutral,
                icon: Icons.graphic_eq_rounded,
              ),
            ),
          ),
      ],
      body: state.activePersona == null
          ? _guard(p, '还没有选中的人格', '先去聊天页选一个人格，或者创建一个新的人格，再打给他。')
          : state.defaultModelConfig == null
              ? _guard(p, '还没有可用的模型',
                  '语音通话要靠模型来「想」和「说」。请到「设置 → 模型管理」添加一个模型并设为默认。')
              : !MicCapture.available
                  ? _guard(p, '当前环境打不开麦克风',
                      '语音通话需要浏览器支持麦克风采集（Chrome / Edge）。也请确认不是 http 访问导致的权限限制。')
                  : engine == null
                      ? Center(
                          child: Text('正在接通…',
                              style: TextStyle(fontSize: 14, color: p.textTertiary)))
                      : ListenableBuilder(
                          listenable: engine,
                          builder: (_, __) => _callBody(p, state, engine),
                        ),
    );
  }

  Widget _guard(AppPalette p, String title, String desc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_off_rounded, size: 40, color: p.textTertiary),
            const SizedBox(height: Spacing.lg),
            Text(title,
                style: TextStyle(
                    fontSize: SiniText.titleMd,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary)),
            const SizedBox(height: Spacing.sm),
            Text(desc,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: SiniText.bodyMd, color: p.textSecondary, height: 1.6)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── 通话中 ───────────────────────────

  Widget _callBody(AppPalette p, AppState state, CallEngine engine) {
    final persona = state.activePersona!;
    final speaking = engine.phase == CallPhase.speaking;
    final listening = engine.phase == CallPhase.listening;

    return Column(
      children: [
        const SizedBox(height: Spacing.lg),
        // 头像 + 呼吸圈
        _AvatarStage(
          persona: persona,
          active: speaking || listening,
          speaking: speaking,
        ),
        const SizedBox(height: Spacing.md),
        Text(persona.name,
            style: TextStyle(
                fontSize: SiniText.titleLg,
                fontWeight: FontWeight.w600,
                color: p.textPrimary)),
        const SizedBox(height: 6),
        Text(
          engine.status,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: p.textSecondary),
        ),
        const SizedBox(height: Spacing.lg),
        // 真实电平波形：听你说时是麦克风响度，TA 说话时是合成音频的包络
        _Waveform(
          level: speaking ? engine.aiLevel : engine.userLevel,
          active: speaking || listening,
          speaking: speaking,
          color: speaking ? p.textPrimary : p.brand,
        ),
        const SizedBox(height: Spacing.md),
        if (engine.openedByPersona && engine.lines.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Text('TA 先开的口',
                style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
          ),
        // 大字幕：此刻正在发生的那一句话（用户边说边出字 / TA 边想边吐字）
        _FloatingCaption(engine: engine),
        // 说完的话落进历史列表
        Expanded(child: _Transcript(engine: engine)),
        // 控制区
        _Controls(
          engine: engine,
          onHangup: () async {
            await engine.hangup();
            if (mounted) Navigator.of(context).maybePop();
          },
          onType: () => _openTypeSheet(engine),
        ),
        const SizedBox(height: Spacing.xl),
      ],
    );
  }

  void _openTypeSheet(CallEngine engine) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    _textCtl.clear();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.mainBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.lg, Spacing.lg, MediaQuery.of(ctx).viewInsets.bottom + Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('打字说',
                style: TextStyle(
                    fontSize: SiniText.titleMd,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary)),
            const SizedBox(height: 6),
            Text('这句话会进同一条对话、同一套记忆，跟说话完全一样。',
                style: TextStyle(fontSize: 12.5, color: p.textTertiary)),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _textCtl,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              style: TextStyle(fontSize: 14, color: p.textPrimary),
              decoration: InputDecoration(
                hintText: '想说什么…',
                filled: true,
                fillColor: p.itemHover,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  borderSide: BorderSide(color: p.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  borderSide: BorderSide(color: p.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  borderSide: BorderSide(color: p.brand),
                ),
              ),
              onSubmitted: (_) => _sendTyped(ctx, engine),
            ),
            const SizedBox(height: Spacing.md),
            SizedBox(
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.textPrimary,
                  foregroundColor: p.mainBg,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.pill)),
                ),
                onPressed: () => _sendTyped(ctx, engine),
                child: const Text('说给他听'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendTyped(BuildContext ctx, CallEngine engine) {
    final t = _textCtl.text.trim();
    if (t.isEmpty) return;
    _textCtl.clear();
    Navigator.of(ctx).pop();
    engine.sendText(t);
  }

  static String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ─────────────────────────── 头像 + 呼吸圈 ───────────────────────────

class _AvatarStage extends StatefulWidget {
  const _AvatarStage({
    required this.persona,
    required this.active,
    required this.speaking,
  });

  final Persona persona;
  final bool active;
  final bool speaking;

  @override
  State<_AvatarStage> createState() => _AvatarStageState();
}

class _AvatarStageState extends State<_AvatarStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return SizedBox(
      width: 176,
      height: 176,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final scale = widget.speaking ? 1 + t * 0.06 : 1 + t * 0.02;
          return Stack(
            alignment: Alignment.center,
            children: [
              // 外圈光晕：说话时更明显
              Container(
                width: 176 * scale,
                height: 176 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.brand.withValues(alpha: widget.speaking ? 0.10 + t * 0.10 : 0.05),
                ),
              ),
              Container(
                width: 124,
                height: 124,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.mainBg,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: PersonaAvatar(
                  persona: widget.persona,
                  size: 100,
                  showSparkle: false,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────── 波形 ───────────────────────────

class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.level,
    required this.active,
    required this.speaking,
    required this.color,
  });

  final double level;
  final bool active;
  final bool speaking;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const bars = 28;
    return SizedBox(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(bars, (i) {
          // 中间高两边低的包络，看起来更像人声
          final shape = 0.35 + 0.65 * math.sin((i + 0.5) / bars * math.pi);
          final v = active ? (level * shape).clamp(0.0, 1.0) : 0.0;
          final h = 4 + v * 34;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: active
                    ? color.withValues(alpha: speaking ? 0.85 : 0.7)
                    : color.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────── 大字幕（浮动文字）───────────────────────────

/// 头像下方那块大字幕：只显示「此刻正在发生的那句话」。
///
/// 用户说话时是还没说完的实时识别结果（会被反复重写），TA 说话时是正在
/// 吐字的回复（只追加）。说完之后这一行会搬进下面的历史列表，所以这里
/// 不会和列表重复。
class _FloatingCaption extends StatelessWidget {
  const _FloatingCaption({required this.engine});

  final CallEngine engine;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final line = engine.live;
    final text = line?.text ?? '';

    // 谁在说：用一个很轻的小标签标出来，免得分不清
    final label = line == null
        ? null
        : (line.isUser ? '你' : (engine.state.activePersona?.name ?? 'TA'));

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.fromLTRB(Spacing.xxl, Spacing.sm, Spacing.xxl, Spacing.md),
      alignment: Alignment.center,
      child: line == null || text.isEmpty
          ? Text(
              // 已经有 live 行但还没出字（刚开口 / 模型刚起头）→ 只显示省略号
              line != null || engine.phase == CallPhase.thinking
                  ? '…'
                  : '对着手机直接说话就行，不用按任何按钮。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: p.textTertiary,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: line.isUser ? p.brand : p.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                _AnimatedCaptionText(
                  text: text,
                  active: line.partial,
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    color: line.isUser ? p.brand : p.textPrimary,
                  ),
                  caretColor: line.isUser ? p.brand : p.textSecondary,
                ),
              ],
            ),
    );
  }
}

/// 会「浮动」的文字：新冒出来的部分淡入 + 整行轻轻上浮。
///
/// 为什么要按**公共前缀**做 diff 而不是简单追加：用户侧的实时字幕是
/// 「重新识别当前整段音频」得到的，结果会被整句重写（不只是变长），
/// 简单追加会导致每次新结果都把整行闪一下。取公共前缀后只让真正变化的
/// 尾巴做动画，视觉上就变成「稳定地一个字一个字冒出来」。
class _AnimatedCaptionText extends StatefulWidget {
  const _AnimatedCaptionText({
    required this.text,
    required this.style,
    required this.caretColor,
    this.active = false,
  });

  final String text;
  final TextStyle style;
  final Color caretColor;

  /// 还在增长（显示闪烁光标）
  final bool active;

  @override
  State<_AnimatedCaptionText> createState() => _AnimatedCaptionTextState();
}

class _AnimatedCaptionTextState extends State<_AnimatedCaptionText>
    with TickerProviderStateMixin {
  /// 新尾巴的淡入 + 整行上浮
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );

  /// 光标闪烁
  late final AnimationController _caret = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  /// 上一次渲染的文本 / 已经稳定的前缀长度
  String _prev = '';
  int _stableLen = 0;

  @override
  void initState() {
    super.initState();
    _prev = widget.text;
    _stableLen = widget.text.length;
  }

  @override
  void didUpdateWidget(covariant _AnimatedCaptionText old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text) return;
    var n = 0;
    final minLen = math.min(_prev.length, widget.text.length);
    while (n < minLen && _prev[n] == widget.text[n]) {
      n++;
    }
    _stableLen = n;
    _prev = widget.text;
    // 文本变短（重识别结果被修正）就别做上浮了，直接切
    if (widget.text.length > n) _rise.forward(from: 0);
  }

  @override
  void dispose() {
    _rise.dispose();
    _caret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final stableLen = math.min(_stableLen, text.length);
    final stable = text.substring(0, stableLen);
    final fresh = text.substring(stableLen);

    return AnimatedBuilder(
      animation: Listenable.merge([_rise, _caret]),
      builder: (_, __) {
        final t = Curves.easeOut.transform(_rise.value);
        return Transform.translate(
          offset: Offset(0, (1 - t) * 5),
          child: Text.rich(
            TextSpan(
              children: [
                if (stable.isNotEmpty)
                  TextSpan(text: stable, style: widget.style),
                if (fresh.isNotEmpty)
                  TextSpan(
                    text: fresh,
                    style: widget.style.copyWith(
                      color: widget.style.color?.withValues(alpha: t),
                    ),
                  ),
                if (widget.active)
                  TextSpan(
                    text: '▍',
                    style: widget.style.copyWith(
                      color: widget.caretColor
                          .withValues(alpha: 0.15 + _caret.value * 0.7),
                    ),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

// ─────────────────────────── 历史字幕列表 ───────────────────────────

class _Transcript extends StatefulWidget {
  const _Transcript({required this.engine});

  final CallEngine engine;

  @override
  State<_Transcript> createState() => _TranscriptState();
}

class _TranscriptState extends State<_Transcript> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final lines = widget.engine.lines;
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl, vertical: Spacing.sm),
      itemCount: lines.length,
      itemBuilder: (_, i) {
        final l = lines[i];
        return Align(
          alignment: l.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: l.isUser ? p.brand.withValues(alpha: 0.12) : p.itemHover,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Text(
              l.text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: p.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────── 控制区 ───────────────────────────

class _Controls extends StatelessWidget {
  const _Controls({
    required this.engine,
    required this.onHangup,
    required this.onType,
  });

  final CallEngine engine;
  final Future<void> Function() onHangup;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CircleBtn(
          p: p,
          icon: engine.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: engine.muted ? '已静音' : '静音',
          onTap: () => engine.setMuted(!engine.muted),
        ),
        _CircleBtn(
          p: p,
          icon: Icons.call_end_rounded,
          label: '挂断',
          background: const Color(0xFFB42318),
          foreground: Colors.white,
          size: 68,
          iconSize: 30,
          onTap: onHangup,
        ),
        _CircleBtn(
          p: p,
          icon: Icons.keyboard_alt_outlined,
          label: '打字',
          onTap: onType,
        ),
      ],
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({
    required this.p,
    required this.icon,
    required this.label,
    required this.onTap,
    this.background,
    this.foreground,
    this.size = 56,
    this.iconSize = 24,
  });

  final AppPalette p;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? background;
  final Color? foreground;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background ?? p.itemHover,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon,
                  size: iconSize, color: foreground ?? p.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(fontSize: SiniText.labelMd, color: p.textSecondary)),
      ],
    );
  }
}
