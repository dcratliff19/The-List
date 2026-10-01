import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../store.dart';

/// Installs user-session timers; the Python helper rechecks live database state
/// before delivery because a reminder may change while the app is closed.
class LinuxScheduler {
  final Store store;
  bool available = false;
  LinuxScheduler(this.store);
  Future<void> initialize() async {
    if (!Platform.isLinux) return;
    try {
      final check = await Process.run('systemctl', [
        '--user',
        'show-environment',
      ]);
      final python = await Process.run('python3', ['--version']);
      final notify = await Process.run('notify-send', ['--version']);
      available =
          check.exitCode == 0 && python.exitCode == 0 && notify.exitCode == 0;
      if (available) {
        await File(
          p.join(store.directory.path, 'linux_reminder.py'),
        ).writeAsString(
          await rootBundle.loadString('assets/linux_reminder.py'),
          flush: true,
        );
      }
    } catch (_) {
      available = false;
    }
  }

  String get unitsPath => p.join(
    Platform.environment['XDG_CONFIG_HOME'] ??
        p.join(Platform.environment['HOME']!, '.config'),
    'systemd',
    'user',
  );
  String unit(Entry e) =>
      'the-list-reminder-${e.id.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '')}';
  String quote(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('%', '%%').replaceAll(r'$', r'$$').replaceAll('\n', ' ').replaceAll('\r', ' ')}"';
  Future<void> schedule(Entry e) async {
    final id = unit(e);
    final due = DateTime.parse(e.text('due')).toUtc();
    final calendar =
        '${due.toIso8601String().substring(0, 19).replaceAll('T', ' ')} UTC';
    final dir = Directory(unitsPath);
    await dir.create(recursive: true);
    final args = [
      '/usr/bin/python3',
      p.join(store.directory.path, 'linux_reminder.py'),
      '--database',
      p.join(store.directory.path, 'the-list.sqlite'),
      '--id',
      e.id,
      '--executable',
      Platform.resolvedExecutable,
    ].map(quote).join(' ');
    await File(p.join(unitsPath, '$id.service')).writeAsString(
      '[Unit]\nDescription=The List reminder\n[Service]\nType=oneshot\nExecStart=$args\n',
    );
    await File(p.join(unitsPath, '$id.timer')).writeAsString(
      '[Unit]\nDescription=The List scheduled reminder\n[Timer]\nOnCalendar=$calendar\nPersistent=true\nAccuracySec=1s\nUnit=$id.service\n[Install]\nWantedBy=timers.target\n',
    );
    final reload = await Process.run('systemctl', ['--user', 'daemon-reload']);
    if (reload.exitCode != 0) {
      throw StateError('Could not reload reminder timers');
    }
    final enabled = await Process.run('systemctl', [
      '--user',
      'enable',
      '--now',
      '$id.timer',
    ]);
    if (enabled.exitCode != 0) {
      throw StateError('Could not enable reminder timer');
    }
    await Process.run('systemctl', ['--user', 'restart', '$id.timer']);
  }

  Future<void> cancel(Entry e) async {
    final id = unit(e);
    await Process.run('systemctl', ['--user', 'disable', '--now', '$id.timer']);
    for (final suffix in ['timer', 'service']) {
      final file = File(p.join(unitsPath, '$id.$suffix'));
      if (await file.exists()) await file.delete();
    }
    await Process.run('systemctl', ['--user', 'daemon-reload']);
  }
}
