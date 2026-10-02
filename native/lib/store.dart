import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

import 'domain/entry.dart';
import 'domain/json.dart';
import 'domain/operation_validator.dart';
import 'persistence/schema.dart';

export 'domain/entry.dart';
export 'domain/json.dart';

part 'persistence/backups.dart';
part 'persistence/conflicts.dart';
part 'project_tools.dart';
part 'shared_activity.dart';

const uuid = Uuid();

/// Persists entities and their operation history in the same SQLite transaction.
/// Field stamps make peer replay idempotent and independent of arrival order.
class Store extends ChangeNotifier {
  final Database db;
  final Directory directory;
  late String device;
  int clock = 0;
  Store(this.directory, {Database? database})
    : db = database ?? sqlite3.open(p.join(directory.path, 'the-list.sqlite')) {
    try {
      initializeSchema(db);
      device = setting('device') ?? uuid.v4();
      setSetting('device', device);
      clock =
          (db.select('SELECT MAX(counter) AS n FROM operations').first['n']
              as int?) ??
          0;
    } catch (_) {
      db.close();
      rethrow;
    }
  }
  String? setting(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key=?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) => db.execute(
    'INSERT OR REPLACE INTO settings (key,value) VALUES(?,?)',
    [key, value],
  );
  Entry _entry(Row r) => Entry(
    r['id'] as String,
    r['project'] as String,
    r['kind'] as String,
    jsonDecode(r['fields'] as String) as Json,
  );
  List<Entry> get entries =>
      db.select('SELECT * FROM entities').map(_entry).toList();
  Entry? get(String id) {
    final rows = db.select('SELECT * FROM entities WHERE id=?', [id]);
    return rows.isEmpty ? null : _entry(rows.first);
  }

  List<Entry> get projects =>
      db
          .select('SELECT * FROM entities WHERE kind=?', ['project'])
          .map(_entry)
          .where((e) => !e.deleted && !e.flag('inbox'))
          .toList()
        ..sort(_recent);
  Map<String, int> projectTotals(String project) {
    final totals = <String, int>{};
    for (final entry in items(project).where((e) => e.kind == 'link')) {
      final cents = entry.priceMinor;
      if (cents != null) {
        totals.update(
          entry.currency,
          (total) => total + cents * entry.quantity,
          ifAbsent: () => cents * entry.quantity,
        );
      }
    }
    return totals;
  }

  List<Entry> items(String project) =>
      db
          .select('SELECT * FROM entities WHERE project=? AND kind!=?', [
            project,
            'project',
          ])
          .map(_entry)
          .where((e) => !e.deleted)
          .toList()
        ..sort(_recent);
  static int _recent(Entry a, Entry b) {
    final date = b.text('created').compareTo(a.text('created'));
    return date != 0 ? date : a.id.compareTo(b.id);
  }

  String create(String kind, String project, Json fields) {
    final id = uuid.v4();
    change(id, kind == 'project' ? id : project, kind, {
      'created': DateTime.now().toUtc().toIso8601String(),
      ...fields,
    });
    return id;
  }

  void update(Entry e, Json fields) {
    final changes = Map<String, dynamic>.fromEntries(
      fields.entries.where(
        (f) => jsonEncode(e.fields[f.key]) != jsonEncode(f.value),
      ),
    );
    if (changes.isNotEmpty) change(e.id, e.project, e.kind, changes);
  }

  void change(String id, String project, String kind, Json fields) {
    if (kind != 'reminder') requireEdit(project);
    final rows = db.select('SELECT stamps FROM entities WHERE id=?', [id]);
    apply([
      {
        'id': uuid.v4(),
        'entity': id,
        'project': project,
        'kind': kind,
        'counter': ++clock,
        'device': device,
        'fields': {
          ...fields,
          'author': setting('display-name') ?? 'This device',
          'modified': DateTime.now().toUtc().toIso8601String(),
          'base': rows.isEmpty ? '{}' : rows.first['stamps'],
        },
      },
    ]);
  }

  static void validate(Json op) => validateOperation(op);

