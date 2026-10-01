import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:the_list/store.dart';
import 'package:the_list/services/media.dart';

void main() {
  late Directory dir;
  late Store a, b;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('the-list-test-');
    a = Store(dir, database: sqlite3.openInMemory());
    b = Store(dir, database: sqlite3.openInMemory());
  });
  tearDown(() async {
    a.dispose();
    b.dispose();
    await dir.delete(recursive: true);
  });
  test('concurrent fields converge regardless of arrival order', () {
    final project = a.create('project', '', {'title': 'Research'});
    final id = a.create('note', project, {
      'title': 'Start',
      'body': 'Original',
    });
    b.apply(a.operations(project));
    a.update(a.get(id)!, {'body': 'Alice revision'});
    b.update(b.get(id)!, {'title': 'Bob title'});
    final ops = [...a.operations(project), ...b.operations(project)];
    ops.shuffle(Random(5));
    a.apply(ops);
    b.apply(ops.reversed.toList());
    expect(a.get(id)!.fields, b.get(id)!.fields);
    expect(a.get(id)!.text('body'), 'Alice revision');
    expect(a.get(id)!.title, 'Bob title');
  });
  test('concurrent prose retained and duplicate replay idempotent', () {
    final pid = a.create('project', '', {'title': 'P'}),
        id = a.create('note', a.projects.first.id, {'body': 'Original'});
    b.apply(a.operations(pid));
    a.update(a.get(id)!, {'body': 'A'});
    b.update(b.get(id)!, {'body': 'B'});
    final ops = [...a.operations(pid), ...b.operations(pid)];
    a.apply(ops);
    b.apply(ops.reversed.toList());
    a.apply(ops);
    expect(a.get(id)!.text('body'), b.get(id)!.text('body'));
    expect(a.history(id).length, 3);
  });
  test('tombstones survive old-device replay and can be restored', () {
    final pid = a.create('project', '', {'title': 'P'});
    final old = a.operations(pid);
    a.update(a.get(pid)!, {'deleted': true});
    a.apply(old);
    expect(a.projects, isEmpty);
    a.update(a.get(pid)!, {'deleted': false});
    expect(a.projects.length, 1);
  });
  test('scope violations roll back the batch', () {
    final pid = a.create('project', '', {'title': 'P'});
    expect(
      () => b.apply(a.operations(pid), scope: 'other'),
      throwsFormatException,
    );
    expect(b.entries, isEmpty);
  });
  test('database restart retains projects and device identity', () {
    final disk = Store(dir);
    final id = disk.create('project', '', {'title': 'Persistent'});
    final device = disk.device;
    disk.dispose();
    final reopened = Store(dir);
    expect(reopened.get(id)!.title, 'Persistent');
    expect(reopened.device, device);
    reopened.dispose();
  });
  test(
    'backup restores and rejects corrupted attachments before applying',
    () async {
      final pid = a.create('project', '', {'title': 'Backup'});
      final file = File('${dir.path}/backup.thelist');
      await a.exportTo(file);
      await b.importFrom(file);
      expect(b.get(pid)!.title, 'Backup');
      final data = jsonDecode(await file.readAsString()) as Map;
      data['photos'] = {
        'a' * 64: base64Encode([1, 2, 3]),
      };
      await file.writeAsString(jsonEncode(data));
      expect(() => b.importFrom(file), throwsFormatException);
    },
  );
  test('private network preview addresses are rejected', () {
    for (final ip in [
      '127.0.0.1',
      '10.1.2.3',
      '192.168.1.1',
      '172.16.0.1',
      '169.254.1.1',
      '100.64.0.1',
      '::1',
      'fe80::1',
      '::ffff:127.0.0.1',
    ]) {
      expect(
        MediaService.publicAddress(InternetAddress(ip)),
        isFalse,
        reason: ip,
      );
    }
    expect(MediaService.publicAddress(InternetAddress('8.8.8.8')), isTrue);
    expect(
      () => MediaService.webUri('file:///etc/passwd'),
      throwsFormatException,
    );
  });

  test(
    'portable backups retain photos referenced by earlier revisions',
    () async {
      final pid = a.create('project', '', {'title': 'Photo history'});
      final oldBytes = utf8.encode('earlier photo');
      final newBytes = utf8.encode('current photo');
      final oldHash = sha256.convert(oldBytes).toString();
      final newHash = sha256.convert(newBytes).toString();
      a.blob(oldHash).parent.createSync(recursive: true);
      a.blob(oldHash).writeAsBytesSync(oldBytes);
      a.blob(newHash).writeAsBytesSync(newBytes);
      final id = a.create('photo', pid, {'photo': oldHash});
      a.update(a.get(id)!, {'photo': newHash});
      final backup = File('${dir.path}/photo-history.thelist');
      await a.exportTo(backup);
      final data = jsonDecode(await backup.readAsString()) as Map;
      expect((data['photos'] as Map).keys, containsAll([oldHash, newHash]));
      final restoredDir = Directory('${dir.path}/restored')..createSync();
      final restored = Store(restoredDir);
      try {
        await restored.importFrom(backup);
        expect(await restored.blob(oldHash).readAsBytes(), oldBytes);
        expect(await restored.blob(newHash).readAsBytes(), newBytes);
        restored.update(restored.get(id)!, {'photo': oldHash});
        expect(
          restored.blob(restored.get(id)!.text('photo')).existsSync(),
          isTrue,
        );
      } finally {
        restored.dispose();
      }
    },
  );
}
