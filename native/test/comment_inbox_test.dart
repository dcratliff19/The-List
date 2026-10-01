import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_list/store.dart';

void main() {
  test(
    'project and item comments fan out, exclude their author and retain read state',
    () async {
      final root = Directory.systemTemp.createTempSync('the-list-comments-');
      final stores = List.generate(
        3,
        (i) => Store(Directory('${root.path}/$i')..createSync()),
      );
      final a = stores[0], b = stores[1], c = stores[2];
      try {
        // Equal display names must not suppress a different participant.
        for (final store in stores) {
          store.setSetting('display-name', 'Alex');
        }
        final pid = a.create('project', '', {'title': 'Shared project'});
        final item = a.create('note', pid, {'title': 'Shared idea'});
        b.apply(a.operations(pid), scope: pid);
        c.apply(a.operations(pid), scope: pid);
        final projectComment = b.addComment(b.get(pid)!, 'Project discussion');
        final itemComment = b.addComment(b.get(item)!, 'Item discussion');
        expect(b.commentInbox, isEmpty);
        a.apply(b.operations(pid), scope: pid);
        // C is paired to A; the author identity must survive this relay.
        c.apply(a.operations(pid), scope: pid);
        expect(a.commentInbox.map((e) => e.id).toSet(), {
          projectComment,
          itemComment,
        });
        expect(c.unreadComments, 2);
        c.markCommentRead(projectComment);
        c.apply(a.operations(pid), scope: pid);
        expect(c.commentInbox.length, 2);
        expect(c.unreadComments, 1);
        b.apply(c.operations(pid), scope: pid);
        expect(b.commentInbox, isEmpty);
        final remoteReply = c.addComment(c.get(pid)!, 'Reply');
        a.apply(c.operations(pid), scope: pid);
        b.apply(a.operations(pid), scope: pid);
        expect(b.commentInbox.single.id, remoteReply);
        expect(c.commentInbox.any((e) => e.id == remoteReply), isFalse);
        a.update(a.get(item)!, {'deleted': true});
        c.apply(a.operations(pid), scope: pid);
        expect(c.commentInbox.map((e) => e.id), [projectComment]);
        c.dispose();
        stores[2] = Store(Directory('${root.path}/2'));
        expect(stores[2].unreadComments, 0);
        stores[2].markCommentRead(projectComment, read: false);
        expect(stores[2].unreadComments, 1);
      } finally {
        for (final store in stores) {
          store.dispose();
        }
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'restoring a backup does not manufacture shared comment notifications',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'the-list-comments-restore-',
      );
      final a = Store(root),
          b = Store(Directory('${root.path}/b')..createSync());
      try {
        final pid = a.create('project', '', {'title': 'Project'});
        expect(() => a.addComment(a.get(pid)!, '  '), throwsFormatException);
        a.addComment(a.get(pid)!, 'Saved comment');
        final backup = File('${root.path}/backup.thelist')
          ..writeAsStringSync(await a.exportData());
        await b.importFrom(backup);
        expect(
          b.childrenOf(pid, 'comment').single.text('body'),
          'Saved comment',
        );
        expect(b.commentInbox, isEmpty);
      } finally {
        a.dispose();
        b.dispose();
        root.deleteSync(recursive: true);
      }
    },
  );
}
