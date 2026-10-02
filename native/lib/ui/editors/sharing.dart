part of '../workspace.dart';

extension _WorkspaceEditorsSharing on _WorkspaceState {
  Future<void> connectionSettings() async {
    final controller = TextEditingController(
      text: SharingConfig.endpoint(store),
    );
    String? error;
    await showEditorDialog<void>(
      context: context,
      controllers: [controller],
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Connection service'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your app owner provides this address. Friends receive it automatically with an invitation.',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Service HTTPS address',
                    errorText: error,
                  ),
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
              onPressed: () async {
                try {
                  final value = controller.text.trim();
                  SyncService.serverUri(value);
                  await sync.request(value, '/health');
                  store.setSetting('sharing-server', value);
                  if (context.mounted) Navigator.pop(context);
                  store.touch();
                  message('Connection service saved. Invitations are ready.');
                } catch (_) {
                  if (context.mounted) {
                    update(
                      () => error =
                          'Could not reach this service. Check its address.',
                    );
                  }
                }
              },
              child: const Text('Check & save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> sharing() async {
    final server = SharingConfig.endpoint(store);
    final code = TextEditingController();
    String? invitation, error;
    bool working = false;
    String access = 'update';
    await showEditorDialog<void>(
      context: context,
      controllers: [code],
      builder: (context) => StatefulBuilder(
        builder: (context, update) => ListenableBuilder(
          listenable: sync,
          builder: (context, _) => AlertDialog(
            title: const Text('Good ideas travel together.'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Share this project directly with a friend. Both apps need to be open. Project contents are encrypted between your devices.',
                      style: TextStyle(fontSize: 12, height: 1.7),
                    ),
                    const SizedBox(height: 18),
                    if (server.isEmpty)
                      const Text(
                        'Sharing is not configured for this installation yet. A connection service must be set up once by the app owner.',
                        style: TextStyle(fontSize: 12),
                      ),
                    const SizedBox(height: 14),
                    if (project != null && store.canManageSharing(projectId!))
                      DropdownButtonFormField<String>(
                        initialValue: access,
                        decoration: const InputDecoration(
                          labelText: 'Invitation access',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'read',
                            child: Text('Read only'),
                          ),
                          DropdownMenuItem(
                            value: 'update',
                            child: Text('Can update'),
                          ),
                        ],
                        onChanged: working
                            ? null
                            : (v) => update(() => access = v!),
                      ),
                    const SizedBox(height: 12),
                    if (project != null && store.canManageSharing(projectId!))
                      FilledButton.icon(
                        onPressed: working || server.isEmpty
                            ? null
                            : () async {
                                update(() => working = true);
                                try {
                                  final value = await sync.invite(
                                    projectId!,
                                    server,
                                    access: access,
                                  );
                                  if (context.mounted) {
                                    update(() => invitation = value);
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    update(() => error = e.toString());
                                  }
                                } finally {
                                  if (context.mounted) {
                                    update(() => working = false);
                                  }
                                }
                              },
                        icon: const Icon(Icons.person_add_alt, size: 17),
                        label: const Text('Create invitation'),
                      ),
                    if (invitation != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'One use · expires in 15 minutes',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              invitation!,
                              maxLines: 3,
                              style: const TextStyle(fontSize: 10),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: invitation!),
                                );
                                message(
                                  'Invitation copied. Send it only to your friend.',
                                );
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('Copy invitation'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    TextField(
                      controller: code,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Have an invitation?',
                        hintText: 'Paste thelist:…',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: working
                          ? null
                          : () async {
                              update(() => working = true);
                              try {
                                final pid = await sync.join(code.text);
                                if (mounted) openProject(pid);
                                if (context.mounted) update(() => code.clear());
                              } catch (e) {
                                if (context.mounted) {
                                  update(() => error = e.toString());
                                }
                              } finally {
                                if (context.mounted) {
                                  update(() => working = false);
                                }
                              }
                            },
                      icon: const Icon(Icons.link, size: 17),
                      label: const Text('Join project'),
                    ),
                    if (working)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: LinearProgressIndicator(),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (sync.error != null)
                      Text(sync.error!, style: const TextStyle(fontSize: 11)),
                    for (final peer in sync.peers.where(
                      (p) => projectId == null || p.project == projectId,
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          peer.connected ? Icons.sync : Icons.sync_problem,
                          size: 20,
                        ),
                        title: Text(
                          '${peer.config['peerName'] ?? 'Friend'} · ${peer.status}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          peer.config['host'] == true
                              ? 'You invited this device · ${peer.config['access'] == 'read' ? 'Read only' : 'Can update'}'
                              : 'You joined this project · ${peer.config['access'] == 'read' ? 'Read only' : 'Can update'}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        trailing: Wrap(
                          children: [
                            if (peer.config['host'] == true)
                              PopupMenuButton<String>(
                                tooltip: 'Change access',
                                icon: const Icon(
                                  Icons.admin_panel_settings_outlined,
                                  size: 18,
                                ),
                                onSelected: (v) =>
                                    act(() => sync.changeAccess(peer, v)),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'read',
                                    child: Text('Read only'),
                                  ),
                                  PopupMenuItem(
                                    value: 'update',
                                    child: Text('Can update'),
                                  ),
                                ],
                              ),
                            IconButton(
                              tooltip: 'Reconnect',
                              onPressed: () => act(() => peer.connect()),
                              icon: const Icon(Icons.refresh, size: 18),
                            ),
                            IconButton(
                              tooltip: 'Stop sharing with this device',
                              onPressed: () => act(() => sync.disconnect(peer)),
                              icon: const Icon(Icons.link_off, size: 18),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    const Text(
                      'Disconnecting stops this pairing. Copies already received by your friend remain on their device. Reminders stay personal.',
                      style: TextStyle(fontSize: 10, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
