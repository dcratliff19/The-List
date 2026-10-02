import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../../domain/json.dart';

/// The same authenticated envelope is used for direct and offline delivery.
class EncryptedMessages {
  final SecretKey _key;
  final _cipher = AesGcm.with256bits();

  EncryptedMessages(String encodedKey)
    : _key = SecretKey(_decodeKey(encodedKey));

  static List<int> _decodeKey(String value) {
    final bytes = base64Url.decode(value);
    if (bytes.length != 32) {
      throw const FormatException('Invalid pairing key');
    }
    return bytes;
  }

  Future<String> encrypt(Json data) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: _key,
    );
    return jsonEncode({
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
  }

  Future<Json> decrypt(String payload) async {
    final envelope = jsonDecode(payload);
    if (envelope is! Json ||
        envelope['n'] is! String ||
        envelope['c'] is! String ||
        envelope['m'] is! String) {
      throw const FormatException('Invalid encrypted message');
    }
    final bytes = await _cipher.decrypt(
      SecretBox(
        base64Decode(envelope['c'] as String),
        nonce: base64Decode(envelope['n'] as String),
        mac: Mac(base64Decode(envelope['m'] as String)),
      ),
      secretKey: _key,
    );
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Json) {
      throw const FormatException('Expected an encrypted JSON object');
    }
    return data;
  }
}
