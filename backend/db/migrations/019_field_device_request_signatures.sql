-- A signed device request never transmits its one-time registration key. The
-- server already stores only the SHA-256 key digest; that digest is used as
-- the HMAC key so a leaked database cannot reconstruct the device secret.
CREATE TABLE IF NOT EXISTS field_device_request_nonces (
  device_id TEXT NOT NULL REFERENCES test_devices(id) ON DELETE CASCADE,
  nonce_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (device_id, nonce_hash)
);
CREATE INDEX IF NOT EXISTS idx_field_device_request_nonces_expiry ON field_device_request_nonces(expires_at);
