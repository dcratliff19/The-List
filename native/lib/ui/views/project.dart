part of '../workspace.dart';

extension _WorkspaceProjectView on _WorkspaceState {
  bool get boardView => store.setting('view-$projectId') == 'board';
  Widget projectContent(bool wide) {
    final all = store
        .items(projectId!)
        .where((e) => ['link', 'note', 'photo'].contains(e.kind))
        .toList();
    return Column(
      children: [
        if (!store.canEdit(projectId!))
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Read-only project'),
              subtitle: Text(
                'You can browse and set personal reminders. Ask the owner for update access to make changes.',
              ),
            ),
          ),
        Row(
          children: [
            statusBadge(
              project!.text('label').isEmpty
                  ? 'PROJECT'
                  : project!.text('label'),
            ),
            const SizedBox(width: 12),
            Text(
              '${all.length} things collected',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: sharing,
              icon: Icon(Icons.people_outline, size: 17),
              label: const Text('Share', style: TextStyle(fontSize: 11)),
            ),
            PopupMenuButton<String>(
              tooltip: 'Project options',
              onSelected: (v) {
                if (v != 'remind' && !allowEdit(projectId!)) return;
                if (v == 'edit') editProject(project);
                if (v == 'cover') pickCover();
                if (v == 'remind') editReminder(target: project);
                if (v == 'archive') {
                  store.update(project!, {
                    'archived': !project!.flag('archived'),
                  });
                  navigate(WorkspaceSection.projects);
                }
                if (v == 'delete') remove(project!);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit project')),
                const PopupMenuItem(
                  value: 'cover',
                  child: Text('Attach cover photo'),
                ),
                const PopupMenuItem(
                  value: 'remind',
                  child: Text('Set a reminder'),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    project!.flag('archived')
                        ? 'Restore project'
                        : 'Archive project',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Move to trash'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => act(projectTools),
              icon: const Icon(Icons.tune),
              label: const Text('Project tools'),
            ),
            OutlinedButton.icon(
              onPressed: () => comments(project!),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Project comments'),
            ),
            OutlinedButton.icon(
              onPressed: store.canEdit(projectId!)
                  ? () => act(() => capture())
                  : null,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Import links'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        budgetSummary(),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              store.projectTotals(projectId!).isEmpty
                  ? 'Project total: no prices added'
                  : 'Project total: ${store.projectTotals(projectId!).entries.map((total) => '${total.key} ${Entry.amount(total.value)}').join('  ·  ')}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('List'),
                icon: Icon(Icons.view_list_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('Board'),
                icon: Icon(Icons.view_kanban_outlined),
              ),
            ],
            selected: {boardView},
            onSelectionChanged: (selection) => rebuild(() {
              store.setSetting(
                'view-$projectId',
                selection.first ? 'board' : 'list',
              );
            }),
          ),
        ),
        const SizedBox(height: 18),
        const Divider(height: 1),
        SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in ['all', 'link', 'note', 'photo'])
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: TextButton(
                            onPressed: () => rebuild(() => filter = f),
                            style: TextButton.styleFrom(
                              foregroundColor: filter == f ? accent : muted,
                            ),
                            child: Text(
                              {
                                'all': 'Everything  ${all.length}',
                                'link': 'Links',
                                'note': 'Notes',
                                'photo': 'Photos',
                              }[f]!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: filter == f
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (wide)
                Text(
                  'Recently added',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
            ],
          ),
        ),
        if (boardView) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: store.canEdit(projectId!)
                      ? addExistingToBoard
                      : null,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Add existing item'),
                ),
                FilledButton.icon(
                  onPressed: store.canEdit(projectId!)
                      ? () => editItem(null, true)
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('New card'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Choose items for this board. Other project items stay in your List.',
            ),
          ),
        ],
        if (boardView)
          kanbanBoard(
            all
                .where(
                  (e) =>
                      boardColumns.containsKey(e.text('boardStatus')) &&
                      (filter == 'all' || e.kind == filter) &&
                      matches(e),
                )
                .toList(),
          )
        else
          itemsView(
            all
                .where(
                  (e) => (filter == 'all' || e.kind == filter) && matches(e),
                )
                .toList(),
            wide,
          ),
      ],
    );
  }
}
