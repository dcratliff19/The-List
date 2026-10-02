import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Fetches bounded resources while pinning every redirect to checked public addresses.
class PreviewFetcher {
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
}

class PreviewResource {
  final Uint8List bytes;
  final Uri uri;
  final String contentType;
  PreviewResource(this.bytes, this.uri, this.contentType);
}
