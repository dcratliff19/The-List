part of 'store.dart';

/// Keeps device-local access decisions and read receipts out of shared history.
extension SharedActivity on Store {
  bool canManageSharing(String project) => db.select(
    'SELECT room FROM project_access WHERE project=? AND host=0',
    [project],
  ).isEmpty;
  bool canEdit(String project) {
    final rows = db.select(
      'SELECT access FROM project_access WHERE project=? AND host=0',
      [project],
    );
    return rows.isEmpty || rows.any((r) => r['access'] == 'update');
  }

  void requireEdit(String project) {
    if (!canEdit(project)) {
      throw StateError(
        'This project is read-only. Ask its owner for update access.',
      );
    }
  }

  void setProjectAccess(String project, String room, bool host, String access) {
    if (!['read', 'update'].contains(access)) {
      throw const FormatException('Invalid sharing access');
    }
    final previous = db.select('SELECT * FROM project_access WHERE room=?', [
      room,
    ]);
    if (previous.isNotEmpty &&
        previous.first['access'] == access &&
        previous.first['host'] == (host ? 1 : 0)) {
      return;
    }
    db.execute('INSERT OR REPLACE INTO project_access VALUES (?,?,?,?)', [
      room,
      project,
      host ? 1 : 0,
      access,
    ]);
    touch();
  }

  void recordActivity(Json op, {required bool received}) {
    if (op['kind'] == 'reminder') return;
    if (!received || op['device'] == device) return;
    final fields = op['fields'] as Map;
    final changes = fields.keys
        .where(
          (k) => ![
            'author',
            'modified',
            'base',
            'previewTitle',
            'previewDescription',
            'previewImage',
            'previewStatus',
            'previewError',
            'previewFetched',
            'previewSite',
            'previewUrl',
            'favicon',
          ].contains(k),
        )
        .toList();
    if (changes.isEmpty ||
        (changes.length == 1 &&
            changes.single == 'photo' &&
            fields.containsKey('previewStatus'))) {
      return;
    }
    db.execute(
      'INSERT OR IGNORE INTO activity_feed (op,received) VALUES (?,?)',
      [op['id'], DateTime.now().toUtc().toIso8601String()],
    );
  }

  List<Json> get sharedActivity => db
      .select(
        'SELECT o.*, a.received, a.seen FROM activity_feed a JOIN operations o ON o.id=a.op ORDER BY a.received DESC,o.counter DESC,o.device DESC,o.id DESC LIMIT 500',
      )
      .map((r) => {...r, 'fields': jsonDecode(r['fields'] as String)})
      .toList();
  int get unreadActivity =>
      db
              .select('SELECT COUNT(*) AS n FROM activity_feed WHERE seen=0')
              .first['n']
          as int;
  void markActivityRead([String? id]) {
    db.execute(
      id == null
          ? 'UPDATE activity_feed SET seen=1'
          : 'UPDATE activity_feed SET seen=1 WHERE op=?',
      id == null ? [] : [id],
    );
    touch();
  }

  String activitySummary(Json op) {
    final f = op['fields'] as Map;
    final kind = op['kind'] == 'check' ? 'checklist item' : op['kind'];
    if (f['deleted'] == true) return 'Removed a $kind';
    if (f['deleted'] == false) return 'Restored a $kind';
    if (kind == 'comment') return 'Commented';
    if (f.containsKey('created')) return 'Added a $kind';
    if (f.containsKey('boardStatus')) return 'Moved a card';
    if (f.containsKey('done')) {
      return f['done'] == true ? 'Completed a $kind' : 'Reopened a $kind';
    }
    if (f.containsKey('price') || f.containsKey('quantity')) {
      return 'Updated pricing';
    }
    return 'Updated a $kind';
  }
}
