part of '../workspace.dart';

extension _WorkspaceEditorsItems on _WorkspaceState {
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
    await showEditorDialog<void>(
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
                      children: e.tags.map(statusBadge).toList(),
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
      if (e.kind == 'project') navigate(WorkspaceSection.projects);
    }
  }
}
