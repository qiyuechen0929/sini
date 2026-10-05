/// 人格相似度评测 —— 回答「它到底像不像 TA」。
///
/// 为什么需要它：光看几张截图说"很像"是没有意义的。这里用**留出法**做客观评测：
///
///   1. 把聊天记录按时间切开：前 80% 用来学画像，后 20% **完全不参与学习**；
///   2. 在留出的 20% 里找真实的「用户说 X → TA 回 Y」；
///   3. 给模型**和当时一样的上下文**，让它生成回复；
///   4. 把生成结果和 TA 的**真实回复**并排比：
///      · 客观：长度接近度、标点习惯一致度、口头禅命中、AI 腔词检出
///      · 主观：交给另一个模型盲评「像不像，1-10」并给理由
///   5. 输出 markdown 报告，能定位到「第 7 条忽然用了句号」这种颗粒度。
///
/// 它同时是**回归测试**：以后改 prompt / 换模型，跑一次就知道是变好还是变坏。
///
/// 用法（会消耗 API 额度，所以不做成默认测试；文件名也不带 _test）：
///   SINI_EVAL_FILE=D:/path/chat.txt \
///   SINI_EVAL_SELF=我 \                 # 你就是哪一方（不填则按启发式猜）
///   SINI_EVAL_KEY=sk-xxx \
///   SINI_EVAL_BASE=https://api.deepseek.com/v1 \
///   SINI_EVAL_MODEL=deepseek-chat \
///   SINI_EVAL_N=12 \
///   flutter test test/persona_similarity_eval.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sini/data/llm_provider.dart';
import 'package:sini/features/persona/chat_import/chat_models.dart';
import 'package:sini/features/persona/chat_import/chat_parser.dart';
import 'package:sini/features/persona/chat_import/chat_stats.dart';
import 'package:sini/features/persona/chat_import/persona_extractor.dart';
import 'package:sini/features/persona/chat_import/text_decode.dart';
import 'package:sini/models.dart';
import 'package:sini/utils/persona_engine.dart';

String _env(String k, [String def = '']) {
  final v = Platform.environment[k];
  return (v == null || v.trim().isEmpty) ? def : v.trim();
}

/// 生成回复用的温度（可用 SINI_EVAL_TEMP 覆盖）
///
/// 默认 0.8，**不要想当然调低**：实测把温度降到 0.6 反而从 7.5 掉到 6.0 ——
/// 要模仿的人本身就是活泼、有情绪起伏的，低温会把她磨平成一个"稳妥的应答机"，
/// 失掉的恰恰是性格。人格模仿虽然要求高保真，但保真包含"情绪的锐度"。
final double _evalTemp =
    double.tryParse(_env('SINI_EVAL_TEMP', '0.8')) ?? 0.8;

/// 「AI 腔」检测词表：真人私聊里几乎不会出现，出现即扣分。
const List<String> _aiSmellWords = [
  '首先', '其次', '综上所述', '总之', '总的来说', '由此可见', '换句话说',
  '需要注意的是', '值得一提的是', '希望对你有所帮助', '希望能帮到你', '希望这些',
  '作为一个', '如果你愿意', '我可以帮你', '有什么我可以', '请问有什么',
  '当然可以', '很高兴', '很乐意', '不妨', '建议你', '总结一下', '以下几点',
  '一方面', '另一方面', '与此同时', '在这个', '我们可以', '让我来',
];

