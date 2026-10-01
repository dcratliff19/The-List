import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

part 'project_tools.dart';
part 'shared_activity.dart';

typedef Json = Map<String, dynamic>;
const uuid = Uuid();

/// A materialized entity; its individual field revisions live in [Store].
class Entry {
  final String id, project, kind;
  final Json fields;
  Entry(this.id, this.project, this.kind, this.fields);
  String text(String key) => fields[key]?.toString() ?? '';
  bool flag(String key) => fields[key] == true;
  List<String> get tags => parseTags(text('tags'));
  static List<String> parseTags(String text) {
    final seen = <String>{};
    return text
        .split(RegExp(r'[\s,]+'))
        .map((tag) => tag.replaceFirst(RegExp(r'^#+'), ''))
        .where((tag) => tag.isNotEmpty && seen.add(tag.toLowerCase()))
        .toList();
  }

  static const currencies = ['USD', 'EUR', 'GBP', 'CAD', 'AUD'];
  static int? parsePrice(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(text)) {
      throw const FormatException(
        'Enter a positive price with up to two decimal places, or leave blank.',
      );
    }
    final parts = text.split('.');
    return int.parse(parts[0]) * 100 +
        int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  }

  static String amount(int cents) =>
      '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
  int? get priceMinor => parsePrice(text('price'));
  String get currency =>
      currencies.contains(text('currency')) ? text('currency') : 'USD';
  String get priceLabel =>
      priceMinor == null ? '' : '$currency ${amount(priceMinor!)}';
  int get quantity => (fields['quantity'] as int?) ?? 1;
  String get title => text('title');
  bool get deleted => flag('deleted');
  Json toJson() => {
    'id': id,
    'project': project,
    'kind': kind,
    'fields': fields,
  };
}

/// Persists entities and their operation history in the same SQLite transaction.
/// Field stamps make peer replay idempotent and independent of arrival order.
class Store extends ChangeNotifier {
  final Database db;
  final Directory directory;
  late String device;
  int clock = 0;
  Store(this.directory, {Database? database})
    : db = database ?? sqlite3.open(p.join(directory.path, 'the-list.sqlite')) {
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA foreign_keys=ON');
    db.execute('PRAGMA busy_timeout=5000');
    db.execute(
      'CREATE TABLE IF NOT EXISTS comment_inbox (comment TEXT PRIMARY KEY, received TEXT NOT NULL, seen INTEGER NOT NULL DEFAULT 0)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS conflicts (id TEXT PRIMARY KEY,entity TEXT,field TEXT,value TEXT,device TEXT,resolved INTEGER DEFAULT 0)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY,value TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS operations (id TEXT PRIMARY KEY,project TEXT NOT NULL,entity TEXT NOT NULL,kind TEXT NOT NULL,counter INTEGER NOT NULL,device TEXT NOT NULL,fields TEXT NOT NULL)',
    );
    db.execute('CREATE INDEX IF NOT EXISTS project_ops ON operations(project)');
    db.execute(
      'CREATE TABLE IF NOT EXISTS entities (id TEXT PRIMARY KEY,project TEXT NOT NULL,kind TEXT NOT NULL,fields TEXT NOT NULL,stamps TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS project_access (room TEXT PRIMARY KEY, project TEXT NOT NULL, host INTEGER NOT NULL, access TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS activity_feed (op TEXT PRIMARY KEY, received TEXT NOT NULL, seen INTEGER NOT NULL DEFAULT 0)',
    );
    db.execute('PRAGMA user_version=1');
    device = setting('device') ?? uuid.v4();
    setSetting('device', device);
    clock =
        (db.select('SELECT MAX(counter) AS n FROM operations').first['n']
            as int?) ??
        0;
  }
  String? setting(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key=?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) =>
      db.execute('INSERT OR REPLACE INTO settings VALUES(?,?)', [key, value]);
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
      entries
          .where((e) => e.kind == 'project' && !e.deleted && !e.flag('inbox'))
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
      entries
          .where(
            (e) => e.project == project && e.kind != 'project' && !e.deleted,
          )
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

