import 'dart:convert';

import 'package:flutter/material.dart';

import 'web_bridge.dart';

/// 把助手回复导出成文件（HTML / Word / 纯文本代码）。
///
/// 本文件只做**内容构造**（markdown → html / doc / ppt 的纯字符串转换），
/// 不直接碰平台 API —— 真正的「存文件 / 开外链 / 内嵌预览」交给
/// `web_bridge.dart`（Web 用 Blob 下载，Android 写进 App 文档目录）。
/// 这样这份代码在 Web 和手机端都能编译、都能用。

// ---- markdown -> html ----

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// 处理行内标记：`行内代码`、**粗体**、*斜体*（先整体转义，再套标签）。
String _inlineHtml(String s) {
  var x = _esc(s);
  x = x.replaceAllMapped(
      RegExp(r'`([^`]+)`'), (m) => '<code>${m.group(1)}</code>');
  x = x.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*'), (m) => '<strong>${m.group(1)}</strong>');
  x = x.replaceAllMapped(
      RegExp(r'\*(.+?)\*'), (m) => '<em>${m.group(1)}</em>');
  return x;
}

/// 把常用 markdown 子集转成 HTML 片段。
/// 覆盖：代码块、引用、无序列表、段落、加粗、斜体、行内代码。
String markdownToHtml(String md) {
  final lines = md.split('\n');
  final out = <String>[];
  int i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final t = line.trim();

    // 围栏代码块 ```
    if (t.startsWith('```')) {
      final lang = t.substring(3).trim();
      final buf = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buf.add(lines[i]);
        i++;
      }
      i++; // 跳过结尾 ```
      out.add(
          '<pre><code${lang.isNotEmpty ? ' class="language-$lang"' : ''}>'
          '${_esc(buf.join('\n'))}</code></pre>');
      continue;
    }

    // 引用 >（可多行）
    if (t.startsWith('>')) {
      final buf = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        buf.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
        i++;
      }
      out.add('<blockquote>${_inlineHtml(buf.join('\n')).replaceAll('\n', '<br/>')}</blockquote>');
      continue;
    }

    // 无序列表 - / *
    if (RegExp(r'^\s*[-*]\s+').hasMatch(line)) {
      final items = <String>[];
      while (i < lines.length && RegExp(r'^\s*[-*]\s+').hasMatch(lines[i])) {
        items.add(lines[i].replaceFirst(RegExp(r'^\s*[-*]\s+'), ''));
        i++;
      }
      out.add(
          '<ul>${items.map((e) => '<li>${_inlineHtml(e)}</li>').join('')}</ul>');
      continue;
    }

    // 段落：聚合到空行 / 新的块起点
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
      out.add('<p>${_inlineHtml(buf.join('\n')).replaceAll('\n', '<br/>')}</p>');
    } else {
      i++; // 空行
    }
  }
  return out.join('\n');
}

// ---- 下载 ----

/// 把文件名里对文件系统非法的字符替换掉，避免下载失败。
String safeFileName(String s) {
  final cleaned = s.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();
  return cleaned.isEmpty ? '似你回复' : cleaned;
}

/// 导出一个文本文件。
///
/// 返回**本地保存路径**（Android/iOS 上写进 App 文档目录时非空，调用方应该
/// 提示用户去哪儿找）；Web 上是浏览器下载，返回 null。
Future<String?> downloadTextFile(String fileName, String content, String mime) {
  return saveFileBytes(fileName, utf8.encode(content), mime);
}

/// 存文件并把「存到哪儿了」告诉用户。
///
/// Web 上浏览器自己处理下载，提示一句「已开始下载」就够；手机端是写进
/// App 文档目录，**必须把完整路径显示出来**，否则用户点完「下载」会以为没反应。
Future<void> saveAndNotify(
  BuildContext context,
  Future<String?> Function() save, {
  String webMessage = '已开始下载',
}) async {
  final path = await save();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(path != null ? '已保存到 $path' : webMessage),
      duration: const Duration(milliseconds: 2400),
    ),
  );
}

