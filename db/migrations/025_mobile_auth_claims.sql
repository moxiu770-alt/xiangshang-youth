-- Mobile clients must receive one explicit, server-authoritative claim set.
-- Role scope stays in user_roles; capabilities are intentionally modeled
-- separately so a homeroom teacher and a PE teacher can share a role code
-- without receiving the same operational powers.
CREATE TABLE IF NOT EXISTS capabilities (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS role_capabilities (
  role_id TEXT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  capability_code TEXT NOT NULL REFERENCES capabilities(code) ON DELETE CASCADE,
  PRIMARY KEY (role_id, capability_code)
);

CREATE TABLE IF NOT EXISTS user_capability_overrides (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  capability_code TEXT NOT NULL REFERENCES capabilities(code) ON DELETE CASCADE,
  allowed BOOLEAN NOT NULL,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  class_id TEXT REFERENCES classes(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_capability_override_scope
  ON user_capability_overrides(user_id, capability_code, COALESCE(school_id, ''), COALESCE(class_id, ''));
CREATE INDEX IF NOT EXISTS idx_user_capability_overrides_active
  ON user_capability_overrides(user_id, expires_at);

INSERT INTO capabilities(code, name, description) VALUES
  ('VIEW_CLASS_DASHBOARD', '查看班级看板', '查看授权班级的测评完成与统计'),
  ('MANAGE_CLASS_STUDENTS', '管理班级学生', '查看和维护授权班级学生名单'),
  ('VIEW_TEST_TASKS', '查看测评任务', '查看授权范围内的体测任务'),
  ('UPDATE_TEST_STATUS', '更新测评状态', '更新签到、候测、完成和缺席状态'),
  ('REVIEW_RESULT', '复核测评结果', '查看并提交成绩复核'),
  ('REQUEST_RETEST', '申请补测', '为学生申请补测'),
  ('UPLOAD_AFTER_SCHOOL_COURSE', '上传课后课程', '提交课后课程内容'),
  ('PUBLISH_CLASS_NOTICE', '发布班级通知', '向授权班级发送通知')
ON CONFLICT (code) DO NOTHING;

-- The seed teacher is intentionally granted only the operational powers
-- needed for the existing pilot flow. Production schools can configure this
-- mapping in the management backend or use user_capability_overrides.
INSERT INTO role_capabilities(role_id, capability_code)
SELECT r.id, c.code
FROM roles r CROSS JOIN capabilities c
WHERE r.code = 'teacher'
  AND c.code IN ('VIEW_CLASS_DASHBOARD', 'MANAGE_CLASS_STUDENTS', 'VIEW_TEST_TASKS', 'UPDATE_TEST_STATUS', 'REVIEW_RESULT', 'REQUEST_RETEST', 'PUBLISH_CLASS_NOTICE')
ON CONFLICT DO NOTHING;
