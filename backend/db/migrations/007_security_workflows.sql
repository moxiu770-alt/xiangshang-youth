ALTER TABLE students ADD COLUMN IF NOT EXISTS binding_code_hash TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS binding_code_expires_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS student_binding_codes (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  used_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_student_binding_codes_student ON student_binding_codes(student_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_student_binding_codes_active ON student_binding_codes(code_hash, expires_at) WHERE used_at IS NULL;

CREATE TABLE IF NOT EXISTS account_password_resets (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_account_password_resets_active ON account_password_resets(token_hash, expires_at) WHERE used_at IS NULL;

ALTER TABLE diagnosis_reports ADD COLUMN IF NOT EXISTS published_version INTEGER;
UPDATE diagnosis_reports SET published_version = current_version WHERE status = 'published' AND published_version IS NULL;

CREATE TABLE IF NOT EXISTS privacy_requests (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  requested_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  request_type TEXT NOT NULL CHECK (request_type IN ('export', 'anonymize', 'delete')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'processing', 'completed', 'rejected')),
  result_json JSONB,
  reviewed_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_privacy_requests_student_time ON privacy_requests(student_id, created_at DESC);

CREATE TABLE IF NOT EXISTS job_queue (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  job_type TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  locked_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_job_queue_poll ON job_queue(status, available_at, created_at);
