CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS schools (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name TEXT NOT NULL,
  campus TEXT NOT NULL DEFAULT '',
  region TEXT NOT NULL DEFAULT '',
  is_poverty_area BOOLEAN NOT NULL DEFAULT FALSE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  phone TEXT UNIQUE,
  name TEXT NOT NULL,
  password_hash TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth_oauth_states (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  provider TEXT NOT NULL CHECK (provider IN ('wechat')),
  state_hash TEXT NOT NULL UNIQUE,
  redirect_uri TEXT NOT NULL,
  request_ip TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_auth_oauth_states_expiry ON auth_oauth_states(expires_at) WHERE consumed_at IS NULL;

CREATE TABLE IF NOT EXISTS auth_identities (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  provider TEXT NOT NULL CHECK (provider IN ('wechat')),
  subject TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  profile_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, subject),
  UNIQUE (provider, user_id)
);
CREATE INDEX IF NOT EXISTS idx_auth_identities_user ON auth_identities(user_id);

CREATE TABLE IF NOT EXISTS idempotency_keys (
  key_hash TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
  response_json JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'succeeded',
  request_hash TEXT,
  locked_at TIMESTAMPTZ,
  response_status INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_rate_limits (
  key_hash TEXT PRIMARY KEY,
  window_started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  request_count INTEGER NOT NULL DEFAULT 0 CHECK (request_count >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS refresh_sessions (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  access_token_hash TEXT,
  access_expires_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  user_agent TEXT,
  ip TEXT,
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS roles (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS grades (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  standard_version TEXT NOT NULL DEFAULT '运动能力标准 v1.0',
  academic_year TEXT NOT NULL DEFAULT '',
  UNIQUE (school_id, name, academic_year),
  UNIQUE (id, school_id)
);

CREATE TABLE IF NOT EXISTS classes (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  grade_id TEXT NOT NULL REFERENCES grades(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  teacher_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  UNIQUE (school_id, grade_id, name),
  UNIQUE (id, school_id)
);

CREATE TABLE IF NOT EXISTS user_roles (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id TEXT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  class_id TEXT REFERENCES classes(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role_id, school_id, class_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_roles_scope
  ON user_roles(user_id, role_id, COALESCE(school_id, ''), COALESCE(class_id, ''));
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='user_roles_class_requires_school') THEN
    ALTER TABLE user_roles ADD CONSTRAINT user_roles_class_requires_school CHECK (class_id IS NULL OR school_id IS NOT NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='user_roles_class_school_fk') THEN
    ALTER TABLE user_roles ADD CONSTRAINT user_roles_class_school_fk FOREIGN KEY (class_id, school_id) REFERENCES classes(id, school_id);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS capabilities (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS role_capabilities (
  role_id TEXT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  capability_code TEXT NOT NULL REFERENCES capabilities(code) ON DELETE CASCADE,
  PRIMARY KEY (role_id, capability_code)
);

CREATE TABLE IF NOT EXISTS user_capability_overrides (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  capability_code TEXT NOT NULL REFERENCES capabilities(code) ON DELETE CASCADE,
  allowed BOOLEAN NOT NULL,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  class_id TEXT REFERENCES classes(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_capability_override_scope
  ON user_capability_overrides(user_id, capability_code, COALESCE(school_id, ''), COALESCE(class_id, ''));
CREATE INDEX IF NOT EXISTS idx_user_capability_overrides_active
  ON user_capability_overrides(user_id, expires_at);

CREATE TABLE IF NOT EXISTS students (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  grade_id TEXT NOT NULL REFERENCES grades(id) ON DELETE RESTRICT,
  class_id TEXT NOT NULL REFERENCES classes(id) ON DELETE RESTRICT,
  student_no TEXT,
  name TEXT NOT NULL,
  gender TEXT NOT NULL DEFAULT '',
  birth_date DATE,
  region TEXT NOT NULL DEFAULT '',
  is_poverty_area BOOLEAN NOT NULL DEFAULT FALSE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  binding_code_hash TEXT,
  binding_code_expires_at TIMESTAMPTZ,
  UNIQUE (school_id, student_no)
);

CREATE TABLE IF NOT EXISTS parent_student_bindings (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  parent_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  relation TEXT NOT NULL DEFAULT '监护人',
  binding_code TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked', 'expired')),
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (parent_user_id, student_id)
);

CREATE TABLE IF NOT EXISTS rule_versions (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  code TEXT NOT NULL,
  version TEXT NOT NULL,
  config JSONB NOT NULL DEFAULT '{}'::jsonb,
  effective_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'active',
  UNIQUE (code, version)
);

CREATE TABLE IF NOT EXISTS region_policies (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  region TEXT NOT NULL,
  standard_version TEXT NOT NULL,
  poverty_area_label TEXT,
  effective_date DATE NOT NULL,
  config JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (region, standard_version, effective_date)
);

CREATE TABLE IF NOT EXISTS assessment_tasks (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  test_date DATE NOT NULL,
  location TEXT NOT NULL DEFAULT '',
  grade_id TEXT REFERENCES grades(id) ON DELETE SET NULL,
  class_id TEXT REFERENCES classes(id) ON DELETE SET NULL,
  items JSONB NOT NULL DEFAULT '[]'::jsonb,
  rule_version TEXT NOT NULL DEFAULT '运动能力标准 v1.0',
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'closed')),
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS task_students (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  task_id TEXT NOT NULL REFERENCES assessment_tasks(id) ON DELETE CASCADE,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT '未签到',
  note TEXT,
  check_in_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  version INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (task_id, student_id)
);

CREATE TABLE IF NOT EXISTS task_student_status_events (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  task_id TEXT NOT NULL REFERENCES assessment_tasks(id) ON DELETE CASCADE,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  from_status TEXT NOT NULL,
  to_status TEXT NOT NULL,
  note TEXT,
  reason_code TEXT,
  operator_teacher_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  expected_version INTEGER,
  resulting_version INTEGER NOT NULL,
  client_operation_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_task_student_status_events_timeline
  ON task_student_status_events(task_id, student_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_task_student_status_events_client_operation
  ON task_student_status_events(task_id, student_id, client_operation_id)
  WHERE client_operation_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS assessment_scores (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  task_id TEXT NOT NULL REFERENCES assessment_tasks(id) ON DELETE CASCADE,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  item_code TEXT NOT NULL,
  score NUMERIC(5,2) NOT NULL CHECK (score >= 0 AND score <= 5),
  confidence NUMERIC(5,4) NOT NULL DEFAULT 0 CHECK (confidence >= 0 AND confidence <= 1),
  note TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT 'teacher',
  review_status TEXT NOT NULL DEFAULT 'passed' CHECK (review_status IN ('passed', 'pendingReview')),
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (task_id, student_id, item_code)
);
ALTER TABLE assessment_scores ADD COLUMN IF NOT EXISTS manual_reviewed BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE assessment_scores ALTER COLUMN confidence SET DEFAULT 0;

CREATE TABLE IF NOT EXISTS score_reviews (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  score_id TEXT NOT NULL REFERENCES assessment_scores(id) ON DELETE CASCADE,
  reviewer_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  action TEXT NOT NULL,
  old_score NUMERIC(5,2),
  new_score NUMERIC(5,2),
  reason TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS diagnosis_reports (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  task_id TEXT NOT NULL REFERENCES assessment_tasks(id) ON DELETE CASCADE,
  risk_level TEXT NOT NULL DEFAULT 'unavailable',
  total_score NUMERIC(6,2) NOT NULL DEFAULT 0,
  rule_version TEXT NOT NULL,
  region_policy_version TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'withdrawn')),
  current_version INTEGER NOT NULL DEFAULT 1,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at TIMESTAMPTZ,
  published_version INTEGER,
  UNIQUE (student_id, task_id)
);

CREATE TABLE IF NOT EXISTS report_versions (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  report_id TEXT NOT NULL REFERENCES diagnosis_reports(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  report_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  generated_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (report_id, version)
);

CREATE TABLE IF NOT EXISTS body_assessments (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  parent_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  height_cm NUMERIC(6,2) NOT NULL CHECK (height_cm > 0),
  weight_kg NUMERIC(6,2) NOT NULL CHECK (weight_kg > 0),
  bmi NUMERIC(6,2) NOT NULL,
  overall_level TEXT NOT NULL DEFAULT 'pending',
  algorithm_version TEXT NOT NULL,
  consent_version TEXT NOT NULL,
  data_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  measured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  retention_until TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS data_consents (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  parent_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  consent_version TEXT NOT NULL,
  purpose TEXT NOT NULL DEFAULT 'body_assessment',
  granted_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  consent_id TEXT NOT NULL DEFAULT gen_random_uuid()::text UNIQUE,
  privacy_policy_version TEXT,
  camera_consent_version TEXT,
  algorithm_notice_version TEXT,
  device_info_hash TEXT,
  app_version TEXT,
  data_retention_notice_accepted BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (student_id, parent_user_id, consent_version, purpose)
);

CREATE TABLE IF NOT EXISTS posture_snapshots (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  body_assessment_id TEXT NOT NULL REFERENCES body_assessments(id) ON DELETE CASCADE,
  capture_task TEXT NOT NULL,
  sample_count INTEGER NOT NULL DEFAULT 0,
  confidence NUMERIC(5,4) NOT NULL DEFAULT 0,
  metrics_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (body_assessment_id, capture_task)
);

CREATE TABLE IF NOT EXISTS files (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  owner_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  object_key TEXT NOT NULL UNIQUE,
  file_type TEXT NOT NULL,
  purpose TEXT NOT NULL DEFAULT 'general',
  content_type TEXT NOT NULL DEFAULT 'application/octet-stream',
  file_size BIGINT,
  checksum_sha256 TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  uploaded_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS courses (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  cover TEXT,
  category TEXT NOT NULL DEFAULT '',
  duration TEXT NOT NULL DEFAULT '',
  focus TEXT NOT NULL DEFAULT '',
  video_file_id TEXT REFERENCES files(id) ON DELETE SET NULL,
  is_public_benefit BOOLEAN NOT NULL DEFAULT FALSE,
  status TEXT NOT NULL DEFAULT 'draft',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS course_progress (
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  progress NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (progress >= 0 AND progress <= 100),
  completed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (student_id, course_id)
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  receiver_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'system',
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  message_type TEXT,
  business_id TEXT,
  business_route TEXT,
  child_id TEXT,
  task_id TEXT,
  course_id TEXT,
  lesson_id TEXT,
  action_label TEXT,
  read_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ
);

-- Voluntary product-improvement events deliberately have no user, child,
-- school, device or health-data foreign key. The startup-only client session
-- identifier is persisted solely as a one-way hash.
CREATE TABLE IF NOT EXISTS product_events (
  event_id UUID PRIMARY KEY,
  event_name TEXT NOT NULL CHECK (event_name IN ('growth_report_opened','growth_report_period_changed','adaptive_plan_opened_courses')),
  coarse_value TEXT CHECK (coarse_value IS NULL OR coarse_value IN ('本周','本月')),
  platform TEXT NOT NULL CHECK (platform IN ('ios','android')),
  app_version TEXT NOT NULL CHECK (char_length(app_version) BETWEEN 1 AND 40),
  client_session_hash TEXT NOT NULL CHECK (char_length(client_session_hash) = 64),
  occurred_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_product_events_name_received ON product_events(event_name, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_product_events_retention ON product_events(received_at);

CREATE TABLE IF NOT EXISTS notification_receipts (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  campaign_id TEXT NOT NULL,
  receiver_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending',
  acknowledged_at TIMESTAMPTZ,
  version INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (status IN ('pending', 'acknowledged')),
  UNIQUE(campaign_id, receiver_user_id)
);
CREATE INDEX IF NOT EXISTS idx_notification_receipts_campaign ON notification_receipts(campaign_id, status);

CREATE TABLE IF NOT EXISTS activity_registrations (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  activity_id TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  child_id TEXT REFERENCES students(id) ON DELETE SET NULL,
  contact_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- `schema.sql` is also applied to long-lived installations that may contain
-- the pre-lifecycle activity table.  Bring that table up to the minimum shape
-- needed by the child-scoped unique index before creating the index.  The
-- historical migration adds the remaining lifecycle fields idempotently.
ALTER TABLE activity_registrations
  ADD COLUMN IF NOT EXISTS child_id TEXT REFERENCES students(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_activity_registrations_activity_user_child
  ON activity_registrations(activity_id, user_id, COALESCE(child_id, '__family__'));

CREATE TABLE IF NOT EXISTS experts (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT REFERENCES schools(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  bio TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS expert_slots (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  expert_id TEXT NOT NULL REFERENCES experts(id) ON DELETE CASCADE,
  school_id TEXT REFERENCES schools(id) ON DELETE SET NULL,
  service_id TEXT,
  scheduled_start_at TIMESTAMPTZ NOT NULL,
  scheduled_end_at TIMESTAMPTZ NOT NULL,
  capacity INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'available',
  version INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (capacity > 0),
  CHECK (scheduled_end_at > scheduled_start_at)
);

CREATE TABLE IF NOT EXISTS expert_appointments (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expert_id TEXT REFERENCES experts(id) ON DELETE SET NULL,
  service_id TEXT,
  slot_id TEXT REFERENCES expert_slots(id) ON DELETE SET NULL,
  child_id TEXT REFERENCES students(id) ON DELETE SET NULL,
  expert_name TEXT NOT NULL,
  preferred_date TEXT NOT NULL,
  scheduled_start_at TIMESTAMPTZ,
  scheduled_end_at TIMESTAMPTZ,
  note TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS course_uploads (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  task_id TEXT,
  attachment_file_id TEXT REFERENCES files(id) ON DELETE SET NULL,
  attendance_count INTEGER NOT NULL DEFAULT 0,
  notes TEXT NOT NULL DEFAULT '',
  attachment_name TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS activities (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  capacity INTEGER,
  registration_start_at TIMESTAMPTZ,
  registration_end_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'draft',
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

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
CREATE INDEX IF NOT EXISTS idx_content_releases_scope ON content_releases(school_id, channel, status, version DESC);
CREATE INDEX IF NOT EXISTS idx_content_release_items_type ON content_release_items(content_type, content_id);

CREATE TABLE IF NOT EXISTS class_posts (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  school_id TEXT REFERENCES schools(id) ON DELETE SET NULL,
  class_id TEXT REFERENCES classes(id) ON DELETE SET NULL,
  author TEXT NOT NULL,
  display_name TEXT,
  content TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'published',
  visibility_scope TEXT NOT NULL DEFAULT 'class',
  moderation_status TEXT NOT NULL DEFAULT 'pending_review',
  pinned BOOLEAN NOT NULL DEFAULT false,
  report_status TEXT,
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS class_post_comments (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  post_id TEXT NOT NULL REFERENCES class_posts(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  content TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'published',
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_class_post_comments_post_created ON class_post_comments(post_id, created_at DESC)
  WHERE deleted_at IS NULL;

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

CREATE TABLE IF NOT EXISTS health_checkins (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  child_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  check_in_date DATE NOT NULL,
  activity_type TEXT NOT NULL,
  duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0 AND duration_minutes <= 1440),
  intensity TEXT NOT NULL CHECK (intensity IN ('low','moderate','high')),
  feeling TEXT,
  completed_recommended BOOLEAN NOT NULL DEFAULT false,
  parent_note TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, child_id, check_in_date)
);
CREATE INDEX IF NOT EXISTS idx_health_checkins_child_date ON health_checkins(child_id, check_in_date DESC);

CREATE TABLE IF NOT EXISTS training_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  child_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  day_id INTEGER NOT NULL CHECK (day_id >= 0 AND day_id < 90),
  completed_at TIMESTAMPTZ NOT NULL,
  duration_seconds INTEGER NOT NULL CHECK (duration_seconds >= 0 AND duration_seconds <= 86400),
  completion_ratio NUMERIC(5,4) NOT NULL CHECK (completion_ratio >= 0 AND completion_ratio <= 1),
  quality_score INTEGER NOT NULL CHECK (quality_score >= 0 AND quality_score <= 100),
  camera_verified BOOLEAN NOT NULL DEFAULT false,
  visual_units JSONB NOT NULL DEFAULT '{}'::jsonb,
  manual_units INTEGER NOT NULL DEFAULT 0 CHECK (manual_units >= 0 AND manual_units <= 100000),
  model_version TEXT NOT NULL,
  mode TEXT NOT NULL DEFAULT 'guidedTraining',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_training_sessions_child_completed ON training_sessions(child_id, completed_at DESC);

CREATE TABLE IF NOT EXISTS support_messages (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  operator_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  school_id TEXT REFERENCES schools(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id TEXT,
  before_json JSONB,
  after_json JSONB,
  ip TEXT,
  request_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  retention_until TIMESTAMPTZ,
  previous_hash TEXT,
  entry_hash TEXT
);

CREATE TABLE IF NOT EXISTS audit_chain_state (
  scope_key TEXT PRIMARY KEY,
  last_entry_id TEXT REFERENCES audit_logs(id) ON DELETE SET NULL,
  last_hash TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE body_assessments ADD COLUMN IF NOT EXISTS retention_until TIMESTAMPTZ;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS retention_until TIMESTAMPTZ;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS previous_hash TEXT;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS entry_hash TEXT;

CREATE INDEX IF NOT EXISTS idx_students_school_class ON students(school_id, class_id);
CREATE INDEX IF NOT EXISTS idx_students_school_status ON students(school_id, status);
CREATE INDEX IF NOT EXISTS idx_bindings_parent ON parent_student_bindings(parent_user_id, status);
CREATE INDEX IF NOT EXISTS idx_task_students_task_status ON task_students(task_id, status);
CREATE INDEX IF NOT EXISTS idx_task_students_student_time ON task_students(student_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_scores_student_task ON assessment_scores(student_id, task_id);
CREATE INDEX IF NOT EXISTS idx_reports_student_status ON diagnosis_reports(student_id, status);
CREATE INDEX IF NOT EXISTS idx_reports_student_published_time ON diagnosis_reports(student_id, generated_at DESC) WHERE status='published';
CREATE INDEX IF NOT EXISTS idx_messages_receiver_read ON messages(receiver_user_id, is_read, created_at DESC);
CREATE TABLE IF NOT EXISTS device_installations (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  provider TEXT NOT NULL CHECK (provider IN ('apns', 'fcm')),
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  device_instance_hash TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  token_ciphertext TEXT NOT NULL,
  token_last_four TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'invalid', 'revoked')),
  app_version TEXT,
  locale TEXT,
  last_registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  invalidated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((platform='ios' AND provider='apns') OR (platform='android' AND provider='fcm'))
);
CREATE INDEX IF NOT EXISTS idx_device_installations_user_active ON device_installations(user_id, last_registered_at DESC) WHERE status='active';
CREATE INDEX IF NOT EXISTS idx_device_installations_device_active ON device_installations(user_id, platform, device_instance_hash) WHERE status='active';
CREATE INDEX IF NOT EXISTS idx_audit_school_time ON audit_logs(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_resource_time ON audit_logs(resource_type, resource_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_files_owner_status ON files(owner_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_scores_task_student ON assessment_scores(task_id, student_id, item_code);
CREATE INDEX IF NOT EXISTS idx_activities_school_time ON activities(school_id, starts_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_expiry ON refresh_sessions(expires_at) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_idempotency_expiry ON idempotency_keys(expires_at);
CREATE INDEX IF NOT EXISTS idx_auth_rate_limits_updated ON auth_rate_limits(updated_at);
CREATE INDEX IF NOT EXISTS idx_user_roles_user_scope ON user_roles(user_id, school_id, class_id);
CREATE INDEX IF NOT EXISTS idx_data_consents_student_active ON data_consents(student_id, parent_user_id, purpose, revoked_at, expires_at);

CREATE TABLE IF NOT EXISTS course_modules (id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text, course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE, title TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS course_lessons (id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text, course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE, module_id TEXT REFERENCES course_modules(id) ON DELETE SET NULL, title TEXT NOT NULL, duration_ms INTEGER NOT NULL DEFAULT 0, video_source TEXT, captions JSONB NOT NULL DEFAULT '[]'::jsonb, sort_order INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'active');
CREATE TABLE IF NOT EXISTS lesson_progress (student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE, lesson_id TEXT NOT NULL REFERENCES course_lessons(id) ON DELETE CASCADE, last_position_ms INTEGER NOT NULL DEFAULT 0, completed BOOLEAN NOT NULL DEFAULT false, version INTEGER NOT NULL DEFAULT 1, updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(student_id, lesson_id));
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
  UNIQUE NULLS NOT DISTINCT (school_id, grade_id, risk_level, lesson_id)
);
CREATE INDEX IF NOT EXISTS idx_course_recommendations_lookup ON course_recommendations(school_id,grade_id,risk_level,active,priority DESC);
CREATE INDEX IF NOT EXISTS idx_body_assessments_retention ON body_assessments(retention_until) WHERE retention_until IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_retention ON audit_logs(retention_until) WHERE retention_until IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_logs_chain ON audit_logs(school_id, created_at, id) WHERE entry_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS student_binding_codes (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  used_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS account_password_resets (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS auth_verification_codes (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  phone TEXT NOT NULL,
  purpose TEXT NOT NULL CHECK (purpose IN ('login', 'register', 'reset-password')),
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  request_ip TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_auth_verification_codes_active ON auth_verification_codes(phone, purpose, created_at DESC) WHERE consumed_at IS NULL;
CREATE TABLE IF NOT EXISTS privacy_requests (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  requested_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  request_type TEXT NOT NULL CHECK (request_type IN ('export', 'anonymize', 'delete')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'processing', 'completed', 'rejected', 'failed')),
  result_json JSONB,
  reviewed_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

-- Account-level deletion is a separate request from deleting a child's
-- records. The account is anonymized only after an administrator approves the
-- request; this preserves school audit history while removing account
-- identity and revoking all sessions.
CREATE TABLE IF NOT EXISTS account_deletion_requests (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  requested_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'processing', 'completed', 'rejected', 'failed')),
  result_json JSONB,
  reviewed_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_account_deletion_requests_user_time ON account_deletion_requests(user_id, created_at DESC);
CREATE TABLE IF NOT EXISTS job_queue (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  job_type TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  locked_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO roles(code, name) VALUES
  ('parent', '家长'), ('teacher', '教师'), ('principal', '校长'), ('admin', '平台管理员')
ON CONFLICT (code) DO NOTHING;
