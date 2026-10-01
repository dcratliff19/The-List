import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_list/store.dart';
import 'package:the_list/services/excel_backup.dart';
import 'package:the_list/services/project_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Store store;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('the-list-planning-');
    store = Store(directory);
  });
  tearDown(() {
    store.dispose();
    directory.deleteSync(recursive: true);
  });

  test('PDF summary paginates a long saved note', () async {
    final pid = store.create('project', '', {'title': 'Project summary'});
    store.create('note', pid, {
      'title': 'Long research',
      'body': List.filled(
        4000,
        'A useful observation. ',
      ).join().substring(0, 49000),
    });
    final bytes = await projectPdf(store.get(pid)!, store.items(pid));
    expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(10000));
  });

  test(
    'manual board membership, ordering, columns, tags and empty templates',
    () {
      final pid = store.create('project', '', {'title': 'Workshop'});
      final a = store.create('note', pid, {
        'title': 'First',
        'tags': 'Desk blue',
      });
      final b = store.create('note', pid, {
        'title': 'Second',
        'tags': 'desk Green',
      });
      expect(store.cards(pid, 'todo'), isEmpty);
      store.saveColumns(pid, {'research': 'Research', 'ready': 'Ready'});
      store.update(store.get(a)!, {'boardStatus': 'research', 'rank': 0});
      store.update(store.get(b)!, {'boardStatus': 'research', 'rank': 1});
      store.reorderCard(store.get(b)!, -1);
      expect(store.cards(pid, 'research').map((e) => e.id), [b, a]);
      expect(
        () => store.saveColumns(pid, {'ready': 'Ready'}),
        throwsFormatException,
      );
      store.renameTag('desk', 'Workspace blue');
      expect(store.get(a)!.tags, ['Workspace', 'blue']);
      expect(store.get(b)!.tags, ['Workspace', 'blue', 'Green']);
      store.saveTemplate(store.get(pid)!, 'Workshop template');
      final created = store.createFromTemplate(
        store.templates.single,
        'Next project',
      );
      expect(store.items(created), isEmpty);
      expect(store.columns(created), {
        'research': 'Research',
        'ready': 'Ready',
      });
    },
  );

  test(
    'quantities and explicit selections keep alternative costs separate',
    () {
      final pid = store.create('project', '', {
        'title': 'Desk',
        'budget': '100.00',
        'budgetCurrency': 'USD',
      });
      final a = store.create('link', pid, {
        'title': 'A',
        'url': 'https://example.com/a',
        'price': '12.50',
        'currency': 'USD',
        'quantity': 3,
        'comparison': 'Lamp',
      });
      final b = store.create('link', pid, {
        'title': 'B',
        'url': 'https://example.com/b',
        'price': '20',
        'currency': 'USD',
        'comparison': 'Lamp',
      });
      expect(store.plannedTotals(pid), isEmpty);
      expect(store.projectTotals(pid), {'USD': 5750});
      store.chooseAlternative(store.get(a)!);
      expect(store.plannedTotals(pid), {'USD': 3750});
      store.chooseAlternative(store.get(b)!);
      expect(store.plannedTotals(pid), {'USD': 2000});
      expect(store.get(a)!.text('purchaseStatus'), 'considering');
    },
  );

  test(
    'normalized duplicate detection and inbox moves require explicit choices',
    () {
      expect(
        ProjectTools.normalizedUrl('https://EXAMPLE.com/?utm_source=test#top'),
        'https://example.com',
      );
      final pid = store.create('project', '', {'title': 'Saved'});
      store.create('link', pid, {
        'url': 'https://example.com/?a=1&utm_source=x',
      });
      expect(store.duplicate(pid, 'https://example.com?a=1#title'), isNotNull);
      final inbox = store.inbox();
      final item = store.create('link', inbox, {
        'url': 'https://example.com/new',
      });
      expect(store.projects.map((e) => e.id), [pid]);
      final moved = store.moveFromInbox(store.get(item)!, pid);
      expect(store.get(item)!.deleted, isTrue);
      expect(store.get(moved)!.text('boardStatus'), '');
      expect(store.get(moved)!.project, pid);
    },
  );

  test('recurrence advances overdue reminders and preserves month day', () {
    final pid = store.create('project', '', {'title': 'Routine'});
    final id = store.create('reminder', pid, {
      'due': '2020-01-31T12:00:00',
      'repeat': 'monthly',
      'repeatDay': 31,
    });
    store.completeReminder(store.get(id)!, true);
    final due = DateTime.parse(store.get(id)!.text('due')).toLocal();
    expect(due.isAfter(DateTime.now()), isTrue);
    expect(due.day, 31.clamp(1, DateTime(due.year, due.month + 1, 0).day));
    expect(store.get(id)!.flag('done'), isFalse);
    expect(store.get(id)!.text('lastCompleted'), isNotEmpty);
  });

  test('URL normalization preserves repeated values and encoded delimiters', () {
    expect(
      ProjectTools.normalizedUrl(
        'https://example.com/search?tag=desk&tag=lamp&q=a%26b&utm_source=test',
      ),
      'https://example.com/search?q=a%26b&tag=desk&tag=lamp',
    );
    expect(
      ProjectTools.normalizedUrl('https://example.com/?tag=desk&tag=lamp'),
      isNot(ProjectTools.normalizedUrl('https://example.com/?tag=lamp')),
    );
  });

  test('concurrent same-field changes retain losing value for review', () {
    final otherDir = Directory('${directory.path}/peer')..createSync();
    final other = Store(otherDir);
    try {
      final pid = store.create('project', '', {'title': 'Original'});
      other.apply(store.operations(pid));
      store.update(store.get(pid)!, {'title': 'Local'});
      other.update(other.get(pid)!, {'title': 'Remote'});
      final localOps = store.operations(pid), remoteOps = other.operations(pid);
      store.apply(remoteOps);
      other.apply(localOps);
      expect(store.get(pid)!.title, other.get(pid)!.title);
      final values = store.db
          .select('SELECT value FROM conflicts')
          .map((r) => jsonDecode(r['value'] as String));
      expect(
        values,
        contains(store.get(pid)!.title == 'Local' ? 'Remote' : 'Local'),
      );
      expect(values, isNot(contains(store.get(pid)!.title)));
    } finally {
      other.dispose();
    }
  });

  test(
    'backup preview includes inbox and selective restore excludes other projects',
    () async {
      final pid = store.create('project', '', {'title': 'Selected'});
      store.create('check', pid, {
        'title': 'Task',
        'target': pid,
        'done': false,
      });
      store.create('comment', pid, {'body': 'Discuss', 'target': pid});
      store.create('note', store.inbox(), {'title': 'Inbox note'});
      final file = File('${directory.path}/export.thelist')
        ..writeAsStringSync(await store.exportData());
      final preview = await store.previewBackup(file);
      expect((preview['projects'] as List).length, 2);
      final other = Store(Directory('${directory.path}/restore')..createSync());
      try {
        await other.importFrom(file, projects: {pid});
        expect(other.entries.length, 3);
        expect(other.childrenOf(pid, 'check').single.title, 'Task');
      } finally {
        other.dispose();
      }
    },
  );

  test(
    'verified backups prune only opted-in intact app-owned folders',
    () async {
      store.create('project', '', {'title': 'Backup'});
      store.setSetting('excel-folder', '${directory.path}/backups');
      final service = ExcelBackup(store);
      try {
        final old = await service.run();
        await service.verify(old);
        final marker = File('$old/manifest.json');
        final manifest = jsonDecode(marker.readAsStringSync()) as Map;
        manifest['created'] = DateTime.now()
            .subtract(const Duration(days: 100))
            .toIso8601String();
        marker.writeAsStringSync(jsonEncode(manifest));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final latest = await service.run();
        expect(Directory(old).existsSync(), isTrue);
        store.setSetting('excel-retention-days', '30');
        await service.prune();
        expect(Directory(old).existsSync(), isFalse);
        expect(Directory(latest).existsSync(), isTrue);
        final workbook = Directory(latest)
            .listSync()
            .whereType<File>()
            .firstWhere((f) => f.path.endsWith('.xlsx'));
        workbook.writeAsStringSync('corrupted');
        await expectLater(service.verify(latest), throwsFormatException);
      } finally {
        service.dispose();
      }
    },
  );
}