  static void validate(Json op) {
    if (![
          'project',
          'link',
          'note',
          'photo',
          'reminder',
          'check',
          'comment',
        ].contains(op['kind']) ||
        op['id'] is! String ||
        op['entity'] is! String ||
        op['project'] is! String ||
        op['device'] is! String ||
        op['counter'] is! int ||
        op['fields'] is! Map) {
      throw const FormatException('Invalid project data');
    }
    if ((op['counter'] as int) < 0 ||
        (op['counter'] as int) > 9007199254740000 ||
        jsonEncode(op).length > 262144) {
      throw const FormatException('Project data exceeds limits');
    }
    for (final key in ['id', 'entity', 'project', 'device']) {
      if ((op[key] as String).isEmpty || (op[key] as String).length > 128) {
        throw const FormatException('Invalid identity');
      }
    }
    if (op['kind'] == 'project' && op['entity'] != op['project']) {
      throw const FormatException('Invalid project identity');
    }
    const strings = {
      'title',
      'body',
      'description',
      'url',
      'tags',
      'photo',
      'cover',
      'due',
      'zone',
      'target',
      'created',
      'label',
      'previewTitle',
      'previewDescription',
      'previewError',
      'previewStatus',
      'boardStatus',
      'price',
      'currency',
      'budget',
      'budgetCurrency',
      'columns',
      'assignee',
      'purchaseStatus',
      'comparison',
      'repeat',
      'lastCompleted',
      'author',
      'modified',
      'base',
    };
    const flags = {
      'deleted',
      'archived',
      'favorite',
      'example',
      'done',
      'inbox',
    };
    (op['fields'] as Map).forEach((key, value) {
      if (key == 'price' || key == 'budget') {
        if (value is! String) throw const FormatException('Invalid price');
        Entry.parsePrice(value);
      }
      if (['currency', 'budgetCurrency'].contains(key) &&
          !Entry.currencies.contains(value)) {
        throw const FormatException('Invalid currency');
      }
      if (strings.contains(key)) {
        if (value is! String || value.length > 50000) {
          throw const FormatException('Invalid text field');
        }
      } else if (flags.contains(key)) {
        if (value is! bool) throw const FormatException('Invalid flag');
      } else if (['quantity', 'rank', 'repeatDay'].contains(key)) {
        if (value is! int ||
            value < 0 ||
            value > 1000000 ||
            (key == 'quantity' && value < 1)) {
          throw const FormatException('Invalid quantity or order');
        }
      } else if (key == 'color') {
        if (value is! int || value < 0 || value > 0xffffffff) {
          throw const FormatException('Invalid color');
        }
      } else {
        throw const FormatException('Unknown project field');
      }
      if (key == 'columns' && value != '') {
        final columns = jsonDecode(value as String);
        if (columns is! Map ||
            columns.isEmpty ||
            columns.length > 20 ||
            columns.entries.any(
              (e) =>
                  e.key is! String ||
                  (e.key as String).isEmpty ||
                  (e.key as String).length > 128 ||
                  e.value is! String ||
                  (e.value as String).trim().isEmpty ||
                  (e.value as String).length > 60,
            )) {
          throw const FormatException('Invalid board columns');
        }
      }
      if (key == 'repeat' &&
          ![
            '',
            'none',
            'daily',
            'weekly',
            'monthly',
            'days:1,2,3,4,5',
          ].contains(value)) {
        throw const FormatException('Invalid reminder recurrence');
      }
      if (key == 'base') {
        final bases = jsonDecode(value as String);
        if (bases is! Map ||
            bases.values.any(
              (v) =>
                  v is! List ||
                  v.length != 3 ||
                  v[0] is! int ||
                  v[1] is! String ||
                  v[2] is! String,
            )) {
          throw const FormatException('Invalid revision ancestry');
        }
      }
      if ((key == 'photo' || key == 'cover') &&
          value != '' &&
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value as String)) {
        throw const FormatException('Invalid photo reference');
      }
    });
  }

  /// Merges a batch atomically. A [scope] identifies received peer data and
  /// confines every operation to that peer's project.
  void apply(List<Json> operations, {String? scope}) {
    for (final op in operations) {
      validate(op);
      if (scope != null && op['project'] != scope) {
        throw const FormatException('Project boundary mismatch');
      }
    }
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
        db.execute('INSERT INTO operations VALUES(?,?,?,?,?,?,?)', [
          op['id'],
          op['project'],
          op['entity'],
          op['kind'],
          op['counter'],
          op['device'],
          jsonEncode(op['fields']),
        ]);
        db.execute('INSERT OR REPLACE INTO entities VALUES(?,?,?,?,?)', [
          op['entity'],
          op['project'],
          op['kind'],
          jsonEncode(fields),
          jsonEncode(stamps),
        ]);
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
        if ((op['counter'] as int) > clock) clock = op['counter'] as int;
      }
      db.execute('COMMIT');
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

  Future<String> exportData({Set<String>? projects}) async {
    final ops = db
        .select('SELECT * FROM operations')
        .map(_operation)
        .where((o) => projects == null || projects.contains(o['project']))
        .toList();
    // Capture metadata before awaiting file reads. Include historical references
    // so restoring an earlier photo revision after import still works.
    final savedTemplates = projects == null ? templates : null;
    final hashes = ops
        .expand(
          (op) => ['photo', 'cover'].map((key) => (op['fields'] as Map)[key]),
        )
        .whereType<String>()
        .where((hash) => hash.isNotEmpty)
        .toSet();
    final photos = <String, String>{};
    var total = 0;
    for (final hash in hashes) {
      final file = blob(hash);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        total += bytes.length;
        if (total > 100 * 1024 * 1024) {
          throw const FormatException(
            'This portable backup exceeds 100 MB of photos. Copy the local workspace folder for a complete backup.',
          );
        }
        photos[hash] = base64Encode(bytes);
      }
    }
    return jsonEncode({
      'format': 'the-list',
      'version': 1,
      'operations': ops,
      'photos': photos,
      'templates': ?savedTemplates,
    });
  }

  Future<void> importFrom(
    File file, {
    Set<String>? projects,
    bool restoreTemplates = true,
  }) async {
    if (await file.length() > 200 * 1024 * 1024) {
      throw const FormatException('Backup exceeds 200 MB');
    }
    final data = jsonDecode(await file.readAsString()) as Json;
    if (data['format'] != 'the-list' || data['version'] != 1) {
      throw const FormatException('Unsupported backup format');
    }
    final ops = (data['operations'] as List)
        .map((o) => Map<String, dynamic>.from(o as Map))
        .where((o) => projects == null || projects.contains(o['project']))
        .toList();
    for (final op in ops) {
      requireEdit(op['project'] as String);
      validate(op);
    }
    final combined = templates;
    if (restoreTemplates && data['templates'] is List) {
      for (final value in data['templates'] as List) {
        if (value is! Map ||
            value['name'] is! String ||
            value['columns'] is! String) {
          continue;
        }
        final template = <String, dynamic>{
          for (final key in ['name', 'description', 'label', 'columns', 'tags'])
            key: value[key] ?? '',
        };
        if (template.values.any((v) => v is! String || v.length > 50000) ||
            (template['name'] as String).trim().isEmpty) {
          throw const FormatException('Invalid template');
        }
        final id = uuid.v4();
        validate({
          'id': id,
          'entity': id,
          'project': id,
          'device': device,
          'counter': 1,
          'kind': 'project',
          'fields': {'columns': template['columns']},
        });
        if (!combined.any((e) => jsonEncode(e) == jsonEncode(template))) {
          combined.add(template);
        }
      }
    }
    final referenced = ops
        .expand(
          (o) => ['photo', 'cover'].map((key) => (o['fields'] as Map)[key]),
        )
        .toSet();
    final photos = Map<String, dynamic>.from(data['photos'] as Map)
      ..removeWhere(
        (key, value) => projects != null && !referenced.contains(key),
      );
    for (final entry in photos.entries) {
      blob(entry.key);
      final bytes = base64Decode(entry.value as String);
      if (bytes.length > 20 * 1024 * 1024 ||
          sha256.convert(bytes).toString() != entry.key) {
        throw const FormatException('Photo integrity check failed');
      }
    }
    for (final entry in photos.entries) {
      final f = blob(entry.key);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(base64Decode(entry.value as String), flush: true);
    }
    apply(ops);
    if (restoreTemplates) {
      setSetting('templates', jsonEncode(combined));
      touch();
    }
  }

  void touch() => notifyListeners();
  @override
  void dispose() {
    db.close();
    super.dispose();
  }
}
