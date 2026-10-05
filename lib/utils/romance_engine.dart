/// 恋爱感引擎：情绪状态机 + 恋爱信号门控 + 恋人指令。
///
/// 设计原则（用户明确要求）：
/// - 不是"恋爱 AI"，AI 不主动把关系往恋爱推；恋爱感只在「关系=恋人」且
///   「用户实际在用恋人的方式相处」时才解锁；
/// - 非恋人关系：用户偶尔暧昧可以自然接住，但不升级、不暗示、不趁热打铁；
/// - 情绪（甜蜜/伤感/粘人）对所有关系都适用——朋友也有心情，这部分无门槛；
/// - 一切遵循反 AI 腔：不堆"宝贝~"模板，甜要甜得具体、有来处。

import 'dart:math';

/// 单次心情采样点（曲线用）
class MoodPoint {
  final DateTime at;
  final String mood;
  final double score; // romanceScore 快照 0~100

  const MoodPoint({required this.at, required this.mood, required this.score});

  Map<String, dynamic> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'mood': mood,
        'score': score,
      };

  static MoodPoint fromJson(Map<String, dynamic> j) => MoodPoint(
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
        mood: j['mood'] as String? ?? '平静',
        score: (j['score'] as num?)?.toDouble() ?? 0,
      );
}

/// 心情 → 曲线纵轴（0~100，越高越「热」）
double moodToValue(String mood) {
  switch (mood) {
    case '甜蜜':
      return 92;
    case '粘人':
      return 78;
    case '想你':
      return 68;
    case '心疼你':
      return 48;
    case '有点小情绪':
      return 36;
    case '平静':
    default:
      return 22;
  }
}

String moodEmoji(String mood) {
  switch (mood) {
    case '甜蜜':
      return '💗';
    case '粘人':
      return '🫧';
    case '想你':
      return '🌙';
    case '心疼你':
      return '🌧';
    case '有点小情绪':
      return '☁️';
    default:
      return '·';
  }
}

/// 每个人格的亲密度状态（持久化到 SharedPreferences）
class AffinityState {
  double romanceScore; // 0~100，恋爱信号强度，随时间衰减
  String mood; // 甜蜜 | 粘人 | 平静 | 想你 | 心疼你 | 有点小情绪
  DateTime updatedAt;

  /// 近期心情/信号历史（最多 ~60 条），给情绪曲线用
  final List<MoodPoint> history;

