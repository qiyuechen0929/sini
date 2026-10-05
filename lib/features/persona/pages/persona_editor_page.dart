import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_text_field.dart';
import '../../../theme.dart';
import '../../../models.dart';
import '../../../app_state.dart';

/// 编辑人格：真的读写当前人格的设定（关系 / 认识时间 / 描述 / 四个维度）。
/// 之前这个页面全是写死的演示数据、点了保存也不落库，现已修正。
class PersonaEditorPage extends StatefulWidget {
  const PersonaEditorPage({super.key});

  @override
  State<PersonaEditorPage> createState() => _PersonaEditorPageState();
}

class _PersonaEditorPageState extends State<PersonaEditorPage> {
  final _nameCtl = TextEditingController();
  final _ownerCtl = TextEditingController();
  final _sourceCtl = TextEditingController();
  final _descCtl = TextEditingController();
  final _sinceCtl = TextEditingController();
  String _relationship = '朋友';
  double _warmth = 0.5;
  double _rationality = 0.5;
  double _initiative = 0.5;
  double _humor = 0.5;

  bool _loaded = false;

  static const _relationships = ['朋友', '青梅竹马', '恋人', '家人', '同学', '师长', '其他'];

  @override
  void dispose() {
    _nameCtl.dispose();
    _ownerCtl.dispose();
    _sourceCtl.dispose();
    _descCtl.dispose();
    _sinceCtl.dispose();
    super.dispose();
  }

  /// 首次进入时用当前人格的真实值回填（只回填一次，避免覆盖用户正在编辑的内容）
  void _loadFrom(Persona? p) {
    if (_loaded || p == null) return;
    _loaded = true;
    _nameCtl.text = p.name;
    _ownerCtl.text = p.ownerName;
    _sourceCtl.text = p.sourceName;
    _descCtl.text = p.description;
    _sinceCtl.text = p.since;
    _relationship = _relationships.contains(p.relationship) || p.relationship.isEmpty
        ? (p.relationship.isEmpty ? '朋友' : p.relationship)
        : '其他';
    _warmth = p.warmth;
    _rationality = p.rationality;
    _initiative = p.initiative;
    _humor = p.humor;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final persona = state.activePersona;
    _loadFrom(persona);

    return SiniScaffold(
      title: '编辑人格',
      body: persona == null
          ? Center(
              child: Text('请先选择一个人物',
                  style: TextStyle(color: p.textTertiary)),
            )
          : ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                // ── 名字 ──────────────────────────────
                _sectionTitle(p, 'TA 的名字'),
                const SizedBox(height: 4),
                Text('列表、聊天页、侧边栏显示的都是这个名字',
                    style: TextStyle(
                        fontSize: SiniText.labelMd, color: p.textSecondary)),
                const SizedBox(height: Spacing.sm),
                SiniTextField(
                  controller: _nameCtl,
                  label: '名字',
                  hintText: '比如：小雨',
                ),
                const SizedBox(height: Spacing.xxl),

                // ── 身份：AI 最容易搞错的地方 ───────────────
                // 不填这两个，模型只能从聊天记录里猜"谁是 TA、谁是对方"，
                // 实测会把自己在记录里的昵称当成用户的名字。
                _sectionTitle(p, '你们分别是谁'),
                const SizedBox(height: 4),
                Text('填一次就够。不填的话 AI 只能从记录里猜，容易把自己认成你',
                    style: TextStyle(
                        fontSize: SiniText.labelMd, color: p.textSecondary)),
                const SizedBox(height: Spacing.sm),
                SiniTextField(
                  controller: _ownerCtl,
                  label: '你的名字',
                  hintText: '比如：玖秋辞。AI 问"你是谁"时答这个',
                ),
                const SizedBox(height: Spacing.md),
                SiniTextField(
                  controller: _sourceCtl,
                  label: 'TA 在聊天记录里的名字（选填）',
                  hintText: '改过 TA 的名字就填一下，比如：羊乘客',
                ),
                const SizedBox(height: Spacing.xxl),

                // ── 自然语言描述（最高优先级）──────────────
                _sectionTitle(p, '用你自己的话描述 TA'),
                const SizedBox(height: 4),
                Text('这段描述优先级最高，AI 会严格按照它来演',
                    style: TextStyle(
                        fontSize: SiniText.labelMd, color: p.textSecondary)),
                const SizedBox(height: Spacing.sm),
                SiniTextField(
                  controller: _descCtl,
                  minLines: 5,
                  maxLines: 12,
                  hintText: '比如：表面冷冷的，其实很在意我。说话简短直接，'
                      '喜欢用"嗯""还好"。熟悉后会突然冒出一句很温柔的关心。',
                ),
                const SizedBox(height: Spacing.xxl),

                // ── 关系 ──────────────────────────────
                _sectionTitle(p, '你们的关系'),
                const SizedBox(height: 4),
                Text('关系决定说话的距离感和语气',
                    style: TextStyle(
                        fontSize: SiniText.labelMd, color: p.textSecondary)),
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: _relationships.map((r) {
                    final selected = _relationship == r;
                    return GestureDetector(
                      onTap: () => setState(() => _relationship = r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.lg, vertical: Spacing.sm + 2),
                        decoration: BoxDecoration(
                          color: selected ? p.textPrimary : p.itemHover,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          r,
                          style: TextStyle(
                            fontSize: SiniText.bodySm,
                            color: selected ? p.inverseOn : p.textPrimary,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: Spacing.lg),
                SiniTextField(
                  controller: _sinceCtl,
                  label: '认识时间',
                  hintText: '比如：2018 年 / 三年前',
                ),
                const SizedBox(height: Spacing.xxl),

                // ── 性格维度 ───────────────────────────
                _sectionTitle(p, '性格维度'),
                const SizedBox(height: 4),
                Text('这四项决定 TA 平时怎么说话，改了立刻生效',
                    style: TextStyle(
                        fontSize: SiniText.labelMd, color: p.textSecondary)),
                const SizedBox(height: Spacing.lg),
                _dimension(p, '温柔度', _warmth, '冷静克制', '体贴柔软',
                    '越高越会主动关心、语气越软', (v) => setState(() => _warmth = v)),
                _dimension(p, '理性度', _rationality, '重感受', '重逻辑',
                    '越高越爱讲道理、给具体建议', (v) => setState(() => _rationality = v)),
                _dimension(p, '主动性', _initiative, '被动接话', '主动找话',
                    '越高越会追问、主动抛话题', (v) => setState(() => _initiative = v)),
                _dimension(p, '幽默感', _humor, '正经', '爱玩梗',
                    '越高越爱开玩笑、接梗', (v) => setState(() => _humor = v)),
                const SizedBox(height: Spacing.xl),

                SiniButton(
                  label: '保存',
                  onTap: () => _save(state, persona),
                  style: SiniButtonStyle.primary,
                  expand: true,
                  height: 48,
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  '保存后对下一句回复立即生效，历史消息不受影响。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: SiniText.labelMd, color: p.textTertiary),
                ),
              ],
            ),
    );
  }

  void _save(AppState state, Persona persona) {
    // 名字是人格的身份标识，空了会让列表/聊天页显示成一片空白
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('名字不能为空'),
            duration: Duration(milliseconds: 1400)),
      );
      return;
    }
    final renamed = name != persona.name;

