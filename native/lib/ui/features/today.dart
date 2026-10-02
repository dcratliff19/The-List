part of '../workspace.dart';

extension _WorkspaceFeaturesToday on _WorkspaceState {
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
}
