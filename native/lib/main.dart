import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'store.dart';
import 'services/excel_backup.dart';
import 'ui/workspace.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final override = Platform.environment['THE_LIST_DATA_DIR'];
  final directory = override != null
      ? Directory(override)
      : await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  try {
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

class TheListApp extends StatefulWidget {
  final Store store;
  final bool servicesEnabled;
  final String? initialTarget;
  const TheListApp({
    super.key,
    required this.store,
    this.servicesEnabled = true,
    this.initialTarget,
  });
  @override
  State<TheListApp> createState() => _TheListAppState();
}

class _TheListAppState extends State<TheListApp> {
  @override
  Widget build(BuildContext context) {
    final dark = widget.store.setting('theme') == 'dark';
    final savedAccent = widget.store.setting('accent') ?? '5848D9';
    final seed = Color(
      0xff000000 | (int.tryParse(savedAccent, radix: 16) ?? 0x5848D9),
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(surface: dark ? const Color(0xff212229) : Colors.white);
    return MaterialApp(
      title: 'The List',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: dark
            ? const Color(0xff191a20)
            : const Color(0xfffafaf8),
        fontFamily: Platform.isWindows ? 'Segoe UI' : null,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
      ),
      home: Workspace(
        store: widget.store,
        servicesEnabled: widget.servicesEnabled,
        initialTarget: widget.initialTarget,
        onTheme: () => setState(() {}),
      ),
    );
  }
}
