import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:the_list/store.dart';
import 'package:the_list/services/media.dart';

void main() {
  test('prepare researched accessory collection', () async {
    final dir = await Directory.systemTemp.createTemp('collection-preview-');
    final store = Store(dir, database: sqlite3.openInMemory());
    final file = File('../collections/AP5SD-build.thelist');
    try {
      await store.importFrom(file);
      final media = MediaService(store);
      for (final entry in store.entries.where((e) => e.kind == 'link')) {
        await media.preview(entry, force: true);
        // ignore: avoid_print
        print('${entry.title}: ${store.get(entry.id)!.text('previewStatus')}');
      }
      await store.exportTo(file);
      expect(store.projects.single.title, 'AP5SD build');
      expect(store.entries.where((e) => e.kind == 'link').length, 8);
    } finally {
      store.dispose();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