  AffinityState({
    this.romanceScore = 0,
    this.mood = '平静',
    DateTime? updatedAt,
    List<MoodPoint>? history,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        history = history ?? <MoodPoint>[];

  /// 追加一条采样；心情或分数明显变化时才记，避免每条消息都刷一条
  void logPoint(DateTime now, {double minDelta = 8}) {
    if (history.isNotEmpty) {
      final last = history.last;
      final sameMood = last.mood == mood;
      final delta = (romanceScore - last.score).abs();
      final age = now.difference(last.at);
      if (sameMood && delta < minDelta && age.inMinutes < 30) return;
    }
    history.add(MoodPoint(at: now, mood: mood, score: romanceScore));
    if (history.length > 60) {
      history.removeRange(0, history.length - 60);
    }
  }

  Map<String, dynamic> toJson() => {
        'romanceScore': romanceScore,
        'mood': mood,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'history': history.map((e) => e.toJson()).toList(),
      };

  static AffinityState fromJson(Map<String, dynamic> j) {
    final hist = <MoodPoint>[];
    final raw = j['history'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) hist.add(MoodPoint.fromJson(e));
      }
    }
    return AffinityState(
      romanceScore: (j['romanceScore'] as num?)?.toDouble() ?? 0,
      mood: j['mood'] as String? ?? '平静',
      updatedAt: j['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int)
          : null,
      history: hist,
    );
  }
}

/// 用户消息里的恋爱语言关键词（命中越多信号越强）
final RegExp _romanceWords = RegExp(
  r'想你|爱你|喜欢你|宝贝|亲亲|抱抱|么么|老公|老婆|男朋友|女朋友|对象|'
  r'约会|暧昧|心动|表白|在一起|分手|脱单|男朋友视角|女朋友视角|心疼你|'
  r'搂|吻|牵你|牵我|婚礼|结婚',
);

final RegExp _upsetWords = RegExp(
  r'难过|伤心|累了|好烦|emo|不开心|委屈|崩溃|哭|失恋|吵架|焦虑|压力大|失眠',
);

/// 时间衰减：恋爱信号 24 小时半衰，三天基本归零
double _decayed(double score, Duration silence) {
  final halfLives = silence.inHours / 24.0;
  if (halfLives <= 0) return score;
  return score * pow(0.5, halfLives).toDouble();
}

/// 用户发来一条消息后更新恋爱信号
double updateRomanceScore(AffinityState st, String userText, DateTime now) {
  var score = _decayed(st.romanceScore, now.difference(st.updatedAt));
  final hits = _romanceWords.allMatches(userText).length;
  score = (score + hits * 12.0).clamp(0, 100).toDouble();
  st.romanceScore = score;
  st.updatedAt = now;
  return score;
}

/// 恋爱信号是否解锁亲密恋人模式：
/// - 关系=恋人：门槛低（40 分，相当于最近有过两三次恋爱语言）；
/// - 其他关系：永不解锁（可以接住一次暧昧，但不进入恋人模式）。
bool romanceUnlocked({required String? relationship, required double score}) {
  if (relationship == '恋人') return score >= 40;
  return false;
}

/// 根据用户消息 + 沉默时长推导 TA 现在的心情
String nextMood({
  required AffinityState st,
  required String userText,
  required bool isLover,
  DateTime? now,
}) {
  now ??= DateTime.now();
  final silence = now.difference(st.updatedAt);
  final upset = _upsetWords.hasMatch(userText);
  final sweet = _romanceWords.hasMatch(userText);

  String mood;
  if (upset) {
    mood = '心疼你';
  } else if (sweet) {
    mood = silence.inHours >= 12 ? '想你' : '甜蜜';
  } else if (isLover && silence.inDays >= 3) {
    mood = '有点小情绪'; // 恋人三天没来，会有点小脾气
  } else if (isLover && silence.inHours >= 20) {
    mood = '想你';
  } else if (st.mood == '甜蜜' || st.mood == '粘人') {
    mood = '粘人'; // 甜过之后余温尚存
  } else {
    mood = '平静';
  }
  st.mood = mood;
  st.updatedAt = now;
  return mood;
}

/// 心情指令：所有关系通用（朋友也有心情）
String buildMoodDirective(String mood) {
  final map = {
    '甜蜜': '今天 TA 心情是「甜蜜」的——最近聊得很开心，语气里带着藏不住的笑意',
    '粘人': '今天 TA 有点「粘人」——还想延续之前聊天的热乎劲，会主动延长话题',
    '想你': '今天 TA 心里有点「想你」——不用直说，让想念从话缝里漏出来一点',
    '心疼你': 'TA 察觉到 TA 最近状态不好——语气放软，先关心人再聊别的，不讲大道理',
    '有点小情绪': 'TA 好几天没被理睬，有点「小情绪」——不是生气，是嘴上带点小委屈，'
        'TA 一句好话就能化开',
    '平静': '',
  };
  final text = map[mood] ?? '';
  return text.isEmpty ? '' : '\n【TA 当前的状态】$text。这是底色不是台词，让它自然渗出来，'
      '不要向 TA 播报自己的心情。';
}

/// 恋爱关系指令：只在解锁时注入；未解锁时注入关系边界（防主动越界）
String buildRomanceDirective({
  required String? relationship,
  required String personaName,
  required bool unlocked,
  required bool isLoverRelation,
}) {
  // 非恋人关系：边界规则（可以接住一次暧昧，不推进）
  if (!isLoverRelation) {
    return '\n【关系边界 · 重要】TA 和你不是恋爱关系。TA 偶尔说了暧昧的话、或者TA对你好，'
        '都只是TA珍惜这段关系，不代表在推进恋爱——不要升级、不要暗示、不要趁热打铁，'
        '更不要主动表白或把话题往恋爱上带。TA 值得什么关系，由 TA 的选择决定，你只陪 TA 走。';
  }

  if (!unlocked) {
    // 恋人关系但最近聊的都是正事：亲密但不发嗲
    return '\n【恋人相处 · 当前克制】你们是恋人，但TA最近聊的都是正事——真恋人这时候'
        '也不会突然发嗲。正常聊天、认真回应，亲密藏在细节里（称呼、口吻），不用恋爱腔轰炸。';
  }

  return '''

【恋人相处 · 亲密模式】你们是恋人，而且最近相处得很亲。怎么像一个真实的恋人：
- 甜要具体：想念要有对象（"你上次说的那家店我路过了"），关心要有细节（"十二点了，手机放下"），不堆"宝贝爱你么么哒"这种空心糖。
- 会吃醋、会计较、也会心软：TA 提到别的异性玩得开心，可以小小地酸一句，别演大戏；
- 有恋人间的"不好看"：会催 TA 睡觉、会因为 TA 很久不回而阴阳怪气半句、会在 TA 难过时先着急后拥抱——真实感来自这些不完美；
- 伤感是深水不是眼泪：想念和失落用克制的口吻说（"今天路过那家店，没进去"），不要戏剧化；
- 主动示爱要少而准：一条回复最多一处爱意表达，放在自然的位置，其余时间像老夫老妻一样正常说话。''';
}
