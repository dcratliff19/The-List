import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:http/http.dart' as http;
import '../store.dart';

/// Coordinates secure pairings, direct peer sessions and encrypted mailboxes.
/// Pairing keys belong in OS secure storage and never enter portable backups.
class SyncService extends ChangeNotifier {
  final Store store;
  final List<PeerSession> peers = [];
  final vault = const FlutterSecureStorage();
  String? error;
  bool disposed = false;
  Timer? offlineTimer;
  bool offlineBusy = false;
  SyncService(this.store);
  String get vaultKey =>
      'the-list-peers-${hashes.sha256.convert(utf8.encode(store.directory.path))}';
  Future<void> initialize() async {
    offlineTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => offlineDelivery(),
    );
    try {
      final saved = await vault.read(key: vaultKey);
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

  void changed() {
    if (!disposed) notifyListeners();
  }

  Future<void> persist() async {
    await vault.write(
      key: vaultKey,
      value: jsonEncode(peers.map((e) => e.config).toList()),
    );
  }

  Future<void> offlineDelivery() async {
    if (disposed || offlineBusy) return;
    offlineBusy = true;
    try {
      for (final peer in peers.toList()) {
        if (store.setting('offline-${peer.project}') != 'on') continue;
        try {
          peer.acceptAccess(await peer.request('access'));
          final cipher = AesGcm.with256bits();
          final key = SecretKey(base64Url.decode(peer.config['key']));
          final sent = ((peer.config['offlineSent'] as List?) ?? [])
              .cast<String>()
              .toSet();
          for (final op
              in store
                  .operations(peer.project)
                  .where(
                    (op) => peer.canSendUpdates && !sent.contains(op['id']),
                  )
                  .take(30)) {
            final box = await cipher.encrypt(
              utf8.encode(jsonEncode({'protocol': 3, 'op': op})),
              secretKey: key,
            );
            final payload = jsonEncode({
              'n': base64Encode(box.nonce),
              'c': base64Encode(box.cipherText),
              'm': base64Encode(box.mac.bytes),
            });
            await request(
              peer.config['server'],
              '/rooms/${peer.config['room']}/mailbox',
              token: peer.config['token'],
              method: 'POST',
              body: {'id': op['id'], 'payload': payload},
            );
            sent.add(op['id']);
          }
          peer.config['offlineSent'] = sent.toList();
          final result = await request(
            peer.config['server'],
            '/rooms/${peer.config['room']}/mailbox',
            token: peer.config['token'],
          );
          final ack = <String>[];
          for (final update in result['updates'] as List) {
            final data = jsonDecode(update['payload']) as Json;
            final plain =
                jsonDecode(
                      utf8.decode(
                        await cipher.decrypt(
                          SecretBox(
                            base64Decode(data['c']),
                            nonce: base64Decode(data['n']),
                            mac: Mac(base64Decode(data['m'])),
                          ),
                          secretKey: key,
                        ),
                      ),
                    )
                    as Json;
            if (![2, 3].contains(plain['protocol'])) {
              throw const FormatException(
                'Update both apps to read offline updates.',
              );
            }
            final op = Map<String, dynamic>.from(plain['op']);
            if (op['kind'] == 'reminder') {
              throw const FormatException(
                'Personal reminders cannot be shared.',
              );
            }
            if (!peer.canReceiveUpdates) {
              throw StateError('Read-only peer cannot send updates');
            }
            store.apply([op], scope: peer.project);
            sent.add(op['id']);
            ack.add(update['id']);
          }
          if (ack.isNotEmpty) {
            await request(
              peer.config['server'],
              '/rooms/${peer.config['room']}/mailbox',
              token: peer.config['token'],
              method: 'DELETE',
              body: {'ids': ack},
            );
          }
          peer.config['offlineSent'] = sent.toList();
          peer.config['lastOffline'] = DateTime.now().toUtc().toIso8601String();
          if (!peer.connected) {
            peer.updateStatus(
              'Encrypted offline updates checked · photos wait for direct sync',
            );
          }
          await persist();
        } catch (e) {
          peer.updateStatus('Offline delivery pending: $e');
        }
      }
    } finally {
      offlineBusy = false;
    }
  }

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
    final client = http.Client();
    try {
      final req = http.Request(method, uri);
      req.headers['content-type'] = 'application/json';
      if (token != null) req.headers['authorization'] = 'Bearer $token';
      if (body != null) req.body = jsonEncode(body);
      final streamed = await client
          .send(req)
          .timeout(const Duration(seconds: 12));
      final bytes = <int>[];
      await for (final part in streamed.stream.timeout(
        const Duration(seconds: 12),
      )) {
        bytes.addAll(part);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('Server response too large');
        }
      }
      final data = jsonDecode(utf8.decode(bytes)) as Json;
      if (streamed.statusCode >= 400) {
        throw Exception(data['error'] ?? 'Sharing unavailable');
      }
      return data;
    } finally {
      client.close();
    }
  }

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