void main() {
  test('人格相似度评测（留出法）', () async {
    final file = _env('SINI_EVAL_FILE');
    final key = _env('SINI_EVAL_KEY');
    final base = _env('SINI_EVAL_BASE', 'https://api.deepseek.com/v1');
    final model = _env('SINI_EVAL_MODEL', 'deepseek-chat');
    final n = int.tryParse(_env('SINI_EVAL_N', '12')) ?? 12;
    // 每题生成几个候选（取最像的那个）。
    // 实测：默认 1 就够——prompt 约束强的场景下，高温也没带来候选多样性
    // （两次生成结果一模一样），多候选纯属多花钱。
    final candN = int.tryParse(_env('SINI_EVAL_CANDIDATES', '1')) ?? 1;

    if (file.isEmpty || key.isEmpty) {
      // ignore: avoid_print
      print('\n[评测] 缺少参数，跳过。用法见文件头部注释。\n'
          '  必填：SINI_EVAL_FILE / SINI_EVAL_KEY\n'
          '  可选：SINI_EVAL_SELF / SINI_EVAL_BASE / SINI_EVAL_MODEL / SINI_EVAL_N\n');
      return;
    }

    final cfg = ModelConfig(
      id: 'eval',
      name: '评测模型',
      providerId: 'custom',
      modelId: model,
      apiKey: key,
      baseUrl: base,
      isDefault: true,
    );

    // ═══════════ 1. 读文件 → 解析 ═══════════
    final bytes = File(file).readAsBytesSync();
    final decoded = decodeChatFile(bytes);
    final parsed = parseChatText(decoded.text);
    expect(parsed, isNotNull, reason: '解析失败，检查文件格式');
    var chat = parsed!;

    final selfHint = _env('SINI_EVAL_SELF');
    final selfName = selfHint.isNotEmpty
        ? selfHint
        : (chat.messages.any((m) => m.isSelf)
            ? chat.messages.firstWhere((m) => m.isSelf).sender
            : chat.messages.first.sender);
    chat = chat.withSelf(selfName);

    _log('文件：$file');
    _log('编码：${decoded.encoding} · 识别为 ${chat.platform}/${chat.format} · '
        '共 ${chat.messages.length} 条 · 参与者 ${chat.participants.join(" / ")}');
    _log('判定「我」= $selfName');

    // ═══════════ 2. 留出法切分 ═══════════
    final all = chat.messages;
    final cut = (all.length * 0.8).round();
    final trainMsgs = all.sublist(0, cut);
    final trainChat = _slice(chat, trainMsgs);

    _log('训练集 ${trainMsgs.length} 条（用于学画像）/ 留出集 ${all.length - cut} 条（用于评测）');

    // ═══════════ 3. 学画像（只用训练集）═══════════
    final stats = computeChatStats(trainChat);
    _log('统计：TA 平均 ${stats.taAvgChars.toStringAsFixed(1)} 字 · '
        '句号率 ${(stats.periodRate * 100).round()}% · '
        '波浪号率 ${(stats.tildeRate * 100).round()}%');

    final extract = await extractStyleWithLlm(cfg: cfg, chat: trainChat, stats: stats);
    expect(extract.ok, isTrue, reason: '画像抽取失败：${extract.error}');
    final style = extract.style!;

    _log('画像总述：${style.summary}');
    _log('口头禅：${style.catchphrases.join(" / ")}');

    // ═══════════ 4. 组装 system prompt（和线上完全一致）═══════════
    final taName = stats.taName.isEmpty ? 'TA' : stats.taName;
    final persona = Persona(
      id: 'eval',
      name: taName,
      subtitle: '',
      gradientSeed: const [1, 2, 3],
      style: style,
      relationship: extract.relationshipGuess,
      since: extract.sinceGuess,
      warmth: extract.traits['warmth'] ?? 0.5,
      rationality: extract.traits['rationality'] ?? 0.5,
      initiative: extract.traits['initiative'] ?? 0.5,
      humor: extract.traits['humor'] ?? 0.5,
    );
    final directive = buildPersonaDirective(persona);

    // ═══════════ 5. 从留出集里挑测试对 ═══════════
    final pairs = <_Pair>[];
    for (var i = cut; i + 1 < all.length; i++) {
      final u = all[i];
      final t = all[i + 1];
      if (!u.isSelf || t.isSelf) continue;
      if (isNoiseText(u.text) || isNoiseText(t.text)) continue;
      if (u.charCount > 60 || t.charCount > 80) continue;
      final ut = u.time;
      final tt = t.time;
      if (ut != null && tt != null && tt.difference(ut).inMinutes.abs() > 60) continue;
      pairs.add(_Pair(index: i, user: u.text, realReply: t.text));
    }

    if (pairs.isEmpty) {
      _log('留出集里没有可用的「用户→TA」对话对，换个文件或调大记录量。');
      return;
    }

    final chosen = _evenly(pairs, n);
    _log('本次评测 ${chosen.length} 组（留出集共 ${pairs.length} 组可用）\n');

    // ═══════════ 6. 逐条生成 + 客观打分 ═══════════
    final results = <_Result>[];
    for (var k = 0; k < chosen.length; k++) {
      final p = chosen[k];
      final ctx = all.sublist(p.index > 10 ? p.index - 10 : 0, p.index);

      final msgs = <Map<String, dynamic>>[
        {'role': 'system', 'content': directive},
        for (final m in ctx)
          {'role': m.isSelf ? 'user' : 'assistant', 'content': m.text},
        {'role': 'user', 'content': p.user},
      ];

      // 每条题生成多个候选再挑最像的那个。
      // 原因：真人的回复有随机性（跳话题、答非所问、突然说自己的事），
      // 只抽一次签会把"这次运气差"误判成"风格不像"。
      // 衡量的是「它有没有能力产出像的话」，而不是单次抽签的结果。
      final gens = <String>[];
      for (var c = 0; c < candN; c++) {
        final res = await chatComplete(
          cfg: cfg,
          messages: msgs,
          temperature: _evalTemp,
          maxTokens: 300,
        );
        final g = (res.content ?? '').trim();
        if (g.isNotEmpty) gens.add(g);
      }
      if (gens.isEmpty) continue;

      _log('[${k + 1}/${chosen.length}] 用户：${_oneLine(p.user)}');
      _log('   TA 真实：${_oneLine(p.realReply)}');
      for (var c = 0; c < gens.length; c++) {
        _log('   候选${c + 1}：${_oneLine(gens[c])}');
      }

      var bestGen = gens.first;
      var bestJudge = const _Judge(0, '', '');
      for (final g in gens) {
        final j = await _judge(cfg: cfg, taName: taName, pair: p, gen: g, ctx: ctx);
        if (j.score >= bestJudge.score) {
          bestJudge = j;
          bestGen = g;
        }
      }
      final m = _score(bestGen, p.realReply, style, stats);

      _log('   最像的一条：${_oneLine(bestGen)}');
      _log('   长度相似 ${(m.lengthSim * 100).round()}% · '
          '标点一致 ${(m.punctSim * 100).round()}% · '
          '口头禅命中 ${m.catchphraseHits}'
          '${m.aiSmell.isEmpty ? "" : " · ⚠️ AI 腔：${m.aiSmell.join("/")}"}');
      _log('   盲评：${bestJudge.score}/10 — ${bestJudge.reason}\n');

      results.add(_Result(pair: p, generated: bestGen, metrics: m, judge: bestJudge));
    }

    // ═══════════ 8. 出报告 ═══════════
    final report = _buildReport(
      file: file,
      chat: chat,
      selfName: selfName,
      stats: stats,
      style: style,
      directive: directive,
      results: results,
      model: model,
      trainCount: trainMsgs.length,
      testCount: all.length - cut,
      candN: candN,
    );
    final out = 'D:/sini/似你_flutter_前端_MVP/评测报告.md';
    File(out).writeAsStringSync(report);

    final avgJudge = results.map((r) => r.judge.score).reduce((a, b) => a + b) /
        results.length;
    final avgLen = results.map((r) => r.metrics.lengthSim).reduce((a, b) => a + b) /
        results.length;
    final avgPunct = results.map((r) => r.metrics.punctSim).reduce((a, b) => a + b) /
        results.length;
    final smell = results.where((r) => r.metrics.aiSmell.isNotEmpty).length;
    final hit = results.where((r) => r.judge.score >= 7).length;

    _log('══════ 汇总 ══════');
    _log('盲评平均分：${avgJudge.toStringAsFixed(1)} / 10');
    _log('像的命中率（≥7分）：$hit / ${results.length}');
    _log('长度相似度：${(avgLen * 100).round()}%');
    _log('标点一致度：${(avgPunct * 100).round()}%');
    _log('出现 AI 腔的条数：$smell / ${results.length}');
    _log('报告已写入：$out');
  }, timeout: const Timeout(Duration(minutes: 25)));
}

