import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_text_field.dart';
import '../../../theme.dart';
import '../../../models.dart';
import '../../../app_state.dart';
import '../../../widgets/persona_avatar.dart';

/// 创建人物：5 步分页表单
/// Step 1 基础资料  →  Step 2 关系背景  →  Step 3 性格描述  →  Step 4 维度
///   →  Step 5 声音（必选，可试听）
class CreatePersonaPage extends StatefulWidget {
  const CreatePersonaPage({super.key});

  @override
  State<CreatePersonaPage> createState() => _CreatePersonaPageState();
}

class _CreatePersonaPageState extends State<CreatePersonaPage> {
  int _step = 0;

  // Step 1
  final _nameCtl = TextEditingController();
  final _subtitleCtl = TextEditingController();
  int _avatarSeed = 0;
  final _seeds = const [
    [231, 217, 209, 183, 196, 216], // 暖橙
    [209, 218, 231, 178, 184, 207], // 冷蓝
    [231, 209, 219, 219, 178, 207], // 粉紫
    [219, 231, 209, 184, 207, 178], // 暖绿
    [231, 224, 209, 207, 196, 178], // 暖黄
    [216, 209, 231, 178, 196, 219], // 紫罗兰
  ];

  // Step 2
  String _relationship = '朋友';
  final _sinceCtl = TextEditingController(text: '2020');

  // Step 3
  final _descCtl = TextEditingController();

  // Step 4
  double _warmth = 0.6;
  double _rationality = 0.5;
  double _initiative = 0.5;
  double _humor = 0.7;

