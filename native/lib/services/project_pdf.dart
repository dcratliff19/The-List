import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import '../store.dart';

Future<Uint8List> projectPdf(Entry project, List<Entry> entries) async {
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final document = pw.Document();
  List<pw.Widget> paragraphs(String text) => [
    for (var offset = 0; offset < text.length; offset += 500)
      pw.Paragraph(
        text: text.substring(offset, (offset + 500).clamp(0, text.length)),
      ),
  ];
  document.addPage(
    pw.MultiPage(
      maxPages: 1000,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      build: (_) => [
        pw.Header(level: 0, text: project.title),
        ...paragraphs(project.text('description')),
        for (final entry in entries.where(
          (e) => ['link', 'note', 'photo'].contains(e.kind),
        )) ...[
          pw.Header(level: 1, text: entry.title),
          if (entry.text('url').isNotEmpty)
            pw.UrlLink(
              destination: entry.text('url'),
              child: pw.Text(entry.text('url')),
            ),
          if (entry.priceLabel.isNotEmpty)
            pw.Text('${entry.priceLabel} × ${entry.quantity}'),
          ...paragraphs(entry.text('body')),
          ...paragraphs('Tags: ${entry.tags.join(', ')}'),
          if (entry.text('assignee').isNotEmpty)
            pw.Text('Assigned to: ${entry.text('assignee')}'),
          for (final child in entries.where(
            (e) =>
                e.text('target') == entry.id &&
                ['check', 'comment', 'reminder'].contains(e.kind),
          ))
            ...paragraphs(
              child.kind == 'check'
                  ? '${child.flag('done') ? '[x]' : '[ ]'} ${child.title}'
                  : child.kind == 'comment'
                  ? '${child.text('author')}: ${child.text('body')}'
                  : 'Reminder: ${child.title} ${child.text('due')}',
            ),
          pw.SizedBox(height: 12),
        ],
      ],
    ),
  );
  return document.save();
}
