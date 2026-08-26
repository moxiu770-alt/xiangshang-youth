-- Database-level tenant integrity for relationships that combine records from
-- multiple school-scoped tables. Application authorization remains necessary,
-- but these constraints prevent a future import, worker or new API endpoint
-- from accidentally wiring two schools' operational data together.

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='tasks_id_school_unique') THEN
    ALTER TABLE assessment_tasks ADD CONSTRAINT tasks_id_school_unique UNIQUE (id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='students_id_school_unique') THEN
    ALTER TABLE students ADD CONSTRAINT students_id_school_unique UNIQUE (id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_queue_entries_id_school_unique') THEN
    ALTER TABLE test_queue_entries ADD CONSTRAINT test_queue_entries_id_school_unique UNIQUE (id, school_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_devices_station_school_fk') THEN
    ALTER TABLE test_devices ADD CONSTRAINT test_devices_station_school_fk
      FOREIGN KEY (station_id, school_id) REFERENCES test_stations(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_queue_task_school_fk') THEN
    ALTER TABLE test_queue_entries ADD CONSTRAINT test_queue_task_school_fk
      FOREIGN KEY (task_id, school_id) REFERENCES assessment_tasks(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_queue_student_school_fk') THEN
    ALTER TABLE test_queue_entries ADD CONSTRAINT test_queue_student_school_fk
      FOREIGN KEY (student_id, school_id) REFERENCES students(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_queue_station_school_fk') THEN
    ALTER TABLE test_queue_entries ADD CONSTRAINT test_queue_station_school_fk
      FOREIGN KEY (station_id, school_id) REFERENCES test_stations(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_sessions_task_school_fk') THEN
    ALTER TABLE test_sessions ADD CONSTRAINT test_sessions_task_school_fk
      FOREIGN KEY (task_id, school_id) REFERENCES assessment_tasks(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_sessions_student_school_fk') THEN
    ALTER TABLE test_sessions ADD CONSTRAINT test_sessions_student_school_fk
      FOREIGN KEY (student_id, school_id) REFERENCES students(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_sessions_station_school_fk') THEN
    ALTER TABLE test_sessions ADD CONSTRAINT test_sessions_station_school_fk
      FOREIGN KEY (station_id, school_id) REFERENCES test_stations(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_sessions_device_school_fk') THEN
    ALTER TABLE test_sessions ADD CONSTRAINT test_sessions_device_school_fk
      FOREIGN KEY (edge_device_id, school_id) REFERENCES test_devices(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_sessions_queue_school_fk') THEN
    ALTER TABLE test_sessions ADD CONSTRAINT test_sessions_queue_school_fk
      FOREIGN KEY (queue_entry_id, school_id) REFERENCES test_queue_entries(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='device_commands_station_school_fk') THEN
    ALTER TABLE device_commands ADD CONSTRAINT device_commands_station_school_fk
      FOREIGN KEY (station_id, school_id) REFERENCES test_stations(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='device_commands_device_school_fk') THEN
    ALTER TABLE device_commands ADD CONSTRAINT device_commands_device_school_fk
      FOREIGN KEY (device_id, school_id) REFERENCES test_devices(id, school_id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION assert_school_scoped_linkage() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  left_school_id TEXT;
  right_school_id TEXT;
  new_row JSONB := to_jsonb(NEW);
BEGIN
  IF TG_TABLE_NAME IN ('task_students', 'assessment_scores', 'diagnosis_reports') THEN
    SELECT school_id INTO left_school_id FROM assessment_tasks WHERE id=new_row->>'task_id';
    SELECT school_id INTO right_school_id FROM students WHERE id=new_row->>'student_id';
    IF left_school_id IS DISTINCT FROM right_school_id THEN
      RAISE EXCEPTION 'task and student must belong to the same school' USING ERRCODE='23514';
    END IF;
  ELSIF TG_TABLE_NAME = 'queue_events' AND new_row->>'station_id' IS NOT NULL THEN
    SELECT school_id INTO left_school_id FROM test_queue_entries WHERE id=new_row->>'queue_entry_id';
    SELECT school_id INTO right_school_id FROM test_stations WHERE id=new_row->>'station_id';
    IF left_school_id IS DISTINCT FROM right_school_id THEN
      RAISE EXCEPTION 'queue event station must belong to the queue school' USING ERRCODE='23514';
    END IF;
  ELSIF TG_TABLE_NAME = 'field_sync_events' AND new_row->>'session_id' IS NOT NULL THEN
    SELECT school_id INTO left_school_id FROM test_devices WHERE id=new_row->>'device_id';
    SELECT school_id INTO right_school_id FROM test_sessions WHERE id=new_row->>'session_id';
    IF left_school_id IS DISTINCT FROM right_school_id THEN
      RAISE EXCEPTION 'field sync device and session must belong to the same school' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS task_students_school_scope ON task_students;
CREATE TRIGGER task_students_school_scope BEFORE INSERT OR UPDATE OF task_id,student_id ON task_students
  FOR EACH ROW EXECUTE FUNCTION assert_school_scoped_linkage();

DROP TRIGGER IF EXISTS assessment_scores_school_scope ON assessment_scores;
CREATE TRIGGER assessment_scores_school_scope BEFORE INSERT OR UPDATE OF task_id,student_id ON assessment_scores
  FOR EACH ROW EXECUTE FUNCTION assert_school_scoped_linkage();

DROP TRIGGER IF EXISTS diagnosis_reports_school_scope ON diagnosis_reports;
CREATE TRIGGER diagnosis_reports_school_scope BEFORE INSERT OR UPDATE OF task_id,student_id ON diagnosis_reports
  FOR EACH ROW EXECUTE FUNCTION assert_school_scoped_linkage();

DROP TRIGGER IF EXISTS queue_events_school_scope ON queue_events;
CREATE TRIGGER queue_events_school_scope BEFORE INSERT OR UPDATE OF queue_entry_id,station_id ON queue_events
  FOR EACH ROW EXECUTE FUNCTION assert_school_scoped_linkage();

DROP TRIGGER IF EXISTS field_sync_events_school_scope ON field_sync_events;
CREATE TRIGGER field_sync_events_school_scope BEFORE INSERT OR UPDATE OF device_id,session_id ON field_sync_events
  FOR EACH ROW EXECUTE FUNCTION assert_school_scoped_linkage();
