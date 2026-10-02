import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/json.dart';

/// Bounded HTTP adapter. Each request owns and closes its client, even on failure.
class SignalingClient {
  final http.Client Function() _createClient;
  final Duration timeout;
  final int maxResponseBytes;

  SignalingClient({
    http.Client Function()? createClient,
    this.timeout = const Duration(seconds: 12),
    this.maxResponseBytes = 2 * 1024 * 1024,
  }) : _createClient = createClient ?? http.Client.new;

  static Uri serverUri(String value) {
    final uri = Uri.parse(value.trim());
    if (uri.host.isEmpty ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Enter the sharing server HTTPS address.');
    }
    if (uri.scheme == 'http' &&
        !['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host)) {
      throw const FormatException('Use HTTPS for a remote sharing server.');
    }
    return uri;
  }

  Future<Json> request(
    String base,
    String path, {
    String? token,
    Json? body,
    String method = 'GET',
  }) async {
    final uri = serverUri(base).resolve(path);
    final client = _createClient();
    try {
      final request = http.Request(method, uri);
      request.headers['content-type'] = 'application/json';
      if (token != null) request.headers['authorization'] = 'Bearer $token';
      if (body != null) request.body = jsonEncode(body);
      final response = await client.send(request).timeout(timeout);
      final bytes = <int>[];
      await for (final part in response.stream.timeout(timeout)) {
        if (bytes.length + part.length > maxResponseBytes) {
          throw const FormatException('Server response too large');
        }
        bytes.addAll(part);
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Json) {
        throw const FormatException('Expected a server JSON object');
      }
      if (response.statusCode >= 400) {
        throw Exception(data['error'] ?? 'Sharing unavailable');
      }
      return data;
    } finally {
      client.close();
    }
  }
}