  /// Merges a batch atomically. A [scope] identifies received peer data and
  /// confines every operation to that peer's project.
  void apply(List<Json> operations, {String? scope}) {
    for (final op in operations) {
      validate(op);
      if (scope != null && op['project'] != scope) {
        throw const FormatException('Project boundary mismatch');
      }
    }
    var committedClock = clock;
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final op in operations) {
        if (db.select('SELECT id FROM operations WHERE id=?', [
          op['id'],
        ]).isNotEmpty) {
          continue;
        }
        final existing = db.select('SELECT * FROM entities WHERE id=?', [
          op['entity'],
        ]);
        if (existing.isNotEmpty &&
            (existing.first['project'] != op['project'] ||
                existing.first['kind'] != op['kind'])) {
          throw const FormatException('Entity identity mismatch');
        }
        final fields = existing.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(existing.first['fields'] as String) as Json;
        final stamps = existing.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(existing.first['stamps'] as String) as Json;
        final stamp = [op['counter'], op['device'], op['id']];
        final bases =
            jsonDecode((op['fields'] as Map)['base'] as String? ?? '{}') as Map;
        (op['fields'] as Map).forEach((key, value) {
          final old = stamps[key] as List?;
          final expected = bases[key] as List?;
          if (old != null &&
              old[1] != op['device'] &&
              !['base', 'author', 'modified', 'created'].contains(key) &&
              (expected == null || compareStamp(expected, old) != 0) &&
              jsonEncode(fields[key]) != jsonEncode(value)) {
            db.execute(
              'INSERT OR IGNORE INTO conflicts (id,entity,field,value,device) VALUES(?,?,?,?,?)',
              [
                '${op['id']}-$key',
                op['entity'],
                key,
                jsonEncode(compareStamp(stamp, old) > 0 ? fields[key] : value),
                compareStamp(stamp, old) > 0 ? old[1] : op['device'],
              ],
            );
          }
          if (old == null || compareStamp(stamp, old) > 0) {
            fields[key as String] = value;
            stamps[key] = stamp;
          }
        });
        db.execute(
          'INSERT INTO operations (id,project,entity,kind,counter,device,fields) VALUES(?,?,?,?,?,?,?)',
          [
            op['id'],
            op['project'],
            op['entity'],
            op['kind'],
            op['counter'],
            op['device'],
            jsonEncode(op['fields']),
          ],
        );
        db.execute(
          'INSERT OR REPLACE INTO entities (id,project,kind,fields,stamps) VALUES(?,?,?,?,?)',
          [
            op['entity'],
            op['project'],
            op['kind'],
            jsonEncode(fields),
            jsonEncode(stamps),
          ],
        );
        // Receipts are private local state. Replayed/relayed operations cannot
        // create duplicates or reset a previously read comment.
        final incoming = op['fields'] as Map;
        recordActivity(op, received: scope != null);
        if (scope != null &&
            op['kind'] == 'comment' &&
            op['device'] != device &&
            incoming.containsKey('created') &&
            incoming.containsKey('body') &&
            incoming.containsKey('target')) {
          db.execute(
            'INSERT OR IGNORE INTO comment_inbox (comment,received) VALUES (?,?)',
            [op['entity'], DateTime.now().toUtc().toIso8601String()],
          );
        }
        if ((op['counter'] as int) > committedClock) {
          committedClock = op['counter'] as int;
        }
      }
      db.execute('COMMIT');
      clock = committedClock;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    notifyListeners();
  }

  static int compareStamp(List a, List b) {
    final n = (a[0] as int).compareTo(b[0] as int);
    if (n != 0) return n;
    final d = (a[1] as String).compareTo(b[1] as String);
    return d != 0 ? d : (a[2] as String).compareTo(b[2] as String);
  }

  Json _operation(Row r) => {
    'id': r['id'],
    'project': r['project'],
    'entity': r['entity'],
    'kind': r['kind'],
    'counter': r['counter'],
    'device': r['device'],
    'fields': jsonDecode(r['fields'] as String),
  };
  List<Json> operations(String project, {bool includeReminders = false}) => db
      .select(
        'SELECT * FROM operations WHERE project=? ORDER BY counter,device,id',
        [project],
      )
      .where((r) => includeReminders || r['kind'] != 'reminder')
      .map(_operation)
      .toList();
  List<Json> history(String id) => db
      .select(
        'SELECT * FROM operations WHERE entity=? ORDER BY counter DESC,device DESC',
        [id],
      )
      .map(
        (r) => {
          'device': r['device'],
          'fields': jsonDecode(r['fields'] as String),
        },
      )
      .toList();
  File blob(String hash) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid attachment hash');
    }
    return File(p.join(directory.path, 'photos', '$hash.jpg'));
  }

  Future<void> exportTo(File file) async =>
      file.writeAsString(await exportData(), flush: true);

  /// Rebuilds an export's exact entity versions without consulting live data.
  static List<Entry> snapshotEntries(Json snapshot) {
    final frozen = Store(
      Directory.systemTemp,
      database: sqlite3.openInMemory(),
    );
    try {
      frozen.apply(
        (snapshot['operations'] as List)
            .map((operation) => Map<String, dynamic>.from(operation as Map))
            .toList(),
      );
      return frozen.entries..sort(_recent);
    } finally {
      frozen.dispose();
    }
  }

  Future<String> exportData({Set<String>? projects}) =>
      _exportData(projects: projects);

  Future<void> importFrom(
    File file, {
    Set<String>? projects,
    bool restoreTemplates = true,
  }) =>
      _importFrom(file, projects: projects, restoreTemplates: restoreTemplates);

  void touch() => notifyListeners();
  @override
  void dispose() {
    db.close();
    super.dispose();
  }
}
