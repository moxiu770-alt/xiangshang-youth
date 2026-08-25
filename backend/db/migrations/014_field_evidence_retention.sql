-- Field evidence contains different classes of sensitive data.  Keep a
-- durable audit trail after an object is removed, while allowing the object
-- itself to follow a shorter, type-specific retention policy.

ALTER TABLE files ADD COLUMN IF NOT EXISTS retention_until TIMESTAMPTZ;
ALTER TABLE session_evidence ADD COLUMN IF NOT EXISTS retention_until TIMESTAMPTZ;
ALTER TABLE session_evidence ADD COLUMN IF NOT EXISTS purged_at TIMESTAMPTZ;
ALTER TABLE session_evidence ADD COLUMN IF NOT EXISTS purge_reason TEXT;

ALTER TABLE session_evidence ALTER COLUMN file_id DROP NOT NULL;
ALTER TABLE session_evidence DROP CONSTRAINT IF EXISTS session_evidence_file_id_fkey;
ALTER TABLE session_evidence ADD CONSTRAINT session_evidence_file_id_fkey
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_files_field_evidence_retention
  ON files(retention_until) WHERE purpose='field_evidence' AND retention_until IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_session_evidence_retention
  ON session_evidence(retention_until) WHERE retention_until IS NOT NULL;

-- Backfill already-linked evidence using conservative defaults: raw image /
-- video for 180 days; replayable derived evidence for three years. Runtime
-- configuration governs every newly completed field session.
UPDATE session_evidence evidence
SET retention_until=COALESCE(session.ended_at,session.created_at,evidence.created_at) +
  CASE WHEN evidence.evidence_type IN ('video','image') THEN interval '180 days' ELSE interval '1095 days' END
FROM test_sessions session
WHERE evidence.session_id=session.id AND evidence.retention_until IS NULL;

UPDATE files file
SET retention_until=evidence.retention_until
FROM session_evidence evidence
WHERE evidence.file_id=file.id AND file.purpose='field_evidence' AND file.retention_until IS NULL;
