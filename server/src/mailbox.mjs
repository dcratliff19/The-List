import { RequestError, json, read } from './http.mjs';
import { DAY, MAX_MAILBOX_BYTES } from './limits.mjs';

/** Opaque updates are isolated by sender role and bounded by count and UTF-8 bytes. */
export async function handleMailbox({ req, res, room, role, now, changed, assertActive }) {
  room.mailbox ??= [];
  room.mailbox = room.mailbox.filter((entry) => entry.expires > now());
  if (req.method === 'POST') {
    const data = await read(req);
    assertActive();
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
    const previous = room.mailbox.find((entry) => entry.id === data.id && entry.from === role);
    if (!previous) {
      const bytes = room.mailbox.reduce((sum, entry) => sum + Buffer.byteLength(entry.payload), 0);
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
      const size = Buffer.byteLength(JSON.stringify({ id: entry.id, payload: entry.payload }));
      if (updates.length >= 25 || bytes + size > 1000000) break;
      updates.push({ id: entry.id, payload: entry.payload });
      bytes += size;
    }
    return json(res, 200, { updates });
  }
  if (req.method === 'DELETE') {
    const data = await read(req);
    assertActive();
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
  return json(res, 404, { error: 'Not found' });
}
