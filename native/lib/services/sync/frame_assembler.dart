import 'dart:convert';
import '../../domain/json.dart';

/// Reassembles out-of-order frames with fixed memory limits before decryption.
class FrameAssembler {
  static const chunkSize = 12000;
  static const maxChunks = 64;
  static const maxAssemblies = 8;
  final _pending = <String, (int, Map<int, String>)>{};

  String? add(String text) {
    if (text.length > 14000) throw const FormatException('Oversized frame');
    final frame = jsonDecode(text);
    if (frame is! Json ||
        frame['id'] is! String ||
        frame['n'] is! int ||
        frame['i'] is! int ||
        frame['d'] is! String) {
      throw const FormatException('Invalid frame');
    }
    final id = frame['id'] as String;
    final count = frame['n'] as int;
    final index = frame['i'] as int;
    final payload = frame['d'] as String;
    if (count < 1 ||
        count > maxChunks ||
        index < 0 ||
        index >= count ||
        id.isEmpty ||
        id.length > 100 ||
        payload.length > chunkSize) {
      throw const FormatException('Invalid frame');
    }
    final existing = _pending[id];
    if (existing != null && existing.$1 != count) {
      _pending.remove(id);
      throw const FormatException('Inconsistent frame count');
    }
    if (existing == null && _pending.length >= maxAssemblies) {
      throw const FormatException('Too many frames');
    }
    final assembly = _pending.putIfAbsent(id, () => (count, {}));
    assembly.$2[index] = payload;
    if (assembly.$2.length != count) return null;
    _pending.remove(id);
    return List.generate(count, (i) => assembly.$2[i]!).join();
  }

  void clear() => _pending.clear();
}
