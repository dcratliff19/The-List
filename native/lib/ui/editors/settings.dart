part of '../workspace.dart';

extension _WorkspaceEditorsSettings on _WorkspaceState {
  Future<void> settings() async => showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Your workspace, your way.'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dark appearance'),
                  value: store.setting('theme') == 'dark',
                  onChanged: (v) {
                    store.setSetting('theme', v ? 'dark' : 'light');
                    widget.onTheme();
                    update(() {});
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Accent color'),
                  subtitle: const Text(
                    'Choose a preset or your own hex color.',
                  ),
                  trailing: CircleAvatar(backgroundColor: accent, radius: 14),
                  onTap: () async {
                    await chooseAccent();
                    update(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Automatic link previews'),
                  subtitle: const Text(
                    'Fetch page metadata directly from websites.',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: store.setting('previews') != 'off',
                  onChanged: (v) {
                    store.setSetting('previews', v ? 'on' : 'off');
                    if (v) media.repairMissing();
                    update(() {});
                  },
                ),
                ListenableBuilder(
                  listenable: reminders,
                  builder: (context, _) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Native notifications'),
                    subtitle: Text(
                      reminders.status,
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: TextButton(
                      onPressed: () => act(() async {
                        if (store.setting('notifications') == 'on') {
                          await reminders.disable();
                        } else {
                          await reminders.enable();
                        }
                      }),
                      child: Text(
                        store.setting('notifications') == 'on'
                            ? 'Disable'
                            : 'Enable',
                      ),
                    ),
                  ),
                ),
                const Divider(),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('Manage tags'),
                  leading: const Icon(Icons.label_outline),
                  onTap: () => act(tagManager),
                ),
                ListTile(
                  title: const Text('Project templates'),
                  leading: const Icon(Icons.copy_all),
                  onTap: () => act(templatesDialog),
                ),
                if (Platform.isWindows)
                  ListTile(
                    leading: const Icon(Icons.share_outlined),
                    title: const Text('Enable browser capture'),
                    subtitle: const Text(
                      'Register this app to receive links from the browser extension.',
                    ),
                    onTap: () => act(() async {
                      const key = r'HKCU\Software\Classes\thelist-capture';
                      for (final args in [
                        [
                          'add',
                          key,
                          '/v',
                          'URL Protocol',
                          '/t',
                          'REG_SZ',
                          '/d',
                          '',
                          '/f',
                        ],
                        [
                          'add',
                          '$key\\shell\\open\\command',
                          '/ve',
                          '/t',
                          'REG_SZ',
                          '/d',
                          '"${Platform.resolvedExecutable}" "%1"',
                          '/f',
                        ],
                      ]) {
                        final result = await Process.run('reg.exe', args);
                        if (result.exitCode != 0) {
                          throw StateError(
                            'Could not register browser capture: ${result.stderr}',
                          );
                        }
                      }
                      message('Browser capture enabled for this app location.');
                    }),
                  ),
                ListTile(
                  title: const Text('Your display name'),
                  subtitle: Text(
                    store.setting('display-name') ?? 'This device',
                  ),
                  onTap: () => act(() async {
                    final v = await featureForm('Your display name', {
                      'Name': store.setting('display-name') ?? 'This device',
                    });
                    if (v != null && v['Name']!.trim().isNotEmpty) {
                      store.setSetting('display-name', v['Name']!.trim());
                      update(() {});
                    }
                  }),
                ),
                const Text(
                  'BACKUP & RECOVERY',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                ListenableBuilder(
                  listenable: excelBackup,
                  builder: (context, _) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.table_chart_outlined),
                    title: const Text('Daily Excel backup'),
                    subtitle: Text(
                      excelBackup.status,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: excelBackupSettings,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Export workspace'),
                  subtitle: const Text(
                    'All projects and photos in a portable backup.',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => act(() async {
                    final bytes = Uint8List.fromList(
                      utf8.encode(await store.exportData()),
                    );
                    final output = await FilePicker.platform.saveFile(
                      dialogTitle: 'Export The List',
                      fileName: 'the-list-backup.thelist',
                      type: FileType.custom,
                      allowedExtensions: ['thelist'],
                      bytes: bytes,
                    );
                    if (output != null) {
                      if (!Platform.isAndroid && !Platform.isIOS) {
                        await File(output).writeAsBytes(bytes, flush: true);
                      }
                      message('Backup saved. Keep it somewhere safe.');
                    }
                  }),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('Import backup'),
                  subtitle: const Text(
                    'Merge without replacing your current work.',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => act(restorePreview),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restore_from_trash_outlined),
                  title: const Text('Restore deleted items'),
                  onTap: trash,
                ),
                const Divider(),
                ExpansionTile(
                  title: const Text(
                    'Connection settings',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Configured once for this installation',
                    style: TextStyle(fontSize: 11),
                  ),
                  children: [
                    ListTile(
                      title: Text(
                        SharingConfig.endpoint(store).isEmpty
                            ? 'No connection service configured'
                            : SharingConfig.endpoint(store),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: TextButton(
                        onPressed: connectionSettings,
                        child: const Text('Configure'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  'Stored on this device:\n${store.directory.path}',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
                const SizedBox(height: 12),
                const Text('The List · 1.2.1', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
  Future<void> trash() async => showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => AlertDialog(
        title: const Text('Recently removed'),
        content: SizedBox(
          width: 450,
          child: ListView(
            shrinkWrap: true,
            children: store.entries
                .where((e) => e.deleted)
                .map(
                  (e) => ListTile(
                    title: Text(e.title),
                    trailing: TextButton(
                      onPressed: () => store.update(e, {'deleted': false}),
                      child: const Text('Restore'),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}
