import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:the_list/store.dart';
import 'package:the_list/domain/entry_query.dart';

void main() {
  test(
    'conflict review enforces access and records an alternative as a local edit',
    () {
      final store = Store(
        Directory.systemTemp,
        database: sqlite3.openInMemory(),
      );
      addTearDown(store.dispose);
      final project = store.create('project', '', {'title': 'Project'});
      final note = store.create('note', project, {'body': 'Original'});
      store.apply([
        {
          'id': 'competing',
          'entity': note,
          'project': project,
          'device': 'peer',
          'counter': 900,
          'kind': 'note',
          'fields': {'body': 'Competing'},
        },
      ]);
      final conflict = store.unresolvedConflicts(project).single;
      store.setProjectAccess(project, 'room', false, 'read');
      expect(
        () => store.resolveConflict(
          conflict['id'] as String,
          useAlternative: true,
        ),
        throwsStateError,
      );
      expect(store.unresolvedConflicts(project), hasLength(1));
      store.setProjectAccess(project, 'room', false, 'update');
      store.resolveConflict(conflict['id'] as String, useAlternative: true);
      expect(store.get(note)!.text('body'), 'Original');
      expect(store.unresolvedConflicts(project), isEmpty);
      expect(store.operations(project).last['device'], store.device);
    },
  );
  test(
    'a failed batch rolls back entities, operations and the logical clock',
    () {
      final store = Store(
        Directory.systemTemp,
        database: sqlite3.openInMemory(),
      );
      addTearDown(store.dispose);
      final project = store.create('project', '', {'title': 'Existing'});
      final beforeClock = store.clock;
      final beforeOperations = store.operations(project).length;
      var notifications = 0;
      store.addListener(() => notifications++);
      final operation = {
        'id': 'incoming',
        'entity': 'new-note',
        'project': project,
        'device': 'peer',
        'counter': 900,
        'kind': 'note',
        'fields': {'body': 'New'},
      };
      expect(
        () => store.apply([
          operation,
          {...operation, 'id': 'identity-conflict', 'entity': project},
        ]),
        throwsFormatException,
      );
      expect(store.get('new-note'), isNull);
      expect(store.operations(project).length, beforeOperations);
      expect(store.clock, beforeClock);
      expect(notifications, 0);
      store.apply([operation]);
      expect(store.clock, 900);
      expect(notifications, 1);
    },
  );

  test(
    'opening an unsupported future database preserves its schema and contents',
    () {
      final dir = Directory.systemTemp.createTempSync('the-list-future-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/the-list.sqlite';
      final db = sqlite3.open(path);
      db.execute('PRAGMA user_version=2');
      db.execute('CREATE TABLE future_data (value TEXT)');
      db.execute("INSERT INTO future_data VALUES ('preserve me')");
      db.close();
      expect(() => Store(dir), throwsFormatException);
      final reopened = sqlite3.open(path);
      addTearDown(reopened.close);
      expect(reopened.select('PRAGMA user_version').first['user_version'], 2);
      expect(
        reopened.select('SELECT value FROM future_data').first['value'],
        'preserve me',
      );
      expect(
        reopened.select("SELECT name FROM sqlite_master WHERE name='entities'"),
        isEmpty,
      );
    },
  );

  test('search combines visible text terms and case-insensitive tag terms', () {
    final entry = Entry('n', 'p', 'note', {
      'title': 'Kitchen ideas',
      'body': 'Quiet corner',
      'tags': 'Home, #Green',
    });
    expect(EntryQuery(' kitchen   #GREEN corner ').matches(entry), isTrue);
    expect(EntryQuery('#kitchen').matches(entry), isFalse);
    expect(EntryQuery('kitchen missing').matches(entry), isFalse);
    expect(EntryQuery('').matches(entry), isTrue);
  });
}
