import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:the_list/main.dart';
import 'package:the_list/store.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android native project and note workflow', (tester) async {
    final dir = await Directory.systemTemp.createTemp('the-list-android-');
    final store = Store(dir);
    try {
      await tester.pumpWidget(TheListApp(store: store, servicesEnabled: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explore an example project'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(store.projects.length, 1);
      expect(tester.takeException(), isNull);
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('06-android-project');
      }
      await tester.tap(find.text('Add to list'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Note'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'A note from Android',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Your note'),
        'Saved locally, ready to share with the project.',
      );
      await tester.ensureVisible(find.text('Save to list'));
      await tester.tap(find.text('Save to list'));
      await tester.pumpAndSettle();
      expect(
        store
            .items(store.projects.first.id)
            .any((e) => e.title == 'A note from Android'),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      if (Platform.isAndroid) {
        await binding.takeScreenshot('07-android-saved-note');
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      await dir.delete(recursive: true);
    }
  });
}
