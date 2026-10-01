part of 'workspace.dart';

extension _WorkspaceFeatures on _WorkspaceState {
  Future<Map<String, String>?> featureForm(
    String title,
    Map<String, String> initial, {
    Map<String, List<String>> choices = const {},
    String? help,
  }) async {
    final values = Map<String, String>.from(initial);
    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (help != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(help),
                  ),
                for (final field in initial.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: choices.containsKey(field.key)
                        ? DropdownButtonFormField<String>(
                            initialValue: field.value,
                            decoration: InputDecoration(labelText: field.key),
                            items: choices[field.key]!
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => values[field.key] = v!,
                          )
                        : TextFormField(
                            initialValue: field.value,
                            maxLines:
                                field.key.contains('URLs') ||
                                    field.key.contains('Comment')
                                ? 5
                                : 1,
                            decoration: InputDecoration(labelText: field.key),
                            onChanged: (v) => values[field.key] = v,
                          ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, values),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> featureSheet(
    String title,
    Widget Function(BuildContext, StateSetter) body,
  ) => showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => ListenableBuilder(
        listenable: store,
        builder: (ctx, _) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 680,
            height: 470,
            child: SingleChildScrollView(child: body(ctx, update)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> projectTools() => featureSheet(
    'Project tools',
    (ctx, update) => Column(
      children: [
        ListTile(
          leading: const Icon(Icons.view_kanban_outlined),
          title: const Text('Manage board columns'),
          onTap: store.canEdit(projectId!) ? () => act(manageColumns) : null,
        ),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Project budget'),
          onTap: store.canEdit(projectId!) ? () => act(editBudget) : null,
        ),
        ListTile(
          leading: const Icon(Icons.compare_arrows),
          title: const Text('Compare purchase options'),
          onTap: () => act(compareOptions),
        ),
        ListTile(
          leading: const Icon(Icons.copy_all),
          title: const Text('Save as template'),
          subtitle: const Text(
            'Structure and tags only; no items are added to future boards.',
          ),
          onTap: () => act(() async {
            final value = await featureForm('Save project template', {
              'Name': project!.title,
            });
            if (value != null) {
              store.saveTemplate(project!, value['Name']!);
              message('Template saved.');
            }
          }),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Activity and conflict review'),
          onTap: () => act(activity),
        ),
        ListTile(
          leading: const Icon(Icons.people_outline),
          title: const Text('People and connection status'),
          onTap: people,
        ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Export this project'),
          onTap: () => act(exportProject),
        ),
      ],
    ),
  );

  Future<void> manageColumns() => featureSheet(
    'Board columns',
    (ctx, update) => Column(
      children: [
        const Text(
          'Move or remove cards before deleting a column. Arrows change column order.',
        ),
        for (final column in store.columns(projectId!).entries)
          ListTile(
            title: Text(column.value),
            subtitle: Text(
              '${store.cards(projectId!, column.key).length} cards',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Move ${column.value} left',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => act(() async {
                    final entries = store.columns(projectId!).entries.toList();
                    final i = entries.indexWhere((c) => c.key == column.key);
                    if (i > 0) {
                      final c = entries.removeAt(i);
                      entries.insert(i - 1, c);
                      store.saveColumns(projectId!, Map.fromEntries(entries));
                    }
                  }),
                ),
                IconButton(
                  tooltip: 'Rename ${column.value}',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => act(() async {
                    final result = await featureForm('Rename column', {
                      'Name': column.value,
                    });
                    if (result != null) {
                      store.saveColumns(projectId!, {
                        ...store.columns(projectId!),
                        column.key: result['Name']!.trim(),
                      });
                    }
                  }),
                ),
                IconButton(
                  tooltip: 'Delete ${column.value}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => act(() async {
                    final columns = store.columns(projectId!)
                      ..remove(column.key);
                    store.saveColumns(projectId!, columns);
                  }),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => act(() async {
            final result = await featureForm('New column', {'Name': ''});
            if (result != null) {
              store.saveColumns(projectId!, {
                ...store.columns(projectId!),
                uuid.v4(): result['Name']!.trim(),
              });
            }
          }),
          icon: const Icon(Icons.add),
          label: const Text('Add column'),
        ),
      ],
    ),
  );

