CREATE TABLE IF NOT EXISTS body_screening_sessions (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  guardian_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  consent_id TEXT REFERENCES data_consents(consent_id) ON DELETE SET NULL,
  body_assessment_id TEXT UNIQUE REFERENCES body_assessments(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'capturing' CHECK (status IN ('capturing','recapture_required','professional_review','auto_archived','review_completed','cancelled')),
  protocol_version TEXT NOT NULL,
  model_version TEXT NOT NULL,
  threshold_version TEXT NOT NULL,
  decision_policy_version TEXT NOT NULL,
  device_model TEXT,
  camera_lens TEXT,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_body_screening_sessions_student_created ON body_screening_sessions(student_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_body_screening_sessions_review_queue ON body_screening_sessions(status, created_at) WHERE status='professional_review';

CREATE TABLE IF NOT EXISTS body_screening_attempts (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  session_id TEXT NOT NULL REFERENCES body_screening_sessions(id) ON DELETE CASCADE,
  capture_task TEXT NOT NULL CHECK (capture_task IN ('standingFront','standingBack','standingSide','forwardBend','dynamicKneeControl','gaitVideo','seatedPosture','footArch')),
  attempt_number INTEGER NOT NULL CHECK (attempt_number > 0),
  attempt_count INTEGER NOT NULL CHECK (attempt_count > 0),
  sample_count INTEGER NOT NULL CHECK (sample_count >= 0),
  confidence NUMERIC(5,4) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  quality_score INTEGER CHECK (quality_score BETWEEN 0 AND 100),
  quality_events_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  metrics_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  repeatability_difference NUMERIC,
  captured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(session_id, capture_task, attempt_number)
);

CREATE TABLE IF NOT EXISTS body_screening_decisions (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  session_id TEXT NOT NULL UNIQUE REFERENCES body_screening_sessions(id) ON DELETE CASCADE,
  route TEXT NOT NULL CHECK (route IN ('auto_archive','recapture_required','professional_review')),
  outcome_level TEXT NOT NULL CHECK (outcome_level IN ('capture_invalid','no_obvious_abnormality','training_observation','school_retest','professional_evaluation')),
  reason_codes JSONB NOT NULL DEFAULT '[]'::jsonb,
  model_confidence NUMERIC(5,4),
  model_uncertainty NUMERIC(5,4),
  quality_score INTEGER CHECK (quality_score BETWEEN 0 AND 100),
  review_required BOOLEAN NOT NULL DEFAULT false,
  policy_version TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  decided_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS body_screening_reviews (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  session_id TEXT NOT NULL REFERENCES body_screening_sessions(id) ON DELETE CASCADE,
  reviewer_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','in_review','completed','recapture_requested')),
  decision TEXT CHECK (decision IN ('archive','continue_observation','refer_for_professional_assessment','recapture')),
  comment TEXT,
  requested_recapture_tasks JSONB NOT NULL DEFAULT '[]'::jsonb,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_body_screening_active_review ON body_screening_reviews(session_id) WHERE status IN ('pending','in_review','recapture_requested');
