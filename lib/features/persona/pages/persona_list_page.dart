import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_sheet.dart';
import '../../../theme.dart';
import '../../../app_state.dart';
import '../../../models.dart';
import '../../../widgets/persona_avatar.dart';
import 'widgets/persona_completeness.dart';

class PersonaListPage extends StatelessWidget {
  const PersonaListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final personas = state.personas;
    return SiniScaffold(
      title: '数字人格',
      actions: [
        IconButton(
          tooltip: '创建',
          icon: Icon(Icons.add_rounded, size: 22, color: p.textPrimary),
          onPressed: () => Navigator.of(context).pushNamed('/persona/new'),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xxxl),
        children: [
          if (personas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xxxl),
              child: Center(
                child: Text('还没有人格，先去创建第一个吧',
                    style: TextStyle(color: p.textTertiary, fontSize: SiniText.bodySm)),
              ),
            ),
          for (final persona in personas)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: Material(
                color: p.itemHover,
                borderRadius: BorderRadius.circular(Radii.xl),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.xl),
                  onTap: () {
                    state.selectPersona(persona.id);
                    Navigator.of(context).pushNamed('/persona/detail');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: Row(
                      children: [
                        PersonaAvatar(persona: persona, size: 52, showSparkle: true),
                        const SizedBox(width: Spacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(persona.name,
                                  style: TextStyle(
                                      fontSize: SiniText.titleMd,
                                      fontWeight: FontWeight.w600,
                                      color: p.textPrimary)),
                              const SizedBox(height: 4),
                              Text(persona.subtitle,
                                  style: TextStyle(
                                      fontSize: SiniText.labelMd, color: p.textSecondary)),
                              const SizedBox(height: Spacing.sm),
                              Row(
                                children: [
                                  if (persona.locked) ...[
                                    _metaPill(p, '默认'),
                                    const SizedBox(width: Spacing.xs),
                                  ],
                                  _metaPill(p, 'v1'),
                                  const SizedBox(width: Spacing.xs),
                                  // 跟详情页同一套算法，不再是写死的 64%
                                  _metaPill(p, '完成度 ${personaCompleteness(persona)}%'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // 默认的「默认助手」不可编辑 / 不可删除
                        if (!persona.locked) _moreButton(context, persona, state, p),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: Spacing.lg),
          SiniButton(
            label: '创建新人物',
            leadingIcon: Icons.person_add_alt_1_rounded,
            onTap: () => Navigator.of(context).pushNamed('/persona/new'),
            style: SiniButtonStyle.primary,
            expand: true,
            height: 48,
          ),
          const SizedBox(height: Spacing.sm),
          SiniButton(
            label: '导入人格养成卡',
            leadingIcon: Icons.download_for_offline_outlined,
            onTap: () => Navigator.of(context)
                .pushNamed('/persona/import-card'),
            style: SiniButtonStyle.secondary,
            expand: true,
            height: 44,
          ),
        ],
      ),
    );
  }

  /// 卡片右侧的「…」小圆角按钮：编辑 / 删除
  Widget _moreButton(BuildContext context, Persona persona, AppState state, AppPalette p) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: () => _showActions(context, persona, state),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xs + 2),
          child: Icon(Icons.more_horiz_rounded, size: 18, color: p.textTertiary),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, Persona persona, AppState state) async {
    await showSiniSheet<void>(
      context: context,
      title: persona.name,
      subtitle: persona.subtitle,
      danger: true,
      primary: ('删除人物', () {
        Navigator.of(context).pop();
        _confirmDelete(context, persona, state);
      }),
      secondary: ('编辑人格', () {
        Navigator.of(context).pop();
        state.selectPersona(persona.id);
        Navigator.of(context).pushNamed('/persona/edit');
      }),
      tertiary: ('取消', () => Navigator.of(context).pop()),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, Persona persona, AppState state) async {
    await showSiniSheet<void>(
      context: context,
      title: '删除人物？',
      subtitle: '「${persona.name}」及其所有对话、记忆将被永久删除，无法恢复。',
      danger: true,
      primary: ('删除', () {
        Navigator.of(context).pop();
        state.deletePersona(persona.id);
      }),
      secondary: ('取消', () => Navigator.of(context).pop()),
    );
  }

  Widget _metaPill(AppPalette p, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: p.mainBg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: SiniText.labelSm,
              color: p.textSecondary,
              fontWeight: FontWeight.w500)),
    );
  }
}
