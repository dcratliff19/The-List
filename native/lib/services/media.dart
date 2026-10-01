import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:html/parser.dart' as html;
import '../store.dart';

/// Normalizes imported photos and fetches bounded, public-network link previews.
class MediaService {
  final Store store;
  MediaService(this.store);
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

  static bool publicAddress(InternetAddress ip) {
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return false;
    final b = ip.rawAddress;
    if (b.length == 4) {
      return !(b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
          (b[0] == 198 && (b[1] == 18 || b[1] == 19)));
    }
    // Only globally routable IPv6 unicast; excludes mapped IPv4 and local ranges.
    return b[0] >= 0x20 && b[0] <= 0x3f;
  }

  static Uri webUri(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Enter a full http:// or https:// web address.',
      );
    }
    return uri;
  }

  Future<PreviewResource> fetchResource(
    Uri uri,
    int maxBytes, {
    bool headOnly = false,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'Mozilla/5.0 (compatible; TheList/1.0; link preview)';
    client.connectionFactory = (target, proxyHost, proxyPort) async {
      // Resolve and pin the checked address for each connection, including
      // redirects, to prevent DNS rebinding into a private network.
      if (proxyHost != null) throw const HttpException('Proxy not supported');
      final addresses = await InternetAddress.lookup(
        target.host,
      ).timeout(const Duration(seconds: 5));
      if (addresses.isEmpty || addresses.any((ip) => !publicAddress(ip))) {
        throw const HttpException('Private network previews are disabled');
      }
      addresses.sort(
        (a, b) => (a.type == InternetAddressType.IPv4 ? 0 : 1).compareTo(
          b.type == InternetAddressType.IPv4 ? 0 : 1,
        ),
      );
      Object? failure;
      for (final address in addresses.take(4)) {
        ConnectionTask<Socket>? task;
        try {
          task = await Socket.startConnect(address, target.port);
          final socket = await task.socket.timeout(const Duration(seconds: 4));
          final connected = target.scheme == 'https'
              ? await SecureSocket.secure(
                  socket,
                  host: target.host,
                ).timeout(const Duration(seconds: 10))
              : socket;
          return ConnectionTask.fromSocket(
            Future.value(connected),
            connected.destroy,
          );
        } catch (e) {
          task?.cancel();
          failure = e;
        }
      }
      throw SocketException('Could not connect to website: $failure');
    };
    try {
      var current = uri;
      for (var redirects = 0; redirects < 6; redirects++) {
        webUri(current.toString());
        final req = await client
            .getUrl(current)
            .timeout(const Duration(seconds: 10));
        req.headers.set(
          HttpHeaders.acceptHeader,
          headOnly
              ? 'text/html,application/xhtml+xml,image/*;q=0.8,*/*;q=0.5'
              : 'image/*,*/*;q=0.5',
        );
        req.followRedirects = false;
        final response = await req.close().timeout(const Duration(seconds: 10));
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value('location');
          if (location == null) throw const HttpException('Invalid redirect');
          current = current.resolve(location);
          continue;
        }
        if (response.statusCode != 200) {
          throw HttpException('Website returned HTTP ${response.statusCode}');
        }
        final type = response.headers.contentType?.mimeType ?? '';
        final isHtml = headOnly && !type.startsWith('image/');
        final out = BytesBuilder();
        var scan = '';
        await for (final part in response.timeout(
          const Duration(seconds: 10),
        )) {
          final remaining = maxBytes - out.length;
          if (part.length > remaining) {
            if (!isHtml) {
              throw const HttpException('Preview image is too large');
            }
            out.add(part.take(remaining).toList());
            break;
          }
          out.add(part);
          if (isHtml) {
            scan += latin1.decode(part).toLowerCase();
            if (scan.contains('</head>')) break;
            if (scan.length > 32) scan = scan.substring(scan.length - 32);
            if (out.length == maxBytes) break;
          }
        }
        return PreviewResource(out.takeBytes(), current, type);
      }
      throw const HttpException('Too many website redirects');
    } finally {
      client.close(force: true);
    }
  }

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

class PreviewResource {
  final Uint8List bytes;
  final Uri uri;
  final String contentType;
  PreviewResource(this.bytes, this.uri, this.contentType);
}
