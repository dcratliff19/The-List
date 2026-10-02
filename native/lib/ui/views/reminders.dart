part of '../workspace.dart';

extension _WorkspaceRemindersView on _WorkspaceState {
  Widget reminderContent() {
    final reminders =
        store.entries
            .where((e) => e.kind == 'reminder' && !e.deleted && matches(e))
            .toList()
          ..sort((a, b) {
            if (a.flag('done') != b.flag('done')) {
              return a.flag('done') ? 1 : -1;
            }
            return a.text('due').compareTo(b.text('due'));
          });
    if (reminders.isEmpty) {
      return empty(
        'Make a little room for later.',
        'Set a reminder on a project, link, or note.',
        Icons.notifications_none,
      );
    }
    return Column(
      children: reminders.map((e) {
        final due = DateTime.tryParse(e.text('due'))?.toLocal();
        return Card(
          elevation: 0,
          color: surface,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
            leading: Checkbox(
              value: e.flag('done'),
              onChanged: (v) => store.completeReminder(e, v ?? false),
            ),
            title: Text(
              e.title,
              style: TextStyle(
                decoration: e.flag('done') ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Text(
              "${e.flag('done')
                  ? 'Completed'
                  : due != null && due.isBefore(DateTime.now())
                  ? 'Overdue'
                  : 'Upcoming'} · ${store.get(e.project)?.title ?? 'Project'} · ${due?.toString().substring(0, 16) ?? 'No date'}",
              style: TextStyle(fontSize: 11, color: muted),
            ),
            onTap: () {
              final target = store.get(e.text('target'));
              if (target != null) {
                if (target.kind == 'project') {
                  openProject(target.id);
                } else {
                  detail(target);
                }
              }
            },
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') editReminder(existing: e);
                if (v == 'snooze') {
                  store.update(e, {
                    'due': DateTime.now()
                        .add(const Duration(hours: 1))
                        .toUtc()
                        .toIso8601String(),
                    'done': false,
                  });
                }
                if (v == 'delete') remove(e);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit reminder')),
                PopupMenuItem(value: 'snooze', child: Text('Snooze 1 hour')),
                PopupMenuItem(value: 'delete', child: Text('Delete reminder')),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
