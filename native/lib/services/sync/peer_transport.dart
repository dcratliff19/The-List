part of 'peer_session.dart';

/// Negotiation, ICE candidate ordering and channel lifecycle for one session.
extension _PeerTransport on PeerSession {
  Future<void> _connect() async {
    if (pc != null) await closeTransport();
    closed = false;
    known.clear();
    requested.clear();
    remoteSet = false;
    candidates.clear();
    final connectivity = await request('ice');
    if (manager.disposed || closed) return;
    acceptAccess(connectivity);
    await manager.persist();
    if (manager.disposed || closed) return;
    config['iceServers'] = connectivity['iceServers'];
    pc = await createPeerConnection({'iceServers': config['iceServers'] ?? []});
    if (manager.disposed || closed) {
      await closeTransport();
      return;
    }
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
}
