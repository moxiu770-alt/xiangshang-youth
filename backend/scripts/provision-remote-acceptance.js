import crypto from 'node:crypto';
import { promisify } from 'node:util';
import { Pool } from 'pg';

const scrypt = promisify(crypto.scrypt);
const required = (name) => {
  const value = String(process.env[name] || '').trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
};
const requirePhone = (name) => {
  const value = required(name);
  if (!/^1\d{10}$/.test(value)) throw new Error(`${name} must be a dedicated 11-digit mobile-style test account`);
  return value;
};
const requirePassword = (name) => {
  const value = required(name);
  if (value.length < 12 || !/[A-Z]/.test(value) || !/[a-z]/.test(value) || !/\d/.test(value)) {
    throw new Error(`${name} must be at least 12 characters and contain upper-case, lower-case and numeric characters`);
  }
  return value;
};
const stableId = (scope, kind) => `remote-e2e-${kind}-${crypto.createHash('sha256').update(scope).digest('hex').slice(0, 12)}`;
const passwordHash = async (value) => {
  const salt = crypto.randomBytes(16).toString('hex');
  const derived = (await scrypt(value, salt, 64)).toString('hex');
  return `scrypt$${salt}$${derived}`;
};

if (process.env.REMOTE_FIXTURE_CONFIRM !== '1') {
  throw new Error('REMOTE_FIXTURE_CONFIRM=1 is required; this command creates persistent, isolated acceptance fixtures');
}

const databaseUrl = required('DATABASE_URL');
const scope = String(process.env.REMOTE_FIXTURE_SCOPE || 'pilot').trim().toLowerCase();
if (!/^[a-z0-9-]{2,32}$/.test(scope)) throw new Error('REMOTE_FIXTURE_SCOPE must contain only lower-case letters, numbers and hyphens');
const parentAccount = requirePhone('REMOTE_FIXTURE_PARENT_ACCOUNT');
const teacherAccount = requirePhone('REMOTE_FIXTURE_TEACHER_ACCOUNT');
if (parentAccount === teacherAccount) throw new Error('Parent and teacher acceptance accounts must be different');
const parentSecret = requirePassword('REMOTE_FIXTURE_PARENT_PASSWORD');
const teacherSecret = requirePassword('REMOTE_FIXTURE_TEACHER_PASSWORD');

const ids = Object.freeze({
  schoolId: stableId(scope, 'school'),
  gradeId: stableId(scope, 'grade'),
  classId: stableId(scope, 'class'),
  parentUserId: stableId(scope, 'parent'),
  teacherUserId: stableId(scope, 'teacher'),
  studentId: stableId(scope, 'student'),
  taskId: stableId(scope, 'task'),
  reportId: stableId(scope, 'report'),
  reportVersionId: stableId(scope, 'report-version'),
  courseId: stableId(scope, 'course'),
  moduleId: stableId(scope, 'module'),
  lessonId: stableId(scope, 'lesson'),
  activityId: stableId(scope, 'activity'),
  expertId: stableId(scope, 'expert'),
  firstSlotId: stableId(scope, 'slot-a'),
  secondSlotId: stableId(scope, 'slot-b')
});

