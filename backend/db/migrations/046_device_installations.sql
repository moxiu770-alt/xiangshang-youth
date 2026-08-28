-- APNs/FCM tokens are personal device identifiers. Store only encrypted tokens
-- plus a one-way provider-scoped hash for deduplication.
CREATE TABLE IF NOT EXISTS device_installations (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  provider TEXT NOT NULL CHECK (provider IN ('apns', 'fcm')),
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  device_instance_hash TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  token_ciphertext TEXT NOT NULL,
  token_last_four TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'invalid', 'revoked')),
  app_version TEXT,
  locale TEXT,
  last_registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  invalidated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((platform='ios' AND provider='apns') OR (platform='android' AND provider='fcm'))
);
CREATE INDEX IF NOT EXISTS idx_device_installations_user_active
  ON device_installations(user_id, last_registered_at DESC) WHERE status='active';
CREATE INDEX IF NOT EXISTS idx_device_installations_device_active
  ON device_installations(user_id, platform, device_instance_hash) WHERE status='active';