  Future<void> editBudget() async {
    final result = await featureForm(
      'Project budget',
      {
        'Budget': project!.text('budget'),
        'Currency': project!.text('budgetCurrency').isEmpty
            ? 'USD'
            : project!.text('budgetCurrency'),
      },
      choices: {'Currency': Entry.currencies},
      help:
          'Remaining budget uses links explicitly marked Chosen, Ordered or Received. Other currencies remain separate.',
    );
    if (result == null) return;
    final cents = Entry.parsePrice(result['Budget']!);
    store.update(project!, {
      'budget': cents == null ? '' : Entry.amount(cents),
      'budgetCurrency': result['Currency'],
    });
  }

  Widget budgetSummary() {
    final cents = Entry.parsePrice(project!.text('budget'));
    if (cents == null) return const SizedBox.shrink();
    final currency = project!.text('budgetCurrency');
    final chosen = store.plannedTotals(projectId!)[currency] ?? 0;
    final difference = cents - chosen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Budget $currency ${Entry.amount(cents)} · Planned ${Entry.amount(chosen)} · ${difference < 0 ? 'Over by' : 'Remaining'} ${Entry.amount(difference.abs())}',
        style: TextStyle(
          color: difference < 0 ? Theme.of(context).colorScheme.error : accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> compareOptions() => featureSheet('Purchase comparison', (
    ctx,
    update,
  ) {
    final groups =
        store
            .items(projectId!)
            .where((e) => e.kind == 'link')
            .map((e) => e.text('comparison'))
            .toSet()
            .toList()
          ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Set a comparison group in an item’s planning options. Choosing one option returns the other members of its group to Considering.',
        ),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(
              group.isEmpty ? 'Ungrouped' : group,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Item')),
                DataColumn(label: Text('Unit price')),
                DataColumn(label: Text('Qty')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Select')),
              ],
              rows: store
                  .items(projectId!)
                  .where(
                    (e) => e.kind == 'link' && e.text('comparison') == group,
                  )
                  .map(
                    (e) => DataRow(
                      cells: [
                        DataCell(
                          SizedBox(width: 160, child: Text(e.title)),
                          onTap: () => detail(e),
                        ),
                        DataCell(
                          Text(
                            e.priceLabel.isEmpty ? 'Unpriced' : e.priceLabel,
                          ),
                        ),
                        DataCell(Text('${e.quantity}')),
                        DataCell(
                          Text(
                            e.text('purchaseStatus').isEmpty
                                ? 'considering'
                                : e.text('purchaseStatus'),
                          ),
                        ),
                        DataCell(
                          TextButton(
                            onPressed: () => store.chooseAlternative(e),
                            child: const Text('Choose'),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  });

  Future<void> itemPlanning(
    Entry original,
  ) => featureSheet('Planning · ${original.title}', (ctx, update) {
    final e = store.get(original.id)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Assigned to'),
          subtitle: Text(
            e.text('assignee').isEmpty ? 'Unassigned' : e.text('assignee'),
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: !store.canEdit(e.project)
              ? null
              : () => act(() async {
                  final result = await featureForm('Assign item', {
                    'Name': e.text('assignee'),
                  });
                  if (result != null) {
                    store.update(e, {'assignee': result['Name']!.trim()});
                  }
                }),
        ),
        if (e.kind == 'link')
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Purchase options'),
            subtitle: Text(
              '${e.quantity} × ${e.priceLabel.isEmpty ? 'Unpriced' : e.priceLabel} · ${e.text('purchaseStatus').isEmpty ? 'considering' : e.text('purchaseStatus')}',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: !store.canEdit(e.project)
                ? null
                : () => act(() async {
                    final result = await featureForm(
                      'Purchase options',
                      {
                        'Quantity': '${e.quantity}',
                        'Status': e.text('purchaseStatus').isEmpty
                            ? 'considering'
                            : e.text('purchaseStatus'),
                        'Comparison group': e.text('comparison'),
                      },
                      choices: {
                        'Status': [
                          'considering',
                          'chosen',
                          'ordered',
                          'received',
                        ],
                      },
                    );
                    if (result != null) {
                      final quantity = int.tryParse(result['Quantity']!);
                      if (quantity == null ||
                          quantity < 1 ||
                          quantity > 1000000) {
                        throw const FormatException(
                          'Enter a whole quantity from 1 to 1,000,000.',
                        );
                      }
                      store.update(e, {
                        'quantity': quantity,
                        'purchaseStatus': result['Status'],
                        'comparison': result['Comparison group']!.trim(),
                      });
                    }
                  }),
          ),
        const Divider(),
        const Text('Checklist', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final task in store.childrenOf(e.id, 'check'))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(task.title),
            value: task.flag('done'),
            onChanged: !store.canEdit(e.project)
                ? null
                : (v) => store.update(task, {'done': v}),
            secondary: IconButton(
              tooltip: 'Remove checklist item',
              icon: const Icon(Icons.close),
              onPressed: !store.canEdit(e.project)
                  ? null
                  : () => store.update(task, {'deleted': true}),
            ),
          ),
        TextButton.icon(
          onPressed: !store.canEdit(e.project)
              ? null
              : () => act(() async {
                  final result = await featureForm('Add checklist item', {
                    'Title': '',
                  });
                  if (result != null && result['Title']!.trim().isNotEmpty) {
                    store.create('check', e.project, {
                      'title': result['Title']!.trim(),
                      'target': e.id,
                      'done': false,
                    });
                  }
                }),
          icon: const Icon(Icons.add),
          label: const Text('Add checklist item'),
        ),
        const Divider(),
        commentThread(e),
      ],
    );
  });

  Future<void> comments(Entry target) => featureSheet(
    'Comments · ${target.title}',
    (ctx, update) => commentThread(target),
  );

  Widget commentThread(Entry target) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Comments', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text(
        'Shared participants receive comments in their Inbox when updates sync.',
      ),
      if (store.childrenOf(target.id, 'comment').isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('Start the conversation.'),
        ),
      for (final comment in store.childrenOf(target.id, 'comment'))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: SelectableText(comment.text('body')),
          subtitle: Text(
            '${comment.text('author')} · ${DateTime.tryParse(comment.text('created'))?.toLocal().toString().substring(0, 16) ?? ''}',
          ),
        ),
      TextButton.icon(
        onPressed: !store.canEdit(target.project)
            ? null
            : () => act(() async {
                final result = await featureForm('Add comment', {
                  'Comment': '',
                });
                if (result != null && result['Comment']!.trim().isNotEmpty) {
                  store.addComment(target, result['Comment']!);
                }
              }),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Add comment'),
      ),
    ],
  );

