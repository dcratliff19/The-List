import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:crypto/crypto.dart' as hashes;
import '../../store.dart';
import 'peer_host.dart';
import 'encrypted_messages.dart';
import 'frame_assembler.dart';

part 'peer_transport.dart';

/// Serializes encrypted frames on one peer channel and enforces its access role.
class PeerSession {
  final PeerHost manager;
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
  final frames = FrameAssembler();
  late final messages = EncryptedMessages(config['key'] as String);
  PeerSession(this.manager, this.config) {
    // SQLite is updated immediately on permission changes; the secure vault
    // can still contain an older snapshot if the app exits before persisting.
    final room = config['room'];
    final saved = room is String
        ? store.projectAccess(project, room, config['host'] == true)
        : null;
    if (saved != null) config['access'] = saved;
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

  Future<void> send(Json data) {
    outgoing = outgoing
        .then((_) async {
          if (!connected || channel == null) return;
          final envelope = await messages.encrypt(data);
          final count = (envelope.length / FrameAssembler.chunkSize).ceil(),
              id = uuid.v4();
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
                    index * FrameAssembler.chunkSize,
                    min(
                      (index + 1) * FrameAssembler.chunkSize,
                      envelope.length,
                    ),
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
    final envelope = frames.add(text);
    if (envelope != null) await receive(await messages.decrypt(envelope));
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
