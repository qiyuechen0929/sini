/// 预设音色清单：没有克隆声音时给用户的「现成人设音色」。
///
/// 每个预设 = 一段预生成的参考音频（assets 同目录 mp3）+ 它的文字稿。
/// ZipVoice 是零样本克隆：拿预设参考 + 文字稿，就能用那个音色念任何话。
/// 参考音频只在本机（web/models/presets/），合成全程本地推理。
///
/// ## 参考音频怎么来的（要重做就照这个来）
///
/// 用 **edge-tts**（微软 Azure 神经语音，免费、无需 key）生成，逐条命令：
///
/// ```
/// edge-tts --voice <音色> --rate=<速率> --pitch=<音高> \
///          --text "<下面 promptText 里的原文>" --write-media <file>
/// ```
///
/// 生成后再统一跑一遍 **两遍 loudnorm**（`I=-18:TP=-1.5:LRA=11`，输出
/// 24kHz / 单声道 / 48kbps mp3）——不同音色原始响度能差 7dB，不归一化的话
/// 用户在试听列表里点来点去会觉得「忽大忽小」。
///
/// 三条经验（踩过）：
///  1. **参考文字必须逐字等于音频内容**，多一个字都会让克隆明显跑偏。
///  2. **口语化的短句**（有语气词、疑问、停顿）比书面长句更像人——旧版写的
///     是「这个项目从今天起由我负责」这种公文腔，听感就是「机器念稿」。
///  3. **长度控制在 5~9 秒**：太短模型不稳，太长合成变慢且容易糊。
library;

import 'dart:typed_data';

import 'audio_pcm.dart';
import 'preset_audio.dart';

/// 参考音频版本号。
///
/// 换了音频内容就把这个数 +1：文件名保持不变，只在 URL 后面挂 `?v=`，
/// 用来绕过浏览器对 mp3 的强缓存（否则用户听到的还是旧音频）。
const int kPresetAudioVersion = 2;

class VoicePreset {
  final String id;
  final String label;
  final String desc;
  final String gender;
  final String file;

  /// 参考音频对应的文字（零样本克隆必需，必须逐字一致）
  final String promptText;

  const VoicePreset({
    required this.id,
    required this.label,
    required this.desc,
    required this.gender,
    required this.file,
    required this.promptText,
  });
}

/// 创建页第五步的选择项（顺序即展示顺序）
///
/// 音色对照（edge-tts voice / rate / pitch）：
/// - 霸道总裁 → zh-CN-YunjianNeural / -6% / -8Hz
/// - 阳光男孩 → zh-CN-YunxiNeural  / +10% / +6Hz
/// - 俏皮萌妹 → zh-CN-XiaoyiNeural / +6% / +14Hz
/// - 清冷御姐 → zh-CN-XiaoxiaoNeural / -12% / -8Hz
/// - 温柔女声 → zh-CN-XiaoxiaoNeural / -3% / +3Hz
/// - 沉稳青年 → zh-CN-YunyangNeural / -6% / -2Hz
///
/// 注意：edge-tts 的 zh-CN 标准音色只有 5 个（Xiaoxiao/Xiaoyi/Yunxi/Yunjian/
/// Yunyang），所以「清冷御姐」和「温柔女声」共用 Xiaoxiao——靠音高（差 11Hz）
/// 和语速（差 9%）拉开区别。其余两条是方言音色，不适合当通用人设。
const List<VoicePreset> kVoicePresets = [
  VoicePreset(
    id: 'bazongzi',
    label: '霸道总裁',
    desc: '低沉强势，说一不二',
    gender: 'male',
    file: 'bazongzi.wav',
    promptText: '行，这事就这么定了，别再讨论。你要是不服，就拿结果来说话。',
  ),
  VoicePreset(
    id: 'yangguang',
    label: '阳光男孩',
    desc: '明亮爽快，元气满满',
    gender: 'male',
    file: 'yangguang.wav',
    promptText: '嘿！今天天气也太好了吧！走走走，别宅着了，咱们出去打会儿球，出出汗多痛快！',
  ),
  VoicePreset(
    id: 'mengmei',
    label: '俏皮萌妹',
    desc: '软糯娇俏，元气甜甜',
    gender: 'female',
    file: 'mengmei.wav',
    promptText: '哇，这个蛋糕看着也太好吃了吧！我们一人一半好不好？不行不行，我要大的那半，你让着我嘛。',
  ),
  VoicePreset(
    id: 'yujie',
    label: '清冷御姐',
    desc: '从容冷静，气场全开',
    gender: 'female',
    file: 'yujie.wav',
    promptText: '你不用急着解释。我听的不是你说什么，而是你做什么。想清楚了，再来找我。',
  ),
  VoicePreset(
    id: 'wenrou',
    label: '温柔女声',
    desc: '轻声细语，暖心体贴',
    gender: 'female',
    file: 'wenrou.wav',
    promptText: '今天辛苦啦，我给你煮了点汤，趁热喝。工作再忙，也要记得好好吃饭，好好照顾自己。',
  ),
  VoicePreset(
    id: 'chenwen',
    label: '沉稳青年',
    desc: '平和可靠，娓娓道来',
    gender: 'male',
    file: 'chenwen.wav',
    promptText: '人生就像一场旅行，重要的不是目的地，而是沿途的风景。慢一点也没关系，我们总会到的。',
  ),
];

VoicePreset? voicePresetById(String id) {
  for (final p in kVoicePresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// 拉取并解码预设参考音频（结果不大，做内存缓存避免重复合成时反复拉取）。
///
/// 读取方式分平台：Web 走 HTTP（带 `?v=` 破缓存），手机走 asset。
/// 见 `preset_audio.dart`。
final Map<String, DecodedAudio> _presetRefCache = {};

Future<DecodedAudio?> loadPresetRefAudio(VoicePreset preset) async {
  if (_presetRefCache.containsKey(preset.id)) {
    return _presetRefCache[preset.id];
  }
  final bytes = await loadPresetAudioBytes(preset.file);
  if (bytes == null) return null;
  final d = await decodeAudioBytes(bytes);
  if (d != null) _presetRefCache[preset.id] = d;
  return d;
}
