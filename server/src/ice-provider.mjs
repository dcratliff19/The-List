import { createHmac } from 'node:crypto';
import { RequestError } from './http.mjs';

/** Fetches short-lived relay credentials without issuing room credentials on failure. */
export function createIceProvider({ now, iceServersUrl, fetchIce, turnUrls, turnSecret }) {
  let iceCache = null;
  let iceCacheUntil = 0;
  async function getIceServers() {
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

  return getIceServers;
}
