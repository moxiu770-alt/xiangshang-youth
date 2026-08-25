-- WeChat OAuth is deliberately modeled separately from the phone identity.
-- A user may complete authorization before a verified mobile is bound.
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

CREATE TABLE IF NOT EXISTS auth_oauth_states (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  provider TEXT NOT NULL CHECK (provider IN ('wechat')),
  state_hash TEXT NOT NULL UNIQUE,
  redirect_uri TEXT NOT NULL,
  request_ip TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_auth_oauth_states_expiry ON auth_oauth_states(expires_at) WHERE consumed_at IS NULL;

CREATE TABLE IF NOT EXISTS auth_identities (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  provider TEXT NOT NULL CHECK (provider IN ('wechat')),
  subject TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  profile_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, subject),
  UNIQUE (provider, user_id)
);
CREATE INDEX IF NOT EXISTS idx_auth_identities_user ON auth_identities(user_id);
