CREATE TABLE IF NOT EXISTS user_mfa_totp (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  secret_encrypted TEXT,
  recovery_code_hashes JSONB NOT NULL DEFAULT '[]'::jsonb,
  last_used_counter BIGINT,
  enabled_at TIMESTAMPTZ,
  pending_secret_encrypted TEXT,
  pending_expires_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((secret_encrypted IS NULL) = (enabled_at IS NULL))
);

CREATE TABLE IF NOT EXISTS auth_mfa_challenges (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  used_at TIMESTAMPTZ,
  user_agent TEXT,
  ip TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_auth_mfa_challenges_active ON auth_mfa_challenges(token_hash, expires_at) WHERE used_at IS NULL;
