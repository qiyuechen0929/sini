import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sini/utils/doc_extract.dart';

Archive _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, content) {
    final b = utf8.encode(content);
    a.addFile(ArchiveFile(name, b.length, b));
  });
  return a;
}

void main() {
  test('纯文本直接解码', () {
    expect(extractDocumentText('笔记.txt', utf8.encode('你好，世界')),
        '你好，世界');
    expect(extractDocumentText('data.json', utf8.encode('{"a":1}')), '{"a":1}');
  });

  test('docx 抽段落', () {
    final docx = _zip({
      'word/document.xml':
          '<?xml version="1.0"?><w:document><w:body>'
          '<w:p><w:r><w:t>第一段标题</w:t></w:r></w:p>'
          '<w:p><w:r><w:t xml:space="preserve">第二段 &amp; 更多</w:t></w:r></w:p>'
          '</w:body></w:document>',
    });
    final bytes = ZipEncoder().encode(docx)!;
    expect(extractDocumentText('方案.docx', bytes), '第一段标题\n第二段 & 更多');
  });

  test('pptx 按页抽文字', () {
    final pptx = _zip({
      'ppt/slides/slide2.xml':
          '<p:spx><a:t>第二页内容</a:t></p:spx>',
      'ppt/slides/slide1.xml': '<p:spx><a:t>第一页标题</a:t></p:spx>',
    });
    final bytes = ZipEncoder().encode(pptx)!;
    expect(extractDocumentText('汇报.pptx', bytes),
        '—— 第 1 页 ——\n第一页标题\n—— 第 2 页 ——\n第二页内容');
  });

  test('xlsx 抽 sharedStrings + sheet 值', () {
    final xlsx = _zip({
      'xl/sharedStrings.xml':
          '<sst><si><t>姓名</t></si><si><t>张三</t></si></sst>',
      'xl/worksheets/sheet1.xml':
          '<worksheet><sheetData>'
          '<row r="1"><c t="s" r="A1"><v>0</v></c></row>'
          '<row r="2"><c t="s" r="A2"><v>1</v></c><c r="B2"><v>18</v></c></row>'
          '</sheetData></worksheet>',
    });
    final bytes = ZipEncoder().encode(xlsx)!;
    expect(extractDocumentText('表.xlsx', bytes),
        '—— sheet1.xml ——\n姓名\n张三 | 18');
  });

  test('不支持 / 损坏类型返回 null 而不是抛异常', () {
    expect(extractDocumentText('照片.png', [1, 2, 3]), isNull);
    expect(extractDocumentText('坏.docx', [80, 75, 3, 4, 1, 2, 3]), isNull);
  });

  test('超长内容截断', () {
    final long = '字' * 50000;
    final out = extractDocumentText('长.md', utf8.encode(long))!;
    expect(out.length, lessThan(50000));
    expect(out, contains('已截断'));
  });
}
