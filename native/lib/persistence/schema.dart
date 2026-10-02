import 'package:sqlite3/sqlite3.dart';

/// Initializes version 1 without changing existing entity or operation layouts.
void initializeSchema(Database db) {
  final version = db.select('PRAGMA user_version').first['user_version'] as int;
  if (version > 1) {
    throw const FormatException(
      'This workspace requires a newer version of The List.',
    );
  }
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
    'CREATE INDEX IF NOT EXISTS entities_project ON entities(project)',
  );
  db.execute('CREATE INDEX IF NOT EXISTS entities_kind ON entities(kind)');
  db.execute(
    'CREATE TABLE IF NOT EXISTS project_access (room TEXT PRIMARY KEY, project TEXT NOT NULL, host INTEGER NOT NULL, access TEXT NOT NULL)',
  );
  db.execute(
    'CREATE TABLE IF NOT EXISTS activity_feed (op TEXT PRIMARY KEY, received TEXT NOT NULL, seen INTEGER NOT NULL DEFAULT 0)',
  );
  db.execute('PRAGMA user_version=1');
}
