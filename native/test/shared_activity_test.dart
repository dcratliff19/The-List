import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_list/store.dart';
import 'package:the_list/services/sync.dart';

void main() {
  test(
    'activity fans out, excludes self and previews, deduplicates and persists',
    () {
      final root = Directory.systemTemp.createTempSync('activity-');
      final a = Store(Directory('${root.path}/a')..createSync());
      var b = Store(Directory('${root.path}/b')..createSync());
      final c = Store(Directory('${root.path}/c')..createSync());
      try {
        final pid = a.create('project', '', {'title': 'Shared ideas'});
        b.apply(a.operations(pid), scope: pid);
        b.markActivityRead();
        final note = b.create('note', pid, {'title': 'From a friend'});
        expect(b.unreadActivity, 0);
        a.apply(b.operations(pid), scope: pid);
        expect(a.sharedActivity.single['entity'], note);
        c.apply(a.operations(pid), scope: pid);
        expect(c.sharedActivity.any((e) => e['entity'] == note), isTrue);
        a.markActivityRead();
        a.apply(b.operations(pid), scope: pid);
        expect(a.unreadActivity, 0);
        a.update(a.get(note)!, {'body': 'Owner reply'});
        b.apply(a.operations(pid), scope: pid);
        expect(b.unreadActivity, 1);
        a.update(a.get(note)!, {
          'previewStatus': 'ready',
          'previewTitle': 'Metadata',
        });
        b.apply(a.operations(pid), scope: pid);
        expect(b.unreadActivity, 1);
        a.update(a.get(note)!, {'deleted': true});
        b.apply(a.operations(pid), scope: pid);
        expect(b.unreadActivity, 2);
        b.dispose();
        b = Store(Directory('${root.path}/b'));
        expect(b.unreadActivity, 2);
        b.markActivityRead();
        expect(b.unreadActivity, 0);
      } finally {
        a.dispose();
        b.dispose();
        c.dispose();
        root.deleteSync(recursive: true);
      }
    },
  );
  test(
    'read-only survives restart and blocks writes and hostile direct messages',
    () async {
      final root = Directory.systemTemp.createTempSync('permissions-');
      var store = Store(root);
      final pid = store.create('project', '', {'title': 'Read only'});
      final note = store.create('note', pid, {'title': 'Original'});
      store.setProjectAccess(pid, 'guest-room', false, 'read');
      expect(
        () => store.update(store.get(note)!, {'title': 'Forbidden'}),
        throwsStateError,
      );
      expect(
        () => store.create('note', pid, {'title': 'Forbidden'}),
        throwsStateError,
      );
      expect(
        () => store.addComment(store.get(pid)!, 'Forbidden'),
        throwsStateError,
      );
      store.create('reminder', pid, {'title': 'Personal reminder'});
      store.dispose();
      store = Store(root);
      expect(store.canEdit(pid), isFalse);
      final backup = File('${root.path}/backup.thelist');
      await store.exportTo(backup);
      await expectLater(store.importFrom(backup), throwsStateError);
      final sync = SyncService(store);
      final stale = PeerSession(sync, {
        'room': 'guest-room',
        'project': pid,
        'host': false,
        'access': 'update',
      });
      expect(stale.canSendUpdates, isFalse);
      expect(stale.config['access'], 'read');
      final peer = PeerSession(sync, {
        'project': pid,
        'host': true,
        'access': 'read',
      });
      peer.compatible = true;
      await expectLater(
        peer.receive({'type': 'op', 'op': store.operations(pid).first}),
        throwsStateError,
      );
      expect(store.canManageSharing(pid), isFalse);
      store.setProjectAccess(pid, 'guest-room', false, 'update');
      store.update(store.get(note)!, {'title': 'Allowed'});
      expect(store.get(note)!.title, 'Allowed');
      sync.dispose();
      store.dispose();
      root.deleteSync(recursive: true);
    },
  );
}
