/// 关系引擎：由**真实对话数据**推导亲密度与关系状态，而不是写死的数字。
///
/// 输入全是本地可得的客观数据：
///  - 该人格名下累计对话轮数（用户发过多少条）
///  - 长期记忆条数（AI 实际记住了多少关于 TA 的信息）
///  - 认识时间（创建时填的 since，解析成年数）
///  - 收到过的点赞反馈数（用户明确认可过多少次）
///
/// 输出是可解释的分数 + 一句状态描述，让用户看到"聊得越多，关系越近"。
library;

import 'dart:math' as math;

import '../models.dart';

/// 关系亲密度快照
class RelationshipStat {
  /// 0~1 的亲密度
  final double intimacy;
  /// 累计对话轮数（用户消息数）
  final int rounds;
  /// 长期记忆条数
  final int memoryCount;
  /// 认识年数（解析不出为 null）
  final int? years;
  /// 收到过的好评数
  final int likes;
  /// 状态标签，如「很熟了」「逐渐熟络」
  final String stage;

  const RelationshipStat({
    required this.intimacy,
    required this.rounds,
    required this.memoryCount,
    required this.years,
    required this.likes,
    required this.stage,
  });

  /// 亲密度百分比（0~100）
  int get percent => (intimacy * 100).round();
}

/// 计算某人格当前的关系亲密度。
///
/// 权重设计（总和 1.0）——刻意让"对话轮数"占大头，
/// 因为用户最直观的体感就是"我聊得越多，TA 越懂我"：
///   对话深度 45% + 记忆沉淀 30% + 评价反馈 15% + 时间跨度 10%
RelationshipStat computeRelationship({
  required Persona persona,
  required List<Conversation> conversations,
  required int likes,
}) {
  // ── 1. 累计轮数（用户主动说了多少话）──────────────
  var rounds = 0;
  for (final c in conversations) {
    if (c.personaId != persona.id) continue;
    for (final m in c.messages) {
      if (m.isUser && m.content.trim().isNotEmpty) rounds++;
    }
  }

  // ── 2. 记忆条数 ──────────────────────────────
  final memoryCount = persona.memory.length;

  // ── 3. 认识年数 ──────────────────────────────
  final years = _yearsSince(persona.since);

  // ── 4. 各项归一化到 0~1（用饱和曲线，避免早期涨得过快）──
  // 对话：100 轮左右接近满值
  final roundScore = _saturate(rounds / 100.0);
  // 记忆：30 条接近满值
  final memScore = _saturate(memoryCount / 30.0);
  // 好评：20 次接近满值
  final likeScore = _saturate(likes / 20.0);
  // 时间：10 年接近满值
  final yearScore = _saturate((years ?? 0) / 10.0);

  final intimacy = (roundScore * 0.45 +
          memScore * 0.30 +
          likeScore * 0.15 +
          yearScore * 0.10)
      .clamp(0.0, 1.0);

  return RelationshipStat(
    intimacy: intimacy,
    rounds: rounds,
    memoryCount: memoryCount,
    years: years,
    likes: likes,
    stage: _stageOf(intimacy, rounds, years),
  );
}

/// 饱和曲线：x 越大增长越慢，f(0)=0，f(1)≈0.70，f(2)≈0.91。
/// 用 1-e^(-1.2x) 而非线性，是因为关系增长本就是"先快后慢"。
double _saturate(double x) {
  if (x <= 0) return 0;
  return (1 - math.exp(-1.2 * x)).clamp(0.0, 1.0);
}

/// 关系阶段：文案要让人有"关系在推进"的体感
String _stageOf(double intimacy, int rounds, int? years) {
  if (rounds == 0) return '还没聊过';
  if (intimacy < 0.15) return '刚刚认识';
  if (intimacy < 0.3) return '开始熟悉';
  if (intimacy < 0.5) return '逐渐熟络';
  if (intimacy < 0.7) return '已经很熟';
  if (intimacy < 0.85) return '无话不谈';
  return '彼此默契';
}

/// 从"2016 年"/"三年前"这类自由文本解析年数
int? _yearsSince(String since) {
  final s = since.trim();
  if (s.isEmpty) return null;
  final now = DateTime.now().year;
  final m = RegExp(r'(19|20)\d{2}').firstMatch(s);
  if (m != null) {
    final y = int.tryParse(m.group(0)!);
    if (y != null && y >= 1900 && y <= now + 1) {
      final d = now - y;
      return d < 0 ? 0 : d;
    }
  }
  final cn = RegExp(r'([一二三四五六七八九十\d]+)\s*年').firstMatch(s);
  if (cn != null) return _cnNum(cn.group(1)!);
  return null;
}

int? _cnNum(String s) {
  const map = {
    '零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
  };
  if (RegExp(r'^\d+$').hasMatch(s)) return int.tryParse(s);
  if (s.contains('十')) {
    final parts = s.split('十');
    final tens = parts[0].isEmpty ? 1 : (map[parts[0]] ?? 0);
    final ones =
        parts.length > 1 && parts[1].isNotEmpty ? (map[parts[1]] ?? 0) : 0;
    return tens * 10 + ones;
  }
  return map[s];
}

/// 记忆分层统计
class MemoryStats {
  final int core;
  final int long;
  final int normal;
  final int avoid;
  const MemoryStats({
    required this.core,
    required this.long,
    required this.normal,
    required this.avoid,
  });

  int get total => core + long + normal + avoid;
}

MemoryStats computeMemoryStats(List<PersonaMemory> memories) {
  var core = 0, lng = 0, normal = 0, avoid = 0;
  for (final m in memories) {
    if (m.kind == PersonaMemoryKind.avoid) {
      avoid++;
      continue;
    }
    switch (m.tier) {
      case MemoryTier.core:
        core++;
        break;
      case MemoryTier.long:
        lng++;
        break;
      case MemoryTier.normal:
        normal++;
        break;
    }
  }
  return MemoryStats(core: core, long: lng, normal: normal, avoid: avoid);
}
