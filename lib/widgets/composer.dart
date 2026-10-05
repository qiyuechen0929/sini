import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../core/design/tokens.dart';
import '../models.dart';
import '../theme.dart';
import '../utils/doc_extract.dart'
    show extractDocumentText, extractDocumentTextIsolate, kHeavyExtractBytes;
import '../utils/quote_reply.dart' show quotePreview;

/// 底部输入栏：附件 / 输入 / 发送。
/// - 文本或附件有内容 → 显示黑色填充发送按钮；都没有 → 麦克风占位
/// - 「+」弹出紧凑上传菜单（文件 / 照片），照片再分「相册选择 / 相机拍摄」
class Composer extends StatefulWidget {
  const Composer({super.key});

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;
  List<MessageAttachment> _pending = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final v = _controller.text.trim().isNotEmpty;
      if (v != _hasText) setState(() => _hasText = v);
    });
  }

  bool get _canSend => _hasText || _pending.isNotEmpty;

  void _send() {
    if (!_canSend) return;
    final t = _controller.text;
    final atts = List<MessageAttachment>.from(_pending);
    AppStateScope.of(context).sendUserMessage(t, attachments: atts);
    _controller.clear();
    _pending = [];
    setState(() {});
    _focus.requestFocus();
  }

  // ---- 附件选择 ----
  /// 「+」只保留两个功能：文件、照片。
  Future<void> _openAttachMenu() async {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final action = await showModalBottomSheet<_AttachAction>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      // 贴底弹出、可点遮罩 / 下拉关闭；不占满高，避免被顶到屏幕上方
      isScrollControlled: false,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      builder: (sheetCtx) => _AttachSheet(p: p),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AttachAction.files:
        await _pickFiles();
      case _AttachAction.photos:
        await _openPhotoMenu();
    }
  }

  /// 照片二级菜单：从相册选 / 用相机拍。
  Future<void> _openPhotoMenu() async {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final source = await showModalBottomSheet<_PhotoSource>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      isScrollControlled: false,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      builder: (sheetCtx) => _PhotoSheet(p: p),
    );
    if (!mounted || source == null) return;
    switch (source) {
      case _PhotoSource.gallery:
        await _pickImages();
      case _PhotoSource.camera:
        await _takePhoto();
    }
  }

  Future<void> _pickFiles() => _pick(FileType.any);

  Future<void> _pickImages() => _pick(FileType.image);

  Future<void> _pick(FileType type) async {
    try {
      // file_picker 12.x：静态方法返回 PlatformFile（字节需要 readAsBytes 异步读）
      final result = await FilePicker.pickFiles(type: type, allowMultiple: true);
      if (result.isEmpty || !mounted) return;
      final picked = <MessageAttachment>[];
      for (final f in result) {
        try {
          final size = f.lengthSync() ?? await f.length();
          final bytes = await f.readAsBytes();
          final kind = _kindOf(f.name);
          // 文档类附件解析正文；大文件丢 isolate，避免卡在选完文件那一帧
          String? previewText;
          if (kind != MessageAttachmentKind.image) {
            if (bytes.length >= kHeavyExtractBytes) {
              previewText = await compute(
                extractDocumentTextIsolate,
                (f.name, bytes),
              );
            } else {
              previewText = extractDocumentText(f.name, bytes);
            }
          }
          picked.add(MessageAttachment(
            name: f.name,
            sizeBytes: size,
            kind: kind,
            bytes: bytes,
            previewText: previewText,
          ));
        } catch (_) {
          // 单个文件读失败就跳过
        }
      }
      if (picked.isEmpty || !mounted) return;
      setState(() => _pending = [..._pending, ...picked]);
    } catch (_) {
      // 取消或失败：静默
    }
  }

  /// 调用相机拍照（移动端）。Web 端浏览器无法直接调相机，会回退到选图。
  Future<void> _takePhoto() async {
    if (kIsWeb) {
      // Web 无相机能力，退化为系统选择器
      await _pickImages();
      return;
    }
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (shot == null || !mounted) return;
      final bytes = await shot.readAsBytes();
      setState(() => _pending = [
            ..._pending,
            MessageAttachment(
              name: shot.name,
              sizeBytes: bytes.length,
              kind: MessageAttachmentKind.image,
              bytes: bytes,
            ),
          ]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('调起相机失败，请检查权限或改用相册'),
          duration: Duration(milliseconds: 1600),
        ),
      );
    }
  }

  MessageAttachmentKind _kindOf(String name) {
    final ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    const images = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif'];
    return images.contains(ext) ? MessageAttachmentKind.image : MessageAttachmentKind.file;
  }

  void _removePending(int i) => setState(() => _pending.removeAt(i));

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 主输入容器
              Container(
                decoration: BoxDecoration(
                  color: p.composerBg,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: p.border, width: 1),
                ),
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                child: Column(
                  children: [
                    // 引用条：长按 TA 消息选了「引用回复」
                    Builder(builder: (ctx) {
                      final quote = AppStateScope.of(ctx).pendingQuote;
                      if (quote == null) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                        decoration: BoxDecoration(
                          color: p.itemHover,
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(
                                color: p.brand.withValues(alpha: 0.75), width: 3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.format_quote_rounded, size: 14, color: p.brand),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    quote.isUser ? '引用我' : '引用 TA',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: p.brand,
                                    ),
                                  ),
                                  Text(
                                    quotePreview(quote.content, max: 48),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: p.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.close_rounded,
                                  size: 16, color: p.textTertiary),
                              tooltip: '取消引用',
                              onPressed: () =>
                                  AppStateScope.read(context).clearPendingQuote(),
                            ),
                          ],
                        ),
                      );
                    }),
                    // 待发送的附件 chips（ChatGPT 式：直接贴在输入框里）
                    if (_pending.isNotEmpty)
                      SizedBox(
                        height: 64,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                          itemCount: _pending.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (context, i) {
                            final a = _pending[i];
                            return _AttachChip(
                              attachment: a,
                              p: p,
                              onRemove: () => _removePending(i),
                            );
                          },
                        ),
                      ),
                    TextField(
                      controller: _controller,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 8,
                      textInputAction: TextInputAction.newline,
                      onSubmitted: (_) => _send(),
                      style: TextStyle(fontSize: 15, color: p.textPrimary, height: 1.5),
                      cursorColor: p.textSecondary,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                        border: InputBorder.none,
                        hintText:
                            '给 ${AppStateScope.read(context).activePersona?.name ?? "AI"} 发消息…',
                        hintStyle: TextStyle(
                          color: p.textTertiary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _CircleIcon(
                          icon: Icons.add_rounded,
                          tooltip: '上传文件或照片',
                          onTap: _openAttachMenu,
                        ),
                        const Spacer(),
                        _SendButton(onTap: _send, active: _canSend),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '似你可能犯错，建议核实重要信息。',
                  style: TextStyle(fontSize: 11.5, color: p.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }
}

enum _AttachAction { files, photos }

enum _PhotoSource { gallery, camera }

/// 液态玻璃风格的紧凑上传菜单（只保留：文件 / 照片）。
/// 弹窗刻意做小：不占满宽度、居中浮动、圆角收纳，不再是全宽大面板。
class _AttachSheet extends StatelessWidget {
  final AppPalette p;
  const _AttachSheet({required this.p});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      p: p,
      children: [
        _row(context, _AttachAction.files, Icons.insert_drive_file_outlined, '文件',
            '文档、表格、压缩包等'),
        const SizedBox(height: 6),
        _row(context, _AttachAction.photos, Icons.photo_library_outlined, '照片',
            '相册选择或拍照'),
      ],
    );
  }

  Widget _row(BuildContext context, _AttachAction action, IconData icon, String title,
      String subtitle) {
    return _MenuRow(
      p: p,
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => Navigator.of(context).pop(action),
    );
  }
}

