import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { test, before, after } from 'node:test';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';
import { totpCode } from '../src/mfa.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const port = Number(process.env.TEST_PORT || 18080);
const base = `http://127.0.0.1:${port}`;
const databaseUrl = process.env.TEST_DATABASE_URL;
if (!databaseUrl) throw new Error('TEST_DATABASE_URL is required; integration tests must not run against a development database');

// A variable name is not an isolation boundary. Running this suite against the
// default public schema creates realistic-looking tasks and can silently pollute
// an operator's local demo database. CI sets a dedicated search_path and local
// runs must do the same.
async function assertIsolatedTestSchema() {
  const verificationPool = new Pool({ connectionString: databaseUrl });
  try {
    const result = await verificationPool.query('SELECT current_schema() AS schema');
    const schema = String(result.rows[0]?.schema || '');
    if (!schema || schema === 'public') throw new Error('TEST_DATABASE_URL must select a dedicated non-public PostgreSQL schema (for example via options=-csearch_path%3Dxiangshang_integration%2Cpublic)');
  } finally {
    await verificationPool.end();
  }
}
await assertIsolatedTestSchema();
let serverProcess;
let createdIntegrationTaskId = null;

async function request(pathname, options = {}) {
  const headers = new Headers(options.headers || {});
  const deviceId = headers.get('X-Device-Id');
  const deviceKey = headers.get('X-Device-Key');
  if (deviceId && deviceKey) {
    const timestamp = String(Date.now());
    const nonce = crypto.randomBytes(16).toString('hex');
    const bodyHash = crypto.createHash('sha256').update(options.body || '').digest('hex');
    const signature = crypto.createHmac('sha256', deviceKey).update(`${String(options.method || 'GET').toUpperCase()}\n${pathname}\n${timestamp}\n${nonce}\n${bodyHash}`).digest('hex');
    headers.delete('X-Device-Key');
    headers.set('X-Device-Timestamp', timestamp);
    headers.set('X-Device-Nonce', nonce);
    headers.set('X-Device-Body-Hash', bodyHash);
    headers.set('X-Device-Signature', signature);
  }
  const response = await fetch(`${base}${pathname}`, { ...options, headers });
  const raw = await response.text();
  let body = null;
  try { body = raw ? JSON.parse(raw) : null; } catch { body = raw; }
  return { response, body };
}

async function runCleanup() {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['scripts/cleanup.js'], {
      cwd: root,
      env: { ...process.env, DATABASE_URL: databaseUrl, NODE_ENV: 'test', CORS_ORIGIN: `http://127.0.0.1:${port}`, ALLOW_PUBLIC_REGISTRATION: 'false' },
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let output = '';
    let errors = '';
    child.stdout.on('data', (data) => { output += data; });
    child.stderr.on('data', (data) => { errors += data; });
    child.once('error', reject);
    child.once('exit', (code) => {
      if (code !== 0) return reject(new Error(`cleanup exited ${code}: ${errors}`));
      try { resolve(JSON.parse(output.trim().split('\n').at(-1))); } catch (error) { reject(new Error(`cleanup did not return JSON: ${output}\n${error.message}`)); }
    });
  });
}

