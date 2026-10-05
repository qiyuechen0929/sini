/// 声音克隆页：导入一段 TA 的语音 → 让 TA 用那个音色说话。
///
/// 这一页的完整链路（全部在本机完成，不联网、不花钱）：
///   选音频 → 浏览器解码 → 确认"这段录音说了什么" → 用 ZipVoice 克隆出音色
///   → 用预设例句试听 → 不满意可**重新生成**（每次都做更多处理，见 [_regenerate]）
///
/// 两个设计要点：
///  1. **样本不出设备**：参考音频只保存在本机（IndexedDB，供聊天页「播放」
///     朗读用），不联网、不上传。既让「TA 用自己的声音说话」成立，
///     也把原始人声留在了用户手里。
///  2. **"重新生成更好"要看得见**：每次重新生成都会列出这次做了什么
///     （去静音 / 裁时长 / 归一化 / 提高步数），而不是无理由重抽一次。
library;

import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_sheet.dart';
import '../../../core/widgets/sini_status_pill.dart';
import '../../../core/widgets/sini_text_field.dart';
import '../../../models.dart';
import '../../../theme.dart';
import '../audio_pcm.dart';
import '../audio_preprocess.dart';
import '../ref_audio_store.dart';
import '../voice_engine.dart';
import '../asr_engine.dart';

/// 创建流程中参考音频的暂存 key（人格建出来后迁移到正式 personaId）
const String kDraftRefKey = '__draft_voice__';

/// 试听用的预设例句。ZipVoice 要求句子不能太短（太短会明显失真），
/// 这句 11 个字，正好在日常口语的范围内。
const String kPreviewSentence = '在吗？今天过得还好吗？';

/// 每次生成用的推理步数：第一次求快，之后逐步提高（越细越慢，但更像）。
const List<int> kStepLadder = [4, 8, 12, 16];

class VoiceClonePage extends StatefulWidget {
  /// 保存目标人格（从素材导入页跳转时通过路由参数带来）。
  /// 有值时保存直接落到 TA 身上；为空则看 [createMode]。
  final String? targetPersonaId;

  /// 创建人格流程：此时目标人格还不存在，保存 = 暂存草稿，
  /// 等用户点「保存并创建」时随人格一起落库（名字以创建页填的为准）。
  final bool createMode;
  const VoiceClonePage({super.key, this.targetPersonaId, this.createMode = false});

  @override
  State<VoiceClonePage> createState() => _VoiceClonePageState();
}

enum _Phase { idle, sampleReady, generating, done }

class _VoiceClonePageState extends State<VoiceClonePage> {
  final _player = AudioPlayer();
  final _refTextCtl = TextEditingController();

  bool _agreed = false;
  _Phase _phase = _Phase.idle;

  String _sourceLabel = '';
  DecodedAudio? _sample;
  double _sampleSeconds = 0;

  VoiceGenResult? _result;
  int _attempt = 0;
  String _status = '';
  String? _error;
  List<String> _applied = const []; // 本次生成做了哪些处理
  bool _saved = false;

  // 一键识别（ASR）状态
  bool _asrBusy = false;
  String _asrStatus = '';

  @override
  void dispose() {
    _player.dispose();
    _refTextCtl.dispose();
    super.dispose();
  }

  // ─────────────────────────── 选样本 ───────────────────────────