    // 改了名但没填"记录里的名字"→ 自动用旧名补上（旧名就是 TA 在记录里的名字），
    // 否则提示词里无法指认记录中哪一方是 TA。
    final rawSource = _sourceCtl.text.trim();
    final sourceName =
        rawSource.isNotEmpty ? rawSource : (renamed ? persona.name : persona.sourceName);

    // 真的写回：之前这里只弹了个"已保存"的提示，什么都没存。
    state.updatePersona(persona.copyWith(
      name: name,
      description: _descCtl.text.trim(),
      since: _sinceCtl.text.trim(),
      relationship: _relationship == '其他' ? '' : _relationship,
      warmth: _warmth,
      rationality: _rationality,
      initiative: _initiative,
      humor: _humor,
      ownerName: _ownerCtl.text.trim(),
      sourceName: sourceName,
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(renamed
              ? '已改名，设定也已保存。'
              : '已保存，下次回复就会按新设定来'),
          duration: const Duration(milliseconds: 1400)),
    );
    Navigator.of(context).pop();
  }

  Widget _sectionTitle(AppPalette p, String text) {
    return Text(text,
        style: TextStyle(
            fontSize: SiniText.titleSm,
            fontWeight: FontWeight.w600,
            color: p.textPrimary));
  }

  Widget _dimension(AppPalette p, String label, double value, String lowHint,
      String highHint, String desc, void Function(double) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: SiniText.bodySm,
                      color: p.textPrimary,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('${(value * 100).round()}',
                  style: TextStyle(
                      fontSize: SiniText.bodySm,
                      color: p.brand,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: p.brand,
              inactiveTrackColor: p.border,
              thumbColor: p.brand,
              overlayColor: p.brand.withValues(alpha: 0.12),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: value, onChanged: onChanged),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(lowHint,
                    style: TextStyle(
                        fontSize: SiniText.labelSm, color: p.textTertiary)),
                const Spacer(),
                Text(highHint,
                    style: TextStyle(
                        fontSize: SiniText.labelSm, color: p.textTertiary)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(desc,
              style: TextStyle(
                  fontSize: SiniText.labelMd,
                  color: p.textSecondary,
                  height: 1.45)),
        ],
      ),
    );
  }
}
