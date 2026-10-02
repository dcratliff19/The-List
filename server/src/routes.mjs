import { RequestError, json, read } from './http.mjs';
import { token, digest, matches, validAccess, signal } from './protocol.mjs';
import { MAX_SIGNAL_BYTES } from './limits.mjs';
import { handleMailbox } from './mailbox.mjs';

/** HTTP protocol adapter. Async credential lookups recheck invitation ownership. */
export function createRequestHandler({
  store,
  ice,
  limiter,
  now,
  roomTtl,
  inviteTtl,
  maxRooms,
  relayConfigured,
  trustProxy,
}) {
  const { rooms, changed, expireRooms } = store;
  return async (req, res) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      const address = trustProxy
        ? String(req.headers['x-forwarded-for'] || '')
            .split(',')
            .at(-1)
            .trim() || req.socket.remoteAddress
        : req.socket.remoteAddress || 'unknown';
      if (req.method === 'GET' && url.pathname === '/health') {
        return json(res, 200, {
          ok: true,
          service: 'The List signaling',
          relayConfigured: relayConfigured,
        });
      }
      if (!limiter.allow(address)) {
        return json(res, 429, { error: 'Too many requests. Try again shortly.' });
      }
      expireRooms();

      if (req.method === 'POST' && url.pathname === '/rooms') {
        const data = await read(req);
        const access = data.access ?? 'update';
        if (!validAccess(access)) throw new RequestError(400, 'Invalid access');
        if (rooms.size >= maxRooms) throw new RequestError(503, 'Server capacity reached');
        // Fetch before issuing credentials: a provider outage must not create orphan rooms.
        const iceServers = await ice();
        expireRooms();
        if (rooms.size >= maxRooms) throw new RequestError(503, 'Server capacity reached');
        const id = token();
        const host = token();
        const invite = token();
        const inviteExpires = now() + inviteTtl;
        rooms.set(id, {
          access,
          host: digest(host),
          invite: digest(invite),
          guest: null,
          inviteExpires,
          expires: now() + roomTtl,
          events: [],
          seq: 0,
        });
        changed();
        return json(res, 201, {
          id,
          access,
          token: host,
          invite,
          expiresAt: inviteExpires,
          iceServers,
        });
      }

      const parts = url.pathname.split('/');
      const room = rooms.get(parts[2]);
      if (parts[1] !== 'rooms' || !room || parts.length > 4) {
        throw new RequestError(404, 'This sharing session has expired. Create a new invitation.');
      }
      const credential = (req.headers.authorization || '').replace(/^Bearer /, '');
      if (req.method === 'POST' && parts[3] === 'join') {
        const joinable = () =>
          rooms.get(parts[2]) === room &&
          room.expires > now() &&
          !room.guest &&
          room.inviteExpires > now() &&
          matches(credential, room.invite);
        if (!joinable())
          throw new RequestError(403, 'Invitation invalid, expired, or already used');
        const iceServers = await ice();
        // Another join, expiry or owner revocation may have happened during the lookup.
        if (!joinable())
          throw new RequestError(403, 'Invitation invalid, expired, or already used');
        const guest = token();
        room.guest = digest(guest);
        room.expires = now() + roomTtl;
        changed();
        return json(res, 200, {
          token: guest,
          access: room.access ?? 'update',
          iceServers,
        });
      }

      const role = matches(credential, room.host)
        ? 'host'
        : room.guest && matches(credential, room.guest)
          ? 'guest'
          : null;
      if (!role) throw new RequestError(403, 'Not authorized');
      const assertActive = () => {
        if (rooms.get(parts[2]) !== room || room.expires <= now()) {
          throw new RequestError(404, 'This sharing session has expired. Create a new invitation.');
        }
      };
      room.expires = now() + roomTtl;
      store.touch();
      if (parts[3] === 'access' && req.method === 'GET') {
        return json(res, 200, { access: room.access ?? 'update' });
      }
      if (parts[3] === 'access' && req.method === 'PATCH') {
        if (role !== 'host') throw new RequestError(403, 'Only the owner can change access');
        const data = await read(req);
        if (!validAccess(data.access)) throw new RequestError(400, 'Invalid access');
        assertActive();
        room.access = data.access;
        if (room.access === 'read')
          room.mailbox = (room.mailbox ?? []).filter((entry) => entry.from === 'host');
        changed();
        return json(res, 200, { access: room.access });
      }

      if (parts[3] === 'mailbox') {
        return await handleMailbox({ req, res, room, role, now, changed, assertActive });
      }
      if (req.method === 'GET' && parts[3] === 'ice') {
        const iceServers = await ice();
        assertActive();
        return json(res, 200, {
          access: room.access ?? 'update',
          iceServers,
        });
      }
      if (req.method === 'GET' && parts[3] === 'events') {
        const after = Number(url.searchParams.get('after') || 0);
        if (!Number.isSafeInteger(after) || after < 0)
          throw new RequestError(400, 'Invalid event cursor');
        return json(res, 200, {
          access: room.access ?? 'update',
          events: room.events.filter((entry) => entry.from !== role && entry.seq > after),
          sequence: room.seq,
          paired: !!room.guest,
        });
      }
      if (req.method === 'POST' && parts[3] === 'signals') {
        const data = signal(await read(req));
        assertActive();
        room.events.push({ ...data, seq: ++room.seq, from: role });
        let bytes = room.events.reduce(
          (sum, entry) => sum + Buffer.byteLength(JSON.stringify(entry)),
          0,
        );
        while (room.events.length > 512 || bytes > MAX_SIGNAL_BYTES) {
          bytes -= Buffer.byteLength(JSON.stringify(room.events.shift()));
        }
        return json(res, 200, { sequence: room.seq });
      }
      if (req.method === 'DELETE' && parts.length === 3 && role === 'host') {
        rooms.delete(parts[2]);
        changed();
        return json(res, 200, { closed: true });
      }
      throw new RequestError(404, 'Not found');
    } catch (error) {
      const status = error instanceof RequestError ? error.status : 500;
      json(res, status, {
        error:
          error instanceof RequestError
            ? error.message
            : 'Sharing service unavailable. Try again shortly.',
      });
    }
  };
}