/// Serializes encrypted frames on one peer channel and enforces its access role.
class PeerSession {
  final SyncService manager;
  final Json config;
  Store get store => manager.store;
  bool get canSendUpdates =>
      config['host'] == true || config['access'] == 'update';
  bool get canReceiveUpdates =>
      config['host'] != true || config['access'] == 'update';
  void acceptAccess(Json data) {
    // The signaling owner is authoritative; invitation text cannot grant access.
    final access = data['access'];
    if (!['read', 'update'].contains(access)) {
      throw StateError('Update the sharing server to support permissions.');
    }
    config['access'] = access;
    store.setProjectAccess(
      project,
      config['room'] as String,
      config['host'] == true,
      access as String,
    );
  }

  String get project => config['project'] as String;
  String status = 'Waiting for friend';
  bool compatible = false;
  RTCPeerConnection? pc;
  RTCDataChannel? channel;
  Timer? pollTimer, debounce, reconnectTimer;
  bool polling = false, closed = false, connected = false, sending = false;
  int cursor = 0;
  bool remoteSet = false;
  final candidates = <RTCIceCandidate>[];
  final known = <String>{}, requested = <String>{};
  Future<void> incoming = Future.value(), outgoing = Future.value();
  final frames = <String, Map<int, String>>{};
  final cipher = AesGcm.with256bits();
  PeerSession(this.manager, this.config) {
    // SQLite is updated immediately on permission changes; the secure vault
    // can still contain an older snapshot if the app exits before persisting.
    final saved = store.db.select(
      'SELECT access FROM project_access WHERE room=? AND project=? AND host=?',
      [config['room'], config['project'], config['host'] == true ? 1 : 0],
    );
    if (saved.isNotEmpty) config['access'] = saved.first['access'];
  }
  Future<Json> request(String suffix, {Json? body, String? method}) =>
      manager.request(
        config['server'],
        '/rooms/${config['room']}/$suffix',
        token: config['token'],
        body: body,
        method: method ?? (body == null ? 'GET' : 'POST'),
      );
  void updateStatus(String value) {
    status = value;
    manager.changed();
  }

  bool connecting = false;
  int retrySeconds = 3;
  Future<void> connect() async {
    if (connecting || manager.disposed) return;
    connecting = true;
    try {
      await _connect();
      retrySeconds = 3;
    } catch (_) {
      if (!closed && !manager.disposed) {
        updateStatus("Waiting for connection · retrying automatically");
        reconnectTimer?.cancel();
        reconnectTimer = Timer(
          Duration(seconds: retrySeconds),
          () => unawaited(connect().catchError((Object _) {})),
        );
        retrySeconds = (retrySeconds * 2).clamp(3, 60);
      }
      rethrow;
    } finally {
      connecting = false;
    }
  }

