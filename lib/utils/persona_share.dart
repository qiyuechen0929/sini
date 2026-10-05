import 'dart:convert';

import '../models.dart';

/// 人格分享包：把一个养了很久的人格连同「养成痕迹」打包成 JSON，
/// 朋友拿到后可以导入成自己的新人格（导入端为后续版本）。
///
/// 隐私边界：
/// - 剔除 ownerName（用户对 TA 的称呼）、voice（克隆音色涉及本人声纹）；
/// - 记忆 / 描述里的手机号、身份证号自动替换成「[已隐去]」。
/// 保留的正是"养成感"：关系、认识时间、性格维度、从聊天里学到的语言
/// 风格（口头禅 / 句式 / 样例对话 / 反应模式）、长期记忆及其被回忆次数。

const String kShareKind = 'sini_persona_share';
const int kShareVersion = 1;

final RegExp _phoneRe = RegExp(r'1[3-9]\d{9}');
final RegExp _idCardRe = RegExp(r'\d{17}[\dXx]');

/// 数字类隐私打码：手机号（11 位）/ 身份证号（18 位）
String scrubPrivacy(String text) {
  var t = text.replaceAll(_idCardRe, '[已隐去]');
  t = t.replaceAll(_phoneRe, '[已隐去]');
  return t;
}

/// 组装分享包。[messageCount] 是这个人格名下的历史消息总数（养成感核心数据）。
Map<String, dynamic> exportPersonaPackage(
  Persona p, {
  required int messageCount,
}) {
  final personaJson = Map<String, dynamic>.from(p.toJson());
  personaJson.remove('ownerName');
  personaJson.remove('voice'); // 声纹隐私，不随卡分享
  // 描述与记忆文本过一遍隐私打码
  personaJson['description'] = scrubPrivacy(p.description);
  personaJson['memory'] = p.memory
      .map((m) => m.copyWith(text: scrubPrivacy(m.text)).toJson())
      .toList();

  return {
    'app': 'sini',
    'kind': kShareKind,
    'version': kShareVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'stats': {
      'messageCount': messageCount,
      'memoryCount': p.memory.length,
      'styleMessageCount': p.style?.messageCount ?? 0,
      'sampleLineCount': p.style?.sampleLines.length ?? 0,
      'exchangeCount': p.style?.exchanges.length ?? 0,
      'catchphraseCount': p.style?.catchphrases.length ?? 0,
    },
    'persona': personaJson,
  };
}

/// 分享包 → 好友间传的文本（复制导入码 / 文件内容都是它）
String encodePersonaPackage(Map<String, dynamic> pkg) =>
    jsonEncode(pkg);

/// 尽力解析一份分享包 JSON；格式不对返回 null。
Map<String, dynamic>? tryParsePersonaPackage(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic>) return null;
    if (j['kind'] != kShareKind) return null;
    if (j['persona'] is! Map<String, dynamic>) return null;
    return j;
  } catch (_) {
    return null;
  }
}
