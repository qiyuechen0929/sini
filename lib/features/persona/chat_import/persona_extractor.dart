/// 把聊天记录「取证」成结构化风格画像。
///
/// 两条路径：
///  1. [extractStyleWithLlm]：有模型时，把**真实统计 + 原话样本 + 真实问答对**
///     一起喂给 LLM，让它输出结构化 JSON。这是"像"的主要来源。
///  2. [buildStyleFromStats]：没配模型时，纯本地统计拼一份简版画像，
///     保证功能可用（相似度低一些，但绝不假报成功）。
///
/// prompt 设计要点（直接决定复刻效果，改动前请先读）：
///  - 明确要求「取证」而不是「创作」：不许美化、不许脑补、不许写人设作文；
///  - sampleLines 必须**原文照抄**——这是后面注入 prompt 当范例的，
///    一旦被模型改写就失去了"像本人"的意义；
///  - 要求指出"从不怎么说话"（donts），负向约束对像不像同样关键；
///  - 所有结论都要能从给出的语料里找到依据。
library;

import 'dart:convert';

import '../../../data/llm_provider.dart';
import '../../../models.dart';
import 'chat_models.dart';
import 'chat_stats.dart';

class ExtractResult {
  final PersonaStyle? style;
  /// 四个性格维度的建议值（0~1），由证据推出，用户可再改
  final Map<String, double> traits;
  /// 从记录里抽到的长期记忆（共同经历、事实）
  final List<Map<String, String>> memories;
  /// TA 对用户的关系推测（朋友 / 恋人 / 家人 …）
  final String relationshipGuess;
  /// 认识时间推测（如 "2021"）
  final String sinceGuess;
  final String? error;
  final String? raw;

  const ExtractResult({
    this.style,
    this.traits = const {},
    this.memories = const [],
    this.relationshipGuess = '',
    this.sinceGuess = '',
    this.error,
    this.raw,
  });

  bool get ok => error == null && style != null;
}

/// 取样规模：控制 token 消耗，同时保证风格特征够收敛。
const int _kSampleLines = 160;
const int _kSampleExchanges = 28;

