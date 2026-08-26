-- The database keeps only an encrypted signing secret. A database dump alone
-- cannot authenticate a field device because decryption needs the separately
-- managed FIELD_DEVICE_SIGNING_ENCRYPTION_KEY.
ALTER TABLE test_devices ADD COLUMN IF NOT EXISTS signing_secret_encrypted TEXT;
CREATE INDEX IF NOT EXISTS idx_test_devices_signing_secret_missing
  ON test_devices(school_id) WHERE signing_secret_encrypted IS NULL;