// ═══════════════════════ 打分 ═══════════════════════

class _Pair {
  final int index;
  final String user;
  final String realReply;
  const _Pair({required this.index, required this.user, required this.realReply});
}

class _Metrics {
  final double lengthSim;
  final double punctSim;
  final int catchphraseHits;
  final List<String> aiSmell;
  final List<String> punctNotes;
  const _Metrics({
    required this.lengthSim,
    required this.punctSim,
    required this.catchphraseHits,
    required this.aiSmell,
    required this.punctNotes,
  });
}

class _Judge {
  final int score;
  final String reason;
  final String diff;
  const _Judge(this.score, this.reason, this.diff);
}

class _Result {
  final _Pair pair;
  final String generated;
  final _Metrics metrics;
  final _Judge judge;
  const _Result({
    required this.pair,
    required this.generated,
    required this.metrics,
    required this.judge,
  });
}

_Metrics _score(String gen, String real, PersonaStyle style, ChatStats stats) {
  // 长度接近度：差得越多分越低
  final rl = real.runes.length;
  final gl = gen.runes.length;
  final lengthSim = rl == 0 ? 0.0 : (1 - (gl - rl).abs() / (rl * 2)).clamp(0.0, 1.0);

  // 标点习惯：TA 不用的，生成也不该用；TA 常用的，生成也该用
  var good = 0;
  var total = 0;
  final notes = <String>[];
  void check(String ch, double taRate, String label) {
    final has = gen.contains(ch);
    total++;
    if (taRate < 0.10) {
      if (!has) {
        good++;
      } else {
        notes.add('TA 几乎不用$label，但生成了');
      }
    } else if (taRate > 0.15) {
      if (has) {
        good++;
      } else {
        notes.add('TA 常用$label，但生成没用');
      }
    } else {
      good++; // TA 自己用得也随意，不评判
    }
  }

  check('。', stats.periodRate, '句号');
  check('！', stats.bangRate, '感叹号');
  check('？', stats.questionRate, '问号');
  check('～', stats.tildeRate, '波浪号');
  check('…', stats.ellipsisRate, '省略号');
  final punctSim = total == 0 ? 1.0 : good / total;

  // 口头禅命中
  int hits = 0;
  for (final c in style.catchphrases) {
    if (c.isNotEmpty && gen.contains(c)) hits++;
  }

  // AI 腔
  final smell = _aiSmellWords.where(gen.contains).toList();

  return _Metrics(
    lengthSim: lengthSim,
    punctSim: punctSim,
    catchphraseHits: hits,
    aiSmell: smell,
    punctNotes: notes,
  );
}

