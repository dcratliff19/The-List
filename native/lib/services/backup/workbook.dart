import 'dart:convert';
import 'package:archive/archive.dart';
import '../../store.dart';

/// Encodes one frozen snapshot as a workbook, preserving raw operation history.
List<int> buildWorkbook(List<Entry> entries, Map<String, dynamic> snapshot) {
  final sheets = <String, List<List<String>>>{};
  final projects = {
    for (final e in entries.where((e) => e.kind == 'project')) e.id: e.title,
  };
  sheets['Summary'] = [
    ['The List — workspace backup', DateTime.now().toUtc().toIso8601String()],
    [
      'Restore',
      'Import the accompanying .thelist file to recover full data and original photos.',
    ],
    ['Prices', 'Totals exclude deleted links and are separated by currency.'],
    [
      'Photo data',
      'Original photo bytes are preserved in the accompanying .thelist file.',
    ],
    ['Project', 'Currency', 'Total'],
    for (final project in projects.entries)
      for (final currency in Entry.currencies)
        if (entries.any(
          (e) =>
              e.project == project.key &&
              e.kind == 'link' &&
              !e.deleted &&
              e.priceMinor != null &&
              e.currency == currency,
        ))
          [
            project.value,
            currency,
            Entry.amount(
              entries
                  .where(
                    (e) =>
                        e.project == project.key &&
                        e.kind == 'link' &&
                        !e.deleted &&
                        e.currency == currency,
                  )
                  .fold<int>(
                    0,
                    (sum, e) => sum + (e.priceMinor ?? 0) * e.quantity,
                  ),
            ),
          ],
  ];
  const fields = [
    'title',
    'url',
    'body',
    'description',
    'tags',
    'price',
    'currency',
    'boardStatus',
    'due',
    'zone',
    'target',
    'done',
    'favorite',
    'archived',
    'deleted',
    'created',
    'photo',
    'cover',
    'previewTitle',
    'previewDescription',
    'previewStatus',
    'previewError',
    'label',
    'color',
    'quantity',
    'purchaseStatus',
    'comparison',
    'budget',
    'budgetCurrency',
    'columns',
    'rank',
    'assignee',
    'repeat',
    'repeatDay',
    'lastCompleted',
    'author',
    'modified',
    'inbox',
  ];
  for (final kind in {
    'project': 'Projects',
    'link': 'Links',
    'note': 'Notes',
    'photo': 'Photos',
    'reminder': 'Reminders',
    'check': 'Checklists',
    'comment': 'Comments',
  }.entries) {
    sheets[kind.value] = [
      ['ID', 'Project ID', 'Project', ...fields],
      for (final entry in entries.where((e) => e.kind == kind.key))
        [
          entry.id,
          entry.project,
          projects[entry.project] ?? '',
          ...fields.map(entry.text),
        ],
    ];
  }
  // Chunking avoids Excel's 32,767-character cell limit without dropping history.
  sheets['Raw data'] = [
    ['Section', 'Record', 'Part', 'JSON (join parts in order)'],
  ];
  for (final section in snapshot.entries.where((e) => e.key != 'photos')) {
    final records = section.value is List
        ? section.value as List
        : [section.value];
    for (var index = 0; index < records.length; index++) {
      final raw = jsonEncode(records[index]);
      for (var offset = 0; offset < raw.length; offset += 16000) {
        sheets['Raw data']!.add([
          section.key,
          '$index',
          '${offset ~/ 16000}',
          raw.substring(offset, (offset + 16000).clamp(0, raw.length)),
        ]);
      }
    }
  }
  final archive = Archive();
  void add(String name, String xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  String escape(String value) => value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  String column(int index) {
    var result = '';
    for (var n = index + 1; n > 0; n = (n - 1) ~/ 26) {
      result = String.fromCharCode(65 + (n - 1) % 26) + result;
    }
    return result;
  }

  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${List.generate(sheets.length, (i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}</Types>',
  );
  add(
    '_rels/.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sheets.keys.toList().asMap().entries.map((e) => '<sheet name="${escape(e.value)}" sheetId="${e.key + 1}" r:id="rId${e.key + 1}"/>').join()}</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${List.generate(sheets.length, (i) => '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join()}</Relationships>',
  );
  var number = 0;
  for (final rows in sheets.values) {
    number++;
    final xml = StringBuffer(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="18"/><cols><col min="1" max="30" width="25" customWidth="1"/></cols><sheetData>',
    );
    for (var row = 0; row < rows.length; row++) {
      xml.write('<row r="${row + 1}">');
      for (var col = 0; col < rows[row].length; col++) {
        final value = rows[row][col];
        final numeric =
            (number == 1 && row >= 5 && col == 2) ||
            (number == 3 && row > 0 && col == 8);
        if (numeric && value.isNotEmpty) {
          xml.write(
            '<c r="${column(col)}${row + 1}"><v>${escape(value)}</v></c>',
          );
          continue;
        }
        xml.write(
          '<c r="${column(col)}${row + 1}" t="inlineStr"><is><t xml:space="preserve">${escape(value.length > 32000 ? '${value.substring(0, 31900)} [full value in Raw data]' : value)}</t></is></c>',
        );
      }
      xml.write('</row>');
    }
    xml.write(
      '</sheetData><autoFilter ref="A1:${column(rows.first.length - 1)}${rows.length}"/></worksheet>',
    );
    add('xl/worksheets/sheet$number.xml', xml.toString());
  }
  return ZipEncoder().encode(archive);
}
