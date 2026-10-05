/// 麦克风采集 + VAD（端点检测）门面。
///
/// 语音通话的「耳朵」：把麦克风音频降采样成 16kHz 单声道 PCM，并且**在本地
/// 判断用户什么时候开口、什么时候说完**，不需要用户按键。
///
/// 分工：
///  - 平台层（[MicBackend]，Web 用 AudioWorklet）只负责「拿到音频 + 每 ~64ms
///    回一个响度 RMS + 缓存 PCM」，不懂业务。
///  - VAD 状态机是纯 Dart（[VadGate]），参数好调、也能单测。
///
/// 为什么不能直接用浏览器的 Web Speech API：那个会把音频传到云端，而这个项目
/// 的承诺是「录音全程在本机处理、不上传」。所以这里只做采集，识别交给端侧的
/// sherpa-onnx Whisper（见 `asr_engine.dart`）。
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'mic_capture_stub.dart'
    if (dart.library.io) 'mic_capture_io.dart'
    if (dart.library.js_interop) 'mic_capture_web.dart' as impl;

/// 采集与识别统一的采样率。
const int kMicSampleRate = 16000;

/// VAD 可调参数。默认值是按「真人打电话」的体感调的，改之前先想清楚代价。
class VadTuning {
  /// 连续几个音频块超过进入阈值才算「开口」（块约 64ms）
  final int startHold;

  /// 低于退出阈值持续这么久算「说完」
  final int endSilenceMs;

  /// AI 正在播报时，要持续开口这么久才允许打断
  final int bargeInMs;

  /// 绝对噪声底：环境再安静也不低于这个值
  final double floor;

  /// 进入阈值 = max(floor, 噪声底 × gain)
  final double gain;

  /// 退出阈值 = 进入阈值 × 这个系数（双阈值，防抖）
  final double exitRatio;

  /// AI 播报时进入阈值再乘这个（抑制外放回声误触）
  final double speakingGain;

  /// 这么久没有一块超过进入阈值就强制收尾
  /// （自动增益把环境底噪抬起来时靠它兜底，不然会一直卡在「说话中」）
  final int watchdogMs;

  /// 短于这个时长的话音当作噪声丢弃（咳嗽 / 碰撞）
  final int minSpeechMs;

  /// 长于这个时长强制收尾（避免对着麦克风碎碎念把缓冲撑爆）
  final int maxSpeechMs;

  const VadTuning({
    this.startHold = 2,
    this.endSilenceMs = 700,
    this.bargeInMs = 800,
    this.floor = 0.006,
    this.gain = 3.2,
    this.exitRatio = 0.62,
    this.speakingGain = 3.3,
    this.watchdogMs = 1600,
    this.minSpeechMs = 300,
    this.maxSpeechMs = 30000,
  });
}

enum VadEvent { none, speechStart, speechEnd }

/// [VadGate.push] 的返回值。
class VadSignal {
  const VadSignal(this.event, {this.bargeIn = false});

  final VadEvent event;

  /// 这次「开口」是不是在 AI 播报时插话（调用方应立刻停播）
  final bool bargeIn;

  static const VadSignal none = VadSignal(VadEvent.none);
}

/// VAD 状态机（纯逻辑，可单测）。
///
/// 三个关键设计（照抄「打电话」的体感，不要随便改）：
///  1. **双阈值**：进入用高阈值、退出用低阈值（[VadTuning.exitRatio]），
///     否则响度悬在临界值上会疯狂抖动、句子被切碎。
///  2. **AI 说话时抬高门槛**（[VadTuning.speakingGain]）：外放的声音会被麦克风
///     收回去，不抬高就会自己把自己打断。
///  3. **打断要保持一段时间**（[VadTuning.bargeInMs]）：呼吸、咳嗽、桌面震动
///     都是短促的，真人插话能撑过 0.8 秒。
class VadGate {
  VadGate({this.tuning = const VadTuning()});

  final VadTuning tuning;

  double _noise = 0.01;
  double _speechMin = 1;
  int _hot = 0;
  int _hotSinceMs = 0;
  int _silenceSinceMs = 0;
  int _lastHotAtMs = 0;
  int _speechStartMs = 0;

  bool speaking = false;
  bool aiSpeaking = false;

  /// 最近一次开口发生的时刻（判断这段话音多长用）
  int get speechStartMs => _speechStartMs;

  /// 当前自适应出来的噪声底（调试 / 展示用）
  double get noiseFloor => _noise;

