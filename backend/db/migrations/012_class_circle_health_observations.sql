ALTER TABLE class_posts ADD COLUMN IF NOT EXISTS school_id TEXT REFERENCES schools(id) ON DELETE SET NULL;
ALTER TABLE class_posts ADD COLUMN IF NOT EXISTS class_id TEXT REFERENCES classes(id) ON DELETE SET NULL;
ALTER TABLE class_posts ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE class_posts ADD COLUMN IF NOT EXISTS visibility_scope TEXT NOT NULL DEFAULT 'class';
ALTER TABLE class_posts ADD COLUMN IF NOT EXISTS moderation_status TEXT NOT NULL DEFAULT 'pending_review';
ALTER TABLE class_posts ADD COLUMN IF NOT EXISTS pinned BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE class_posts ADD COLUMN IF NOT EXISTS report_status TEXT;
ALTER TABLE class_posts ADD COLUMN IF NOT EXISTS attachments JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE class_posts ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE class_posts ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS idx_class_posts_class_created ON class_posts(class_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_class_posts_school_created ON class_posts(school_id, created_at DESC);

CREATE TABLE IF NOT EXISTS class_post_comments (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  post_id TEXT NOT NULL REFERENCES class_posts(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  content TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'published',
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_class_post_comments_post ON class_post_comments(post_id, created_at);

CREATE TABLE IF NOT EXISTS class_post_reports (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  post_id TEXT NOT NULL REFERENCES class_posts(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(post_id, user_id)
);

CREATE TABLE IF NOT EXISTS family_health_observations (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  child_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  form_version TEXT NOT NULL,
  answers JSONB NOT NULL,
  frequency TEXT,
  severity TEXT,
  note TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, child_id, category, form_version)
);
CREATE INDEX IF NOT EXISTS idx_family_health_observations_child ON family_health_observations(child_id, submitted_at DESC);
