import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';
import 'core/design/tokens.dart';
import 'core/widgets/sini_sheet.dart';
import 'widgets/composer.dart';
import 'widgets/empty_state.dart';
import 'widgets/message_bubble.dart';
import 'widgets/persona_avatar.dart';

/// 调试条总开关：默认关闭（界面清爽）。需要再排问题时改 true 重新编译。
const bool _kShowDebugBanner = false;

/// 聊天主区域：顶栏 + 消息列表 / 空状态 + 输入栏
class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Removed unused scroll helper; post-frame jumping is inline in _buildList.

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    // 还没有人格：给一个极简「去创建」入口，去掉原先的大段引导页
    if (!state.hasPersonas) {
      return _NoPersonaCTA(p: AppPalette(isDark: Theme.of(context).brightness == Brightness.dark));
    }
    final conv = state.activeConversation;
    // 正在看这条对话 = 已读：清掉未读小红点（覆盖 TA 主动发消息时你恰好不在场的情况）
    if (conv != null && conv.unread > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state.markActiveConversationRead();
      });
    }
    return Column(
      children: [
        // 顶部小条：当前人格 + 状态
        _subHeader(state, conv),
        if (_kShowDebugBanner && state.debugBanner != null) _debugBar(state.debugBanner!),
        Expanded(
          child: conv == null || conv.messages.isEmpty
              // 同样要绑 key：const 实例会被跳过更新，换人格时大标题不会变
              ? EmptyState(key: ValueKey('empty_${state.activePersonaId}'))
              : _buildList(conv, state),
        ),
        // key 绑定人格：切换聊天对象时强制重建输入框，
        // 否则 const 实例会被 Flutter 跳过更新，提示语一直停在旧人格名字上
        Composer(key: ValueKey('composer_${state.activePersonaId}')),
      ],
    );
  }

  Widget _subHeader(AppState state, Conversation? conv) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final persona = state.activePersona;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.mainBg,
        border: Border(bottom: BorderSide(color: p.border, width: 0.5)),
      ),
      child: Row(
        children: [
          if (persona != null) ...[
            PersonaAvatar(persona: persona, size: 20, showSparkle: false),
            const SizedBox(width: 8),
            Text(
              persona.name,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: p.textPrimary),
            ),
            const SizedBox(width: 8),
            Container(width: 3, height: 3, decoration: BoxDecoration(color: p.textTertiary, shape: BoxShape.circle)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              conv == null
                  ? '还没有对话'
                  : conv.messages.isEmpty
                      ? '准备开始…'
                      : '${conv.messages.length} 条消息 · 人格 v1',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: p.textTertiary),
            ),
          ),
          const SizedBox(width: 10),
          _memoryChip(state),
        ],
      ),
    );
  }

  Widget _memoryChip(AppState state) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final n = state.memoryFactCount;
    return InkWell(
      onTap: () => _openMemoryPanel(state),
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: p.itemHover,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_rounded, size: 13, color: p.textSecondary),
            const SizedBox(width: 4),
            Text(
              n == 0 ? '记忆' : '$n',
              style: TextStyle(fontSize: 12, color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  void _openMemoryPanel(AppState state) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final persona = state.activePersona;
    showSiniSheet(
      context: context,
      title: '人格记忆',
      subtitle: '这是「${persona?.name ?? 'TA'}」跨所有对话长期记住的内容——删掉对话、开新对话都还在，'
          '且只属于这个人格、不会串到别人身上。聊得越长，当前对话的早期内容还会被浓缩成「摘要」留在上方。',
      child: StatefulBuilder(
        builder: (ctx, setSt) {
          final memories = state.activePersonaMemory;
          final facts = memories.where((m) => m.kind == PersonaMemoryKind.fact).toList();
          final avoids = memories.where((m) => m.kind == PersonaMemoryKind.avoid).toList();
          final summary = state.activeEarlySummary;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (summary != null && summary.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.itemHover,
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('本对话早期摘要',
                          style: TextStyle(fontSize: 12, color: p.textSecondary)),
                      const SizedBox(height: 6),
                      Text(summary,
                          style: TextStyle(fontSize: 13.5, color: p.textPrimary, height: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (memories.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    summary == null
                        ? '还没有记住任何信息。多聊几句 TA 会自动记住你说的关键事；你也可以直接对它说「记住…」「以后别…」。'
                        : '长期记忆会在对话中自动积累，也可以直接对它说「记住…」「以后别…」。',
                    style: TextStyle(fontSize: 13, color: p.textTertiary, height: 1.5),
                  ),
                )
              else ...[
                if (facts.isNotEmpty) ...[
                  Text('长期记住的', style: TextStyle(fontSize: 12, color: p.textSecondary)),
                  const SizedBox(height: 8),
                  ...facts.map((m) => _memoryRow(p, state, persona, m, setSt)),
                  if (avoids.isNotEmpty) const SizedBox(height: 12),
                ],
                if (avoids.isNotEmpty) ...[
                  Text('用户要求避免的', style: TextStyle(fontSize: 12, color: p.textSecondary)),
                  const SizedBox(height: 8),
                  ...avoids.map((m) => _memoryRow(p, state, persona, m, setSt)),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _memoryRow(
    AppPalette p,
    AppState state,
    Persona? persona,
    PersonaMemory m,
    void Function(void Function()) setSt,
  ) {
    final isAvoid = m.kind == PersonaMemoryKind.avoid;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        children: [
          if (isAvoid) Icon(Icons.block_rounded, size: 14, color: p.textTertiary),
          if (isAvoid) const SizedBox(width: 6),
          Expanded(
            child: Text(m.text,
                style: TextStyle(fontSize: 13.5, color: p.textPrimary, height: 1.4)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              if (persona != null) state.removePersonaMemory(persona.id, m.id);
              setSt(() {});
            },
            child: Icon(Icons.close_rounded, size: 16, color: p.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _debugBar(String text) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: dark ? const Color(0xFF2A2A2E) : const Color(0xFFEFEFEF),
      child: SelectableText(
        text,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          height: 1.4,
          color: dark ? const Color(0xFFD0D0D0) : const Color(0xFF444444),
        ),
      ),
    );
  }

  Widget _buildList(Conversation conv, AppState state) {
    // 订阅消息列表变化
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      itemCount: conv.messages.length,
      itemBuilder: (context, i) {
        final m = conv.messages[i];
        // 自动滚到底部
        if (i == conv.messages.length - 1 && m.streaming) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.jumpTo(_scroll.position.maxScrollExtent);
            }
          });
        } else if (i == conv.messages.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.animateTo(
                _scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
        // 找到触发这条回复的用户提问，供 MessageBubble 判断是否要生成文件
        String? prompt;
        if (!m.isUser) {
          for (int j = i - 1; j >= 0; j--) {
            if (conv.messages[j].isUser) {
              prompt = conv.messages[j].content;
              break;
            }
          }
        }
        return MessageBubble(
          message: m,
          // 头像按「这条消息所属对话的人格」取，而不是当前选中的人格 ——
          // 否则切换人格 / 恢复历史对话后，旧消息的助手头像会消失。
          persona: state.personaOfConversation(conv.id) ?? state.activePersona,
          conversationId: conv.id,
          userPrompt: prompt,
        );
      },
    );
  }
}

/// 没有人格时的极简入口（去掉原先的大段创建引导）
class _NoPersonaCTA extends StatelessWidget {
  final AppPalette p;
  const _NoPersonaCTA({required this.p});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 40, color: p.textTertiary),
          const SizedBox(height: 12),
          Text('先创建一个人格',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.textPrimary)),
          const SizedBox(height: 6),
          Text('创建后就能开始和 TA 聊天了',
              style: TextStyle(fontSize: 13, color: p.textTertiary)),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: p.brand),
            onPressed: () => Navigator.of(context).pushNamed('/persona/new'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('创建人物'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/persona/import'),
            child: Text('或导入聊天记录', style: TextStyle(color: p.textSecondary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
