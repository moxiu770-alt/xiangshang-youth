CREATE TABLE IF NOT EXISTS school_periods (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  academic_year TEXT NOT NULL,
  term TEXT NOT NULL DEFAULT '全年',
  starts_on DATE,
  ends_on DATE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (school_id, academic_year, term)
);

ALTER TABLE grades ADD COLUMN IF NOT EXISTS period_id TEXT REFERENCES school_periods(id) ON DELETE SET NULL;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS period_id TEXT REFERENCES school_periods(id) ON DELETE SET NULL;
ALTER TABLE students ADD COLUMN IF NOT EXISTS period_id TEXT REFERENCES school_periods(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS student_lifecycle_events (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('created', 'updated', 'class_transfer', 'promoted', 'graduated', 'transferred_out', 'reactivated', 'deactivated')),
  from_grade_id TEXT,
  from_class_id TEXT,
  to_grade_id TEXT,
  to_class_id TEXT,
  from_status TEXT,
  to_status TEXT,
  note TEXT NOT NULL DEFAULT '',
  operator_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_student_lifecycle_student_time ON student_lifecycle_events(student_id, created_at DESC);

CREATE TABLE IF NOT EXISTS student_imports (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  requested_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  school_id TEXT REFERENCES schools(id) ON DELETE SET NULL,
  filename TEXT NOT NULL DEFAULT '',
  duplicate_policy TEXT NOT NULL DEFAULT 'skip' CHECK (duplicate_policy IN ('skip', 'update')),
  status TEXT NOT NULL DEFAULT 'previewed' CHECK (status IN ('previewed', 'imported', 'failed')),
  total_rows INTEGER NOT NULL DEFAULT 0,
  imported_count INTEGER NOT NULL DEFAULT 0,
  skipped_count INTEGER NOT NULL DEFAULT 0,
  failed_count INTEGER NOT NULL DEFAULT 0,
  errors_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_student_imports_operator_time ON student_imports(requested_by, created_at DESC);

CREATE TABLE IF NOT EXISTS notification_campaigns (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT REFERENCES schools(id) ON DELETE SET NULL,
  created_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  audience_type TEXT NOT NULL CHECK (audience_type IN ('school', 'grade', 'class', 'users')),
  audience_filter JSONB NOT NULL DEFAULT '{}'::jsonb,
  channel TEXT NOT NULL DEFAULT 'in_app' CHECK (channel IN ('in_app', 'push', 'sms', 'wechat')),
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sent', 'partial', 'failed')),
  sent_count INTEGER NOT NULL DEFAULT 0,
  failed_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_notification_campaigns_school_time ON notification_campaigns(school_id, created_at DESC);

CREATE TABLE IF NOT EXISTS notification_deliveries (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  campaign_id TEXT NOT NULL REFERENCES notification_campaigns(id) ON DELETE CASCADE,
  receiver_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sent', 'failed')),
  error_message TEXT,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (campaign_id, receiver_user_id, channel)
);
CREATE INDEX IF NOT EXISTS idx_notification_deliveries_campaign ON notification_deliveries(campaign_id, status);

ALTER TABLE expert_appointments ADD COLUMN IF NOT EXISTS school_id TEXT REFERENCES schools(id) ON DELETE SET NULL;
ALTER TABLE course_uploads ADD COLUMN IF NOT EXISTS school_id TEXT REFERENCES schools(id) ON DELETE SET NULL;
ALTER TABLE class_posts ADD COLUMN IF NOT EXISTS school_id TEXT REFERENCES schools(id) ON DELETE SET NULL;
ALTER TABLE support_messages ADD COLUMN IF NOT EXISTS school_id TEXT REFERENCES schools(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_expert_appointments_school_status ON expert_appointments(school_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_course_uploads_school_status ON course_uploads(school_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_messages_school_status ON support_messages(school_id, status, created_at DESC);
