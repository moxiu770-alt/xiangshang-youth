-- Old installations had the original course catalogue before course
-- recommendations became school-scoped.  Keep the migration idempotent so
-- existing course records remain valid while newer APIs can safely scope them.
ALTER TABLE courses ADD COLUMN IF NOT EXISTS school_id TEXT REFERENCES schools(id) ON DELETE CASCADE;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS cover TEXT;
CREATE INDEX IF NOT EXISTS idx_courses_school_status ON courses(school_id, status, created_at DESC);
