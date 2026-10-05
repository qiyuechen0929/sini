import 'package:flutter/material.dart';

import 'app_state.dart';
import 'chat_view.dart';
import 'theme.dart';
import 'utils/persona_bg.dart';
import 'widgets/sidebar.dart';
import 'widgets/top_bar.dart';

/// 桌面 + 移动自适应：
/// - 宽 >= 720：固定左侧栏（可折叠到 0）
/// - 宽 < 720：侧栏改成 Drawer
class HomeShell extends StatelessWidget {
  static const double kMobileBreakpoint = 720;
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return LayoutBuilder(
      builder: (context, c) {
        final isMobile = c.maxWidth < HomeShell.kMobileBreakpoint;
        return Scaffold(
          backgroundColor: p.mainBg,
          drawer: isMobile
              ? Drawer(
                  backgroundColor: p.sidebarBg,
                  elevation: 0,
                  width: 280,
                  child: const Sidebar(isDrawer: true),
                )
              : null,
          body: SafeArea(
            child: isMobile ? const _MobileBody() : const _DesktopBody(),
          ),
        );
      },
    );
  }
}

class _DesktopBody extends StatelessWidget {
  const _DesktopBody();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final persona = state.activePersona;
    final usePersonaBg =
        state.personaBgEnabled && persona != null && !persona.locked;

    Widget chatArea = const Column(
      children: [
        TopBar(),
        Expanded(child: ChatView()),
      ],
    );
    if (usePersonaBg) {
      chatArea = PersonaChatBackground(persona: persona, child: chatArea);
    } else {
      chatArea = ColoredBox(color: p.mainBg, child: chatArea);
    }

    return Row(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: state.sidebarOpen
              ? const Sidebar()
              : const SizedBox(width: 0, height: 0),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: p.border, width: 0.5)),
            ),
            child: chatArea,
          ),
        ),
      ],
    );
  }
}

class _MobileBody extends StatelessWidget {
  const _MobileBody();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final persona = state.activePersona;
    final usePersonaBg =
        state.personaBgEnabled && persona != null && !persona.locked;

    final body = const Column(
      children: [
        TopBar(),
        Expanded(child: ChatView()),
      ],
    );

    if (!usePersonaBg) {
      return ColoredBox(color: p.mainBg, child: body);
    }
    return PersonaChatBackground(persona: persona!, child: body);
  }
}