Future<_Judge> _judge({
  required ModelConfig cfg,
  required String taName,
  required _Pair pair,
  required String gen,
  required List<ChatMessage> ctx,
}) async {
  final ctxText = ctx
      .map((m) => '${m.isSelf ? "用户" : taName}：${_oneLine(m.text)}')
      .join('\n');

  final prompt = '''
下面是一位真实的人「$taName」的一段聊天。

【对话上下文】
$ctxText
用户：${_oneLine(pair.user)}

【$taName 当时实际回的是】
${_oneLine(pair.realReply)}

【现在有一个 AI 模仿 $taName，回的是这一句】
${_oneLine(gen)}

请判断：**这句 AI 生成的话，像不像 $taName 会说的？**

⚠️ 判断标准很重要，别搞错：
**不要拿"和实际那句是不是同一句"当标准。**
同一个人面对同一句话，本来就可能有好几种说法——她这次说 A，下次可能说 B，
两个都是她会说的话。真人自己重来一次也未必说同一句。

你要判断的是**风格一致性**：用词、句子长短、标点习惯、情绪态度，
以及"这句话会不会从这个人嘴里说出来"。

- 如果这是一句她**完全可能说**的话（哪怕和实际那句不一样）→ 给高分
- 只有当它明显不像她（突然变书面语、变啰嗦、变客套、变成助手腔）→ 才给低分

只输出 JSON，不要解释、不要 markdown 围栏：
{"score": 1到10的整数, "reason": "一句话理由", "diff": "最不像 TA 的地方（没有就写 无）"}
''';

  final res = await chatComplete(
    cfg: cfg,
    messages: <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '你是严格的风格评审。只输出 JSON。分数分布要有区分度，不要一律给高分。',
      },
      {'role': 'user', 'content': prompt},
    ],
    temperature: 0.2,
    maxTokens: 300,
  );

  final parsed = res.content == null ? null : parseLooseJson(res.content!);
  if (parsed == null) {
    return const _Judge(0, '盲评失败：模型返回无法解析', '');
  }
  final score = parsed['score'];
  return _Judge(
    score is num ? score.toInt().clamp(0, 10) : 0,
    '${parsed['reason'] ?? ''}',
    '${parsed['diff'] ?? ''}',
  );
}

// ═══════════════════════ 报告 ═══════════════════════