/// 导出一个二进制文件（图片等）。
Future<String?> downloadBinaryFile(
    String fileName, List<int> bytes, String mime) {
  return saveFileBytes(fileName, bytes, mime);
}

/// 下载一张 AI 生成的图片：有字节就存字节，只有直链就交给系统打开。
Future<String?> downloadImage(String fileName,
    {String? url, List<int>? bytes}) async {
  if (bytes != null && bytes.isNotEmpty) {
    return downloadBinaryFile(fileName, bytes, 'image/png');
  }
  if (url != null && url.isNotEmpty) {
    await openExternalUrl(url);
  }
  return null;
}

const String _htmlStyle = '''
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,"PingFang SC","Microsoft YaHei",sans-serif;max-width:820px;margin:36px auto;padding:0 24px;line-height:1.75;color:#1a1a1a;background:#fff;}
h1,h2,h3{line-height:1.3;}
pre{background:#f4f4f5;border-radius:10px;padding:14px 16px;overflow:auto;font-size:13.5px;}
code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px;}
pre code{background:none;padding:0;}
:not(pre)>code{background:#ededef0;padding:2px 6px;border-radius:5px;}
blockquote{border-left:3px solid #d0d0d0;margin:0;padding:8px 14px;background:#f6f6f7;color:#5d5d5d;}
ul{padding-left:22px;}
''';

/// 从回复里提取「本身就是一个完整 HTML 文档」的代码块。
/// 命中则原样返回（保留 script/style，网页能真正运行）；否则返回 null。
String? extractHtmlDoc(String md) {
  final lines = md.split('\n');
  int i = 0;
  String? fallback;
  while (i < lines.length) {
    final t = lines[i].trim();
    if (t.startsWith('```')) {
      final lang = t.substring(3).trim().toLowerCase();
      final buf = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buf.add(lines[i]);
        i++;
      }
      i++; // 跳过结尾 ```
      final code = buf.join('\n');
      final lower = code.toLowerCase();
      // 完整 HTML 文档的标志：有 doctype 声明，或有 <html 根标签
      final isHtmlDoc =
          lower.contains('<!doctype html') || lower.contains('<html');
      if (isHtmlDoc) {
        // 明确标了 html 的代码块优先；没标语言的也接受（fallback）
        if (lang == 'html' || lang == 'htm') return code;
        fallback ??= code;
      }
      continue;
    }
    i++;
  }
  return fallback;
}