  Future<void> _pickSample() async {
    setState(() {
      _error = null;
      _status = '';
    });

    // 用 pickFile（单文件）：pickFiles 的 allowMultiple / withData 都已废弃
    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['wav', 'mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac'],
      );
    } catch (_) {
      try {
        file = await FilePicker.pickFile();
      } catch (_) {
        return; // 用户取消
      }
    }
    if (file == null) return;
    // 提为非空局部变量：try/catch 里赋值的可空变量，流分析不会做空提升
    final picked = file;

    Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      setState(() => _error = '读不到文件内容，换一个文件试试');
      return;
    }
    if (bytes.isEmpty) {
      setState(() => _error = '这个文件是空的');
      return;
    }

    setState(() => _status = '正在解码音频…');
    final decoded = await decodeAudioBytes(bytes);
    if (!mounted) return;

    if (decoded == null || decoded.samples.isEmpty) {
      setState(() {
        _status = '';
        _error = '这个格式解不开。换成 wav 或 mp3 再试（微信语音条要先转成 mp3）';
      });
      return;
    }

    // 原始样本先做一次质量体检，把问题提前告诉用户。
    // 关键：**样本本身就用预处理后的音频**（去静音 + 超长裁到 10s）。
    // ZipVoice 靠「参考音频 + 对应文字稿」对齐来学音色——如果音频被裁短
    // 而文字稿还是整段的，俩对不上，合成出来的内容就会乱。
    // 统一裁好之后，「一键识别」转的就是裁后这段，文字永远和音频对齐；
    // 试听按钮听到的也是模型实际使用的那段。
    final prep = prepareReference(decoded.samples, decoded.sampleRate);
    final keptSample = DecodedAudio(
      samples: prep.samples.isEmpty ? decoded.samples : prep.samples,
      sampleRate: decoded.sampleRate,
    );
    setState(() {
      _phase = _Phase.sampleReady;
      _sourceLabel = picked.name;
      _sample = keptSample;
      _sampleSeconds = keptSample.durationSeconds;
      _result = null;
      _attempt = 0;
      _applied = const [];
      _saved = false;
      _status = '';
      _error = null;
      // 样本做了什么处理 / 有什么问题，选完就告诉用户
      _prepNotes = prep.notes;
      _prepWarnings = prep.warnings;
    });
  }

  /// 选样本时对音频做的处理说明（如「裁到能量最集中的 10s」）
  List<String> _prepNotes = const [];
  List<String> _prepWarnings = const [];

  // ─────────────────────────── 生成 ───────────────────────────

  /// 第 [attempt] 次生成（从 1 开始）。
  ///
  /// 第一次：拿原始样本直接生成，求快，先让用户听到音色。
  /// 之后每次：**先做参考音频预处理**（去静音 / 截到能量最集中的一段 /
  /// 响度归一化），再按 [kStepLadder] 提高推理步数 —— 这两件事都会
  /// 实打实地抬升音色还原度，而不是重复抽签。
  Future<void> _generate({required bool regenerate}) async {
    final sample = _sample;
    if (sample == null) return;
    if (!_agreed) {
      setState(() => _error = '请先勾选「已获得本人授权」');
      return;
    }
    final refText = _refTextCtl.text.trim();
    if (refText.isEmpty) {
      setState(() => _error = '请填写这段录音说的是什么（克隆音色必须要有它）');
      return;
    }

    final nextAttempt = regenerate ? _attempt + 1 : 1;
    final steps = kStepLadder[
        (nextAttempt - 1).clamp(0, kStepLadder.length - 1)];

    // 参考音频**每次都预处理**（不只重新生成时）：
    // ZipVoice 对参考长度非常敏感——太长会发散甚至把 WASM 搞崩
    // （表现就是 RuntimeError: Aborted()），太短会不稳。
    // 统一走「去静音 → 超长截到能量集中段 → 响度归一化」。
    final prep = prepareReference(sample.samples, sample.sampleRate);
    var samples = prep.samples;
    final applied = [...prep.notes];
    if (regenerate && applied.isEmpty) {
      applied.add('样本本身已经很干净，这次靠提高推理步数（$steps 步）提升细节');
    }

    // 超短参考会让模型直接崩溃，提前拦截并说人话
    final refSeconds = samples.length / sample.sampleRate;
    if (refSeconds < 1.2) {
      setState(() => _error = '这段录音只有 ${refSeconds.toStringAsFixed(1)} 秒，'
          '太短了，模型没法稳定克隆（至少 3 秒，建议 3~10 秒清晰人声）');
      return;
    }

    setState(() {
      _phase = _Phase.generating;
      _error = null;
      _status = regenerate
          ? '正在按更精细的参数重新生成（第 $nextAttempt 次）…'
          : '正在生成…首次会先加载模型，可能要等一会儿';
      _result = null;
    });
    // 让"生成中"这一帧先渲染出来 —— 下面的调用会阻塞主线程
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    try {
      await VoiceEngine.ensureLoaded(onStatus: (s) {
        if (mounted) setState(() => _status = s);
      });
      if (!mounted) return;
      setState(() => _status = '正在合成语音（${steps} 步）…');
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final result = VoiceEngine.generate(
        referenceSamples: samples,
        referenceSampleRate: sample.sampleRate,
        referenceText: refText,
        text: kPreviewSentence,
        numSteps: steps,
      );

      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _result = result;
        _attempt = nextAttempt;
        _applied = applied;
        _status = '';
        _saved = false;
      });
      await _play();
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      // WASM 层崩溃（内存不足 / 音频触发的内部错误）只给一句 "Aborted()"，
      // 对用户毫无意义，翻译成可行动的建议。
      final friendly = raw.contains('Aborted') || raw.contains('RuntimeError')
          ? '合成引擎在本机崩溃了。常见原因：录音太短或太长、浏览器内存不足。'
              '建议换一段 3~10 秒的清晰人声，关掉其他标签页后重试'
          : '生成失败：$e';
      setState(() {
        _phase = _Phase.sampleReady;
        _status = '';
        _error = friendly;
      });
    }
  }

  // ─────────────────────────── 一键识别（ASR）──────────────────────────

  /// 用同一个 WASM 运行时把当前样本自动转成文字，填入参考文本。
  /// 用户只需校对，不必手打。识别失败不清空已有内容，仍可手打。
  Future<void> _autoTranscribe() async {
    final sample = _sample;
    if (sample == null || _asrBusy) return;
    setState(() {
      _asrBusy = true;
      _asrStatus = '正在加载识别模型…';
      _error = null;
    });
    try {
      await AsrEngine.ensureLoaded(onStatus: (s) {
        if (mounted) setState(() => _asrStatus = s);
      });
      if (!mounted) return;
      setState(() => _asrStatus = '正在识别…');
      // 让状态先渲染
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final text = await AsrEngine.transcribe(sample.samples, sample.sampleRate);
      if (!mounted) return;
      _refTextCtl.text = text;
      setState(() => _asrStatus =
          text.isEmpty ? '没听清，请手动填写' : '已自动识别，请校对一下');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '自动识别失败：$e（可直接手动填写）');
    } finally {
      if (mounted) setState(() => _asrBusy = false);
    }
  }

  Future<void> _play() async {
    final r = _result;
    if (r == null) return;
    try {
      await _player.stop();
      await _player.play(BytesSource(r.toWavBytes()));
    } catch (e) {
      if (mounted) setState(() => _error = '播放失败：$e');
    }
  }

  // ─────────────────────────── 保存 / 撤销 ───────────────────────────

  /// 保存分发：有目标人格 → 直接存；创建流程 → 暂存草稿；
  /// 都没有 → 弹人格列表 / 问名字。
  void _onSaveTap(Persona? persona) {
    if (persona != null && !persona.locked) {
      _saveToPersona(persona);
      return;
    }
    if (widget.createMode) {
      _saveDraftVoice();
      return;
    }
    _pickPersonaAndSave();
  }

  String _saveLabel(Persona? persona) {
    if (persona != null && !persona.locked) return '用这个声音';
    if (widget.createMode) return '保存声音（随人格一起创建）';
    return '保存到人格…';
  }

  /// 创建人格流程：人格还没建出来，把声音的授权与参考信息暂存成草稿，
  /// 等用户点「保存并创建」时随人格一起落库——名字以创建页填的为准，
  /// 全程不用再问。
  void _saveDraftVoice() {
    final r = _result;
    if (r == null) return;
    AppStateScope.read(context).setDraftVoice(PersonaVoice(
      sourceLabel: _sourceLabel,
      referenceText: _refTextCtl.text.trim(),
      sampleSeconds: _sampleSeconds,
      consentedAt: DateTime.now(),
      ready: true,
    ));
    // 参考音频也暂存（固定 key），「保存并创建」建出人格后再迁移过去
    final s = _sample;
    if (s != null) {
      RefAudioStore.save(kDraftRefKey, encodeWav(s.samples, s.sampleRate));
    }
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('声音已保存，创建人格时会自动带上（回素材页点「保存并创建」）'),
        duration: Duration(milliseconds: 2400),
      ),
    );
  }

  /// 非创建流程且没有目标人格时：弹列表挑一个，或建新人格。
  Future<void> _pickPersonaAndSave() async {
    final app = AppStateScope.read(context);
    // 锁定的「默认助手」不进候选
    final candidates = app.personas.where((p) => !p.locked).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('还没有人格：先在「导入素材」里创建一个人格，再来保存声音'),
          duration: Duration(milliseconds: 2200),
        ),
      );
      return;
    }

    final picked = await showSiniSheet<Object?>(
      context: context,
      title: '保存到哪个人格',
      subtitle: 'TA 之后就用这个声音说话',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 340),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: candidates.length,
          itemBuilder: (ctx, i) {
            final persona = candidates[i];
            return ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.lg)),
              leading: CircleAvatar(
                backgroundColor:
                    AppPalette(isDark: Theme.of(ctx).brightness == Brightness.dark)
                        .itemHover,
                child: Text(
                  persona.name.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              title: Text(persona.name),
              onTap: () => Navigator.pop(ctx, persona),
            );
          },
        ),
      ),
    );
    if (picked is Persona && mounted) _saveToPersona(picked);
  }

  void _saveToPersona(Persona persona) {
    final r = _result;
    if (r == null) return;
    AppStateScope.read(context).setPersonaVoice(
      persona.id,
      PersonaVoice(
        sourceLabel: _sourceLabel,
        referenceText: _refTextCtl.text.trim(),
        sampleSeconds: _sampleSeconds,
        consentedAt: DateTime.now(),
        ready: true,
      ),
    );
    // 参考音频存本机（IndexedDB）：聊天页「播放」要用 TA 的声音朗读。
    // 只存本机、不上传。覆盖写，重复克隆自动更新。
    final s = _sample;
    if (s != null) {
      RefAudioStore.save(persona.id, encodeWav(s.samples, s.sampleRate));
    }
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「${persona.name}」的声音已保存（授权记录已留档）'),
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }

  Future<void> _revoke(Persona persona) async {
    AppStateScope.read(context).removePersonaVoice(persona.id);
    // 本机存的参考音频一并删掉（撤销授权 = 声音数据也清干净）
    await RefAudioStore.delete(persona.id);
    setState(() {
      _saved = false;
      _phase = _Phase.sampleReady;
      _result = null;
      _attempt = 0;
      _applied = const [];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已撤销授权并删除声音记录'),
        duration: Duration(milliseconds: 1600),
      ),
    );
  }

  // ─────────────────────────── UI ───────────────────────────

  /// 保存目标人格：优先路由参数带来的人格（素材导入流程的目标），
  /// 其次当前选中人格。锁定的「默认助手」不算有效目标——
  /// 用户克隆的声音几乎不会想存到它身上。
  Persona? _resolvePersona(AppState app) {
    final id = widget.targetPersonaId;
    if (id != null && id.isNotEmpty) {
      for (final p in app.personas) {
        if (p.id == id) return p;
      }
    }
    final active = app.activePersona;
    return (active != null && !active.locked) ? active : null;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final persona = _resolvePersona(AppStateScope.of(context));

    // 注意：这里**不因为"还没选人格"就整页挡住** —— 让人先挑样本、听效果，
    // 保存时再要求有人格。否则用户连"这个引擎效果行不行"都试不了。
    return SiniScaffold(
      title: '声音克隆',
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          _statusCard(p, persona),
          const SizedBox(height: Spacing.xxl),
          _stepTitle(p, '1', '选一段 TA 的语音'),
          const SizedBox(height: Spacing.sm),
          _hint(p, '安静环境下录的、或聊天里发过的语音条都行；建议 3~10 秒，越清晰越像。'),
          const SizedBox(height: Spacing.md),
          if (_phase == _Phase.idle)
            SiniButton(
              label: '选择语音文件',
              leadingIcon: Icons.upload_file_rounded,
              onTap: _busy ? null : _pickSample,
              style: SiniButtonStyle.primary,
              expand: true,
              height: 48,
            )
          else
            _sampleCard(p),
          const SizedBox(height: Spacing.xxl),
          if (_phase != _Phase.idle) ...[
            _stepTitle(p, '2', '这段录音说了什么？'),
            const SizedBox(height: Spacing.sm),
            _hint(p, '必须照实填。ZipVoice 靠这句话对齐发音，填错会明显失真。'),
            const SizedBox(height: Spacing.md),
            SiniTextField(
              controller: _refTextCtl,
              maxLines: 3,
              hintText: '例如：那个事情我明天再跟你说一下',
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                SiniButton(
                  label: _asrBusy ? '识别中…' : '一键识别',
                  leadingIcon: Icons.auto_awesome_rounded,
                  onTap: _asrBusy ? null : _autoTranscribe,
                  style: SiniButtonStyle.secondary,
                  height: 38,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    _asrStatus,
                    style: TextStyle(
                        fontSize: SiniText.labelMd, color: p.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xxl),
            _consentCard(p),
            const SizedBox(height: Spacing.xxl),
            _stepTitle(p, '3', '生成并试听'),
            const SizedBox(height: Spacing.sm),
            _hint(p, '会用这句预设例句试听：$kPreviewSentence'),
            const SizedBox(height: Spacing.md),
            _generateButton(p),
            if (_result != null) ...[
              const SizedBox(height: Spacing.lg),
              _resultCard(p, persona),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: Spacing.lg),
            _errorBox(p, _error!),
          ],
          if (_status.isNotEmpty) ...[
            const SizedBox(height: Spacing.lg),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: p.brand),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(_status,
                      style: TextStyle(
                          fontSize: SiniText.labelMd, color: p.textSecondary)),
                ),
              ],
            ),
          ],
          const SizedBox(height: Spacing.xxl),
          _footer(p),
        ],
      ),
    );
  }

  bool get _busy => _phase == _Phase.generating;

  Widget _statusCard(AppPalette p, Persona? persona) {
    if (persona == null) {
      return Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: p.itemHover,
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: p.textSecondary),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                widget.createMode
                    ? '正在为创建中的 TA 准备声音——保存后回素材页点「保存并创建」，声音会跟着人格一起建好。'
                    : '还没有选中的人格。可以先试听效果；要保存的话，先去人格列表选一个人格再回来。',
                style: TextStyle(
                    fontSize: SiniText.labelMd,
                    color: p.textSecondary,
                    height: 1.5),
              ),
            ),
          ],
        ),
      );
    }
    final voice = persona.voice;
    final ready = voice != null && voice.ready;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.mainBg),
            child: Icon(Icons.graphic_eq_rounded, size: 28, color: p.brand),
          ),
          const SizedBox(width: Spacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${persona.name} 的声音',
                        style: TextStyle(
                            fontSize: SiniText.bodySm, color: p.textSecondary)),
                    const SizedBox(width: Spacing.sm),
                    SiniStatusPill(
                      label: ready ? '已配声音' : '未设置',
                      tone: ready
                          ? SiniStatusTone.success
                          : SiniStatusTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  ready
                      ? '样本「${voice.sourceLabel}」· '
                          '${voice.sampleSeconds.toStringAsFixed(1)}s · '
                          '授权于 ${_fmtDate(voice.consentedAt)}'
                      : '还没为 TA 配声音',
                  style: TextStyle(
                      fontSize: SiniText.titleSm,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary),
                ),
                if (ready) ...[
                  const SizedBox(height: Spacing.sm),
                  GestureDetector(
                    onTap: () => _revoke(persona),
                    child: Text('撤销授权并删除',
                        style: TextStyle(
                            fontSize: SiniText.labelMd,
                            color: p.textTertiary,
                            decoration: TextDecoration.underline)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sampleCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.audio_file_rounded, size: 18, color: p.brand),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(_sourceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: SiniText.bodySm,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary)),
              ),
              Text('${_sampleSeconds.toStringAsFixed(1)}s',
                  style: TextStyle(
                      fontSize: SiniText.labelMd, color: p.textSecondary)),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              SiniButton(
                label: '试听样本',
                onTap: _busy ? null : _playSample,
                style: SiniButtonStyle.secondary,
                height: 36,
              ),
              const SizedBox(width: Spacing.sm),
              SiniButton(
                label: '换一个',
                onTap: _busy ? null : _pickSample,
                style: SiniButtonStyle.secondary,
                height: 36,
              ),
            ],
          ),
          for (final n in _prepNotes) ...[
            const SizedBox(height: Spacing.sm),
            Text('· 已自动处理：$n（点「试听样本」听到的是处理后的片段，'
                '「一键识别」转的也是这段）',
                style: TextStyle(
                    fontSize: SiniText.labelMd,
                    color: p.textSecondary,
                    height: 1.4)),
          ],
          for (final w in _prepWarnings) ...[
            const SizedBox(height: Spacing.sm),
            Text('⚠ $w',
                style: TextStyle(
                    fontSize: SiniText.labelMd, color: p.textSecondary, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Future<void> _playSample() async {
    final s = _sample;
    if (s == null) return;
    await _player.stop();
    await _player.play(BytesSource(encodeWav(s.samples, s.sampleRate)));
  }

  Widget _consentCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('声音授权',
              style: TextStyle(
                  fontSize: SiniText.bodySm + 0.5,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary)),
          const SizedBox(height: Spacing.sm),
          Text(
            '克隆的是真人的声音，必须获得本人同意。样本只保存在这台设备上，不会上传到任何服务器；'
            '你可以随时在这里撤销授权并删除记录。',
            style: TextStyle(
                fontSize: SiniText.labelMd, color: p.textSecondary, height: 1.55),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Checkbox(
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                activeColor: p.brand,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.xs)),
              ),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child: Text('我已获得本人授权，并同意在本机合成该声音',
                    style:
                        TextStyle(fontSize: SiniText.labelMd, color: p.textPrimary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _generateButton(AppPalette p) {
    if (_phase == _Phase.generating) {
      return SiniButton(
        label: '生成中…',
        onTap: null,
        style: SiniButtonStyle.primary,
        expand: true,
        height: 48,
      );
    }
    if (_phase == _Phase.done) {
      return SiniButton(
        label: '重新生成（这次更精细）',
        leadingIcon: Icons.refresh_rounded,
        onTap: () => _generate(regenerate: true),
        style: SiniButtonStyle.primary,
        expand: true,
        height: 48,
      );
    }
    return SiniButton(
      label: '生成声音',
      leadingIcon: Icons.graphic_eq_rounded,
      onTap: () => _generate(regenerate: false),
      style: SiniButtonStyle.primary,
      expand: true,
      height: 48,
    );
  }

  Widget _resultCard(AppPalette p, Persona? persona) {
    final r = _result!;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('第 $_attempt 次生成 · ${r.numSteps} 步',
                    style: TextStyle(
                        fontSize: SiniText.bodySm,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary)),
              ),
              Text(
                '${r.durationSeconds.toStringAsFixed(1)}s / '
                '耗时 ${(r.elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s',
                style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SiniButton(
            label: '再听一遍',
            leadingIcon: Icons.play_arrow_rounded,
            onTap: _play,
            style: SiniButtonStyle.secondary,
            height: 40,
          ),
          if (_applied.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            Text('这次做了什么：',
                style: TextStyle(
                    fontSize: SiniText.labelMd,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary)),
            for (final a in _applied) ...[
              const SizedBox(height: 4),
              Text('· $a',
                  style: TextStyle(
                      fontSize: SiniText.labelMd,
                      color: p.textSecondary,
                      height: 1.4)),
            ],
          ],
          const SizedBox(height: Spacing.lg),
          SiniButton(
            label: _saved
                ? '已保存'
                : _saveLabel(persona),
            leadingIcon: _saved ? Icons.check_rounded : Icons.save_rounded,
            onTap: _saved ? null : () => _onSaveTap(persona),
            style: SiniButtonStyle.primary,
            expand: true,
            height: 44,
          ),
        ],
      ),
    );
  }

  Widget _stepTitle(AppPalette p, String index, String text) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: p.textPrimary),
          child: Text(index,
              style: TextStyle(
                  fontSize: SiniText.labelSm,
                  fontWeight: FontWeight.w700,
                  color: p.inverseOn)),
        ),
        const SizedBox(width: Spacing.sm),
        Text(text,
            style: TextStyle(
                fontSize: SiniText.titleSm,
                fontWeight: FontWeight.w600,
                color: p.textPrimary)),
      ],
    );
  }

  Widget _hint(AppPalette p, String text) => Text(text,
      style: TextStyle(
          fontSize: SiniText.labelMd, color: p.textSecondary, height: 1.5));

  Widget _errorBox(AppPalette p, String text) => Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: p.mainBg,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: p.border),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: SiniText.labelMd, color: p.textPrimary, height: 1.5)),
      );

  Widget _footer(AppPalette p) => Text(
        '声音由 AI 合成，不是本人录制。用的是开源模型 ZipVoice（Apache-2.0）'
        '在本机推理，不联网、不收费。',
        style: TextStyle(
            fontSize: SiniText.labelSm, color: p.textTertiary, height: 1.5),
      );

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