  Future<void> _connect() async {
    if (pc != null) await closeTransport();
    closed = false;
    known.clear();
    requested.clear();
    remoteSet = false;
    candidates.clear();
    final connectivity = await request('ice');
    acceptAccess(connectivity);
    await manager.persist();
    config['iceServers'] = connectivity['iceServers'];
    pc = await createPeerConnection({'iceServers': config['iceServers'] ?? []});
    pc!.onIceCandidate = (c) {
      if (c.candidate?.isNotEmpty == true) {
        unawaited(
          request(
            'signals',
            body: {
              'type': 'candidate',
              'candidate': c.candidate,
              'mid': c.sdpMid,
              'index': c.sdpMLineIndex,
            },
          ).catchError((Object _) => <String, dynamic>{}),
        );
      }
    };
    pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        connected = false;
        compatible = false;
        updateStatus('Disconnected · changes saved locally');
        if (config['host'] == true && !closed) {
          reconnectTimer?.cancel();
          reconnectTimer = Timer(const Duration(seconds: 10), () {
            if (!connected && !closed) {
              unawaited(
                connect().catchError((Object _) {
                  updateStatus('Reconnect needed');
                }),
              );
            }
          });
        }
      }
    };
    pc!.onDataChannel = attach;
    if (config['host'] == true) {
      final data = await pc!.createDataChannel(
        'the-list',
        RTCDataChannelInit(),
      );
      attach(data);
      final offer = await pc!.createOffer();
      await pc!.setLocalDescription(offer);
      await request('signals', body: {'type': 'offer', 'sdp': offer.sdp});
    } else {
      await request('signals', body: {'type': 'ready'});
    }
    store.addListener(onChange);
    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
    await poll();
  }

  Future<void> poll() async {
    if (polling || closed) return;
    polling = true;
    try {
      final data = await request('events?after=$cursor');
      final accessChanged = config['access'] != data['access'];
      acceptAccess(data);
      if (accessChanged) {
        await manager.persist();
        manager.changed();
      }
      for (final raw in data['events'] as List) {
        final e = Map<String, dynamic>.from(raw as Map);
        if (e['type'] == 'offer' && config['host'] != true) {
          if (remoteSet) {
            await closeTransport();
            await connect();
            return;
          }
          await pc!.setRemoteDescription(
            RTCSessionDescription(e['sdp'], 'offer'),
          );
          remoteSet = true;
          await flushCandidates();
          final answer = await pc!.createAnswer();
          await pc!.setLocalDescription(answer);
          await request('signals', body: {'type': 'answer', 'sdp': answer.sdp});
        }
        if (e['type'] == 'answer' && config['host'] == true && !remoteSet) {
          await pc!.setRemoteDescription(
            RTCSessionDescription(e['sdp'], 'answer'),
          );
          remoteSet = true;
          await flushCandidates();
        }
        if (e['type'] == 'candidate') {
          final c = RTCIceCandidate(e['candidate'], e['mid'], e['index']);
          if (remoteSet) {
            await pc!.addCandidate(c);
          } else {
            candidates.add(c);
          }
        }
        if (e['type'] == 'ready' && config['host'] == true && remoteSet) {
          await closeTransport();
          cursor = data['sequence'] as int;
          await connect();
          return;
        }
      }
      cursor = data['sequence'] as int;
    } catch (_) {
      if (!connected) updateStatus('Server unavailable · retrying');
    } finally {
      polling = false;
    }
  }

  Future<void> flushCandidates() async {
    for (final c in candidates) {
      await pc!.addCandidate(c);
    }
    candidates.clear();
  }

  void attach(RTCDataChannel data) {
    channel = data;
    data.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        connected = true;
        updateStatus('Connected · syncing');
        unawaited(
          send({
            'type': 'hello',
            'protocol': 3,
            'name': store.setting('display-name') ?? 'Friend',
          }),
        );
        onChange();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        connected = false;
        compatible = false;
        updateStatus('Disconnected · changes saved locally');
      }
    };
    data.onMessage = (message) {
      incoming = incoming.then((_) => receiveFrame(message.text)).catchError((
        Object e,
      ) {
        updateStatus('Sync error · retry or reconnect');
      });
    };
  }

  Future<void> send(Json data) {
    outgoing = outgoing
        .then((_) async {
          if (!connected || channel == null) return;
          final sealed = await cipher.encrypt(
            utf8.encode(jsonEncode(data)),
            secretKey: SecretKey(base64Url.decode(config['key'])),
          );
          final envelope = jsonEncode({
            'n': base64Encode(sealed.nonce),
            'c': base64Encode(sealed.cipherText),
            'm': base64Encode(sealed.mac.bytes),
          });
          final count = (envelope.length / 12000).ceil(), id = uuid.v4();
          for (var index = 0; index < count; index++) {
            while ((channel?.bufferedAmount ?? 0) > 128000 && connected) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            if (!connected) return;
            await channel!.send(
              RTCDataChannelMessage(
                jsonEncode({
                  'id': id,
                  'i': index,
                  'n': count,
                  'd': envelope.substring(
                    index * 12000,
                    min((index + 1) * 12000, envelope.length),
                  ),
                }),
              ),
            );
          }
        })
        .catchError((Object _) {
          updateStatus('Transfer paused · reconnect to retry');
        });
    return outgoing;
  }

  Future<void> receiveFrame(String text) async {
    // Bound incomplete assemblies before decrypting untrusted transport input.
    if (text.length > 14000) throw const FormatException('Oversized frame');
    final frame = jsonDecode(text) as Json;
    final id = frame['id'] as String,
        n = frame['n'] as int,
        i = frame['i'] as int;
    if (n < 1 || n > 64 || i < 0 || i >= n || id.length > 100) {
      throw const FormatException('Invalid frame');
    }
    if (frames.length > 8) {
      frames.clear();
      throw const FormatException('Too many frames');
    }
    final parts = frames.putIfAbsent(id, () => {});
    parts[i] = frame['d'] as String;
    if (parts.length != n) return;
    final envelope =
        jsonDecode(List.generate(n, (i) => parts[i]!).join()) as Json;
    frames.remove(id);
    final data =
        jsonDecode(
              utf8.decode(
                await cipher.decrypt(
                  SecretBox(
                    base64Decode(envelope['c']),
                    nonce: base64Decode(envelope['n']),
                    mac: Mac(base64Decode(envelope['m'])),
                  ),
                  secretKey: SecretKey(base64Url.decode(config['key'])),
                ),
              ),
            )
            as Json;
    await receive(data);
  }

  void onChange() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () => syncChanges());
  }

  Future<void> syncChanges() async {
    if (!connected || !compatible || sending) return;
    sending = true;
    try {
      for (final op in store.operations(project)) {
        if (canSendUpdates && !known.contains(op['id'])) {
          await send({'type': 'op', 'op': op});
        }
      }
      await requestPhotos();
      await send({'type': 'complete'});
    } finally {
      sending = false;
    }
  }

  Set<String> photoHashes() => store.entries
      .where((e) => e.project == project)
      .expand((e) => [e.text('photo'), e.text('cover')])
      .where((h) => h.isNotEmpty)
      .toSet();
  Future<void> requestPhotos() async {
    if (!canReceiveUpdates) return;
    for (final hash in photoHashes()) {
      final f = store.blob(hash);
      if (!f.existsSync() && !requested.contains(hash)) {
        requested.add(hash);
        final part = File('${f.path}.part');
        await send({
          'type': 'needPhoto',
          'hash': hash,
          'offset': part.existsSync() ? part.lengthSync() : 0,
        });
      }
    }
  }

  Future<void> receive(Json data) async {
    if (data['type'] != 'hello' && !compatible) return;
    switch (data['type']) {
      case 'hello':
        compatible = data['protocol'] == 3;
        if (!compatible) {
          updateStatus(
            'Update required: install the latest app on both devices.',
          );
          return;
        }
        config['peerName'] = data['name'] is String
            ? (data['name'] as String).substring(
                0,
                min(80, (data['name'] as String).length),
              )
            : 'Friend';
        await syncChanges();
      case 'op':
        if (!canReceiveUpdates) {
          throw StateError('Read-only peer cannot send updates');
        }
        final op = Map<String, dynamic>.from(data['op'] as Map);
        if (op['kind'] == 'reminder') {
          throw const FormatException('Personal reminder received');
        }
        store.apply([op], scope: project);
        known.add(op['id'] as String);
        await send({'type': 'ack', 'id': op['id']});
        await requestPhotos();
      case 'ack':
        known.add(data['id'] as String);
      case 'complete':
        config['lastSync'] = DateTime.now().toUtc().toIso8601String();
        unawaited(manager.persist());
        updateStatus(
          requested.isEmpty
              ? 'Up to date · connected'
              : 'Connected · receiving photos',
        );
      case 'needPhoto':
        final hash = data['hash'] as String;
        if (!photoHashes().contains(hash)) {
          throw const FormatException('Photo outside project');
        }
        final file = store.blob(hash);
        if (!file.existsSync()) {
          await send({'type': 'missingPhoto', 'hash': hash});
          return;
        }
        final size = file.lengthSync();
        final offset = data['offset'] as int;
        if (offset < 0 || offset > size || size > 20 * 1024 * 1024) {
          throw const FormatException('Invalid transfer');
        }
        final reader = await file.open();
        try {
          await reader.setPosition(offset);
          var pos = offset;
          while (pos < size && connected) {
            final bytes = await reader.read(12000);
            await send({
              'type': 'photo',
              'hash': hash,
              'offset': pos,
              'size': size,
              'bytes': base64Encode(bytes),
            });
            pos += bytes.length;
          }
        } finally {
          await reader.close();
        }
      case 'missingPhoto':
        requested.remove(data['hash']);
        updateStatus('Photo pending on friend’s device');
      case 'photo':
        if (!canReceiveUpdates) {
          throw StateError('Read-only peer cannot send photos');
        }
        final hash = data['hash'] as String;
        if (!photoHashes().contains(hash)) {
          throw const FormatException('Unrequested photo');
        }
        final file = store.blob(hash),
            part = File('${store.blob(hash).path}.part');
        final size = data['size'] as int, offset = data['offset'] as int;
        if (size > 20 * 1024 * 1024 || size < 0 || offset < 0) {
          throw const FormatException('Photo too large');
        }
        await part.parent.create(recursive: true);
        final current = part.existsSync() ? part.lengthSync() : 0;
        if (current != offset) return;
        final bytes = base64Decode(data['bytes']);
        if (bytes.length > 12000 || current + bytes.length > size) {
          throw const FormatException('Invalid photo chunk');
        }
        await part.writeAsBytes(bytes, mode: FileMode.append, flush: true);
        if (part.lengthSync() == size) {
          if (hashes.sha256.convert(await part.readAsBytes()).toString() !=
              hash) {
            await part.delete();
            requested.remove(hash);
            throw const FormatException('Photo integrity check failed');
          }
          await part.rename(file.path);
          requested.remove(hash);
          store.touch();
          if (requested.isEmpty) updateStatus('Up to date · connected');
        }
      default:
        throw const FormatException('Unknown sync message');
    }
  }

  Future<void> closeTransport() async {
    pollTimer?.cancel();
    debounce?.cancel();
    reconnectTimer?.cancel();
    store.removeListener(onChange);
    connected = false;
    compatible = false;
    await channel?.close();
    await pc?.close();
    channel = null;
    pc = null;
    frames.clear();
  }

  Future<void> close() async {
    closed = true;
    await closeTransport();
  }
}
