import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/widgets/sini_sheet.dart';
import '../core/widgets/sini_text_field.dart';
import '../models.dart';
import '../theme.dart';
import 'persona_avatar.dart';

/// 侧栏整体：Logo / 新建对话 / 数字人格 / 最近对话（按时间分组）/ 用户档案。
/// 通过 `isDrawer` 区分：在 Drawer 里时点击"新对话"会自动关闭抽屉。
class Sidebar extends StatelessWidget {
  final bool isDrawer;
  const Sidebar({super.key, this.isDrawer = false});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Material(
      color: p.sidebarBg,
      child: SafeArea(
        right: false,
        bottom: false,
        child: SizedBox(
          width: 280,
          child: Column(
            children: [
              _header(context, p),
              _newChatButton(context, p),
              const SizedBox(height: 6),
              _personaSection(context, p),
              const SizedBox(height: 4),
              const Divider(height: 1, thickness: 1),
              const SizedBox(height: 4),
              Expanded(child: _conversationList(context, p)),
              const Divider(height: 1, thickness: 1),
              _footer(context, p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: p.textPrimary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '似你',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: isDrawer ? '关闭侧栏' : '收起侧栏',
            icon: Icon(
              isDrawer ? Icons.close_rounded : Icons.menu_open_rounded,
              size: 20,
              color: p.textSecondary,
            ),
            onPressed: () {
              if (isDrawer) {
                Scaffold.of(context).closeDrawer();
              } else {
                AppStateScope.of(context).toggleSidebar();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _newChatButton(BuildContext context, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: p.itemHover,
          onTap: () {
            final s = AppStateScope.of(context);
            s.newConversation();
            if (isDrawer) s.setSidebarOpen(false);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 18, color: p.textPrimary),
                const SizedBox(width: 12),
                Text('新对话', style: TextStyle(fontSize: 14, color: p.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _personaSection(BuildContext context, AppPalette p) {
    // 用 of（不是 read）注册依赖：新增/删除人物后侧栏要跟着重建
    final state = AppStateScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '数字人格',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).pushNamed('/persona/new'),
                child: Icon(Icons.add_rounded, size: 16, color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (state.personas.isEmpty)
            _emptyPersonaHint(context, p)
          else
            for (final pe in state.personas) _personaTile(context, pe, p),
        ],
      ),
    );
  }

  /// 还没创建任何人格时的引导行
  Widget _emptyPersonaHint(BuildContext context, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 8, 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: p.itemHover,
          onTap: () => Navigator.of(context).pushNamed('/persona/new'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 15, color: p.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '创建第一个人格',
                    style: TextStyle(fontSize: 13, color: p.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _personaTile(BuildContext context, Persona persona, AppPalette p) {
    final state = AppStateScope.read(context);
    final active = state.activePersonaId == persona.id;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: p.itemHover,
        onTap: () {
          // 切换到这个人格 → 同时切到和 TA 的最近一次对话，并回到聊天首页
          state.selectPersona(persona.id);
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              PersonaAvatar(persona: persona, size: 26, showSparkle: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      persona.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      persona.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: p.textTertiary),
                    ),
                  ],
                ),
              ),
              if (!persona.locked)
                _MoreButton(
                  p: p,
                  primaryLabel: '编辑人格',
                  primaryIcon: Icons.tune_rounded,
                  onRename: () {
                    state.selectPersona(persona.id);
                    Navigator.of(context).pushNamed('/persona/edit');
                  },
                  onDelete: () => _confirmDeletePersona(context, persona, state),
                ),
              if (state.unreadOf(persona.id) > 0)
                _UnreadDot(p: p)
              else if (active)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: p.brand,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 侧栏里删除人格：二次确认（默认助手不允许删除，入口根本不显示）
  Future<void> _confirmDeletePersona(
      BuildContext context, Persona persona, AppState state) async {
    if (persona.locked) return;
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

  Widget _conversationList(BuildContext context, AppPalette p) {
    // of（不是 read）：切换人格时对话列表要跟着重建
    final state = AppStateScope.of(context);
    final active = state.activePersona;
    final list = state.conversationsForActivePersona;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            active == null
                ? '还没有人格，先创建一个吧。'
                : '还没有和${active.name}的对话，\n点上方「新对话」开始。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: p.textTertiary, height: 1.5),
          ),
        ),
      );
    }
    final now = DateTime.now();
    final groups = <ConversationGroup, List<Conversation>>{};
    for (final c in list) {
      groups.putIfAbsent(c.groupKey(now), () => []).add(c);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      children: [
        for (final g in ConversationGroup.values)
          if (groups[g]?.isNotEmpty ?? false) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
              child: Text(
                g.label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: p.textTertiary,
                ),
              ),
            ),
            for (final c in groups[g]!) _conversationTile(context, c, p),
          ],
      ],
    );
  }

  Widget _conversationTile(BuildContext context, Conversation c, AppPalette p) {
    final state = AppStateScope.read(context);
    final active = state.activeConversationId == c.id;
    return _ConversationTile(
      conversation: c,
      active: active,
      isDrawer: isDrawer,
      onTap: () {
        state.selectConversation(c.id);
        if (isDrawer) state.setSidebarOpen(false);
      },
      onRename: () => _showRenameSheet(context, c, state),
      onDelete: () => _showDeleteSheet(context, c, state),
    );
  }

  /// iOS 风底部 Sheet：圆角输入 + 取消/确定
  void _showRenameSheet(BuildContext context, Conversation c, AppState state) {
    final ctl = TextEditingController(text: c.title);
    showSiniSheet<void>(
      context: context,
      title: '重命名对话',
      child: SiniTextField(controller: ctl, hintText: '对话标题', autofocus: true),
      primary: (
        '确定',
        () {
          final t = ctl.text.trim();
          if (t.isNotEmpty) state.renameConversation(c.id, t);
          Navigator.of(context).pop();
        }
      ),
      secondary: ('取消', () => Navigator.of(context).pop()),
    );
  }

  /// iOS 风底部 Sheet：危险动作二次确认
  void _showDeleteSheet(BuildContext context, Conversation c, AppState state) {
    showSiniSheet<void>(
      context: context,
      title: '删除对话？',
      subtitle: '「${c.title}」将被永久删除，无法恢复。',
      primary: (
        '删除',
        () {
          state.deleteConversation(c.id);
          Navigator.of(context).pop();
        }
      ),
      secondary: ('取消', () => Navigator.of(context).pop()),
    );
  }

  Widget _footer(BuildContext context, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        children: [
          _navItem(
            context: context,
            icon: Icons.science_outlined,
            label: '人格实验室',
            p: p,
            onTap: () => Navigator.of(context).pushNamed('/lab'),
          ),
          _navItem(
            context: context,
            icon: Icons.settings_outlined,
            label: '设置',
            p: p,
            onTap: () => Navigator.of(context).pushNamed('/settings'),
          ),
          const SizedBox(height: 6),
          _userCard(context, p),
        ],
      ),
    );
  }

  Widget _navItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required AppPalette p,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: p.itemHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 18, color: p.textSecondary),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(fontSize: 14, color: p.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _userCard(BuildContext context, AppPalette p) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: p.itemHover,
        onTap: () => Navigator.of(context).pushNamed('/settings'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              const UserAvatar(name: '启', size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '陈启粤',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: p.textPrimary),
                    ),
                    Text(
                      '免费版 · 升级',
                      style: TextStyle(fontSize: 11, color: p.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 对话列表项：hover/focus/active 时才显形 `...` 菜单按钮，避免侧栏看着杂乱
class _ConversationTile extends StatefulWidget {
  final Conversation conversation;
  final bool active;
  final bool isDrawer;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  const _ConversationTile({
    required this.conversation,
    required this.active,
    required this.isDrawer,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  final FocusNode _focus = FocusNode();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final c = widget.conversation;
    // 桌面:hover / 焦点 / 当前激活 → 显形；移动端（Drawer）→ 始终显形（没 hover）
    final showMenu = !widget.isDrawer
        ? (_hover || widget.active)
        : true;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: widget.active ? p.itemActive : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: p.itemHover,
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 15,
                  color: widget.active ? p.textPrimary : p.textTertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: widget.active ? p.textPrimary : p.textSecondary,
                      fontWeight: widget.active ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: showMenu ? 1.0 : 0.0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 140),
                    scale: showMenu ? 1.0 : 0.85,
                    child: _MoreButton(
                      onRename: widget.onRename,
                      onDelete: widget.onDelete,
                      p: p,
                    ),
                  ),
                ),
                // 未读小红点：TA 主动发来的消息。有未读时小红点常亮（不受 hover 影响），
                // 用户点开这条对话即清零。
                if (c.unread > 0 && !showMenu) ...[
                  const SizedBox(width: 4),
                  _UnreadDot(p: p),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 侧栏未读小红点（TA 主动找你时的提示）
class _UnreadDot extends StatelessWidget {
  final AppPalette p;
  const _UnreadDot({required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: p.brand,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: p.brand.withValues(alpha: 0.45),
            blurRadius: 5,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }
}

/// `...` 圆角小图标按钮；点击弹出 iOS 风自定义菜单浮层（不是系统的 PopupMenu）
class _MoreButton extends StatefulWidget {
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final AppPalette p;
  /// 第一项的文案（对话列表是「重命名」，人格列表是「编辑人格」）
  final String primaryLabel;
  final IconData primaryIcon;
  const _MoreButton({
    required this.onRename,
    required this.onDelete,
    required this.p,
    this.primaryLabel = '重命名',
    this.primaryIcon = Icons.edit_outlined,
  });

  @override
  State<_MoreButton> createState() => _MoreButtonState();
}

class _MoreButtonState extends State<_MoreButton> {
  final GlobalKey _key = GlobalKey();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: widget.p.itemHover,
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(Icons.more_horiz_rounded, size: 16, color: widget.p.textSecondary),
          ),
        ),
      ),
    );
  }

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    final overlay = Overlay.of(context);
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final size = renderBox.size;
    final overlaySize = overlayBox.size;

    // 浮层放在按钮正下方，宽度 160。优先往右铺；右边不够再往左铺。
    const menuWidth = 160.0;
    final rightSpace = overlaySize.width - topLeft.dx - size.width;
    final leftSpace = topLeft.dx;
    final double left;
    if (rightSpace >= menuWidth + 8) {
      left = topLeft.dx + size.width - menuWidth;
    } else if (leftSpace >= menuWidth + 8) {
      left = topLeft.dx;
    } else {
      left = (overlaySize.width - menuWidth) / 2;
    }
    final top = topLeft.dy + size.height + 6;

    final entry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            // 全屏透明遮罩，吸收外部点击关闭
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _close,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: Material(
                color: widget.p.surface,
                elevation: 0,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: widget.p.border, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF000000).withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MenuRow(
                        icon: widget.primaryIcon,
                        label: widget.primaryLabel,
                        color: widget.p.textPrimary,
                        p: widget.p,
                        onTap: () {
                          _close();
                          widget.onRename();
                        },
                      ),
                      Container(height: 0.5, color: widget.p.border),
                      _MenuRow(
                        icon: Icons.delete_outline_rounded,
                        label: '删除',
                        color: const Color(0xFFB42318),
                        p: widget.p,
                        onTap: () {
                          _close();
                          widget.onDelete();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    _entry = entry;
    overlay.insert(entry);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final AppPalette p;
  final VoidCallback onTap;
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.p,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        hoverColor: p.itemHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(fontSize: 13.5, color: color, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sheet 底部圆角按钮（取消/确定/删除）
class _SheetButton extends StatelessWidget {
  final String label;
  final bool filled;
  final bool danger;
  final VoidCallback onTap;
  const _SheetButton({
    required this.label,
    required this.filled,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final Color bg;
    final Color fg;
    if (filled) {
      if (danger) {
        bg = const Color(0xFFB42318);
        fg = Colors.white;
      } else {
        bg = p.textPrimary;
        fg = p.inverseOn;
      }
    } else {
      bg = p.itemHover;
      fg = p.textPrimary;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
