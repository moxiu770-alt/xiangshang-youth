-- Older migrations looked up constraint names across the whole database.
-- PostgreSQL constraint names are only unique per table, so a second schema
-- could incorrectly inherit a "constraint exists" decision from public.
-- Repair every affected constraint using the current search_path relation.

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='grades_id_school_unique' AND conrelid='grades'::regclass) THEN
    ALTER TABLE grades ADD CONSTRAINT grades_id_school_unique UNIQUE (id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='classes_id_school_unique' AND conrelid='classes'::regclass) THEN
    ALTER TABLE classes ADD CONSTRAINT classes_id_school_unique UNIQUE (id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='classes_grade_school_fk' AND conrelid='classes'::regclass) THEN
    ALTER TABLE classes ADD CONSTRAINT classes_grade_school_fk FOREIGN KEY (grade_id, school_id) REFERENCES grades(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='students_grade_school_fk' AND conrelid='students'::regclass) THEN
    ALTER TABLE students ADD CONSTRAINT students_grade_school_fk FOREIGN KEY (grade_id, school_id) REFERENCES grades(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='students_class_school_fk' AND conrelid='students'::regclass) THEN
    ALTER TABLE students ADD CONSTRAINT students_class_school_fk FOREIGN KEY (class_id, school_id) REFERENCES classes(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='tasks_grade_school_fk' AND conrelid='assessment_tasks'::regclass) THEN
    ALTER TABLE assessment_tasks ADD CONSTRAINT tasks_grade_school_fk FOREIGN KEY (grade_id, school_id) REFERENCES grades(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='tasks_class_school_fk' AND conrelid='assessment_tasks'::regclass) THEN
    ALTER TABLE assessment_tasks ADD CONSTRAINT tasks_class_school_fk FOREIGN KEY (class_id, school_id) REFERENCES classes(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='user_roles_class_requires_school' AND conrelid='user_roles'::regclass) THEN
    ALTER TABLE user_roles ADD CONSTRAINT user_roles_class_requires_school CHECK (class_id IS NULL OR school_id IS NOT NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='user_roles_class_school_fk' AND conrelid='user_roles'::regclass) THEN
    ALTER TABLE user_roles ADD CONSTRAINT user_roles_class_school_fk FOREIGN KEY (class_id, school_id) REFERENCES classes(id, school_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='tasks_id_school_unique' AND conrelid='assessment_tasks'::regclass) THEN
    ALTER TABLE assessment_tasks ADD CONSTRAINT tasks_id_school_unique UNIQUE (id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='students_id_school_unique' AND conrelid='students'::regclass) THEN
    ALTER TABLE students ADD CONSTRAINT students_id_school_unique UNIQUE (id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_queue_entries_id_school_unique' AND conrelid='test_queue_entries'::regclass) THEN
    ALTER TABLE test_queue_entries ADD CONSTRAINT test_queue_entries_id_school_unique UNIQUE (id, school_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_devices_station_school_fk' AND conrelid='test_devices'::regclass) THEN
    ALTER TABLE test_devices ADD CONSTRAINT test_devices_station_school_fk FOREIGN KEY (station_id, school_id) REFERENCES test_stations(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_queue_task_school_fk' AND conrelid='test_queue_entries'::regclass) THEN
    ALTER TABLE test_queue_entries ADD CONSTRAINT test_queue_task_school_fk FOREIGN KEY (task_id, school_id) REFERENCES assessment_tasks(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_queue_student_school_fk' AND conrelid='test_queue_entries'::regclass) THEN
    ALTER TABLE test_queue_entries ADD CONSTRAINT test_queue_student_school_fk FOREIGN KEY (student_id, school_id) REFERENCES students(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_queue_station_school_fk' AND conrelid='test_queue_entries'::regclass) THEN
    ALTER TABLE test_queue_entries ADD CONSTRAINT test_queue_station_school_fk FOREIGN KEY (station_id, school_id) REFERENCES test_stations(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_sessions_task_school_fk' AND conrelid='test_sessions'::regclass) THEN
    ALTER TABLE test_sessions ADD CONSTRAINT test_sessions_task_school_fk FOREIGN KEY (task_id, school_id) REFERENCES assessment_tasks(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_sessions_student_school_fk' AND conrelid='test_sessions'::regclass) THEN
    ALTER TABLE test_sessions ADD CONSTRAINT test_sessions_student_school_fk FOREIGN KEY (student_id, school_id) REFERENCES students(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_sessions_station_school_fk' AND conrelid='test_sessions'::regclass) THEN
    ALTER TABLE test_sessions ADD CONSTRAINT test_sessions_station_school_fk FOREIGN KEY (station_id, school_id) REFERENCES test_stations(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_sessions_device_school_fk' AND conrelid='test_sessions'::regclass) THEN
    ALTER TABLE test_sessions ADD CONSTRAINT test_sessions_device_school_fk FOREIGN KEY (edge_device_id, school_id) REFERENCES test_devices(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_sessions_queue_school_fk' AND conrelid='test_sessions'::regclass) THEN
    ALTER TABLE test_sessions ADD CONSTRAINT test_sessions_queue_school_fk FOREIGN KEY (queue_entry_id, school_id) REFERENCES test_queue_entries(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='device_commands_station_school_fk' AND conrelid='device_commands'::regclass) THEN
    ALTER TABLE device_commands ADD CONSTRAINT device_commands_station_school_fk FOREIGN KEY (station_id, school_id) REFERENCES test_stations(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='device_commands_device_school_fk' AND conrelid='device_commands'::regclass) THEN
    ALTER TABLE device_commands ADD CONSTRAINT device_commands_device_school_fk FOREIGN KEY (device_id, school_id) REFERENCES test_devices(id, school_id);
  END IF;
END $$;
