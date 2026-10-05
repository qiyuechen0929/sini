/// 语音通话引擎：把「麦克风 → 识别 → 人格模型 → 合成 → 播放」串成一条
/// 可以随时被打断的流水线。
///
/// ## 和文字聊天的关系（这是本功能的核心约束）
///
/// 通话**不是**另一套会话。用户的话和 TA 的话都写进**当前那条对话**
/// （`AppState.callTurn`），system prompt / 长期记忆 / 早期摘要 / 人格设定
/// 全部复用文字聊天那一套。所以：打完电话回到聊天页，刚才说的话就在那儿；
/// 在文字里聊完再打电话，TA 也记得。
///
/// ## 为什么要分句流水线
///
/// ZipVoice 在本机推理，一句 2~3 秒的话要 2~4 秒才合成完（CPU + WASM）。
/// 如果「等整段回复写完 → 整段合成 → 才开始出声」，用户要干等十几秒。
/// 所以：
///   - LLM 走流式，吐到句子边界就切一句出来；
///   - 第一句合成完立刻开始播；
///   - **播放的同时**合成下一句（音频在浏览器音频线程上放，不会被主线程的
///     合成阻塞）。听感上就是「马上接话、中间不断」。
///
/// ## 实时字幕（live）
///
/// [live] 是「此刻正在发生的那句话」：用户说话时是他还没说完的实时识别结果，
/// TA 说话时是正在吐字的回复。说完整句后搬进 [lines]（历史列表）。
///
/// 用户侧的「实时」是靠**本机增量识别**做的：说话期间每隔一会儿把当前这段
/// 音频重新丢给本机 Whisper 解一次（`_partialLoop`）。所以本机没有流式识别
/// 模型也能出实时字幕，代价是吃 CPU —— 节奏由 `_partialDelayMs` 自适应控制。
///
/// ## 打断
///
/// AI 播报时麦克风继续听（`MicCapture.setAiSpeaking(true)` 会抬高 VAD 门槛，
/// 避免外放被自己打断）。用户真的开口并撑过 `bargeInMs` 才判定为插话：
/// 立刻停播、丢弃还没播的句子、并让正在跑的 LLM 流提前收尾。
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../../app_state.dart';
import '../../../models.dart';
import '../asr_engine.dart';
import '../voice_engine.dart';
import 'mic_capture.dart';
import 'sentence_splitter.dart';

/// 通话阶段。UI 的状态文案和按钮可用性都看它。
enum CallPhase {
  /// 还没接通 / 正在建立
  connecting,

  /// 在听用户说
  listening,

  /// 正在识别 / 等模型回复
  thinking,

  /// TA 正在说
  speaking,

  /// 已挂断
  ended,
}

/// 一句话（字幕里的一行）
class CallLine {
  CallLine({required this.isUser, required this.text, this.partial = false});

  final bool isUser;
  String text;

  /// 还在增长中（用户还在说 / LLM 还在吐字）—— 用来显示光标
  bool partial;
}

/// 合成好的一段音频 + 它的响度包络（用来画真实波形，不是假动画）
class _SpokenAudio {
  _SpokenAudio(this.wav, this.envelope, this.duration);

  final Uint8List wav;

  /// 40 个桶的 RMS 包络，0~1
  final List<double> envelope;
  final Duration duration;
}

class CallEngine extends ChangeNotifier {
  CallEngine(this.state);

  final AppState state;

  // ── 对外可读状态 ──
  CallPhase phase = CallPhase.connecting;
  String status = '正在接通…';

  /// 已经说完的句子（历史列表）
  final List<CallLine> lines = [];

  /// 此刻正在发生的那一句（大字幕）。说完后搬进 [lines]。
  CallLine? live;

  double userLevel = 0;
  double aiLevel = 0;
  bool muted = false;
  bool get connected => phase != CallPhase.connecting && phase != CallPhase.ended;

  /// TA 有没有先开口（用于 UI 上给一句轻提示）
  bool openedByPersona = false;

  // ── 内部 ──
  final MicCapture _mic = MicCapture();
  AudioPlayer? _player;
  Completer<void>? _playDone;
  Timer? _envTimer;