  void reset() {
    _hot = 0;
    _hotSinceMs = 0;
    _silenceSinceMs = 0;
    _lastHotAtMs = 0;
    _speechStartMs = 0;
    speaking = false;
    _noise = 0.01;
    _speechMin = 1;
  }

  /// 喂一个音频块的响度，返回这一步发生的状态变化。
  VadSignal push(double rms, int nowMs) {
    // 先按当前噪声底算这一块的阈值
    var enter = math.max(tuning.floor, _noise * tuning.gain);
    if (aiSpeaking) enter *= tuning.speakingGain;
    final exit = enter * tuning.exitRatio;

    // 噪声底只在「明显不是人声」的块上更新（rms 低于当前阈值时）。
    //
    // ⚠️ 这一条是踩过坑的：如果像常见写法那样「只要没判定在说话就更新噪声底」，
    // 持续说话时噪声底会一路追着人声往上涨，阈值被顶飞 —— 表现是
    // ① 说着说着突然被判成「说完了」；② AI 播报时用户插话永远触发不了
    // （等不到 bargeInMs，阈值已经涨到人声之上）。
    if (!speaking) {
      if (rms < enter) _noise = _noise * 0.97 + rms * 0.03;
    } else {
      _speechMin = math.min(_speechMin, rms);
      _noise = math.min(_noise * 1.0015, math.max(_noise, _speechMin));
    }

    if (rms > enter) _lastHotAtMs = nowMs;

    if (!speaking) {
      if (rms > enter) {
        _hot++;
        if (_hotSinceMs == 0) _hotSinceMs = nowMs;
        if (_hot >= tuning.startHold) {
          // AI 正在播报时要撑够 bargeInMs 才算插话
          final need = aiSpeaking ? tuning.bargeInMs : 0;
          if (nowMs - _hotSinceMs >= need) {
            final barge = aiSpeaking;
            speaking = true;
            _hot = 0;
            _hotSinceMs = 0;
            _silenceSinceMs = 0;
            _speechStartMs = nowMs;
            _lastHotAtMs = nowMs;
            _speechMin = 1;
            return VadSignal(VadEvent.speechStart, bargeIn: barge);
          }
        }
      } else {
        _hot = 0;
        _hotSinceMs = 0;
      }
      return VadSignal.none;
    }

    // 说话中
    if (nowMs - _speechStartMs >= tuning.maxSpeechMs) {
      return _end();
    }
    if (rms < exit) {
      if (_silenceSinceMs == 0) {
        _silenceSinceMs = nowMs;
      } else if (nowMs - _silenceSinceMs >= tuning.endSilenceMs) {
        return _end();
      }
    } else {
      _silenceSinceMs = 0;
    }
    if (_lastHotAtMs != 0 && nowMs - _lastHotAtMs >= tuning.watchdogMs) {
      return _end();
    }
    return VadSignal.none;
  }

  VadSignal _end() {
    speaking = false;
    _silenceSinceMs = 0;
    _hot = 0;
    _hotSinceMs = 0;
    return const VadSignal(VadEvent.speechEnd);
  }
}

/// 一次通话的麦克风句柄：把平台层的音频块喂给 [VadGate]，并在判定
/// 「说完」时把这段音频整段交出来。
class MicCapture {
  MicCapture({VadTuning tuning = const VadTuning()})
      : _gate = VadGate(tuning: tuning);

  final VadGate _gate;

  /// 实时响度（0~1），用来画波形
  void Function(double rms)? onLevel;

  /// 开口 / 收尾状态变化
  void Function(bool speaking)? onSpeechChanged;

  /// 识别到一整句（已去静音、已重采样到 [kMicSampleRate]）
  void Function(Float32List samples)? onUtterance;

  /// AI 正在播报时用户插话（调用方应立刻停播）
  void Function()? onBargeIn;

  /// 采集失败（没权限 / 没有设备）
  void Function(String message)? onError;

  bool _running = false;
  bool _muted = false;
  final _clock = Stopwatch();

  bool get running => _running;
  bool get muted => _muted;
  bool get speaking => _gate.speaking;

  /// 当前环境能不能采集（Web + getUserMedia）
  static bool get available => impl.MicBackend.available;

