-- Remote acknowledgement for the in-app visual follow-along workflow.
-- Raw camera frames are never stored; only the structured session summary is.
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
CREATE INDEX IF NOT EXISTS idx_training_sessions_user_child ON training_sessions(user_id, child_id, completed_at DESC);