  /// 轮次号：任何打断 / 挂断都会 +1，让旧流水线自己退出
  int _turnId = 0;
  bool _disposed = false;

  // 分句 → 合成 → 播放 的两级队列
  final SentenceSplitter _splitter = SentenceSplitter();
  final List<String> _pendingSentences = [];
  Completer<void>? _sentenceWake;
  bool _allTextReceived = false;

  /// 正在思考时用户又说话了：留到这一轮结束后接着处理
  Float32List? _queuedUtterance;

  // 增量识别（实时字幕）
  Timer? _partialTimer;
  bool _partialBusy = false;
  bool _partialStopped = true;
  int _partialDelayMs = 800;

  PersonaVoice? get _voice => state.activePersona?.voice;

  // ═══════════════════════════ 生命周期 ═══════════════════════════

  Future<void> start() async {
    _turnId++;
    _disposed = false;
    phase = CallPhase.connecting;
    status = '正在接通…';
    notifyListeners();

    _mic
      ..onLevel = _onUserLevel
      ..onSpeechChanged = _onSpeechChanged
      ..onUtterance = _onUtterance
      ..onBargeIn = _onBargeIn
      ..onError = (m) {
        status = m;
        notifyListeners();
      };

    // 识别模型 90MB，提前在后台挂载，别等用户说完才开始读盘
    unawaited(AsrEngine.ensureLoaded().catchError((Object _) {}));

    try {
      await _mic.start();
    } catch (_) {
      phase = CallPhase.ended;
      status = '打不开麦克风，无法通话';
      notifyListeners();
      return;
    }

    phase = CallPhase.listening;
    status = '通了，在听你说';
    notifyListeners();

    // TA 可能先开口（也可能不，由它自己判断）
    unawaited(_maybeOpen());
  }

  Future<void> hangup() async {
    if (phase == CallPhase.ended) return;
    _turnId++;
    _stopPartialLoop();
    _stopPlayback();
    _wakeSentences();
    await _mic.stop();
    _mic.onUtterance = null;
    _mic.onBargeIn = null;
    _mic.onSpeechChanged = null;
    _mic.onLevel = null;
    phase = CallPhase.ended;
    status = '通话已结束';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _turnId++;
    _stopPartialLoop();
    _stopPlayback();
    _mic.stop();
    _player?.dispose();
    _player = null;
    super.dispose();
  }

  Future<void> setMuted(bool v) async {
    muted = v;
    await _mic.setMuted(v);
    if (v) _stopPartialLoop();
    notifyListeners();
  }