  /// 打开麦克风。拿不到权限会抛异常，同时回调 [onError] 给一句人话。
  Future<void> start() async {
    if (_running) return;
    try {
      await impl.MicBackend.start(_onBlock);
      _running = true;
      _clock
        ..reset()
        ..start();
      _gate.reset();
    } catch (e) {
      onError?.call(_friendly(e));
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _clock.stop();
    _gate.reset();
    await impl.MicBackend.stop();
  }

  /// 静音：真的把音轨停掉（浏览器麦克风指示灯会灭），不是假装听不见。
  Future<void> setMuted(bool v) async {
    if (_muted == v) return;
    _muted = v;
    await impl.MicBackend.mute(v);
    if (v && _gate.speaking) {
      _gate.speaking = false;
      onSpeechChanged?.call(false);
    }
  }

  /// 告诉 VAD「AI 正在说话」——用来抬高门槛，避免外放被当成用户插话。
  void setAiSpeaking(bool v) => _gate.aiSpeaking = v;

  /// 丢弃当前缓冲里已经收到的音频（比如这轮结束后把残留的环境音清掉）。
  void discard() {
    impl.MicBackend.drop();
    _gate.reset();
  }

  /// 看一眼当前缓冲里的音频但不清空 —— 增量识别（实时字幕）用。
  ///
  /// [maxSeconds] 只取尾部这么久，避免说越久识别越慢。
  Float32List? peekAudio({double maxSeconds = 12}) {
    if (!_running) return null;
    return impl.MicBackend.peek((kMicSampleRate * maxSeconds).round());
  }

  // ── 每个音频块（约 64ms）来一次 ────────────────────────────────────────
  void _onBlock(double rms) {
    if (!_running || _muted) {
      onLevel?.call(0);
      return;
    }
    onLevel?.call(rms.clamp(0.0, 1.0));

    final sig = _gate.push(rms, _clock.elapsedMilliseconds);
    switch (sig.event) {
      case VadEvent.none:
        break;
      case VadEvent.speechStart:
        onSpeechChanged?.call(true);
        if (sig.bargeIn) onBargeIn?.call();
      case VadEvent.speechEnd:
        onSpeechChanged?.call(false);
        _takeUtterance();
    }
  }

  void _takeUtterance() {
    final durMs = _clock.elapsedMilliseconds - _gate.speechStartMs;
    final raw = impl.MicBackend.take();
    if (raw == null || raw.isEmpty) return;
    if (durMs < _gate.tuning.minSpeechMs) return; // 太短当噪声丢掉

    final trimmed = trimSilence(raw);
    final minLen = kMicSampleRate * _gate.tuning.minSpeechMs ~/ 1000;
    if (trimmed.length < minLen) return;
    onUtterance?.call(trimmed);
  }

  static String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('NotAllowedError') || s.contains('Permission')) {
      return '麦克风权限被拒绝了。请在浏览器地址栏的权限设置里允许麦克风后重试。';
    }
    if (s.contains('NotFoundError') || s.contains('DevicesNotFound')) {
      return '没找到可用的麦克风设备。';
    }
    if (s.contains('NotReadableError')) {
      return '麦克风被其它程序占用了（比如会议软件），关掉再试。';
    }
    return '打不开麦克风：$s';
  }
}

/// 去掉首尾静音：按 20ms 一帧算能量，掐掉开头/结尾没有话音的部分。
///
/// 不掐的话，一段「说完后愣了几秒」的录音会把整段静音一起喂给 Whisper ——
/// 既慢又容易让它产生幻觉文本。
Float32List trimSilence(Float32List pcm, {double floor = 0.008}) {
  const frame = kMicSampleRate ~/ 50; // 20ms
  if (pcm.length <= frame * 2) return pcm;

  double frameRms(int i) {
    var sum = 0.0;
    final end = math.min(i + frame, pcm.length);
    for (var k = i; k < end; k++) {
      sum += pcm[k] * pcm[k];
    }
    return math.sqrt(sum / (end - i));
  }

  var first = -1;
  for (var i = 0; i + frame <= pcm.length; i += frame) {
    if (frameRms(i) > floor) {
      first = i;
      break;
    }
  }
  if (first < 0) return Float32List(0);

  var last = pcm.length;
  for (var i = pcm.length - frame; i >= first; i -= frame) {
    if (frameRms(i) > floor) {
      last = math.min(pcm.length, i + frame);
      break;
    }
  }

  // 前后各留一点余量，别把起音的辅音削掉
  final start = math.max(0, first - frame);
  final end = math.min(pcm.length, last + frame * 2);
  if (end <= start) return Float32List(0);
  return Float32List.sublistView(pcm, start, end);
}