  Future<void> tagManager() => featureSheet(
    'Manage tags',
    (ctx, update) => Column(
      children: [
        const Text(
          'Rename a tag, merge it into another tag, or leave the replacement blank to remove it. Changes apply across your workspace.',
        ),
        for (final tag in store.allTags)
          ListTile(
            title: Text(tag),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => act(() async {
              final result = await featureForm('Rename or merge tag', {
                'Replacement': tag,
              });
              if (result != null) store.renameTag(tag, result['Replacement']!);
            }),
          ),
      ],
    ),
  );
  Future<void> templatesDialog() => featureSheet(
    'Project templates',
    (ctx, update) => Column(
      children: [
        const Text(
          'Save a template from Project tools. Templates create an empty project with your chosen columns, category and tags.',
        ),
        for (final template in store.templates)
          ListTile(
            title: Text(template['name']),
            trailing: const Icon(Icons.add),
            onTap: () => act(() async {
              final result = await featureForm('Create from template', {
                'Project name': template['name'],
              });
              if (result != null && result['Project name']!.trim().isNotEmpty) {
                final id = store.createFromTemplate(
                  template,
                  result['Project name']!.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                openProject(id);
              }
            }),
          ),
      ],
    ),
  );

  Future<void> capture({String initial = '', String note = ''}) async {
    final result = await featureForm('Quick capture', {
      'Title or note': note,
      'URLs (one per line, optional)': initial,
    });
    if (result == null || !mounted) return;
    final raw = result['URLs (one per line, optional)']!
        .split(RegExp(r'\s+'))
        .where((v) => v.isNotEmpty)
        .toList();
    if (raw.length > 100) {
      throw const FormatException('Import up to 100 URLs at a time.');
    }
    final urls = raw.map(ProjectTools.normalizedUrl).toSet().toList();
    if (urls.isEmpty && result['Title or note']!.trim().isEmpty) return;
    // Capture remains available while browsing a read-only shared project.
    String destination = projectId != null && store.canEdit(projectId!)
        ? projectId!
        : 'inbox';
    final selected = urls.toSet();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Review capture'),
          content: SizedBox(
            width: 520,
            height: 360,
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: destination,
                  decoration: const InputDecoration(labelText: 'Save to'),
                  items: [
                    const DropdownMenuItem(
                      value: 'inbox',
                      child: Text('Inbox'),
                    ),
                    ...store.projects
                        .where((e) => store.canEdit(e.id))
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.title),
                          ),
                        ),
                  ],
                  onChanged: (v) => update(() => destination = v!),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: urls.isEmpty
                      ? Text(result['Title or note']!)
                      : ListView(
                          children: urls.map((url) {
                            final duplicate = destination == 'inbox'
                                ? null
                                : store.duplicate(destination, url);
                            return CheckboxListTile(
                              title: Text(url),
                              subtitle: duplicate == null
                                  ? null
                                  : const Text(
                                      'Already saved — tap the open icon to view',
                                    ),
                              secondary: duplicate == null
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.open_in_new),
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        openProject(duplicate.project);
                                        detail(duplicate);
                                      },
                                    ),
                              value:
                                  duplicate == null && selected.contains(url),
                              onChanged: duplicate != null
                                  ? null
                                  : (v) => update(() {
                                      if (v == true) {
                                        selected.add(url);
                                      } else {
                                        selected.remove(url);
                                      }
                                    }),
                            );
                          }).toList(),
                        ),
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
              onPressed: () => act(() async {
                final pid = destination == 'inbox'
                    ? store.inbox()
                    : destination;
                if (urls.isEmpty) {
                  store.create('note', pid, {
                    'title': result['Title or note']!.trim(),
                    'body': result['Title or note']!.trim(),
                  });
                }
                for (final url in selected) {
                  if (store.duplicate(pid, url) != null) continue;
                  final id = store.create('link', pid, {
                    'title':
                        urls.length == 1 &&
                            result['Title or note']!.trim().isNotEmpty
                        ? result['Title or note']!.trim()
                        : Uri.parse(url).host,
                    'url': url,
                  });
                  if (widget.servicesEnabled) {
                    unawaited(media.preview(store.get(id)!));
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (destination == 'inbox') {
                  navigate('inbox');
                } else {
                  openProject(pid);
                }
              }),
              child: const Text('Save selected'),
            ),
          ],
        ),
      ),
    );
  }

  Widget inboxContent() {
    final inboxProjects = store.entries
        .where((e) => e.kind == 'project' && e.flag('inbox') && !e.deleted)
        .map((e) => e.id)
        .toSet();
    final entries = store.entries.where(
      (e) =>
          inboxProjects.contains(e.project) &&
          ['link', 'note', 'photo'].contains(e.kind) &&
          !e.deleted &&
          matches(e),
    );
    final notifications = store.commentInbox
        .where(
          (e) =>
              matches(e) ||
              (store
                      .get(e.project)
                      ?.title
                      .toLowerCase()
                      .contains(query.toLowerCase()) ??
                  false) ||
              (store
                      .get(e.text('target'))
                      ?.title
                      .toLowerCase()
                      .contains(query.toLowerCase()) ??
                  false),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Shared comments · ${store.unreadComments} unread',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (notifications.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text('Comments from shared projects will appear here.'),
          ),
        for (final comment in notifications)
          Card(
            child: ListTile(
              leading: Icon(
                store.commentUnread(comment.id)
                    ? Icons.mark_chat_unread_outlined
                    : Icons.chat_bubble_outline,
              ),
              title: Text(
                comment.text('body'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: store.commentUnread(comment.id)
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                '${comment.text('author')} · ${store.get(comment.project)?.title}${comment.text('target') == comment.project ? ' · Project comment' : ' → ${store.get(comment.text('target'))?.title}'}',
              ),
              onTap: () {
                store.markCommentRead(comment.id);
                final target = store.get(comment.text('target'));
                if (target != null) comments(target);
              },
              trailing: IconButton(
                tooltip: store.commentUnread(comment.id)
                    ? 'Mark comment read'
                    : 'Mark comment unread',
                icon: Icon(
                  store.commentUnread(comment.id)
                      ? Icons.done
                      : Icons.markunread_outlined,
                ),
                onPressed: () => store.markCommentRead(
                  comment.id,
                  read: store.commentUnread(comment.id),
                ),
              ),
            ),
          ),
        const Divider(height: 32),
        const Text(
          'Captured ideas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => act(() => capture()),
          icon: const Icon(Icons.add),
          label: const Text('Capture an idea or links'),
        ),
        for (final item in entries)
          ListTile(
            title: Text(item.title),
            subtitle: Text(item.text('url')),
            onTap: () => detail(item),
            trailing: PopupMenuButton<String>(
              tooltip: 'Move to project',
              onSelected: (pid) => act(() async {
                store.moveFromInbox(item, pid);
              }),
              itemBuilder: (_) => store.projects
                  .map(
                    (e) => PopupMenuItem(
                      value: e.id,
                      child: Text('Move to ${e.title}'),
                    ),
                  )
                  .toList(),
            ),
          ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No captured ideas yet. Capture now; choose a project later.',
            ),
          ),
      ],
    );
  }

  Widget todayContent() {
    final tomorrow = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day + 1,
    );
    final due = store.entries.where(
      (e) =>
          e.kind == 'reminder' &&
          !e.deleted &&
          !e.flag('done') &&
          (DateTime.tryParse(e.text('due'))?.isBefore(tomorrow) ?? false),
    );
    final name = store.setting('display-name') ?? 'This device';
    final assigned = store.entries.where(
      (e) =>
          ['link', 'note', 'photo'].contains(e.kind) &&
          !e.deleted &&
          e.text('assignee').toLowerCase() == name.toLowerCase(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Due today and overdue',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final e in due)
          CheckboxListTile(
            title: Text(e.title),
            subtitle: Text(
              '${store.get(e.project)?.title} · ${DateTime.tryParse(e.text('due'))?.toLocal().toString().substring(0, 16) ?? e.text('due')}',
            ),
            value: false,
            onChanged: (v) => store.completeReminder(e, v ?? false),
          ),
        if (due.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No reminders due today.'),
          ),
        const Divider(),
        Text(
          'Assigned to $name',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final e in assigned)
          ListTile(
            title: Text(e.title),
            subtitle: Text(store.get(e.project)?.title ?? ''),
            onTap: () => detail(e),
          ),
      ],
    );
  }

  Future<void> activity() => featureSheet(
    'Activity and conflict review',
    (ctx, update) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in store.db.select(
          'SELECT conflicts.* FROM conflicts JOIN entities ON entities.id=conflicts.entity WHERE entities.project=? AND resolved=0',
          [projectId],
        ))
          Card(
            child: ListTile(
              title: Text(
                'Competing ${row['field']} · ${store.get(row['entity'] as String)?.title ?? ''}',
              ),
              subtitle: Text(
                'Current: ${store.get(row['entity'] as String)?.text(row['field'] as String)}\nAlternative: ${jsonDecode(row['value'] as String)}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (choice) {
                  final e = store.get(row['entity'] as String);
                  if (e != null && choice == 'use') {
                    if (!allowEdit(e.project)) return;
                    store.update(e, {
                      row['field'] as String: jsonDecode(
                        row['value'] as String,
                      ),
                    });
                  }
                  store.db.execute(
                    'UPDATE conflicts SET resolved=1 WHERE id=?',
                    [row['id']],
                  );
                  store.touch();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'keep', child: Text('Keep current')),
                  PopupMenuItem(value: 'use', child: Text('Use alternative')),
                ],
              ),
            ),
          ),
        const Divider(),
        for (final op
            in store
                .operations(projectId!, includeReminders: true)
                .reversed
                .take(150))
          ListTile(
            title: Text(
              '${store.get(op['entity'])?.title ?? 'Item'} · ${(op['fields'] as Map).keys.where((key) => !['base', 'author', 'modified'].contains(key)).join(', ')}',
            ),
            subtitle: Text(
              '${op['fields']['author'] ?? op['device']} · ${op['fields']['modified'] ?? ''}',
            ),
          ),
      ],
    ),
  );
  Future<void> people() => showDialog<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: sync,
      builder: (ctx, _) => AlertDialog(
        title: const Text('People and connections'),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(store.setting('display-name') ?? 'This device'),
                  subtitle: const Text('Your display name'),
                  trailing: const Icon(Icons.edit),
                  onTap: () => act(() async {
                    final value = await featureForm('Your display name', {
                      'Name': store.setting('display-name') ?? 'This device',
                    });
                    if (value != null && value['Name']!.trim().isNotEmpty) {
                      store.setSetting('display-name', value['Name']!.trim());
                      sync.changed();
                    }
                  }),
                ),
                for (final peer in sync.peers.where(
                  (p) => p.project == projectId,
                ))
                  ListTile(
                    title: Text(
                      peer.config['peerName'] as String? ?? 'Paired friend',
                    ),
                    subtitle: Text(
                      '${peer.status}\nLast successful sync: ${peer.config['lastSync'] ?? 'Not yet'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Reconnect',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => act(peer.connect),
                    ),
                  ),
                if (sync.peers.where((p) => p.project == projectId).isEmpty)
                  const Text(
                    'No friends paired yet. Use Share to create an invitation.',
                  ),
                SwitchListTile(
                  title: const Text('Encrypted offline delivery'),
                  subtitle: const Text(
                    'Opt in to encrypted text updates on your server for up to 30 days. Photos sync directly when both devices are online.',
                  ),
                  value: store.setting('offline-$projectId') == 'on',
                  onChanged: (v) {
                    store.setSetting('offline-$projectId', v ? 'on' : 'off');
                    sync.changed();
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );

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
