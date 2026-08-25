ALTER TABLE body_assessments ADD COLUMN IF NOT EXISTS retention_until TIMESTAMPTZ;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS retention_until TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS data_consents (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  parent_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  consent_version TEXT NOT NULL,
  purpose TEXT NOT NULL DEFAULT 'body_assessment',
  granted_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (student_id, parent_user_id, consent_version, purpose)
);

CREATE INDEX IF NOT EXISTS idx_data_consents_student_active
  ON data_consents(student_id, parent_user_id, purpose, revoked_at, expires_at);
CREATE INDEX IF NOT EXISTS idx_body_assessments_retention
  ON body_assessments(retention_until) WHERE retention_until IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_retention
  ON audit_logs(retention_until) WHERE retention_until IS NOT NULL;

CREATE OR REPLACE FUNCTION set_retention_until()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.retention_until IS NULL THEN
    NEW.retention_until := now() + interval '2555 days';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS body_assessments_retention_default ON body_assessments;
CREATE TRIGGER body_assessments_retention_default
BEFORE INSERT ON body_assessments FOR EACH ROW EXECUTE FUNCTION set_retention_until();

DROP TRIGGER IF EXISTS audit_logs_retention_default ON audit_logs;
CREATE TRIGGER audit_logs_retention_default
BEFORE INSERT ON audit_logs FOR EACH ROW EXECUTE FUNCTION set_retention_until();
