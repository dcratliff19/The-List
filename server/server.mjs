import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { randomBytes, createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const DAY = 24 * 60 * 60 * 1000;
const MAX_REQUEST_BYTES = 512 * 1024;
const MAX_SIGNAL_BYTES = 1024 * 1024;
const MAX_MAILBOX_BYTES = 16 * 1024 * 1024;
const token = () => randomBytes(32).toString('base64url');
const digest = (value) => createHash('sha256').update(value).digest();
const matches = (value, hash) =>
  typeof value === 'string' && hash?.length === 32 && timingSafeEqual(digest(value), hash);

class RequestError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function json(res, status, data) {
  res.writeHead(status, {
    'content-type': 'application/json',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  });
  res.end(JSON.stringify(data));
}

async function read(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req.iterator({ destroyOnReturn: false })) {
    size += chunk.length;
    if (size > MAX_REQUEST_BYTES) {
      // Drain without destroying the socket so the client receives the 413.
      req.resume();
      throw new RequestError(413, 'Request too large');
    }
    chunks.push(chunk);
  }
  // Decode once: TCP chunks can split a multibyte UTF-8 character.
  const data = size ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {};
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new RequestError(400, 'Expected a JSON object');
  }
  return data;
}

function validAccess(access) {
  return access === 'read' || access === 'update';
}

function signal(data) {
  // Copy only protocol fields so arbitrary JSON cannot inflate the retained queue.
  switch (data.type) {
    case 'offer':
    case 'answer':
      if (typeof data.sdp === 'string' && data.sdp.length <= 65536) {
        return { type: data.type, sdp: data.sdp };
      }
      break;
    case 'candidate':
      if (
        typeof data.candidate === 'string' &&
        data.candidate.length <= 8192 &&
        (data.mid == null || (typeof data.mid === 'string' && data.mid.length <= 256)) &&
        (data.index == null ||
          (Number.isInteger(data.index) && data.index >= 0 && data.index <= 65535))
      ) {
        return {
          type: data.type,
          candidate: data.candidate,
          mid: data.mid,
          index: data.index,
        };
      }
      break;
    case 'ready':
    case 'bye':
      return { type: data.type };
  }
  throw new RequestError(400, 'Invalid signal');
}

