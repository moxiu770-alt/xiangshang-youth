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
