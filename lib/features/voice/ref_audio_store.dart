/// 克隆参考音频的本机持久化（IndexedDB，仅 Web）。
///
/// 为什么存：聊天页「播放」要用 TA 的声音朗读回复，零样本克隆必须有
/// 参考音频。原来「样本用完即弃」的设计只考虑了克隆页场景；要让
/// 「TA 用自己的声音说话」成立，参考音频必须留在本机。
/// 隐私边界不变：只存本机（IndexedDB），绝不上传。
///
/// 存的是 16-bit WAV 字节（单声道、样本自带的采样率），读取后走
/// AudioContext 解码，与克隆页同一条解码路径。
library;

import 'dart:typed_data';

import 'ref_audio_store_stub.dart'
    if (dart.library.indexed_db) 'ref_audio_store_web.dart' as impl;

class RefAudioStore {
  RefAudioStore._();

  /// 保存某人格的参考音频（WAV 字节）。同一 personaId 覆盖写。
  static Future<void> save(String personaId, Uint8List wavBytes) =>
      impl.save(personaId, wavBytes);

  /// 读取参考音频；没有则返回 null。
  static Future<Uint8List?> load(String personaId) => impl.load(personaId);

  /// 删除（撤销授权时一并清掉）。
  static Future<void> delete(String personaId) => impl.delete(personaId);
}
