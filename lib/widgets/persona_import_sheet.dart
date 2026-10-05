import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../app_router.dart';
import '../core/design/tokens.dart';
import '../core/widgets/sini_button.dart';
import '../core/widgets/sini_scaffold.dart';
import '../models.dart';
import '../theme.dart';
import '../utils/persona_share.dart'
    show scrubPrivacy, tryParsePersonaPackage;
import 'persona_share_card_3d.dart' show PersonaShareCardFront;

/// 「导入人格养成卡」面板（入口：人格列表页「创建新人物」下方）：
/// 1. 选朋友发来的 .sini.json 文件，或直接粘贴导入码；
/// 2. 解析成功 → 展示 TA 的卡（本命色正面 + 养成统计）；
/// 3. 「让 TA 醒来」→ 长成一个新人格并跳到详情页。
///
/// 声纹不随卡分享（导出时已剔除），导入后想听 TA 说话要另配音色。
///
/// 两种形态：[asPage] = false 是底部弹窗（showPersonaImportSheet）；
/// true 是独立页面（PersonaImportPage）——曾经弹窗在 iframe 预览里
/// 莫空白，页面形态是兜底方案。
Future<void> showPersonaImportSheet(BuildContext context, AppState state) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => PersonaImportSheet(state: state),
  );
}

class PersonaImportSheet extends StatefulWidget {
  final AppState state;
  final bool asPage;
  const PersonaImportSheet({super.key, required this.state, this.asPage = false});

  @override
  State<PersonaImportSheet> createState() => _PersonaImportSheetState();
}

class _PersonaImportSheetState extends State<PersonaImportSheet> {
  final _codeCtrl = TextEditingController();
  Map<String, dynamic>? _pkg;
  String? _error;
  bool _busy = false;

