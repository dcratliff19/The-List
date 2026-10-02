part of '../workspace.dart';

extension _WorkspaceFeaturesActivity on _WorkspaceState {
  Future<void> activity() => featureSheet(
    'Activity and conflict review',
    (ctx, update) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in store.unresolvedConflicts(projectId!))
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
                  }
                  store.resolveConflict(
                    row['id'] as String,
                    useAlternative: choice == 'use',
                  );
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
}
