part of '../workspace.dart';

extension _WorkspaceEditorsProjects on _WorkspaceState {
  Future<void> editProject([Entry? existing]) async {
    if (existing != null && !allowEdit(existing.project)) return;
    final title = TextEditingController(text: existing?.title),
        description = TextEditingController(
          text: existing?.text('description'),
        ),
        label = TextEditingController(text: existing?.text('label'));
    var color = int.tryParse(existing?.text('color') ?? '') ?? 0xffad9dcf;
    String? error;
    await showEditorDialog<void>(
      context: context,
      controllers: [title, description, label],
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            existing == null ? 'A home for your next idea' : 'Edit project',
          ),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Give your collection a name. The rest can come later.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: title,
                    autofocus: true,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: 'Project name',
                      hintText: 'A space of our own',
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'What is this project about?',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: label,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Category (optional)',
                      hintText: 'Home & living',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children:
                        [
                              0xffad9dcf,
                              0xff92af9c,
                              0xffcfab83,
                              0xff839dc1,
                              0xffc68b9a,
                            ]
                            .map(
                              (c) => InkWell(
                                onTap: () => update(() => color = c),
                                borderRadius: BorderRadius.circular(20),
                                child: CircleAvatar(
                                  radius: 17,
                                  backgroundColor: Color(c),
                                  child: color == c
                                      ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 17,
                                        )
                                      : null,
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty) {
                  update(() => error = 'Give your project a name.');
                  return;
                }
                try {
                  final data = {
                    'title': title.text.trim(),
                    'description': description.text.trim(),
                    'label': label.text.trim(),
                    'color': color,
                  };
                  if (existing != null) {
                    store.update(existing, data);
                  } else {
                    openProject(store.create('project', '', data));
                  }
                  Navigator.pop(context);
                } catch (e) {
                  update(() => error = 'Could not save. $e');
                }
              },
              child: Text(existing == null ? 'Create project' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> choosePhoto() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (picked == null) return null;
    final f = picked.files.single;
    return media.importPhoto(f.bytes ?? await File(f.path!).readAsBytes());
  }

  Future<void> pickCover() async => act(() async {
    if (!allowEdit(projectId!)) return;
    final p = project!;
    final photo = await choosePhoto();
    if (photo != null) store.update(p, {'cover': photo});
  });
}