/// 照片来源二级菜单：从相册选 / 用相机拍。
class _PhotoSheet extends StatelessWidget {
  final AppPalette p;
  const _PhotoSheet({required this.p});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      p: p,
      children: [
        _MenuRow(
          p: p,
          icon: Icons.photo_library_outlined,
          title: '从相册选择',
          subtitle: '在照片里挑一张或多张',
          onTap: () => Navigator.of(context).pop(_PhotoSource.gallery),
        ),
        const SizedBox(height: 6),
        _MenuRow(
          p: p,
          icon: Icons.photo_camera_outlined,
          title: '用相机拍摄',
          subtitle: '打开相机拍一张',
          onTap: () => Navigator.of(context).pop(_PhotoSource.camera),
        ),
      ],
    );
  }
}

/// 小型液态玻璃卡片：贴底居中、宽度受限，不再撑满整屏飞高。
class _GlassCard extends StatelessWidget {
  final AppPalette p;
  final List<Widget> children;
  const _GlassCard({required this.p, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 底部留出安全距离：贴底但不紧挨屏幕边缘
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          // 关键：限制最大宽度，让弹窗"小一点"
          constraints: const BoxConstraints(maxWidth: 340),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                decoration: BoxDecoration(
                  color: p.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: p.border.withValues(alpha: 0.6), width: 0.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 菜单项：图标 + 标题 + 说明，紧凑单行。
class _MenuRow extends StatelessWidget {
  final AppPalette p;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _MenuRow({
    required this.p,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        hoverColor: p.itemHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: p.itemHover,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(icon, size: 19, color: p.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: p.textPrimary)),
                    const SizedBox(height: 1),
                    Text(subtitle,
                        style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
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

/// 待发送附件的圆形小卡：图片显示缩略图，文件显示类型图标
class _AttachChip extends StatelessWidget {
  final MessageAttachment attachment;
  final AppPalette p;
  final VoidCallback onRemove;
  const _AttachChip({
    required this.attachment,
    required this.p,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: p.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (attachment.isImage && attachment.bytes != null)
                  Image.memory(
                    Uint8List.fromList(attachment.bytes!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallback(),
                  )
                else
                  _fallback(),
                Positioned(
                  top: 3,
                  right: 3,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 11, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 3, 6, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: p.surface,
      alignment: Alignment.center,
      child: Icon(
        attachment.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
        size: 18,
        color: p.textTertiary,
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          hoverColor: p.itemHover,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: p.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool active;
  const _SendButton({required this.onTap, required this.active});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final bg = active ? p.sendActive : p.sendIdle;
    final fg = active ? p.inverseOn : p.textTertiary;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.arrow_upward_rounded, size: 18, color: fg),
        ),
      ),
    );
  }
}
