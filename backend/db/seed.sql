INSERT INTO schools(id, name, campus, region, is_poverty_area)
VALUES ('school-1', '向上实验小学', '南湖校区', '广东省韶关市乳源瑶族自治县', TRUE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO grades(id, school_id, name, standard_version, academic_year)
VALUES
  ('grade-1', 'school-1', '一年级', '运动能力标准 v1.0', '2026'),
  ('grade-2', 'school-1', '二年级', '运动能力标准 v1.0', '2026'),
  ('grade-3', 'school-1', '三年级', '运动能力标准 v1.0', '2026')
ON CONFLICT (id) DO NOTHING;

INSERT INTO classes(id, school_id, grade_id, name)
VALUES
  ('class-1', 'school-1', 'grade-1', '一年级1班'),
  ('class-2', 'school-1', 'grade-2', '二年级1班'),
  ('class-3', 'school-1', 'grade-3', '三年级2班')
ON CONFLICT (id) DO NOTHING;

INSERT INTO rule_versions(code, version, config)
VALUES ('movement-assessment', 'v1.0', '{"itemCount":7,"itemMaximum":5,"reviewConfidenceThreshold":0.8}')
ON CONFLICT (code, version) DO NOTHING;

INSERT INTO users(id, phone, name, password_hash)
VALUES
  ('user-admin', '13800000000', '演示管理员', 'scrypt$xiangshang-demo-salt$41123a19c947c7bcd91d1c200666b8607bf464ccdcd8cf6c6c35e8b4b24fb838bea13692b60fcf512d73c0b09a1523427c6ae345e93c5f6519213ca0b7b61f39'),
  ('user-teacher', '13800000001', '演示教师', 'scrypt$xiangshang-demo-salt$41123a19c947c7bcd91d1c200666b8607bf464ccdcd8cf6c6c35e8b4b24fb838bea13692b60fcf512d73c0b09a1523427c6ae345e93c5f6519213ca0b7b61f39'),
  ('user-parent', '13800000002', '演示家长', 'scrypt$xiangshang-demo-salt$41123a19c947c7bcd91d1c200666b8607bf464ccdcd8cf6c6c35e8b4b24fb838bea13692b60fcf512d73c0b09a1523427c6ae345e93c5f6519213ca0b7b61f39')
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_roles(user_id, role_id, school_id, class_id)
SELECT 'user-admin', id, 'school-1', NULL FROM roles WHERE code='admin'
ON CONFLICT DO NOTHING;
INSERT INTO user_roles(user_id, role_id, school_id, class_id)
SELECT 'user-teacher', id, 'school-1', 'class-3' FROM roles WHERE code='teacher'
ON CONFLICT DO NOTHING;
INSERT INTO user_roles(user_id, role_id, school_id, class_id)
SELECT 'user-parent', id, 'school-1', NULL FROM roles WHERE code='parent'
ON CONFLICT DO NOTHING;
UPDATE classes SET teacher_id='user-teacher' WHERE id='class-3';

INSERT INTO students(id, school_id, grade_id, class_id, student_no, name, gender, birth_date, region, is_poverty_area)
VALUES
  ('student-1', 'school-1', 'grade-3', 'class-3', 'XS-S01', '王小明', '男', '2017-05-12', '广东省韶关市乳源瑶族自治县', TRUE),
  ('student-2', 'school-1', 'grade-3', 'class-3', 'XS-S02', '王小雨', '女', '2017-09-18', '广东省韶关市乳源瑶族自治县', TRUE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO parent_student_bindings(parent_user_id, student_id, relation, binding_code)
VALUES ('user-parent', 'student-1', '母子', 'XS-S01'), ('user-parent', 'student-2', '母女', 'XS-S02')
ON CONFLICT (parent_user_id, student_id) DO NOTHING;

INSERT INTO assessment_tasks(id, school_id, title, test_date, location, grade_id, class_id, items, rule_version, status, created_by)
VALUES ('task-demo', 'school-1', '2026 春季综合运动能力测评', '2026-09-12', '学校操场', 'grade-3', 'class-3', '["连续双脚障碍跳","侧向滑步","倒退平衡","接球-上手掷准","手运球绕杆","脚运球变向","定点踢准"]', '运动能力标准 v1.0', 'published', 'user-teacher')
ON CONFLICT (id) DO NOTHING;

INSERT INTO task_students(task_id, student_id, status)
VALUES ('task-demo', 'student-1', '已完成'), ('task-demo', 'student-2', '待复核')
ON CONFLICT (task_id, student_id) DO NOTHING;

UPDATE assessment_tasks
SET items='["连续双脚障碍跳","侧向滑步","倒退平衡","接球-上手掷准","手运球绕杆","脚运球变向","定点踢准"]'::jsonb
WHERE id='task-demo';

INSERT INTO messages(receiver_user_id, title, content, category)
VALUES ('user-parent', '测评任务已发布', '请关注孩子的综合运动能力测评安排。', 'task'), ('user-teacher', '待复核提醒', '有学生成绩需要复核。', 'review')
ON CONFLICT DO NOTHING;
