ALTER TABLE idempotency_keys ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'succeeded';
ALTER TABLE idempotency_keys ADD COLUMN IF NOT EXISTS request_hash TEXT;
ALTER TABLE idempotency_keys ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ;
ALTER TABLE idempotency_keys ADD COLUMN IF NOT EXISTS response_status INTEGER;

ALTER TABLE refresh_sessions ADD COLUMN IF NOT EXISTS access_token_hash TEXT;
ALTER TABLE refresh_sessions ADD COLUMN IF NOT EXISTS access_expires_at TIMESTAMPTZ;
ALTER TABLE refresh_sessions ADD COLUMN IF NOT EXISTS user_agent TEXT;
ALTER TABLE refresh_sessions ADD COLUMN IF NOT EXISTS ip TEXT;
ALTER TABLE refresh_sessions ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ;
ALTER TABLE files ADD COLUMN IF NOT EXISTS checksum_sha256 TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_access_token_hash
  ON refresh_sessions(access_token_hash) WHERE access_token_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sessions_expiry
  ON refresh_sessions(expires_at) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_idempotency_expiry
  ON idempotency_keys(expires_at);
CREATE INDEX IF NOT EXISTS idx_reports_student_published_time
  ON diagnosis_reports(student_id, generated_at DESC) WHERE status='published';
CREATE INDEX IF NOT EXISTS idx_audit_resource_time
  ON audit_logs(resource_type, resource_id, created_at DESC);
