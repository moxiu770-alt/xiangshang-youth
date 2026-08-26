-- Central service domain for the Windows field-testing client.  The client can
-- run offline, but every replayable fact is modeled here once it is synced.

CREATE TABLE IF NOT EXISTS test_stations (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  station_code TEXT NOT NULL,
  name TEXT NOT NULL,
  item_code TEXT,
  queue_capacity INTEGER NOT NULL DEFAULT 20 CHECK (queue_capacity BETWEEN 1 AND 500),
  status TEXT NOT NULL DEFAULT 'offline' CHECK (status IN ('online', 'offline', 'maintenance', 'paused', 'disabled')),
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  last_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (school_id, station_code),
  UNIQUE (id, school_id)
);
CREATE INDEX IF NOT EXISTS idx_test_stations_school_status ON test_stations(school_id, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS test_devices (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  station_id TEXT REFERENCES test_stations(id) ON DELETE SET NULL,
  device_code TEXT NOT NULL,
  name TEXT NOT NULL,
  device_type TEXT NOT NULL CHECK (device_type IN ('edge_host', 'depth_camera', 'rgb_camera', 'display', 'speaker', 'reader', 'ups', 'network')),
  serial_number TEXT,
  software_version TEXT NOT NULL DEFAULT '',
  api_key_hash TEXT NOT NULL UNIQUE,
  api_key_expires_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'offline' CHECK (status IN ('online', 'offline', 'maintenance', 'disabled')),
  capabilities_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  health_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  last_heartbeat_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (school_id, device_code),
  UNIQUE (id, school_id)
);
CREATE INDEX IF NOT EXISTS idx_test_devices_station_status ON test_devices(station_id, status, last_heartbeat_at DESC);

CREATE TABLE IF NOT EXISTS station_calibrations (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  station_id TEXT NOT NULL REFERENCES test_stations(id) ON DELETE CASCADE,
  version TEXT NOT NULL,
  checksum_sha256 TEXT NOT NULL,
  config_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'archived', 'invalid')),
  verified_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  verified_at TIMESTAMPTZ,
  effective_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (station_id, version)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_station_calibration_active ON station_calibrations(station_id) WHERE status='active';

CREATE TABLE IF NOT EXISTS test_queue_entries (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  task_id TEXT NOT NULL REFERENCES assessment_tasks(id) ON DELETE CASCADE,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  station_id TEXT REFERENCES test_stations(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting', 'called', 'checked_in', 'testing', 'completed', 'retest', 'absent', 'skipped', 'cancelled', 'paused')),
  priority INTEGER NOT NULL DEFAULT 0,
  queue_order INTEGER NOT NULL DEFAULT 0,
  retest_count INTEGER NOT NULL DEFAULT 0,
  state_version INTEGER NOT NULL DEFAULT 1,
  note TEXT NOT NULL DEFAULT '',
  last_called_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (task_id, student_id)
);
CREATE INDEX IF NOT EXISTS idx_test_queue_dispatch ON test_queue_entries(task_id, station_id, status, priority DESC, queue_order, created_at);
CREATE INDEX IF NOT EXISTS idx_test_queue_student ON test_queue_entries(student_id, created_at DESC);

CREATE TABLE IF NOT EXISTS test_sessions (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  client_session_id TEXT NOT NULL UNIQUE,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  task_id TEXT NOT NULL REFERENCES assessment_tasks(id) ON DELETE CASCADE,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  station_id TEXT REFERENCES test_stations(id) ON DELETE SET NULL,
  edge_device_id TEXT REFERENCES test_devices(id) ON DELETE SET NULL,
  queue_entry_id TEXT REFERENCES test_queue_entries(id) ON DELETE SET NULL,
  attempt_no INTEGER NOT NULL DEFAULT 1 CHECK (attempt_no >= 1),
  status TEXT NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'checked_in', 'testing', 'completed', 'needs_review', 'retest', 'cancelled', 'aborted', 'sync_conflict')),
  rule_version TEXT NOT NULL,
  calibration_version TEXT NOT NULL DEFAULT '',
  algorithm_version TEXT NOT NULL DEFAULT '',
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  device_started_at TIMESTAMPTZ,
  device_ended_at TIMESTAMPTZ,
  sync_version INTEGER NOT NULL DEFAULT 1,
  summary_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (task_id, student_id, attempt_no)
);
CREATE INDEX IF NOT EXISTS idx_test_sessions_task_student ON test_sessions(task_id, student_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_test_sessions_station_status ON test_sessions(station_id, status, started_at DESC);

CREATE TABLE IF NOT EXISTS session_action_events (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  session_id TEXT NOT NULL REFERENCES test_sessions(id) ON DELETE CASCADE,
  client_event_id TEXT NOT NULL UNIQUE,
  sequence_no INTEGER NOT NULL CHECK (sequence_no >= 0),
  event_type TEXT NOT NULL,
  happened_at TIMESTAMPTZ NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, sequence_no)
);
CREATE INDEX IF NOT EXISTS idx_session_action_events_timeline ON session_action_events(session_id, sequence_no);

