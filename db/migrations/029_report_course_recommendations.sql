-- Stable report-to-lesson mapping.  Titles are presentation data only; mobile
-- clients open courseId + lessonId after confirming the child's assignment.
CREATE TABLE IF NOT EXISTS course_recommendations (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  grade_id TEXT REFERENCES grades(id) ON DELETE CASCADE,
  risk_level TEXT,
  course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  lesson_id TEXT NOT NULL REFERENCES course_lessons(id) ON DELETE CASCADE,
  focus TEXT NOT NULL DEFAULT '',
  is_public_benefit BOOLEAN NOT NULL DEFAULT false,
  priority INTEGER NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (school_id, grade_id, risk_level, lesson_id),
  CONSTRAINT course_recommendations_lesson_matches_course CHECK (course_id IS NOT NULL AND lesson_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_course_recommendations_lookup
  ON course_recommendations(school_id, grade_id, risk_level, active, priority DESC);

-- PostgreSQL cannot express this cross-table invariant as a CHECK.  The
-- service also validates it on writes; this trigger protects direct admin SQL.
CREATE OR REPLACE FUNCTION ensure_recommendation_lesson_course_match()
RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM course_lessons WHERE id = NEW.lesson_id AND course_id = NEW.course_id) THEN
    RAISE EXCEPTION 'lesson_id must belong to course_id';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS course_recommendation_lesson_course_match ON course_recommendations;
CREATE TRIGGER course_recommendation_lesson_course_match
  BEFORE INSERT OR UPDATE OF course_id, lesson_id ON course_recommendations
  FOR EACH ROW EXECUTE FUNCTION ensure_recommendation_lesson_course_match();
