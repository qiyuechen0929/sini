import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design/tokens.dart';
import '../theme.dart';
import '../utils/chart_spec.dart' show tryParseChartBlock;
import '../utils/export_file.dart';
import 'chart_card.dart';
import 'thinking_dots.dart';

/// 把助手/用户的回复按 ChatGPT 风格渲染：
/// 代码块（灰底 + 语言标签 + 一键复制）、行内代码、引用、列表、加粗。
/// 纯前端轻量解析，不依赖第三方 markdown 包，便于 iOS 液态玻璃风格统一。

// ---- 块模型 ----
class _CodeBlock {
  final String lang;
  final String code;
  const _CodeBlock(this.lang, this.code);
}

class _TextBlock {
  final String text;
  const _TextBlock(this.text);
}

/// markdown 表格：| a | b | 行 + |---|---| 分隔行 + 数据行
class _TableBlock {
  final List<String> header;
  final List<List<String>> rows;
  const _TableBlock(this.header, this.rows);
}

class _QuoteBlock {
  final String text;
  const _QuoteBlock(this.text);
}

class _BulletBlock {
  final List<String> items;
  const _BulletBlock(this.items);
}

/// 把整段文本切成块：先按 ``` 代码块，再按 `>` 引用、`- ` 列表、其余为段落。
List<dynamic> _parseBlocks(String text) {
  final lines = text.split('\n');
  final blocks = <dynamic>[];
  int i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final t = line.trim();

    // markdown 表格：本行以 | 开头且下一行是 |---|---| 分隔
    if (t.startsWith('|') && i + 1 < lines.length) {
      final sep = lines[i + 1].trim();
      if (sep.startsWith('|') && RegExp(r'^\|[\s:|-]+$').hasMatch(sep)) {
        List<String>? cells(String line) {
          var parts = line.trim().split('|');
          if (parts.isNotEmpty && parts.first.trim().isEmpty) parts = parts.sublist(1);
          if (parts.isNotEmpty && parts.last.trim().isEmpty) parts = parts.sublist(0, parts.length - 1);
          return parts.isEmpty ? null : parts.map((c) => c.trim()).toList();
        }

        final header = cells(t);
        if (header != null && header.isNotEmpty) {
          i += 2; // 跳过表头行 + 分隔行
          final rows = <List<String>>[];
          while (i < lines.length && lines[i].trim().startsWith('|')) {
            final r = cells(lines[i]);
            if (r != null) rows.add(r);
            i++;
          }
          blocks.add(_TableBlock(header, rows));
          continue;
        }
      }
    }

    // 围栏代码块 ```
    if (t.startsWith('```')) {
      final lang = t.substring(3).trim();
      final buf = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buf.add(lines[i]);
        i++;
      }
      i++; // 跳过结束的 ```
      blocks.add(_CodeBlock(lang, buf.join('\n')));
      continue;
    }

    // 引用 >
    if (t.startsWith('>')) {
      final buf = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        buf.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
        i++;
      }
      blocks.add(_QuoteBlock(buf.join('\n')));
      continue;
    }

    // 无序列表 - / *
    if (RegExp(r'^\s*[-*]\s+').hasMatch(line)) {
      final items = <String>[];
      while (i < lines.length && RegExp(r'^\s*[-*]\s+').hasMatch(lines[i])) {
        items.add(lines[i].replaceFirst(RegExp(r'^\s*[-*]\s+'), ''));
        i++;
      }
      blocks.add(_BulletBlock(items));
      continue;
    }

    // 段落：聚合直到空行或新的块起点
    final buf = <String>[];
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        !lines[i].trim().startsWith('```') &&
        !lines[i].trim().startsWith('>') &&
        !RegExp(r'^\s*[-*]\s+').hasMatch(lines[i])) {
      buf.add(lines[i]);
      i++;
    }
    if (buf.isNotEmpty) {
      blocks.add(_TextBlock(buf.join('\n')));
    } else {
      i++; // 空行
    }
  }
  return blocks;
}

final _inlinePattern = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\*(.+?)\*');

/// 行内富文本：**粗体**、`行内代码`、*斜体*
List<TextSpan> _buildInline(String src, AppPalette p) {
  final base = TextStyle(fontSize: 15.5, height: 1.6, color: p.textPrimary);
  final bold = base.copyWith(fontWeight: FontWeight.w600);
  final italic = base.copyWith(fontStyle: FontStyle.italic);
  final code = base.copyWith(
    backgroundColor: p.codeInlineBg,
    fontFamily: 'monospace',
    fontSize: 14,
    color: p.codeText,
  );
  final spans = <TextSpan>[];
  int last = 0;
  for (final m in _inlinePattern.allMatches(src)) {
    if (m.start > last) {
      spans.add(TextSpan(text: src.substring(last, m.start), style: base));
    }
    if (m.group(1) != null) {
      spans.add(TextSpan(text: m.group(1), style: bold));
    } else if (m.group(2) != null) {
      spans.add(TextSpan(text: m.group(2), style: code));
    } else if (m.group(3) != null) {
      spans.add(TextSpan(text: m.group(3), style: italic));
    }
    last = m.end;
  }
  if (last < src.length) {
    spans.add(TextSpan(text: src.substring(last), style: base));
  }
  return spans;
}