/** Hashed credentials and opaque mailbox updates are durable; SDP/ICE events are ephemeral. */
export function createSignalingServer({
  now = Date.now,
  roomTtl = 90 * DAY,
  inviteTtl = 15 * 60 * 1000,
  maxRooms = 1000,
  turnUrls = process.env.TURN_URLS,
  turnSecret = process.env.TURN_SECRET,
  stateFile = process.env.STATE_FILE,
  iceServersUrl = process.env.ICE_SERVERS_URL,
  fetchIce = fetch,
} = {}) {
  const rooms = new Map();
  const rates = new Map();
  if (stateFile && fs.existsSync(stateFile)) {
    const saved = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
    for (const [id, room] of saved.rooms ?? []) {
      if (room.expires <= now()) continue;
      rooms.set(id, {
        ...room,
        host: Buffer.from(room.host, 'base64'),
        invite: Buffer.from(room.invite, 'base64'),
        guest: room.guest ? Buffer.from(room.guest, 'base64') : null,
        events: [],
      });
    }
  }

  let dirty = false;
  function persist() {
    if (!stateFile || !dirty) return;
    fs.mkdirSync(path.dirname(stateFile), { recursive: true });
    const records = [...rooms].map(([id, room]) => [
      id,
      {
        ...room,
        host: room.host.toString('base64'),
        invite: room.invite.toString('base64'),
        guest: room.guest?.toString('base64') ?? null,
        events: [],
      },
    ]);
    // Rename a complete private snapshot, keeping the previous file intact on write failure.
    fs.writeFileSync(`${stateFile}.tmp`, JSON.stringify({ version: 1, rooms: records }), {
      mode: 0o600,
    });
    fs.renameSync(`${stateFile}.tmp`, stateFile);
    dirty = false;
  }
  function changed() {
    dirty = true;
    persist();
  }
  function checkpoint() {
    try {
      persist();
    } catch {
      // Keep dirty state for the next retry without logging secrets or crashing a timer.
      console.error('The List signaling could not persist its state.');
    }
  }
  function expireRooms() {
    for (const [id, room] of rooms) {
      if (room.expires <= now()) {
        rooms.delete(id);
        dirty = true;
      }
    }
  }

  let iceCache = null;
  let iceCacheUntil = 0;
  async function ice() {
    if (iceServersUrl) {
      if (iceCache && iceCacheUntil > now()) return iceCache;
      try {
        const endpoint = new URL(iceServersUrl);
        if (endpoint.protocol !== 'https:') throw new Error('ICE provider must use HTTPS');
        const response = await fetchIce(endpoint, {
          signal: AbortSignal.timeout(8000),
        });
        if (!response.ok) throw new Error('ICE provider unavailable');
        const data = await response.json();
        const values = Array.isArray(data) ? data : data?.iceServers;
        if (!Array.isArray(values) || !values.length) throw new Error('Invalid ICE response');
        iceCache = values;
        iceCacheUntil = now() + 60000;
        return values;
      } catch {
        throw new RequestError(503, 'Connection relay unavailable. Try again shortly.');
      }
    }
    const servers = [{ urls: 'stun:stun.l.google.com:19302' }];
    if (turnUrls && turnSecret) {
      const username = `${Math.floor(now() / 1000) + 3600}:the-list`;
      servers.push({
        urls: turnUrls
          .split(',')
          .map((value) => value.trim())
          .filter(Boolean),
        username,
        credential: createHmac('sha1', turnSecret).update(username).digest('base64'),
      });
    }
    return servers;
  }

  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      const address =
        process.env.TRUST_PROXY === 'true'
          ? String(req.headers['x-forwarded-for'] || '')
              .split(',')
              .at(-1)
              .trim() || req.socket.remoteAddress
          : req.socket.remoteAddress || 'unknown';
      if (req.method === 'GET' && url.pathname === '/health') {
        return json(res, 200, {
          ok: true,
          service: 'The List signaling',
          relayConfigured: !!((turnUrls && turnSecret) || iceServersUrl),
        });
      }
      let limit = rates.get(address);
      if (!limit || now() - limit.start >= 60000) {
        limit = { start: now(), count: 0 };
        rates.set(address, limit);
      }
      if (++limit.count > 600) {
        return json(res, 429, {
          error: 'Too many requests. Try again shortly.',
        });
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
      room.expires = now() + roomTtl;
      dirty = true;
      if (parts[3] === 'access' && req.method === 'GET') {
        return json(res, 200, { access: room.access ?? 'update' });
      }
      if (parts[3] === 'access' && req.method === 'PATCH') {
        if (role !== 'host') throw new RequestError(403, 'Only the owner can change access');
        const data = await read(req);
        if (!validAccess(data.access)) throw new RequestError(400, 'Invalid access');
        room.access = data.access;
        if (room.access === 'read')
          room.mailbox = (room.mailbox ?? []).filter((entry) => entry.from === 'host');
        changed();
        return json(res, 200, { access: room.access });
      }

      if (parts[3] === 'mailbox') {
        room.mailbox ??= [];
        room.mailbox = room.mailbox.filter((entry) => entry.expires > now());
        if (req.method === 'POST') {
          const data = await read(req);
          // Check after reading the body so an in-flight downgrade also blocks uploads.
          if (role === 'guest' && room.access === 'read')
            throw new RequestError(403, 'This project is read-only');
          if (
            typeof data.id !== 'string' ||
            !data.id ||
            data.id.length > 100 ||
            typeof data.payload !== 'string' ||
            !data.payload ||
            data.payload.length > 400000
          ) {
            throw new RequestError(400, 'Invalid encrypted update');
          }
          const previous = room.mailbox.find(
            (entry) => entry.id === data.id && entry.from === role,
          );
          if (!previous) {
            const bytes = room.mailbox.reduce(
              (sum, entry) => sum + Buffer.byteLength(entry.payload),
              0,
            );
            if (
              room.mailbox.length >= 2000 ||
              bytes + Buffer.byteLength(data.payload) > MAX_MAILBOX_BYTES
            ) {
              throw new RequestError(
                507,
                'Offline mailbox full. Connect peers directly to finish syncing.',
              );
            }
            room.mailbox.push({
              id: data.id,
              payload: data.payload,
              from: role,
              expires: now() + 30 * DAY,
            });
            changed();
          }
          return json(res, 200, { stored: true });
        }
        if (req.method === 'GET') {
          const updates = [];
          let bytes = 0;
          for (const entry of room.mailbox.filter((entry) => entry.from !== role)) {
            const size = Buffer.byteLength(
              JSON.stringify({ id: entry.id, payload: entry.payload }),
            );
            if (updates.length >= 25 || bytes + size > 1000000) break;
            updates.push({ id: entry.id, payload: entry.payload });
            bytes += size;
          }
          return json(res, 200, { updates });
        }
        if (req.method === 'DELETE') {
          const data = await read(req);
          if (
            !Array.isArray(data.ids) ||
            data.ids.length > 25 ||
            data.ids.some((id) => typeof id !== 'string')
          ) {
            throw new RequestError(400, 'Invalid acknowledgement');
          }
          room.mailbox = room.mailbox.filter(
            (entry) => entry.from === role || !data.ids.includes(entry.id),
          );
          changed();
          return json(res, 200, { acknowledged: true });
        }
      }
      if (req.method === 'GET' && parts[3] === 'ice') {
        return json(res, 200, {
          access: room.access ?? 'update',
          iceServers: await ice(),
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
      const status =
        error instanceof RequestError ? error.status : error instanceof SyntaxError ? 400 : 500;
      json(res, status, {
        error:
          error instanceof RequestError
            ? error.message
            : status === 400
              ? 'Invalid request'
              : 'Sharing service unavailable. Try again shortly.',
      });
    }
  });

  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  const checkpointTimer = setInterval(checkpoint, 5000);
  checkpointTimer.unref();
  const cleanup = setInterval(() => {
    for (const [key, value] of rates) if (now() - value.start >= 60000) rates.delete(key);
    expireRooms();
  }, 60000);
  cleanup.unref();
  server.on('close', () => {
    clearInterval(cleanup);
    clearInterval(checkpointTimer);
    checkpoint();
  });
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT || 5174);
  createSignalingServer().listen(port, process.env.HOST || '127.0.0.1', () => {
    console.log(`The List signaling listening on port ${port}`);
  });
}
