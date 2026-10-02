import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:the_list/services/sync/encrypted_messages.dart';
import 'package:the_list/services/sync/frame_assembler.dart';
import 'package:the_list/services/sync/signaling_client.dart';

class _TrackingClient extends MockClient {
  bool closed = false;
  _TrackingClient(super.handler);
  @override
  void close() {
    closed = true;
    super.close();
  }
}

String frame(String id, int index, int count, String payload) =>
    jsonEncode({'id': id, 'i': index, 'n': count, 'd': payload});

void main() {
  test(
    'direct and offline envelopes preserve Unicode and authenticate bytes',
    () async {
      final key = base64UrlEncode(List.generate(32, (i) => i));
      final sender = EncryptedMessages(key);
      final receiver = EncryptedMessages(key);
      final message = {
        'protocol': 3,
        'op': {'body': 'Hello 🌍 — 你好'},
      };
      final first = await sender.encrypt(message);
      final second = await sender.encrypt(message);
      expect(
        first,
        isNot(second),
        reason: 'Each encryption must use a fresh nonce',
      );
      expect(await receiver.decrypt(first), message);
      // Decrypt the envelope using the pre-refactor protocol, independently of the codec.
      final legacy = jsonDecode(first) as Map<String, dynamic>;
      final decoded = await AesGcm.with256bits().decrypt(
        SecretBox(
          base64Decode(legacy['c'] as String),
          nonce: base64Decode(legacy['n'] as String),
          mac: Mac(base64Decode(legacy['m'] as String)),
        ),
        secretKey: SecretKey(base64Url.decode(key)),
      );
      expect(jsonDecode(utf8.decode(decoded)), message);
      final ciphertext = base64Decode(legacy['c'] as String);
      ciphertext[0] ^= 1;
      legacy['c'] = base64Encode(ciphertext);
      await expectLater(
        receiver.decrypt(jsonEncode(legacy)),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final wrongKey = EncryptedMessages(base64UrlEncode(List.filled(32, 255)));
      await expectLater(
        wrongKey.decrypt(second),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );

  test(
    'frames handle reordering, duplicate delivery and interleaved messages',
    () {
      final assembler = FrameAssembler();
      expect(assembler.add(frame('a', 2, 3, 'C')), isNull);
      expect(assembler.add(frame('b', 0, 2, '1')), isNull);
      expect(assembler.add(frame('a', 0, 3, 'A')), isNull);
      expect(assembler.add(frame('a', 0, 3, 'A')), isNull);
      expect(assembler.add(frame('a', 1, 3, 'B')), 'ABC');
      expect(assembler.add(frame('b', 1, 2, '2')), '12');
    },
  );

  test(
    'inconsistent counts and oversized chunks are rejected before decryption',
    () {
      final assembler = FrameAssembler();
      assembler.add(frame('a', 0, 2, 'A'));
      expect(() => assembler.add(frame('a', 1, 3, 'B')), throwsFormatException);
      expect(
        () => assembler.add(frame('large', 0, 1, 'x' * 12001)),
        throwsFormatException,
      );
      expect(
        () => assembler.add(frame('bad', 2, 2, 'X')),
        throwsFormatException,
      );
      expect(() => assembler.add('{}'), throwsFormatException);
      expect(assembler.add(frame('a', 0, 1, 'fresh')), 'fresh');
    },
  );

  test(
    'incomplete frame assemblies are bounded and released on completion or clear',
    () {
      final assembler = FrameAssembler();
      for (var i = 0; i < 8; i++) {
        expect(assembler.add(frame('$i', 0, 2, 'A')), isNull);
      }
      expect(
        () => assembler.add(frame('overflow', 0, 2, 'B')),
        throwsFormatException,
      );
      expect(assembler.add(frame('0', 1, 2, 'B')), 'AB');
      expect(assembler.add(frame('overflow', 0, 2, 'B')), isNull);
      assembler.clear();
      expect(assembler.add(frame('clean', 0, 1, 'C')), 'C');
    },
  );

  test(
    'signaling sends protocol fields and closes the client on success',
    () async {
      final client = _TrackingClient((request) async {
        expect(request.url.toString(), 'https://relay.example/rooms/r/access');
        expect(request.method, 'PATCH');
        expect(request.headers['authorization'], 'Bearer credential');
        expect(jsonDecode(request.body), {'access': 'read'});
        return http.Response('{"access":"read"}', 200);
      });
      final api = SignalingClient(createClient: () => client);
      expect(
        await api.request(
          'https://relay.example',
          '/rooms/r/access',
          token: 'credential',
          method: 'PATCH',
          body: {'access': 'read'},
        ),
        {'access': 'read'},
      );
      expect(client.closed, isTrue);
    },
  );

  test(
    'signaling closes resources on HTTP, malformed, oversized and timeout failures',
    () async {
      for (final response in [
        http.Response('{"error":"No access"}', 403),
        http.Response('[]', 200),
        http.Response('invalid JSON', 200),
        http.Response('{"large":"${'x' * 100}"}', 200),
      ]) {
        final client = _TrackingClient((_) async => response);
        final api = SignalingClient(
          createClient: () => client,
          maxResponseBytes: 64,
        );
        await expectLater(
          api.request('https://relay.example', '/rooms'),
          throwsA(isA<Exception>()),
        );
        expect(client.closed, isTrue);
      }
      final client = _TrackingClient((_) => Completer<http.Response>().future);
      final api = SignalingClient(
        createClient: () => client,
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        api.request('https://relay.example', '/rooms'),
        throwsA(isA<TimeoutException>()),
      );
      expect(client.closed, isTrue);
    },
  );

  test(
    'remote plaintext, embedded credentials and ambiguous server URLs are rejected',
    () {
      for (final value in [
        'http://relay.example',
        'https://user:secret@relay.example',
        'https://relay.example?key=value',
        'https://relay.example#fragment',
        'file:///local',
      ]) {
        expect(() => SignalingClient.serverUri(value), throwsFormatException);
      }
      expect(
        SignalingClient.serverUri(' http://127.0.0.1:5174 ').host,
        '127.0.0.1',
      );
    },
  );
}