  void _applyRaw(String raw) {
    final pkg = tryParsePersonaPackage(raw.trim());
    setState(() {
      _pkg = pkg;
      _error = pkg == null
          ? '这不是有效的养成包：请确认是「似你」导出的 .sini.json 文件或完整导入码'
          : null;
    });
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (result.isEmpty || !mounted) {
        setState(() => _busy = false);
        return;
      }
      final bytes = await result.first.readAsBytes();
      _applyRaw(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      if (mounted) {
        setState(() => _error = '文件读取失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 分享包 → 新人格：换新 id、去声纹、再打一遍隐私码（防旧版导出没打干净）、
  /// 描述里加一行来历标注。养成数据（记忆 / 语言风格 / 性格）原样保留。
  Persona _personaFromPackage(Map<String, dynamic> pkg) {
    final pj = Map<String, dynamic>.from(pkg['persona'] as Map<String, dynamic>);
    pj['id'] = 'p_${DateTime.now().microsecondsSinceEpoch}';
    pj['locked'] = false;
    pj.remove('voice'); // 双保险：正常分享包里本来就没有
    var desc = scrubPrivacy((pj['description'] ?? '').toString());
    const mark = '（TA 由朋友在「似你」养成后分享而来，记忆与语言风格原样保留）';
    if (!desc.contains('由朋友')) {
      desc = desc.isEmpty ? mark : '$desc\n$mark';
    }
    pj['description'] = desc;
    if (pj['memory'] is List) {
      pj['memory'] = (pj['memory'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) {
            final mm = Map<String, dynamic>.from(m);
            mm['text'] = scrubPrivacy((mm['text'] ?? '').toString());
            return mm;
          })
          .toList();
    }
    return Persona.fromJson(pj);
  }

  void _confirmImport() {
    final p = _personaFromPackage(_pkg!);
    widget.state.addPersona(p);
    widget.state.selectPersona(p.id);
    Navigator.of(context).pop();
    Navigator.of(context).pushNamed(AppRoutes.personaDetail);
  }


  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final stats = _pkg?['stats'] as Map<String, dynamic>?;
    final persona = _pkg == null ? null : _personaFromPackage(_pkg!);
    final body = Container(
      // 注意：color 和 decoration 不能同时给（Container 会直接断言崩溃）
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: widget.asPage
            ? null
            : const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xxl),
      // 可滚动兜底：小屏 / 键盘弹出时内容再多也不挤爆
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('导入人格养成卡',
                    style: TextStyle(
                        fontSize: SiniText.titleMd,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 20, color: p.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '收到朋友分享的 .sini.json 或导入码？TA 会在你这里醒来：'
              '性格、口头禅、记忆，全都是养好的。',
              style:
                  TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary),
            ),
            const SizedBox(height: Spacing.md),
            if (_pkg == null) ...[
              SiniButton(
                label: _busy ? '正在读取…' : '选择养成包文件（.sini.json）',
                leadingIcon: Icons.folder_open_rounded,
                onTap: _busy ? null : _pickFile,
                height: 46,
                expand: true,
              ),
              const SizedBox(height: Spacing.sm),
              Text('或者粘贴导入码',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11.5, color: p.textTertiary)),
              const SizedBox(height: Spacing.xs),
              TextField(
                controller: _codeCtrl,
                maxLines: 3,
                style: TextStyle(fontSize: 12.5, color: p.textPrimary),
                decoration: InputDecoration(
                  hintText: '粘贴朋友发给你的导入码（一段 JSON 文本）',
                  hintStyle:
                      TextStyle(fontSize: 12, color: p.textTertiary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: p.border),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              SiniButton(
                label: '解析导入码',
                leadingIcon: Icons.qr_code_scanner_rounded,
                style: SiniButtonStyle.secondary,
                onTap: () => _applyRaw(_codeCtrl.text),
                height: 46,
                expand: true,
              ),
            ] else ...[
              // 预览：TA 的卡 + 养成统计
              Center(
                child: SizedBox(
                  width: 240,
                  child: PersonaShareCardFront(
                    persona: persona!,
                    messageCount: (stats?['messageCount'] as num?)?.toInt() ?? 0,
                    daysKnown: 0,
                  ),
                ),
              ),
              if (stats != null) ...[
                const SizedBox(height: Spacing.sm),
                Center(
                  child: Text(
                    '共聊 ${(stats['messageCount'] as num?)?.toInt() ?? 0} 条消息 · '
                    '${(stats['memoryCount'] as num?)?.toInt() ?? 0} 条长期记忆 · '
                    '${(stats['sampleLineCount'] as num?)?.toInt() ?? 0} 句原话样本',
                    style: TextStyle(
                        fontSize: 12, color: p.textSecondary),
                  ),
                ),
              ],
              const SizedBox(height: Spacing.sm),
              Center(
                child: Text('声纹不随卡分享，导入后可另配音色',
                    style: TextStyle(fontSize: 10.5, color: p.textTertiary)),
              ),
              const SizedBox(height: Spacing.md),
              SiniButton(
                label: '让 TA 醒来',
                leadingIcon: Icons.auto_awesome_rounded,
                onTap: _confirmImport,
                height: 48,
                expand: true,
              ),
              const SizedBox(height: Spacing.xs),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _pkg = null),
                  child: Text('换个文件 / 导入码',
                      style:
                          TextStyle(fontSize: 12, color: p.textTertiary)),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Spacing.sm),
              Text('⚠️ $_error',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFD63031)),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
    // 页面形态直接铺开；弹窗形态套一层键盘避让
    if (widget.asPage) return body;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: body,
    );
  }
}

/// 独立页面形态（弹窗在 iframe 预览里曾莫名空白，页面是最稳的兜底）
class PersonaImportPage extends StatelessWidget {
  const PersonaImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    return SiniScaffold(
      title: '导入人格养成卡',
      body: SafeArea(
        child: PersonaImportSheet(state: state, asPage: true),
      ),
    );
  }
}