String _buildReport({
  required String file,
  required ParsedChat chat,
  required String selfName,
  required ChatStats stats,
  required PersonaStyle style,
  required String directive,
  required List<_Result> results,
  required String model,
  required int trainCount,
  required int testCount,
  required int candN,
}) {
  final b = StringBuffer();
  final avgJudge =
      results.map((r) => r.judge.score).reduce((a, b) => a + b) / results.length;
  final avgLen =
      results.map((r) => r.metrics.lengthSim).reduce((a, b) => a + b) / results.length;
  final avgPunct =
      results.map((r) => r.metrics.punctSim).reduce((a, b) => a + b) / results.length;
  final smellCount = results.where((r) => r.metrics.aiSmell.isNotEmpty).length;
  final hitCount = results.where((r) => r.judge.score >= 7).length;

  b.writeln('# 人格相似度评测报告');
  b.writeln();
  b.writeln('- 语料：`$file`');
  b.writeln('- 解析：${chat.platform} / ${chat.format} · 共 ${chat.messages.length} 条 · '
      '「我」= $selfName · 对象 = ${stats.taName}');
  b.writeln('- 评测模型：$model（每题生成 $candN 个候选，取最像的一个）');
  b.writeln('- 留出法：$trainCount 条学画像 / $testCount 条留出评测（**留出部分未参与任何学习**）');
  b.writeln();
  b.writeln('## 总评');
  b.writeln();
  b.writeln('| 指标 | 结果 |');
  b.writeln('|---|---|');
  b.writeln('| 盲评平均分 | **${avgJudge.toStringAsFixed(1)} / 10** |');
  b.writeln('| 像的命中率（≥7分） | $hitCount / ${results.length} |');
  b.writeln('| 长度相似度 | ${(avgLen * 100).round()}% |');
  b.writeln('| 标点习惯一致度 | ${(avgPunct * 100).round()}% |');
  b.writeln('| 出现 AI 腔的条数 | $smellCount / ${results.length} |');
  b.writeln();
  b.writeln('## 学到的画像');
  b.writeln();
  b.writeln('- 语言风格：${style.summary}');
  b.writeln('- 口头禅：${style.catchphrases.join(" / ")}');
  b.writeln('- 称呼：叫我「${style.callUser}」，自称「${style.selfCall}」');
  b.writeln('- 说话习惯：');
  for (final h in style.speechHabits) {
    b.writeln('  - $h');
  }
  b.writeln('- 必须做到：${style.dos.join("；")}');
  b.writeln('- 绝对不要：${style.donts.join("；")}');
  b.writeln();
  b.writeln('## 性格反应（情境 → TA 会怎么接）');
  b.writeln();
  b.writeln('这是决定「像不像」的第一因素，改 prompt 时优先看这一段。');
  b.writeln();
  for (final r in style.reactionPatterns) {
    b.writeln('- **${r.when}** → ${r.how}');
    if (r.userSaid.trim().isNotEmpty || r.example.trim().isNotEmpty) {
      b.writeln('  - 实例：对方「${r.userSaid}」→ TA「${r.example}」');
    }
  }
  if (style.reactionPatterns.isEmpty) {
    b.writeln('> ⚠️ 没有抽到反应模式——这是相似度的主要短板，检查抽取 prompt。');
  }
  b.writeln();
  b.writeln('## 逐条对比');
  b.writeln();
  b.writeln('| # | 用户说 | TA 真实回复 | AI 生成 | 盲评 | 长度 | 标点 | 口头禅 | AI 腔 |');
  b.writeln('|---|---|---|---|---|---|---|---|---|');
  for (var i = 0; i < results.length; i++) {
    final r = results[i];
    b.writeln('| ${i + 1} '
        '| ${_cell(r.pair.user)} '
        '| ${_cell(r.pair.realReply)} '
        '| ${_cell(r.generated)} '
        '| ${r.judge.score} '
        '| ${(r.metrics.lengthSim * 100).round()}% '
        '| ${(r.metrics.punctSim * 100).round()}% '
        '| ${r.metrics.catchphraseHits} '
        '| ${r.metrics.aiSmell.isEmpty ? "—" : r.metrics.aiSmell.join("、")} |');
  }
  b.writeln();
  b.writeln('## 盲评理由（最不像的地方）');
  b.writeln();
  for (var i = 0; i < results.length; i++) {
    final r = results[i];
    b.writeln('${i + 1}. **${r.judge.score}/10** ${r.judge.reason}');
    if (r.judge.diff.trim().isNotEmpty && r.judge.diff.trim() != '无') {
      b.writeln('   - 最不像：${r.judge.diff}');
    }
    if (r.metrics.punctNotes.isNotEmpty) {
      b.writeln('   - 标点问题：${r.metrics.punctNotes.join("；")}');
    }
  }
  b.writeln();
  b.writeln('## 实际注入给模型的 system prompt');
  b.writeln();
  b.writeln('```text');
  b.writeln(directive);
  b.writeln('```');
  return b.toString();
}

String _cell(String s) =>
    _oneLine(s).replaceAll('|', '\\|');

String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

List<_Pair> _evenly(List<_Pair> list, int n) {
  if (list.length <= n) return list;
  final out = <_Pair>[];
  final step = list.length / n;
  for (var i = 0; i < n; i++) {
    out.add(list[(i * step).floor().clamp(0, list.length - 1)]);
  }
  return out;
}

ParsedChat _slice(ParsedChat c, List<ChatMessage> msgs) => ParsedChat(
      messages: msgs,
      platform: c.platform,
      format: c.format,
      note: c.note,
    );

void _log(String s) {
  // ignore: avoid_print
  print('[评测] $s');
}
