import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as image;
import 'package:the_list/store.dart';
import 'package:the_list/main.dart';
import 'package:the_list/services/media.dart';
import 'package:the_list/services/sync.dart';

// Override for an isolated test server without disturbing active user pairings.
const signalUrl = String.fromEnvironment(
  'THE_LIST_TEST_SIGNAL_URL',
  defaultValue: 'http://127.0.0.1:5174',
);

Future<void> until(bool Function() predicate, String reason) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) throw StateError(reason);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real native WebRTC exchanges edits and photos and reconnects', (
    tester,
  ) async {
    final da = await Directory.systemTemp.createTemp('the-list-peer-a-'),
        db = await Directory.systemTemp.createTemp('the-list-peer-b-');
    final a = Store(da), b = Store(db);
    final sa = SyncService(a), sb = SyncService(b);
    try {
      final pid = a.create('project', '', {
        'title': 'Shared native test',
        'description': 'Two encrypted peers. No central project database.',
      });
      final id = a.create('note', pid, {
        'title': 'A shared idea',
        'body': 'First version',
      });
      await tester.pumpWidget(TheListApp(store: a, servicesEnabled: false));
      await tester.pumpAndSettle();
      final invitation = await sa.invite(pid, signalUrl, access: 'read');
      await sb.join(invitation);
      await until(
        () => b.get(id) != null,
        'Initial project did not arrive: ${sa.peers.first.status} / ${sb.peers.first.status}',
      );
      expect(b.get(id)!.text('body'), 'First version');
      expect(b.canEdit(pid), isFalse);
      expect(
        () => b.update(b.get(id)!, {'title': 'Forbidden'}),
        throwsStateError,
      );
      await expectLater(
        sa.peers.first.receive({'type': 'op', 'op': a.operations(pid).first}),
        throwsStateError,
      );
      a.update(a.get(id)!, {'body': 'Visible to a reader'});
      await until(
        () => b.get(id)!.text('body') == 'Visible to a reader',
        'Read-only recipient did not receive owner updates',
      );
      await sa.changeAccess(sa.peers.first, 'update');
      await until(() => b.canEdit(pid), 'Update access did not propagate');
      a.update(a.get(id)!, {'body': 'From Alice'});
      b.update(b.get(id)!, {'title': 'From Bob'});
      await until(
        () =>
            b.get(id)!.text('body') == 'From Alice' &&
            a.get(id)!.title == 'From Bob',
        'Concurrent edits did not converge',
      );
      final projectComment = a.addComment(
        a.get(pid)!,
        'Shared project comment',
      );
      await until(
        () => b.commentInbox.any((e) => e.id == projectComment),
        'Project comment did not enter recipient Inbox',
      );
      expect(a.commentInbox.any((e) => e.id == projectComment), isFalse);
      b.markCommentRead(projectComment);
      final itemReply = b.addComment(b.get(id)!, 'Reply on the list item');
      await until(
        () => a.commentInbox.any((e) => e.id == itemReply),
        'List item reply did not enter recipient Inbox',
      );
      expect(b.commentInbox.any((e) => e.id == itemReply), isFalse);
      final pixels = image.Image(width: 400, height: 300);
      for (var y = 0; y < 300; y++) {
        for (var x = 0; x < 400; x++) {
          pixels.setPixelRgb(
            x,
            y,
            (x * 17 + y * 31) % 256,
            (x * 79 + y * 11) % 256,
            (x * 7 + y * 61) % 256,
          );
        }
      }
      final photo = await MediaService(
        a,
      ).importPhoto(Uint8List.fromList(image.encodePng(pixels)));
      final photoId = a.create('photo', pid, {
        'title': 'Transfer test',
        'photo': photo,
        'body': 'A generated test fixture',
      });
      await until(
        () => b.get(photoId) != null && b.blob(photo).existsSync(),
        'Photo did not transfer: ${sb.peers.first.status}',
      );
      expect(
        await b.blob(photo).readAsBytes(),
        await a.blob(photo).readAsBytes(),
      );
      await sb.peers.first.close();
      a.update(a.get(id)!, {'body': 'Offline change survives'});
      await sb.peers.first.connect();
      await until(
        () => b.get(id)!.text('body') == 'Offline change survives',
        'Reconnect did not deliver queued edit: ${sa.peers.first.status} / ${sb.peers.first.status}',
      );
      a.update(a.get(photoId)!, {'deleted': true});
      await until(
        () => b.get(photoId)!.deleted,
        'Deletion did not synchronize',
      );
      expect(
        a.sharedActivity.any(
          (e) => (e['fields'] as Map)['title'] == 'From Bob',
        ),
        isTrue,
      );
      await sa.changeAccess(sa.peers.first, 'read');
      await until(
        () => !b.canEdit(pid),
        'Read-only downgrade did not propagate',
      );
      expect(() => b.addComment(b.get(pid)!, 'Forbidden'), throwsStateError);
      await sa.peers.first.close();
      await sb.peers.first.close();
      a.setSetting('offline-$pid', 'on');
      b.setSetting('offline-$pid', 'on');
      final offlineId = a.create('note', pid, {
        'title': 'Mailbox-only update',
        'body': 'Encrypted delivery without a connected peer',
      });
      a.create('reminder', pid, {
        'title': 'Private reminder',
        'due': DateTime.now().toUtc().toIso8601String(),
      });
      final offlineComment = a.addComment(
        a.get(pid)!,
        'A comment delivered asynchronously',
      );
      await sa.offlineDelivery();
      await sb.offlineDelivery();
      expect(
        b.get(offlineId)?.text('body'),
        'Encrypted delivery without a connected peer',
      );
      expect(b.commentInbox.any((e) => e.id == offlineComment), isTrue);
      expect(b.commentUnread(projectComment), isFalse);
      expect(b.items(pid).where((e) => e.kind == 'reminder'), isEmpty);
      expect(sa.peers.first.connected, isFalse);
      await sa.disconnect(sa.peers.first);
      await until(
        () => !sb.peers.first.connected,
        'Revocation did not close the peer channel',
      );
    } finally {
      for (final peer in [...sa.peers]) {
        await peer.close();
      }
      for (final peer in [...sb.peers]) {
        await peer.close();
      }
      await sa.vault.delete(key: sa.vaultKey);
      await sb.vault.delete(key: sb.vaultKey);
      sa.dispose();
      sb.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      a.dispose();
      b.dispose();
      await da.delete(recursive: true);
      await db.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
