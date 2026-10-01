import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_list/main.dart';
import 'package:the_list/store.dart';
import 'helpers/fonts.dart';

void main() {
  testWidgets('planning, capture review and Today work on desktop and phone', (
    tester,
  ) async {
    await loadTestFonts();
    final dir = Directory.systemTemp.createTempSync('the-list-expansion-ui-');
    final store = Store(dir);
    store.setSetting('display-name', 'Alex');
    final pid = store.create('project', '', {
      'title': 'A calmer workspace',
      'description': 'Thoughtful upgrades for the place where ideas happen.',
      'budget': '500',
      'budgetCurrency': 'USD',
      'label': 'Home',
    });
    final lamp = store.create('link', pid, {
      'title': 'The reading lamp',
      'url': 'https://example.com/lamp',
      'body': 'Warm light, a compact base, and an adjustable arm.',
      'price': '89',
      'currency': 'USD',
      'quantity': 2,
      'purchaseStatus': 'chosen',
      'comparison': 'Lighting',
      'tags': 'lighting desk',
      'assignee': 'Alex',
      'boardStatus': 'todo',
    });
    store.create('link', pid, {
      'title': 'A different perspective',
      'url': 'https://example.com/alternative',
      'price': '120',
      'currency': 'USD',
      'comparison': 'Lighting',
      'tags': 'lighting inspiration',
    });
    store.create('check', pid, {
      'title': 'Measure the desk depth',
      'target': lamp,
      'done': true,
    });
    store.create('check', pid, {
      'title': 'Check the bulb temperature',
      'target': lamp,
      'done': false,
    });
    store.create('comment', pid, {
      'body': 'The warmer finish would work well beside the window.',
      'target': lamp,
    });
    store.create('reminder', pid, {
      'title': 'Review the shortlist',
      'due': DateTime.now()
          .subtract(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
      'repeat': 'weekly',
    });
    tester.view.physicalSize = const Size(1360, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(TheListApp(store: store, servicesEnabled: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A calmer workspace').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Remaining 322.00'), findsOneWidget);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/17-planning-workspace.png'),
      );
    }
    await tester.tap(find.text('The reading lamp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planning & comments'));
    await tester.pumpAndSettle();
    expect(find.text('Check the bulb temperature'), findsOneWidget);
    await tester.tap(find.text('Check the bulb temperature'));
    await tester.pumpAndSettle();
    expect(
      store.childrenOf(lamp, 'check').every((e) => e.flag('done')),
      isTrue,
    );
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/18-checklists-comments.png'),
      );
    }
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare purchase options'));
    await tester.pumpAndSettle();
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/19-comparison.png'),
      );
    }
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import links'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'URLs (one per line, optional)'),
      'https://example.com/lamp?utm_source=test\nhttps://example.com/new',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Already saved'), findsOneWidget);
    expect(store.items(pid).where((e) => e.kind == 'link').length, 2);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/20-capture-review.png'),
      );
    }
    await tester.tap(find.text('Save selected'));
    await tester.pumpAndSettle();
    expect(store.items(pid).where((e) => e.kind == 'link').length, 3);
    await tester.tap(find.text('Today').first);
    await tester.pumpAndSettle();
    expect(find.text('Review the shortlist'), findsOneWidget);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/21-today.png'),
      );
    }
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/22-today-phone.png'),
      );
    }
    tester.view.physicalSize = const Size(1360, 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('A calmer workspace').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project comments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add comment'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Comment'),
      'Let us review the shortlist together.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      store.childrenOf(pid, 'comment').single.text('body'),
      'Let us review the shortlist together.',
    );
    expect(store.unreadComments, 0);
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    final peer = Store(Directory('${dir.path}/peer')..createSync());
    peer.setSetting('display-name', 'Jordan');
    peer.apply(store.operations(pid), scope: pid);
    peer.addComment(
      peer.get(pid)!,
      'The shortlist looks good. Can we compare the two lamps?',
    );
    store.apply(peer.operations(pid), scope: pid);
    peer.dispose();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox').first);
    await tester.pumpAndSettle();
    expect(find.text('Shared comments · 1 unread'), findsOneWidget);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/25-shared-comments-inbox.png'),
      );
    }
    await tester.tap(
      find.text('The shortlist looks good. Can we compare the two lamps?'),
    );
    await tester.pumpAndSettle();
    expect(store.unreadComments, 0);
    expect(find.text('Let us review the shortlist together.'), findsOneWidget);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/26-project-conversation.png'),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    dir.deleteSync(recursive: true);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
