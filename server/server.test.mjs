import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createSignalingServer } from './server.mjs';

async function fixture(t, options = {}) {
  const server = createSignalingServer(options);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const close = async () => {
    if (server.listening) await new Promise((resolve) => server.close(resolve));
  };
  t.after(close);
  const call = (path, method = 'GET', token, body) =>
    fetch(origin + path, {
      method,
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  return { server, origin, call, close };
}

async function data(response, expectedStatus = 200) {
  assert.equal(response.status, expectedStatus);
  return response.json();
}

const iceResponse = () => ({
  ok: true,
  json: async () => ({ iceServers: [{ urls: 'turn:relay.example:3478' }] }),
});

test('single-use invitations, isolated signaling, authentication, and revocation', async (t) => {
  const { call } = await fixture(t);
  const room = await data(await call('/rooms', 'POST'), 201);
  const path = `/rooms/${room.id}`;
  assert.equal((await call(`${path}/events`)).status, 403);
  const guest = await data(await call(`${path}/join`, 'POST', room.invite));
  assert.ok(guest.token);
  assert.equal((await call(`${path}/join`, 'POST', room.invite)).status, 403);
  await data(
    await call(`${path}/signals`, 'POST', room.token, {
      type: 'offer',
      sdp: 'test',
    }),
  );
  assert.equal(
    (await data(await call(`${path}/events`, 'GET', guest.token))).events[0].sdp,
    'test',
  );
  assert.deepEqual((await data(await call(`${path}/events`, 'GET', room.token))).events, []);
  assert.equal(
    (await call(`${path}/signals`, 'POST', guest.token, { type: 'content' })).status,
    400,
  );
  await data(await call(path, 'DELETE', room.token));
  assert.equal((await call(`${path}/events`, 'GET', guest.token)).status, 404);
});

test('invitations expire at the exact deadline', async (t) => {
  let clock = 0;
  const { call } = await fixture(t, { now: () => clock, inviteTtl: 100 });
  const room = await data(await call('/rooms', 'POST'), 201);
  clock = 100;
  assert.equal((await call(`/rooms/${room.id}/join`, 'POST', room.invite)).status, 403);
});

test('authenticated activity extends sessions and reconnect refreshes TURN credentials', async (t) => {
  let clock = 0;
  const { call } = await fixture(t, {
    now: () => clock,
    roomTtl: 100000,
    turnUrls: 'turn:relay.example:3478',
    turnSecret: 'test-only-secret',
  });
  const room = await data(await call('/rooms', 'POST'), 201);
  const path = `/rooms/${room.id}`;
  assert.equal((await call(`${path}/ice`)).status, 403);
  clock = 90000;
  await data(await call(`${path}/events`, 'GET', room.token));
  clock = 150000;
  const refreshed = (await data(await call(`${path}/ice`, 'GET', room.token))).iceServers[1];
  assert.equal(refreshed.urls[0], 'turn:relay.example:3478');
  assert.notEqual(refreshed.credential, room.iceServers[1].credential);
  assert.equal(refreshed.username, '3750:the-list');
  clock = 250000;
  assert.equal((await call(`${path}/ice`, 'GET', room.token)).status, 404);
});

test('paired credentials survive a signaling server restart', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'the-list-server-'));
  const options = { stateFile: join(directory, 'rooms.json') };
  let current = await fixture(t, options);
  try {
    const room = await data(await current.call('/rooms', 'POST'), 201);
    const path = `/rooms/${room.id}`;
    const guest = await data(await current.call(`${path}/join`, 'POST', room.invite));
    await current.close();
    current = await fixture(t, options);
    await data(await current.call(`${path}/ice`, 'GET', guest.token));
    assert.equal((await current.call(`${path}/join`, 'POST', room.invite)).status, 403);
    await data(await current.call(path, 'DELETE', room.token));
    await current.close();
    current = await fixture(t, options);
    assert.equal((await current.call(`${path}/ice`, 'GET', guest.token)).status, 404);
  } finally {
    await current.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test('encrypted mailbox isolates recipients, persists, acknowledges and expires', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'the-list-mailbox-'));
  let clock = Date.now();
  const options = {
    stateFile: join(directory, 'state.json'),
    now: () => clock,
  };
  let current = await fixture(t, options);
  try {
    const room = await data(await current.call('/rooms', 'POST'), 201);
    const path = `/rooms/${room.id}`;
    const guest = await data(await current.call(`${path}/join`, 'POST', room.invite));
    const mailbox = `${path}/mailbox`;
    const update = { id: 'op-1', payload: 'ciphertext' };
    assert.equal((await current.call(mailbox)).status, 403);
    await data(await current.call(mailbox, 'POST', room.token, update));
    await data(await current.call(mailbox, 'POST', room.token, update));
    assert.deepEqual((await data(await current.call(mailbox, 'GET', room.token))).updates, []);
    await data(await current.call(mailbox, 'DELETE', room.token, { ids: ['op-1'] }));
    await current.close();
    current = await fixture(t, options);
    assert.deepEqual((await data(await current.call(mailbox, 'GET', guest.token))).updates, [
      update,
    ]);
    await data(await current.call(mailbox, 'DELETE', guest.token, { ids: ['op-1'] }));
    assert.deepEqual((await data(await current.call(mailbox, 'GET', guest.token))).updates, []);
    assert.equal(
      (
        await current.call(mailbox, 'POST', room.token, {
          id: 'huge',
          payload: 'x'.repeat(400001),
        })
      ).status,
      400,
    );
    await data(
      await current.call(mailbox, 'POST', room.token, {
        id: 'op-2',
        payload: 'ciphertext',
      }),
    );
    clock += 31 * 24 * 60 * 60 * 1000;
    assert.deepEqual((await data(await current.call(mailbox, 'GET', guest.token))).updates, []);
  } finally {
    await current.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test('read-only access is authoritative, owner-controlled and blocks queued writes', async (t) => {
  const { call } = await fixture(t);
  const room = await data(await call('/rooms', 'POST', undefined, { access: 'read' }), 201);
  const path = `/rooms/${room.id}`;
  assert.equal(room.access, 'read');
  const guest = await data(await call(`${path}/join`, 'POST', room.invite, { access: 'update' }));
  assert.equal(guest.access, 'read');
  assert.equal(
    (
      await call(`${path}/mailbox`, 'POST', guest.token, {
        id: 'blocked',
        payload: 'encrypted',
      })
    ).status,
    403,
  );
  assert.equal(
    (await call(`${path}/access`, 'PATCH', guest.token, { access: 'update' })).status,
    403,
  );
  await data(
    await call(`${path}/mailbox`, 'POST', room.token, {
      id: 'owner',
      payload: 'encrypted',
    }),
  );
  assert.equal((await data(await call(`${path}/mailbox`, 'GET', guest.token))).updates.length, 1);
  await data(await call(`${path}/access`, 'PATCH', room.token, { access: 'update' }));
  await data(
    await call(`${path}/mailbox`, 'POST', guest.token, {
      id: 'guest',
      payload: 'encrypted',
    }),
  );
  await data(await call(`${path}/access`, 'PATCH', room.token, { access: 'read' }));
  assert.equal((await data(await call(`${path}/events`, 'GET', guest.token))).access, 'read');
  assert.deepEqual((await data(await call(`${path}/mailbox`, 'GET', room.token))).updates, []);
  assert.equal(
    (await call(`${path}/access`, 'PATCH', room.token, { access: 'admin' })).status,
    400,
  );
});

test('an in-flight guest upload is rejected after an owner downgrade', async (t) => {
  const { call, origin } = await fixture(t);
  const room = await data(await call('/rooms', 'POST'), 201);
  const path = `/rooms/${room.id}`;
  const guest = await data(await call(`${path}/join`, 'POST', room.invite));
  let request;
  const uploaded = new Promise((resolve, reject) => {
    request = http.request(
      `${origin}${path}/mailbox`,
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${guest.token}`,
          'content-type': 'application/json',
        },
      },
      (response) => {
        response.resume();
        response.on('end', () => resolve(response.statusCode));
      },
    );
    request.on('error', reject);
    request.write('{"id":"in-flight","payload":"');
  });
  try {
    // Hold the body open while a separate authenticated request changes access.
    await new Promise((resolve) => setTimeout(resolve, 20));
    await data(await call(`${path}/access`, 'PATCH', room.token, { access: 'read' }));
    request.end('encrypted"}');
    assert.equal(await uploaded, 403);
    assert.deepEqual((await data(await call(`${path}/mailbox`, 'GET', room.token))).updates, []);
  } finally {
    request.destroy();
  }
});

test('relay failures preserve capacity and leave invitations redeemable', async (t) => {
  let clock = 0;
  let failing = true;
  const { call } = await fixture(t, {
    now: () => clock,
    maxRooms: 1,
    iceServersUrl: 'https://relay.example/ice',
    fetchIce: async () => {
      if (failing) throw new Error('Provider outage');
      return iceResponse();
    },
  });
  assert.equal((await call('/rooms', 'POST')).status, 503);
  failing = false;
  const room = await data(await call('/rooms', 'POST'), 201);
  clock = 60001; // Expire only the provider cache.
  failing = true;
  assert.equal((await call(`/rooms/${room.id}/join`, 'POST', room.invite)).status, 503);
  failing = false;
  const guest = await data(await call(`/rooms/${room.id}/join`, 'POST', room.invite));
  assert.ok(guest.token);
});

test('concurrent invitation joins issue exactly one guest credential', async (t) => {
  let clock = 0;
  let arrivals = 0;
  let release;
  const gate = new Promise((resolve) => {
    release = resolve;
  });
  const { call } = await fixture(t, {
    now: () => clock,
    iceServersUrl: 'https://relay.example/ice',
    fetchIce: async () => {
      if (clock > 0) {
        if (++arrivals === 2) release();
        await gate;
      }
      return iceResponse();
    },
  });
  const room = await data(await call('/rooms', 'POST'), 201);
  clock = 60001;
  const responses = await Promise.all([
    call(`/rooms/${room.id}/join`, 'POST', room.invite),
    call(`/rooms/${room.id}/join`, 'POST', room.invite),
  ]);
  assert.deepEqual(responses.map((response) => response.status).sort(), [200, 403]);
  const guest = await responses.find((response) => response.status === 200).json();
  await data(await call(`/rooms/${room.id}/events`, 'GET', guest.token));
});

test('malformed JSON objects, cursors and nested routes are rejected', async (t) => {
  const { call } = await fixture(t);
  for (const body of [null, [], 'text']) {
    assert.equal((await call('/rooms', 'POST', undefined, body)).status, 400);
  }
  assert.equal(
    (
      await call('/rooms', 'POST', undefined, {
        extra: 'x'.repeat(512 * 1024),
      })
    ).status,
    413,
  );
  const room = await data(await call('/rooms', 'POST'), 201);
  const path = `/rooms/${room.id}`;
  for (const cursor of ['NaN', '-1', '1.5', '9007199254740992']) {
    assert.equal((await call(`${path}/events?after=${cursor}`, 'GET', room.token)).status, 400);
  }
  assert.equal(
    (
      await call(`${path}/access/extra`, 'PATCH', room.token, {
        access: 'read',
      })
    ).status,
    404,
  );
});

test('signal validation and byte limits keep event responses bounded', async (t) => {
  const { call } = await fixture(t);
  const room = await data(await call('/rooms', 'POST'), 201);
  const path = `/rooms/${room.id}`;
  const guest = await data(await call(`${path}/join`, 'POST', room.invite));
  for (const body of [
    { type: 'offer', sdp: 42 },
    { type: 'offer', sdp: 'x'.repeat(65537) },
    { type: 'candidate', candidate: [], index: -1 },
  ]) {
    assert.equal((await call(`${path}/signals`, 'POST', room.token, body)).status, 400);
  }
  for (let index = 0; index < 8; index++) {
    await data(
      await call(`${path}/signals`, 'POST', room.token, {
        type: 'offer',
        sdp: '\u0000'.repeat(65536),
        extra: 'discard me',
      }),
    );
  }
  const response = await call(`${path}/events`, 'GET', guest.token);
  assert.equal(response.status, 200);
  const body = await response.text();
  assert.ok(Buffer.byteLength(body) < 1024 * 1024 + 1024);
  const events = JSON.parse(body).events;
  assert.ok(events.length > 0 && events.length < 8);
  assert.ok(events.every((event) => !('extra' in event)));
});

test('UTF-8 characters survive request body chunk boundaries', async (t) => {
  const { call, origin } = await fixture(t);
  const room = await data(await call('/rooms', 'POST'), 201);
  const path = `/rooms/${room.id}`;
  const guest = await data(await call(`${path}/join`, 'POST', room.invite));
  const body = Buffer.from(JSON.stringify({ type: 'offer', sdp: 'A😊Z' }));
  const split = body.indexOf(Buffer.from('😊')) + 1;
  await new Promise((resolve, reject) => {
    const req = http.request(
      `${origin}${path}/signals`,
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${room.token}`,
          'content-type': 'application/json',
        },
      },
      (res) => {
        res.resume();
        res.on('end', () => {
          try {
            assert.equal(res.statusCode, 200);
            resolve();
          } catch (error) {
            reject(error);
          }
        });
      },
    );
    req.on('error', reject);
    req.write(body.subarray(0, split));
    setTimeout(() => req.end(body.subarray(split)), 20);
  });
  const events = (await data(await call(`${path}/events`, 'GET', guest.token))).events;
  assert.equal(events[0].sdp, 'A😊Z');
});
