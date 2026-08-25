import crypto from 'node:crypto';

const base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const timingEqual = (left, right) => {
  const a = Buffer.from(String(left));
  const b = Buffer.from(String(right));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
};

export const encodeBase32 = (bytes) => {
  let value = 0;
  let bits = 0;
  let result = '';
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      result += base32Alphabet[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  return result + (bits ? base32Alphabet[(value << (5 - bits)) & 31] : '');
};

export const decodeBase32 = (input) => {
  const text = String(input || '').replace(/[\s=-]/g, '').toUpperCase();
  if (!text || !/^[A-Z2-7]+$/.test(text)) throw Object.assign(new Error('动态口令密钥格式不正确'), { code: 'MFA_SECRET_INVALID' });
  let value = 0;
  let bits = 0;
  const bytes = [];
  for (const char of text) {
    value = (value << 5) | base32Alphabet.indexOf(char);
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
};

export const createTotpSecret = () => encodeBase32(crypto.randomBytes(20));

export const normalizeOtp = (value) => String(value || '').replace(/[\s-]/g, '');

export const totpCode = (secret, counter) => {
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(counter));
  const digest = crypto.createHmac('sha1', decodeBase32(secret)).update(message).digest();
  const start = digest[digest.length - 1] & 15;
  return String(((digest.readUInt32BE(start) & 0x7fffffff) % 1_000_000)).padStart(6, '0');
};

export const verifyTotp = (secret, code, now = Date.now(), drift = 1) => {
  const normalizedCode = normalizeOtp(code);
  if (!/^\d{6}$/.test(normalizedCode)) return null;
  const key = decodeBase32(secret);
  const current = Math.floor(now / 30_000);
  for (let offset = -drift; offset <= drift; offset += 1) {
    const counter = current + offset;
    const message = Buffer.alloc(8);
    message.writeBigUInt64BE(BigInt(counter));
    const digest = crypto.createHmac('sha1', key).update(message).digest();
    const start = digest[digest.length - 1] & 15;
    const expected = String(((digest.readUInt32BE(start) & 0x7fffffff) % 1_000_000)).padStart(6, '0');
    if (timingEqual(expected, normalizedCode)) return counter;
  }
  return null;
};

const encryptionKey = (value) => {
  if (!value || String(value).length < 32) throw Object.assign(new Error('未配置 MFA_ENCRYPTION_KEY，无法安全启用双重验证'), { status: 503, code: 'MFA_UNAVAILABLE' });
  return crypto.createHash('sha256').update(String(value)).digest();
};

export const encryptMfaSecret = (secret, keyValue) => {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(keyValue), iv);
  cipher.setAAD(Buffer.from('xiangshang-mfa-totp-v1'));
  const ciphertext = Buffer.concat([cipher.update(String(secret), 'utf8'), cipher.final()]);
  return `v1.${iv.toString('base64url')}.${cipher.getAuthTag().toString('base64url')}.${ciphertext.toString('base64url')}`;
};

export const decryptMfaSecret = (encrypted, keyValue) => {
  const [version, ivText, tagText, ciphertextText] = String(encrypted || '').split('.');
  if (version !== 'v1' || !ivText || !tagText || !ciphertextText) throw Object.assign(new Error('动态口令密钥不可用'), { status: 503, code: 'MFA_SECRET_UNREADABLE' });
  try {
    const decipher = crypto.createDecipheriv('aes-256-gcm', encryptionKey(keyValue), Buffer.from(ivText, 'base64url'));
    decipher.setAAD(Buffer.from('xiangshang-mfa-totp-v1'));
    decipher.setAuthTag(Buffer.from(tagText, 'base64url'));
    return Buffer.concat([decipher.update(Buffer.from(ciphertextText, 'base64url')), decipher.final()]).toString('utf8');
  } catch (error) {
    if (error.code === 'MFA_UNAVAILABLE') throw error;
    throw Object.assign(new Error('动态口令密钥不可用'), { status: 503, code: 'MFA_SECRET_UNREADABLE' });
  }
};

export const normalizeRecoveryCode = (value) => String(value || '').replace(/[\s-]/g, '').toUpperCase();
export const recoveryCodeHash = (code, keyValue) => crypto.createHmac('sha256', encryptionKey(keyValue)).update(normalizeRecoveryCode(code)).digest('hex');
export const createRecoveryCodes = (count = 10) => Array.from({ length: count }, () => {
  const text = encodeBase32(crypto.randomBytes(8)).slice(0, 10);
  return `${text.slice(0, 5)}-${text.slice(5)}`;
});
