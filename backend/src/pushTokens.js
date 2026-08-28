import crypto from 'node:crypto';

const keyFor = (secret) => {
  const value = String(secret || '');
  if (value.length < 32) throw Object.assign(new Error('推送令牌加密密钥未配置'), { status: 503, code: 'PUSH_TOKEN_ENCRYPTION_NOT_CONFIGURED' });
  return crypto.createHash('sha256').update(value).digest();
};

export const pushTokenHash = (provider, token) => crypto.createHash('sha256')
  .update(`${String(provider || '').toLowerCase()}:${String(token || '')}`)
  .digest('hex');

export function encryptPushToken(token, secret) {
  const value = String(token || '');
  if (!value) throw Object.assign(new Error('推送令牌不能为空'), { status: 400, code: 'PUSH_TOKEN_REQUIRED' });
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', keyFor(secret), iv);
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return ['v1', iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), ciphertext.toString('base64url')].join('.');
}

export function decryptPushToken(encoded, secret) {
  const [version, ivText, tagText, ciphertextText] = String(encoded || '').split('.');
  if (version !== 'v1' || !ivText || !tagText || !ciphertextText) throw Object.assign(new Error('推送令牌密文无效'), { code: 'PUSH_TOKEN_CIPHERTEXT_INVALID' });
  try {
    const decipher = crypto.createDecipheriv('aes-256-gcm', keyFor(secret), Buffer.from(ivText, 'base64url'));
    decipher.setAuthTag(Buffer.from(tagText, 'base64url'));
    return Buffer.concat([decipher.update(Buffer.from(ciphertextText, 'base64url')), decipher.final()]).toString('utf8');
  } catch {
    throw Object.assign(new Error('推送令牌无法解密'), { code: 'PUSH_TOKEN_DECRYPT_FAILED' });
  }
}
