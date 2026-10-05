import 'package:flutter/foundation.dart';

/// 判断用户是不是在让 AI 画图。
/// 命中条件：出现画图动作词（画/生成/做…张图/draw/paint/generate image 等）
/// 且出现图像目标词（图/图片/插画/海报/image/picture…）。
/// 普通聊天（"分析这张图"这类没有动作词的）不会命中。
bool isImageRequest(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return false;

  final hasAction = RegExp(
    r'(画|繪|绘|生成|做|来|來|给|給|弄|出|创作|創作|设计|設計|painted?|draw|drawing|sketch|generate|create|make|render|imagine)',
  ).hasMatch(t);

  final hasTarget = RegExp(
    r'(图|圖|图片|圖像|图像|插画|插畫|海报|海報|壁纸|壁紙|封面|头像|頭像|logo|图标|圖標|表情包|漫画|漫畫|'
    r'image|picture|photo|illustration|poster|wallpaper|avatar|artwork)',
  ).hasMatch(t);

  if (!hasAction || !hasTarget) return false;

  // 排除明显不是生图的场景：分析/识别/描述已有图片、生成图片文件（.png 下载）等
  final isAnalysis = RegExp(
    r'(分析|识别|識別|描述|看看|这是什么|這是什麼|ocr|识图|讀圖|读图)',
  ).hasMatch(t);
  if (isAnalysis) return false;

  return true;
}

/// 从用户的话里提炼出给图片模型的画面描述（去掉"帮我画一张图"这类指令词）。
/// 提炼结果太短时返回原文，保证提示词不丢信息。
String extractImagePrompt(String text) {
  var s = text.trim();

  // 去掉开头的称呼/指令套话
  s = s.replaceAll(
    RegExp(
      r'^(帮我|幫我|请你|請你|麻烦你|麻煩你|能不能|可以|能否|给我|給我|我要|我想|想让你|想讓你|再|另外|还有|還有)+',
    ),
    '',
  );
  // 去掉画图动作词 + 数量词 + 目标词（如"画一张图片"、"生成个图"）
  s = s.replaceAll(
    RegExp(
      r'^(画|繪|绘|生成|做|来|來|弄|出|创作|創作|设计|設計|painted?|draw|generate|create|make|render)+'
      r'\s*(一|一个|一张|一幅|一张?|个|张|幅|些|几张|幾張|兩張|两张|the|an?|some)?\s*'
      r'(张|張|幅|个|個)?\s*'
      r'(图片|圖像|图像|图|圖|插画|插畫|海报|海報|壁纸|壁紙|封面|头像|頭像|图标|圖標|'
      r'image|picture|photo|illustration|poster|wallpaper|avatar|artwork)?\s*'
      r'(，|,|、|：|:|。|\s)*',
      caseSensitive: false,
    ),
    '',
  );
  // 去掉结尾的语气/格式要求碎片
  s = s.replaceAll(RegExp(r'(吧|呢|啊|呀|哈|谢谢|謝謝|thanks?)+$'), '').trim();

  if (s.length < 4) return text.trim();
  return s;
}

/// 从用户的话里猜画幅比例，返回给图片模型的 size 参数（智谱要求 32 的整数倍）。
String guessImageSize(String text) {
  final t = text.toLowerCase();
  if (RegExp(r'(横屏|横版|宽屏|横向|电脑|桌面|壁纸|壁紙|16:9|风景|風景|全景)').hasMatch(t)) {
    return '1472x1088';
  }
  if (RegExp(r'(竖屏|竖版|纵向|手机|手機|封面|海报|海報|9:16|头像|頭像)').hasMatch(t)) {
    return '1088x1472';
  }
  return '1280x1280';
}

/// 给 AI 的提示：让它知道自己有画图能力（避免它回"我不会画图"）。
const String kImageSystemHint = '''
【画图能力】你有图片生成能力：当用户让你画图/生成图片时，你的回复下方会自动出现真实生成的图片，
所以**绝对不要**说"我不会画图""我无法生成图片""请你去找绘图工具"这类拒绝的话。
正确做法：先用一句符合你人设的口语化短句回应（比如"给你画好了～"），
然后**具体描述**你画了什么（画面主体、风格、配色、氛围），让用户感觉你真的创作了它。
你可以顺带问一句要不要调整（换风格/换配色/加细节）。不要输出占位符、不要输出图片链接。''';

/// 单元测试用（debug 时可在控制台验证规则）
void debugImageIntent(List<String> cases) {
  for (final c in cases) {
    debugPrint(
      '[${isImageRequest(c) ? '命中' : '  '}] $c  → prompt="${extractImagePrompt(c)}" size=${guessImageSize(c)}',
    );
  }
}
