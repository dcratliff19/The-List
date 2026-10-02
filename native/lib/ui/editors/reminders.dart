part of '../workspace.dart';

extension _WorkspaceEditorsReminders on _WorkspaceState {
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
    await showEditorDialog<void>(
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
}
