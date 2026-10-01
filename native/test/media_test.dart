import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:image/image.dart' as img;
import 'package:the_list/store.dart';
import 'package:the_list/services/media.dart';

class FixtureMedia extends MediaService {
  final Future<PreviewResource> Function(Uri) load;
  FixtureMedia(super.store, this.load);
  @override
  Future<PreviewResource> fetchResource(
    Uri uri,
    int maxBytes, {
    bool headOnly = false,
  }) => load(uri);
}

void main() {
  late Store store;
  late Directory dir;
  late String id;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('preview-test-');
    store = Store(dir, database: sqlite3.openInMemory());
    final p = store.create('project', '', {'title': 'Test'});
    id = store.create('link', p, {
      'title': 'My title',
      'body': 'My context',
      'url': 'https://example.com/start',
    });
  });
  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });
  PreviewResource page(String source, String address) => PreviewResource(
    Uint8List.fromList(utf8.encode(source)),
    Uri.parse(address),
    'text/html',
  );
  test(
    'Twitter preview uses redirect destination and retains user prose',
    () async {
      final seen = <Uri>[];
      final media = FixtureMedia(store, (uri) async {
        seen.add(uri);
        if (seen.length == 1) {
          return page(
            '<head><meta name="twitter:title" content="Page title"><meta name="description" content="Page description"><meta name="twitter:image" content="image.png"></head>',
            'https://example.com/products/item/',
          );
        }
        return PreviewResource(
          Uint8List.fromList(img.encodePng(img.Image(width: 20, height: 20))),
          uri,
          'image/png',
        );
      });
      await media.preview(store.get(id)!);
      expect(
        seen.last.toString(),
        'https://example.com/products/item/image.png',
      );
      expect(store.get(id)!.text('previewStatus'), 'ready');
      expect(store.get(id)!.text('previewDescription'), 'Page description');
      expect(store.get(id)!.title, 'My title');
      expect(store.get(id)!.text('body'), 'My context');
      expect(await store.blob(store.get(id)!.text('photo')).exists(), isTrue);
    },
  );
  test('blocked page exposes reason and retry recovers', () async {
    var fail = true;
    final media = FixtureMedia(store, (uri) async {
      if (fail) throw const HttpException('Website returned HTTP 403');
      return page(
        '<head><title>A readable title</title></head>',
        uri.toString(),
      );
    });
    await media.preview(store.get(id)!);
    expect(store.get(id)!.text('previewError'), contains('403'));
    fail = false;
    await media.preview(store.get(id)!, force: true);
    expect(store.get(id)!.text('previewStatus'), 'no-image');
    expect(store.get(id)!.text('previewError'), '');
    expect(store.get(id)!.text('previewTitle'), 'A readable title');
  });
  test('stale results cannot overwrite a changed URL', () async {
    final response = Completer<PreviewResource>();
    final media = FixtureMedia(store, (_) => response.future);
    final task = media.preview(store.get(id)!);
    store.update(store.get(id)!, {'url': 'https://other.example/'});
    response.complete(
      page('<head><title>Old page</title></head>', 'https://example.com/start'),
    );
    await task;
    expect(store.get(id)!.text('previewTitle'), '');
  });
  test('explicit retry works with automatic previews disabled', () async {
    store.setSetting('previews', 'off');
    var calls = 0;
    final media = FixtureMedia(store, (uri) async {
      calls++;
      return page('<head><title>Title</title></head>', uri.toString());
    });
    await media.preview(store.get(id)!);
    expect(calls, 0);
    await media.preview(store.get(id)!, force: true);
    expect(calls, 1);
  });

  test('photo imports accept PNG and reject unsupported GIF data', () async {
    final media = MediaService(store);
    final image = img.Image(width: 10, height: 10);
    final hash = await media.importPhoto(
      Uint8List.fromList(img.encodePng(image)),
    );
    expect(await store.blob(hash).exists(), isTrue);
    await expectLater(
      media.importPhoto(Uint8List.fromList(img.encodeGif(image))),
      throwsFormatException,
    );
  });
}
