import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../store.dart';
import 'backup/workbook.dart';

/// Produces a verified workbook and portable restore file from one snapshot.
/// Only complete, intact folders created by this service qualify for retention.
class ExcelBackup extends ChangeNotifier {
  final Store store;
  ExcelBackup(this.store);
  Timer? _timer;
  bool busy = false;
  String get folder => store.setting('excel-folder') ?? '';
  String get time => store.setting('excel-time') ?? '18:00';
  bool get enabled => store.setting('excel-enabled') == 'on';
  String get status => store.setting('excel-error')?.isNotEmpty == true
      ? 'Last attempt failed: ${store.setting('excel-error')}'
      : store.setting('excel-last') == null
      ? 'No Excel backup yet.'
      : 'Last backup: ${DateTime.parse(store.setting('excel-last')!).toLocal().toString().substring(0, 16)}';

  void initialize() {
    checkDue();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => checkDue());
  }

  Future<void> checkDue() async {
    if (!enabled || busy || folder.isEmpty) return;
    final now = DateTime.now();
    final parts = time.split(':').map(int.parse).toList();
    var scheduled = DateTime(now.year, now.month, now.day, parts[0], parts[1]);
    if (now.isBefore(scheduled)) {
      scheduled = DateTime(
        now.year,
        now.month,
        now.day - 1,
        parts[0],
        parts[1],
      );
    }
    final last = DateTime.tryParse(store.setting('excel-last') ?? '');
    final since = DateTime.tryParse(store.setting('excel-since') ?? '') ?? now;
    if ((last ?? since).isBefore(scheduled)) {
      try {
        await run();
      } catch (_) {
        /* Status is persisted for Settings. */
      }
    }
  }

  Future<void> configure(String destination, String at, bool on) async {
    if (destination.trim().isEmpty) {
      throw const FormatException('Choose a backup folder first.');
    }
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(at)) {
      throw const FormatException('Invalid daily time.');
    }
    await Directory(destination).create(recursive: true);
    if (Platform.isWindows) {
      final task = 'The List daily Excel backup';
      if (on) {
        final result = await Process.run('schtasks.exe', [
          '/Create',
          '/F',
          '/SC',
          'DAILY',
          '/TN',
          task,
          '/ST',
          at,
          '/IT',
          '/TR',
          '"${Platform.resolvedExecutable}" --excel-backup',
        ]);
        if (result.exitCode != 0) {
          throw StateError(
            'Windows could not register the daily task: ${result.stderr}',
          );
        }
      } else {
        final exists = await Process.run('schtasks.exe', [
          '/Query',
          '/TN',
          task,
        ]);
        if (exists.exitCode == 0) {
          final result = await Process.run('schtasks.exe', [
            '/Delete',
            '/F',
            '/TN',
            task,
          ]);
          if (result.exitCode != 0) {
            throw StateError('Windows could not disable the daily task.');
          }
        }
      }
    }
    store.setSetting('excel-folder', destination);
    store.setSetting('excel-time', at);
    store.setSetting('excel-enabled', on ? 'on' : 'off');
    store.setSetting('excel-since', DateTime.now().toUtc().toIso8601String());
    notifyListeners();
  }

  Future<String> run() async {
    if (busy) throw StateError('A backup is already running.');
    if (folder.isEmpty) throw StateError('Choose a backup folder first.');
    busy = true;
    notifyListeners();
    RandomAccessFile? lock;
    Directory? staging;
    try {
      await Directory(folder).create(recursive: true);
      lock = await File(
        p.join(store.directory.path, 'excel-backup.lock'),
      ).open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      // One immutable snapshot feeds both files so the workbook and restore data agree.
      final snapshot = await store.exportData();
      final snapshotData = jsonDecode(snapshot) as Map<String, dynamic>;
      final rows = Store.snapshotEntries(snapshotData);
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final name = 'The-List-$stamp';
      staging = Directory(p.join(folder, '.$name.partial'));
      await staging.create();
      await File(
        p.join(staging.path, '$name.thelist'),
      ).writeAsString(snapshot, flush: true);
      await File(
        p.join(staging.path, '$name.xlsx'),
      ).writeAsBytes(workbook(rows, snapshotData), flush: true);
      final hashes = <String, String>{};
      for (final extension in ['thelist', 'xlsx']) {
        final file = File(p.join(staging.path, '$name.$extension'));
        hashes[p.basename(file.path)] = sha256
            .convert(await file.readAsBytes())
            .toString();
      }
      await File(p.join(staging.path, 'manifest.json')).writeAsString(
        jsonEncode({
          'owner': 'the-list-backup-v1',
          'created': DateTime.now().toUtc().toIso8601String(),
          'files': hashes,
        }),
        flush: true,
      );
      await verify(staging.path);
      final completed = p.join(folder, name);
      await staging.rename(completed);
      staging = null;
      store.setSetting('excel-last', DateTime.now().toUtc().toIso8601String());
      store.setSetting('excel-path', completed);
      store.setSetting('excel-error', '');
      await prune();
      return completed;
    } catch (error) {
      store.setSetting('excel-error', error.toString());
      rethrow;
    } finally {
      // Keep partial files for diagnosis; never present them as completed backups.
      await lock?.close();
      busy = false;
      notifyListeners();
    }
  }

  Future<void> verify(String path) async {
    final directory = Directory(path);
    final manifest =
        jsonDecode(await File(p.join(path, 'manifest.json')).readAsString())
            as Map;
    if (manifest['owner'] != 'the-list-backup-v1') {
      throw const FormatException('Unknown backup manifest.');
    }
    final files = Map<String, dynamic>.from(manifest['files'] as Map);
    if (files.length != 2) throw const FormatException('Incomplete backup.');
    for (final entry in files.entries) {
      if (p.basename(entry.key) != entry.key) {
        throw const FormatException('Invalid backup filename.');
      }
      final file = File(p.join(directory.path, entry.key));
      if (sha256.convert(await file.readAsBytes()).toString() != entry.value) {
        throw const FormatException('Backup integrity check failed.');
      }
    }
  }

  Future<void> prune() async {
    final days = int.tryParse(store.setting('excel-retention-days') ?? '') ?? 0;
    // Zero is the default: retain every backup until the user opts into pruning.
    if (days <= 0) return;
    final root = p.normalize(p.absolute(folder));
    final cutoff = DateTime.now().toUtc().subtract(Duration(days: days));
    await for (final entity in Directory(root).list(followLinks: false)) {
      if (entity is! Directory ||
          !p.basename(entity.path).startsWith('The-List-')) {
        continue;
      }
      final candidate = p.normalize(p.absolute(entity.path));
      if (!p.isWithin(root, candidate) ||
          candidate == store.setting('excel-path')) {
        continue;
      }
      final marker = File(p.join(candidate, 'manifest.json'));
      if (!await marker.exists()) continue;
      try {
        final manifest = jsonDecode(await marker.readAsString()) as Map;
        final created = DateTime.tryParse(
          manifest['created']?.toString() ?? '',
        );
        if (manifest['owner'] != 'the-list-backup-v1' ||
            created == null ||
            !created.isBefore(cutoff)) {
          continue;
        }
        // Preserve folders with added files, altered backups, or symbolic links.
        final expected = {...(manifest['files'] as Map).keys, 'manifest.json'};
        final contents = await entity.list(followLinks: false).toList();
        if (contents.length != expected.length ||
            contents.any(
              (f) => f is! File || !expected.contains(p.basename(f.path)),
            )) {
          continue;
        }
        await verify(candidate);
        for (final file in contents) {
          await file.delete();
        }
        await entity.delete();
      } catch (_) {
        /* Preserve unrecognized or damaged folders for recovery. */
      }
    }
  }

  static List<int> workbook(List<Entry> entries, Json snapshot) =>
      buildWorkbook(entries, snapshot);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
