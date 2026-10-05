import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/widgets/sini_sheet.dart';
import '../core/widgets/sini_text_field.dart';
import '../models.dart';
import '../theme.dart';
import '../utils/safe_text.dart' show safeClip;
import 'email_compose_card.dart';
import 'image_gen_card.dart';
import '../utils/export_file.dart';
import '../utils/moments.dart' show momentTitleFromText;
import '../utils/quote_reply.dart' show quotePreview;
import '../utils/recommend_card.dart' as rec;
import '../utils/route_card.dart' as rc;
import 'markdown_view.dart';
import 'persona_avatar.dart';
import 'recommend_card.dart';
import 'route_card.dart';
import 'thinking_dots.dart';

/// 单条消息 + 下方操作行（仅助手消息）
class MessageBubble extends StatefulWidget {
  final Message message;
  final Persona? persona;
  /// 所属对话 id，用于把反馈（好/不好）持久化到这条消息上
  final String conversationId;
  /// 触发这条回复的用户提问，用于判断用户是否真的要生成文件
  final String? userPrompt;
  const MessageBubble({
    super.key,
    required this.message,
    this.persona,
    required this.conversationId,
    this.userPrompt,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  /// 反馈状态直接读消息对象本身（已持久化），不再用易丢失的本地字段。
  bool get _liked => widget.message.feedback == MessageFeedback.like;
  bool get _disliked => widget.message.feedback == MessageFeedback.dislike;

  /// 「编辑重发」输入框的控制器：放在 State 里，sheet 的确认按钮才能读到最新文本
  final TextEditingController _editCtl = TextEditingController();

  @override
  void dispose() {
    _editCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final m = widget.message;
    // 只有用户真的要文件（或 AI 给出了完整 HTML 文档）时才挂产物卡
    final base = widget.persona?.name ?? '似你回复';
    final ts = m.createdAt.millisecondsSinceEpoch;
    final List<MessageAttachment> autoFiles = <MessageAttachment>[];
    if (!m.isUser && !m.streaming && m.content.trim().isNotEmpty) {
      final kinds = detectFileKinds(
        userPrompt: widget.userPrompt ?? '',
        aiText: m.content,
      );
      for (final k in kinds) {
        final String name;
        final String content;
        switch (k) {
          case FileKind.html:
            name = '${safeFileName(base)}_$ts.html';
            content = buildHtmlExport(base, m.content);
            break;
          case FileKind.word:
            name = '${safeFileName(base)}_$ts.doc';
            content = buildWordExport(base, m.content);
            break;
          case FileKind.ppt:
            // 自包含 HTML 幻灯片：可在 app 内直接翻页播放
            name = '${safeFileName(base)}_$ts.slides.html';
            content = buildSlidesExport(base, m.content);
            break;
          case FileKind.md:
            name = '${safeFileName(base)}_$ts.md';
            content = m.content;
            break;
        }
        autoFiles.add(MessageAttachment(
          name: name,
          sizeBytes: utf8.encode(content).length,
          kind: MessageAttachmentKind.file,
          bytes: utf8.encode(content),
          // Word / Markdown 卡可在 app 内用 markdown 渲染器「查看内容」，
          // 避免浏览器没法直接渲染 .doc/.md、用户只能下载的尴尬。
          // HTML / PPT 不需要：点开就是可运行的 iframe。
          previewText: (k == FileKind.word || k == FileKind.md) ? m.content : null,
        ));
      }
    }
    final allAttachments = <MessageAttachment>[
      ...m.attachments,
      ...autoFiles,
    ];
    // 问路场景：用户问"从 A 到 B 怎么走"时挂路线卡片（可跳转高德/腾讯地图）
    final routeInfo = (!m.isUser && !m.streaming)
        ? (() {
            final prompt = widget.userPrompt ?? '';
            if (!rc.isRouteQuestion(prompt)) return null;
            return rc.parseRoute(prompt);
          })()
        : null;
    // 推荐场景：用户问"附近有什么好吃的/好喝的/好玩的"时挂推荐卡片
    // （6 个平台跳转：高德/腾讯地图、美团/大众点评、京东/淘宝）。
    // 注意：问路卡片优先级更高，已出路线卡时不再出推荐卡，避免两张卡堆叠。
    final recommendInfo = (!m.isUser && !m.streaming && routeInfo == null)
        ? (() {
            final prompt = widget.userPrompt ?? '';
            if (!rec.isRecommendQuestion(prompt)) return null;
            return rec.parseRecommend(prompt);
          })()
        : null;

    return Column(
      crossAxisAlignment: m.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // 消息本体：自己长按 = 复制/编辑/撤回；TA 长按 = 复制/引用回复
        GestureDetector(
          onLongPress: m.isUser ? _openUserMessageActions : _openAssistantMessageActions,
          child: Row(
          mainAxisAlignment: m.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!m.isUser && widget.persona != null) ...[
              PersonaAvatar(persona: widget.persona!, size: 30, showSparkle: true),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: m.isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // TA 主动找你时给一个小标记：让用户明白"这条是 TA 先开的口"
                  if (m.proactive && !m.isUser) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.waving_hand_rounded,
                              size: 12, color: p.textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.persona?.name ?? 'TA'} 主动来找你',
                            style: TextStyle(
                                fontSize: 11, color: p.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Container(
                    // 用户消息：灰底圆角气泡（iOS 风格），配合外层右对齐，一眼区分"谁说的"
                    padding: m.isUser
                        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                        : EdgeInsets.zero,
                    decoration: m.isUser
                        ? BoxDecoration(
                            color: p.userBubble,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(18),
                              bottomLeft: Radius.circular(18),
                              bottomRight: Radius.circular(5),
                            ),
                          )
                        : null,
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: m.isUser
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 引用块：这条消息引用了之前的某句
                        if (m.quoteText != null && m.quoteText!.trim().isNotEmpty) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: p.itemHover,
                              borderRadius: BorderRadius.circular(10),
                              border: Border(
                                left: BorderSide(color: p.brand.withValues(alpha: 0.7), width: 3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.quoteIsUser ? '引用我' : '引用 TA',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: p.brand,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  quotePreview(m.quoteText!, max: 80),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: p.textSecondary,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (allAttachments.isNotEmpty) ...[
                          _AttachmentGrid(
                            attachments: allAttachments,
                            p: p,
                            onFileTap: _openFileSheet,
                          ),
                          if (m.content.isNotEmpty || m.streaming)
                            const SizedBox(height: 8),
                        ],
                        if (m.content.isNotEmpty || m.streaming)
                          m.streaming && m.content.trim().isEmpty
                              ? (m.emailCompose
                                  ? const EmailComposeCard()
                                  : m.generatingImage
                                      ? ImageGenCard(prompt: m.imagePrompt ?? '')
                                      : ThinkingBubble(p: p))
                              : SelectionArea(
                                  // TA 的话可划选，配合长按菜单「划词解释」
                                  child: SiniMarkdown(
                                    text: m.content,
                                    streaming: m.streaming,
                                    isUser: m.isUser,
                                  ),
                                ),
                        // 路线卡片（问路时自动出现，可跳高德/腾讯）
                        if (routeInfo != null) ...[
                          const SizedBox(height: 10),
                          RouteCard(route: routeInfo),
                        ],
                        // 推荐卡片（问"附近/推荐"时自动出现，6 个平台一键跳转）
                        if (recommendInfo != null) ...[
                          const SizedBox(height: 10),
                          RecommendCard(info: recommendInfo),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
        // 操作行（仅助手）
        if (!m.isUser) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: _ActionsRow(
              streaming: m.streaming,
              liked: _liked,
              disliked: _disliked,
              onCopy: () => _copyMessage(m.content),
              onRegenerate: () {
                AppStateScope.of(context).regenerateLast();
              },
              onLike: () => AppStateScope.of(context)
                  .setMessageFeedback(
                      widget.conversationId, m.id, MessageFeedback.like),
              onDislike: () {
                final state = AppStateScope.of(context);
                // 已点踩则再点取消；否则弹原因选择
                if (_disliked) {
                  state.setMessageFeedback(
                      widget.conversationId, m.id, MessageFeedback.dislike);
                } else {
                  _openDislikeSheet(state, m.id);
                }
              },
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  /// 点文件卡：HTML 直接在 app 内 iframe 预览；Word/其它则出详情 + 下载
  /// （下载后系统会用 WPS / Word 等默认应用打开）。
  void _openFileSheet(MessageAttachment a) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final lower = a.name.toLowerCase();
    final content = a.bytes == null ? '' : utf8.decode(a.bytes!);
    final mime = mimeForName(a.name);

    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      // HTML：Web 上直接 iframe 预览；手机端没有 platform view 的等价物，
      // 降级成「存成文件」，让用户用系统浏览器打开。
      final viewType = registerHtmlPreview(content);
      if (viewType == null) {
        saveAndNotify(context, () => downloadTextFile(a.name, content, mime));
        return;
      }
      showSiniSheet<void>(
        context: context,
        title: '预览 HTML',
        subtitle: a.name,
        child: SizedBox(
          height: 420,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: HtmlElementView(viewType: viewType),
          ),
        ),
        secondary: ('下载到本机', () {
          Navigator.pop(context);
          saveAndNotify(
              context, () => downloadTextFile(a.name, content, mime));
        }),
        tertiary: ('关闭', () => Navigator.pop(context)),
      );
      return;
    }

    // Word / Markdown：默认出文件详情 + 下载；但若附带了原文 markdown，
    // 用户也可以「在 app 内查看内容」直接阅读，不必非下载不可。
    final isDoc = mime.startsWith('application/');
    final isMd = lower.endsWith('.md');
    final canPreviewContent = isDoc || isMd;
    final previewText = a.previewText ?? '';

    Widget body() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FileSummaryCard(a: a, p: p),
          const SizedBox(height: 12),
          Text(
            isDoc
                ? 'Word 文档浏览器无法直接渲染。点「下载到本机」保存后，系统会用 WPS / Word 等默认应用打开；'
                    '也可以先「在 app 内查看内容」直接阅读。'
                : '点「下载到本机」保存到本机；也可以先「在 app 内查看内容」直接阅读。',
            style: TextStyle(fontSize: 12, color: p.textSecondary, height: 1.55),
          ),
        ],
      );
    }

    if (canPreviewContent && previewText.isNotEmpty) {
      // 三段按钮：查看内容（主）/ 下载到本机（次）/ 关闭
      showSiniSheet<void>(
        context: context,
        title: '文件已生成',
        subtitle: a.name,
        child: body(),
        primary: (
          '在 app 内查看内容',
          () {
            Navigator.pop(context);
            _showMarkdownPreview(a.name, previewText);
          },
        ),
        secondary: ('下载到本机', () {
          Navigator.pop(context);
          saveAndNotify(context, () => downloadTextFile(a.name, content, mime));
        }),
        tertiary: ('关闭', () => Navigator.pop(context)),
      );
      return;
    }

    showSiniSheet<void>(
      context: context,
      title: '文件已生成',
      subtitle: a.name,
      child: body(),
      secondary: ('下载到本机', () {
        Navigator.pop(context);
        saveAndNotify(context, () => downloadTextFile(a.name, content, mime));
      }),
      tertiary: ('关闭', () => Navigator.pop(context)),
    );
  }

  /// 用 markdown 渲染器在 app 内展示文档正文（Word / Markdown 文件卡点开的内容）。
  void _showMarkdownPreview(String title, String md) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    showSiniSheet<void>(
      context: context,
      title: '查看内容',
      subtitle: title,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SiniMarkdown(
            text: md,
            streaming: false,
            isUser: false,
          ),
        ),
      ),
      tertiary: ('关闭', () => Navigator.pop(context)),
    );
  }

  // ── 撤回 / 编辑重发（真人感细节：发错话可以改） ──

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('已复制'), duration: Duration(milliseconds: 1200)),
    );
  }

  /// 长按消息 → 记入回忆册
  void _markMoment(Message m) {
    final state = AppStateScope.of(context);
    final personaId = state.activePersona?.id;
    if (personaId == null) return;
    state.addMoment(
      personaId: personaId,
      title: momentTitleFromText(m.content),
      manual: true,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已记入回忆册'),
        duration: Duration(milliseconds: 1400),
      ),
    );
  }

  /// 划词解释：优先用当前选中文本，否则让用户输入/粘贴要问的词
  void _openExplainSheet(Message m) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final ctl = TextEditingController();
    // 预填：优先用划选；拿不到选区就留空让用户输入
    // （Selection API 在不同 Flutter 版本差异大，这里做软处理）

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('划词解释',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: p.textPrimary)),
                const SizedBox(height: 6),
                Text('在 TA 的话里选中一个词，或者自己输入。TA 会用大白话讲给你听。',
                    style: TextStyle(fontSize: 12.5, color: p.textSecondary, height: 1.5)),
                const SizedBox(height: 14),
                TextField(
                  controller: ctl,
                  autofocus: ctl.text.isEmpty,
                  style: TextStyle(fontSize: 14, color: p.textPrimary),
                  decoration: InputDecoration(
                    hintText: '要解释的词 / 短语',
                    hintStyle: TextStyle(color: p.textTertiary, fontSize: 13),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: p.border)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: Text('取消', style: TextStyle(color: p.textTertiary)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: p.brand,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          final word = ctl.text.trim();
                          if (word.isEmpty) return;
                          Navigator.pop(sheetCtx);
                          final state = AppStateScope.read(context);
                          state.sendUserMessage('「$word」是什么意思？用你的话简单讲讲');
                        },
                        child: const Text('让 TA 讲讲'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 长按 TA 的消息 → 复制 / 引用回复
  void _openAssistantMessageActions() {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final m = widget.message;
    if (m.content.trim().isEmpty) return;
    final state = AppStateScope.of(context);

    Widget row({
      required IconData icon,
      required String label,
      String? hint,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: p.itemHover,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: p.textPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label,
                            style: TextStyle(fontSize: 13.5, color: p.textPrimary)),
                        if (hint != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(hint,
                                style: TextStyle(
                                    fontSize: 11.5, color: p.textTertiary)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    showSiniSheet<void>(
      context: context,
      title: '这条消息',
      subtitle: quotePreview(m.content, max: 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          row(
            icon: Icons.format_quote_rounded,
            label: '引用回复',
            hint: '针对这句话追问 TA',
            onTap: () {
              Navigator.pop(context);
              state.setPendingQuote(m);
            },
          ),
          row(
            icon: Icons.translate_outlined,
            label: '划词解释',
            hint: '让 TA 用大白话讲某个词',
            onTap: () {
              Navigator.pop(context);
              _openExplainSheet(m);
            },
          ),
          row(
            icon: Icons.auto_stories_outlined,
            label: '记入回忆',
            hint: '把这句话存进回忆册时间线',
            onTap: () {
              Navigator.pop(context);
              _markMoment(m);
            },
          ),
          row(
            icon: Icons.content_copy_outlined,
            label: '复制',
            onTap: () {
              Navigator.pop(context);
              _copyMessage(m.content);
            },
          ),
        ],
      ),
    );
  }

  /// 长按自己发的消息 → 操作菜单（复制 / 编辑重发 / 撤回）
  void _openUserMessageActions() {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final m = widget.message;
    final state = AppStateScope.of(context);
    final after = state.messagesAfterMessage(widget.conversationId, m.id);

    Widget row({
      required IconData icon,
      required String label,
      String? hint,
      Color? color,
      required VoidCallback onTap,
    }) {
      final c = color ?? p.textPrimary;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: p.itemHover,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: c),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: TextStyle(fontSize: 13.5, color: c)),
                        if (hint != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(hint,
                                style: TextStyle(
                                    fontSize: 11.5, color: p.textTertiary)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final preview = m.content.trim();
    showSiniSheet<void>(
      context: context,
      title: '这条消息',
      subtitle: preview.isEmpty
          ? null
          : '${safeClip(preview, 60)}${preview.length > 60 ? '…' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          row(
            icon: Icons.content_copy_outlined,
            label: '复制',
            onTap: () {
              Navigator.pop(context);
              _copyMessage(m.content);
            },
          ),
          row(
            icon: Icons.edit_outlined,
            label: '编辑重发',
            hint: '改完让 TA 按新的说法重新理解',
            onTap: () {
              Navigator.pop(context);
              _openEditSheet(state, m);
            },
          ),
          row(
            icon: Icons.undo_rounded,
            label: '撤回',
            hint: after > 0
                ? '这条之后还有 $after 条，会一起收回'
                : 'TA 的回复会一起收回',
            color: const Color(0xFFB42318),
            onTap: () {
              Navigator.pop(context);
              _openRecallConfirm(state, m, after);
            },
          ),
        ],
      ),
      tertiary: ('取消', () => Navigator.pop(context)),
    );
  }

  /// 编辑重发：弹出可改的输入框，确认后用新文本重新问一遍
  void _openEditSheet(AppState state, Message m) {
    _editCtl.text = m.content;
    _editCtl.selection = TextSelection.collapsed(offset: _editCtl.text.length);
    showSiniSheet<void>(
      context: context,
      title: '编辑重发',
      subtitle: 'TA 会按新的说法重新理解；原来那条回复会被收回',
      child: SiniTextField(
        controller: _editCtl,
        hintText: '说点什么…',
        minLines: 2,
        maxLines: 6,
        autofocus: true,
      ),
      primary: (
        '重新发送',
        () {
          final t = _editCtl.text.trim();
          Navigator.pop(context);
          if (t.isEmpty) return;
          state.editAndResend(widget.conversationId, m.id, t);
        },
      ),
      secondary: ('取消', () => Navigator.pop(context)),
    );
  }

  /// 撤回前的确认：因为 TA 的回复会跟着一起收回，先说清楚再动手
  void _openRecallConfirm(AppState state, Message m, int after) {
    showSiniSheet<void>(
      context: context,
      title: '撤回这条消息？',
      subtitle: after > 0
          ? '这条之后的 $after 条对话会被一起收回，TA 也不会再记得你说过这句。'
          : 'TA 的回复会一起收回，就像你没说过这句话。',
      primary: (
        '确认撤回',
        () {
          Navigator.pop(context);
          final text = state.recallMessage(widget.conversationId, m.id);
          if (text == null) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('已撤回'), duration: Duration(milliseconds: 1200)),
          );
        },
      ),
      secondary: ('取消', () => Navigator.pop(context)),
      danger: true,
    );
  }

  /// 点「不好」时弹出原因选择（参考 ChatGPT），选完把反馈+原因写回消息。
  void _openDislikeSheet(AppState state, String msgId) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final reasons = const [
      '不准确 / 与事实不符',
      '不相关 / 答非所问',
      '太啰嗦 / 不够简洁',
      '格式混乱 / 排版差',
      '语气不对 / 不像这个人',
      '其它',
    ];
    showSiniSheet<void>(
      context: context,
      title: '这条回复哪里不好？',
      subtitle: '你的反馈会记在这条消息上',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: p.itemHover,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(context);
                    state.setMessageFeedback(
                      widget.conversationId,
                      msgId,
                      MessageFeedback.dislike,
                      reason: r,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.thumb_down_outlined,
                            size: 16, color: p.textSecondary),
                        const SizedBox(width: 10),
                        Text(r,
                            style:
                                TextStyle(fontSize: 13.5, color: p.textPrimary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      tertiary: ('取消', () => Navigator.pop(context)),
    );
  }
}

