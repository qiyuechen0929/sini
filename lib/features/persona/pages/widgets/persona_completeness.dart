import '../../../../models.dart';

/// 人格完成度：按实际填了哪些设定项估算。
///
/// 算法：描述 40 + 关系 20 + 认识时间 15 + 性格维度偏移 25（四档各自偏离 0.5 的
/// 绝对值之和 ÷ 2，再折算成 25 分）。
///
/// 抽出来是为了让「人格列表页」和「人格详情页」用同一套算法，
/// 之前列表页写死了 64%，跟详情页算出来的值对不上。
int personaCompleteness(Persona p) {
  int score = 0;
  if (p.description.trim().isNotEmpty) score += 40;
  if (p.relationship.trim().isNotEmpty) score += 20;
  if (p.since.trim().isNotEmpty) score += 15;
  final traitDelta = (p.warmth - 0.5).abs() +
      (p.rationality - 0.5).abs() +
      (p.initiative - 0.5).abs() +
      (p.humor - 0.5).abs();
  score += (traitDelta / 2.0 * 25).round().clamp(0, 25);
  return score.clamp(0, 100);
}
