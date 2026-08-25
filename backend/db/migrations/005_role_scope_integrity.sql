DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='user_roles_class_requires_school') THEN
    ALTER TABLE user_roles ADD CONSTRAINT user_roles_class_requires_school CHECK (class_id IS NULL OR school_id IS NOT NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='user_roles_class_school_fk') THEN
    ALTER TABLE user_roles ADD CONSTRAINT user_roles_class_school_fk FOREIGN KEY (class_id, school_id) REFERENCES classes(id, school_id);
  END IF;
END $$;
