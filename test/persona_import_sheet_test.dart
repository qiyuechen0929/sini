import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sini/app_state.dart';
import 'package:sini/theme.dart';
import 'package:sini/widgets/persona_import_sheet.dart';

/// 复现「导入面板打开后一片空白」：直接 pump 导入面板，
/// 断言文件按钮和导入码输入框真的渲染出来了。
/// 不拦截 FlutterError——让测试框架把真实的构建异常完整打出来。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('导入面板初始就应显示：选文件按钮 + 导入码输入框', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    try {
      tester.view.physicalSize = const Size(1170, 2532); // 逻辑 390×844 @dpr3
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppStateScope(
          state: state,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const _SheetHost(),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('选择养成包文件（.sini.json）'), findsOneWidget,
          reason: '选文件按钮应渲染出来');
      expect(find.text('解析导入码'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    } finally {
      state.dispose();
    }
  });
}

class _SheetHost extends StatelessWidget {
  const _SheetHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showPersonaImportSheet(
                context, AppStateScope.of(context)),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }
}
