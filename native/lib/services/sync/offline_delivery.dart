part of '../sync.dart';

/// Offline text delivery shares encryption and permission checks with direct sessions.
extension _OfflineDelivery on SyncService {
  Future<void> _offlineDelivery() async {
    if (disposed || offlineBusy) return;
    offlineBusy = true;
    try {
      for (final peer in peers.toList()) {
        if (disposed) return;
        if (store.setting('offline-${peer.project}') != 'on') continue;
        try {
          peer.acceptAccess(await peer.request('access'));
          final sent = ((peer.config['offlineSent'] as List?) ?? [])
              .cast<String>()
              .toSet();
          for (final op
              in store
                  .operations(peer.project)
                  .where(
                    (op) => peer.canSendUpdates && !sent.contains(op['id']),
                  )
                  .take(30)) {
            final payload = await peer.messages.encrypt({
              'protocol': 3,
              'op': op,
            });
            await request(
              peer.config['server'],
              '/rooms/${peer.config['room']}/mailbox',
              token: peer.config['token'],
              method: 'POST',
              body: {'id': op['id'], 'payload': payload},
            );
            sent.add(op['id']);
          }
          peer.config['offlineSent'] = sent.toList();
          final result = await request(
            peer.config['server'],
            '/rooms/${peer.config['room']}/mailbox',
            token: peer.config['token'],
          );
          final ack = <String>[];
          if (disposed) return;
          for (final update in result['updates'] as List) {
            final plain = await peer.messages.decrypt(
              update['payload'] as String,
            );
            if (![2, 3].contains(plain['protocol'])) {
              throw const FormatException(
                'Update both apps to read offline updates.',
              );
            }
            final op = Map<String, dynamic>.from(plain['op']);
            if (op['kind'] == 'reminder') {
              throw const FormatException(
                'Personal reminders cannot be shared.',
              );
            }
            if (!peer.canReceiveUpdates) {
              throw StateError('Read-only peer cannot send updates');
            }
            store.apply([op], scope: peer.project);
            sent.add(op['id']);
            ack.add(update['id']);
          }
          if (ack.isNotEmpty) {
            await request(
              peer.config['server'],
              '/rooms/${peer.config['room']}/mailbox',
              token: peer.config['token'],
              method: 'DELETE',
              body: {'ids': ack},
            );
          }
          peer.config['offlineSent'] = sent.toList();
          peer.config['lastOffline'] = DateTime.now().toUtc().toIso8601String();
          if (!peer.connected) {
            peer.updateStatus(
              'Encrypted offline updates checked · photos wait for direct sync',
            );
          }
          await persist();
        } catch (e) {
          peer.updateStatus('Offline delivery pending: $e');
        }
      }
    } finally {
      offlineBusy = false;
    }
  }
}
