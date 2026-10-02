import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart' as hashes;
import '../store.dart';
import 'sync/peer_host.dart';
import 'sync/peer_session.dart';
import 'sync/signaling_client.dart';

export 'sync/peer_session.dart';

part 'sync/offline_delivery.dart';

/// Coordinates secure pairings, direct peer sessions and encrypted mailboxes.
/// Pairing keys belong in OS secure storage and never enter portable backups.
class SyncService extends ChangeNotifier implements PeerHost {
  @override
  final Store store;
  final List<PeerSession> peers = [];
  final FlutterSecureStorage vault;
  String? error;
  @override
  bool disposed = false;
  Timer? offlineTimer;
  bool offlineBusy = false;
  final SignalingClient signaling;
  Future<void>? _initialization;
  SyncService(
    this.store, {
    SignalingClient? signaling,
    FlutterSecureStorage? vault,
  }) : signaling = signaling ?? SignalingClient(),
       vault = vault ?? const FlutterSecureStorage();
  String get vaultKey =>
      'the-list-peers-${hashes.sha256.convert(utf8.encode(store.directory.path))}';
  Future<void> initialize() {
    if (disposed) return Future.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    offlineTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => offlineDelivery(),
    );
    try {
      final saved = await vault.read(key: vaultKey);
      if (disposed) return;
      if (saved != null) {
        for (final value in jsonDecode(saved) as List) {
          final peer = PeerSession(
            this,
            Map<String, dynamic>.from(value as Map),
          );
          store.setProjectAccess(
            peer.project,
            peer.config['room'] as String,
            peer.config['host'] == true,
            peer.config['access'] as String? ?? 'update',
          );
          peers.add(peer);
          unawaited(
            peer.connect().catchError((Object e) {
              peer.status = 'Reconnect needed';
              changed();
            }),
          );
        }
      }
    } catch (_) {
      error = 'Device pairing could not be restored from secure storage.';
    }
  }

  @override
  void changed() {
    if (!disposed) notifyListeners();
  }

  @override
  Future<void> persist() async {
    await vault.write(
      key: vaultKey,
      value: jsonEncode(peers.map((e) => e.config).toList()),
    );
  }

  Future<void> offlineDelivery() => _offlineDelivery();

  static Uri serverUri(String value) => SignalingClient.serverUri(value);

  @override
  Future<Json> request(
    String base,
    String path, {
    String? token,
    Json? body,
    String method = 'GET',
  }) => signaling.request(base, path, token: token, body: body, method: method);

  Future<String> invite(
    String project,
    String base, {
    String access = 'update',
  }) async {
    if (!store.canManageSharing(project)) {
      throw StateError('Only the project owner can invite people.');
    }
    serverUri(base);
    final room = await request(
      base,
      '/rooms',
      method: 'POST',
      body: {'access': access},
    );
    final key = base64UrlEncode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final config = <String, dynamic>{
      'server': base,
      'room': room['id'],
      'token': room['token'],
      'project': project,
      'key': key,
      'host': true,
      'iceServers': room['iceServers'],
      'access': room['access'] ?? 'update',
    };
    final peer = PeerSession(this, config);
    peer.acceptAccess(room);
    peers.add(peer);
    await persist();
    await peer.connect();
    final invite = {
      'version': 1,
      'server': base,
      'room': room['id'],
      'invite': room['invite'],
      'project': project,
      'key': key,
    };
    changed();
    return 'thelist:${base64UrlEncode(utf8.encode(jsonEncode(invite)))}';
  }

  Future<String> join(String invitation) async {
    final raw = invitation.trim();
    if (!raw.startsWith('thelist:') || raw.length > 6000) {
      throw const FormatException('Paste a The List invitation.');
    }
    final code =
        jsonDecode(utf8.decode(base64Url.decode(raw.substring(8)))) as Json;
    if (code['version'] != 1 ||
        code['project'] is! String ||
        base64Url.decode(code['key'] as String).length != 32) {
      throw const FormatException('Invalid invitation');
    }
    serverUri(code['server'] as String);
    final room = await request(
      code['server'],
      '/rooms/${code['room']}/join',
      token: code['invite'],
      method: 'POST',
    );
    final config = <String, dynamic>{
      'server': code['server'],
      'room': code['room'],
      'token': room['token'],
      'project': code['project'],
      'key': code['key'],
      'host': false,
      'iceServers': room['iceServers'],
      'access': room['access'] ?? 'update',
    };
    final peer = PeerSession(this, config);
    peer.acceptAccess(room);
    peers.add(peer);
    await persist();
    await peer.connect();
    changed();
    return code['project'];
  }

  Future<void> changeAccess(PeerSession peer, String access) async {
    if (peer.config['host'] != true) {
      throw StateError('Only the owner can change access.');
    }
    final data = await peer.request(
      'access',
      method: 'PATCH',
      body: {'access': access},
    );
    peer.acceptAccess(data);
    await persist();
    changed();
  }

  Future<void> disconnect(PeerSession peer) async {
    if (peer.config['host'] == true) {
      try {
        await request(
          peer.config['server'],
          '/rooms/${peer.config['room']}',
          token: peer.config['token'],
          method: 'DELETE',
        );
      } catch (_) {}
    }
    await peer.close();
    peers.remove(peer);
    await persist();
    changed();
  }

  @override
  void dispose() {
    disposed = true;
    offlineTimer?.cancel();
    for (final peer in peers) {
      unawaited(peer.close());
    }
    super.dispose();
  }
}
