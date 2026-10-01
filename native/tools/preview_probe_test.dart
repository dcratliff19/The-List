import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:the_list/store.dart';
import 'package:the_list/services/media.dart';

void main() {
  test('live link preview', () async {
    final dir = await Directory.systemTemp.createTemp('preview-live-');
    final store = Store(dir, database: sqlite3.openInMemory());
    final p = store.create('project', '', {'title': 'Preview test'});
    try {
      for (final url
          in (Platform.environment['PREVIEW_URLS'] ??
                  'https://dart.dev|https://magpul.com/ms1-sling.html')
              .split('|')) {
        final id = store.create('link', p, {'title': 'Test', 'url': url});
        await MediaService(store).preview(store.get(id)!);
        final e = store.get(id)!;
        // ignore: avoid_print
        print(
          '$url => ${e.text('previewStatus')} / ${e.text('previewTitle')} / ${e.text('previewError')}',
        );
        expect(e.text('previewStatus'), 'ready');
      }
    } finally {
      store.dispose();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
