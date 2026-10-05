import 'dart:convert';

import 'package:archive/archive.dart';

/// 附件文字提取：把用户发来的文档在本地解析成纯文本，塞进 prompt 给模型看。
///
/// 支持：txt / md / csv / json / log / html 等纯文本，docx / pptx / xlsx
/// （zip+XML 解包），pdf（尽力而为：解压内容流后抽字面文本）。
/// 提不出来的返回 null，前端当普通文件卡片处理，不影响发送。

/// 单条附件注入 prompt 的最大字符数
/// （调小是为了加速：模型一轮塞 4 万字正文又慢又容易超上下文）
const int kMaxExtractChars = 16000;

/// 大于这个体积的附件，丢到 isolate 解析，避免卡 UI
const int kHeavyExtractBytes = 80 * 1024;

String? extractDocumentText(String name, List<int> bytes) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  try {
    final String? text;
    switch (ext) {
      case 'txt':
      case 'md':
      case 'markdown':
      case 'csv':
      case 'tsv':
      case 'json':
      case 'log':
      case 'srt':
      case 'vtt':
      case 'yml':
      case 'yaml':
      case 'xml':
        text = _decodeText(bytes);
      case 'htm':
      case 'html':
        text = _stripTags(_decodeText(bytes));
      case 'docx':
        text = _extractDocx(bytes);
      case 'pptx':
        text = _extractPptx(bytes);
      case 'xlsx':
      case 'xlsm':
        text = _extractXlsx(bytes);
      case 'pdf':
        text = _extractPdf(bytes);
      default:
        return null; // 不认识的类型不硬解析（zip/图片/音视频等）
    }
    if (text == null) return null;
    final t = text.trim();
    if (t.isEmpty) return null;
    if (t.length <= kMaxExtractChars) return t;
    return '${t.substring(0, kMaxExtractChars)}\n\n（内容过长，已截断，原文共 ${t.length} 字）';
  } catch (_) {
    return null;
  }
}

/// 给 isolate 用的入口（参数必须是可传消息的对象）
String? extractDocumentTextIsolate((String, List<int>) args) =>
    extractDocumentText(args.$1, args.$2);

/// 按 BOM / 试探解码 UTF-8 / UTF-16 / latin1 兜底
String _decodeText(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16Decode(bytes.sublist(2), bigEndian: false);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16Decode(bytes.sublist(2), bigEndian: true);
  }
  // 先按 UTF-8 解；遇到非法字节再按 latin1 兜底（GBK 文件会得到可容忍的乱码，
  // 完整 GBK 表太大，MVP 阶段先这样——多数中文文档已是 UTF-8）
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

String _utf16Decode(List<int> b, {required bool bigEndian}) {
  final sb = StringBuffer();
  for (int i = 0; i + 1 < b.length; i += 2) {
    sb.writeCharCode(bigEndian ? (b[i] << 8) | b[i + 1] : b[i] | (b[i + 1] << 8));
  }
  return sb.toString();
}

final RegExp _tagPattern = RegExp(r'<[^>]*>');
final RegExp _entityPattern = RegExp(r'&(amp|lt|gt|quot|apos|#x?[0-9a-fA-F]+);');

String _decodeXmlEntities(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(_entityPattern, (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
      default:
        if (e.startsWith('#x') || e.startsWith('#X')) {
          return String.fromCharCode(int.tryParse(e.substring(2), radix: 16) ?? 0);
        }
        if (e.startsWith('#')) {
          return String.fromCharCode(int.tryParse(e.substring(1)) ?? 0);
        }
        return m.group(0)!;
    }
  });
}

String _stripTags(String html) {
  final noScript = html
      .replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), ' ');
  return _decodeXmlEntities(noScript.replaceAll(_tagPattern, ' '))
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// 不是 zip（PK 头）返回 null；损坏时 ZipDecoder 抛异常由上层兜底
Archive? _tryDecodeZip(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) return null;
  return ZipDecoder().decodeBytes(bytes);
}

/// docx：word/document.xml，一个 <w:p> 是一段，段内 <w:t> 是文字
String? _extractDocx(List<int> bytes) {
  final zip = _tryDecodeZip(bytes);
  if (zip == null) return null;
  final f = zip.findFile('word/document.xml');
  if (f == null) return null;
  final xml = _decodeText(f.content as List<int>);
  final paras = xml.split('</w:p>');
  final out = <String>[];
  for (final p in paras) {
    final texts = _group1All(p, RegExp(r'<w:t[^>]*>([\s\S]*?)</w:t>'));
    if (texts.isEmpty) continue;
    final line = _decodeXmlEntities(texts.join()).trim();
    if (line.isNotEmpty) out.add(line);
  }
  return out.isEmpty ? null : out.join('\n');
}

