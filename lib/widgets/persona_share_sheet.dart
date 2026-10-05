import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../app_state.dart';
import '../core/design/tokens.dart';
import '../core/widgets/sini_button.dart';
import '../models.dart';
import '../theme.dart';
import '../utils/export_file.dart'
    show downloadBinaryFile, downloadTextFile, saveAndNotify;
import '../utils/mobile_share.dart'
    show exportTextToPickedDir, fallbackExportDir, savePngToGallery, shareImageFile;
import '../utils/persona_share.dart'
    show encodePersonaPackage, exportPersonaPackage;
import 'persona_share_card_3d.dart'
    show PersonaShareCard3D, PersonaShareCardFront, kCardPalettes;

/// 「分享人格卡片」面板：
/// - 上面是可以拖拽旋转 / 翻面的 3D 养成卡
/// - 「保存卡片图片」：把卡片正面渲染成 PNG（发朋友圈 / 微博 / 群都行）
/// - 「导出养成数据」：.sini.json 全量养成包（朋友导入即可复活这个人格）
Future<void> showPersonaShareSheet(
  BuildContext context,
  Persona persona,
  AppState state,
) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) => _PersonaShareSheet(persona: persona, state: state),
  );
}

class _PersonaShareSheet extends StatefulWidget {
  final Persona persona;
  final AppState state;
  const _PersonaShareSheet({required this.persona, required this.state});

  @override
  State<_PersonaShareSheet> createState() => _PersonaShareSheetState();
}

class _PersonaShareSheetState extends State<_PersonaShareSheet> {
  final _captureKey = GlobalKey();

  /// 当前配色档（null = TA 本命色）；打开面板时随机起一档，给点开箱感
  late int? _palette = _randomPalette(exclude: null);
  String get _paletteName =>
      _palette == null || _palette == 0
          ? '本命色'
          : kCardPalettes[_palette!].name;

  static int? _randomPalette({int? exclude}) {
    final rnd = math.Random();
    // 0 是本命色；首次打开也允许停在本命色（exclude==null 时全档可摇）
    final max = kCardPalettes.length - 1;
    int i = rnd.nextInt(max + 1);
    if (exclude != null && i == exclude) i = (i + 1) % (max + 1);
    return i == 0 ? null : i;
  }

  void _shuffle() {
    setState(() => _palette = _randomPalette(exclude: _palette));
  }

  int get _messageCount =>
      widget.state.messageCountOfPersona(widget.persona.id);

  int get _daysKnown {
    final first = widget.state.firstMessageAtOfPersona(widget.persona.id);
    if (first == null) return 0;
    final d = DateTime.now().difference(first).inDays;
    return d < 1 ? 1 : d; // 当天也算 1 天，别显示 0 太寒酸
  }

