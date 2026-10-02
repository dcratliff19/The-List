part of '../workspace.dart';

extension _WorkspaceFeaturesCapture on _WorkspaceState {
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
                  navigate(WorkspaceSection.inbox);
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
}
