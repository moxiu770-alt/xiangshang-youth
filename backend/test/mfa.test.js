import assert from 'node:assert/strict';
import test from 'node:test';
import { createRecoveryCodes, decryptMfaSecret, encryptMfaSecret, recoveryCodeHash, verifyTotp } from '../src/mfa.js';

const key = 'mfa-test-key-that-is-longer-than-thirty-two-characters';

test('TOTP accepts the RFC SHA-1 vector and rejects a mismatched code', () => {
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  assert.equal(verifyTotp(secret, '287082', 59_000), 1);
  assert.equal(verifyTotp(secret, '287083', 59_000), null);
});

test('MFA secret encryption authenticates the ciphertext and recovery codes are keyed', () => {
  const secret = 'JBSWY3DPEHPK3PXP';
  const encrypted = encryptMfaSecret(secret, key);
  assert.notEqual(encrypted, secret);
  assert.equal(decryptMfaSecret(encrypted, key), secret);
  assert.throws(() => decryptMfaSecret(encrypted, `${key}-wrong`), { code: 'MFA_SECRET_UNREADABLE' });
  const codes = createRecoveryCodes();
  assert.equal(codes.length, 10);
  assert.equal(new Set(codes).size, 10);
  assert.equal(recoveryCodeHash(codes[0], key), recoveryCodeHash(codes[0].toLowerCase().replace('-', ' '), key));
});