/// 生成一段可下载 / 可预览的 .html 文档字符串。
/// 若回复里本身就有完整 HTML 文档（如"写个贪吃蛇网页"），**原样交付**以便直接运行；
/// 否则把 markdown 转成带基础排版的文档。
String buildHtmlExport(String baseName, String md) {
  final direct = extractHtmlDoc(md);
  if (direct != null) return direct;
  return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>$baseName</title>
<style>$_htmlStyle</style>
</head>
<body>
${markdownToHtml(md)}
</body>
</html>''';
}

/// 导出为独立 .html 文件（下载）。
void exportAsHtml(String baseName, String md) {
  downloadTextFile(
    '${safeFileName(baseName)}.html',
    buildHtmlExport(baseName, md),
    'text/html;charset=utf-8',
  );
}

/// 生成 Word/WPS 可直接打开的 HTML 封装（`.doc` 文本）。
String buildWordExport(String baseName, String md) {
  return '''
<html xmlns:o="urn:schemas-microsoft-com:office:office"
      xmlns:w="urn:schemas-microsoft-com:office:word"
      xmlns="http://www.w3.org/TR/REC-html40">
<head><meta charset="utf-8"><title>$baseName</title></head>
<body>
${markdownToHtml(md)}
</body>
</html>''';
}

/// 把 markdown 切成一页一页：优先按 `---` 分隔线，其次按 `#`/`##` 标题。
List<String> _splitSlides(String md) {
  final byDash = md.split(RegExp(r'\n\s*-{3,}\s*\n'));
  if (byDash.length > 1) {
    return byDash.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  final lines = md.split('\n');
  final out = <String>[];
  var buf = <String>[];
  for (final l in lines) {
    if (RegExp(r'^#{1,2}\s+').hasMatch(l.trim()) && buf.isNotEmpty) {
      out.add(buf.join('\n').trim());
      buf = <String>[];
    }
    buf.add(l);
  }
  if (buf.isNotEmpty) out.add(buf.join('\n').trim());
  return out.where((e) => e.isNotEmpty).toList();
}

/// 生成一份自包含 HTML 幻灯片（可点开播放、左右键/点击翻页）。
/// 不依赖 reveal.js 等外部资源，离线可用，能在 app 内 iframe 直接预览。
String buildSlidesExport(String baseName, String md) {
  final slides = _splitSlides(md);
  final body = slides
      .map((s) => '  <section class="slide">${markdownToHtml(s)}</section>')
      .join('\n');
  return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>$baseName</title>
<style>
*{box-sizing:border-box;}
html,body{margin:0;padding:0;background:#111318;color:#f2f2f2;
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"PingFang SC","Microsoft YaHei",sans-serif;}
.slide{display:none;min-height:100vh;padding:44px 34px 64px;flex-direction:column;justify-content:center;}
.slide.active{display:flex;}
h1,h2,h3{margin:0 0 16px;line-height:1.25;}
h1{font-size:30px;}h2{font-size:25px;}h3{font-size:20px;}
p{margin:0 0 12px;line-height:1.75;font-size:16px;}
ul{padding-left:22px;line-height:1.85;font-size:16px;}
pre{background:#1c1f26;border-radius:10px;padding:14px 16px;overflow:auto;font-size:13.5px;}
code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;}
:not(pre)>code{background:#2a2f3a;padding:2px 6px;border-radius:5px;}
blockquote{margin:0 0 12px;border-left:3px solid #4a90d9;padding:6px 14px;background:#191c22;color:#c9c9c9;}
.hint{position:fixed;left:0;right:0;bottom:14px;text-align:center;font-size:12px;color:#8a8a8a;}
.num{position:fixed;right:16px;top:14px;font-size:12px;color:#8a8a8a;}
</style>
</head>
<body>
$body
<div class="num" id="num"></div>
<div class="hint">点击 / ← → / 空格 翻页</div>
<script>
var i=0,s=document.querySelectorAll('.slide');
function show(n){for(var k=0;k<s.length;k++){s[k].classList.toggle('active',k===n);}
  var el=document.getElementById('num');if(el){el.textContent=(n+1)+' / '+s.length;}}
document.addEventListener('keydown',function(e){
  if(e.key==='ArrowRight'||e.key===' '||e.key==='PageDown'){i=Math.min(i+1,s.length-1);show(i);}
  else if(e.key==='ArrowLeft'||e.key==='PageUp'){i=Math.max(i-1,0);show(i);}});
document.body.addEventListener('click',function(){i=(i+1)%s.length;show(i);});
show(0);
</script>
</body>
</html>''';
}

/// 导出为 .doc（保存后交给系统用 WPS / Word 等默认应用打开）。
Future<String?> exportAsWord(String baseName, String md) {
  return downloadTextFile(
    '${safeFileName(baseName)}.doc',
    buildWordExport(baseName, md),
    'application/msword',
  );
}

// ---- 代码块下载 ----

String _langExt(String lang) {
  final l = lang.toLowerCase();
  const map = {
    'python': 'py',
    'py': 'py',
    'dart': 'dart',
    'javascript': 'js',
    'js': 'js',
    'typescript': 'ts',
    'ts': 'ts',
    'html': 'html',
    'css': 'css',
    'json': 'json',
    'java': 'java',
    'c': 'c',
    'cpp': 'cpp',
    'c++': 'cpp',
    'go': 'go',
    'rust': 'rs',
    'rs': 'rs',
    'swift': 'swift',
    'kotlin': 'kt',
    'php': 'php',
    'sql': 'sql',
    'sh': 'sh',
    'bash': 'sh',
    'shell': 'sh',
    'yaml': 'yaml',
    'yml': 'yml',
    'xml': 'xml',
    'markdown': 'md',
    'md': 'md',
  };
  return map[l] ?? 'txt';
}

