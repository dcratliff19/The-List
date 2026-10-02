part of '../workspace.dart';

extension _WorkspaceFeaturesForms on _WorkspaceState {
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
}