  /// 把静态正面卡渲染成 PNG 字节
  Future<Uint8List?> _captureCard() async {
    await Future.delayed(const Duration(milliseconds: 60)); // 等一帧
    final boundary = _captureKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _saveImage() async {
    final bytes = await _captureCard();
    if (!mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('卡片生成失败，请重试')),
      );
      return;
    }
    // 手机：直接进相册；Web：浏览器下载
    if (!kIsWeb) {
      final err = await savePngToGallery(
        bytes,
        name: 'sini_card_${widget.persona.name}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err == null ? '已保存到手机相册' : '保存相册失败：$err'),
        ),
      );
      return;
    }
    await saveAndNotify(
      context,
      () => downloadBinaryFile(
          '人格卡片_${widget.persona.name}.png', bytes, 'image/png'),
      webMessage: '卡片图片已开始下载，可以直接发到朋友圈 / 群',
    );
  }

  Future<void> _exportData() async {
    final pkg = exportPersonaPackage(
      widget.persona,
      messageCount: _messageCount,
    );
    final fileName = '${widget.persona.name}_人格养成包.sini.json';
    final content = encodePersonaPackage(pkg);
    if (!mounted) return;

    if (kIsWeb) {
      await saveAndNotify(
        context,
        () => downloadTextFile(fileName, content, 'application/json'),
        webMessage: '养成包已开始下载，发给朋友导入即可',
      );
      return;
    }

    // 手机：优先让用户选文件夹；取消/失败则落到下载目录并回显路径
    String? dir;
    try {
      dir = await FilePicker.getDirectoryPath(dialogTitle: '选择导出文件夹');
    } catch (_) {
      dir = null;
    }
    if (!mounted) return;

    if (dir == null) {
      // 用户主动取消
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消导出（未选择文件夹）')),
      );
      return;
    }

    var r = await exportTextToPickedDir(
      fileName: fileName,
      content: content,
      dirPath: dir,
    );
    if (!r.ok) {
      // 部分机型对所选目录没有写权限 → 落到下载并回显路径
      final fallback = await fallbackExportDir();
      r = await exportTextToPickedDir(
        fileName: fileName,
        content: content,
        dirPath: fallback.path,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? '养成包已保存到\n${r.message}' : '导出失败：${r.message}'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// 复制导入码：分享包 JSON 原文就是导入码，朋友粘贴进「导入人格养成卡」即可
  Future<void> _copyCode() async {
    final pkg = exportPersonaPackage(
      widget.persona,
      messageCount: _messageCount,
    );
    await Clipboard.setData(ClipboardData(text: encodePersonaPackage(pkg)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('导入码已复制，发给朋友粘贴到「导入人格养成卡」即可'),
        duration: Duration(milliseconds: 2400),
      ),
    );
  }

  /// 一键分享：只发图片（安卓系统对多文件/非图片类型限制多）。
  /// 养成包用导入码塞进分享文案，朋友粘贴即可。
  Future<void> _shareToApps() async {
    final bytes = await _captureCard();
    if (bytes == null || !mounted) return;
    final pkg = encodePersonaPackage(exportPersonaPackage(
      widget.persona,
      messageCount: _messageCount,
    ));
    final name = widget.persona.name;
    final text = '我在「似你」养了一个人格：$name · '
        '聊了 $_messageCount 条 · ${widget.persona.memory.length} 条记忆 · '
        '养成 $_daysKnown 天。\n'
        '想领养 TA：在 App 里「导入人格养成卡」粘贴下面导入码即可 ↓\n\n'
        '$pkg';
    try {
      await shareImageFile(
        bytes: bytes,
        fileName: '人格卡片_$name.png',
        text: text,
        subject: '似你 · 人格养成卡「$name」',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('系统分享失败（$e），已改为保存到相册')),
      );
      await _saveImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('分享人格养成卡',
                  style: TextStyle(
                      fontSize: SiniText.titleMd,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 20, color: p.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '左右拖一拖旋转卡片，点一下翻面。'
            '图片发朋友圈，数据文件发给想「领养」TA 的朋友。',
            style: TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary),
          ),
          const SizedBox(height: Spacing.lg),
          // 随机配色
          Center(
            child: InkWell(
              onTap: _shuffle,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: p.border, width: 1),
                  borderRadius: BorderRadius.circular(999),
                  color: p.itemHover,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.casino_rounded,
                        size: 15, color: Color(0xFF6C5CE7)),
                    const SizedBox(width: 6),
                    Text('随机配色 · 当前 $_paletteName',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: p.textPrimary)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          // 3D 卡 + 隐藏的静态正面卡（供截图用，始终正面朝前）
          Center(
            child: SizedBox(
              width: 300,
              child: Stack(children: [
                // 截图专用：静态正面（几乎透明但参与绘制）
                RepaintBoundary(
                  key: _captureKey,
                  child: AspectRatio(
                    aspectRatio: 300 / 430,
                    child: Opacity(
                      opacity: 0.01,
                      child: ExcludeSemantics(
                        child: IgnorePointer(
                          child: PersonaShareCardFront(
                            persona: widget.persona,
                            messageCount: _messageCount,
                            daysKnown: _daysKnown,
                            paletteIndex: _palette,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: PersonaShareCard3D(
                    persona: widget.persona,
                    messageCount: _messageCount,
                    daysKnown: _daysKnown,
                    paletteIndex: _palette,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          // 主操作：系统分享（微信 / QQ / 朋友圈…）
          SiniButton(
            label: '分享到微信 / QQ / 朋友圈…',
            leadingIcon: Icons.share_rounded,
            onTap: _shareToApps,
            height: 48,
            expand: true,
          ),
          const SizedBox(height: Spacing.sm),
          // 次操作：仅存图 / 导出数据文件 / 复制导入码
          Row(children: [
            Expanded(
              child: SiniButton(
                label: '保存卡片图片',
                leadingIcon: Icons.image_outlined,
                style: SiniButtonStyle.secondary,
                onTap: _saveImage,
                height: 46,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: SiniButton(
                label: '导出养成数据',
                leadingIcon: Icons.file_download_outlined,
                style: SiniButtonStyle.secondary,
                onTap: _exportData,
                height: 46,
              ),
            ),
          ]),
          const SizedBox(height: Spacing.sm),
          SiniButton(
            label: '复制导入码（朋友粘贴即可导入）',
            leadingIcon: Icons.content_copy_rounded,
            style: SiniButtonStyle.secondary,
            onTap: _copyCode,
            height: 44,
            expand: true,
          ),
          const SizedBox(height: Spacing.sm),
          // 隐私说明
          Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  size: 13, color: p.textTertiary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '养成包含人设、性格、语言风格、长期记忆和养成统计；'
                  '你的称呼与手机号 / 证件号等数字隐私会自动剔除，声纹不上传。',
                  style: TextStyle(
                      fontSize: 10.5, color: p.textTertiary, height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
