import 'package:flutter/foundation.dart';

/// 跨对话、按人格隔离的长期记忆条目。
/// - fact：用户透露的稳定信息（姓名、关系、约定、偏好、关键事件…）
/// - avoid：用户明确要求「不要提及 / 不要做」的事
@immutable
class PersonaMemory {
  final String id;
  final String text;
  final PersonaMemoryKind kind;
  /// 记忆权重（分层展示用）：core 核心 / long 长期 / normal 普通。
  /// 由抽取时的 AI 判定 + 后续被提及次数动态提升。
  final MemoryTier tier;
  /// 被回忆/命中的次数（用户在对话里再次提到相关话题时会 +1），
  /// 次数越高越"牢固"，也是提升 tier 的依据。
  final int hits;
  final DateTime createdAt;

  const PersonaMemory({
    required this.id,
    required this.text,
    required this.kind,
    required this.createdAt,
    this.tier = MemoryTier.normal,
    this.hits = 0,
  });

  PersonaMemory copyWith({
    String? text,
    PersonaMemoryKind? kind,
    MemoryTier? tier,
    int? hits,
  }) =>
      PersonaMemory(
        id: id,
        text: text ?? this.text,
        kind: kind ?? this.kind,
        createdAt: createdAt,
        tier: tier ?? this.tier,
        hits: hits ?? this.hits,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'kind': kind.name,
        'tier': tier.name,
        'hits': hits,
        'createdAt': createdAt.toIso8601String(),
      };