class SiniMarkdown extends StatelessWidget {
  final String text;
  final bool streaming;
  final bool isUser;
  const SiniMarkdown({
    super.key,
    required this.text,
    this.streaming = false,
    this.isUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final blocks = _parseBlocks(text);

    if (blocks.isEmpty) {
      // 空文本 + streaming：直接返回 SizedBox，由 message_bubble 显示「思考气泡」
      // （这里不返回任何文字光标，避免一闪一闪的方块）
      return const SizedBox.shrink();
    }

    int lastTextIdx = -1;
    for (int i = 0; i < blocks.length; i++) {
      if (blocks[i] is _TextBlock) lastTextIdx = i;
    }

    final children = <Widget>[];
    for (int i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      Widget w;
      if (b is _TableBlock) {
        w = _TableView(block: b, p: p);
      } else if (b is _CodeBlock) {
        // AI 内嵌的 ```chart 数据块 → 原生图表卡片；解析不出（流式中途/格式
        // 不对）时：流式中显示占位，完毕后原样显示代码块兜底
        final chart = tryParseChartBlock(b.lang, b.code);
        if (chart != null) {
          w = ChartCard(spec: chart);
        } else if (b.lang == 'chart' && streaming) {
          w = _ChartPending(p: p);
        } else {
          w = SiniCodeBlock(lang: b.lang, code: b.code);
        }
      } else if (b is _QuoteBlock) {
        w = _QuoteView(text: b.text, p: p);
      } else if (b is _BulletBlock) {
        w = _BulletView(items: b.items, p: p);
      } else {
        final showCursor = streaming && i == lastTextIdx;
        w = _TextContentView(
          text: b.text,
          p: p,
          showCursor: showCursor,
          alignEnd: isUser,
        );
      }
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(w);
    }
    // 用户消息：整块靠右（文字右对齐 + 收缩到内容宽度），
    // 配合外层气泡，用户能一眼看出"这是我发的"。
    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _TextContentView extends StatelessWidget {
  final String text;
  final AppPalette p;
  final bool showCursor;
  /// 用户消息：文字右对齐（配合气泡右侧）
  final bool alignEnd;
  const _TextContentView({
    required this.text,
    required this.p,
    this.showCursor = false,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final spans = _buildInline(text, p);
    final rtl = alignEnd ? TextAlign.right : TextAlign.left;
    if (showCursor) {
      // 流式结尾光标：换成炫酷版「彩色脉冲圆点」，不再是静态 ▍
      return Wrap(
        alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          RichText(text: TextSpan(children: spans), textAlign: rtl),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: ThinkingIndicator(p: p, compact: true),
          ),
        ],
      );
    }
    return RichText(text: TextSpan(children: spans), textAlign: rtl);
  }
}

class _QuoteView extends StatelessWidget {
  final String text;
  final AppPalette p;
  const _QuoteView({required this.text, required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: p.quoteBg,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: p.borderStrong, width: 3)),
      ),
      child: RichText(text: TextSpan(children: _buildInline(text, p))),
    );
  }
}

class _BulletView extends StatelessWidget {
  final List<String> items;
  final AppPalette p;
  const _BulletView({required this.items, required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•', style: TextStyle(fontSize: 15.5, color: p.textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(text: TextSpan(children: _buildInline(it, p))),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// markdown 表格渲染：表头加底色加粗，行间细分隔线；列多时横向滚动
class _TableView extends StatelessWidget {
  final _TableBlock block;
  final AppPalette p;
  const _TableView({required this.block, required this.p});

  @override
  Widget build(BuildContext context) {
    final colCount = block.header.length;
    final bodyCells = <TableRow>[
      TableRow(
        decoration: BoxDecoration(
          color: p.itemHover,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        ),
        children: [
          for (final h in block.header)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Text(
                h,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary),
              ),
            ),
        ],
      ),
      for (final row in block.rows)
        TableRow(
          decoration: BoxDecoration(
            border: Border(
                top: BorderSide(color: p.border.withValues(alpha: .6), width: 0.5)),
          ),
          children: [
            for (int c = 0; c < colCount; c++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Text(
                  c < row.length ? row[c] : '',
                  style: TextStyle(fontSize: 11.5, color: p.textSecondary, height: 1.4),
                ),
              ),
          ],
        ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: p.border, width: 0.5),
      ),
      // 列多时横向滚，别把字挤成一列竖排
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: 240),
          child: Table(
            columnWidths: {
              for (int c = 0; c < colCount; c++) c: const FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: bodyCells,
          ),
        ),
      ),
    );
  }
}

/// 图表数据块流式输出中：还没收完/没解析成功时的占位
class _ChartPending extends StatelessWidget {
  final AppPalette p;
  const _ChartPending({required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: p.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: p.textTertiary),
          ),
          const SizedBox(width: 8),
          Text('图表绘制中…',
              style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
        ],
      ),
    );
  }
}

class SiniCodeBlock extends StatelessWidget {
  final String lang;
  final String code;
  const SiniCodeBlock({required this.lang, required this.code});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.5,
      height: 1.5,
      color: p.codeText,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: p.codeHeaderBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    lang.isEmpty ? '代码' : lang,
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已复制代码'),
                              duration: Duration(milliseconds: 1200),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy, size: 14, color: p.textTertiary),
                              const SizedBox(width: 4),
                              Text('复制', style: TextStyle(fontSize: 12, color: p.textTertiary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          saveAndNotify(
                            context,
                            () => downloadCode(lang, code),
                            webMessage: '已下载代码文件',
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download, size: 14, color: p.textTertiary),
                              const SizedBox(width: 4),
                              Text('下载', style: TextStyle(fontSize: 12, color: p.textTertiary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(code, style: mono),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
