import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart' show ConversationSearchHit;
import '../theme.dart';
import 'model_picker_sheet.dart';

/// 顶部栏：左侧折叠按钮，中间模型选择器，右侧主题切换。
/// 在窄屏（移动端）：按钮调用 `Scaffold.openDrawer()` 弹出 Drawer；
/// 在宽屏（桌面）：按钮走 `AppState.toggleSidebar()` 折叠固定侧栏。
class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 720;
    // 初始引导页（还没人格且没跳过）：藏掉左侧栏按钮和语音/视频——这个界面上没有可聊的对象
    final bool onGuide = !state.hasPersonas && !state.guideSkipped;
    // 没有任何人格时不给语音/视频入口
    final bool showCall = state.hasPersonas;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: p.mainBg,
        border: Border(bottom: BorderSide(color: p.border, width: 0.5)),
      ),
      child: Row(
        children: [
          if (!onGuide)
            IconButton(
              tooltip: isMobile ? '打开侧栏' : (state.sidebarOpen ? '收起侧栏' : '打开侧栏'),
              icon: Icon(
                isMobile
                    ? Icons.menu_rounded
                    : (state.sidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded),
                size: 20,
                color: p.textSecondary,
              ),
              onPressed: () {
                if (isMobile) {
                  Scaffold.of(context).openDrawer();
                } else {
                  AppStateScope.of(context).toggleSidebar();
                }
              },
            )
          else
            const SizedBox(width: 8),
          const Spacer(),
          // 还没有人格时不显示模型选择器（没有可套用的人格）
          if (state.hasPersonas) const ModelPickerButton() else const SizedBox.shrink(),
          const Spacer(),
          if (showCall) ...[
            // 语音通话 / 视频通话：前端已搭好，但功能还没开发完，入口先锁住。
            // 解锁时把这两个 _LockedCallButton 换回原来的 IconButton 即可
            // （路由 /voice 和 /call 都还在 app_router 里，不用动）。
            const _LockedCallButton(icon: Icons.graphic_eq_rounded, label: '语音通话'),
            const _LockedCallButton(icon: Icons.video_call_outlined, label: '视频通话'),
          ],
          if (state.hasPersonas)
            IconButton(
              tooltip: '搜索对话',
              icon: Icon(Icons.search_rounded, size: 20, color: p.textSecondary),
              onPressed: () => _openSearchSheet(context),
            ),
          IconButton(
            tooltip: state.isDark ? '切换为浅色' : '切换为深色',
            icon: Icon(
              state.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 20,
              color: p.textSecondary,
            ),
            onPressed: () => AppStateScope.of(context).toggleTheme(),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// 对话搜索弹层
void _openSearchSheet(BuildContext context) {
  final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
  final state = AppStateScope.read(context);
  final q = TextEditingController();
  var hits = <ConversationSearchHit>[];

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              height: MediaQuery.of(ctx).size.height * 0.72,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: p.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('搜索对话',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.textPrimary)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: q,
                    autofocus: true,
                    style: TextStyle(fontSize: 14, color: p.textPrimary),
                    decoration: InputDecoration(
                      hintText: '搜你们聊过的话…',
                      hintStyle: TextStyle(color: p.textTertiary, fontSize: 13),
                      prefixIcon: Icon(Icons.search_rounded, size: 18, color: p.textTertiary),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) {
                      setModalState(() {
                        hits = state.searchMessages(q.text);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: hits.isEmpty
                        ? Center(
                            child: Text(
                              q.text.trim().isEmpty ? '输入关键词开始搜索' : '没有搜到相关内容',
                              style: TextStyle(fontSize: 13, color: p.textTertiary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: hits.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (_, i) {
                              final h = hits[i];
                              return Material(
                                color: p.itemHover,
                                borderRadius: BorderRadius.circular(12),
                                child: ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  title: Text(
                                    h.snippet,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: p.textPrimary, height: 1.4),
                                  ),
                                  subtitle: Text(
                                    '${h.isUser ? "我" : "TA"} · ${h.conversationTitle}',
                                    style: TextStyle(fontSize: 11, color: p.textTertiary),
                                  ),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    state.selectConversation(h.conversationId);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 被锁住的入口按钮：功能未完成时的占位。
///
/// 视觉上把图标调淡、右下角挂一把小锁；点击不跳转，只提示「开发中」。
/// 这样功能入口仍然可见（用户知道有这个东西），但不会被点进半成品界面。
class _LockedCallButton extends StatelessWidget {
  const _LockedCallButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return IconButton(
      tooltip: '$label（开发中）',
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label功能还在开发中，敬请期待'),
            duration: const Duration(milliseconds: 1800),
          ),
        );
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 20, color: p.textTertiary.withValues(alpha: 0.5)),
          Positioned(
            right: -4,
            bottom: -2,
            child: Icon(
              Icons.lock_rounded,
              size: 10,
              color: p.textTertiary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
