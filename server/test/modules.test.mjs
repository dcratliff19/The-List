import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRateLimiter } from '../src/rate-limiter.mjs';
import { createIceProvider } from '../src/ice-provider.mjs';

test('rate limiting isolates clients and resets at the exact window boundary', () => {
  let clock = 0;
  const limiter = createRateLimiter({ now: () => clock, maxRequests: 2, windowMs: 100 });
  assert.equal(limiter.allow('a'), true);
  assert.equal(limiter.allow('a'), true);
  assert.equal(limiter.allow('a'), false);
  assert.equal(limiter.allow('b'), true);
  clock = 99;
  assert.equal(limiter.allow('a'), false);
  clock = 100;
  limiter.cleanup();
  assert.equal(limiter.allow('a'), true);
});

test('relay credentials cache until expiry and recover after provider failure', async () => {
  let clock = 0;
  let calls = 0;
  let fail = false;
  const ice = createIceProvider({
    now: () => clock,
    iceServersUrl: 'https://relay.example/ice',
    fetchIce: async (url, options) => {
      assert.equal(url.protocol, 'https:');
      assert.ok(options.signal);
      calls++;
      if (fail) throw new Error('Provider secret must not reach clients');
      return { ok: true, json: async () => ({ iceServers: [{ urls: 'turn:relay.example' }] }) };
    },
  });
  assert.deepEqual(await ice(), [{ urls: 'turn:relay.example' }]);
  clock = 59999;
  await ice();
  assert.equal(calls, 1);
  clock = 60000;
  fail = true;
  await assert.rejects(ice(), {
    status: 503,
    message: 'Connection relay unavailable. Try again shortly.',
  });
  fail = false;
  await ice();
  assert.equal(calls, 3);
});
