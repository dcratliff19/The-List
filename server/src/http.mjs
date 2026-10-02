import { MAX_REQUEST_BYTES } from './limits.mjs';

export class RequestError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function json(res, status, data) {
  res.writeHead(status, {
    'content-type': 'application/json',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  });
  res.end(JSON.stringify(data));
}

export async function read(req) {
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
  let data;
  try {
    data = size ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {};
  } catch {
    throw new RequestError(400, 'Invalid request');
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new RequestError(400, 'Expected a JSON object');
  }
  return data;
}
