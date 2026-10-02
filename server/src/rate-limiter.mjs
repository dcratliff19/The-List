/** Fixed-window limiter with injectable time and periodic removal of idle clients. */
export function createRateLimiter({ now, windowMs = 60000, maxRequests = 600 }) {
  const clients = new Map();
  return {
    allow(address) {
      let limit = clients.get(address);
      if (!limit || now() - limit.start >= windowMs) {
        limit = { start: now(), count: 0 };
        clients.set(address, limit);
      }
      return ++limit.count <= maxRequests;
    },
    cleanup() {
      for (const [address, limit] of clients) {
        if (now() - limit.start >= windowMs) clients.delete(address);
      }
    },
  };
}
