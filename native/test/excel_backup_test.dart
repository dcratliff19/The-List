import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_list/store.dart';
import 'package:the_list/services/excel_backup.dart';

void main() {
  test(
    'export materialization stays consistent after subsequent peer edits',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'the-list-snapshot-',
      );
      final store = Store(directory);
      try {
        final project = store.create('project', '', {'title': 'Snapshot'});
        final note = store.create('note', project, {
          'body': 'Captured revision',
        });
        final snapshot = jsonDecode(await store.exportData()) as Json;
        store.update(store.get(note)!, {'body': 'Later revision'});
        final entries = Store.snapshotEntries(snapshot);
        expect(
          entries.firstWhere((entry) => entry.id == note).text('body'),
          'Captured revision',
        );
        expect(store.get(note)!.text('body'), 'Later revision');
      } finally {
        store.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Excel and restore backup retain records, history, literal formulas and exact prices',
    () async {
      final dir = Directory.systemTemp.createTempSync('the-list-backup-test-');
      final store = Store(dir);
      final backup = ExcelBackup(store);
      try {
        store.setSetting('excel-folder', '${dir.path}/exports');
        final pid = store.create('project', '', {'title': 'Test project'});
        store.create('link', pid, {
          'title': '=HYPERLINK("evil")',
          'url': 'https://example.com',
          'price': '19.95',
          'currency': 'USD',
        });
        store.create('note', pid, {
          'title': 'Long note',
          'body': List.filled(40000, 'x').join(),
        });
        store.create('reminder', pid, {
          'title': 'Review',
          'due': DateTime.now().toUtc().toIso8601String(),
          'done': false,
        });
        final bytes = utf8.encode('photo fixture');
        final hash = sha256.convert(bytes).toString();
        store.blob(hash).parent.createSync(recursive: true);
        store.blob(hash).writeAsBytesSync(bytes);
        store.create('photo', pid, {'title': 'Photo', 'photo': hash});
        final folder = Directory(await backup.run());
        final workbook = folder.listSync().whereType<File>().firstWhere(
          (f) => f.path.endsWith('.xlsx'),
        );
        final archive = ZipDecoder().decodeBytes(workbook.readAsBytesSync());
        final links = utf8.decode(
          archive.findFile('xl/worksheets/sheet3.xml')!.content as List<int>,
        );
        expect(links, contains('t="inlineStr"'));
        expect(links, contains('=HYPERLINK'));
        expect(links, isNot(contains('<f>')));
        expect(links, contains('<v>19.95</v>'));
        expect(archive.findFile('xl/worksheets/sheet7.xml'), isNotNull);
        final restored = Store(Directory('${dir.path}/restored')..createSync());
        try {
          await restored.importFrom(
            folder.listSync().whereType<File>().firstWhere(
              (f) => f.path.endsWith('.thelist'),
            ),
          );
          expect(restored.entries.length, store.entries.length);
          expect(restored.blob(hash).readAsBytesSync(), bytes);
          expect(
            restored.entries
                .firstWhere((e) => e.kind == 'note')
                .text('body')
                .length,
            40000,
          );
        } finally {
          restored.dispose();
        }
        expect(store.setting('excel-error'), '');
        final first = store.setting('excel-last');
        store.setSetting('excel-enabled', 'on');
        store.setSetting(
          'excel-since',
          DateTime.now()
              .subtract(const Duration(days: 2))
              .toUtc()
              .toIso8601String(),
        );
        await backup.checkDue();
        expect(store.setting('excel-last'), first);
      } finally {
        backup.dispose();
        store.dispose();
        dir.deleteSync(recursive: true);
      }
    },
  );
}
