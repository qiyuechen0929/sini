import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sini/app_state.dart';
import 'package:sini/features/persona/pages/persona_editor_page.dart';
import 'package:sini/models.dart';
import 'package:sini/theme.dart';

/// 编辑人格页的改名功能：改完要真的落到 AppState（而不只是界面变一下），
/// 并且名字清空时必须拦住——名字是人格的身份标识，空了列表/聊天页会一片空白。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppState> pumpEditor(WidgetTester tester, Persona p) async {
    final state = AppState();
    state.addPersona(p);
    state.selectPersona(p.id);

    await tester.pumpWidget(
      AppStateScope(
        state: state,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const PersonaEditorPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  /// 保存按钮在长表单末尾，页面是懒加载列表，得先滚过去才会被构建。
  Future<void> tapSave(WidgetTester tester) async {
    final save = find.text('保存');
    await tester.scrollUntilVisible(save, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Persona base() => const Persona(
        id: 'p_rename',
        name: '小雨',
        subtitle: '由聊天记录还原',
        gradientSeed: [12, 34, 56, 78],
      );

  testWidgets('打开编辑页时名字框回填当前名字', (tester) async {
    await pumpEditor(tester, base());

    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.controller?.text, '小雨');
  });

  testWidgets('改名后保存，新名字真的写进人格', (tester) async {
    final state = await pumpEditor(tester, base());

    await tester.enterText(find.byType(TextField).first, '小语');
    await tester.pump();
    await tapSave(tester);

    expect(state.personaById('p_rename')!.name, '小语');
    // 头像渐变不该跟着名字变——改的是叫法，不是换了个人
    expect(state.personaById('p_rename')!.gradientSeed, const [12, 34, 56, 78]);
  });

  testWidgets('只改名字、不动其它字段时，原有设定不能被清空', (tester) async {
    final state = await pumpEditor(
      tester,
      base().copyWith(
        description: '表面冷冷的，其实很在意我',
        relationship: '同学',
        since: '2019 年',
        warmth: 0.2,
      ),
    );

    await tester.enterText(find.byType(TextField).first, '小语');
    await tester.pump();
    await tapSave(tester);

    final after = state.personaById('p_rename')!;
    expect(after.name, '小语');
    expect(after.description, '表面冷冷的，其实很在意我');
    expect(after.relationship, '同学');
    expect(after.since, '2019 年');
    expect(after.warmth, closeTo(0.2, 0.001));
  });

  testWidgets('名字清空时保存被拦下，不写库', (tester) async {
    final state = await pumpEditor(tester, base());

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pump();
    await tapSave(tester);

    expect(state.personaById('p_rename')!.name, '小雨');
    expect(find.text('名字不能为空'), findsOneWidget);
  });

  testWidgets('改名并填「你的名字」后，双方身份都落库；改过名会自动补上旧名', (tester) async {
    final state = await pumpEditor(tester, base()); // 原名「小雨」

    await tester.enterText(find.byType(TextField).at(0), '杨成凯'); // TA 的名字
    await tester.enterText(find.byType(TextField).at(1), '玖秋辞'); // 你的名字
    await tester.pump();
    await tapSave(tester);

    final p = state.personaById('p_rename')!;
    expect(p.name, '杨成凯');
    expect(p.ownerName, '玖秋辞');
    // 改过名又没单独填「TA 在记录里的名字」→ 用旧名兜底（旧名就是记录里的名字）
    expect(p.sourceName, '小雨');
  });

  testWidgets('没改名时保存，不会把已有的「记录里的名字」清掉', (tester) async {
    final state = await pumpEditor(
      tester,
      base().copyWith(ownerName: '玖秋辞', sourceName: '羊乘客'),
    );

    await tester.enterText(find.byType(TextField).at(1), '玖秋辞改');
    await tester.pump();
    await tapSave(tester);

    final p = state.personaById('p_rename')!;
    expect(p.ownerName, '玖秋辞改');
    expect(p.sourceName, '羊乘客');
  });
}
