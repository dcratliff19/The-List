import fs from 'node:fs';
import path from 'node:path';

/** Owns durable room state. Signaling events are intentionally never restored. */
export function createRoomStore({ stateFile, now }) {
  const rooms = new Map();
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

  return {
    rooms,
    changed,
    checkpoint,
    expireRooms,
    touch: () => {
      dirty = true;
    },
  };
}
