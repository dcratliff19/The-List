import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_list/main.dart';
import 'package:the_list/store.dart';
import 'helpers/fonts.dart';

void main() {
  testWidgets('feed opens updates and read-only project presents access clearly', (
    tester,
  ) async {
    await loadTestFonts();
    final root = Directory.systemTemp.createTempSync('feed-ui-');
    final local = Store(Directory('${root.path}/local')..createSync());
    final friend = Store(Directory('${root.path}/friend')..createSync());
    local.setSetting('sharing-server', 'http://127.0.0.1:5174');
    friend.setSetting('display-name', 'Jamie');
    final pid = friend.create('project', '', {
      'title': 'A calmer workspace',
      'description': 'A few thoughtful upgrades, collected together.',
      'label': 'Home',
    });
    local.apply(friend.operations(pid), scope: pid);
    local.markActivityRead();
    final link = friend.create('link', pid, {
      'title': 'The reading lamp',
      'url': 'https://example.com/lamp',
      'body': 'Warm light for late-night ideas.',
      'price': '89',
      'currency': 'USD',
      'tags': 'lighting desk',
    });
    friend.addComment(
      friend.get(pid)!,
      'Found a warmer finish that would look great beside the window. What do you think?',
    );
    friend.update(friend.get(link)!, {'price': '79'});
    local.apply(friend.operations(pid), scope: pid);
    local.setProjectAccess(pid, 'test-room', false, 'read');
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(TheListApp(store: local, servicesEnabled: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(find.text('Jamie · Updated pricing'), findsOneWidget);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/27-shared-activity-feed.png'),
      );
    }
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    expect(local.unreadActivity, 0);
    await tester.tap(find.text('Jamie · Added a link'));
    await tester.pumpAndSettle();
    final edit = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Edit'),
    );
    expect(edit.onPressed, isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Read-only project'), findsOneWidget);
    expect(find.text('Add to list'), findsNothing);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/28-read-only-project.png'),
      );
    }
    // Separate owner project demonstrates invitation choices without network access.
    final own = local.create('project', '', {'title': 'Weekend ideas'});
    local.touch();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekend ideas').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Invitation access'), findsOneWidget);
    await tester.tap(find.text('Can update').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read only').last);
    await tester.pumpAndSettle();
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/29-sharing-access.png'),
      );
    }
    expect(local.canManageSharing(own), isTrue);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(430, 932);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(find.text('Jamie · Updated pricing'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/30-feed-phone.png'),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    local.dispose();
    friend.dispose();
    root.deleteSync(recursive: true);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
