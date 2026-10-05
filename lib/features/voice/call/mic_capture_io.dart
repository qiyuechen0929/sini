/// 非 Web（Android / iOS / 桌面）的麦克风采集实现，用 `record` 包拿 PCM 流。
///
/// 为什么不用浏览器那套：手机上没有 AudioWorklet，必须用原生录音能力。
/// `record` 能以 **PCM16 / 16kHz / 单声道** 吐流，正好是我们 VAD 和 Whisper
/// 要的格式，不用再转码。
///
/// 和 Web 实现对外**接口完全一致**（start / take / peek / drop / mute / stop），
/// 所以 `mic_capture.dart` 里的 VAD 状态机一行都不用改。
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

class MicBackend {
  MicBackend._();

  static final AudioRecorder _rec = AudioRecorder();
  static StreamSubscription<Uint8List>? _sub;

  /// 累积的 PCM 缓冲（16kHz Int16），供 take / peek 取用
  static final List<Int16List> _chunks = [];
  static int _samples = 0;

  /// 一个音频块 = 1024 个采样（约 64ms），和 Web 侧保持一致，
  /// 这样 VAD 的阈值和计时不用分平台调。
  static const int _blockSamples = 1024;
  static const int _maxSamples = 16000 * 30; // 最多留 30 秒

  /// 正在攒的这一块（凑满 _blockSamples 才算一次响度回调）
  static final Int16List _block = Int16List(_blockSamples);
  static int _blockLen = 0;

  /// 不足两个字节的零头（PCM16 是 2 字节一个采样，原生给的 chunk 长度不保证偶）
  static int _oddByte = -1;

  static void Function(double rms)? _onLevel;

  static bool get available => true; // 移动端都支持；权限在 start 时申请

  static RecordConfig get _config => const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        // 通话是外放 + 麦克风同时工作，没有回声消除会把 TA 的声音录回去
        echoCancel: true,
        autoGain: true,
      );

  static Future<void> start(void Function(double rms) onLevel) async {
    // record 7.x：hasPermission(request: true) 会弹系统权限框
    final granted = await _rec.hasPermission(request: true);
    if (!granted) throw StateError('麦克风权限被拒绝了');
    _reset();
    _onLevel = onLevel;
    await _sub?.cancel();
    final stream = await _rec.startStream(_config);
    _sub = stream.listen(_onData, onError: (_) {});
  }

  static void _onData(Uint8List raw) {
    var i = 0;
    if (_oddByte >= 0 && raw.isNotEmpty) {
      _pushSample(_oddByte | (raw[0] << 8));
      _oddByte = -1;
      i = 1;
    }
    for (; i + 1 < raw.length; i += 2) {
      _pushSample(raw[i] | (raw[i + 1] << 8)); // 小端
    }
    if (i < raw.length) _oddByte = raw[i];
  }

  static void _pushSample(int v) {
    final s = v >= 32768 ? v - 65536 : v; // 补码还原
    // 存进缓冲（给 take / peek 用）
    if (_chunks.isEmpty || _chunks.last.length >= 8192) {
      _chunks.add(Int16List(8192));
      _tailLen = 0;
    }
    _chunks.last[_tailLen++] = s;
    _samples++;
    while (_samples > _maxSamples && _chunks.length > 1) {
      final dropped = _chunks.removeAt(0);
      _samples -= dropped.length;
      if (_tailLen > dropped.length) {
        _tailLen -= dropped.length;
      }
    }

    // 攒够一块就算一次响度
    _block[_blockLen++] = s;
    if (_blockLen >= _blockSamples) {
      var sum = 0.0;
      for (var k = 0; k < _blockSamples; k++) {
        final x = _block[k] / 32768.0;
        sum += x * x;
      }
      _blockLen = 0;
      _onLevel?.call(math.sqrt(sum / _blockSamples));
    }
  }

  /// 最后一个 chunk 已经写了多少个采样
  static int _tailLen = 0;

  static void _reset() {
    _chunks.clear();
    _samples = 0;
    _tailLen = 0;
    _blockLen = 0;
    _oddByte = -1;
  }

  /// 取走缓冲里的全部音频并清空。
  static Float32List? take() {
    if (_samples <= 0) return null;
    final out = Float32List(_samples);
    var o = 0;
    for (var ci = 0; ci < _chunks.length; ci++) {
      final c = _chunks[ci];
      final n = (ci == _chunks.length - 1) ? _tailLen : c.length;
      for (var i = 0; i < n && o < out.length; i++) {
        out[o++] = c[i] / 32768.0;
      }
    }
    _reset();
    return out;
  }

  /// 看一眼缓冲尾部最多 [maxSamples] 个采样，不清空。
  static Float32List? peek(int maxSamples) {
    if (_samples <= 0) return null;
    final total = _samples;
    var skip = 0;
    var take = total;
    if (maxSamples > 0 && total > maxSamples) {
      skip = total - maxSamples;
      take = maxSamples;
    }
    final out = Float32List(take);
    var pos = 0; // 已经数过的采样数
    var o = 0;
    for (var ci = 0; ci < _chunks.length && o < take; ci++) {
      final c = _chunks[ci];
      final n = (ci == _chunks.length - 1) ? _tailLen : c.length;
      for (var i = 0; i < n && o < take; i++, pos++) {
        if (pos < skip) continue;
        out[o++] = c[i] / 32768.0;
      }
    }
    return out;
  }

  static void drop() => _reset();

  static Future<void> mute(bool v) async {
    if (v) {
      await _sub?.cancel();
      _sub = null;
      if (await _rec.isRecording()) await _rec.stop();
      _reset();
      return;
    }
    final stream = await _rec.startStream(_config);
    await _sub?.cancel();
    _sub = stream.listen(_onData, onError: (_) {});
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (await _rec.isRecording()) {
      await _rec.stop();
    }
    _reset();
    _onLevel = null;
  }

  static int get sampleRate => 16000;
}
