CREATE TABLE IF NOT EXISTS courses (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  cover TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','archived')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS course_modules (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS course_lessons (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  module_id TEXT REFERENCES course_modules(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  duration_ms INTEGER NOT NULL DEFAULT 0 CHECK (duration_ms >= 0),
  video_source TEXT,
  captions JSONB NOT NULL DEFAULT '[]'::jsonb,
  sort_order INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','archived'))
);
CREATE TABLE IF NOT EXISTS lesson_progress (
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  lesson_id TEXT NOT NULL REFERENCES course_lessons(id) ON DELETE CASCADE,
  last_position_ms INTEGER NOT NULL DEFAULT 0 CHECK (last_position_ms >= 0),
  completed BOOLEAN NOT NULL DEFAULT false,
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(student_id, lesson_id)
);
CREATE INDEX IF NOT EXISTS idx_course_lessons_course ON course_lessons(course_id,sort_order);
