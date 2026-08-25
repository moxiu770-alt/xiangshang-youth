CREATE INDEX IF NOT EXISTS idx_students_school_status ON students(school_id, status);
CREATE INDEX IF NOT EXISTS idx_task_students_student_time ON task_students(student_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_roles_user_scope ON user_roles(user_id, school_id, class_id);
