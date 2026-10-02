part of '../workspace.dart';

extension _WorkspaceEditorsBackups on _WorkspaceState {
  Future<void> excelBackupSettings() async {
    var destination = excelBackup.folder;
    var daily = excelBackup.enabled;
    var at = excelBackup.time;
    var retention = store.setting('excel-retention-days') ?? '0';
    var working = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Daily Excel backup'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tabbed Excel workbook plus a restorable backup containing your original photos. Each run creates a new dated folder; previous backups are kept.',
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Automatic daily backup'),
                    value: daily,
                    onChanged: working ? null : (v) => update(() => daily = v),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Save location'),
                    subtitle: Text(
                      destination.isEmpty ? 'Choose a folder' : destination,
                    ),
                    trailing: const Icon(Icons.folder_open),
                    onTap: working
                        ? null
                        : () async {
                            final selected = await FilePicker.platform
                                .getDirectoryPath(
                                  dialogTitle: 'Choose backup folder',
                                );
                            if (selected != null && context.mounted) {
                              update(() => destination = selected);
                            }
                          },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Daily time (local time)'),
                    subtitle: Text(at),
                    trailing: const Icon(Icons.schedule),
                    onTap: working
                        ? null
                        : () async {
                            final parts = at.split(':').map(int.parse).toList();
                            final selected = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(
                                hour: parts[0],
                                minute: parts[1],
                              ),
                            );
                            if (selected != null && context.mounted) {
                              update(
                                () => at =
                                    '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
                              );
                            }
                          },
                  ),
                  Text(
                    Platform.isWindows
                        ? 'Windows can run backups with the app closed while you are signed in. Missed runs catch up when the app is next opened. Keep this app in its current location.'
                        : 'Automatic backups run while the app is open, with catch-up when you reopen it. Your system may suspend background apps.',
                  ),
                  const SizedBox(height: 12),
                  Text(excelBackup.status),
                  DropdownButtonFormField<String>(
                    initialValue: retention,
                    decoration: const InputDecoration(
                      labelText: 'Keep backups',
                    ),
                    items: const [
                      DropdownMenuItem(value: '0', child: Text('Forever')),
                      DropdownMenuItem(value: '30', child: Text('30 days')),
                      DropdownMenuItem(value: '90', child: Text('90 days')),
                      DropdownMenuItem(value: '365', child: Text('1 year')),
                    ],
                    onChanged: working
                        ? null
                        : (v) => update(() => retention = v!),
                  ),
                  TextButton.icon(
                    onPressed: () => act(() async {
                      final path = store.setting('excel-path');
                      if (path == null) {
                        throw StateError('Create a backup first.');
                      }
                      await excelBackup.verify(path);
                      message(
                        'Latest backup verified: both files match their saved hashes.',
                      );
                    }),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Verify latest backup'),
                  ),
                  const Text(
                    'Portable backups support up to 100 MB of photos. Only verified backup folders created by The List are eligible for your retention policy. The latest backup is always kept.',
                    style: TextStyle(fontSize: 11),
                  ),
                  if (working) const LinearProgressIndicator(),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: working ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: working
                  ? null
                  : () async {
                      update(() {
                        working = true;
                        error = null;
                      });
                      try {
                        await excelBackup.configure(destination, at, daily);
                        store.setSetting('excel-retention-days', retention);
                        final path = await excelBackup.run();
                        if (context.mounted) {
                          update(() => working = false);
                          message('Backup saved: $path');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          update(() {
                            working = false;
                            error = e.toString();
                          });
                        }
                      }
                    },
              child: const Text('Save & back up now'),
            ),
            FilledButton(
              onPressed: working
                  ? null
                  : () async {
                      update(() {
                        working = true;
                        error = null;
                      });
                      try {
                        await excelBackup.configure(destination, at, daily);
                        store.setSetting('excel-retention-days', retention);
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          update(() {
                            working = false;
                            error = e.toString();
                          });
                        }
                      }
                    },
              child: const Text('Save settings'),
            ),
          ],
        ),
      ),
    );
  }
}
