part of 'workspace.dart';

extension _WorkspaceActions on _WorkspaceState {
  Future<void> editProject([Entry? existing]) async {
    if (existing != null && !allowEdit(existing.project)) return;
    final title = TextEditingController(text: existing?.title),
        description = TextEditingController(
          text: existing?.text('description'),
        ),
        label = TextEditingController(text: existing?.text('label'));
    var color = int.tryParse(existing?.text('color') ?? '') ?? 0xffad9dcf;
    String? error;
    await _showEditorDialog<void>(
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
  Future<void> editItem([Entry? existing, bool addToBoard = false]) async {
    if (projectId == null && existing == null) {
      message('Open a project first.');
      return;
    }
    if (!allowEdit(existing?.project ?? projectId!)) return;
    final title = TextEditingController(text: existing?.title),
        body = TextEditingController(text: existing?.text('body')),
        url = TextEditingController(text: existing?.text('url')),
        tags = TextEditingController(text: existing?.text('tags')),
        price = TextEditingController(text: existing?.text('price'));
    var currency = existing?.currency ?? 'USD';
    var kind = existing?.kind ?? (addToBoard ? 'note' : 'link');
    String? photo = existing?.text('photo'), error;
    bool saving = false;
    await _showEditorDialog<void>(
      context: context,
      controllers: [title, body, url, tags, price],
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            existing == null ? 'Keep something good.' : 'Edit saved item',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (existing == null) ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'link',
                          label: Text('Link'),
                          icon: Icon(Icons.link),
                        ),
                        ButtonSegment(
                          value: 'note',
                          label: Text('Note'),
                          icon: Icon(Icons.notes),
                        ),
                        ButtonSegment(
                          value: 'photo',
                          label: Text('Photo'),
                          icon: Icon(Icons.photo_outlined),
                        ),
                      ],
                      selected: {kind},
                      onSelectionChanged: (v) => update(() => kind = v.first),
                    ),
                    const SizedBox(height: 22),
                  ],
                  if (kind == 'link') ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: price,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Price (optional)',
                              hintText: '0.00',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: currency,
                          items: Entry.currencies
                              .map(
                                (code) => DropdownMenuItem(
                                  value: code,
                                  child: Text(code),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => update(() => currency = value!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: url,
                      keyboardType: TextInputType.url,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Web address',
                        hintText: 'https://',
                      ),
                    ),
                    const SizedBox(height: 15),
                  ],
                  TextField(
                    controller: title,
                    maxLength: 150,
                    decoration: InputDecoration(
                      labelText: kind == 'photo' ? 'Photo title' : 'Title',
                      hintText: 'What caught your eye?',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: body,
                    maxLines: kind == 'note' ? 7 : 3,
                    maxLength: 20000,
                    decoration: InputDecoration(
                      labelText: kind == 'note' ? 'Your note' : 'Description',
                      hintText: 'A little context for your future self.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tags,
                    maxLength: 150,
                    decoration: const InputDecoration(
                      labelText: 'Tags',
                      hintText: 'inspiration research weekend',
                      helperText:
                          'Separate tags with spaces. Commas also work.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: store.allTags
                        .take(12)
                        .map(
                          (tag) => ActionChip(
                            label: Text(tag),
                            onPressed: () => update(
                              () => tags.text = Entry.parseTags(
                                '${tags.text} $tag',
                              ).join(' '),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if (kind == 'photo' || photo?.isNotEmpty == true)
                    OutlinedButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              update(() => saving = true);
                              try {
                                final result = await choosePhoto();
                                if (result != null && context.mounted) {
                                  update(() => photo = result);
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  update(() => error = e.toString());
                                }
                              } finally {
                                if (context.mounted) {
                                  update(() => saving = false);
                                }
                              }
                            },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        photo?.isNotEmpty == true
                            ? 'Replace attached photo'
                            : 'Choose a photo',
                      ),
                    ),
                  if (photo?.isNotEmpty == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Photo attached · location metadata removed',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () {
                      try {
                        if (title.text.trim().isEmpty) {
                          throw const FormatException(
                            'Add a title so you can find this later.',
                          );
                        }
                        if (kind == 'link') MediaService.webUri(url.text);
                        if (kind == 'photo' &&
                            (photo == null || photo!.isEmpty)) {
                          throw const FormatException('Choose a photo first.');
                        }
                        final pid = existing?.project ?? projectId!;
                        if (kind == 'link' &&
                            existing == null &&
                            store
                                .items(pid)
                                .any(
                                  (e) =>
                                      e.kind == 'link' &&
                                      ProjectTools.normalizedUrl(
                                            e.text('url'),
                                          ) ==
                                          ProjectTools.normalizedUrl(
                                            url.text.trim(),
                                          ),
                                )) {
                          throw const FormatException(
                            'This link is already in the project. Edit it instead.',
                          );
                        }
                        final cents = kind == 'link'
                            ? Entry.parsePrice(price.text)
                            : null;
                        final data = {
                          if (kind == 'link')
                            'price': cents == null ? '' : Entry.amount(cents),
                          if (kind == 'link') 'currency': currency,
                          if (addToBoard)
                            'boardStatus': store.columns(pid).keys.first,
                          'title': title.text.trim(),
                          'body': body.text.trim(),
                          'url': url.text.trim(),
                          'tags': Entry.parseTags(tags.text).join(' '),
                          'photo': ?photo,
                        };
                        final id =
                            existing?.id ?? store.create(kind, pid, data);
                        if (kind == 'link' &&
                            existing != null &&
                            existing.text('url') != url.text.trim()) {
                          data['photo'] = '';
                          data['previewTitle'] = '';
                          data['previewDescription'] = '';
                        }
                        if (existing != null) store.update(existing, data);
                        Navigator.pop(context);
                        if (kind == 'link') media.preview(store.get(id)!);
                        message('Saved on this device.');
                      } catch (e) {
                        update(
                          () => error = e.toString().replaceFirst(
                            'FormatException: ',
                            '',
                          ),
                        );
                      }
                    },
              child: Text(saving ? 'Preparing photo…' : 'Save to list'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> detail(Entry initial) async => showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final e = store.get(initial.id) ?? initial;
        final hash = e.text('photo');
        return AlertDialog(
          title: Text(e.title),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hash.isNotEmpty && store.blob(hash).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        store.blob(hash),
                        height: 250,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(height: 14),
                  if (e.kind == 'link') ...[
                    SelectableText(
                      e.text('url'),
                      style: TextStyle(color: accent, fontSize: 12),
                    ),
                    previewStatus(e),
                    if (e.priceLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          e.priceLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (e.text('previewDescription').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          e.text('previewDescription'),
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                            height: 1.6,
                          ),
                        ),
                      ),
                    const SizedBox(height: 15),
                  ],
                  SelectableText(
                    e.text('body'),
                    style: const TextStyle(fontSize: 14, height: 1.8),
                  ),
                  const SizedBox(height: 15),
                  if (e.tags.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: e.tags.map(pill).toList(),
                    ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => itemPlanning(e),
                        icon: const Icon(Icons.checklist),
                        label: const Text('Planning & comments'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => comments(e),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Comments'),
                      ),
                      OutlinedButton.icon(
                        onPressed: !store.canEdit(e.project)
                            ? null
                            : () {
                                Navigator.pop(context);
                                editItem(e);
                              },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          editReminder(target: e);
                        },
                        icon: const Icon(Icons.notifications_none, size: 16),
                        label: const Text('Remind me'),
                      ),
                      TextButton(
                        onPressed: () => history(e),
                        child: const Text('Version history'),
                      ),
                      TextButton(
                        onPressed: !store.canEdit(e.project)
                            ? null
                            : () {
                                Navigator.pop(context);
                                remove(e);
                              },
                        child: const Text('Move to trash'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (e.kind == 'link')
              FilledButton.icon(
                onPressed: () => act(() async {
                  if (!await launchUrl(
                    MediaService.webUri(e.text('url')),
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw Exception('Could not open the browser.');
                  }
                }),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Visit website'),
              ),
          ],
        );
      },
    ),
  );
  Future<void> history(Entry e) async {
    final versions = store
        .history(e.id)
        .where((o) => (o['fields'] as Map).containsKey('body'))
        .toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Every version, kept safe.'),
        content: SizedBox(
          width: 500,
          child: ListView(
            shrinkWrap: true,
            children: versions
                .map(
                  (o) => ListTile(
                    title: Text(
                      (o['fields'] as Map)['body'].toString(),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text('Saved revision · newest first'),
                    trailing: TextButton(
                      onPressed: !store.canEdit(e.project)
                          ? null
                          : () {
                              store.update(e, {
                                'body': (o['fields'] as Map)['body'],
                              });
                              Navigator.pop(context);
                            },
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
    );
  }

  Future<void> remove(Entry e) async {
    if (e.kind != 'reminder' && !allowEdit(e.project)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to trash?'),
        content: Text(
          '“${e.title}” will be hidden. Restore it from Settings. Shared changes reach connected friends.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move to trash'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      store.update(e, {'deleted': true});
      if (e.kind == 'project') navigate('projects');
    }
  }

  Future<void> editReminder({Entry? target, Entry? existing}) async {
    if (store.projects.isEmpty) {
      message('Create a project before adding a reminder.');
      return;
    }
    final title = TextEditingController(text: existing?.title ?? target?.title);
    String pid =
        existing?.project ??
        target?.project ??
        projectId ??
        store.projects.first.id;
    var recurrence = existing?.text('repeat').isNotEmpty == true
        ? existing!.text('repeat')
        : 'none';
    DateTime due =
        DateTime.tryParse(existing?.text('due') ?? '')?.toLocal() ??
        DateTime.now().add(const Duration(days: 1));
    await _showEditorDialog<void>(
      context: context,
      controllers: [title],
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('A little reminder.'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Remind me to…'),
                ),
                const SizedBox(height: 17),
                if (target == null && existing == null)
                  DropdownButtonFormField<String>(
                    initialValue: pid,
                    decoration: const InputDecoration(labelText: 'Project'),
                    items: store.projects
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.title),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => pid = v!,
                  ),
                const SizedBox(height: 17),
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: due,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(due),
                    );
                    if (time != null && context.mounted) {
                      update(
                        () => due = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 17),
                  label: Text(due.toString().substring(0, 16)),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: recurrence,
                  decoration: const InputDecoration(labelText: 'Repeat'),
                  items: const [
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('Does not repeat'),
                    ),
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(
                      value: 'days:1,2,3,4,5',
                      child: Text('Weekdays'),
                    ),
                  ],
                  onChanged: (v) => recurrence = v!,
                ),
                const Text(
                  'Personal to this device. Due times use your current time zone.',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty) return;
                final fields = {
                  'title': title.text.trim(),
                  'due': due.toUtc().toIso8601String(),
                  'repeat': recurrence,
                  'repeatDay': due.day,
                  'zone': due.timeZoneName,
                  'target': existing?.text('target') ?? target?.id ?? pid,
                  'done': false,
                };
                if (existing != null) {
                  store.update(existing, fields);
                } else {
                  store.create('reminder', pid, fields);
                }
                Navigator.pop(context);
                message('Reminder saved.');
              },
              child: const Text('Set reminder'),
            ),
          ],
        ),
      ),
    );
  }

  void loadExample() {
    final pid = store.create('project', '', {
      'title': 'A space of our own',
      'description':
          'A collection of things that could make a place feel like us.',
      'label': 'Home & living',
      'color': 0xff91a997,
      'example': true,
    });
    store.create('link', pid, {
      'title': 'A better way to make space',
      'body':
          'Thoughtful spaces, natural materials, and ideas worth coming back to.',
      'url': 'https://www.architecturaldigest.com/',
      'tags': 'Inspiration',
    });
    store.create('note', pid, {
      'title': "The feeling we're going for",
      'body':
          'Less, but better.\n\nA room that feels collected, not decorated. Warm light. Honest materials. A place to slow down.',
      'tags': 'Starting point',
    });
    store.create('link', pid, {
      'title': 'Objects with a little more meaning',
      'body': 'Independent makers and considered pieces for everyday life.',
      'url': 'https://www.are.na/',
      'tags': 'Research',
    });
    store.create('note', pid, {
      'title': 'Things to look into',
      'body':
          "Oak or walnut for the desk?\nA lamp with a warmer glow\nStorage that doesn't feel like storage",
      'tags': 'Ideas',
    });
    openProject(pid);
    message('Example project added. You can edit or remove it.');
  }

  Future<void> chooseAccent() async {
    final input = TextEditingController(
      text: store.setting('accent') ?? '5848D9',
    );
    String? error;
    await _showEditorDialog<void>(
      context: context,
      controllers: [input],
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final hex = input.text.trim().replaceFirst('#', '');
          final valid = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex);
          final selected = valid
              ? Color(0xff000000 | int.parse(hex, radix: 16))
              : accent;
          return AlertDialog(
            title: const Text('Choose your accent color'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final preset in <String, String>{
                          'Purple': '5848D9',
                          'Blue': '2563EB',
                          'Teal': '008577',
                          'Green': '2E7D32',
                          'Orange': 'C05600',
                          'Rose': 'BE185D',
                          'Red': 'C62828',
                          'Slate': '475569',
                        }.entries)
                          Tooltip(
                            message: preset.key,
                            child: Semantics(
                              label: preset.key,
                              button: true,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () => update(() {
                                  input.text = preset.value;
                                  error = null;
                                }),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(
                                      0xff000000 |
                                          int.parse(preset.value, radix: 16),
                                    ),
                                  ),
                                  child: hex.toUpperCase() == preset.value
                                      ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: input,
                      maxLength: 7,
                      decoration: InputDecoration(
                        labelText: 'Hex color',
                        hintText: '#008577',
                        errorText: error,
                      ),
                      onChanged: (_) => update(() {
                        error = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selected,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Your ideas, your color.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected.computeLuminance() > .179
                              ? Colors.black
                              : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Light and dark themes adapt your color for readability.',
                      style: TextStyle(fontSize: 12),
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
                  if (!valid) {
                    update(
                      () =>
                          error = 'Enter six hex digits, for example #008577.',
                    );
                    return;
                  }
                  store.setSetting('accent', hex.toUpperCase());
                  widget.onTheme();
                  Navigator.pop(context);
                },
                child: const Text('Apply color'),
              ),
            ],
          );
        },
      ),
    );
  }

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
                const Text('The List · 1.2.0', style: TextStyle(fontSize: 11)),
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

  Future<void> connectionSettings() async {
    final controller = TextEditingController(
      text: SharingConfig.endpoint(store),
    );
    String? error;
    await _showEditorDialog<void>(
      context: context,
      controllers: [controller],
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Connection service'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your app owner provides this address. Friends receive it automatically with an invitation.',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Service HTTPS address',
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final value = controller.text.trim();
                  SyncService.serverUri(value);
                  await sync.request(value, '/health');
                  store.setSetting('sharing-server', value);
                  if (context.mounted) Navigator.pop(context);
                  store.touch();
                  message('Connection service saved. Invitations are ready.');
                } catch (_) {
                  if (context.mounted) {
                    update(
                      () => error =
                          'Could not reach this service. Check its address.',
                    );
                  }
                }
              },
              child: const Text('Check & save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> sharing() async {
    final server = SharingConfig.endpoint(store);
    final code = TextEditingController();
    String? invitation, error;
    bool working = false;
    String access = 'update';
    await _showEditorDialog<void>(
      context: context,
      controllers: [code],
      builder: (context) => StatefulBuilder(
        builder: (context, update) => ListenableBuilder(
          listenable: sync,
          builder: (context, _) => AlertDialog(
            title: const Text('Good ideas travel together.'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Share this project directly with a friend. Both apps need to be open. Project contents are encrypted between your devices.',
                      style: TextStyle(fontSize: 12, height: 1.7),
                    ),
                    const SizedBox(height: 18),
                    if (server.isEmpty)
                      const Text(
                        'Sharing is not configured for this installation yet. A connection service must be set up once by the app owner.',
                        style: TextStyle(fontSize: 12),
                      ),
                    const SizedBox(height: 14),
                    if (project != null && store.canManageSharing(projectId!))
                      DropdownButtonFormField<String>(
                        initialValue: access,
                        decoration: const InputDecoration(
                          labelText: 'Invitation access',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'read',
                            child: Text('Read only'),
                          ),
                          DropdownMenuItem(
                            value: 'update',
                            child: Text('Can update'),
                          ),
                        ],
                        onChanged: working
                            ? null
                            : (v) => update(() => access = v!),
                      ),
                    const SizedBox(height: 12),
                    if (project != null && store.canManageSharing(projectId!))
                      FilledButton.icon(
                        onPressed: working || server.isEmpty
                            ? null
                            : () async {
                                update(() => working = true);
                                try {
                                  final value = await sync.invite(
                                    projectId!,
                                    server,
                                    access: access,
                                  );
                                  if (context.mounted) {
                                    update(() => invitation = value);
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    update(() => error = e.toString());
                                  }
                                } finally {
                                  if (context.mounted) {
                                    update(() => working = false);
                                  }
                                }
                              },
                        icon: const Icon(Icons.person_add_alt, size: 17),
                        label: const Text('Create invitation'),
                      ),
                    if (invitation != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'One use · expires in 15 minutes',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              invitation!,
                              maxLines: 3,
                              style: const TextStyle(fontSize: 10),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: invitation!),
                                );
                                message(
                                  'Invitation copied. Send it only to your friend.',
                                );
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('Copy invitation'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    TextField(
                      controller: code,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Have an invitation?',
                        hintText: 'Paste thelist:…',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: working
                          ? null
                          : () async {
                              update(() => working = true);
                              try {
                                final pid = await sync.join(code.text);
                                if (mounted) openProject(pid);
                                if (context.mounted) update(() => code.clear());
                              } catch (e) {
                                if (context.mounted) {
                                  update(() => error = e.toString());
                                }
                              } finally {
                                if (context.mounted) {
                                  update(() => working = false);
                                }
                              }
                            },
                      icon: const Icon(Icons.link, size: 17),
                      label: const Text('Join project'),
                    ),
                    if (working)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: LinearProgressIndicator(),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (sync.error != null)
                      Text(sync.error!, style: const TextStyle(fontSize: 11)),
                    for (final peer in sync.peers.where(
                      (p) => projectId == null || p.project == projectId,
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          peer.connected ? Icons.sync : Icons.sync_problem,
                          size: 20,
                        ),
                        title: Text(
                          '${peer.config['peerName'] ?? 'Friend'} · ${peer.status}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          peer.config['host'] == true
                              ? 'You invited this device · ${peer.config['access'] == 'read' ? 'Read only' : 'Can update'}'
                              : 'You joined this project · ${peer.config['access'] == 'read' ? 'Read only' : 'Can update'}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        trailing: Wrap(
                          children: [
                            if (peer.config['host'] == true)
                              PopupMenuButton<String>(
                                tooltip: 'Change access',
                                icon: const Icon(
                                  Icons.admin_panel_settings_outlined,
                                  size: 18,
                                ),
                                onSelected: (v) =>
                                    act(() => sync.changeAccess(peer, v)),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'read',
                                    child: Text('Read only'),
                                  ),
                                  PopupMenuItem(
                                    value: 'update',
                                    child: Text('Can update'),
                                  ),
                                ],
                              ),
                            IconButton(
                              tooltip: 'Reconnect',
                              onPressed: () => act(() => peer.connect()),
                              icon: const Icon(Icons.refresh, size: 18),
                            ),
                            IconButton(
                              tooltip: 'Stop sharing with this device',
                              onPressed: () => act(() => sync.disconnect(peer)),
                              icon: const Icon(Icons.link_off, size: 18),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    const Text(
                      'Disconnecting stops this pairing. Copies already received by your friend remain on their device. Reminders stay personal.',
                      style: TextStyle(fontSize: 10, height: 1.6),
                    ),
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
      ),
    );
  }
}
