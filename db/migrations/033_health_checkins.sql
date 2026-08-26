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
