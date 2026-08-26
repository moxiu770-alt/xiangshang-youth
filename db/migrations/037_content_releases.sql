CREATE TABLE IF NOT EXISTS content_releases (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  channel TEXT NOT NULL DEFAULT 'mobile',
  version INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'draft',
  notes TEXT NOT NULL DEFAULT '',
  effective_at TIMESTAMPTZ,
  published_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  published_at TIMESTAMPTZ,
  withdrawn_at TIMESTAMPTZ,
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (channel IN ('mobile', 'teacher', 'family')),
  CHECK (status IN ('draft', 'published', 'withdrawn')),
  UNIQUE (school_id, channel, version)
);

CREATE TABLE IF NOT EXISTS content_release_items (
  release_id TEXT NOT NULL REFERENCES content_releases(id) ON DELETE CASCADE,
  content_type TEXT NOT NULL,
  content_id TEXT NOT NULL,
  content_version INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL DEFAULT 0,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (release_id, content_type, content_id),
  CHECK (content_type IN ('course', 'activity', 'expert', 'notification_template', 'scoring_rule'))
);

CREATE TABLE IF NOT EXISTS notification_templates (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  recipient_scope TEXT NOT NULL DEFAULT 'all_guardians',
  status TEXT NOT NULL DEFAULT 'draft',
  version INTEGER NOT NULL DEFAULT 1,
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (status IN ('draft', 'active', 'archived'))
);

CREATE INDEX IF NOT EXISTS idx_content_releases_scope
  ON content_releases(school_id, channel, status, version DESC);
CREATE INDEX IF NOT EXISTS idx_content_release_items_type
  ON content_release_items(content_type, content_id);
