part of 'workspace.dart';

extension _WorkspaceFeed on _WorkspaceState {
  bool allowEdit(String project) {
    if (store.canEdit(project)) return true;
    message('This project is read-only. Ask the owner for update access.');
    return false;
  }

  Widget feedContent() {
    final events = store.sharedActivity
        .where(
          (e) =>
              query.trim().isEmpty ||
              '${e['fields']} ${store.get(e['project'] as String)?.title}'
                  .toLowerCase()
                  .contains(query.trim().toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'What changed while you were away.',
                style: TextStyle(color: muted),
              ),
            ),
            TextButton.icon(
              onPressed: store.unreadActivity == 0
                  ? null
                  : () => store.markActivityRead(),
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Mark all read'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (events.isEmpty)
          empty(
            'Good ideas grow together.',
            'Updates from friends appear here for projects you share and projects shared with you.',
            Icons.dynamic_feed_outlined,
          ),
        for (final event in events)
          Builder(
            builder: (context) {
              final fields = event['fields'] as Map;
              final project = store.get(event['project'] as String);
              final item = store.get(event['entity'] as String);
              final actor = fields['author']?.toString() ?? 'A friend';
              final time = DateTime.tryParse(
                fields['modified']?.toString() ?? event['received'] as String,
              )?.toLocal().toString();
              final unread = event['seen'] == 0;
              final title =
                  fields['title']?.toString() ?? item?.title ?? 'Project item';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: muted.withValues(alpha: .15)),
                  ),
                  color: unread ? accent.withValues(alpha: .07) : surface,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: accent.withValues(alpha: .12),
                      child: Text(
                        actor.isEmpty
                            ? '?'
                            : actor.substring(0, 1).toUpperCase(),
                      ),
                    ),
                    title: Text(
                      '$actor · ${store.activitySummary(event)}',
                      style: TextStyle(
                        fontWeight: unread
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${project?.title ?? 'Shared project'}${title.isEmpty || event['kind'] == 'comment' ? '' : ' / $title'}',
                          ),
                          if (event['kind'] == 'comment')
                            Text(
                              fields['body']?.toString() ?? '',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 6),
                          Text(
                            time == null ? '' : time.substring(0, 16),
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                    trailing: unread
                        ? Icon(Icons.circle, size: 8, color: accent)
                        : const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      store.markActivityRead(event['id'] as String);
                      if (project == null || project.deleted) {
                        message('This project is no longer available.');
                        return;
                      }
                      if (event['kind'] == 'comment') {
                        final target = store.get(
                          fields['target']?.toString() ??
                              item?.text('target') ??
                              '',
                        );
                        if (target != null && !target.deleted) {
                          store.markCommentRead(event['entity'] as String);
                          comments(target);
                          return;
                        }
                      }
                      openProject(project.id);
                      if (item != null &&
                          !item.deleted &&
                          ['link', 'note', 'photo'].contains(item.kind)) {
                        detail(item);
                      }
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