Future<ExtractResult> extractStyleWithLlm({
  required ModelConfig cfg,
  required ParsedChat chat,
  required ChatStats stats,
}) async {
  final taName = stats.taName.isEmpty ? 'TA' : stats.taName;
  final samples = sampleTaMessages(chat.messages, max: _kSampleLines);
  final exchanges = sampleExchanges(chat.messages, max: _kSampleExchanges);

  if (samples.isEmpty) {
    return const ExtractResult(error: '没有可用于分析的消息');
  }

  final prompt = StringBuffer();
  prompt.writeln('你的任务：对一份真实聊天记录做**语言风格取证**，输出结构化画像，'
      '供一个数字人格系统模仿「$taName」的说话方式。');
  prompt.writeln();
  prompt.writeln('【一、客观统计（已由程序算好，直接采信）】');
  prompt.writeln(stats.toPromptBlock());

  prompt.writeln('【二、$taName 的原话样本（共 ${samples.length} 条，按时间顺序）】');
  for (final s in samples) {
    prompt.writeln('· ${_oneLine(s)}');
  }

  if (exchanges.isNotEmpty) {
    prompt.writeln();
    prompt.writeln('【三、真实对话片段（用户 → $taName 的真实反应）】');
    for (final e in exchanges) {
      prompt.writeln('用户：${_oneLine(e.user)}');
      prompt.writeln('$taName：${_oneLine(e.ta)}');
    }
  }

  prompt.writeln();
  prompt.writeln('''
【输出要求】
只输出一个 JSON 对象，不要任何解释、不要 markdown 代码块。字段如下：

{
  "summary": "一句话概括 TA 的说话风格（≤40字，要具体，比如'句子极短、爱用省略号、几乎不用句号'）",
  "catchphrases": ["口头禅，必须是上面语料里真实出现过、而且出现**至少两次**的短词（2~4字，如\\"嗯嗯\\"\\"好吧\\"\\"真的假的\\"）。不要拿一整句话充当口头禅。3-8个，没有就给空数组"],
  "callUser": "TA 怎么称呼用户（如\\"你\\"、\\"宝宝\\"、\\"老张\\"；没观察到就空字符串）",
  "selfCall": "TA 怎么自称（没观察到就空字符串）",
  "nicknames": ["对用户的昵称/外号，没有就空数组"],
  "speechHabits": ["具体说话习惯，4-8条，比如\\"几乎不用句号\\"、\\"句子很短，常只有两三个字\\"、\\"爱用～结尾\\"、\\"常连发两条\\""],
  "emojiHabit": "表情符号/颜文字使用习惯（不用就写\\"几乎不用表情\\"）",
  "lengthHabit": "长度习惯描述（结合统计里的平均字数）",
  "sampleLines": ["从上面样本里挑选最能代表 TA 语感的原话，原样照抄，不要改写，12-20条"],
  "interests": ["TA 常聊的话题/兴趣，3-8个"],
  "emotionalPattern": "情绪表达模式：开心时怎么说话、生气/不满时怎么说话、关心对方时怎么说话",
  "reactionPatterns": [
    {"when": "触发情境，一句话，如\\"对方调侃或质疑时\\"",
     "how": "TA 的典型反应，必须写清**情绪走向**：是服软认错 / 反问试探 / 敷衍顺从 / 主动表态 / 玩笑式回击 / 直接给方案 / 顺着说…",
     "userSaid": "这种情况下对方说的话，照抄原话",
     "example": "TA 当时回的那句话，照抄原话"}
  ],
  "dos": ["模仿时必须做到的，3-6条"],
  "donts": ["绝对不能出现的表达/语气，3-6条；要针对TA这个人，比如\\"不要用书面语\\"、\\"别用感叹号\\"、\\"不要长篇大论\\""],
  "topWords": ["从高频词候选里筛出真正有代表性的词，5-15个"],
  "traits": {"warmth": 0.0, "rationality": 0.0, "initiative": 0.0, "humor": 0.0},
  "relationshipGuess": "TA 和用户最可能是什么关系（恋人/朋友/家人/同学/同事/师长…，只选一个词）",
  "sinceGuess": "两人大概从哪一年开始有大量聊天（如 2021；判断不了就空字符串）",
  "memories": [{"text": "值得长期记住的事实或共同经历，一句话", "kind": "fact"}]
}

【硬性规则】
1. 所有结论必须能从上面语料里找到依据。**不确定就留空**，绝对不要编造。
2. sampleLines 必须逐字照抄原样本，禁止润色、补标点、改错别字。
3. traits 四个值：warmth(温柔度)/rationality(理性度)/initiative(主动性)/humor(幽默感)，
   取 0~1 小数，要贴合观察到的证据（比如几乎不主动起话题 → initiative 给 0.2 左右）。
4. summary/speechHabits/donts 要**具体到这个人的特点**，
   禁止出现"性格开朗""善于倾听""很有亲和力"这类放到谁身上都成立的废话。
5. memories 最多 12 条，只写能长期复用的事实（共同经历、重要日期、喜好），
   日常寒暄不要写。
6. **reactionPatterns 是最重要的字段**，给 5-9 条，覆盖常见情境
   （被夸、被调侃、被质疑、对方生气说狠话、对方关心或唠叨、对方提问、需要做安排时…）。
   它记录的是「面对这类话，TA 会往哪个方向接」——这是"性格"最直接的体现。
   举例说明这个字段的价值：同样是回应"我小气，你别来了"，
   有人会怼回去、有人会反问"生气啦？"、有人会直接服软说"我错了嘛"——**反应方向不同，就是不同的人**。
   用词、句长、标点都模仿对了，只要反应方向错，一眼就不像。
   所以每条 how 必须写清情绪走向（服软/反问/敷衍/主动/对抗/玩笑回击…），
   且必须配一条语料里的原话作为 example。
   userSaid 必须是**紧挨着那句 example 之前**、对方真实说过的那句话；
   **不同条目不要复用同一句 userSaid**（实在对不出前后关系就留空字符串，
   宁可少给一个锚点，也不要编一个错的对应关系）。
7. catchphrases 只收 **2~4 字的短词**，并且要在语料里出现过**至少两次**。
   拿一整句话（比如"不管怎么样都要查"）冒充口头禅会让画像失真——
   样本少的时候特别容易这样，宁可只给两三个，也不要凑数。
8. 如果语料里 TA 的回复经常和对方上一句**没什么关系**（跳话题、只挑自己关心的点说），
   这本身就是重要的性格特征，请写进 reactionPatterns 或 speechHabits，
   并用 donts 明确"不要有问必答、不要硬接话"。''');

  final res = await chatComplete(
    cfg: cfg,
    messages: <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '你是一名严谨的语言风格取证分析师。你只根据给定语料下结论，'
            '从不编造，也从不使用空泛的套话。你只输出 JSON。',
      },
      {'role': 'user', 'content': prompt.toString()},
    ],
    temperature: 0.3, // 取证要稳，不要发挥
    maxTokens: 4096,
  );

  if (!res.ok || res.content == null || res.content!.trim().isEmpty) {
    return ExtractResult(error: res.error ?? '模型没有返回内容');
  }

  final parsed = parseLooseJson(res.content!);
  if (parsed == null) {
    return ExtractResult(error: '模型的返回不是合法 JSON', raw: res.content);
  }

  // 「情境 → 反应」：性格的核心，单独解析
  final rawParsed = <ReactionPattern>[];
  final rawReactions = parsed['reactionPatterns'];
  if (rawReactions is List) {
    for (final r in rawReactions.take(12)) {
      if (r is! Map) continue;
      final rp = ReactionPattern.fromJson({
        'when': _str(r['when']),
        'how': _str(r['how']),
        'example': _str(r['example'] ?? r['exampleLine'] ?? r['sample']),
        'userSaid': _str(r['userSaid'] ?? r['user_said'] ?? r['trigger']),
      });
      if (!rp.isEmpty) rawParsed.add(rp);
    }
  }
  final reactions = dedupeReactionTriggers(rawParsed);

  final style = PersonaStyle(
    summary: _str(parsed['summary']),
    catchphrases: _strList(parsed['catchphrases'], 12),
    callUser: _str(parsed['callUser']),
    selfCall: _str(parsed['selfCall']),
    nicknames: _strList(parsed['nicknames'], 10),
    speechHabits: _strList(parsed['speechHabits'], 10),
    emojiHabit: _str(parsed['emojiHabit']),
    lengthHabit: _str(parsed['lengthHabit']),
    sampleLines: _strList(parsed['sampleLines'], 24),
    exchanges: sampleExchanges(chat.messages, max: 24),
    interests: _strList(parsed['interests'], 10),
    emotionalPattern: _str(parsed['emotionalPattern']),
    reactionPatterns: reactions,
    dos: _strList(parsed['dos'], 8),
    donts: _strList(parsed['donts'], 8),
    topWords: _strList(parsed['topWords'], 18),
    messageCount: chat.messages.length,
    platform: chat.platform,
    spanText: chat.spanText,
    importedAt: DateTime.now(),
  );

  final traits = <String, double>{};
  final rawTraits = parsed['traits'];
  if (rawTraits is Map) {
    for (final k in ['warmth', 'rationality', 'initiative', 'humor']) {
      final v = rawTraits[k];
      if (v is num) traits[k] = v.toDouble().clamp(0.0, 1.0);
    }
  }

  final memories = <Map<String, String>>[];
  final rawMem = parsed['memories'];
  if (rawMem is List) {
    for (final m in rawMem.take(12)) {
      if (m is Map && _str(m['text']).isNotEmpty) {
        memories.add({
          'text': _str(m['text']),
          'kind': _str(m['kind']).isEmpty ? 'fact' : _str(m['kind']),
        });
      }
    }
  }

  // 一份画像连一条原话、一条习惯都没有，等于没学到东西——按失败处理，
  // 免得用户以为"导入成功了"却得到一个毫无变化的空壳人格。
  if (style.sampleLines.isEmpty && style.speechHabits.isEmpty && style.summary.isEmpty) {
    return ExtractResult(error: '模型没能从记录里提取出有效风格', raw: res.content);
  }

  return ExtractResult(
    style: style,
    traits: traits,
    memories: memories,
    relationshipGuess: _str(parsed['relationshipGuess']),
    sinceGuess: _str(parsed['sinceGuess']),
    raw: res.content,
  );
}

