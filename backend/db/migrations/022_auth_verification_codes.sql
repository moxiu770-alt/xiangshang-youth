-- A one-time code is stored as a hash only. Delivery is delegated to the
-- deployment's SMS webhook so this service stays vendor-neutral.
CREATE TABLE IF NOT EXISTS auth_verification_codes (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  phone TEXT NOT NULL,
  purpose TEXT NOT NULL CHECK (purpose IN ('login', 'register', 'reset-password')),
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  request_ip TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_auth_verification_codes_active
  ON auth_verification_codes(phone, purpose, created_at DESC)
  WHERE consumed_at IS NULL;
