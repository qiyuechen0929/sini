// 把主要界面渲染成 PNG，存到 screenshots/ 目录。
// 用 SimHei 解决测试环境无中文字体的问题。
// 运行：flutter test test/golden_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sini/app_state.dart';
import 'package:sini/home_shell.dart';
import 'package:sini/persona_lab_page.dart';
import 'package:sini/settings_page.dart';
import 'package:sini/theme.dart';

const String _outDir = '../screenshots';

/// 加载系统里的 SimHei.ttf 注册到 Flutter 测试引擎。
Future<void> _loadSimHei() async {
  final file = File('C:/Windows/Fonts/simhei.ttf');
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  final loader = FontLoader('SimHei');
  loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

Future<void> _save(WidgetTester tester, String name) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 800));
  final binding = tester.binding;
  await binding.runAsync(() async {
    // 再多 pump 一下让 repaint boundary 完成布局
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final List<ui.Image> images = [];
    Future<void> visit(RenderObject obj) async {
      if (obj is RenderRepaintBoundary) {
        if (obj.hasSize && obj.size.width > 1 && obj.size.height > 1) {
          try {
            images.add(await obj.toImage(pixelRatio: 1.0));
          } catch (_) {
            // ignore: avoid_print
            print('skip repaint boundary at ${obj.debugSemantics?.toStringDeep()}');
          }
        }
      }
      obj.visitChildren((child) {
        visit(child);
      });
    }
    final RenderObject? rootObj = binding.renderViewElement?.renderObject;
    if (rootObj != null) await visit(rootObj);
    if (images.isEmpty) return;
    images.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    final img = images.first;
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final dir = Directory(_outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('$_outDir/$name.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    for (final i in images) {
      i.dispose();
    }
    // ignore: avoid_print
    print('saved $_outDir/$name.png (${img.width}x${img.height})');
  });
}

ThemeData _themed(Brightness b) {
  final t = b == Brightness.dark ? AppTheme.dark() : AppTheme.light();
  // 在每个 TextStyle 上覆盖字体
  const ff = 'SimHei';
  TextStyle _map(TextStyle? s) =>
      (s ?? const TextStyle()).copyWith(fontFamily: ff, fontFamilyFallback: const [ff, 'Microsoft YaHei', 'sans-serif']);
  TextTheme _mapText(TextTheme t) => TextTheme(
        displayLarge: _map(t.displayLarge),
        displayMedium: _map(t.displayMedium),
        displaySmall: _map(t.displaySmall),
        headlineLarge: _map(t.headlineLarge),
        headlineMedium: _map(t.headlineMedium),
        headlineSmall: _map(t.headlineSmall),
        titleLarge: _map(t.titleLarge),
        titleMedium: _map(t.titleMedium),
        titleSmall: _map(t.titleSmall),
        bodyLarge: _map(t.bodyLarge),
        bodyMedium: _map(t.bodyMedium),
        bodySmall: _map(t.bodySmall),
        labelLarge: _map(t.labelLarge),
        labelMedium: _map(t.labelMedium),
        labelSmall: _map(t.labelSmall),
      );
  return t.copyWith(textTheme: _mapText(t.textTheme));
}

Widget _wrap(Widget child, {required double width, required double height, ThemeMode mode = ThemeMode.light}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _themed(Brightness.light),
    darkTheme: _themed(Brightness.dark),
    themeMode: mode,
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, height), devicePixelRatio: 1.0),
      child: child,
    ),
  );
}

AppState _newState({bool withMessages = false}) {
  final s = AppState();
  s.selectPersona(s.personas.first.id);
  s.newConversation();
  if (withMessages) {
    s.sendUserMessage('今天做点什么好？');
    s.sendUserMessage('帮我把这段经历写进日记');
  }
  return s;
}

void _setSize(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    await _loadSimHei();
  });

  testWidgets('mobile_light_home_with_messages', (tester) async {
    _setSize(tester, 390, 844);
    final state = _newState();
    state.sendUserMessage('今天做点什么好？');
    await tester.pump(const Duration(milliseconds: 100));
    state.sendUserMessage('帮我把这段经历写进日记');
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      AppStateScope(state: state, child: _wrap(const HomeShell(), width: 390, height: 844)),
    );
    await _save(tester, 'mobile_light_home_with_messages');
  });

  testWidgets('mobile_light_home_empty', (tester) async {
    _setSize(tester, 390, 844);
    final state = _newState();
    await tester.pumpWidget(
      AppStateScope(state: state, child: _wrap(const HomeShell(), width: 390, height: 844)),
    );
    await _save(tester, 'mobile_light_home_empty');
  });

  testWidgets('mobile_dark_home_with_messages', (tester) async {
    _setSize(tester, 390, 844);
    final state = _newState();
    state.toggleTheme();
    state.sendUserMessage('今天做点什么好？');
    state.sendUserMessage('帮我把这段经历写进日记');
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      AppStateScope(
        state: state,
        child: _wrap(const HomeShell(), width: 390, height: 844, mode: ThemeMode.dark),
      ),
    );
    await _save(tester, 'mobile_dark_home_with_messages');
  });

  testWidgets('mobile_dark_drawer_open', (tester) async {
    _setSize(tester, 390, 844);
    final state = _newState();
    state.toggleTheme();
    state.sendUserMessage('今天做点什么好？');
    state.sendUserMessage('帮我把这段经历写进日记');
    state.sendUserMessage('回忆我们最近一次见面的场景');
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      AppStateScope(
        state: state,
        child: _wrap(const HomeShell(), width: 390, height: 844, mode: ThemeMode.dark),
      ),
    );
    // 在移动端侧栏就是 Drawer，sidebarOpen 状态对它不影响。点击顶栏第一个 IconButton
    // （即菜单按钮）就能打开 Drawer。
    Finder? menu;
    if (find.byIcon(Icons.menu_rounded).evaluate().isNotEmpty) {
      menu = find.byIcon(Icons.menu_rounded).first;
    } else if (find.byIcon(Icons.menu_open_rounded).evaluate().isNotEmpty) {
      menu = find.byIcon(Icons.menu_open_rounded).first;
    } else {
      // 兜底：点第一个 IconButton
      menu = find.byType(IconButton).first;
    }
    await tester.tap(menu);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await _save(tester, 'mobile_dark_drawer_open');
  });

  testWidgets('mobile_light_settings', (tester) async {
    _setSize(tester, 390, 844);
    final state = _newState();
    await tester.pumpWidget(
      AppStateScope(state: state, child: _wrap(const SettingsPage(), width: 390, height: 844)),
    );
    await _save(tester, 'mobile_light_settings');
  });

  testWidgets('mobile_light_persona_lab', (tester) async {
    _setSize(tester, 390, 844);
    final state = _newState();
    await tester.pumpWidget(
      AppStateScope(state: state, child: _wrap(const PersonaLabPage(), width: 390, height: 1100)),
    );
    await _save(tester, 'mobile_light_persona_lab');
  });
}
