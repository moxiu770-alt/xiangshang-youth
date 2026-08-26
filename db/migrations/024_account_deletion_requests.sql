CREATE TABLE IF NOT EXISTS account_deletion_requests (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  requested_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'processing', 'completed', 'rejected', 'failed')),
  result_json JSONB,
  reviewed_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_account_deletion_requests_user_time ON account_deletion_requests(user_id, created_at DESC);
ALTER TABLE account_deletion_requests ADD COLUMN IF NOT EXISTS requested_by TEXT REFERENCES users(id) ON DELETE RESTRICT;
UPDATE account_deletion_requests SET requested_by=user_id WHERE requested_by IS NULL;
ALTER TABLE account_deletion_requests ALTER COLUMN requested_by SET NOT NULL;
