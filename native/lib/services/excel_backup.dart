import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../store.dart';

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

  static List<int> workbook(
    List<Entry> entries,
    Map<String, dynamic> snapshot,
  ) {
    final sheets = <String, List<List<String>>>{};
    final projects = {
      for (final e in entries.where((e) => e.kind == 'project')) e.id: e.title,
    };
    sheets['Summary'] = [
      ['The List — workspace backup', DateTime.now().toUtc().toIso8601String()],
      [
        'Restore',
        'Import the accompanying .thelist file to recover full data and original photos.',
      ],
      ['Prices', 'Totals exclude deleted links and are separated by currency.'],
      [
        'Photo data',
        'Original photo bytes are preserved in the accompanying .thelist file.',
      ],
      ['Project', 'Currency', 'Total'],
      for (final project in projects.entries)
        for (final currency in Entry.currencies)
          if (entries.any(
            (e) =>
                e.project == project.key &&
                e.kind == 'link' &&
                !e.deleted &&
                e.priceMinor != null &&
                e.currency == currency,
          ))
            [
              project.value,
              currency,
              Entry.amount(
                entries
                    .where(
                      (e) =>
                          e.project == project.key &&
                          e.kind == 'link' &&
                          !e.deleted &&
                          e.currency == currency,
                    )
                    .fold<int>(
                      0,
                      (sum, e) => sum + (e.priceMinor ?? 0) * e.quantity,
                    ),
              ),
            ],
    ];
    const fields = [
      'title',
      'url',
      'body',
      'description',
      'tags',
      'price',
      'currency',
      'boardStatus',
      'due',
      'zone',
      'target',
      'done',
      'favorite',
      'archived',
      'deleted',
      'created',
      'photo',
      'cover',
      'previewTitle',
      'previewDescription',
      'previewStatus',
      'previewError',
      'label',
      'color',
      'quantity',
      'purchaseStatus',
      'comparison',
      'budget',
      'budgetCurrency',
      'columns',
      'rank',
      'assignee',
      'repeat',
      'repeatDay',
      'lastCompleted',
      'author',
      'modified',
      'inbox',
    ];
    for (final kind in {
      'project': 'Projects',
      'link': 'Links',
      'note': 'Notes',
      'photo': 'Photos',
      'reminder': 'Reminders',
      'check': 'Checklists',
      'comment': 'Comments',
    }.entries) {
      sheets[kind.value] = [
        ['ID', 'Project ID', 'Project', ...fields],
        for (final entry in entries.where((e) => e.kind == kind.key))
          [
            entry.id,
            entry.project,
            projects[entry.project] ?? '',
            ...fields.map(entry.text),
          ],
      ];
    }
    // Chunking avoids Excel's 32,767-character cell limit without dropping history.
    sheets['Raw data'] = [
      ['Section', 'Record', 'Part', 'JSON (join parts in order)'],
    ];
    for (final section in snapshot.entries.where((e) => e.key != 'photos')) {
      final records = section.value is List
          ? section.value as List
          : [section.value];
      for (var index = 0; index < records.length; index++) {
        final raw = jsonEncode(records[index]);
        for (var offset = 0; offset < raw.length; offset += 16000) {
          sheets['Raw data']!.add([
            section.key,
            '$index',
            '${offset ~/ 16000}',
            raw.substring(offset, (offset + 16000).clamp(0, raw.length)),
          ]);
        }
      }
    }
    final archive = Archive();
    void add(String name, String xml) {
      final bytes = utf8.encode(xml);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    String escape(String value) => value
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
    String column(int index) {
      var result = '';
      for (var n = index + 1; n > 0; n = (n - 1) ~/ 26) {
        result = String.fromCharCode(65 + (n - 1) % 26) + result;
      }
      return result;
    }

    add(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${List.generate(sheets.length, (i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}</Types>',
    );
    add(
      '_rels/.rels',
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    );
    add(
      'xl/workbook.xml',
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sheets.keys.toList().asMap().entries.map((e) => '<sheet name="${escape(e.value)}" sheetId="${e.key + 1}" r:id="rId${e.key + 1}"/>').join()}</sheets></workbook>',
    );
    add(
      'xl/_rels/workbook.xml.rels',
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${List.generate(sheets.length, (i) => '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join()}</Relationships>',
    );
    var number = 0;
    for (final rows in sheets.values) {
      number++;
      final xml = StringBuffer(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="18"/><cols><col min="1" max="30" width="25" customWidth="1"/></cols><sheetData>',
      );
      for (var row = 0; row < rows.length; row++) {
        xml.write('<row r="${row + 1}">');
        for (var col = 0; col < rows[row].length; col++) {
          final value = rows[row][col];
          final numeric =
              (number == 1 && row >= 5 && col == 2) ||
              (number == 3 && row > 0 && col == 8);
          if (numeric && value.isNotEmpty) {
            xml.write(
              '<c r="${column(col)}${row + 1}"><v>${escape(value)}</v></c>',
            );
            continue;
          }
          xml.write(
            '<c r="${column(col)}${row + 1}" t="inlineStr"><is><t xml:space="preserve">${escape(value.length > 32000 ? '${value.substring(0, 31900)} [full value in Raw data]' : value)}</t></is></c>',
          );
        }
        xml.write('</row>');
      }
      xml.write(
        '</sheetData><autoFilter ref="A1:${column(rows.first.length - 1)}${rows.length}"/></worksheet>',
      );
      add('xl/worksheets/sheet$number.xml', xml.toString());
    }
    return ZipEncoder().encode(archive);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
