import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'store.dart';
import 'services/excel_backup.dart';
import 'app/app.dart';

export 'app/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final override = Platform.environment['THE_LIST_DATA_DIR'];
    final directory = override != null
        ? Directory(override)
        : await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final store = Store(directory);
    if (args.contains('--excel-backup')) {
      final backup = ExcelBackup(store);
      try {
        if (backup.enabled) await backup.run();
      } finally {
        backup.dispose();
        store.dispose();
      }
      exit(0);
    }
    runApp(
      TheListApp(
        store: store,
        initialTarget: args.length == 2 && args.first == '--open-target'
            ? args[1]
            : null,
      ),
    );
  } catch (error) {
    if (args.contains('--excel-backup')) exit(1);
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableText(
              'The List could not open its local database.\nYour files have not been removed.\n\n$error',
            ),
          ),
        ),
      ),
    );
  }
}