/// pptx：ppt/slides/slideN.xml 按页序拼，每页内 <a:t> 是文字块
String? _extractPptx(List<int> bytes) {
  final zip = _tryDecodeZip(bytes);
  if (zip == null) return null;
  final slides = zip.files
      .where((f) =>
          f.isFile && RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name))
      .toList()
    ..sort((a, b) {
      final na = int.tryParse(a.name.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final nb = int.tryParse(b.name.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return na.compareTo(nb);
    });
  if (slides.isEmpty) return null;
  final out = <String>[];
  for (int i = 0; i < slides.length; i++) {
    final xml = _decodeText(slides[i].content as List<int>);
    final texts = _group1All(xml, RegExp(r'<a:t>([\s\S]*?)</a:t>'))
        .map(_decodeXmlEntities)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (texts.isEmpty) continue;
    out.add('—— 第 ${i + 1} 页 ——');
    out.addAll(texts);
  }
  return out.isEmpty ? null : out.join('\n');
}

/// xlsx：xl/sharedStrings.xml（字符串表）+ 各 sheet 的 <v>（数字等），拼出近似表格
String? _extractXlsx(List<int> bytes) {
  final zip = _tryDecodeZip(bytes);
  if (zip == null) return null;
  final shared = <String>[];
  final sf = zip.findFile('xl/sharedStrings.xml');
  if (sf != null) {
    shared.addAll(_group1All(_decodeText(sf.content as List<int>),
            RegExp(r'<t[^>]*>([\s\S]*?)</t>'))
        .map(_decodeXmlEntities));
  }
  final sheets = zip.files
      .where((f) =>
          f.isFile && RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  if (shared.isEmpty && sheets.isEmpty) return null;
  final out = <String>[];
  for (final sheet in sheets) {
    out.add('—— ${sheet.name.replaceAll('xl/worksheets/', '')} ——');
    final xml = _decodeText(sheet.content as List<int>);
    for (final rowXml in _group1All(xml, RegExp(r'<row[^>]*>([\s\S]*?)</row>'))) {
      // 每个单元格：t="s" 表示引用 sharedStrings 下标，否则直接取 <v>
      final cells = <String>[];
      for (final m in RegExp(r'<c\s([^>]*)>([\s\S]*?)</c>').allMatches(rowXml)) {
        final isShared = m.group(1)!.contains(RegExp(r'\bt="s"'));
        final body = m.group(2)!;
        final v = RegExp(r'<v>([\s\S]*?)</v>').firstMatch(body)?.group(1);
        if (v == null) continue;
        if (isShared) {
          final idx = int.tryParse(v.trim());
          if (idx != null && idx < shared.length) cells.add(shared[idx]);
        } else {
          cells.add(_decodeXmlEntities(v).trim());
        }
      }
      final line = cells.where((c) => c.isNotEmpty).join(' | ');
      if (line.isNotEmpty) out.add(line);
    }
  }
  // 兜底：只有 sharedStrings 也要给点内容
  if (out.length <= 1 && shared.isNotEmpty) return shared.join('\n');
  return out.isEmpty ? null : out.join('\n');
}

/// pdf 尽力而为：找出所有流，能 inflate 的解开后抓 () 字面量拼成近似正文。
/// 扫描版（图片型）PDF 提不出文字，返回 null 走「不支持」路径。
String? _extractPdf(List<int> bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final out = <String>[];
  for (final m in RegExp(r'stream\r?\n').allMatches(raw)) {
    final end = raw.indexOf('endstream', m.end);
    if (end < 0) continue;
    // latin1 是 1:1 映射，字符偏移可直接当字节偏移
    var data = bytes.sublist(
        m.end < bytes.length ? m.end : bytes.length,
        end < bytes.length ? end : bytes.length);
    if (data.isEmpty) continue;
    // 多数内容流是 FlateDecode（zlib）；解不开的流（图片/加密）跳过
    try {
      data = const ZLibDecoder().decodeBytes(data);
    } catch (_) {
      try {
        data = Inflate(data).getBytes();
      } catch (_) {
        continue;
      }
    }
    final s = latin1.decode(data, allowInvalid: true);
    if (!s.contains('Tj') && !s.contains('TJ')) continue;
    final sb = StringBuffer();
    for (final tm in RegExp(r'\((?:\\.|[^\\()])*\)').allMatches(s)) {
      final lit = tm.group(0)!;
      sb.write(_decodePdfLiteral(lit.substring(1, lit.length - 1)));
    }
    final line = sb.toString().trim();
    if (line.isNotEmpty) out.add(line);
  }
  final text = out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (text.length < 20) return null; // 基本没提出东西（扫描件 / 加密件）
  return text;
}

/// PDF 字面串的转义还原
String _decodePdfLiteral(String s) {
  final sb = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      final n = s[i + 1];
      switch (n) {
        case 'n':
          sb.write('\n');
        case 'r':
          break;
        case 't':
          sb.write('\t');
        case 'b':
        case 'f':
          break;
        case '(':
        case ')':
        case r'\':
          sb.write(n);
        default:
          // 八进制 \ddd
          final oct = RegExp(r'^[0-7]{1,3}').firstMatch(s.substring(i + 1));
          if (oct != null) {
            sb.writeCharCode(int.parse(oct.group(0)!, radix: 8));
            i += oct.group(0)!.length;
            continue;
          }
          sb.write(n);
      }
      i++;
    } else {
      sb.write(c);
    }
  }
  return sb.toString();
}

List<String> _group1All(String s, RegExp re) {
  return re.allMatches(s).map((m) => m.group(1) ?? '').toList();
}