/// 把一段代码保存成对应扩展名的文件。
Future<String?> downloadCode(String lang, String code) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final name = 'snippet_$ts.${_langExt(lang)}';
  return downloadTextFile(name, code, 'text/plain;charset=utf-8');
}

// ---- 在 app 内预览 HTML ----

/// 把 HTML 内容注册成可内嵌的 platform view，返回 viewType
/// （调用方用 `HtmlElementView(viewType: ...)` 嵌进界面）。
///
/// **只有 Web 支持**（浏览器 iframe）。Android / iOS 上返回 null，
/// 调用方应当降级成「存成 .html 文件 + 让系统浏览器打开」。
String? registerHtmlPreview(String htmlContent) =>
    registerHtmlPreviewView(htmlContent);

// ---- 文件交付意图识别 ----

/// 可交付的文件类型
enum FileKind { html, word, ppt, md }

/// 判断 AI 回复要不要挂"文件卡片"、要哪些。
/// 只有用户真的要文件时才命中（满足其一）：
/// 1) 用户提问里同时出现「生成/导出/做成/转成…」动作词 + 目标词
///    （html/网页 → HTML；word/文档 → Word；ppt/幻灯片 → PPT；markdown/md → Markdown）；
/// 2) AI 回复里直接给出了完整 HTML 文档（用 extractHtmlDoc 判定）。
/// 普通问答、短代码（如"写个快排"）不会命中，仍走灰底代码块 + 一键复制。
Set<FileKind> detectFileKinds({
  required String userPrompt,
  required String aiText,
}) {
  final u = userPrompt.toLowerCase();
  final kinds = <FileKind>{};

  final wantsFile = RegExp(
    r'(生成|导出|输出|做成|存成|保存成|存为|另存为|下载|给我|要个|弄个|来份|来个|写份|写个|做份|做个|整理成|转成|变成|输出成)',
  ).hasMatch(u);

  if (wantsFile) {
    if (RegExp(r'(html|网页|页面|web\s*page|landing\s*page|h5)').hasMatch(u)) {
      kinds.add(FileKind.html);
    }
    if (RegExp(r'(word|文档|docx|\.doc\b|报告|简历|合同|论文|方案)').hasMatch(u)) {
      kinds.add(FileKind.word);
    }
    if (RegExp(r'(ppt|幻灯片|slides|演示文|演示稿|presentation|pptx)')
        .hasMatch(u)) {
      kinds.add(FileKind.ppt);
    }
    if (RegExp(r'(markdown|\.md\b|md\s*文件)').hasMatch(u)) {
      kinds.add(FileKind.md);
    }
  }

  // AI 确实输出了完整 HTML 文档（讲解用代码片段不会命中）
  if (extractHtmlDoc(aiText) != null) kinds.add(FileKind.html);

  return kinds;
}

/// 根据文件名后缀推断 MIME，导出/预览统一用。
String mimeForName(String fileName) {
  final n = fileName.toLowerCase();
  if (n.endsWith('.html') || n.endsWith('.htm')) return 'text/html;charset=utf-8';
  if (n.endsWith('.doc')) return 'application/msword';
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.json')) return 'application/json;charset=utf-8';
  if (n.endsWith('.md')) return 'text/markdown;charset=utf-8';
  if (n.endsWith('.txt')) return 'text/plain;charset=utf-8';
  if (n.endsWith('.csv')) return 'text/csv;charset=utf-8';
  if (n.endsWith('.svg')) return 'image/svg+xml';
  return 'text/plain;charset=utf-8';
}
