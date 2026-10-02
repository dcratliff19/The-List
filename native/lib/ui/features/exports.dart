part of '../workspace.dart';

extension _WorkspaceFeaturesExports on _WorkspaceState {
  Future<void> restorePreview() async {
    final chosen = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['thelist'],
    );
    final path = chosen?.files.single.path;
    if (path == null) return;
    final file = File(path);
    final preview = await store.previewBackup(file);
    if (!mounted) return;
    final selected = <String>{};
    var includeTemplates = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Review backup before restoring'),
          content: SizedBox(
            width: 500,
            height: 350,
            child: ListView(
              children: [
                const Text(
                  'Choose projects to merge. Current projects are preserved; newer field versions win.',
                ),
                CheckboxListTile(
                  title: const Text('Also merge saved project templates'),
                  value: includeTemplates,
                  onChanged: (v) => update(() => includeTemplates = v ?? false),
                ),
                for (final e in preview['projects'])
                  CheckboxListTile(
                    title: Text(e['fields']['title'] ?? 'Project'),
                    subtitle: Text('${preview['counts'][e['id']]} items'),
                    value: selected.contains(e['id']),
                    onChanged: (v) => update(() {
                      if (v == true) {
                        selected.add(e['id']);
                      } else {
                        selected.remove(e['id']);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => act(() async {
                      await store.importFrom(
                        file,
                        projects: selected,
                        restoreTemplates: includeTemplates,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      message('Selected projects restored.');
                    }),
              child: const Text('Restore selected'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> exportProject() async {
    final pid = projectId;
    if (pid == null) return;
    final choice = await featureForm(
      'Export project',
      {'Format': 'Excel'},
      choices: {
        'Format': ['Excel', 'Portable backup', 'PDF'],
      },
    );
    if (choice == null) return;
    final snapshot =
        jsonDecode(await store.exportData(projects: {pid})) as Json;
    // Peer edits may arrive during export. Every output uses the same frozen
    // revisions as the portable file instead of reading the live store again.
    final entries = Store.snapshotEntries(snapshot);
    final format = choice['Format'];
    List<int> bytes;
    String extension;
    if (format == 'Excel') {
      bytes = ExcelBackup.workbook(entries, snapshot);
      extension = 'xlsx';
    } else if (format == 'PDF') {
      bytes = await projectPdf(
        entries.firstWhere((entry) => entry.id == pid),
        entries
            .where((entry) => entry.kind != 'project' && !entry.deleted)
            .toList(),
      );
      extension = 'pdf';
    } else {
      bytes = utf8.encode(jsonEncode(snapshot));
      extension = 'thelist';
    }
    final output = await FilePicker.platform.saveFile(
      dialogTitle: 'Export project',
      fileName: 'the-list-project.$extension',
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: Uint8List.fromList(bytes),
    );
    if (output != null && !Platform.isAndroid && !Platform.isIOS) {
      await File(output).writeAsBytes(bytes, flush: true);
    }
    if (output != null) message('Project exported.');
  }
}
