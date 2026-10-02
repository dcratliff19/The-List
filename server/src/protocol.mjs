import { randomBytes, createHash, timingSafeEqual } from 'node:crypto';
import { RequestError } from './http.mjs';

export const token = () => randomBytes(32).toString('base64url');
export const digest = (value) => createHash('sha256').update(value).digest();
export const matches = (value, hash) =>
  typeof value === 'string' && hash?.length === 32 && timingSafeEqual(digest(value), hash);

export function validAccess(access) {
  return access === 'read' || access === 'update';
}

export function signal(data) {
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
