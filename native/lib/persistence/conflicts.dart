part of '../store.dart';

/// Conflict review stays behind the storage boundary; UI never mutates SQL rows.
extension ConflictReview on Store {
  List<Json> unresolvedConflicts(String project) => db
      .select(
        'SELECT conflicts.* FROM conflicts JOIN entities ON entities.id=conflicts.entity WHERE entities.project=? AND resolved=0',
        [project],
      )
      .map((row) => Map<String, dynamic>.from(row))
      .toList();

  void resolveConflict(String id, {bool useAlternative = false}) {
    final rows = db.select(
      'SELECT * FROM conflicts WHERE id=? AND resolved=0',
      [id],
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final entry = get(row['entity'] as String);
    if (useAlternative && entry != null) {
      update(entry, {
        row['field'] as String: jsonDecode(row['value'] as String),
      });
    }
    db.execute('UPDATE conflicts SET resolved=1 WHERE id=?', [id]);
    touch();
  }
}