  @override
  void initState() {
    super.initState();
    // 昵称变化要实时刷新「下一步」的可用性（表单只传了 controller，
    // 不加监听的话打完字按钮也不会亮）
    _nameCtl.addListener(_onFormChanged);
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtl.removeListener(_onFormChanged);
    _nameCtl.dispose();
    _subtitleCtl.dispose();
    _sinceCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  bool get _canNext {
    switch (_step) {
      case 0:
        return _nameCtl.text.trim().isNotEmpty;
      case 1:
        return _relationship.isNotEmpty;
      case 3:
        // 最后一步的「完成」也要求名字
        return _nameCtl.text.trim().isNotEmpty;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return SiniScaffold(
      title: '创建人物',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text('取消', style: TextStyle(color: p.textSecondary)),
        ),
      ],
      body: Column(
        children: [
          _stepper(p),
          const Divider(height: 0.5),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.lg),
              child: _buildStep(p),
            ),
          ),
          _footer(p),
        ],
      ),
    );
  }

  Widget _stepper(AppPalette p) {
    const labels = ['基础', '关系', '性格', '维度'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = i == _step;
          final done = i < _step;
          final color = done
              ? p.brand
              : active
                  ? p.textPrimary
                  : p.textTertiary;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done ? p.brand : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color,
                      width: 1.5,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                              fontSize: SiniText.labelSm,
                              fontWeight: FontWeight.w600,
                              color: color),
                        ),
                ),
                if (i < labels.length - 1)
                  Expanded(
                    child: Container(
                      height: 1.5,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: done ? p.brand : p.border,
                    ),
                  ),
                const SizedBox(width: 4),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: SiniText.labelMd,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep(AppPalette p) {
    switch (_step) {
      case 0:
        return _step1(p);
      case 1:
        return _step2(p);
      case 2:
        return _step3(p);
      case 3:
        return _step4(p);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _step1(AppPalette p) {
    final preview = Persona(
      id: 'preview',
      name: _nameCtl.text.isEmpty ? '?' : _nameCtl.text,
      subtitle: _subtitleCtl.text.isEmpty ? '点击选择头像' : _subtitleCtl.text,
      gradientSeed: _seeds[_avatarSeed],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _importEntry(p),
        const SizedBox(height: Spacing.xl),
        Text('给他一个名字', style: TextStyle(fontSize: SiniText.titleMd, fontWeight: FontWeight.w600, color: p.textPrimary)),
        const SizedBox(height: Spacing.xs),
        Text('这是人格在对话里被称呼的方式', style: TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary)),
        const SizedBox(height: Spacing.lg),
        Center(child: PersonaAvatar(persona: preview, size: 96, showSparkle: true)),
        const SizedBox(height: Spacing.lg),
        SiniTextField(controller: _nameCtl, label: '昵称', hintText: '比如：小雨', autofocus: true),
        const SizedBox(height: Spacing.lg),
        SiniTextField(controller: _subtitleCtl, label: '一句话关系', hintText: '比如：外冷内热的青梅竹马'),
        const SizedBox(height: Spacing.xl),
        Text('选择头像渐变', style: TextStyle(fontSize: SiniText.labelLg, fontWeight: FontWeight.w500, color: p.textSecondary)),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.md,
          children: List.generate(_seeds.length, (i) {
            final selected = i == _avatarSeed;
            final seed = _seeds[i];
            return GestureDetector(
              onTap: () => setState(() => _avatarSeed = i),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Color.fromARGB(255, seed[0], seed[1], seed[2]),
                      Color.fromARGB(255, seed[3], seed[4], seed[5]),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: selected ? p.brand : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// 「创建人物」里的另一条路：从聊天记录导入，自动生成画像
  Widget _importEntry(AppPalette p) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.xl),
        onTap: () =>
            Navigator.of(context).pushNamed('/persona/import', arguments: 'create'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                p.brand.withValues(alpha: 0.12),
                p.itemHover,
              ],
            ),
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: p.brand.withValues(alpha: 0.22), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: Border.all(color: p.border, width: 1),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.upload_file_rounded, size: 22, color: p.brand),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('导入聊天记录克隆 TA',
                        style: TextStyle(
                            fontSize: SiniText.titleSm,
                            fontWeight: FontWeight.w600,
                            color: p.textPrimary)),
                    const SizedBox(height: 3),
                    Text('上传你们的聊天记录，自动还原 TA 的画像与说话方式',
                        style: TextStyle(
                            fontSize: SiniText.labelMd,
                            color: p.textSecondary,
                            height: 1.45)),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step2(AppPalette p) {
    final relationships = ['朋友', '青梅竹马', '恋人', '家人', '同学', '师长', '其他'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('你们是什么关系？', style: TextStyle(fontSize: SiniText.titleMd, fontWeight: FontWeight.w600, color: p.textPrimary)),
        const SizedBox(height: Spacing.xs),
        Text('关系会决定他说话的距离感和语气', style: TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary)),
        const SizedBox(height: Spacing.lg),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: relationships.map((r) {
            final selected = _relationship == r;
            return GestureDetector(
              onTap: () => setState(() => _relationship = r),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm + 2),
                decoration: BoxDecoration(
                  color: selected ? p.textPrimary : p.itemHover,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  r,
                  style: TextStyle(
                    fontSize: SiniText.bodySm,
                    color: selected ? p.inverseOn : p.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: Spacing.xxl),
        SiniTextField(controller: _sinceCtl, label: '认识时间', hintText: '比如：2020 年'),
        const SizedBox(height: Spacing.lg),
        Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: p.itemHover,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Row(
            children: [
              Icon(Icons.tips_and_updates_outlined, size: 18, color: p.textSecondary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  '后续可以在人物主页补充共同经历和重要事件。',
                  style: TextStyle(fontSize: SiniText.labelMd, color: p.textSecondary, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _step3(AppPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('用你自己的话描述他', style: TextStyle(fontSize: SiniText.titleMd, fontWeight: FontWeight.w600, color: p.textPrimary)),
        const SizedBox(height: Spacing.xs),
        Text('写得越具体，越像你想的那个人', style: TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary)),
        const SizedBox(height: Spacing.lg),
        SiniTextField(
          controller: _descCtl,
          minLines: 6,
          maxLines: 10,
          hintText: '比如：表面上冷冷的，其实很在意我。说话简短直接，喜欢用"嗯""还好"。熟悉了以后会突然冒出一句很温柔的关心。',
        ),
      ],
    );
  }

  Widget _step4(AppPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('调整性格维度',
            style: TextStyle(
                fontSize: SiniText.titleMd,
                fontWeight: FontWeight.w600,
                color: p.textPrimary)),
        const SizedBox(height: Spacing.xs),
        Text('这四项决定 TA 平时怎么说话，改了立刻生效',
            style: TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary)),
        const SizedBox(height: Spacing.xl),
        _dimension(
          p,
          label: '温柔度',
          value: _warmth,
          lowHint: '冷静克制',
          highHint: '体贴柔软',
          desc: '越高越会主动关心、语气越软；越低越偏冷静、把关心藏在行动里',
          onChanged: (v) => setState(() => _warmth = v),
        ),
        _dimension(
          p,
          label: '理性度',
          value: _rationality,
          lowHint: '重感受',
          highHint: '重逻辑',
          desc: '越高越爱讲道理、给具体建议；越低越只共情、不分析',
          onChanged: (v) => setState(() => _rationality = v),
        ),
        _dimension(
          p,
          label: '主动性',
          value: _initiative,
          lowHint: '被动接话',
          highHint: '主动找话',
          desc: '越高越会追问、主动抛话题；越低越偏向等着被问',
          onChanged: (v) => setState(() => _initiative = v),
        ),
        _dimension(
          p,
          label: '幽默感',
          value: _humor,
          lowHint: '正经',
          highHint: '爱玩梗',
          desc: '越高越爱开玩笑、接梗；越低越严肃认真',
          onChanged: (v) => setState(() => _humor = v),
        ),
      ],
    );
  }

  /// 单个性格维度：滑块 + 左右语义标签 + 一句话解释
  Widget _dimension(
    AppPalette p, {
    required String label,
    required double value,
    required String lowHint,
    required String highHint,
    required String desc,
    required void Function(double) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: SiniText.bodySm,
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: p.brand.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text('${(value * 100).round()}',
                    style: TextStyle(
                        fontSize: SiniText.labelMd,
                        color: p.brand,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: p.brand,
              inactiveTrackColor: p.itemHover,
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
                    style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary)),
                const Spacer(),
                Text(highHint,
                    style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(desc,
              style: TextStyle(
                  fontSize: SiniText.labelMd, color: p.textSecondary, height: 1.45)),
        ],
      ),
    );
  }

  Widget _slider(AppPalette p, String label, double value, void Function(double) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: TextStyle(fontSize: SiniText.bodySm, color: p.textPrimary, fontWeight: FontWeight.w500)),
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
              inactiveTrackColor: p.itemHover,
              thumbColor: p.brand,
              overlayColor: p.brand.withValues(alpha: 0.12),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _footer(AppPalette p) {
    final isLast = _step == 3;
    return Container(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.lg),
      decoration: BoxDecoration(
        color: p.mainBg,
        border: Border(top: BorderSide(color: p.border, width: 0.5)),
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: SiniButton(
                label: '上一步',
                onTap: () => setState(() => _step = _step - 1),
                style: SiniButtonStyle.secondary,
                height: 48,
              ),
            ),
          if (_step > 0) const SizedBox(width: Spacing.sm),
          Expanded(
            flex: 2,
            child: SiniButton(
              label: isLast ? '完成' : '下一步',
              onTap: _canNext
                  ? () {
                      if (isLast) {
                        _finish();
                      } else {
                        setState(() => _step = _step + 1);
                      }
                    }
                  : null,
              style: SiniButtonStyle.primary,
              height: 48,
            ),
          ),
        ],
      ),
    );
  }

  void _finish() {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) return;
    final state = AppStateScope.of(context);
    // 创建流程不再选音色；若素材导入页留下过克隆草稿则仍带上
    final voice = state.draftVoice;
    final persona = Persona(
      id: 'p_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      subtitle: _subtitleCtl.text.trim().isEmpty
          ? _relationship
          : _subtitleCtl.text.trim(),
      gradientSeed: _seeds[_avatarSeed],
      relationship: _relationship,
      since: _sinceCtl.text.trim(),
      description: _descCtl.text.trim(),
      warmth: _warmth,
      rationality: _rationality,
      initiative: _initiative,
      humor: _humor,
      voice: voice,
    );
    state.takeDraftVoice();
    state.addPersona(persona);
    state.selectPersona(persona.id);
    state.newConversation();
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }
}
