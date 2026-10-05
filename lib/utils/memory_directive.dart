import '../models.dart';

/// 把人格的长期记忆编译成 system prompt 里的一段。
///
/// ⚠️ 设计要点（真实踩过，别改回去）：
/// 记忆是**背景知识，不是话题清单**。
/// 之前这里写的是"任何对话里都可随时自然引用，不要假装不知道"——
/// 结果 AI 一开场就翻旧账：记录里聊过补考，它第一句就问"你补考准备咋样了"。
/// 真人不会这样，记忆应该"用户提到才接住，绝不主动拿出来当话题"。
String buildMemoryDirective(List<PersonaMemory> memory) {
  if (memory.isEmpty) return '';

  final facts = memory.where((m) => m.kind == PersonaMemoryKind.fact).toList();
  final avoids = memory.where((m) => m.kind == PersonaMemoryKind.avoid).toList();
  if (facts.isEmpty && avoids.isEmpty) return '';

  final b = StringBuffer();
  if (facts.isNotEmpty) {
    b.write('\n[你长期记得的关于这位用户与你们的事 · **这是背景知识，不是话题清单**]\n');
    b.write('- 用户主动聊到时，你要自然地接住，绝不假装不知道；\n');
    b.write('- **但绝对不要主动提起**，也不要拿这些事当开场白或寒暄素材——'
        '真人不会一上来就翻旧账（哪怕记着"对方在准备补考"，也不该开口就问补考）。\n');
    for (final f in facts) {
      b.write('- ${f.text}\n');
    }
  }
  if (avoids.isNotEmpty) {
    b.write('\n[用户明确要求你避免的，请严格做到，绝对不要提及或违背]\n');
    for (final a in avoids) {
      b.write('- 不要：${a.text}\n');
    }
  }
  return b.toString();
}
