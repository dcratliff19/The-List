import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_list/main.dart';
import 'package:the_list/store.dart';
import 'helpers/fonts.dart';

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('the-list-cleanup-ui-');
    store = Store(directory);
  });

  tearDown(() {
    store.dispose();
    directory.deleteSync(recursive: true);
  });

  testWidgets('global reminders can be snoozed on a read-only project', (
    tester,
  ) async {
    await loadTestFonts();
    final project = store.create('project', '', {'title': 'Shared project'});
    final reminder = store.create('reminder', project, {
      'title': 'Personal reminder',
      'target': project,
      'due': DateTime.now()
          .subtract(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
    });
    store.setProjectAccess(project, 'reader-room', false, 'read');
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(TheListApp(store: store, servicesEnabled: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reminders').first);
    await tester.pumpAndSettle();
    final tile = find.ancestor(
      of: find.text('Personal reminder'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snooze 1 hour'));
    await tester.pumpAndSettle();
    expect(
      DateTime.parse(store.get(reminder)!.text('due')).isAfter(DateTime.now()),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'quick capture from a read-only project saves to the private inbox',
    (tester) async {
      await loadTestFonts();
      final project = store.create('project', '', {'title': 'Shared project'});
      store.setProjectAccess(project, 'reader-room', false, 'read');
      tester.view.physicalSize = const Size(1360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(TheListApp(store: store, servicesEnabled: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shared project').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quick capture'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'URLs (one per line, optional)'),
        'https://example.com/?tag=desk&tag=lamp',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save selected'));
      await tester.pumpAndSettle();
      expect(store.items(project), isEmpty);
      expect(
        store.items(store.inbox()).single.text('url'),
        'https://example.com?tag=desk&tag=lamp',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
