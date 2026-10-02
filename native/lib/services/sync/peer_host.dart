import '../../store.dart';

/// Session dependencies, independent of UI, secure storage and pairing creation.
abstract interface class PeerHost {
  Store get store;
  bool get disposed;
  void changed();
  Future<void> persist();
  Future<Json> request(
    String base,
    String path, {
    String? token,
    Json? body,
    String method = 'GET',
  });
}