/// 文件详情卡：图标 + 文件名 + 类型 + 大小（sheet 内使用）
class _FileSummaryCard extends StatelessWidget {
  final MessageAttachment a;
  final AppPalette p;
  const _FileSummaryCard({required this.a, required this.p});

  @override
  Widget build(BuildContext context) {
    final lower = a.name.toLowerCase();
    final IconData icon;
    final String label;
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      icon = Icons.code;
      label = 'HTML';
    } else if (lower.endsWith('.doc')) {
      icon = Icons.description_outlined;
      label = 'Word';
    } else if (lower.endsWith('.pdf')) {
      icon = Icons.picture_as_pdf_outlined;
      label = 'PDF';
    } else {
      icon = Icons.insert_drive_file_outlined;
      label = 'FILE';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: p.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(label, style: TextStyle(fontSize: 11, color: p.textTertiary)),
                    const SizedBox(width: 8),
                    Text(a.sizeLabel,
                        style: TextStyle(fontSize: 11, color: p.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 消息附件：图片出缩略图网格，文件出名称小卡
class _AttachmentGrid extends StatelessWidget {
  final List<MessageAttachment> attachments;
  final AppPalette p;
  final void Function(MessageAttachment) onFileTap;
  const _AttachmentGrid({
    required this.attachments,
    required this.p,
    required this.onFileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final a in attachments)
          if (a.isImage)
            _image(context, a)
          else
            _fileChip(a, onTap: () => onFileTap(a)),
      ],
    );
  }

  Widget _image(BuildContext context, MessageAttachment a) {
    final hasPrompt = a.prompt?.isNotEmpty ?? false;
    final w = hasPrompt ? 210.0 : 96.0;
    final h = hasPrompt ? 158.0 : 96.0;
    final img = _buildImage(a, w, h);
    return GestureDetector(
      onTap: () => _openImageSheet(context, a, p),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: img,
      ),
    );
  }

  /// 按优先级渲染图片：URL 直链 → 本地字节 → 占位。
  Widget _buildImage(MessageAttachment a, double w, double h) {
    final fallback = Container(
      width: w,
      height: h,
      color: p.itemHover,
      child: Icon(Icons.image_outlined, size: 26, color: p.textTertiary),
    );
    if (a.url != null && a.url!.isNotEmpty) {
      return Image.network(
        a.url!,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            a.bytes != null && a.bytes!.isNotEmpty
                ? Image.memory(Uint8List.fromList(a.bytes!),
                    width: w, height: h, fit: BoxFit.cover)
                : fallback,
      );
    }
    if (a.bytes != null && a.bytes!.isNotEmpty) {
      return Image.memory(
        Uint8List.fromList(a.bytes!),
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return fallback;
  }

  /// 点图片：放大查看 + 提示词说明 + 下载。
  void _openImageSheet(BuildContext context, MessageAttachment a, AppPalette p) {
    showSiniSheet<void>(
      context: context,
      title: 'AI 生成的图片',
      subtitle: a.prompt ?? '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: a.url != null && a.url!.isNotEmpty
                  ? Image.network(a.url!, fit: BoxFit.contain)
                  : (a.bytes != null && a.bytes!.isNotEmpty
                      ? Image.memory(Uint8List.fromList(a.bytes!),
                          fit: BoxFit.contain)
                      : Container(
                          height: 160,
                          color: p.itemHover,
                          child: Icon(Icons.image_outlined,
                              size: 30, color: p.textTertiary),
                        )),
            ),
          ),
          if (a.prompt != null && a.prompt!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '画面描述：${a.prompt!}',
              style: TextStyle(fontSize: 12.5, color: p.textSecondary, height: 1.55),
            ),
          ],
        ],
      ),
      primary: ('下载图片', () {
        Navigator.pop(context);
        saveAndNotify(
          context,
          () => downloadImage(a.name, url: a.url, bytes: a.bytes),
          webMessage: '已开始下载图片',
        );
      }),
      tertiary: ('关闭', () => Navigator.pop(context)),
    );
  }

  Widget _fileChip(MessageAttachment a, {required VoidCallback onTap}) {
    final lower = a.name.toLowerCase();
    final IconData icon;
    final String label;
    if (lower.contains('.slides.html')) {
      icon = Icons.slideshow;
      label = 'PPT';
    } else if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      icon = Icons.code;
      label = 'HTML';
    } else if (lower.endsWith('.doc')) {
      icon = Icons.description_outlined;
      label = 'Word';
    } else if (lower.endsWith('.pdf')) {
      icon = Icons.picture_as_pdf_outlined;
      label = 'PDF';
    } else if (lower.endsWith('.md')) {
      icon = Icons.article_outlined;
      label = 'Markdown';
    } else {
      icon = Icons.insert_drive_file_outlined;
      label = 'FILE';
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: p.itemHover,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.border, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: p.textPrimary),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: p.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(label,
                          style:
                              TextStyle(fontSize: 10.5, color: p.textTertiary)),
                      const SizedBox(width: 6),
                      Text(a.sizeLabel,
                          style:
                              TextStyle(fontSize: 10.5, color: p.textTertiary)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  final bool streaming;
  final bool liked;
  final bool disliked;
  final VoidCallback onCopy;
  final VoidCallback onRegenerate;
  final VoidCallback onLike;
  final VoidCallback onDislike;
  const _ActionsRow({
    required this.streaming,
    required this.liked,
    required this.disliked,
    required this.onCopy,
    required this.onRegenerate,
    required this.onLike,
    required this.onDislike,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    if (streaming) {
      // 流式输出时只显示"停止生成"占位，避免操作误触
      return Row(
        children: [
          _Pill(
            icon: Icons.stop_circle_outlined,
            label: '正在生成',
            onTap: () {},
            color: p.textTertiary,
          ),
        ],
      );
    }
    return Wrap(
      spacing: 4,
      children: [
        _IconAction(icon: Icons.content_copy_outlined, tooltip: '复制', onTap: onCopy, p: p),
        _IconAction(icon: Icons.refresh, tooltip: '重新生成', onTap: onRegenerate, p: p),
        _IconAction(
          icon: liked ? Icons.thumb_up : Icons.thumb_up_outlined,
          tooltip: '好',
          onTap: onLike,
          p: p,
          active: liked,
        ),
        _IconAction(
          icon: disliked ? Icons.thumb_down : Icons.thumb_down_outlined,
          tooltip: '不好',
          onTap: onDislike,
          p: p,
          active: disliked,
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _Pill({required this.icon, required this.label, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final AppPalette p;
  final bool active;
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.p,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: p.itemHover,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 16,
              color: active ? p.textPrimary : p.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
