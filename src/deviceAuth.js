import crypto from 'node:crypto';

const encryptionKey = (value) => {
  if (!value || String(value).length < 32) throw Object.assign(new Error('未配置 FIELD_DEVICE_SIGNING_ENCRYPTION_KEY，无法安全保存设备签名材料'), { status: 503, code: 'FIELD_DEVICE_SIGNING_UNAVAILABLE' });
  return crypto.createHash('sha256').update(String(value)).digest();
};

export const encryptFieldDeviceSigningSecret = (secret, keyValue) => {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(keyValue), iv);
  cipher.setAAD(Buffer.from('xiangshang-field-device-signing-v1'));
  const ciphertext = Buffer.concat([cipher.update(String(secret), 'utf8'), cipher.final()]);
  return `v1.${iv.toString('base64url')}.${cipher.getAuthTag().toString('base64url')}.${ciphertext.toString('base64url')}`;
};

export const decryptFieldDeviceSigningSecret = (encrypted, keyValue) => {
  const [version, ivText, tagText, ciphertextText] = String(encrypted || '').split('.');
  if (version !== 'v1' || !ivText || !tagText || !ciphertextText) throw Object.assign(new Error('设备签名材料不可用'), { status: 503, code: 'FIELD_DEVICE_SIGNING_UNREADABLE' });
  try {
    const decipher = crypto.createDecipheriv('aes-256-gcm', encryptionKey(keyValue), Buffer.from(ivText, 'base64url'));
    decipher.setAAD(Buffer.from('xiangshang-field-device-signing-v1'));
    decipher.setAuthTag(Buffer.from(tagText, 'base64url'));
    return Buffer.concat([decipher.update(Buffer.from(ciphertextText, 'base64url')), decipher.final()]).toString('utf8');
  } catch (error) {
    if (error.code === 'FIELD_DEVICE_SIGNING_UNAVAILABLE') throw error;
    throw Object.assign(new Error('设备签名材料不可用'), { status: 503, code: 'FIELD_DEVICE_SIGNING_UNREADABLE' });
  }
};
