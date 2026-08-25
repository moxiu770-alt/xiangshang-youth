ALTER TABLE activities ADD COLUMN IF NOT EXISTS capacity INTEGER;
ALTER TABLE activities ADD COLUMN IF NOT EXISTS registration_start_at TIMESTAMPTZ;
ALTER TABLE activities ADD COLUMN IF NOT EXISTS registration_end_at TIMESTAMPTZ;
ALTER TABLE activities ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE activities ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS idx_activities_school_status ON activities(school_id, status, starts_at DESC);

ALTER TABLE activity_registrations ADD COLUMN IF NOT EXISTS child_id TEXT REFERENCES students(id) ON DELETE SET NULL;
ALTER TABLE activity_registrations ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE activity_registrations ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE activity_registrations ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_activity_registrations_user_created ON activity_registrations(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_registrations_activity_status ON activity_registrations(activity_id, status);

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
CREATE INDEX IF NOT EXISTS idx_experts_school_status ON experts(school_id, status, name);

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
CREATE INDEX IF NOT EXISTS idx_expert_slots_expert_time ON expert_slots(expert_id, scheduled_start_at);
CREATE INDEX IF NOT EXISTS idx_expert_slots_school_status ON expert_slots(school_id, status, scheduled_start_at);

ALTER TABLE expert_appointments ADD COLUMN IF NOT EXISTS expert_id TEXT REFERENCES experts(id) ON DELETE SET NULL;
ALTER TABLE expert_appointments ADD COLUMN IF NOT EXISTS service_id TEXT;
ALTER TABLE expert_appointments ADD COLUMN IF NOT EXISTS slot_id TEXT REFERENCES expert_slots(id) ON DELETE SET NULL;
ALTER TABLE expert_appointments ADD COLUMN IF NOT EXISTS child_id TEXT REFERENCES students(id) ON DELETE SET NULL;
ALTER TABLE expert_appointments ADD COLUMN IF NOT EXISTS scheduled_start_at TIMESTAMPTZ;
ALTER TABLE expert_appointments ADD COLUMN IF NOT EXISTS scheduled_end_at TIMESTAMPTZ;
ALTER TABLE expert_appointments ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE expert_appointments ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE expert_appointments ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_expert_appointments_user_created ON expert_appointments(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_expert_appointments_slot_status ON expert_appointments(slot_id, status);