// ═══════════════════════ 无模型时的降级画像 ═══════════════════════

/// 纯本地拼的简版画像：不"聪明"，但每一条都来自真实统计，不是编的。
PersonaStyle buildStyleFromStats({
  required ParsedChat chat,
  required ChatStats stats,
}) {
  final habits = <String>[];
  if (stats.periodRate < 0.15) habits.add('几乎不用句号');
  if (stats.tildeRate > 0.05) habits.add('爱用波浪号～');
  if (stats.ellipsisRate > 0.05) habits.add('爱用省略号');
  if (stats.emojiRate > 0.05) habits.add('会用表情符号');
  if (stats.laughRate > 0.05) habits.add('常笑');
  if (stats.newlineRate > 0.05) habits.add('会把一句话分成几行发');
  if (stats.questionRate > 0.15) habits.add('常发问句');
  if (stats.bangRate > 0.1) habits.add('常用感叹号');

  // 平均字数放进 summary（它是统计量，不是"习惯"），避免两处重复
  final summary = [
    '从 ${stats.taCount} 条 TA 的消息统计得出',
    if (stats.taAvgChars > 0) '平均每条 ${stats.taAvgChars.toStringAsFixed(0)} 个字',
    if (habits.isNotEmpty) habits.first,
  ].join(' · ');

  return PersonaStyle(
    summary: summary,
    catchphrases: stats.shortPhrases.take(8).map((c) => c.word).toList(),
    speechHabits: habits,
    sampleLines: sampleTaMessages(chat.messages, max: 60),
    exchanges: sampleExchanges(chat.messages, max: 12),
    topWords: stats.topWords.take(15).map((c) => c.word).toList(),
    messageCount: chat.messages.length,
    platform: chat.platform,
    spanText: chat.spanText,
    importedAt: DateTime.now(),
  );
}