const [parentHash, teacherHash] = await Promise.all([passwordHash(parentSecret), passwordHash(teacherSecret)]);
const pool = new Pool({ connectionString: databaseUrl, max: 1 });
const client = await pool.connect();
try {
  await client.query('BEGIN');
  await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`xiangshang.remote-fixture.${scope}`]);

  const roles = await client.query("SELECT id,code FROM roles WHERE code IN ('parent','teacher')");
  const roleByCode = new Map(roles.rows.map((row) => [row.code, row.id]));
  if (!roleByCode.get('parent') || !roleByCode.get('teacher')) throw new Error('parent and teacher roles must exist before provisioning fixtures');

  await client.query(`INSERT INTO schools(id,name,campus,region,is_poverty_area,status)
    VALUES($1,$2,'远程验收隔离校区','广东省广州市',false,'active')
    ON CONFLICT(id) DO UPDATE SET name=EXCLUDED.name,status='active',updated_at=now()`, [ids.schoolId, `向上少年远程验收学校（${scope}）`]);
  await client.query(`INSERT INTO grades(id,school_id,name,standard_version,academic_year)
    VALUES($1,$2,'远程验收年级','运动能力标准 v1.0','acceptance')
    ON CONFLICT(id) DO UPDATE SET standard_version=EXCLUDED.standard_version`, [ids.gradeId, ids.schoolId]);

  await client.query(`INSERT INTO users(id,phone,name,password_hash,status)
    VALUES($1,$2,'远程验收家长',$3,'active')
    ON CONFLICT(id) DO UPDATE SET phone=EXCLUDED.phone,password_hash=EXCLUDED.password_hash,status='active',updated_at=now()`, [ids.parentUserId, parentAccount, parentHash]);
  await client.query(`INSERT INTO users(id,phone,name,password_hash,status)
    VALUES($1,$2,'远程验收教师',$3,'active')
    ON CONFLICT(id) DO UPDATE SET phone=EXCLUDED.phone,password_hash=EXCLUDED.password_hash,status='active',updated_at=now()`, [ids.teacherUserId, teacherAccount, teacherHash]);

  await client.query(`INSERT INTO classes(id,school_id,grade_id,name,teacher_id)
    VALUES($1,$2,$3,'远程验收1班',$4)
    ON CONFLICT(id) DO UPDATE SET teacher_id=EXCLUDED.teacher_id`, [ids.classId, ids.schoolId, ids.gradeId, ids.teacherUserId]);
  await client.query(`INSERT INTO user_roles(user_id,role_id,school_id,class_id)
    VALUES($1,$2,$3,NULL) ON CONFLICT DO NOTHING`, [ids.parentUserId, roleByCode.get('parent'), ids.schoolId]);
  await client.query(`INSERT INTO user_roles(user_id,role_id,school_id,class_id)
    VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING`, [ids.teacherUserId, roleByCode.get('teacher'), ids.schoolId, ids.classId]);

  await client.query(`INSERT INTO students(id,school_id,grade_id,class_id,student_no,name,gender,birth_date,region,is_poverty_area,status)
    VALUES($1,$2,$3,$4,$5,'验收同学','男','2017-06-01','广东省广州市',false,'active')
    ON CONFLICT(id) DO UPDATE SET class_id=EXCLUDED.class_id,status='active',updated_at=now()`, [ids.studentId, ids.schoolId, ids.gradeId, ids.classId, `REMOTE-${scope.toUpperCase()}`]);
  await client.query(`INSERT INTO parent_student_bindings(parent_user_id,student_id,relation,status)
    VALUES($1,$2,'监护人','active')
    ON CONFLICT(parent_user_id,student_id) DO UPDATE SET status='active',expires_at=NULL`, [ids.parentUserId, ids.studentId]);

  const movementItems = ['连续双脚障碍跳','侧向滑步','倒退平衡','接球-上手掷准','手运球绕杆','脚运球变向','定点踢准'];
  await client.query(`INSERT INTO assessment_tasks(id,school_id,title,test_date,location,grade_id,class_id,items,rule_version,status,created_by)
    VALUES($1,$2,'远程接口验收专用任务',current_date+14,'隔离验收环境',$3,$4,$5::jsonb,'运动能力标准 v1.0','published',$6)
    ON CONFLICT(id) DO UPDATE SET test_date=current_date+14,status='published',updated_at=now()`, [ids.taskId, ids.schoolId, ids.gradeId, ids.classId, JSON.stringify(movementItems), ids.teacherUserId]);
  await client.query(`INSERT INTO task_students(task_id,student_id,status,version)
    VALUES($1,$2,'已签到',1) ON CONFLICT(task_id,student_id) DO NOTHING`, [ids.taskId, ids.studentId]);

  const scores = movementItems.map((item) => ({ item, score: 4, confidence: 0.99, reviewStatus: 'passed', humanReviewed: true }));
  const reportJson = {
    id: ids.reportId,
    studentId: ids.studentId,
    studentName: '验收同学',
    gradeName: '远程验收年级',
    className: '远程验收1班',
    measuredAt: new Date().toISOString(),
    scores,
    abilityTags: ['动作协调'],
    risks: [],
    trainingSuggestions: ['保持规律运动'],
    courseSuggestions: [{ courseId: ids.courseId, lessonId: ids.lessonId, title: '远程验收课程' }],
    ruleVersion: '运动能力标准 v1.0'
  };
  await client.query(`INSERT INTO diagnosis_reports(id,student_id,task_id,risk_level,total_score,rule_version,status,current_version,published_at,published_version)
    VALUES($1,$2,$3,'low',28,'运动能力标准 v1.0','published',1,now(),1)
    ON CONFLICT(id) DO UPDATE SET status='published',published_version=1,published_at=now()`, [ids.reportId, ids.studentId, ids.taskId]);
  await client.query(`INSERT INTO report_versions(id,report_id,version,report_json,generated_by)
    VALUES($1,$2,1,$3::jsonb,$4)
    ON CONFLICT(report_id,version) DO UPDATE SET report_json=EXCLUDED.report_json,generated_at=now()`, [ids.reportVersionId, ids.reportId, JSON.stringify(reportJson), ids.teacherUserId]);

  await client.query(`INSERT INTO courses(id,school_id,title,category,duration,focus,is_public_benefit,status)
    VALUES($1,$2,'远程验收课程','基础训练','05:00','动作控制',true,'active')
    ON CONFLICT(id) DO UPDATE SET status='active'`, [ids.courseId, ids.schoolId]);
  await client.query(`INSERT INTO course_modules(id,course_id,title,sort_order)
    VALUES($1,$2,'验收模块',1) ON CONFLICT(id) DO UPDATE SET title=EXCLUDED.title`, [ids.moduleId, ids.courseId]);
  await client.query(`INSERT INTO course_lessons(id,course_id,module_id,title,duration_ms,video_source,captions,sort_order,status)
    VALUES($1,$2,$3,'验收课节',300000,NULL,'[]'::jsonb,1,'active')
    ON CONFLICT(id) DO UPDATE SET status='active',duration_ms=300000`, [ids.lessonId, ids.courseId, ids.moduleId]);

  await client.query(`INSERT INTO activities(id,school_id,title,description,starts_at,ends_at,capacity,registration_start_at,registration_end_at,status,created_by,version)
    VALUES($1,$2,'远程接口验收活动','仅供自动化创建、编辑、冲突和取消验收',now()+interval '14 day',now()+interval '14 day 2 hour',5,now()-interval '1 day',now()+interval '10 day','published',$3,1)
    ON CONFLICT(id) DO UPDATE SET registration_start_at=now()-interval '1 day',registration_end_at=now()+interval '10 day',starts_at=now()+interval '14 day',ends_at=now()+interval '14 day 2 hour',capacity=5,status='published',updated_at=now()`, [ids.activityId, ids.schoolId, ids.teacherUserId]);
  await client.query(`INSERT INTO experts(id,school_id,name,title,bio,status)
    VALUES($1,$2,'远程验收专家','自动化验收','仅供隔离远程验收使用','active')
    ON CONFLICT(id) DO UPDATE SET status='active',updated_at=now()`, [ids.expertId, ids.schoolId]);
  await client.query(`INSERT INTO expert_slots(id,expert_id,school_id,service_id,scheduled_start_at,scheduled_end_at,capacity,status,version)
    VALUES
      ($1,$3,$4,'remote-acceptance',now()+interval '16 day',now()+interval '16 day 1 hour',1,'available',1),
      ($2,$3,$4,'remote-acceptance',now()+interval '17 day',now()+interval '17 day 1 hour',1,'available',1)
    ON CONFLICT(id) DO UPDATE SET scheduled_start_at=EXCLUDED.scheduled_start_at,scheduled_end_at=EXCLUDED.scheduled_end_at,status='available',version=expert_slots.version+1,updated_at=now()`, [ids.firstSlotId, ids.secondSlotId, ids.expertId, ids.schoolId]);

  await client.query(`INSERT INTO messages(receiver_user_id,title,content,category,message_type,business_id,business_route,child_id,task_id,action_label)
    SELECT $1,'远程验收报告','仅供远程业务路由验收。','system','report',$2,'report',$3,$4,'查看报告'
    WHERE NOT EXISTS(SELECT 1 FROM messages WHERE receiver_user_id=$1 AND business_route='report' AND business_id=$2)`, [ids.parentUserId, ids.reportId, ids.studentId, ids.taskId]);

  await client.query('COMMIT');
  console.log(JSON.stringify({
    ready: true,
    scope,
    fixture: {
      schoolId: ids.schoolId,
      childId: ids.studentId,
      taskId: ids.taskId,
      studentId: ids.studentId,
      activityId: ids.activityId,
      expertId: ids.expertId,
      slotId: ids.firstSlotId,
      rescheduleSlotId: ids.secondSlotId,
      courseId: ids.courseId,
      lessonId: ids.lessonId
    },
    accounts: { parent: parentAccount.replace(/^(\d{3})\d{4}(\d{4})$/, '$1****$2'), teacher: teacherAccount.replace(/^(\d{3})\d{4}(\d{4})$/, '$1****$2') },
    note: 'Passwords are intentionally never printed. Store accounts and passwords in the release environment secret store.'
  }, null, 2));
} catch (error) {
  await client.query('ROLLBACK').catch(() => {});
  throw error;
} finally {
  client.release();
  await pool.end();
}
