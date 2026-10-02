import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { DAY } from './src/limits.mjs';
import { createRoomStore } from './src/room-store.mjs';
import { createIceProvider } from './src/ice-provider.mjs';
import { createRateLimiter } from './src/rate-limiter.mjs';
import { createRequestHandler } from './src/routes.mjs';

/** Composition root; importing this module never starts a listener. */
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
  trustProxy = process.env.TRUST_PROXY === 'true',
} = {}) {
  const store = createRoomStore({ stateFile, now });
  const limiter = createRateLimiter({ now });
  const ice = createIceProvider({ now, iceServersUrl, fetchIce, turnUrls, turnSecret });
  const server = http.createServer(
    createRequestHandler({
      store,
      ice,
      limiter,
      now,
      roomTtl,
      inviteTtl,
      maxRooms,
      trustProxy,
      relayConfigured: !!((turnUrls && turnSecret) || iceServersUrl),
    }),
  );

  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  const checkpointTimer = setInterval(store.checkpoint, 5000);
  checkpointTimer.unref();
  const cleanup = setInterval(() => {
    limiter.cleanup();
    store.expireRooms();
  }, 60000);
  cleanup.unref();
  server.on('close', () => {
    clearInterval(cleanup);
    clearInterval(checkpointTimer);
    store.checkpoint();
  });
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT || 5174);
  createSignalingServer().listen(port, process.env.HOST || '127.0.0.1', () => {
    console.log(`The List signaling listening on port ${port}`);
  });
}
