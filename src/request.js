import { isIP } from 'node:net';

const validIp = (value) => {
  const candidate = String(value || '').trim();
  return isIP(candidate) ? candidate : null;
};

/**
 * Resolves the client address without accepting forged forwarding headers.
 * `trustProxy` is safe only when the API is private and its immediate proxy
 * overwrites X-Forwarded-For before forwarding requests.
 */
export function clientIp(req, { trustProxy = false } = {}) {
  const socketIp = validIp(req?.socket?.remoteAddress);
  if (!trustProxy) return socketIp || 'unknown';
  const forwarded = String(req?.headers?.['x-forwarded-for'] || '')
    .split(',')
    .map(validIp)
    .find(Boolean);
  return forwarded || socketIp || 'unknown';
}
