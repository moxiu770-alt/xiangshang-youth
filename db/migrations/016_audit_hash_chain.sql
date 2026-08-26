ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS previous_hash TEXT;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS entry_hash TEXT;

CREATE TABLE IF NOT EXISTS audit_chain_state (
  scope_key TEXT PRIMARY KEY,
  last_entry_id TEXT REFERENCES audit_logs(id) ON DELETE SET NULL,
  last_hash TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_chain ON audit_logs(school_id, created_at, id) WHERE entry_hash IS NOT NULL;