  static PersonaMemory fromJson(Map<String, dynamic> j) => PersonaMemory(
        id: j['id'] as String? ?? 'm_${DateTime.now().microsecondsSinceEpoch}',
        text: j['text'] as String? ?? '',
        kind: PersonaMemoryKind.values.firstWhere(
          (k) => k.name == (j['kind'] as String? ?? 'fact'),
          orElse: () => PersonaMemoryKind.fact,
        ),
        tier: MemoryTier.values.firstWhere(
          (t) => t.name == (j['tier'] as String? ?? 'normal'),
          orElse: () => MemoryTier.normal,
        ),
        hits: j['hits'] as int? ?? 0,
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

enum PersonaMemoryKind { fact, avoid }

/// 记忆分层：核心 / 长期 / 普通（对应记忆列表页的三个 Tab）
enum MemoryTier {
  core,
  long,
  normal;

  String get label => switch (this) {
        MemoryTier.core => '核心',
        MemoryTier.long => '长期',
        MemoryTier.normal => '普通',
      };
}

@immutable
/// 一组真实的「用户 → TA」对话对。
/// 这是 few-shot 里最有效的东西：AI 不只知道 TA 说过什么，
/// 还知道**面对某句话时 TA 会怎么回**。
class StyleExchange {
  final String user;
  final String ta;
  const StyleExchange({required this.user, required this.ta});

  Map<String, dynamic> toJson() => {'user': user, 'ta': ta};

  static StyleExchange fromJson(Map<String, dynamic> j) => StyleExchange(
        user: j['user'] as String? ?? '',
        ta: j['ta'] as String? ?? '',
      );
}

/// 从聊天记录里「取证」出来的语言风格画像。
///
/// 这是让数字人格**像本人**的核心：它不是性格概括，而是可执行的说话方式
/// （口头禅、称呼、句长、标点习惯、情绪表达）**加上本人原话样本**——
/// 后者会直接进 system prompt 当范例，比任何形容词都管用。
///
/// 字段设计原则：凡是 AI 能观察到的，都要是「记录里真实出现过的东西」，
/// 不允许出现"善于倾听""性格开朗"这种放到谁身上都成立的废话。
/// 一种「情境 → TA 的典型反应」。
///
/// 这是"性格"最直接的载体，也是相似度评测里暴露出来的最大短板：
/// 用词、句长、标点都对了，但**面对同一句话往哪个方向接**错了，一眼就不像——
/// 该服软的时候反问、该敷衍的时候主动表态、该玩笑式回击的时候怼人。
class ReactionPattern {
  /// 触发情境，如"对方调侃或质疑时"
  final String when;
  /// TA 的典型反应，要写清**情绪走向**（服软 / 反问 / 敷衍 / 主动给方案 / 撒娇式回击…）
  final String how;
  /// TA 当时的回应（原话），给模型做锚点
  final String example;
  /// 对方当时说了什么。和 [example] 凑成完整的一来一回——
  /// 光说"被质疑时会反问"不够，给出「对方原话 → TA 原话」才能让模型看清
  /// 是什么刺激触发了什么反应。
  final String userSaid;

  const ReactionPattern({
    required this.when,
    required this.how,
    this.example = '',
    this.userSaid = '',
  });

  bool get isEmpty => when.trim().isEmpty && how.trim().isEmpty;

  Map<String, dynamic> toJson() =>
      {'when': when, 'how': how, 'example': example, 'userSaid': userSaid};

  static ReactionPattern fromJson(Map<String, dynamic> j) => ReactionPattern(
        when: j['when'] as String? ?? '',
        how: j['how'] as String? ?? '',
        example: j['example'] as String? ?? '',
        userSaid: j['userSaid'] as String? ?? '',
      );
}

class PersonaStyle {
  /// 一句话总结说话风格（既给用户看，也给 AI 当总纲）
  final String summary;
  /// 口头禅 / 高频口头词（必须是记录里真实出现过的词）
  final List<String> catchphrases;
  /// TA 怎么称呼用户、怎么自称
  final String callUser;
  final String selfCall;
  /// 外号、互称
  final List<String> nicknames;
  /// 说话习惯（"几乎不用句号" "句子很短" "爱用～" …）
  final List<String> speechHabits;
  final String emojiHabit;
  /// 长度习惯描述（如"平均 6 个字，很少超过两行"）
  final String lengthHabit;
  /// TA 的原话样本（**原样照抄**，进 prompt 当范例）
  final List<String> sampleLines;
  /// 真实问答对
  final List<StyleExchange> exchanges;
  final List<String> interests;
  /// 情绪表达模式（开心/生气/关心时分别怎么说）
  final String emotionalPattern;
  /// **情境 → 反应**：决定"性格像不像"的关键，比用词更能被察觉
  final List<ReactionPattern> reactionPatterns;
  /// 该做 / 千万别做
  final List<String> dos;
  final List<String> donts;
  /// 高频词（先本地统计出候选，再让 AI 筛）
  final List<String> topWords;

  // ── 来源信息：让用户知道"这是从哪学的"，也可解释相似度 ──
  final int messageCount;
  final String platform;
  final String spanText;
  final DateTime importedAt;

  const PersonaStyle({
    this.summary = '',
    this.catchphrases = const [],
    this.callUser = '',
    this.selfCall = '',
    this.nicknames = const [],
    this.speechHabits = const [],
    this.emojiHabit = '',
    this.lengthHabit = '',
    this.sampleLines = const [],
    this.exchanges = const [],
    this.interests = const [],
    this.emotionalPattern = '',
    this.reactionPatterns = const [],
    this.dos = const [],
    this.donts = const [],
    this.topWords = const [],
    this.messageCount = 0,
    this.platform = '',
    this.spanText = '',
    required this.importedAt,
  });

  /// 是否真的学到了东西（空画像不值得注入 prompt）
  bool get isEmpty =>
      summary.trim().isEmpty &&
      catchphrases.isEmpty &&
      sampleLines.isEmpty &&
      exchanges.isEmpty &&
      speechHabits.isEmpty &&
      reactionPatterns.isEmpty;

  PersonaStyle copyWith({
    String? summary,
    List<String>? catchphrases,
    String? callUser,
    String? selfCall,
    List<String>? nicknames,
    List<String>? speechHabits,
    String? emojiHabit,
    String? lengthHabit,
    List<String>? sampleLines,
    List<StyleExchange>? exchanges,
    List<String>? interests,
    String? emotionalPattern,
    List<ReactionPattern>? reactionPatterns,
    List<String>? dos,
    List<String>? donts,
    List<String>? topWords,
    int? messageCount,
    String? platform,
    String? spanText,
    DateTime? importedAt,
  }) =>
      PersonaStyle(
        summary: summary ?? this.summary,
        catchphrases: catchphrases ?? this.catchphrases,
        callUser: callUser ?? this.callUser,
        selfCall: selfCall ?? this.selfCall,
        nicknames: nicknames ?? this.nicknames,
        speechHabits: speechHabits ?? this.speechHabits,
        emojiHabit: emojiHabit ?? this.emojiHabit,
        lengthHabit: lengthHabit ?? this.lengthHabit,
        sampleLines: sampleLines ?? this.sampleLines,
        exchanges: exchanges ?? this.exchanges,
        interests: interests ?? this.interests,
        emotionalPattern: emotionalPattern ?? this.emotionalPattern,
        reactionPatterns: reactionPatterns ?? this.reactionPatterns,
        dos: dos ?? this.dos,
        donts: donts ?? this.donts,
        topWords: topWords ?? this.topWords,
        messageCount: messageCount ?? this.messageCount,
        platform: platform ?? this.platform,
        spanText: spanText ?? this.spanText,
        importedAt: importedAt ?? this.importedAt,
      );

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'catchphrases': catchphrases,
        'callUser': callUser,
        'selfCall': selfCall,
        'nicknames': nicknames,
        'speechHabits': speechHabits,
        'emojiHabit': emojiHabit,
        'lengthHabit': lengthHabit,
        'sampleLines': sampleLines,
        'exchanges': exchanges.map((e) => e.toJson()).toList(),
        'interests': interests,
        'emotionalPattern': emotionalPattern,
        'reactionPatterns': reactionPatterns.map((r) => r.toJson()).toList(),
        'dos': dos,
        'donts': donts,
        'topWords': topWords,
        'messageCount': messageCount,
        'platform': platform,
        'spanText': spanText,
        'importedAt': importedAt.toIso8601String(),
      };

  static PersonaStyle fromJson(Map<String, dynamic> j) {
    List<String> strs(dynamic v) =>
        (v as List?)?.whereType<String>().where((s) => s.trim().isNotEmpty).toList() ??
        const [];
    return PersonaStyle(
      summary: j['summary'] as String? ?? '',
      catchphrases: strs(j['catchphrases']),
      callUser: j['callUser'] as String? ?? '',
      selfCall: j['selfCall'] as String? ?? '',
      nicknames: strs(j['nicknames']),
      speechHabits: strs(j['speechHabits']),
      emojiHabit: j['emojiHabit'] as String? ?? '',
      lengthHabit: j['lengthHabit'] as String? ?? '',
      sampleLines: strs(j['sampleLines']),
      exchanges: (j['exchanges'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(StyleExchange.fromJson)
              .where((e) => e.user.trim().isNotEmpty || e.ta.trim().isNotEmpty)
              .toList() ??
          const [],
      interests: strs(j['interests']),
      emotionalPattern: j['emotionalPattern'] as String? ?? '',
      reactionPatterns: (j['reactionPatterns'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(ReactionPattern.fromJson)
              .where((r) => !r.isEmpty)
              .toList() ??
          const [],
      dos: strs(j['dos']),
      donts: strs(j['donts']),
      topWords: strs(j['topWords']),
      messageCount: j['messageCount'] as int? ?? 0,
      platform: j['platform'] as String? ?? '',
      spanText: j['spanText'] as String? ?? '',
      importedAt: DateTime.tryParse(j['importedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// 声音克隆的授权与状态记录。
///
/// 为什么必须单独存这一份：技术方案里明确要求「声音/肖像克隆必须有**授权状态、
/// 来源记录、删除能力和 AI 身份标识**」。所以这里记下：样本从哪来、用哪段文字
/// 对齐、什么时候获得授权、授权范围是什么 —— 用户可以随时查看并删除。
///
/// ⚠️ 本类**不保存音频样本本身**（体积大，且存原始人声风险更高）。
/// 音色来自「参考音频 + 参考文本」，需要在会话中导入一次；元数据长期保留。
class PersonaVoice {
  /// 样本来源说明（文件名或用户填的来源）
  final String sourceLabel;

  /// 参考音频**对应的文字**（零样本克隆必需，必须与音频内容一致）
  final String referenceText;

  /// 样本时长（秒），用于展示与质量提示
  final double sampleSeconds;

  /// 授权时间（用户勾选「已获授权」的时刻）
  final DateTime consentedAt;

  /// 授权范围文案（例如「仅本机、仅用于该人格的语音合成」）
  final String consentScope;

  /// 推理引擎标识，便于将来换模型时区分
  final String engine;

  /// 是否已经成功生成过预览（生成失败不该记成"已克隆"）
  final bool ready;

  /// 预设音色 id（非空 = 用的预设音色，如「霸道总裁」；空 = 用户克隆的声音）。
  /// 预设音色的参考音频在引擎内置清单里，无需本机保存音频。
  final String? presetId;

  const PersonaVoice({
    required this.sourceLabel,
    required this.referenceText,
    required this.sampleSeconds,
    required this.consentedAt,
    this.consentScope = '仅在本设备用于该人格的语音合成',
    this.engine = 'zipvoice-distill-int8',
    this.ready = false,
    this.presetId,
  });

  /// 是否为预设音色（非克隆）
  bool get isPreset => presetId != null && presetId!.isNotEmpty;


  Map<String, dynamic> toJson() => {
        'sourceLabel': sourceLabel,
        'referenceText': referenceText,
        'sampleSeconds': sampleSeconds,
        'consentedAt': consentedAt.toIso8601String(),
        'consentScope': consentScope,
        'engine': engine,
        'ready': ready,
        if (presetId != null) 'presetId': presetId,
      };

  static PersonaVoice fromJson(Map<String, dynamic> j) => PersonaVoice(
        sourceLabel: j['sourceLabel'] as String? ?? '',
        referenceText: j['referenceText'] as String? ?? '',
        sampleSeconds: (j['sampleSeconds'] as num?)?.toDouble() ?? 0,
        consentedAt:
            DateTime.tryParse(j['consentedAt'] as String? ?? '') ?? DateTime.now(),
        consentScope: j['consentScope'] as String? ?? '仅在本设备用于该人格的语音合成',
        engine: j['engine'] as String? ?? 'zipvoice-distill-int8',
        ready: j['ready'] as bool? ?? false,
        presetId: j['presetId'] as String?,
      );
}

class Persona {
  final String id;
  final String name;
  final String subtitle;
  final List<int> gradientSeed; // 用于稳定生成头像渐变
  /// 兜底的「默认助手」：不可编辑、不可删除
  final bool locked;

  // ── 人格设定（创建页填写，真实影响对话表现）───────────────
  /// 与用户的关系：朋友 / 恋人 / 家人 / 师长 …
  final String relationship;
  /// 认识时间，自由文本（如 "2018 年" / "三年前"），由引擎解析成时间感知
  final String since;
  /// 用户在创建页亲手写的自然语言描述 —— 人格的最高优先级来源
  final String description;
  /// 性格维度（0~1）：温柔度 / 理性度 / 主动性 / 幽默感
  final double warmth;
  final double rationality;
  final double initiative;
  final double humor;

  /// 跨对话、按人格隔离的长期记忆（持久化到本机）。
  /// 删掉某个对话甚至开新对话，这个人格依然记得；不同人格之间互不可见。
  final List<PersonaMemory> memory;

  /// 从导入的聊天记录里学到的语言风格画像。
  /// 为空表示这个人格还没导入过聊天记录（只靠用户手填的设定）。
  final PersonaStyle? style;

  /// 正在跟你聊天的这个人（用户）在聊天记录里的名字。
  ///
  /// 为什么必须存：提示词里如果不说清"谁是 TA、谁是对方"，模型只能自己猜，
  /// **实测会把 TA 自己的名字安到用户头上**（问"你知道我叫什么吗"，
  /// 它答的是自己在记录里的昵称）。身份错了，前面所有风格模仿都白搭。
  final String ownerName;

  /// TA 在聊天记录里的名字（网名 / 群昵称），可能与 [name] 不同
  /// （比如用户后来把人挌改成了 TA 的真名）。
  /// 用于向模型指认"记录里哪一方是我"。
  final String sourceName;

  /// 声音克隆的授权与状态记录。为空表示这个人格还没有配声音。
  final PersonaVoice? voice;

  const Persona({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.gradientSeed,
    this.locked = false,
    this.relationship = '',
    this.since = '',
    this.description = '',
    this.warmth = 0.5,
    this.rationality = 0.5,
    this.initiative = 0.5,
    this.humor = 0.5,
    this.memory = const [],
    this.style,
    this.ownerName = '',
    this.sourceName = '',
    this.voice,
  });

  /// 是否已被用户真正设定过（决定要不要走人格引擎，而非通用助手）
  bool get isConfigured =>
      description.trim().isNotEmpty ||
      relationship.trim().isNotEmpty ||
      since.trim().isNotEmpty ||
      _hasCustomTraits ||
      (style != null && !style!.isEmpty) ||
      voice != null;

  bool get _hasCustomTraits =>
      (warmth - 0.5).abs() > 0.01 ||
      (rationality - 0.5).abs() > 0.01 ||
      (initiative - 0.5).abs() > 0.01 ||
      (humor - 0.5).abs() > 0.01;

  /// 认识时间的展示文案（详情页用）
  String get sinceLabel => since.trim();

  Persona copyWith({
    String? name,
    String? subtitle,
    List<int>? gradientSeed,
    bool? locked,
    String? relationship,
    String? since,
    String? description,
    double? warmth,
    double? rationality,
    double? initiative,
    double? humor,
    List<PersonaMemory>? memory,
    PersonaStyle? style,
    String? ownerName,
    String? sourceName,
    PersonaVoice? voice,
    /// voice 是「有值才覆盖」，要清空必须显式说一声（避免传 null 被当成"不改"）
    bool clearVoice = false,
  }) {
    return Persona(
      id: id,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      gradientSeed: gradientSeed ?? this.gradientSeed,
      locked: locked ?? this.locked,
      relationship: relationship ?? this.relationship,
      since: since ?? this.since,
      description: description ?? this.description,
      warmth: warmth ?? this.warmth,
      rationality: rationality ?? this.rationality,
      initiative: initiative ?? this.initiative,
      humor: humor ?? this.humor,
      memory: memory ?? this.memory,
      style: style ?? this.style,
      ownerName: ownerName ?? this.ownerName,
      sourceName: sourceName ?? this.sourceName,
      voice: clearVoice ? null : (voice ?? this.voice),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subtitle': subtitle,
        'gradientSeed': gradientSeed,
        'locked': locked,
        'relationship': relationship,
        'since': since,
        'description': description,
        'warmth': warmth,
        'rationality': rationality,
        'initiative': initiative,
        'humor': humor,
        'memory': memory.map((m) => m.toJson()).toList(),
        if (style != null) 'style': style!.toJson(),
        if (ownerName.isNotEmpty) 'ownerName': ownerName,
        if (sourceName.isNotEmpty) 'sourceName': sourceName,
        if (voice != null) 'voice': voice!.toJson(),
      };

  static Persona fromJson(Map<String, dynamic> j) => Persona(
        id: j['id'] as String,
        name: j['name'] as String? ?? '人物',
        subtitle: j['subtitle'] as String? ?? '',
        gradientSeed: (j['gradientSeed'] as List?)?.map((e) => e as int).toList() ??
            const [210, 214, 220, 176, 182, 200],
        locked: j['locked'] as bool? ?? false,
        relationship: j['relationship'] as String? ?? '',
        since: j['since'] as String? ?? '',
        description: j['description'] as String? ?? '',
        warmth: (j['warmth'] as num?)?.toDouble() ?? 0.5,
        rationality: (j['rationality'] as num?)?.toDouble() ?? 0.5,
        initiative: (j['initiative'] as num?)?.toDouble() ?? 0.5,
        humor: (j['humor'] as num?)?.toDouble() ?? 0.5,
        memory: (j['memory'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(PersonaMemory.fromJson)
                .toList() ??
            const [],
        style: j['style'] is Map<String, dynamic>
            ? PersonaStyle.fromJson(j['style'] as Map<String, dynamic>)
            : null,
        ownerName: j['ownerName'] as String? ?? '',
        sourceName: j['sourceName'] as String? ?? '',
        voice: j['voice'] is Map<String, dynamic>
            ? PersonaVoice.fromJson(j['voice'] as Map<String, dynamic>)
            : null,
      );
}

enum MessageAttachmentKind { image, file }

@immutable
class MessageAttachment {
  final String name;
  final int sizeBytes;
  final MessageAttachmentKind kind;
  /// 图片附件保留字节，用于本地缩略预览；文件可以为 null
  final List<int>? bytes;
  /// 文档类附件的 markdown 原文（用于在 app 内预览正文，避免只能下载）。
  /// Word / Markdown 卡点开后可用「查看内容」按钮渲染这段文本。
  final String? previewText;
  /// 网络图片直链（AI 生成的图只有 URL，没有本地字节）
  final String? url;
  /// 生成这张图用的提示词（点开大图时可展示/复用）
  final String? prompt;

  const MessageAttachment({
    required this.name,
    required this.sizeBytes,
    required this.kind,
    this.bytes,
    this.previewText,
    this.url,
    this.prompt,
  });

  bool get isImage => kind == MessageAttachmentKind.image;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'sizeBytes': sizeBytes,
        'kind': kind == MessageAttachmentKind.image ? 'image' : 'file',
        'bytes': bytes,
        'previewText': previewText,
        'url': url,
        'prompt': prompt,
      };

  static MessageAttachment fromJson(Map<String, dynamic> j) => MessageAttachment(
        name: j['name'] as String? ?? '',
        sizeBytes: j['sizeBytes'] as int? ?? 0,
        kind: (j['kind'] as String? ?? 'file') == 'image'
            ? MessageAttachmentKind.image
            : MessageAttachmentKind.file,
        bytes: (j['bytes'] as List?)?.map((e) => e as int).toList(),
        previewText: j['previewText'] as String?,
        url: j['url'] as String?,
        prompt: j['prompt'] as String?,
      );
}

/// 用户对一条 AI 回复的反馈（点赞 / 点踩），持久化在消息本身，刷新不丢。
enum MessageFeedback { none, like, dislike }

@immutable
class Message {
  final String id;
  final String content;
  final bool isUser;
  final DateTime createdAt;
  final bool streaming; // 用于显示"正在输入"光标
  final List<MessageAttachment> attachments;
  /// 用户对这条回复的反馈（好 / 不好），默认 none。
  final MessageFeedback feedback;
  /// 点「不好」时选的原因（不准确 / 不相关 等），仅 dislike 时有值。
  final String? feedbackReason;

  /// 是否是 TA「主动来找用户」发出的消息（用于气泡上的小标记，
  /// 也用于让 AI 知道这轮是它自己先开的口，而不是回复用户）。
  final bool proactive;

  /// 正在生成图片（画图流程中）：气泡里显示炫酷的生成卡片而不是思考点。
  /// [imagePrompt] 是本次画图的提示词，卡片上会打字机展示。
  final bool generatingImage;
  final String? imagePrompt;

  /// 邮件写信卡片：这条回复是交互式写信流程（收件人→内容→确认→发送）
  final bool emailCompose;

  /// 引用回复：这条消息引用了哪句话。
  /// [quoteText] 存**文本快照**（不是外键）——被引用的那条消息之后被撤回 / 编辑掉，
  /// 引用块依然显示得出来，不会变成空白。
  final String? quoteText;
  /// 引用的是用户自己的话（true）还是 TA 的话（false）
  final bool quoteIsUser;
  /// 被引用消息的 id，仅用于「点引用块跳到原消息」这类定位，可为空
  final String? quoteId;

  const Message({
    required this.id,
    required this.content,
    required this.isUser,
    required this.createdAt,
    this.streaming = false,
    this.attachments = const [],
    this.feedback = MessageFeedback.none,
    this.feedbackReason,
    this.proactive = false,
    this.generatingImage = false,
    this.imagePrompt,
    this.emailCompose = false,
    this.quoteText,
    this.quoteIsUser = false,
    this.quoteId,
  });

  Message copyWith({
    String? content,
    bool? streaming,
    List<MessageAttachment>? attachments,
    MessageFeedback? feedback,
    String? feedbackReason,
    bool? proactive,
    bool? generatingImage,
    String? imagePrompt,
    bool? emailCompose,
    /// 编辑重发时把时间戳刷新成「这次重发」的时间
    DateTime? createdAt,
    String? quoteText,
    bool? quoteIsUser,
    String? quoteId,
  }) {
    return Message(
      id: id,
      content: content ?? this.content,
      isUser: isUser,
      createdAt: createdAt ?? this.createdAt,
      streaming: streaming ?? this.streaming,
      attachments: attachments ?? this.attachments,
      feedback: feedback ?? this.feedback,
      feedbackReason: feedbackReason ?? this.feedbackReason,
      proactive: proactive ?? this.proactive,
      generatingImage: generatingImage ?? this.generatingImage,
      imagePrompt: imagePrompt ?? this.imagePrompt,
      emailCompose: emailCompose ?? this.emailCompose,
      quoteText: quoteText ?? this.quoteText,
      quoteIsUser: quoteIsUser ?? this.quoteIsUser,
      quoteId: quoteId ?? this.quoteId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'isUser': isUser,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'streaming': streaming,
        'feedback': feedback.name,
        'feedbackReason': feedbackReason,
        'proactive': proactive,
        'generatingImage': generatingImage,
        'imagePrompt': imagePrompt,
        'emailCompose': emailCompose,
        'quoteText': quoteText,
        'quoteIsUser': quoteIsUser,
        'quoteId': quoteId,
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };

  static Message fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String? ?? '',
        content: j['content'] as String? ?? '',
        isUser: j['isUser'] as bool? ?? false,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int? ?? 0),
        streaming: j['streaming'] as bool? ?? false,
        feedback: MessageFeedback.values.firstWhere(
          (e) => e.name == (j['feedback'] as String? ?? 'none'),
          orElse: () => MessageFeedback.none,
        ),
        feedbackReason: j['feedbackReason'] as String?,
        proactive: j['proactive'] as bool? ?? false,
        generatingImage: j['generatingImage'] as bool? ?? false,
        imagePrompt: j['imagePrompt'] as String?,
        emailCompose: j['emailCompose'] as bool? ?? false,
        quoteText: j['quoteText'] as String?,
        quoteIsUser: j['quoteIsUser'] as bool? ?? false,
        quoteId: j['quoteId'] as String?,
        attachments: (j['attachments'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(MessageAttachment.fromJson)
                .toList() ??
            const [],
      );
}

/// 自动化任务：用户对 TA 说"每天早上给我发邮件"这类话后创建，
/// 到点由后台定时器执行（发邮件 / 在聊天里主动发消息）。
@immutable
class AutomationTask {
  final String id;
  final String personaId; // 归属人格（用谁的身份执行）
  final String name; // 短名，如「早安信」
  final bool daily; // true=每天 HH:mm 循环；false=单次（onceAt）
  final String timeHHmm; // "08:30"
  final DateTime? onceAt; // 单次执行的完整时间
  final String action; // email | message
  final String prompt; // 到点后交给 TA 的执行指令
  final bool enabled;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;

  const AutomationTask({
    required this.id,
    required this.personaId,
    required this.name,
    required this.daily,
    required this.timeHHmm,
    this.onceAt,
    required this.action,
    required this.prompt,
    this.enabled = true,
    this.lastRunAt,
    this.nextRunAt,
  });

  AutomationTask copyWith({
    String? name,
    bool? daily,
    String? timeHHmm,
    DateTime? onceAt,
    String? action,
    String? prompt,
    bool? enabled,
    bool clearOnceAt = false,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
  }) {
    return AutomationTask(
      id: id,
      personaId: personaId,
      name: name ?? this.name,
      daily: daily ?? this.daily,
      timeHHmm: timeHHmm ?? this.timeHHmm,
      onceAt: clearOnceAt ? null : (onceAt ?? this.onceAt),
      action: action ?? this.action,
      prompt: prompt ?? this.prompt,
      enabled: enabled ?? this.enabled,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt ?? this.nextRunAt,
    );
  }

  /// 下次执行时间：daily 取今天/明天的 HH:mm；once 取 onceAt
  DateTime computeNextRun([DateTime? from]) {
    final base = from ?? DateTime.now();
    if (!daily) return onceAt ?? base;
    final parts = timeHHmm.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    var next = DateTime(base.year, base.month, base.day, h, m);
    if (!next.isAfter(base)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  String scheduleLabel() {
    if (!daily) {
      final d = onceAt;
      if (d == null) return '单次';
      return '${d.month}/${d.day} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '每天 ${timeHHmm}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'personaId': personaId,
        'name': name,
        'daily': daily,
        'timeHHmm': timeHHmm,
        'onceAt': onceAt?.millisecondsSinceEpoch,
        'action': action,
        'prompt': prompt,
        'enabled': enabled,
        'lastRunAt': lastRunAt?.millisecondsSinceEpoch,
        'nextRunAt': nextRunAt?.millisecondsSinceEpoch,
      };

  static AutomationTask fromJson(Map<String, dynamic> j) => AutomationTask(
        id: j['id'] as String? ?? '',
        personaId: j['personaId'] as String? ?? '',
        name: j['name'] as String? ?? '自动化',
        daily: j['daily'] as bool? ?? true,
        timeHHmm: j['timeHHmm'] as String? ?? '08:00',
        onceAt: j['onceAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['onceAt'] as int)
            : null,
        action: j['action'] as String? ?? 'message',
        prompt: j['prompt'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? true,
        lastRunAt: j['lastRunAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['lastRunAt'] as int)
            : null,
        nextRunAt: j['nextRunAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['nextRunAt'] as int)
            : null,
      );
}

/// 对话搜索命中项
class ConversationSearchHit {
  final String conversationId;
  final String conversationTitle;
  final String messageId;
  final String snippet;
  final bool isUser;
  final DateTime at;

  const ConversationSearchHit({
    required this.conversationId,
    required this.conversationTitle,
    required this.messageId,
    required this.snippet,
    required this.isUser,
    required this.at,
  });
}

@immutable
class Conversation {
  final String id;
  final String title;
  final String? personaId;
  final DateTime updatedAt;
  final List<Message> messages;

  /// 长对话被摘要压缩后留下的「早期对话要点」。注入 system prompt，作为模型已知背景。
  /// 仅针对当前这一条对话，删掉对话即随之消失；长期记忆请见 Persona.memory。
  final String? earlySummary;

  /// 未读的「TA 主动发来的」消息条数（点亮侧栏小红点）。
  /// 用户打开这条对话时清零。
  final int unread;

  /// TA 最后一次主动搭话的时间（用于节流：不能太频繁地来打扰用户）
  final DateTime? lastProactiveAt;

  /// 角色扮演模式：用户提出「一起角色扮演」后整条对话切换成扮演式输出。
  /// 只属于当前对话，删对话即消失；用户说「不演了」自动关闭。
  final bool roleplay;

  const Conversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.personaId,
    this.messages = const [],
    this.earlySummary,
    this.unread = 0,
    this.lastProactiveAt,
    this.roleplay = false,
  });

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    List<Message>? messages,
    String? earlySummary,
    int? unread,
    DateTime? lastProactiveAt,
    bool? roleplay,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      personaId: personaId,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      earlySummary: earlySummary ?? this.earlySummary,
      unread: unread ?? this.unread,
      lastProactiveAt: lastProactiveAt ?? this.lastProactiveAt,
      roleplay: roleplay ?? this.roleplay,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'personaId': personaId,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'earlySummary': earlySummary,
        'unread': unread,
        'lastProactiveAt': lastProactiveAt?.millisecondsSinceEpoch,
        'roleplay': roleplay,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  static Conversation fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '新对话',
        personaId: j['personaId'] as String?,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int? ?? 0),
        earlySummary: j['earlySummary'] as String?,
        unread: j['unread'] as int? ?? 0,
        lastProactiveAt: j['lastProactiveAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['lastProactiveAt'] as int),
        roleplay: j['roleplay'] as bool? ?? false,
        messages: (j['messages'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(Message.fromJson)
                .toList() ??
            const [],
      );

  /// 用于侧栏时间分组：今天 / 昨天 / 7 天内 / 30 天内 / 更早
  ConversationGroup groupKey(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(updatedAt.year, updatedAt.month, updatedAt.day);
    final diff = today.difference(that).inDays;
    if (diff <= 0) return ConversationGroup.today;
    if (diff == 1) return ConversationGroup.yesterday;
    if (diff < 7) return ConversationGroup.lastWeek;
    if (diff < 30) return ConversationGroup.lastMonth;
    return ConversationGroup.older;
  }
}

enum ConversationGroup {
  today,
  yesterday,
  lastWeek,
  lastMonth,
  older;

  String get label {
    switch (this) {
      case ConversationGroup.today:
        return '今天';
      case ConversationGroup.yesterday:
        return '昨天';
      case ConversationGroup.lastWeek:
        return '7 天内';
      case ConversationGroup.lastMonth:
        return '30 天内';
      case ConversationGroup.older:
        return '更早';
    }
  }
}

@immutable
class ModelOption {
  final String id;
  final String label;
  final String description;
  const ModelOption({
    required this.id,
    required this.label,
    required this.description,
  });
}

/// 本地账号（纯前端演示用，密码明文存在本机 SharedPreferences，不做真实鉴权）
@immutable
class UserAccount {
  final String id;
  final String name;
  final String email;
  final String password;
  final DateTime createdAt;

  const UserAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'password': password,
        'createdAt': createdAt.toIso8601String(),
      };

  static UserAccount fromJson(Map<String, dynamic> j) => UserAccount(
        id: j['id'] as String,
        name: j['name'] as String? ?? '用户',
        email: j['email'] as String? ?? '',
        password: j['password'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
