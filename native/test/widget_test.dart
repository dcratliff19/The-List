import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:the_list/main.dart';
import 'package:the_list/store.dart';
import 'helpers/fonts.dart';

void main() {
  testWidgets('native workspace, editors, persistence and phone layout', (
    tester,
  ) async {
    await loadTestFonts();
    final dir = Directory.systemTemp.createTempSync('the-list-ui-');
    final store = Store(dir, database: sqlite3.openInMemory());
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(TheListApp(store: store, servicesEnabled: false));
    await tester.pumpAndSettle();
    expect(find.text('Good things start with a project.'), findsOneWidget);
    await tester.tap(find.text('Explore an example project'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(store.projects.length, 1);
    expect(store.items(store.projects.first.id).length, 4);
    final pricedLink = store
        .items(store.projects.first.id)
        .firstWhere((e) => e.kind == 'link');
    store.update(pricedLink, {'price': '19.95', 'currency': 'USD'});
    await tester.pumpAndSettle();
    expect(find.text('Project total: USD 19.95'), findsOneWidget);
    expect(find.text('USD 19.95'), findsOneWidget);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/15-project-prices.png'),
      );
    }

    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/01-native-workspace.png'),
      );
    }
    await tester.tap(find.text('Add to list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'A real saved note',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Your note'),
      'Remember the quiet corner by the window.',
    );
    await tester.tap(find.text('Save to list'));
    await tester.pumpAndSettle();
    expect(
      store
          .items(store.projects.first.id)
          .any((e) => e.title == 'A real saved note'),
      isTrue,
    );
    await tester.tap(find.text('A real saved note'));
    await tester.pumpAndSettle();
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/02-native-note-detail.png'),
      );
    }
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();
    final card = store
        .items(store.projects.first.id)
        .firstWhere((e) => e.title == 'A real saved note');
    expect(find.text('To do  0'), findsOneWidget);
    expect(find.text('A real saved note'), findsNothing);
    await tester.tap(find.text('Add existing item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A real saved note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move A real saved note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to In progress'));
    await tester.pumpAndSettle();
    expect(store.get(card.id)!.text('boardStatus'), 'doing');
    expect(find.text('In progress  1'), findsOneWidget);
    final drag = await tester.startGesture(
      tester.getCenter(find.text('A real saved note')),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await drag.moveTo(
      tester.getCenter(find.byKey(const ValueKey('column-done'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await drag.up();
    await tester.pumpAndSettle();
    expect(store.get(card.id)!.text('boardStatus'), 'done');
    expect(find.text('Done  1'), findsOneWidget);

    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/14-project-kanban.png'),
      );
    }
    await tester.tap(find.byTooltip('Move A real saved note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from board'));
    await tester.pumpAndSettle();
    expect(find.text('A real saved note'), findsNothing);
    expect(store.get(card.id)!.deleted, isFalse);
    await tester.tap(find.text('New card'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Explicit board card',
    );
    await tester.tap(find.text('Save to list'));
    await tester.pumpAndSettle();
    expect(find.text('Explicit board card'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1360, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Daily Excel backup'));
    await tester.tap(find.text('Daily Excel backup'));
    await tester.pumpAndSettle();
    expect(find.text('Save & back up now'), findsOneWidget);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/16-excel-backup-settings.png'),
      );
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Accent color'));
    await tester.tap(find.text('Accent color'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Hex color'), 'oops');
    await tester.pump();
    await tester.tap(find.text('Apply color'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter six hex digits, for example #008577.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Hex color'),
      '#008577',
    );
    await tester.pump();
    await tester.tap(find.text('Apply color'));
    await tester.pumpAndSettle();
    expect(store.setting('accent'), '008577');
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme
          .primary,
      ColorScheme.fromSeed(seedColor: const Color(0xff008577)).primary,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/12-teal-theme.png'),
      );
    }
    final pid = store.projects.first.id;
    final tagged = store.create('note', pid, {
      'title': 'Tagged research',
      'tags': 'alpha beta,gamma',
    });
    expect(store.get(tagged)!.tags, ['alpha', 'beta', 'gamma']);
    expect(Entry.parseTags('alpha  ALPHA #beta,gamma'), [
      'alpha',
      'beta',
      'gamma',
    ]);
    final reminder = store.create('reminder', pid, {
      'title': 'Review saved ideas',
      'target': tagged,
      'due': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toUtc()
          .toIso8601String(),
      'done': false,
    });
    await tester.pumpAndSettle();
    expect(find.text('1 reminder need attention'), findsOneWidget);
    await tester.tap(find.text('All projects'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search your list'),
      '#beta',
    );
    await tester.pumpAndSettle();
    expect(find.text('Tagged research'), findsOneWidget);
    await tester.tap(find.text('1 reminder need attention'));
    await tester.pumpAndSettle();
    expect(find.text('Review saved ideas'), findsOneWidget);
    expect(find.textContaining('Overdue ·'), findsOneWidget);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/13-missed-reminders.png'),
      );
    }
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(store.get(reminder)!.flag('done'), isTrue);
    expect(find.textContaining('Completed ·'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/03-native-phone-layout.png'),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    dir.deleteSync(recursive: true);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