// ═══════════════════════ 工具 ═══════════════════════

String _oneLine(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').trim();

String _str(dynamic v) {
  if (v == null) return '';
  final s = '$v'.trim();
  return s == 'null' ? '' : s;
}

List<String> _strList(dynamic v, int max) {
  if (v is! List) return const [];
  final out = <String>[];
  for (final item in v) {
    if (item is Map) {
      final t = _str(item['text'] ?? item['word'] ?? item['value']);
      if (t.isNotEmpty) out.add(t);
    } else {
      final t = _str(item);
      if (t.isNotEmpty) out.add(t);
    }
    if (out.length >= max) break;
  }
  return out;
}

/// 反应模式里的「对方说」去重。
///
/// 模型有时会把同一句"对方说"套到好几条反应上（实测 3 条共用同一句），
/// 那是它编出来的对应关系。这里只保留第一次出现的 userSaid，其余清空——
/// 宁可少一个锚点，也不能让 AI 学到错误的因果（情境对不上，反应方向就会错）。
List<ReactionPattern> dedupeReactionTriggers(List<ReactionPattern> raw) {
  final used = <String>{};
  final out = <ReactionPattern>[];
  for (final rp in raw) {
    final t = rp.userSaid.trim();
    if (t.isEmpty || used.add(t)) {
      out.add(rp);
    } else {
      out.add(ReactionPattern(when: rp.when, how: rp.how, example: rp.example));
    }
  }
  return out;
}

/// 宽容解析模型返回的 JSON。
///
/// 现实里模型很少老老实实只输出一个 JSON：常见的三种脏法都要能救回来——
/// 套了 ```json 围栏、前后带解释文字、尾随逗号 / 字符串里有裸换行。
/// （公开出来是为了能被单测覆盖，这是最容易出 bug 的一环。）
Map<String, dynamic>? parseLooseJson(String raw) {
  var s = raw.trim();

  // 去掉 ```json ... ``` 围栏
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
  if (fence != null) s = fence.group(1)!.trim();

  // 截取第一个 { 到最后一个 }
  final start = s.indexOf('{');
  final end = s.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  s = s.substring(start, end + 1);

  for (final candidate in [s, _repairJson(s)]) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 试下一个
    }
  }
  return null;
}

/// 常见毛病：尾随逗号、字符串里有裸换行
String _repairJson(String s) {
  // 注意：replaceAll 不解释 $1 分组引用（只有 replaceAllMapped 才会），
  // 写成 replaceAll(..., r'$1') 会把 "$1" 字面塞进去、反而生成非法 JSON。
  var out = s.replaceAllMapped(
    RegExp(r',\s*([}\]])'),
    (m) => m.group(1)!,
  );
  out = out.replaceAllMapped(
    RegExp(r'"([^"\\]*(?:\\.[^"\\]*)*)"'),
    (m) => '"${m.group(1)!.replaceAll('\n', r'\n').replaceAll('\r', '')}"',
  );
  return out;
}