CREATE TABLE IF NOT EXISTS session_evidence (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  session_id TEXT NOT NULL REFERENCES test_sessions(id) ON DELETE CASCADE,
  file_id TEXT NOT NULL REFERENCES files(id) ON DELETE RESTRICT,
  evidence_type TEXT NOT NULL CHECK (evidence_type IN ('video', 'image', 'skeleton', 'timeline', 'calibration', 'log', 'other')),
  ordinal INTEGER NOT NULL DEFAULT 0,
  checksum_sha256 TEXT,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, evidence_type, ordinal),
  UNIQUE (file_id)
);
CREATE INDEX IF NOT EXISTS idx_session_evidence_session ON session_evidence(session_id, evidence_type, ordinal);

CREATE TABLE IF NOT EXISTS queue_events (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  queue_entry_id TEXT NOT NULL REFERENCES test_queue_entries(id) ON DELETE CASCADE,
  client_event_id TEXT UNIQUE,
  old_status TEXT,
  new_status TEXT NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  actor_type TEXT NOT NULL CHECK (actor_type IN ('device', 'teacher', 'admin', 'system')),
  actor_id TEXT,
  station_id TEXT REFERENCES test_stations(id) ON DELETE SET NULL,
  happened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_queue_events_entry_time ON queue_events(queue_entry_id, happened_at DESC);

CREATE TABLE IF NOT EXISTS field_sync_batches (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  device_id TEXT NOT NULL REFERENCES test_devices(id) ON DELETE CASCADE,
  client_batch_id TEXT NOT NULL,
  event_count INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'completed', 'failed')),
  response_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  UNIQUE (device_id, client_batch_id)
);

CREATE TABLE IF NOT EXISTS field_sync_events (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  device_id TEXT NOT NULL REFERENCES test_devices(id) ON DELETE CASCADE,
  client_event_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  session_id TEXT REFERENCES test_sessions(id) ON DELETE SET NULL,
  happened_at TIMESTAMPTZ NOT NULL,
  payload_hash TEXT NOT NULL,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (device_id, client_event_id)
);
CREATE INDEX IF NOT EXISTS idx_field_sync_events_device_time ON field_sync_events(device_id, processed_at DESC);

CREATE TABLE IF NOT EXISTS device_commands (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  station_id TEXT REFERENCES test_stations(id) ON DELETE CASCADE,
  device_id TEXT REFERENCES test_devices(id) ON DELETE CASCADE,
  command_type TEXT NOT NULL CHECK (command_type IN ('pause', 'resume', 'stop', 'call_next', 'recall', 'skip', 'retest', 'refresh_config')),
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'delivered', 'acknowledged', 'failed', 'cancelled')),
  issued_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  acknowledged_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_device_commands_pending ON device_commands(device_id, status, created_at) WHERE status IN ('pending', 'delivered');

ALTER TABLE assessment_scores ADD COLUMN IF NOT EXISTS session_id TEXT REFERENCES test_sessions(id) ON DELETE SET NULL;
ALTER TABLE assessment_scores ADD COLUMN IF NOT EXISTS algorithm_version TEXT NOT NULL DEFAULT '';
ALTER TABLE assessment_scores ADD COLUMN IF NOT EXISTS evidence_json JSONB NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS idx_assessment_scores_session ON assessment_scores(session_id);