async function waitForReportRefreshJob(sessionId, timeoutMs = 8_000) {
  const verificationPool = new Pool({ connectionString: databaseUrl });
  const deadline = Date.now() + timeoutMs;
  try {
    while (Date.now() < deadline) {
      const result = await verificationPool.query(`SELECT status,last_error AS "lastError" FROM job_queue
        WHERE job_type='report.refresh' AND payload->>'sessionId'=$1 ORDER BY created_at DESC LIMIT 1`, [sessionId]);
      const job = result.rows[0];
      if (job?.status === 'completed') return job;
      if (job?.status === 'failed') throw new Error(`report.refresh entered failed queue: ${job.lastError}`);
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    throw new Error(`timed out waiting for report.refresh job for session ${sessionId}`);
  } finally {
    await verificationPool.end();
  }
}

async function login(account, password) {
  const result = await request('/v1/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ account, password }) });
  assert.equal(result.response.status, 200, JSON.stringify(result.body));
  return result.body.data;
}

before(async () => {
  serverProcess = spawn(process.execPath, ['src/server.js'], {
    cwd: root,
    env: { ...process.env, DATABASE_URL: databaseUrl, PORT: String(port), NODE_ENV: 'test', CORS_ORIGIN: `http://127.0.0.1:${port}`, ALLOW_PUBLIC_REGISTRATION: 'false', METRICS_TOKEN: '', MFA_ENCRYPTION_KEY: 'integration-mfa-key-that-is-longer-than-thirty-two-characters', AUDIT_LOG_SIGNING_KEY: 'integration-audit-key-that-is-longer-than-thirty-two-characters', FIELD_DEVICE_SIGNED_REQUESTS_REQUIRED: 'true', FIELD_DEVICE_OFFLINE_AFTER_SECONDS: '1', FIELD_LIVENESS_RECONCILE_INTERVAL_SECONDS: '1', JOB_WORKER_CONCURRENCY: '3' },
    stdio: ['ignore', 'pipe', 'pipe']
  });
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    try {
      const result = await request('/readyz');
      if (result.response.status === 200) return;
    } catch { /* server is still starting */ }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error('backend did not become ready');
});

after(async () => {
  if (serverProcess) {
    serverProcess.kill('SIGTERM');
    await new Promise((resolve) => serverProcess.once('exit', resolve));
  }
  if (!createdIntegrationTaskId) return;
  const cleanupPool = new Pool({ connectionString: databaseUrl });
  try {
    // The task is created only to exercise idempotency and optimistic locking.
    // It has no value after the suite and PostgreSQL cascades its test scores,
    // queue entries and sessions through the task foreign keys.
    await cleanupPool.query('DELETE FROM assessment_tasks WHERE id=$1', [createdIntegrationTaskId]);
  } finally {
    await cleanupPool.end();
  }
});

test('auth, scope, idempotency and file guardrails', async () => {
  const live = await request('/livez');
  assert.equal(live.response.status, 200);
  assert.equal(live.body.data.status, 'alive');
  const ready = await request('/readyz');
  assert.equal(ready.response.status, 200);
  assert.equal(ready.body.data.migration.healthy, true);
  assert.equal(ready.body.data.migration.missing.length, 0);
  assert.equal(ready.body.data.worker.mode, 'embedded');
  assert.equal(ready.body.data.worker.healthy, true);
  assert.ok(live.response.headers.get('x-request-id'));
  assert.equal(live.response.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(live.response.headers.get('x-frame-options'), 'DENY');
  assert.equal(live.response.headers.get('cross-origin-opener-policy'), 'same-origin');
  assert.match(live.response.headers.get('permissions-policy') || '', /camera=\(self\)/);
  const metrics = await request('/metrics');
  assert.equal(metrics.response.status, 200);
  assert.match(metrics.response.headers.get('content-type') || '', /text\/plain/);
  assert.match(String(metrics.body), /xiangshang_worker_healthy\{mode="embedded"\} 1/);
  assert.match(String(metrics.body), /xiangshang_job_queue_jobs\{status="failed"\} \d+/);
  assert.match(String(metrics.body), /xiangshang_backup_healthy\{enabled="false"\} 1/);
  assert.match(String(metrics.body), /xiangshang_database_schema_healthy 1/);

  const admin = await login('13800000000', process.env.SEED_PASSWORD || 'ChangeMe123!');
  assert.notEqual(admin.accessToken, admin.refreshToken);
  const cookieLogin = await request('/v1/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ account: '13800000000', password: process.env.SEED_PASSWORD || 'ChangeMe123!' }) });
  const loginCookie = cookieLogin.response.headers.get('set-cookie');
  assert.match(loginCookie || '', /HttpOnly/);
  const cookieRefresh = await request('/v1/auth/refresh', { method: 'POST', headers: { cookie: String(loginCookie).split(';')[0] } });
  assert.equal(cookieRefresh.response.status, 200, JSON.stringify(cookieRefresh.body));
  const me = await request('/v1/me', { headers: { Authorization: `Bearer ${admin.accessToken}` } });
  assert.equal(me.response.status, 200);
  const sessions = await request('/v1/me/sessions', { headers: { Authorization: `Bearer ${admin.accessToken}` } });
  assert.equal(sessions.response.status, 200);
  const auditLogs = await request('/v1/admin/audit-logs?schoolId=school-1&paged=1&page=1&pageSize=20', { headers: { Authorization: `Bearer ${admin.accessToken}` } });
  assert.equal(auditLogs.response.status, 200);

  const rotated = await request('/v1/auth/refresh', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ refreshToken: admin.refreshToken }) });
  assert.equal(rotated.response.status, 200, JSON.stringify(rotated.body));
  const oldAccess = await request('/v1/me', { headers: { Authorization: `Bearer ${admin.accessToken}` } });
  assert.equal(oldAccess.response.status, 401);

  const accounts = await request('/v1/admin/accounts?schoolId=school-1&paged=1&page=1&pageSize=20', { headers: { Authorization: `Bearer ${rotated.body.data.accessToken}` } });
  assert.equal(accounts.response.status, 200);
  assert.ok(accounts.body.data.items.every((item) => !('phone' in item) && item.phoneMasked));

  const teacher = await login('13800000001', 'ChangeMe123!');
  const teacherDashboard = await request('/v1/schools/school-1/dashboard?studentPage=1&studentPageSize=100', { headers: { Authorization: `Bearer ${teacher.accessToken}` } });
  assert.equal(teacherDashboard.response.status, 200, JSON.stringify(teacherDashboard.body));
  assert.equal(teacherDashboard.body.data.studentPage, 1);
  assert.equal(teacherDashboard.body.data.studentPageSize, 100);
  assert.equal(typeof teacherDashboard.body.data.studentTotal, 'number');
  assert.ok(teacherDashboard.body.data.students.every((item) => item.className === '三年级2班'));
  assert.ok(teacherDashboard.body.data.classes.every((item) => item.id === 'class-3'));
  assert.ok(teacherDashboard.body.data.grades.every((item) => item.id === 'grade-3'));
  const teacherGradeStats = await request('/v1/schools/school-1/grade-stats', { headers: { Authorization: `Bearer ${teacher.accessToken}` } });
  assert.equal(teacherGradeStats.response.status, 200, JSON.stringify(teacherGradeStats.body));
  assert.ok(teacherGradeStats.body.data.every((item) => item.id === 'grade-3'));
  const teacherClassStats = await request('/v1/schools/school-1/class-stats', { headers: { Authorization: `Bearer ${teacher.accessToken}` } });
  assert.equal(teacherClassStats.response.status, 200, JSON.stringify(teacherClassStats.body));
  assert.ok(teacherClassStats.body.data.every((item) => item.id === 'class-3'));
  const teacherSchoolWideTask = await request('/v1/admin/tasks', { method: 'POST', headers: { Authorization: `Bearer ${teacher.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `teacher-schoolwide-${Date.now()}` }, body: JSON.stringify({ schoolId: 'school-1', title: '教师不可创建全校任务', testDate: '2027-01-03', items: ['run'] }) });
  assert.equal(teacherSchoolWideTask.response.status, 403, JSON.stringify(teacherSchoolWideTask.body));
  const teacherSchoolNotice = await request('/v1/admin/notifications/campaigns', { method: 'POST', headers: { Authorization: `Bearer ${teacher.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `teacher-school-notice-${Date.now()}` }, body: JSON.stringify({ schoolId: 'school-1', title: '班级测评提醒', content: '请按班级安排完成测评。', audienceType: 'school' }) });
  assert.equal(teacherSchoolNotice.response.status, 403, JSON.stringify(teacherSchoolNotice.body));
  const teacherOwnClassNotice = await request('/v1/admin/notifications/campaigns', { method: 'POST', headers: { Authorization: `Bearer ${teacher.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `teacher-class-notice-${Date.now()}` }, body: JSON.stringify({ schoolId: 'school-1', title: '本班测评提醒', content: '请按班级安排完成测评。', audienceType: 'class', classId: 'class-3' }) });
  assert.equal(teacherOwnClassNotice.response.status, 201, JSON.stringify(teacherOwnClassNotice.body));
  const teacherOtherClassNotice = await request('/v1/admin/notifications/campaigns', { method: 'POST', headers: { Authorization: `Bearer ${teacher.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `teacher-other-class-notice-${Date.now()}` }, body: JSON.stringify({ schoolId: 'school-1', title: '越权班级提醒', content: '不应发送。', audienceType: 'class', classId: 'class-1' }) });
  assert.equal(teacherOtherClassNotice.response.status, 403, JSON.stringify(teacherOtherClassNotice.body));
  const ownClass = await request('/v1/schools/school-1/students?classId=class-3&paged=1&page=1&pageSize=20', { headers: { Authorization: `Bearer ${teacher.accessToken}` } });
  const otherClass = await request('/v1/schools/school-1/students?classId=class-1&paged=1&page=1&pageSize=20', { headers: { Authorization: `Bearer ${teacher.accessToken}` } });
  assert.equal(ownClass.response.status, 200);
  assert.equal(otherClass.response.status, 200);
  assert.equal(otherClass.body.data.total, 0);

  const isolatedClass = await request('/v1/admin/classes', { method: 'POST', headers: { Authorization: `Bearer ${rotated.body.data.accessToken}`, 'content-type': 'application/json' }, body: JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', name: `隔离测试班-${Date.now()}`, teacherId: 'user-teacher' }) });
  assert.equal(isolatedClass.response.status, 201, JSON.stringify(isolatedClass.body));
  const auditIntegrity = await request('/v1/admin/audit-integrity?schoolId=school-1', { headers: { Authorization: `Bearer ${rotated.body.data.accessToken}` } });
  assert.equal(auditIntegrity.response.status, 200, JSON.stringify(auditIntegrity.body));
  assert.equal(auditIntegrity.body.data.valid, true, JSON.stringify(auditIntegrity.body));
  assert.ok(auditIntegrity.body.data.checked >= 1, JSON.stringify(auditIntegrity.body));
  const isolatedStudent = await request('/v1/admin/students', { method: 'POST', headers: { Authorization: `Bearer ${rotated.body.data.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `student-${Date.now()}` }, body: JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', classId: isolatedClass.body.data.id, name: `隔离学生-${Date.now()}` }) });
  assert.equal(isolatedStudent.response.status, 201, JSON.stringify(isolatedStudent.body));
  const isolatedTask = await request('/v1/admin/tasks', { method: 'POST', headers: { Authorization: `Bearer ${rotated.body.data.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `isolated-task-${Date.now()}` }, body: JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', classId: isolatedClass.body.data.id, title: `隔离任务-${Date.now()}`, testDate: '2027-01-02', items: ['run'] }) });
  assert.equal(isolatedTask.response.status, 201, JSON.stringify(isolatedTask.body));
  const crossScopeStatus = await request(`/v1/tasks/${isolatedTask.body.data.id}/students/${isolatedStudent.body.data.id}/status`, { method: 'PATCH', headers: { Authorization: `Bearer ${teacher.accessToken}`, 'content-type': 'application/json' }, body: JSON.stringify({ status: '已签到' }) });
  assert.equal(crossScopeStatus.response.status, 403);

  // These writes bypass HTTP on purpose: the database must reject a faulty
  // future import/worker even if an application-layer scope check is missed.
  const isolationPool = new Pool({ connectionString: databaseUrl });
  const isolationSuffix = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const foreignSchoolId = `school-isolation-${isolationSuffix}`;
  const foreignGradeId = `grade-isolation-${isolationSuffix}`;
  const foreignClassId = `class-isolation-${isolationSuffix}`;
  const foreignStudentId = `student-isolation-${isolationSuffix}`;
  try {
    await isolationPool.query('INSERT INTO schools(id,name) VALUES($1,$2)', [foreignSchoolId, '跨校隔离验收学校']);
    await isolationPool.query('INSERT INTO grades(id,school_id,name) VALUES($1,$2,$3)', [foreignGradeId, foreignSchoolId, '验收年级']);
    await isolationPool.query('INSERT INTO classes(id,school_id,grade_id,name) VALUES($1,$2,$3,$4)', [foreignClassId, foreignSchoolId, foreignGradeId, '验收班级']);
    await isolationPool.query('INSERT INTO students(id,school_id,grade_id,class_id,name) VALUES($1,$2,$3,$4,$5)', [foreignStudentId, foreignSchoolId, foreignGradeId, foreignClassId, '跨校学生']);
    await assert.rejects(
      isolationPool.query('INSERT INTO task_students(task_id,student_id) VALUES($1,$2)', [isolatedTask.body.data.id, foreignStudentId]),
      { code: '23514' }
    );
    await assert.rejects(
      isolationPool.query("INSERT INTO assessment_scores(task_id,student_id,item_code,score,confidence) VALUES($1,$2,'run',1,0)", [isolatedTask.body.data.id, foreignStudentId]),
      { code: '23514' }
    );
    await assert.rejects(
      isolationPool.query('INSERT INTO test_queue_entries(school_id,task_id,student_id,queue_order) VALUES($1,$2,$3,999)', ['school-1', isolatedTask.body.data.id, foreignStudentId]),
      { code: '23503' }
    );
  } finally { await isolationPool.end(); }

  const issuedBinding = await request('/v1/admin/students/student-1/binding-code', { method: 'POST', headers: { Authorization: `Bearer ${rotated.body.data.accessToken}`, 'content-type': 'application/json' }, body: '{}' });
  assert.equal(issuedBinding.response.status, 201, JSON.stringify(issuedBinding.body));
  const parent = await login('13800000002', 'ChangeMe123!');
  const bound = await request(`/v1/students/student-1/bind?code=${encodeURIComponent(issuedBinding.body.data.bindingCode)}`, { method: 'POST', headers: { Authorization: `Bearer ${parent.accessToken}` } });
  assert.equal(bound.response.status, 201, JSON.stringify(bound.body));
  const reusedBinding = await request(`/v1/students/student-1/bind?code=${encodeURIComponent(issuedBinding.body.data.bindingCode)}`, { method: 'POST', headers: { Authorization: `Bearer ${parent.accessToken}` } });
  assert.equal(reusedBinding.response.status, 400);

  const cleanSnapshots = ['standingBack', 'forwardBend', 'seatedPosture', 'gaitVideo'].map((captureTask) => ({
    captureTask,
    sampleCount: 18,
    confidence: 0.82,
    metrics: {
      shoulderHeightDifferenceCm: 0.2,
      pelvicHeightDifferenceCm: 0.2,
      spinalMidlineDeviationCm: 0.2,
      thoracicRoundingDegrees: 10,
      forwardHeadAngleDegrees: 5,
      gaitShoulderSwingDifferenceCm: 0.2,
      gaitPelvicSwingDifferenceCm: 0.2,
      gaitTrunkSwayCm: 0.2
    }
  }));
  const bodyAssessment = await request('/v1/students/student-1/body-assessments', {
    method: 'POST',
    headers: { Authorization: `Bearer ${parent.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `body-${Date.now()}` },
    body: JSON.stringify({ heightCm: 135, weightKg: 32, overallLevel: 'red', data: { postureReport: { overallLevel: 'red' } }, snapshots: cleanSnapshots })
  });
  assert.equal(bodyAssessment.response.status, 201, JSON.stringify(bodyAssessment.body));
  assert.equal(bodyAssessment.body.data.overallLevel, 'green');
  assert.equal(bodyAssessment.body.data.bmiAlgorithmVersion, 'UY-IMCA-BMI-1.2');
  assert.equal(bodyAssessment.body.data.heightAlgorithmVersion, 'UY-IMCA-HEIGHT-1.0');
  assert.equal(bodyAssessment.body.data.modelRegistryVersion, 'UY-MODELS-1.0');
  assert.equal(bodyAssessment.body.data.postureReport.overallLevel, 'green');
  assert.equal(bodyAssessment.body.data.postureReport.rulesSourceVersion, 'UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20');
  const latestBody = await request('/v1/students/student-1/body-assessments/latest', { headers: { Authorization: `Bearer ${parent.accessToken}` } });
  assert.equal(latestBody.response.status, 200, JSON.stringify(latestBody.body));
  assert.equal(latestBody.body.data.overallLevel, 'green');
  assert.equal(latestBody.body.data.bmiAlgorithmVersion, 'UY-IMCA-BMI-1.2');
  assert.equal(latestBody.body.data.heightAlgorithmVersion, 'UY-IMCA-HEIGHT-1.0');
  assert.equal(latestBody.body.data.modelRegistryVersion, 'UY-MODELS-1.0');
  assert.equal(latestBody.body.data.postureReport.algorithm, 'UY-IMCA-CV-1.3');
  assert.equal(latestBody.body.data.postureReport.rulesSourceVersion, 'UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20');

  const refreshed = await request(`/v1/students/${isolatedStudent.body.data.id}/report/refresh`, { method: 'POST', headers: { Authorization: `Bearer ${rotated.body.data.accessToken}` } });
  assert.equal(refreshed.response.status, 200, JSON.stringify(refreshed.body));
  const reports = await request('/v1/reports?schoolId=school-1&paged=1&page=1&pageSize=100', { headers: { Authorization: `Bearer ${rotated.body.data.accessToken}` } });
  const isolatedReport = reports.body.data.items.find((item) => item.studentId === isolatedStudent.body.data.id);
  assert.equal(isolatedReport.status, 'draft');
  const teacherReports = await request('/v1/reports?schoolId=school-1&paged=1&page=1&pageSize=100', { headers: { Authorization: `Bearer ${teacher.accessToken}` } });
  assert.equal(teacherReports.response.status, 200, JSON.stringify(teacherReports.body));
  assert.ok(teacherReports.body.data.items.every((item) => item.className === '三年级2班'));
  assert.ok(!teacherReports.body.data.items.some((item) => item.id === isolatedReport.id));
  const teacherPublishOtherClass = await request(`/v1/reports/${isolatedReport.id}/publish`, { method: 'POST', headers: { Authorization: `Bearer ${teacher.accessToken}` } });
  assert.equal(teacherPublishOtherClass.response.status, 403, JSON.stringify(teacherPublishOtherClass.body));

  const parentDashboard = await request('/v1/schools/school-1/dashboard?studentPage=1&studentPageSize=100', { headers: { Authorization: `Bearer ${parent.accessToken}` } });
  assert.equal(parentDashboard.response.status, 200, JSON.stringify(parentDashboard.body));
  assert.ok(parentDashboard.body.data.students.every((item) => ['student-1', 'student-2'].includes(item.id)));
  assert.ok(parentDashboard.body.data.classes.every((item) => item.id === 'class-3'));
  assert.ok(parentDashboard.body.data.tasks.every((item) => item.id !== isolatedTask.body.data.id));
  const parentTasks = await request('/v1/schools/school-1/tasks?paged=1&page=1&pageSize=100', { headers: { Authorization: `Bearer ${parent.accessToken}` } });
  assert.equal(parentTasks.response.status, 200, JSON.stringify(parentTasks.body));
  assert.ok(parentTasks.body.data.items.every((item) => item.id !== isolatedTask.body.data.id));
  const visibleTaskId = parentTasks.body.data.items[0]?.id;
  if (visibleTaskId) {
    const parentTaskStudents = await request(`/v1/tasks/${visibleTaskId}/students`, { headers: { Authorization: `Bearer ${parent.accessToken}` } });
    assert.equal(parentTaskStudents.response.status, 200, JSON.stringify(parentTaskStudents.body));
    assert.ok(parentTaskStudents.body.data.every((item) => ['student-1', 'student-2'].includes(item.studentId)));
  }
  const parentReports = await request('/v1/reports?schoolId=school-1&paged=1&page=1&pageSize=100', { headers: { Authorization: `Bearer ${parent.accessToken}` } });
  assert.equal(parentReports.response.status, 200, JSON.stringify(parentReports.body));
  assert.ok(parentReports.body.data.items.every((item) => ['student-1', 'student-2'].includes(item.studentId)));
  assert.ok(parentReports.body.data.items.every((item) => item.status === 'published'));

  const exportRequest = await request(`/v1/admin/students/${isolatedStudent.body.data.id}/export`, { method: 'POST', headers: { Authorization: `Bearer ${rotated.body.data.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `export-${Date.now()}` }, body: '{}' });
  assert.equal(exportRequest.response.status, 202, JSON.stringify(exportRequest.body));
  let exportStatus;
  for (let attempt = 0; attempt < 20; attempt += 1) {
    exportStatus = await request(`/v1/admin/privacy-requests/${exportRequest.body.data.id}`, { headers: { Authorization: `Bearer ${rotated.body.data.accessToken}` } });
    if (exportStatus.body.data?.status === 'completed') break;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.equal(exportStatus.body.data.status, 'completed', JSON.stringify(exportStatus.body));
  assert.equal(exportStatus.body.data.data.student.id, isolatedStudent.body.data.id);
  assert.ok(Array.isArray(exportStatus.body.data.data.tasks));
  assert.ok(Array.isArray(exportStatus.body.data.data.scores));
  const concurrentJobsPool = new Pool({ connectionString: databaseUrl });
  const concurrentJobIds = [];
  try {
    for (let index = 0; index < 3; index += 1) {
      const job = await concurrentJobsPool.query(`INSERT INTO job_queue(job_type,payload,available_at)
        VALUES('privacy.export',$1,now()) RETURNING id`, [{ requestId: exportRequest.body.data.id, studentId: isolatedStudent.body.data.id, requestedBy: 'user-admin' }]);
      concurrentJobIds.push(job.rows[0].id);
    }
    let concurrentJobs;
    for (let attempt = 0; attempt < 30; attempt += 1) {
      concurrentJobs = await concurrentJobsPool.query(`SELECT id,status,attempts FROM job_queue WHERE id=ANY($1::text[]) ORDER BY id`, [concurrentJobIds]);
      if (concurrentJobs.rows.length === 3 && concurrentJobs.rows.every((job) => job.status === 'completed')) break;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    assert.equal(concurrentJobs.rows.length, 3, JSON.stringify(concurrentJobs.rows));
    assert.ok(concurrentJobs.rows.every((job) => job.status === 'completed' && Number(job.attempts) === 1), JSON.stringify(concurrentJobs.rows));
  } finally { await concurrentJobsPool.end(); }
  const workerAudit = await request('/v1/admin/audit-logs?schoolId=school-1&action=privacy.export.completed&paged=1&page=1&pageSize=20', { headers: { Authorization: `Bearer ${rotated.body.data.accessToken}` } });
  assert.equal(workerAudit.response.status, 200, JSON.stringify(workerAudit.body));
  assert.ok(workerAudit.body.data.items.some((item) => item.resourceId === exportRequest.body.data.id), JSON.stringify(workerAudit.body));
  const postWorkerAuditIntegrity = await request('/v1/admin/audit-integrity?schoolId=school-1', { headers: { Authorization: `Bearer ${rotated.body.data.accessToken}` } });
  assert.equal(postWorkerAuditIntegrity.response.status, 200, JSON.stringify(postWorkerAuditIntegrity.body));
  assert.equal(postWorkerAuditIntegrity.body.data.valid, true, JSON.stringify(postWorkerAuditIntegrity.body));
  const anonymizeRequest = await request(`/v1/admin/students/${isolatedStudent.body.data.id}/anonymize`, { method: 'POST', headers: { Authorization: `Bearer ${rotated.body.data.accessToken}` } });
  assert.equal(anonymizeRequest.response.status, 201, JSON.stringify(anonymizeRequest.body));
  const anonymizeApproval = await request(`/v1/admin/operations/privacy/${anonymizeRequest.body.data.id}/status`, { method: 'PATCH', headers: { Authorization: `Bearer ${rotated.body.data.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `anonymize-${Date.now()}` }, body: JSON.stringify({ status: 'completed' }) });
  assert.equal(anonymizeApproval.response.status, 200, JSON.stringify(anonymizeApproval.body));
  let anonymizedStatus;
  const anonymizePool = new Pool({ connectionString: databaseUrl });
  try {
    for (let attempt = 0; attempt < 30; attempt += 1) {
      const check = await anonymizePool.query('SELECT status,name FROM students WHERE id=$1', [isolatedStudent.body.data.id]);
      anonymizedStatus = check.rows[0];
      if (anonymizedStatus?.status === 'inactive') break;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  } finally { await anonymizePool.end(); }
  assert.deepEqual(anonymizedStatus, { status: 'inactive', name: '已删除学生' });
  const deadLetterPool = new Pool({ connectionString: databaseUrl });
  let deadLetterJob;
  try {
    deadLetterJob = await deadLetterPool.query(`INSERT INTO job_queue(job_type,payload,status,attempts,last_error,available_at) VALUES('privacy.export',$1,'failed',3,'simulated export outage',now()+interval '5 minutes') RETURNING id`, [{ requestId: 'simulated-failed-request' }]);
  } finally { await deadLetterPool.end(); }
  const failedJobs = await request('/v1/admin/jobs?status=failed&paged=1&page=1&pageSize=100', { headers: { Authorization: `Bearer ${rotated.body.data.accessToken}` } });
  assert.equal(failedJobs.response.status, 200, JSON.stringify(failedJobs.body));
  assert.ok(failedJobs.body.data.items.some((job) => job.id === deadLetterJob.rows[0].id), JSON.stringify(failedJobs.body));
  const retriedJob = await request(`/v1/admin/jobs/${deadLetterJob.rows[0].id}/retry`, { method: 'POST', headers: { Authorization: `Bearer ${rotated.body.data.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `retry-${Date.now()}` }, body: '{}' });
  assert.equal(retriedJob.response.status, 200, JSON.stringify(retriedJob.body));
  assert.equal(retriedJob.body.data.status, 'queued');
  const cleanupDeadLetterPool = new Pool({ connectionString: databaseUrl });
  try { await cleanupDeadLetterPool.query('DELETE FROM job_queue WHERE id=$1', [deadLetterJob.rows[0].id]); } finally { await cleanupDeadLetterPool.end(); }

  const invalidStudent = await request('/v1/admin/students', { method: 'POST', headers: { Authorization: `Bearer ${rotated.body.data.accessToken}`, 'content-type': 'application/json' }, body: JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', classId: 'class-1', name: 'invalid-scope' }) });
  assert.equal(invalidStudent.response.status, 400);
  assert.equal(invalidStudent.body.code, 'STUDENT_SCOPE_INVALID');

  const idempotencyKey = `integration-${Date.now()}`;
  const taskBody = JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', classId: 'class-3', title: `Integration ${Date.now()}`, testDate: '2027-01-01', items: ['run'] });
  const headers = { Authorization: `Bearer ${rotated.body.data.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': idempotencyKey };
  const [first, second] = await Promise.all([request('/v1/admin/tasks', { method: 'POST', headers, body: taskBody }), request('/v1/admin/tasks', { method: 'POST', headers, body: taskBody })]);
  assert.ok([first.response.status, second.response.status].includes(201));
  const replay = await request('/v1/admin/tasks', { method: 'POST', headers, body: taskBody });
  assert.equal(replay.response.status, 201, JSON.stringify(replay.body));
  const taskId = replay.body.data.id;
  createdIntegrationTaskId = taskId;
  const taskStudents = await request(`/v1/tasks/${encodeURIComponent(taskId)}/students`, { headers: { Authorization: headers.Authorization } });
  assert.equal(taskStudents.response.status, 200, JSON.stringify(taskStudents.body));
  if (taskStudents.body.data.length) {
    const initialVersion = taskStudents.body.data[0].version;
    const batch = await request('/v1/admin/tasks/batch-status', { method: 'POST', headers: { ...headers, 'Idempotency-Key': `${idempotencyKey}-batch` }, body: JSON.stringify({ updates: [{ taskId, studentId: taskStudents.body.data[0].studentId, status: '已签到', expectedVersion: initialVersion }] }) });
    assert.equal(batch.response.status, 201, JSON.stringify(batch.body));
    assert.equal(batch.body.data.updated, 1);
    const staleHeaders = { Authorization: headers.Authorization, 'content-type': 'application/json', 'Idempotency-Key': `${idempotencyKey}-stale` };
    const staleBody = JSON.stringify({ status: '候测', expectedVersion: initialVersion });
    const stale = await request(`/v1/tasks/${taskId}/students/${taskStudents.body.data[0].studentId}/status`, { method: 'PATCH', headers: staleHeaders, body: staleBody });
    assert.equal(stale.response.status, 409);
    assert.equal(stale.body.code, 'VERSION_CONFLICT');
    const staleRetry = await request(`/v1/tasks/${taskId}/students/${taskStudents.body.data[0].studentId}/status`, { method: 'PATCH', headers: staleHeaders, body: staleBody });
    assert.equal(staleRetry.response.status, 409);
    assert.equal(staleRetry.body.code, 'VERSION_CONFLICT');
  }
  const reused = await request('/v1/admin/tasks', { method: 'POST', headers, body: taskBody.replace('Integration ', 'Changed ') });
  assert.equal(reused.response.status, 409);
  assert.equal(reused.body.code, 'IDEMPOTENCY_KEY_REUSED');

  const badFile = await request('/v1/files/presign', { method: 'POST', headers: { Authorization: headers.Authorization, 'content-type': 'application/json' }, body: JSON.stringify({ fileName: 'malware.exe', contentType: 'application/x-msdownload', fileSize: 10 }) });
  assert.equal(badFile.response.status, 400);
  assert.equal(badFile.body.code, 'FILE_TYPE_NOT_ALLOWED');
  const fileKey = `file-${Date.now()}`;
  const presign = await request('/v1/files/presign', { method: 'POST', headers: { ...headers, 'Idempotency-Key': fileKey }, body: JSON.stringify({ fileName: 'note.txt', contentType: 'text/plain', fileSize: 5 }) });
  assert.equal(presign.response.status, 201, JSON.stringify(presign.body));
  const fileId = presign.body.data.id;
  const upload = await request(`/v1/files/${fileId}/content`, { method: 'PUT', headers: { Authorization: headers.Authorization, 'content-type': 'text/plain' }, body: 'hello' });
  assert.equal(upload.response.status, 200, JSON.stringify(upload.body));
  const download = await request(`/v1/files/${fileId}/content`, { headers: { Authorization: headers.Authorization } });
  assert.equal(download.response.status, 200);
  assert.equal(download.body, 'hello');
  const forbiddenDownload = await request(`/v1/files/${fileId}/content`, { headers: { Authorization: `Bearer ${teacher.accessToken}` } });
  assert.equal(forbiddenDownload.response.status, 404);
});

test('activity and expert appointment lifecycles persist versions and reject stale writes', async () => {
  const parent = await login('13800000002', 'ChangeMe123!');
  const suffix = `${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
  const activityId = `integration-activity-${suffix}`;
  const expertId = `integration-expert-${suffix}`;
  const firstSlotId = `integration-slot-a-${suffix}`;
  const secondSlotId = `integration-slot-b-${suffix}`;
  const verificationPool = new Pool({ connectionString: databaseUrl });
  try {
    await verificationPool.query(`INSERT INTO activities(id,school_id,title,description,starts_at,ends_at,capacity,registration_start_at,registration_end_at,status,created_by)
      VALUES($1,'school-1','集成验收活动','仅用于自动化验收',now()+interval '10 day',now()+interval '10 day 2 hour',2,now()-interval '1 day',now()+interval '5 day','published','user-admin')`, [activityId]);
    await verificationPool.query(`INSERT INTO experts(id,school_id,name,title,bio,status) VALUES($1,'school-1','验收专家','自动化验收','仅用于独立测试库','active')`, [expertId]);
    await verificationPool.query(`INSERT INTO expert_slots(id,expert_id,school_id,service_id,scheduled_start_at,scheduled_end_at,capacity,status)
      VALUES($1,$3,'school-1','integration-service',now()+interval '11 day',now()+interval '11 day 1 hour',1,'available'),
            ($2,$3,'school-1','integration-service',now()+interval '12 day',now()+interval '12 day 1 hour',1,'available')`, [firstSlotId, secondSlotId, expertId]);

    const createRegistration = await request(`/v1/activities/${activityId}/registrations`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${parent.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `activity-create-${suffix}` },
      body: JSON.stringify({ childId: 'student-1', contactName: '验收联系人', phone: '13900000000' })
    });
    assert.equal(createRegistration.response.status, 201, JSON.stringify(createRegistration.body));
    const registration = createRegistration.body.data;
    const editRegistration = await request(`/v1/activities/${activityId}/registrations/${registration.registrationId}`, {
      method: 'PUT',
      headers: { Authorization: `Bearer ${parent.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `activity-edit-${suffix}` },
      body: JSON.stringify({ childId: 'student-1', contactName: '验收联系人', phone: '13900000000', expectedVersion: registration.version })
    });
    assert.equal(editRegistration.response.status, 200, JSON.stringify(editRegistration.body));
    assert.ok(editRegistration.body.data.version > registration.version);
    const staleRegistration = await request(`/v1/activities/${activityId}/registrations/${registration.registrationId}`, {
      method: 'PUT',
      headers: { Authorization: `Bearer ${parent.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `activity-stale-${suffix}` },
      body: JSON.stringify({ childId: 'student-1', contactName: '验收联系人', phone: '13900000000', expectedVersion: registration.version })
    });
    assert.equal(staleRegistration.response.status, 409, JSON.stringify(staleRegistration.body));
    assert.equal(staleRegistration.body.code, 'VERSION_CONFLICT');
    const cancelRegistration = await request(`/v1/activities/${activityId}/registrations/${registration.registrationId}/cancel`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${parent.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `activity-cancel-${suffix}` },
      body: JSON.stringify({ expectedVersion: editRegistration.body.data.version })
    });
    assert.equal(cancelRegistration.response.status, 200, JSON.stringify(cancelRegistration.body));
    assert.equal(cancelRegistration.body.data.status, 'cancelled');

    const createAppointment = await request('/v1/expert-appointments', {
      method: 'POST',
      headers: { Authorization: `Bearer ${parent.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `appointment-create-${suffix}` },
      body: JSON.stringify({ childId: 'student-1', expertId, slotId: firstSlotId, note: '自动化验收' })
    });
    assert.equal(createAppointment.response.status, 201, JSON.stringify(createAppointment.body));
    const appointment = createAppointment.body.data;
    const reschedule = await request(`/v1/expert-appointments/${appointment.appointmentId}/reschedule`, {
      method: 'PUT',
      headers: { Authorization: `Bearer ${parent.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `appointment-reschedule-${suffix}` },
      body: JSON.stringify({ slotId: secondSlotId, expectedVersion: appointment.version })
    });
    assert.equal(reschedule.response.status, 200, JSON.stringify(reschedule.body));
    assert.ok(reschedule.body.data.version > appointment.version);
    const staleAppointment = await request(`/v1/expert-appointments/${appointment.appointmentId}/reschedule`, {
      method: 'PUT',
      headers: { Authorization: `Bearer ${parent.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `appointment-stale-${suffix}` },
      body: JSON.stringify({ slotId: firstSlotId, expectedVersion: appointment.version })
    });
    assert.equal(staleAppointment.response.status, 409, JSON.stringify(staleAppointment.body));
    assert.equal(staleAppointment.body.code, 'VERSION_CONFLICT');
    const cancelAppointment = await request(`/v1/expert-appointments/${appointment.appointmentId}/cancel`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${parent.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `appointment-cancel-${suffix}` },
      body: JSON.stringify({ expectedVersion: reschedule.body.data.version })
    });
    assert.equal(cancelAppointment.response.status, 200, JSON.stringify(cancelAppointment.body));
    assert.equal(cancelAppointment.body.data.status, 'cancelled');
  } finally {
    await verificationPool.query('DELETE FROM activity_registrations WHERE activity_id=$1', [activityId]).catch(() => {});
    await verificationPool.query('DELETE FROM expert_appointments WHERE expert_id=$1 OR slot_id=ANY($2::text[])', [expertId, [firstSlotId, secondSlotId]]).catch(() => {});
    await verificationPool.query('DELETE FROM activities WHERE id=$1', [activityId]).catch(() => {});
    await verificationPool.query('DELETE FROM experts WHERE id=$1', [expertId]).catch(() => {});
    await verificationPool.end();
  }
});

test('field device syncs queue, session, evidence contract and commands idempotently', async () => {
  const admin = await login('13800000000', process.env.SEED_PASSWORD || 'ChangeMe123!');
  const authHeaders = { Authorization: `Bearer ${admin.accessToken}`, 'content-type': 'application/json' };
  const suffix = Date.now().toString(36);
  // Give each run a separate date-scoped standard so local reruns can coexist
  // while still exercising the active-scope uniqueness constraint.
  const standardEffectiveDate = new Date(Date.UTC(2027, 0, 1) + (parseInt(suffix, 36) % 9000) * 86_400_000).toISOString().slice(0, 10);
  const station = await request('/v1/admin/test-stations', {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ schoolId: 'school-1', stationCode: `IT-${suffix}`, name: '场地端集成验收点', itemCode: '连续双脚障碍跳', queueCapacity: 30 })
  });
  assert.equal(station.response.status, 201, JSON.stringify(station.body));
  const invalidCalibration = await request(`/v1/admin/test-stations/${encodeURIComponent(station.body.data.id)}/calibrations`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ version: `INVALID-CAL-${suffix}`, checksumSha256: 'not-a-sha256', config: {} })
  });
  assert.equal(invalidCalibration.response.status, 400, JSON.stringify(invalidCalibration.body));
  const calibration = await request(`/v1/admin/test-stations/${encodeURIComponent(station.body.data.id)}/calibrations`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ version: `IT-CAL-${suffix}`, checksumSha256: 'a'.repeat(64), config: { cameraHeightCm: 130, captureZone: '2m x 3m' } })
  });
  assert.equal(calibration.response.status, 201, JSON.stringify(calibration.body));
  const device = await request('/v1/admin/test-devices', {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ schoolId: 'school-1', stationId: station.body.data.id, deviceCode: `EDGE-${suffix}`, name: '场地端验收主机', deviceType: 'edge_host', softwareVersion: 'it/1.0', capabilities: { offline: true } })
  });
  assert.equal(device.response.status, 201, JSON.stringify(device.body));
  assert.ok(device.body.data.deviceKey);
  assert.ok(Date.parse(device.body.data.apiKeyExpiresAt) > Date.now() + 80 * 86_400_000, JSON.stringify(device.body));
  const parallelStation = await request('/v1/admin/test-stations', {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ schoolId: 'school-1', stationCode: `IT-B-${suffix}`, name: '场地端并行验收点', itemCode: '连续双脚障碍跳', queueCapacity: 30 })
  });
  assert.equal(parallelStation.response.status, 201, JSON.stringify(parallelStation.body));
  const parallelCalibration = await request(`/v1/admin/test-stations/${encodeURIComponent(parallelStation.body.data.id)}/calibrations`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ version: `IT-B-CAL-${suffix}`, checksumSha256: 'b'.repeat(64), config: { cameraHeightCm: 130, captureZone: '2m x 3m' } })
  });
  assert.equal(parallelCalibration.response.status, 201, JSON.stringify(parallelCalibration.body));
  const parallelDevice = await request('/v1/admin/test-devices', {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ schoolId: 'school-1', stationId: parallelStation.body.data.id, deviceCode: `EDGE-B-${suffix}`, name: '场地端并行主机', deviceType: 'edge_host', softwareVersion: 'it/1.0', capabilities: { offline: true } })
  });
  assert.equal(parallelDevice.response.status, 201, JSON.stringify(parallelDevice.body));
  const teacher = await login('13800000001', 'ChangeMe123!');
  const teacherDeviceCommand = await request('/v1/admin/device-commands', {
    method: 'POST', headers: { Authorization: `Bearer ${teacher.accessToken}`, 'content-type': 'application/json' },
    body: JSON.stringify({ deviceId: device.body.data.id, commandType: 'stop' })
  });
  assert.equal(teacherDeviceCommand.response.status, 403, JSON.stringify(teacherDeviceCommand.body));
  const deviceHeaders = { 'X-Device-Id': device.body.data.id, 'X-Device-Key': device.body.data.deviceKey, 'content-type': 'application/json' };
  const parallelDeviceHeaders = { 'X-Device-Id': parallelDevice.body.data.id, 'X-Device-Key': parallelDevice.body.data.deviceKey, 'content-type': 'application/json' };
  const legacyRequest = await fetch(`${base}/v1/field/heartbeat`, { method: 'POST', headers: deviceHeaders, body: '{}' });
  assert.equal(legacyRequest.status, 401, '生产模式拒绝在每个请求中传递原始设备密钥');
  const signedTimestamp = String(Date.now());
  const signedNonce = crypto.randomBytes(16).toString('hex');
  const signedBodyHash = crypto.createHash('sha256').update('{}').digest('hex');
  const signedRequestHeaders = {
    'X-Device-Id': device.body.data.id,
    'X-Device-Timestamp': signedTimestamp,
    'X-Device-Nonce': signedNonce,
    'X-Device-Body-Hash': signedBodyHash,
    'X-Device-Signature': crypto.createHmac('sha256', device.body.data.deviceKey).update(`POST\n/v1/field/heartbeat\n${signedTimestamp}\n${signedNonce}\n${signedBodyHash}`).digest('hex'),
    'content-type': 'application/json'
  };
  const signedRequest = await fetch(`${base}/v1/field/heartbeat`, { method: 'POST', headers: signedRequestHeaders, body: '{}' });
  assert.equal(signedRequest.status, 200);
  const replayedSignedRequest = await fetch(`${base}/v1/field/heartbeat`, { method: 'POST', headers: signedRequestHeaders, body: '{}' });
  assert.equal(replayedSignedRequest.status, 401, '相同随机数的签名请求不能重放');
  const healthyFieldHealth = (calibrationVersion = null, checksumSha256 = null) => ({
    schemaVersion: 'field-health/v1',
    selfTest: { passed: true, completedAt: new Date().toISOString() },
    capture: { adapterReady: true, adapterName: 'integration-visual-adapter', depthCameraCount: 2, rgbCameraCount: 1, gpuReady: true, frameSyncOffsetMs: 8.2 },
    storage: { freeMb: 10_240 },
    calibration: { passed: true, version: calibrationVersion, checksumSha256, errorCm: 2.5 }
  });
  const fieldTask = await request('/v1/admin/tasks', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `field-task-${suffix}` },
    body: JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', classId: 'class-3', title: `场地端验收任务-${suffix}`, testDate: '2055-03-03', items: ['连续双脚障碍跳'] })
  });
  assert.equal(fieldTask.response.status, 201, JSON.stringify(fieldTask.body));
  // An online heartbeat alone is not enough for formal scoring: the central
  // gate must reject an edge host until it attests the complete visual
  // preflight contract.
  const incompleteHeartbeat = await request('/v1/field/heartbeat', { method: 'POST', headers: deviceHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: {} }) });
  assert.equal(incompleteHeartbeat.response.status, 200, JSON.stringify(incompleteHeartbeat.body));
  const incompleteBootstrap = await request(`/v1/field/bootstrap?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: deviceHeaders });
  assert.equal(incompleteBootstrap.response.status, 200, JSON.stringify(incompleteBootstrap.body));
  assert.equal(incompleteBootstrap.body.data.readiness.ready, false, JSON.stringify(incompleteBootstrap.body));
  assert.ok(incompleteBootstrap.body.data.readiness.blockers.some((blocker) => blocker.includes('field-health/v1')), JSON.stringify(incompleteBootstrap.body));
  const unhealthySession = await request('/v1/field/sessions', {
    method: 'POST', headers: deviceHeaders,
    body: JSON.stringify({ clientSessionId: `unhealthy-${suffix}`, taskId: fieldTask.body.data.id, studentId: incompleteBootstrap.body.data.queue[0].studentId, startedAt: new Date().toISOString(), algorithmVersion: 'it/1.0' })
  });
  assert.equal(unhealthySession.response.status, 409, JSON.stringify(unhealthySession.body));
  assert.equal(unhealthySession.body.code, 'FIELD_STATION_NOT_READY');
  const uncalibratedStation = await request('/v1/admin/test-stations', {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ schoolId: 'school-1', stationCode: `IT-NOCAL-${suffix}`, name: '未标定拦截验收点', itemCode: '连续双脚障碍跳', queueCapacity: 10 })
  });
  assert.equal(uncalibratedStation.response.status, 201, JSON.stringify(uncalibratedStation.body));
  const uncalibratedDevice = await request('/v1/admin/test-devices', {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ schoolId: 'school-1', stationId: uncalibratedStation.body.data.id, deviceCode: `EDGE-NOCAL-${suffix}`, name: '未标定拦截主机', deviceType: 'edge_host', softwareVersion: 'it/1.0', capabilities: { offline: true } })
  });
  assert.equal(uncalibratedDevice.response.status, 201, JSON.stringify(uncalibratedDevice.body));
  const uncalibratedHeaders = { 'X-Device-Id': uncalibratedDevice.body.data.id, 'X-Device-Key': uncalibratedDevice.body.data.deviceKey, 'content-type': 'application/json' };
  await request('/v1/field/heartbeat', { method: 'POST', headers: uncalibratedHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth() }) });
  const blockedSession = await request('/v1/field/sessions', {
    method: 'POST', headers: uncalibratedHeaders,
    body: JSON.stringify({ clientSessionId: `uncalibrated-${suffix}`, taskId: fieldTask.body.data.id, studentId: 'student-1', startedAt: new Date().toISOString(), algorithmVersion: 'it/1.0' })
  });
  assert.equal(blockedSession.response.status, 409, JSON.stringify(blockedSession.body));
  assert.equal(blockedSession.body.code, 'FIELD_STATION_NOT_READY');
  // This isolated integration schema is intentionally reusable. Supersede any
  // prior school-wide grade standard before asserting the new effective
  // version, mirroring the production replacement workflow.
  const activeStandards = await request('/v1/admin/assessment-standards?schoolId=school-1&gradeId=grade-3&status=active', { headers: authHeaders });
  assert.equal(activeStandards.response.status, 200, JSON.stringify(activeStandards.body));
  for (const item of activeStandards.body.data.filter((standard) => !standard.region && standard.povertyArea == null)) {
    const archived = await request(`/v1/admin/assessment-standards/${encodeURIComponent(item.id)}/status`, {
      method: 'PATCH', headers: { ...authHeaders, 'Idempotency-Key': `archive-standard-${suffix}-${item.id}` }, body: JSON.stringify({ status: 'archived' })
    });
    assert.equal(archived.response.status, 200, JSON.stringify(archived.body));
  }
  const fieldStandard = await request('/v1/admin/assessment-standards', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `field-standard-${suffix}` },
    body: JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', standardVersion: `场地标准-${suffix}`, effectiveDate: standardEffectiveDate, status: 'active', ruleConfig: { itemCount: 7, lowConfidenceRequiresReview: true } })
  });
  assert.equal(fieldStandard.response.status, 201, JSON.stringify(fieldStandard.body));
  const duplicateFieldStandard = await request('/v1/admin/assessment-standards', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `field-standard-duplicate-${suffix}` },
    body: JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', standardVersion: `冲突标准-${suffix}`, effectiveDate: standardEffectiveDate, status: 'active', ruleConfig: { itemCount: 7 } })
  });
  assert.equal(duplicateFieldStandard.response.status, 409, JSON.stringify(duplicateFieldStandard.body));
  const heartbeat = await request('/v1/field/heartbeat', { method: 'POST', headers: deviceHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth(`IT-CAL-${suffix}`, 'a'.repeat(64)) }) });
  assert.equal(heartbeat.response.status, 200, JSON.stringify(heartbeat.body));
  const parallelHeartbeat = await request('/v1/field/heartbeat', { method: 'POST', headers: parallelDeviceHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth(`IT-B-CAL-${suffix}`, 'b'.repeat(64)) }) });
  assert.equal(parallelHeartbeat.response.status, 200, JSON.stringify(parallelHeartbeat.body));
  const dispatch = await request('/v1/admin/test-queues/rebalance', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `field-rebalance-${suffix}` }, body: JSON.stringify({ taskId: fieldTask.body.data.id })
  });
  assert.equal(dispatch.response.status, 200, JSON.stringify(dispatch.body));
  assert.equal(dispatch.body.data.eligibleStations.length, 2, JSON.stringify(dispatch.body));
  assert.ok(new Set(dispatch.body.data.assignments.map((item) => item.stationId)).size >= 2, JSON.stringify(dispatch.body));
  const deviceInventory = await request('/v1/admin/test-devices?schoolId=school-1', { headers: authHeaders });
  assert.equal(deviceInventory.response.status, 200, JSON.stringify(deviceInventory.body));
  assert.equal(deviceInventory.body.data.find((item) => item.id === device.body.data.id)?.signedRequestReady, true, JSON.stringify(deviceInventory.body));
  assert.equal(deviceInventory.body.data.find((item) => item.id === device.body.data.id)?.apiKeyStatus, 'valid');
  const bootstrap = await request(`/v1/field/bootstrap?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: deviceHeaders });
  assert.equal(bootstrap.response.status, 200, JSON.stringify(bootstrap.body));
  assert.ok(bootstrap.body.data.queue.length >= 1);
  assert.equal(bootstrap.body.data.readiness.ready, true, JSON.stringify(bootstrap.body));
  assert.equal(bootstrap.body.data.readiness.calibrationVersion, `IT-CAL-${suffix}`);
  assert.equal(bootstrap.body.data.readiness.hardware.depthCameraCount, 2);
  assert.equal(bootstrap.body.data.readiness.hardware.rgbCameraCount, 1);
  assert.equal(bootstrap.body.data.readiness.hardware.frameSyncOffsetMs, 8.2);
  assert.ok(bootstrap.body.data.standards.some((standard) => standard.standardVersion === `场地标准-${suffix}`), JSON.stringify(bootstrap.body));
  const parallelBootstrap = await request(`/v1/field/bootstrap?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: parallelDeviceHeaders });
  assert.equal(parallelBootstrap.response.status, 200, JSON.stringify(parallelBootstrap.body));
  assert.equal(parallelBootstrap.body.data.readiness.ready, true, JSON.stringify(parallelBootstrap.body));
  assert.ok(parallelBootstrap.body.data.queue.length >= 1, JSON.stringify(parallelBootstrap.body));
  const student = bootstrap.body.data.queue[0];
  const clientSessionId = `offline-session-${suffix}`;
  const scoreItems = ['连续双脚障碍跳', '侧向滑步', '倒退平衡', '接球-上手掷准', '手运球绕杆', '脚运球变向', '定点踢准'];
  const evidenceBytes = Buffer.from(`timeline=${clientSessionId}\nframeSyncOffsetMs=8.2\n`, 'utf8');
  const evidencePresign = await request('/v1/field/files/presign', {
    method: 'POST', headers: deviceHeaders,
    body: JSON.stringify({ fileName: `timeline-${suffix}.txt`, contentType: 'text/plain', fileSize: evidenceBytes.length })
  });
  assert.equal(evidencePresign.response.status, 201, JSON.stringify(evidencePresign.body));
  const evidenceUpload = await request(`/v1/field/files/${encodeURIComponent(evidencePresign.body.data.id)}/content`, {
    method: 'PUT', headers: { ...deviceHeaders, 'content-type': 'text/plain' }, body: evidenceBytes
  });
  assert.equal(evidenceUpload.response.status, 200, JSON.stringify(evidenceUpload.body));
  const duplicateEvidenceUpload = await request(`/v1/field/files/${encodeURIComponent(evidencePresign.body.data.id)}/content`, {
    method: 'PUT', headers: { ...deviceHeaders, 'content-type': 'text/plain' }, body: evidenceBytes
  });
  assert.equal(duplicateEvidenceUpload.response.status, 409, JSON.stringify(duplicateEvidenceUpload.body));
  const captureAction = { clientEventId: `action-${suffix}`, sequenceNo: 1, eventType: 'capture.started', happenedAt: new Date().toISOString(), payload: { framesPerSecond: 30 } };
  const batch = {
    clientBatchId: `batch-${suffix}`,
    events: [
      {
        clientEventId: `open-${suffix}`, eventType: 'session.open', happenedAt: new Date().toISOString(),
        payload: { clientSessionId, taskId: fieldTask.body.data.id, studentId: student.studentId, algorithmVersion: 'UY-IMCA-SCORE-1.3', summary: { source: 'integration-offline' } }
      },
      {
        clientEventId: `actions-${suffix}`, eventType: 'session.events', happenedAt: new Date().toISOString(),
        payload: { sessionId: clientSessionId, events: [captureAction] }
      },
      {
        clientEventId: `actions-replay-${suffix}`, eventType: 'session.events', happenedAt: new Date().toISOString(),
        payload: { sessionId: clientSessionId, events: [captureAction] }
      },
      {
        clientEventId: `complete-${suffix}`, eventType: 'session.complete', happenedAt: new Date().toISOString(),
        payload: { sessionId: clientSessionId, algorithmVersion: 'UY-IMCA-SCORE-1.3', endedAt: new Date().toISOString(), scores: scoreItems.map((item) => ({ item, score: 4, confidence: 0.91, reviewStatus: 'passed' })), evidence: [{ fileId: evidencePresign.body.data.id, evidenceType: 'timeline', checksumSha256: evidenceUpload.body.data.checksumSha256, metadata: { frameSyncOffsetMs: 8.2 } }], summary: { source: 'integration', frameCount: 300 } }
      }
    ]
  };
  const synced = await request('/v1/field/sync/batches', { method: 'POST', headers: deviceHeaders, body: JSON.stringify(batch) });
  assert.equal(synced.response.status, 200, JSON.stringify(synced.body));
  assert.equal(synced.body.data.accepted, 4);
  const replay = await request('/v1/field/sync/batches', { method: 'POST', headers: deviceHeaders, body: JSON.stringify(batch) });
  assert.equal(replay.response.status, 200, JSON.stringify(replay.body));
  assert.equal(replay.body.data.idempotent, true);
  const tamperedReplay = await request('/v1/field/sync/batches', {
    method: 'POST', headers: deviceHeaders,
    body: JSON.stringify({
      clientBatchId: `tampered-batch-${suffix}`,
      events: [{ ...batch.events[0], payload: { ...batch.events[0].payload, summary: { source: 'tampered-replay' } } }]
    })
  });
  assert.equal(tamperedReplay.response.status, 409, JSON.stringify(tamperedReplay.body));
  assert.equal(tamperedReplay.body.code, 'FIELD_EVENT_REPLAY_MISMATCH');
  const sessions = await request(`/v1/admin/test-sessions?schoolId=school-1&taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: authHeaders });
  const syncedSession = sessions.body.data.find((item) => item.clientSessionId === clientSessionId);
  assert.ok(syncedSession, JSON.stringify(sessions.body));
  const detail = await request(`/v1/admin/test-sessions/${syncedSession.id}`, { headers: authHeaders });
  assert.equal(detail.response.status, 200, JSON.stringify(detail.body));
  assert.equal(detail.body.data.status, 'completed');
  assert.equal(detail.body.data.standardVersion, `场地标准-${suffix}`);
  assert.equal(detail.body.data.standardSnapshot.standardVersion, `场地标准-${suffix}`);
  assert.equal(detail.body.data.events.length, 1);
  assert.equal(detail.body.data.scores.length, 7);
  assert.equal(detail.body.data.evidence.length, 1);
  assert.equal(detail.body.data.evidence[0].evidenceType, 'timeline');
  assert.equal(detail.body.data.evidence[0].purgedAt, null);
  assert.ok(Date.parse(detail.body.data.evidence[0].retentionUntil) > Date.now() + 1000 * 86_400_000, JSON.stringify(detail.body));
  await waitForReportRefreshJob(syncedSession.id);
  const reportRefreshPool = new Pool({ connectionString: databaseUrl });
  try {
    const generatedReport = await reportRefreshPool.query('SELECT status FROM diagnosis_reports WHERE student_id=$1 AND task_id=$2', [student.studentId, fieldTask.body.data.id]);
    assert.equal(generatedReport.rows[0]?.status, 'draft');
    const workerAudit = await reportRefreshPool.query(`SELECT 1 FROM audit_logs
      WHERE action='report.refresh' AND request_id LIKE 'worker:report-refresh:%' AND school_id='school-1' LIMIT 1`);
    assert.equal(workerAudit.rowCount, 1);
  } finally {
    await reportRefreshPool.end();
  }
  const retention = await request('/v1/admin/data-retention', { headers: authHeaders });
  assert.equal(retention.response.status, 200, JSON.stringify(retention.body));
  assert.equal(retention.body.data.fieldEvidence.derivedEvidenceRetentionDays, 1095);
  const cleanupPool = new Pool({ connectionString: databaseUrl });
  try {
    await cleanupPool.query(`UPDATE files SET retention_until=now()-interval '1 second' WHERE id=$1`, [evidencePresign.body.data.id]);
  } finally { await cleanupPool.end(); }
  const cleanupResult = await runCleanup();
  assert.ok(cleanupResult.removedFiles >= 1, JSON.stringify(cleanupResult));
  assert.ok(cleanupResult.purgedFieldEvidence >= 1, JSON.stringify(cleanupResult));
  const purgedDetail = await request(`/v1/admin/test-sessions/${syncedSession.id}`, { headers: authHeaders });
  assert.equal(purgedDetail.response.status, 200, JSON.stringify(purgedDetail.body));
  assert.equal(purgedDetail.body.data.evidence.length, 1);
  assert.equal(purgedDetail.body.data.evidence[0].fileId, null);
  assert.ok(purgedDetail.body.data.evidence[0].purgedAt, JSON.stringify(purgedDetail.body));
  assert.equal(purgedDetail.body.data.evidence[0].purgeReason, 'retention_expired');
  const manualContext = [
    ...bootstrap.body.data.queue.filter((entry) => entry.studentId !== student.studentId).map((entry) => ({ entry, headers: deviceHeaders })),
    ...parallelBootstrap.body.data.queue.filter((entry) => entry.studentId !== student.studentId).map((entry) => ({ entry, headers: parallelDeviceHeaders }))
  ][0];
  assert.ok(manualContext, '集成任务至少应包含两名候测学生，以验证人工兜底复核链路');
  const manualStudent = manualContext.entry;
  const manualClientSessionId = `manual-session-${suffix}`;
  const manualBatch = {
    clientBatchId: `manual-batch-${suffix}`,
    events: [
      {
        clientEventId: `manual-open-${suffix}`, eventType: 'session.open', happenedAt: new Date().toISOString(),
        payload: { clientSessionId: manualClientSessionId, taskId: fieldTask.body.data.id, studentId: manualStudent.studentId, algorithmVersion: 'field-client/0.1-manual-fallback', summary: { captureMode: 'manual-fallback' } }
      },
      {
        clientEventId: `manual-complete-${suffix}`, eventType: 'session.complete', happenedAt: new Date().toISOString(),
        payload: {
          sessionId: manualClientSessionId, algorithmVersion: 'field-client/0.1-manual-fallback', endedAt: new Date().toISOString(),
          scores: scoreItems.map((item) => ({ item, score: 3.5, confidence: 0, note: '现场人工录入，待复核' })),
          summary: { captureMode: 'manual-fallback', operatorConfirmed: true }
        }
      }
    ]
  };
  const manualSynced = await request('/v1/field/sync/batches', { method: 'POST', headers: manualContext.headers, body: JSON.stringify(manualBatch) });
  assert.equal(manualSynced.response.status, 200, JSON.stringify(manualSynced.body));
  assert.equal(manualSynced.body.data.accepted, 2);
  const manualSessions = await request(`/v1/admin/test-sessions?schoolId=school-1&taskId=${encodeURIComponent(fieldTask.body.data.id)}&status=needs_review`, { headers: authHeaders });
  const manualSession = manualSessions.body.data.find((item) => item.clientSessionId === manualClientSessionId);
  assert.ok(manualSession, JSON.stringify(manualSessions.body));
  const manualDetail = await request(`/v1/admin/test-sessions/${manualSession.id}`, { headers: authHeaders });
  assert.equal(manualDetail.response.status, 200, JSON.stringify(manualDetail.body));
  assert.equal(manualDetail.body.data.status, 'needs_review');
  assert.ok(manualDetail.body.data.scores.every((score) => score.reviewStatus === 'pendingReview'));
  const command = await request('/v1/admin/device-commands', { method: 'POST', headers: authHeaders, body: JSON.stringify({ deviceId: device.body.data.id, commandType: 'refresh_config', payload: { calibration: true } }) });
  assert.equal(command.response.status, 201, JSON.stringify(command.body));
  const commands = await request('/v1/field/commands', { headers: deviceHeaders });
  assert.equal(commands.response.status, 200, JSON.stringify(commands.body));
  assert.ok(commands.body.data.commands.some((item) => item.id === command.body.data.id));
  const acknowledged = await request(`/v1/field/commands/${command.body.data.id}/ack`, { method: 'POST', headers: deviceHeaders, body: '{}' });
  assert.equal(acknowledged.response.status, 200, JSON.stringify(acknowledged.body));
  const rotatedDevice = await request(`/v1/admin/test-devices/${device.body.data.id}/rotate-key`, { method: 'POST', headers: authHeaders, body: '{}' });
  assert.equal(rotatedDevice.response.status, 200, JSON.stringify(rotatedDevice.body));
  assert.ok(rotatedDevice.body.data.deviceKey);
  assert.ok(Date.parse(rotatedDevice.body.data.apiKeyExpiresAt) > Date.now() + 80 * 86_400_000, JSON.stringify(rotatedDevice.body));
  const revokedKeyHeartbeat = await request('/v1/field/heartbeat', { method: 'POST', headers: deviceHeaders, body: '{}' });
  assert.equal(revokedKeyHeartbeat.response.status, 401, JSON.stringify(revokedKeyHeartbeat.body));
  const rotatedHeaders = { ...deviceHeaders, 'X-Device-Key': rotatedDevice.body.data.deviceKey };
  const rotatedHeartbeat = await request('/v1/field/heartbeat', { method: 'POST', headers: rotatedHeaders, body: '{}' });
  assert.equal(rotatedHeartbeat.response.status, 200, JSON.stringify(rotatedHeartbeat.body));
  await new Promise((resolve) => setTimeout(resolve, 1200));
  let livenessDevices;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    livenessDevices = await request('/v1/admin/test-devices?schoolId=school-1', { headers: authHeaders });
    if (livenessDevices.body.data?.find((item) => item.id === device.body.data.id)?.status === 'offline') break;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  assert.equal(livenessDevices.response.status, 200, JSON.stringify(livenessDevices.body));
  assert.equal(livenessDevices.body.data.find((item) => item.id === device.body.data.id)?.status, 'offline', JSON.stringify(livenessDevices.body));
});

test('TOTP enrollment uses a short challenge, rejects replay and consumes recovery codes', async () => {
  const admin = await login('13800000000', process.env.SEED_PASSWORD || 'ChangeMe123!');
  const headers = { Authorization: `Bearer ${admin.accessToken}`, 'content-type': 'application/json' };
  const before = await request('/v1/me/mfa', { headers });
  assert.equal(before.response.status, 200, JSON.stringify(before.body));
  assert.equal(before.body.data.enabled, false);
  const setup = await request('/v1/me/mfa/totp/setup', { method: 'POST', headers, body: JSON.stringify({ currentPassword: process.env.SEED_PASSWORD || 'ChangeMe123!' }) });
  assert.equal(setup.response.status, 200, JSON.stringify(setup.body));
  const currentCounter = Math.floor(Date.now() / 30_000);
  const confirmed = await request('/v1/me/mfa/totp/confirm', { method: 'POST', headers, body: JSON.stringify({ code: totpCode(setup.body.data.secret, currentCounter) }) });
  assert.equal(confirmed.response.status, 200, JSON.stringify(confirmed.body));
  assert.equal(confirmed.body.data.recoveryCodes.length, 10);
  const passwordLogin = await request('/v1/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ account: '13800000000', password: process.env.SEED_PASSWORD || 'ChangeMe123!' }) });
  assert.equal(passwordLogin.response.status, 200, JSON.stringify(passwordLogin.body));
  assert.equal(passwordLogin.body.data.mfaRequired, true);
  const futureCode = totpCode(setup.body.data.secret, currentCounter + 1);
  const mfaLogin = await request('/v1/auth/mfa/totp', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ challengeToken: passwordLogin.body.data.challengeToken, code: futureCode }) });
  assert.equal(mfaLogin.response.status, 200, JSON.stringify(mfaLogin.body));
  const replayLogin = await request('/v1/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ account: '13800000000', password: process.env.SEED_PASSWORD || 'ChangeMe123!' }) });
  const replay = await request('/v1/auth/mfa/totp', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ challengeToken: replayLogin.body.data.challengeToken, code: futureCode }) });
  assert.equal(replay.response.status, 401, JSON.stringify(replay.body));
  assert.equal(replay.body.code, 'MFA_CODE_INVALID');
  const disable = await request('/v1/me/mfa/totp/disable', { method: 'POST', headers, body: JSON.stringify({ currentPassword: process.env.SEED_PASSWORD || 'ChangeMe123!', code: confirmed.body.data.recoveryCodes[0] }) });
  assert.equal(disable.response.status, 200, JSON.stringify(disable.body));
  const enrollmentChallengeToken = `enrollment-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const enrollmentPool = new Pool({ connectionString: databaseUrl });
  try {
    await enrollmentPool.query(`INSERT INTO auth_mfa_challenges(user_id,token_hash,purpose,expires_at) VALUES('user-admin',$1,'enroll',now()+interval '5 minutes')`, [crypto.createHash('sha256').update(enrollmentChallengeToken).digest('hex')]);
  } finally { await enrollmentPool.end(); }
  const enrollmentSetup = await request('/v1/auth/mfa/enroll/setup', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ challengeToken: enrollmentChallengeToken }) });
  assert.equal(enrollmentSetup.response.status, 200, JSON.stringify(enrollmentSetup.body));
  const enrollmentConfirm = await request('/v1/auth/mfa/enroll/confirm', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ challengeToken: enrollmentChallengeToken, code: totpCode(enrollmentSetup.body.data.secret, Math.floor(Date.now() / 30_000)) }) });
  assert.equal(enrollmentConfirm.response.status, 200, JSON.stringify(enrollmentConfirm.body));
  assert.equal(enrollmentConfirm.body.data.mfaEnrollmentCompleted, true);
  const recovery = await request('/v1/admin/accounts/user-admin/reset-mfa', { method: 'POST', headers: { Authorization: `Bearer ${enrollmentConfirm.body.data.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `mfa-recovery-${Date.now()}` }, body: JSON.stringify({ reason: '测试身份验证器遗失恢复流程' }) });
  assert.equal(recovery.response.status, 200, JSON.stringify(recovery.body));
  assert.equal(recovery.body.data.mfaReset, true);
  const revokedAfterRecovery = await request('/v1/me', { headers: { Authorization: `Bearer ${enrollmentConfirm.body.data.accessToken}` } });
  assert.equal(revokedAfterRecovery.response.status, 401, JSON.stringify(revokedAfterRecovery.body));
});