  /// 通话里直接打字（用户不方便说话时）。走的是同一条对话和同一套上下文。
  Future<void> sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty || phase == CallPhase.ended) return;
    _turnId++;
    _stopPartialLoop();
    _stopPlayback();
    _commitLive();
    await _runTurn(t, userSamples: null);
  }

  /// 让 TA 别说了（手动打断）。
  void shutUp() {
    if (phase != CallPhase.speaking) return;
    _interrupt();
  }

  // ═══════════════════════════ 主动开口 ═══════════════════════════

  Future<void> _maybeOpen() async {
    final myTurn = _turnId;
    final opening = await state.callOpeningLine();
    if (_disposed || myTurn != _turnId) return;
    if (opening == null || opening.trim().isEmpty) return;

    openedByPersona = true;
    final line = CallLine(isUser: false, text: opening, partial: true);
    live = line;
    _pendingSentences
      ..clear()
      ..add(opening);
    _allTextReceived = true;
    _wakeSentences();
    phase = CallPhase.speaking;
    status = '${state.activePersona?.name ?? 'TA'} 先开口了';
    notifyListeners();

    await _speakLoop(myTurn);
    if (_disposed || myTurn != _turnId) return;
    line.partial = false;
    _commitLive();
    _finishTurn();
  }

  // ═══════════════════════════ 麦克风回调 ═══════════════════════════

  void _onUserLevel(double rms) {
    userLevel = rms;
    notifyListeners();
  }

  void _onSpeechChanged(bool speaking) {
    if (speaking) {
      // 用户开口就立刻起一个大字幕（此时还没识别出内容），边说边填字
      _beginUserLine();
      _startPartialLoop();
      if (phase == CallPhase.listening) status = '我在听…';
    } else {
      _stopPartialLoop();
      if (phase == CallPhase.listening) status = '在听你说';
    }
    notifyListeners();
  }

  void _onUtterance(Float32List samples) {
    if (_disposed || phase == CallPhase.ended) return;
    _stopPartialLoop();
    if (phase == CallPhase.thinking || phase == CallPhase.speaking) {
      // 正在忙：留到这一轮结束后处理（保留最新的那句）
      _queuedUtterance = samples;
      return;
    }
    unawaited(_handleUtterance(samples));
  }

  void _onBargeIn() {
    if (phase == CallPhase.speaking) {
      _interrupt();
      status = '你说，我在听…';
      notifyListeners();
    }
    _beginUserLine();
    _startPartialLoop();
  }

  void _beginUserLine() {
    final cur = live;
    if (cur != null && cur.isUser && cur.partial) return; // 已经在录了
    live = CallLine(isUser: true, text: '', partial: true);
    notifyListeners();
  }

  /// 把当前 live 行搬进历史列表。
  void _commitLive() {
    final cur = live;
    live = null;
    if (cur == null) return;
    cur.partial = false;
    if (cur.text.trim().isEmpty) return;
    lines.add(cur);
    notifyListeners();
  }

  // ═══════════════════════════ 实时字幕（本机增量识别）═══════════════════════════

  void _startPartialLoop() {
    if (_disposed || muted) return;
    _partialStopped = false;
    _schedulePartial(initial: true);
  }

  void _stopPartialLoop() {
    _partialStopped = true;
    _partialTimer?.cancel();
    _partialTimer = null;
  }

  void _schedulePartial({bool initial = false}) {
    _partialTimer?.cancel();
    if (_partialStopped || _disposed) return;
    _partialTimer = Timer(
      Duration(milliseconds: initial ? 600 : _partialDelayMs),
      _runPartial,
    );
  }

  /// 拿当前这段音频重解一次，把结果填进大字幕。
  ///
  /// 识别是同步阻塞的（WASM 单线程），所以节奏必须自适应：这次花多久，
  /// 下次就至少歇同样久，否则用户说话时界面会明显卡。
  Future<void> _runPartial() async {
    if (_partialStopped || _disposed || _partialBusy) {
      _schedulePartial();
      return;
    }
    final line = live;
    if (line == null || !line.isUser || !line.partial) {
      _stopPartialLoop();
      return;
    }
    _partialBusy = true;
    final sw = Stopwatch()..start();
    try {
      final pcm = _mic.peekAudio(maxSeconds: 12);
      if (pcm != null && pcm.length > kMicSampleRate * 0.4) {
        final t = await AsrEngine.transcribe(pcm, kMicSampleRate);
        if (!_disposed && identical(live, line) && t.isNotEmpty) {
          line.text = t;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[sini:call] 增量识别失败（忽略）：$e');
    } finally {
      _partialBusy = false;
      sw.stop();
      _partialDelayMs =
          (sw.elapsedMilliseconds * 1.1).round().clamp(600, 4000);
      _schedulePartial();
    }
  }

  // ═══════════════════════════ 一轮对话 ═══════════════════════════

  Future<void> _handleUtterance(Float32List samples) async {
    final myTurn = _turnId;
    _stopPartialLoop();
    phase = CallPhase.thinking;
    status = '正在听清你说的话…';
    notifyListeners();

    String text = '';
    try {
      await AsrEngine.ensureLoaded();
      if (_disposed || myTurn != _turnId) return;
      text = await AsrEngine.transcribe(samples, kMicSampleRate);
    } catch (e) {
      debugPrint('[sini:call] 识别失败：$e');
    }
    if (_disposed || myTurn != _turnId) return;

    if (text.trim().isEmpty) {
      live = null; // 没听清就别留半截字幕
      status = '没听清，你再说一遍？';
      _backToListening();
      return;
    }

    // 用最终识别结果覆盖增量结果，然后搬进历史
    final cur = live;
    if (cur != null && cur.isUser) {
      cur.text = text;
      cur.partial = false;
    } else {
      live = CallLine(isUser: true, text: text, partial: false);
    }
    _commitLive();
    await _runTurn(text.trim(), userSamples: samples);
  }

  Future<void> _runTurn(String userText, {Float32List? userSamples}) async {
    final myTurn = _turnId;
    phase = CallPhase.thinking;
    status = '在想…';
    final aiLine = CallLine(isUser: false, text: '', partial: true);
    live = aiLine;
    notifyListeners();

    _pendingSentences.clear();
    _allTextReceived = false;

    final reply = await state.callTurn(
      userText: userText,
      isCancelled: () => _disposed || myTurn != _turnId,
      onDelta: (d) {
        if (_disposed || myTurn != _turnId) return;
        aiLine.text += d;
        notifyListeners();
        // 吐到句子边界就立刻送去合成 —— 第一句能尽早出声全靠这里
        for (final s in _splitter.feed(d)) {
          _pendingSentences.add(s);
          _wakeSentences();
        }
      },
      onError: (e) {
        if (_disposed || myTurn != _turnId) return;
        aiLine.text = '（$e）';
        aiLine.partial = false;
        notifyListeners();
      },
    );

    if (_disposed || myTurn != _turnId) return;

    _allTextReceived = true;
    final tail = _splitter.flush();
    if (tail != null) {
      _pendingSentences.add(tail);
      _wakeSentences();
    }

    if (reply == null || reply.trim().isEmpty) {
      aiLine.partial = false;
      status = '没接上话，你再说一次？';
      notifyListeners();
      _commitLive();
      _finishTurn();
      return;
    }

    aiLine.text = reply;
    notifyListeners();

    if (_pendingSentences.isNotEmpty) {
      phase = CallPhase.speaking;
      status = '${state.activePersona?.name ?? 'TA'} 正在说…';
      notifyListeners();
    }

    await _speakLoop(myTurn);
    if (_disposed || myTurn != _turnId) return;
    aiLine.partial = false;
    _commitLive();
    _finishTurn();
  }

  void _finishTurn() {
    _pendingSentences.clear();
    _allTextReceived = false;
    final queued = _queuedUtterance;
    _queuedUtterance = null;
    if (queued != null) {
      unawaited(_handleUtterance(queued));
      return;
    }
    _backToListening();
  }

  void _backToListening() {
    if (_disposed || phase == CallPhase.ended) return;
    _mic.setAiSpeaking(false);
    _mic.discard(); // 丢掉这轮积下来的环境音（可能含外放残留）
    phase = CallPhase.listening;
    status = '在听你说';
    aiLevel = 0;
    notifyListeners();
  }

  // ═══════════════════════════ 播放流水线 ═══════════════════════════

  /// 等下一句待合成的文本；没有更多了返回 null。
  Future<String?> _nextSentence(int myTurn) async {
    while (true) {
      if (_disposed || myTurn != _turnId) return null;
      if (_pendingSentences.isNotEmpty) return _pendingSentences.removeAt(0);
      if (_allTextReceived) return null;
      _sentenceWake = Completer<void>();
      await _sentenceWake!.future;
      _sentenceWake = null;
    }
  }

  void _wakeSentences() {
    final c = _sentenceWake;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// 逐句合成 + 播放；播放当前句的同时预合成下一句。
  Future<void> _speakLoop(int myTurn) async {
    final voice = _voice;
    _SpokenAudio? carry;

    while (true) {
      if (_disposed || myTurn != _turnId) return;

      _SpokenAudio? audio = carry;
      carry = null;
      if (audio == null) {
        final s = await _nextSentence(myTurn);
        if (s == null) return;
        if (voice == null || !voice.ready) continue; // 没配声音：只显示字幕
        audio = await _synthesize(s, voice, myTurn);
        if (audio == null) continue;
      }

      _mic.setAiSpeaking(true);
      final done = _play(audio, myTurn);

      // 趁这几秒把下一句合成好，播完能立刻接上
      if (!_disposed && myTurn == _turnId) {
        final s2 = await _nextSentence(myTurn);
        if (s2 != null && voice != null && voice.ready) {
          carry = await _synthesize(s2, voice, myTurn);
        }
      }
      await done;
    }
  }

  Future<_SpokenAudio?> _synthesize(
      String text, PersonaVoice voice, int myTurn) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    try {
      final persona = state.activePersona;
      if (persona == null) return null;
      status = '正在用「${persona.name}」的声音说出来…';
      notifyListeners();
      final r = await VoiceEngine.speakText(
        personaId: persona.id,
        text: t,
        voice: voice,
      );
      if (_disposed || myTurn != _turnId) return null;
      return _SpokenAudio(
        r.toWavBytes(),
        _envelope(r.samples),
        Duration(microseconds: (r.durationSeconds * 1e6).round()),
      );
    } catch (e) {
      debugPrint('[sini:call] 合成失败（跳过这句）：$e');
      return null;
    }
  }

  /// 从合成出来的采样算响度包络 —— 波形画的是真实数据，不是假动画。
  static List<double> _envelope(Float32List samples, {int buckets = 40}) {
    if (samples.isEmpty) return List.filled(buckets, 0);
    final size = (samples.length / buckets).ceil();
    final out = <double>[];
    var peak = 1e-6;
    for (var b = 0; b < buckets; b++) {
      final start = b * size;
      if (start >= samples.length) {
        out.add(0);
        continue;
      }
      final end = math.min(start + size, samples.length);
      var sum = 0.0;
      for (var i = start; i < end; i++) {
        sum += samples[i] * samples[i];
      }
      final rms = math.sqrt(sum / (end - start));
      peak = math.max(peak, rms);
      out.add(rms);
    }
    // 归一化到 0~1，听感上小音量也能看到明显起伏
    return out.map((v) => (v / peak).clamp(0.0, 1.0)).toList();
  }

  /// 开始播一段，返回「播完了」的 Future。播放期间用包络驱动波形。
  Future<void> _play(_SpokenAudio audio, int myTurn) async {
    final player = _player ??= AudioPlayer();
    final c = Completer<void>();
    _playDone = c;

    late StreamSubscription sub;
    sub = player.onPlayerComplete.listen((_) {
      if (!c.isCompleted) c.complete();
    });

    _startEnvelope(audio.envelope, audio.duration);

    try {
      await player.stop();
      await player.play(BytesSource(audio.wav));
    } catch (e) {
      debugPrint('[sini:call] 播放失败：$e');
      if (!c.isCompleted) c.complete();
    }

    await c.future.timeout(
      audio.duration + const Duration(seconds: 20),
      onTimeout: () {},
    );
    await sub.cancel();
    _stopEnvelope();
    if (_disposed || myTurn != _turnId) return;
    aiLevel = 0;
    notifyListeners();
  }

  void _startEnvelope(List<double> env, Duration total) {
    _envTimer?.cancel();
    if (env.isEmpty || total.inMilliseconds <= 0) return;
    final started = DateTime.now();
    _envTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final idx = (elapsed / total.inMilliseconds * env.length).floor();
      if (idx < 0 || idx >= env.length) return;
      aiLevel = env[idx];
      notifyListeners();
    });
  }

  void _stopEnvelope() {
    _envTimer?.cancel();
    _envTimer = null;
  }

  /// 打断：停播、丢弃未播的句子、让正在跑的 LLM 流收尾。
  void _interrupt() {
    _turnId++; // 旧流水线看到轮次变了会自己退出
    _stopPartialLoop();
    _stopPlayback();
    _pendingSentences.clear();
    _allTextReceived = false;
    _wakeSentences();
    _mic.setAiSpeaking(false);
    // 被打断的那句（TA 没说完的）也搬进历史，别凭空消失
    final cur = live;
    if (cur != null && !cur.isUser) {
      cur.partial = false;
      if (cur.text.trim().isNotEmpty) lines.add(cur);
    }
    live = null;
    phase = CallPhase.listening;
    aiLevel = 0;
    notifyListeners();
  }

  void _stopPlayback() {
    _stopEnvelope();
    final c = _playDone;
    if (c != null && !c.isCompleted) c.complete();
    _playDone = null;
    _player?.stop();
    aiLevel = 0;
  }

  void _wakeAll() {
    _wakeSentences();
  }
}
