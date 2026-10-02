import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:html/parser.dart' as html;
import '../store.dart';
import 'media/preview_fetcher.dart';

export 'media/preview_fetcher.dart' show PreviewResource;

/// Normalizes imported photos and fetches bounded, public-network link previews.
class MediaService {
  final Store store;
  final PreviewFetcher _fetcher;
  MediaService(this.store, {PreviewFetcher? fetcher})
    : _fetcher = fetcher ?? PreviewFetcher();
  Future<String> importPhoto(Uint8List bytes) async {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Please choose a photo smaller than 20 MB.');
    }
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null ||
        (decoder is! img.JpegDecoder &&
            decoder is! img.PngDecoder &&
            decoder is! img.WebPDecoder) ||
        info.width * info.height > 40000000) {
      throw const FormatException(
        'Choose a JPEG, PNG or WebP photo under 40 megapixels.',
      );
    }
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('This image could not be opened.');
    }
    final oriented = img.bakeOrientation(image);
    final resized = oriented.width > 2000 || oriented.height > 2000
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? 2000 : null,
            height: oriented.height > oriented.width ? 2000 : null,
          )
        : oriented;
    resized.exif.clear();
    final data = img.encodeJpg(resized, quality: 86);
    final hash = sha256.convert(data).toString();
    final f = store.blob(hash);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(data, flush: true);
    return hash;
  }

  static bool publicAddress(InternetAddress ip) =>
      PreviewFetcher.publicAddress(ip);
  static Uri webUri(String text) => PreviewFetcher.webUri(text);

  Future<PreviewResource> fetchResource(
    Uri uri,
    int maxBytes, {
    bool headOnly = false,
  }) => _fetcher.fetchResource(uri, maxBytes, headOnly: headOnly);

  Future<Uint8List> fetch(Uri uri, int maxBytes) async =>
      (await fetchResource(uri, maxBytes)).bytes;

  final Map<String, Future<void>> _active = {};
  Future<void> preview(Entry entry, {bool force = false}) {
    if (!store.canEdit(entry.project) ||
        entry.kind != 'link' ||
        (!force && store.setting('previews') == 'off')) {
      return Future.value();
    }
    final key = '${entry.id}|${entry.text('url')}';
    return _active.putIfAbsent(
      key,
      () => _preview(entry).whenComplete(() {
        _active.remove(key);
      }),
    );
  }

  Future<void> repairMissing() async {
    if (store.setting('previews') == 'off') return;
    final retryLegacy = store.setting('preview-tls-migration') != '1';
    final entries = store.entries
        .where(
          (e) =>
              e.kind == 'link' &&
              !e.deleted &&
              (e.text('previewStatus').isEmpty ||
                  (retryLegacy && e.text('previewStatus') == 'unavailable') ||
                  ['loading', 'saved'].contains(e.text('previewStatus'))),
        )
        .toList();
    for (final entry in entries) {
      await preview(entry);
    }
    store.setSetting('preview-tls-migration', '1');
  }

  Future<void> _preview(Entry entry) async {
    final originalUrl = entry.text('url');
    bool current() =>
        store.get(entry.id)?.text('url') == originalUrl &&
        store.get(entry.id)?.deleted == false;
    void save(Json changes) {
      if (current() && store.canEdit(entry.project)) {
        store.update(store.get(entry.id)!, changes);
      }
    }

    save({'previewStatus': 'loading', 'previewError': ''});
    try {
      final resource = await fetchResource(
        webUri(originalUrl),
        2 * 1024 * 1024,
        headOnly: true,
      );
      if (resource.contentType.startsWith('image/')) {
        final photo = await importPhoto(resource.bytes);
        save({
          'photo': photo,
          'previewStatus': 'ready',
          'previewTitle': resource.uri.host,
          'previewDescription': '',
        });
        return;
      }
      final doc = html.parse(utf8.decode(resource.bytes, allowMalformed: true));
      String meta(String key) {
        for (final tag in doc.querySelectorAll('meta')) {
          if ((tag.attributes['property'] ?? tag.attributes['name'] ?? '')
                  .toLowerCase() ==
              key) {
            return tag.attributes['content']?.trim() ?? '';
          }
        }
        return '';
      }

      String first(List<String> values) =>
          values.firstWhere((v) => v.isNotEmpty, orElse: () => '');
      String limit(String value, int n) =>
          value.substring(0, value.length.clamp(0, n));
      final title = first([
        meta('og:title'),
        meta('twitter:title'),
        doc.querySelector('title')?.text.trim() ?? '',
        resource.uri.host,
      ]);
      final description = first([
        meta('og:description'),
        meta('twitter:description'),
        meta('description'),
      ]);
      final images = <String>[
        meta('og:image:secure_url'),
        meta('og:image'),
        meta('og:image:url'),
        meta('twitter:image'),
        meta('twitter:image:src'),
        doc.querySelector('link[rel="image_src"]')?.attributes['href'] ?? '',
        doc.querySelector('meta[itemprop="image"]')?.attributes['content'] ??
            '',
      ].where((v) => v.isNotEmpty).toSet().toList();
      Uri base = resource.uri;
      final baseHref = doc.querySelector('base[href]')?.attributes['href'];
      if (baseHref != null) base = base.resolve(baseHref);
      final changes = <String, dynamic>{
        'previewTitle': limit(title, 500),
        'previewDescription': limit(description, 2000),
        'previewStatus': 'no-image',
        'previewError': '',
      };
      save(changes);
      var failedImage = false;
      for (final source in images.take(4)) {
        try {
          final uri = webUri(base.resolve(source).toString());
          changes['photo'] = await importPhoto(
            await fetch(uri, 8 * 1024 * 1024),
          );
          changes['previewStatus'] = 'ready';
          failedImage = false;
          break;
        } catch (_) {
          failedImage = true;
        }
      }
      if (failedImage) {
        changes['previewStatus'] = 'image-unavailable';
        changes['previewError'] =
            'The page details loaded, but its image could not be downloaded.';
      }
      save(changes);
    } catch (error) {
      final message = error is HttpException
          ? error.message
          : error is HandshakeException
          ? 'The website could not establish a secure connection.'
          : error is SocketException
          ? 'Could not reach the website. Check your connection and retry.'
          : error is FormatException
          ? error.message
          : 'The website did not respond in time. Try again.';
      save({'previewStatus': 'unavailable', 'previewError': message});
    }
  }
}
