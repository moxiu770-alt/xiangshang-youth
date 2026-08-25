-- A versioned, effective-dated policy that is resolved before a field session
-- begins. Rows are append-only in normal use: supersede an active standard by
-- creating a newer row and archiving the previous one, never by rewriting a
-- historical snapshot.
CREATE TABLE IF NOT EXISTS assessment_standards (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  grade_id TEXT REFERENCES grades(id) ON DELETE CASCADE,
  region TEXT NOT NULL DEFAULT '',
  poverty_area BOOLEAN,
  standard_version TEXT NOT NULL,
  rule_config JSONB NOT NULL DEFAULT '{}'::jsonb,
  report_config JSONB NOT NULL DEFAULT '{}'::jsonb,
  course_config JSONB NOT NULL DEFAULT '{}'::jsonb,
  effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'archived')),
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assessment_standards_effective
  ON assessment_standards(school_id, grade_id, region, effective_date DESC)
  WHERE status='active';

-- The old region-policy table remains readable; this copies its active
-- configuration into the effective-dated policy model without deleting data.
INSERT INTO assessment_standards(region, poverty_area, standard_version, rule_config, effective_date, status)
SELECT rp.region, CASE WHEN rp.poverty_area_label IS NULL THEN NULL ELSE TRUE END, rp.standard_version, rp.config, rp.effective_date, 'active'
FROM region_policies rp
WHERE NOT EXISTS (
  SELECT 1 FROM assessment_standards s
  WHERE s.school_id IS NULL AND s.grade_id IS NULL AND s.region=rp.region
    AND s.standard_version=rp.standard_version AND s.effective_date=rp.effective_date
);

ALTER TABLE test_sessions ADD COLUMN IF NOT EXISTS standard_id TEXT REFERENCES assessment_standards(id) ON DELETE SET NULL;
ALTER TABLE test_sessions ADD COLUMN IF NOT EXISTS standard_version TEXT NOT NULL DEFAULT '';
ALTER TABLE test_sessions ADD COLUMN IF NOT EXISTS standard_snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS idx_test_sessions_standard ON test_sessions(standard_id, created_at DESC);
