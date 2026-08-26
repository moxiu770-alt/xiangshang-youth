DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='grades_id_school_unique') THEN
    ALTER TABLE grades ADD CONSTRAINT grades_id_school_unique UNIQUE (id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='classes_id_school_unique') THEN
    ALTER TABLE classes ADD CONSTRAINT classes_id_school_unique UNIQUE (id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='classes_grade_school_fk') THEN
    ALTER TABLE classes ADD CONSTRAINT classes_grade_school_fk FOREIGN KEY (grade_id, school_id) REFERENCES grades(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='students_grade_school_fk') THEN
    ALTER TABLE students ADD CONSTRAINT students_grade_school_fk FOREIGN KEY (grade_id, school_id) REFERENCES grades(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='students_class_school_fk') THEN
    ALTER TABLE students ADD CONSTRAINT students_class_school_fk FOREIGN KEY (class_id, school_id) REFERENCES classes(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='tasks_grade_school_fk') THEN
    ALTER TABLE assessment_tasks ADD CONSTRAINT tasks_grade_school_fk FOREIGN KEY (grade_id, school_id) REFERENCES grades(id, school_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='tasks_class_school_fk') THEN
    ALTER TABLE assessment_tasks ADD CONSTRAINT tasks_class_school_fk FOREIGN KEY (class_id, school_id) REFERENCES classes(id, school_id);
  END IF;
END $$;
