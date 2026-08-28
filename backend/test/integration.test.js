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
    const requiredTables = ['users', 'files', 'assessment_tasks', 'test_stations', 'schema_migrations'];
    const ownedTables = await verificationPool.query(`SELECT table_name FROM information_schema.tables
      WHERE table_schema=$1 AND table_name=ANY($2::text[])`, [schema, requiredTables]);
    const available = new Set(ownedTables.rows.map((row) => row.table_name));
    const missing = requiredTables.filter((table) => !available.has(table));
    if (missing.length) throw new Error(`TEST_DATABASE_URL schema ${schema} is not bootstrapped in isolation; missing ${missing.join(', ')}. Run migrate and seed against this schema before integration tests.`);
  } finally {
    await verificationPool.end();
  }
}
await assertIsolatedTestSchema();
let serverProcess;
let createdIntegrationTaskId = null;
let createdIntegrationFollowUpTaskId = null;

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
  if (process.env.TEST_VERBOSE_SERVER_LOGS === 'true') {
    serverProcess.stdout.pipe(process.stdout);
    serverProcess.stderr.pipe(process.stderr);
  }
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
  if (!createdIntegrationTaskId && !createdIntegrationFollowUpTaskId) return;
  const cleanupPool = new Pool({ connectionString: databaseUrl });
  try {
    // The task is created only to exercise idempotency and optimistic locking.
    // It has no value after the suite and PostgreSQL cascades its test scores,
    // queue entries and sessions through the task foreign keys.
    await cleanupPool.query('DELETE FROM assessment_tasks WHERE id=ANY($1::text[])', [[createdIntegrationTaskId, createdIntegrationFollowUpTaskId].filter(Boolean)]);
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
  const fieldClientRelease = await request('/v1/public/field-client-release');
  assert.equal(fieldClientRelease.response.status, 200);
  assert.equal(typeof fieldClientRelease.body.data.available, 'boolean');
  assert.equal(fieldClientRelease.body.data.runtime, 'win-x64 self-contained');
  if (fieldClientRelease.body.data.available) {
    assert.match(fieldClientRelease.body.data.sha256, /^[a-f0-9]{64}$/);
    const fieldClientHead = await fetch(`${base}${fieldClientRelease.body.data.downloadUrl}`, { method: 'HEAD' });
    assert.equal(fieldClientHead.status, 200);
    assert.equal(fieldClientHead.headers.get('content-type'), 'application/zip');
    assert.equal(fieldClientHead.headers.get('x-checksum-sha256'), fieldClientRelease.body.data.sha256);
    assert.equal(Number(fieldClientHead.headers.get('content-length')), fieldClientRelease.body.data.sizeBytes);
  }

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
  const teacherSchoolWideTask = await request('/v1/admin/tasks', { method: 'POST', headers: { Authorization: `Bearer ${teacher.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `teacher-schoolwide-${Date.now()}` }, body: JSON.stringify({ schoolId: 'school-1', title: '教师不可创建全校任务', testDate: '2027-01-03', items: ['连续双脚障碍跳'] }) });
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
  const isolatedTask = await request('/v1/admin/tasks', { method: 'POST', headers: { Authorization: `Bearer ${rotated.body.data.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': `isolated-task-${Date.now()}` }, body: JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', classId: isolatedClass.body.data.id, title: `隔离任务-${Date.now()}`, testDate: '2027-01-02', items: ['连续双脚障碍跳'] }) });
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

  const cleanSnapshots = ['standingFront', 'standingBack', 'standingSide', 'forwardBend', 'dynamicKneeControl', 'gaitVideo', 'seatedPosture', 'footArch'].map((captureTask) => ({
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
  assert.equal(bodyAssessment.body.data.modelRegistryVersion, 'UY-MODELS-1.1');
  assert.equal(bodyAssessment.body.data.postureReport.overallLevel, 'pending');
  assert.equal(bodyAssessment.body.data.postureReport.riskScore, 0);
  assert.equal(bodyAssessment.body.data.postureReport.classificationPublished, false);
  assert.equal(bodyAssessment.body.data.postureReport.validationStatus, 'pending-human-validation');
  assert.equal(bodyAssessment.body.data.postureReport.rulesSourceVersion, 'UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20');
  const latestBody = await request('/v1/students/student-1/body-assessments/latest', { headers: { Authorization: `Bearer ${parent.accessToken}` } });
  assert.equal(latestBody.response.status, 200, JSON.stringify(latestBody.body));
  assert.equal(latestBody.body.data.overallLevel, 'green');
  assert.equal(latestBody.body.data.bmiAlgorithmVersion, 'UY-IMCA-BMI-1.2');
  assert.equal(latestBody.body.data.heightAlgorithmVersion, 'UY-IMCA-HEIGHT-1.0');
  assert.equal(latestBody.body.data.modelRegistryVersion, 'UY-MODELS-1.1');
  assert.equal(latestBody.body.data.postureReport.algorithm, 'UY-IMCA-CV-1.3');
  assert.equal(latestBody.body.data.postureReport.rulesSourceVersion, 'UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20');
  assert.equal(latestBody.body.data.postureReport.overallLevel, 'pending');
  assert.equal(latestBody.body.data.postureReport.classificationPublished, false);

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
  const taskBody = JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', classId: 'class-3', title: `Integration ${Date.now()}`, testDate: '2027-01-01', items: ['连续双脚障碍跳'] });
  const headers = { Authorization: `Bearer ${rotated.body.data.accessToken}`, 'content-type': 'application/json', 'Idempotency-Key': idempotencyKey };
  const [first, second] = await Promise.all([request('/v1/admin/tasks', { method: 'POST', headers, body: taskBody }), request('/v1/admin/tasks', { method: 'POST', headers, body: taskBody })]);
  assert.ok([first.response.status, second.response.status].includes(201));
  const replay = await request('/v1/admin/tasks', { method: 'POST', headers, body: taskBody });
  assert.equal(replay.response.status, 201, JSON.stringify(replay.body));
  const taskId = replay.body.data.id;
  createdIntegrationTaskId = taskId;
  const taskStudents = await request(`/v1/tasks/${encodeURIComponent(taskId)}/students`, { headers: { Authorization: headers.Authorization } });
  assert.equal(taskStudents.response.status, 200, JSON.stringify(taskStudents.body));
  let completedIntegrationStudentId = null;
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
    const studentId = taskStudents.body.data[0].studentId;
    completedIntegrationStudentId = studentId;
    const checkedInVersion = batch.body.data.items[0].version;
    const waiting = await request(`/v1/tasks/${taskId}/students/${studentId}/status`, {
      method: 'PATCH', headers: { ...headers, 'Idempotency-Key': `${idempotencyKey}-waiting` },
      body: JSON.stringify({ status: '候测', expectedVersion: checkedInVersion })
    });
    assert.equal(waiting.response.status, 200, JSON.stringify(waiting.body));
    const testing = await request(`/v1/tasks/${taskId}/students/${studentId}/status`, {
      method: 'PATCH', headers: { ...headers, 'Idempotency-Key': `${idempotencyKey}-testing` },
      body: JSON.stringify({ status: '测试中', expectedVersion: waiting.body.data.version })
    });
    assert.equal(testing.response.status, 200, JSON.stringify(testing.body));
    const completedWithoutScores = await request(`/v1/tasks/${taskId}/students/${studentId}/status`, {
      method: 'PATCH', headers: { ...headers, 'Idempotency-Key': `${idempotencyKey}-complete-missing` },
      body: JSON.stringify({ status: '已完成', expectedVersion: testing.body.data.version })
    });
    assert.equal(completedWithoutScores.response.status, 409, JSON.stringify(completedWithoutScores.body));
    assert.equal(completedWithoutScores.body.code, 'TASK_COMPLETION_SCORES_INCOMPLETE');
    assert.deepEqual(completedWithoutScores.body.data.missingItems, ['连续双脚障碍跳']);
    const scoreOutsideTask = await request(`/v1/tasks/${taskId}/students/${studentId}/scores`, {
      method: 'POST', headers: { ...headers, 'Idempotency-Key': `${idempotencyKey}-outside-score` },
      body: JSON.stringify({ scores: [{ item: '侧向滑步', score: 4, confidence: 0.99, reviewStatus: 'passed' }] })
    });
    assert.equal(scoreOutsideTask.response.status, 409, JSON.stringify(scoreOutsideTask.body));
    assert.equal(scoreOutsideTask.body.code, 'SCORE_ITEM_OUTSIDE_TASK');
    const completedWithScores = await request(`/v1/tasks/${taskId}/students/${studentId}/scores`, {
      method: 'POST', headers: { ...headers, 'Idempotency-Key': `${idempotencyKey}-score-complete` },
      body: JSON.stringify({ markCompleted: true, scores: [{ item: '连续双脚障碍跳', score: 4, confidence: 0.99, reviewStatus: 'passed' }] })
    });
    assert.equal(completedWithScores.response.status, 201, JSON.stringify(completedWithScores.body));
    assert.ok(Array.isArray(completedWithScores.body.data), '成绩提交接口必须保留已有数组响应契约');
    const completedRoster = await request(`/v1/tasks/${encodeURIComponent(taskId)}/students`, { headers: { Authorization: headers.Authorization } });
    const completedStudent = completedRoster.body.data.find((item) => item.studentId === studentId);
    assert.equal(completedStudent.status, '已完成', JSON.stringify(completedRoster.body));
    assert.equal(completedStudent.completionReady, true, JSON.stringify(completedStudent));
    assert.equal(completedStudent.measuredItemCount, 1, JSON.stringify(completedStudent));
    assert.equal(completedStudent.requiredItemCount, 1, JSON.stringify(completedStudent));
  }
  const reused = await request('/v1/admin/tasks', { method: 'POST', headers, body: taskBody.replace('Integration ', 'Changed ') });
  assert.equal(reused.response.status, 409);
  assert.equal(reused.body.code, 'IDEMPOTENCY_KEY_REUSED');

  const unfinishedStudent = taskStudents.body.data.find((item) => item.studentId !== completedIntegrationStudentId);
  assert.ok(unfinishedStudent, JSON.stringify(taskStudents.body));
  const closeVerificationPool = new Pool({ connectionString: databaseUrl });
  let activeSessionId;
  try {
    const queue = await closeVerificationPool.query('SELECT id FROM test_queue_entries WHERE task_id=$1 AND student_id=$2', [taskId, unfinishedStudent.studentId]);
    assert.ok(queue.rows[0], 'unfinished student must have a field queue entry');
    const activeSession = await closeVerificationPool.query(`INSERT INTO test_sessions(client_session_id,school_id,task_id,student_id,queue_entry_id,status,rule_version)
      VALUES($1,'school-1',$2,$3,$4,'testing','运动能力标准 v1.0') RETURNING id`, [`close-guard-${Date.now()}`, taskId, unfinishedStudent.studentId, queue.rows[0].id]);
    activeSessionId = activeSession.rows[0].id;
  } finally { await closeVerificationPool.end(); }
  const blockedClose = await request(`/v1/admin/tasks/${taskId}/status`, {
    method: 'PATCH', headers: { ...headers, 'Idempotency-Key': `${idempotencyKey}-close-active` },
    body: JSON.stringify({ status: 'closed', reason: '集成验收现场收尾', unfinishedAction: 'create_followup', followUpDate: '2027-01-08' })
  });
  assert.equal(blockedClose.response.status, 409, JSON.stringify(blockedClose.body));
  assert.equal(blockedClose.body.code, 'TASK_CLOSE_ACTIVE_SESSIONS');
  const resolveClosePool = new Pool({ connectionString: databaseUrl });
  try { await resolveClosePool.query("UPDATE test_sessions SET status='aborted',ended_at=now() WHERE id=$1", [activeSessionId]); } finally { await resolveClosePool.end(); }
  const closed = await request(`/v1/admin/tasks/${taskId}/status`, {
    method: 'PATCH', headers: { ...headers, 'Idempotency-Key': `${idempotencyKey}-close-success` },
    body: JSON.stringify({ status: 'closed', reason: '集成验收现场收尾', unfinishedAction: 'create_followup', followUpDate: '2027-01-08', followUpTitle: '集成验收后续补测' })
  });
  assert.equal(closed.response.status, 200, JSON.stringify(closed.body));
  assert.equal(closed.body.data.status, 'closed');
  assert.equal(closed.body.data.completedStudentCount, 1);
  assert.equal(closed.body.data.incompleteStudentCount, 1);
  assert.equal(closed.body.data.followUpTask.status, 'draft');
  assert.equal(closed.body.data.followUpTask.studentCount, 1);
  createdIntegrationFollowUpTaskId = closed.body.data.followUpTask.id;
  const closedStatePool = new Pool({ connectionString: databaseUrl });
  try {
    const roster = await closedStatePool.query('SELECT student_id,status FROM task_students WHERE task_id=$1 ORDER BY student_id', [taskId]);
    assert.equal(roster.rows.find((item) => item.student_id === unfinishedStudent.studentId)?.status, '未完成', JSON.stringify(roster.rows));
    assert.equal(roster.rows.filter((item) => item.status === '已完成').length, 1, JSON.stringify(roster.rows));
    const queue = await closedStatePool.query('SELECT status FROM test_queue_entries WHERE task_id=$1', [taskId]);
    assert.ok(queue.rows.every((item) => item.status === 'cancelled'), JSON.stringify(queue.rows));
    const queueEvents = await closedStatePool.query(`SELECT event.reason FROM queue_events event JOIN test_queue_entries queue ON queue.id=event.queue_entry_id
      WHERE queue.task_id=$1 AND event.new_status='cancelled'`, [taskId]);
    assert.equal(queueEvents.rowCount, queue.rowCount);
    assert.ok(queueEvents.rows.every((item) => item.reason === '任务关闭：集成验收现场收尾'));
    const statusEvent = await closedStatePool.query(`SELECT to_status,reason_code FROM task_student_status_events
      WHERE task_id=$1 AND student_id=$2 ORDER BY created_at DESC LIMIT 1`, [taskId, unfinishedStudent.studentId]);
    assert.deepEqual(statusEvent.rows[0], { to_status: '未完成', reason_code: 'task_closed' });
    const followUpRoster = await closedStatePool.query('SELECT student_id,status FROM task_students WHERE task_id=$1', [createdIntegrationFollowUpTaskId]);
    assert.deepEqual(followUpRoster.rows, [{ student_id: unfinishedStudent.studentId, status: '未签到' }]);
  } finally { await closedStatePool.end(); }
  const closedDashboard = await request('/v1/schools/school-1/dashboard?studentPage=1&studentPageSize=100', { headers: { Authorization: headers.Authorization } });
  const closedTask = closedDashboard.body.data.tasks.find((item) => item.id === taskId);
  assert.equal(closedTask.lifecycleStatus, 'closed');
  assert.equal(closedTask.progressStatus, '已关闭');

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
  const scoreItems = ['连续双脚障碍跳', '侧向滑步', '倒退平衡', '接球-上手掷准', '手运球绕杆', '脚运球变向', '定点踢准'];
  // Give each run a separate date-scoped standard so local reruns can coexist
  // while still exercising the active-scope uniqueness constraint.
  const standardEffectiveDate = new Date(Date.UTC(2027, 0, 1) + (parseInt(suffix, 36) % 9000) * 86_400_000).toISOString().slice(0, 10);
  const station = await request('/v1/admin/test-stations', {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ schoolId: 'school-1', stationCode: `IT-${suffix}`, name: '场地端集成验收点', itemCode: null, queueCapacity: 30 })
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
    body: JSON.stringify({ schoolId: 'school-1', stationCode: `IT-B-${suffix}`, name: '场地端并行验收点', itemCode: null, queueCapacity: 30 })
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
  const renamedStationCode = `IT-A-${suffix}`;
  const renamedStation = await request(`/v1/admin/test-stations/${encodeURIComponent(station.body.data.id)}`, {
    method: 'PATCH', headers: authHeaders,
    body: JSON.stringify({ stationCode: renamedStationCode, name: '场地端主测试点', queueCapacity: 31 })
  });
  assert.equal(renamedStation.response.status, 200, JSON.stringify(renamedStation.body));
  assert.equal(renamedStation.body.data.stationCode, renamedStationCode);
  assert.equal(renamedStation.body.data.name, '场地端主测试点');
  assert.equal(renamedStation.body.data.queueCapacity, 31);
  station.body.data.stationCode = renamedStationCode;
  const duplicateStationCode = await request(`/v1/admin/test-stations/${encodeURIComponent(station.body.data.id)}`, {
    method: 'PATCH', headers: authHeaders, body: JSON.stringify({ stationCode: parallelStation.body.data.stationCode })
  });
  assert.equal(duplicateStationCode.response.status, 409, JSON.stringify(duplicateStationCode.body));
  assert.equal(duplicateStationCode.body.code, 'FIELD_STATION_CODE_CONFLICT');
  const renamedDeviceCode = `EDGE-A-${suffix}`;
  const renamedDevice = await request(`/v1/admin/test-devices/${encodeURIComponent(device.body.data.id)}`, {
    method: 'PATCH', headers: authHeaders,
    body: JSON.stringify({ name: '场地端一号采集主机', deviceCode: renamedDeviceCode, serialNumber: `SN-${suffix}` })
  });
  assert.equal(renamedDevice.response.status, 200, JSON.stringify(renamedDevice.body));
  assert.equal(renamedDevice.body.data.name, '场地端一号采集主机');
  assert.equal(renamedDevice.body.data.deviceCode, renamedDeviceCode);
  assert.equal(renamedDevice.body.data.serialNumber, `SN-${suffix}`);
  const duplicateDeviceCode = await request(`/v1/admin/test-devices/${encodeURIComponent(device.body.data.id)}`, {
    method: 'PATCH', headers: authHeaders, body: JSON.stringify({ deviceCode: parallelDevice.body.data.deviceCode })
  });
  assert.equal(duplicateDeviceCode.response.status, 409, JSON.stringify(duplicateDeviceCode.body));
  assert.equal(duplicateDeviceCode.body.code, 'FIELD_DEVICE_CODE_CONFLICT');
  const reboundDevice = await request(`/v1/admin/test-devices/${encodeURIComponent(device.body.data.id)}`, {
    method: 'PATCH', headers: authHeaders, body: JSON.stringify({ stationId: parallelStation.body.data.id })
  });
  assert.equal(reboundDevice.response.status, 200, JSON.stringify(reboundDevice.body));
  assert.equal(reboundDevice.body.data.stationId, parallelStation.body.data.id);
  const restoredDeviceBinding = await request(`/v1/admin/test-devices/${encodeURIComponent(device.body.data.id)}`, {
    method: 'PATCH', headers: authHeaders, body: JSON.stringify({ stationId: station.body.data.id })
  });
  assert.equal(restoredDeviceBinding.response.status, 200, JSON.stringify(restoredDeviceBinding.body));
  assert.equal(restoredDeviceBinding.body.data.stationId, station.body.data.id);
  const teacher = await login('13800000001', 'ChangeMe123!');
  const teacherDeviceEdit = await request(`/v1/admin/test-devices/${encodeURIComponent(device.body.data.id)}`, {
    method: 'PATCH', headers: { Authorization: `Bearer ${teacher.accessToken}`, 'content-type': 'application/json' }, body: JSON.stringify({ name: '教师无权修改' })
  });
  assert.equal(teacherDeviceEdit.response.status, 403, JSON.stringify(teacherDeviceEdit.body));
  const teacherDeviceCommand = await request('/v1/admin/device-commands', {
    method: 'POST', headers: { Authorization: `Bearer ${teacher.accessToken}`, 'content-type': 'application/json' },
    body: JSON.stringify({ deviceId: device.body.data.id, commandType: 'stop' })
  });
  assert.equal(teacherDeviceCommand.response.status, 403, JSON.stringify(teacherDeviceCommand.body));
  const forgedOnlineStation = await request(`/v1/admin/test-stations/${encodeURIComponent(station.body.data.id)}`, {
    method: 'PATCH', headers: authHeaders, body: JSON.stringify({ status: 'online', reason: '不应允许人工伪造在线状态' })
  });
  assert.equal(forgedOnlineStation.response.status, 400, JSON.stringify(forgedOnlineStation.body));
  const maintenanceStation = await request(`/v1/admin/test-stations/${encodeURIComponent(station.body.data.id)}`, {
    method: 'PATCH', headers: authHeaders, body: JSON.stringify({ status: 'maintenance', reason: '集成测试验证维护状态不会被心跳覆盖' })
  });
  assert.equal(maintenanceStation.response.status, 200, JSON.stringify(maintenanceStation.body));
  assert.equal(maintenanceStation.body.data.status, 'maintenance');
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
  const stationsDuringMaintenance = await request('/v1/admin/test-stations?schoolId=school-1', { headers: authHeaders });
  assert.equal(stationsDuringMaintenance.response.status, 200, JSON.stringify(stationsDuringMaintenance.body));
  assert.equal(stationsDuringMaintenance.body.data.find((item) => item.id === station.body.data.id)?.status, 'maintenance', '设备心跳不能覆盖后台维护状态');
  assert.equal(stationsDuringMaintenance.body.data.find((item) => item.id === station.body.data.id)?.statusReason, '集成测试验证维护状态不会被心跳覆盖');
  assert.ok(stationsDuringMaintenance.body.data.find((item) => item.id === station.body.data.id)?.statusChangedByName, '后台应显示测试点状态的修改人员');
  const maintenanceBootstrap = await request('/v1/field/bootstrap', { headers: deviceHeaders });
  assert.equal(maintenanceBootstrap.response.status, 200, JSON.stringify(maintenanceBootstrap.body));
  assert.equal(maintenanceBootstrap.body.data.station.status, 'maintenance');
  assert.equal(maintenanceBootstrap.body.data.station.statusReason, '集成测试验证维护状态不会被心跳覆盖');
  const restoreStation = await request(`/v1/admin/test-stations/${encodeURIComponent(station.body.data.id)}`, {
    method: 'PATCH', headers: authHeaders, body: JSON.stringify({ status: 'offline', reason: '集成测试完成维护并恢复待连接' })
  });
  assert.equal(restoreStation.response.status, 200, JSON.stringify(restoreStation.body));
  const stationReconnectHeartbeat = await request('/v1/field/heartbeat', { method: 'POST', headers: deviceHeaders, body: '{}' });
  assert.equal(stationReconnectHeartbeat.response.status, 200, JSON.stringify(stationReconnectHeartbeat.body));
  const stationsAfterReconnect = await request('/v1/admin/test-stations?schoolId=school-1', { headers: authHeaders });
  assert.equal(stationsAfterReconnect.response.status, 200, JSON.stringify(stationsAfterReconnect.body));
  assert.equal(stationsAfterReconnect.body.data.find((item) => item.id === station.body.data.id)?.status, 'online', '离线测试点应由下一次真实心跳恢复在线');
  assert.equal(stationsAfterReconnect.body.data.find((item) => item.id === station.body.data.id)?.statusReason, null, '恢复在线后不应继续显示旧维护原因');
  const onlineDeviceRebind = await request(`/v1/admin/test-devices/${encodeURIComponent(device.body.data.id)}`, {
    method: 'PATCH', headers: authHeaders, body: JSON.stringify({ stationId: parallelStation.body.data.id })
  });
  assert.equal(onlineDeviceRebind.response.status, 409, JSON.stringify(onlineDeviceRebind.body));
  assert.equal(onlineDeviceRebind.body.code, 'FIELD_DEVICE_ONLINE');
  const healthyFieldHealth = (calibrationVersion = null, checksumSha256 = null) => ({
    schemaVersion: 'field-health/v1',
    selfTest: { passed: true, completedAt: new Date().toISOString() },
    capture: { adapterReady: true, adapterName: 'integration-visual-adapter', depthCameraCount: 2, rgbCameraCount: 1, gpuReady: true, frameSyncOffsetMs: 8.2 },
    storage: { freeMb: 10_240 },
    calibration: { passed: true, version: calibrationVersion, checksumSha256, errorCm: 2.5 }
  });
  const fieldTask = await request('/v1/admin/tasks', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `field-task-${suffix}` },
    body: JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', classId: 'class-3', title: `场地端验收任务-${suffix}`, testDate: '2055-03-03', items: scoreItems })
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
  assert.equal(incompleteBootstrap.body.data.dispatch.mode, 'pre_dispatch', JSON.stringify(incompleteBootstrap.body));
  assert.equal(incompleteBootstrap.body.data.dispatch.readyStationCount, 0, JSON.stringify(incompleteBootstrap.body));
  assert.ok(incompleteBootstrap.body.data.dispatch.planningStationCount >= 2, JSON.stringify(incompleteBootstrap.body));
  assert.ok(incompleteBootstrap.body.data.queue.length >= 1, '未就绪设备也应收到预分流学生名单');
  assert.ok(incompleteBootstrap.body.data.queue.every((entry) => entry.stationId === station.body.data.id), JSON.stringify(incompleteBootstrap.body));
  assert.ok(incompleteBootstrap.body.data.queueSummary.rosterCount >= incompleteBootstrap.body.data.queue.length, JSON.stringify(incompleteBootstrap.body));
  assert.equal(incompleteBootstrap.body.data.queueSummary.activeQueueCount, incompleteBootstrap.body.data.queueSummary.stationActiveCount + incompleteBootstrap.body.data.queueSummary.unassignedCount + incompleteBootstrap.body.data.queueSummary.otherStationCount, JSON.stringify(incompleteBootstrap.body));
  assert.ok(incompleteBootstrap.body.data.readiness.blockers.some((blocker) => blocker.includes('field-health/v1')), JSON.stringify(incompleteBootstrap.body));
  assert.ok(incompleteBootstrap.body.data.readiness.checks.some((check) => check.key === 'health_contract' && check.status === 'blocked' && check.remediation), JSON.stringify(incompleteBootstrap.body));
  const disableLoadedStation = await request(`/v1/admin/test-stations/${encodeURIComponent(station.body.data.id)}`, {
    method: 'PATCH', headers: authHeaders, body: JSON.stringify({ status: 'disabled', reason: '验证存在现场学生时不能直接退役测试点' })
  });
  assert.equal(disableLoadedStation.response.status, 409, JSON.stringify(disableLoadedStation.body));
  assert.equal(disableLoadedStation.body.code, 'FIELD_STATION_HAS_ACTIVE_QUEUE');
  const skippedCallCheckIn = await request(`/v1/admin/test-queues/${encodeURIComponent(incompleteBootstrap.body.data.queue[0].id)}/transition`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ status: 'checked_in', expectedVersion: incompleteBootstrap.body.data.queue[0].stateVersion, identityVerified: true, reason: '候测学生不能跳过叫号直接签到' })
  });
  assert.equal(skippedCallCheckIn.response.status, 409, JSON.stringify(skippedCallCheckIn.body));
  assert.equal(skippedCallCheckIn.body.code, 'FIELD_QUEUE_TRANSITION_INVALID');
  const unreadyCall = await request(`/v1/admin/test-queues/${encodeURIComponent(incompleteBootstrap.body.data.queue[0].id)}/transition`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ status: 'called', expectedVersion: incompleteBootstrap.body.data.queue[0].stateVersion, reason: '未通过开测检查时不应叫号' })
  });
  assert.equal(unreadyCall.response.status, 409, JSON.stringify(unreadyCall.body));
  assert.equal(unreadyCall.body.code, 'FIELD_STATION_NOT_READY');
  const unhealthySession = await request('/v1/field/sessions', {
    method: 'POST', headers: deviceHeaders,
    body: JSON.stringify({ clientSessionId: `unhealthy-${suffix}`, taskId: fieldTask.body.data.id, studentId: incompleteBootstrap.body.data.queue[0].studentId, startedAt: new Date().toISOString(), algorithmVersion: 'it/1.0' })
  });
  assert.equal(unhealthySession.response.status, 409, JSON.stringify(unhealthySession.body));
  assert.equal(unhealthySession.body.code, 'FIELD_STATION_NOT_READY');
  const uncalibratedStation = await request('/v1/admin/test-stations', {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ schoolId: 'school-1', stationCode: `IT-NOCAL-${suffix}`, name: '未标定拦截验收点', itemCode: null, queueCapacity: 10 })
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
  const disabledFieldDevice = await request(`/v1/admin/test-devices/${uncalibratedDevice.body.data.id}`, {
    method: 'PATCH', headers: authHeaders, body: JSON.stringify({ status: 'disabled', reason: '集成测试停用历史设备' })
  });
  assert.equal(disabledFieldDevice.response.status, 200, JSON.stringify(disabledFieldDevice.body));
  assert.equal(disabledFieldDevice.body.data.status, 'disabled');
  const disabledHeartbeat = await request('/v1/field/heartbeat', { method: 'POST', headers: uncalibratedHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth() }) });
  assert.equal(disabledHeartbeat.response.status, 401, JSON.stringify(disabledHeartbeat.body));
  const restoredFieldDevice = await request(`/v1/admin/test-devices/${uncalibratedDevice.body.data.id}`, {
    method: 'PATCH', headers: authHeaders, body: JSON.stringify({ status: 'offline', reason: '集成测试恢复设备' })
  });
  assert.equal(restoredFieldDevice.response.status, 200, JSON.stringify(restoredFieldDevice.body));
  const restoredHeartbeat = await request('/v1/field/heartbeat', { method: 'POST', headers: uncalibratedHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth() }) });
  assert.equal(restoredHeartbeat.response.status, 200, JSON.stringify(restoredHeartbeat.body));
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
  assert.equal(dispatch.body.data.mode, 'formal_ready', JSON.stringify(dispatch.body));
  assert.equal(dispatch.body.data.readyStationCount, 2, JSON.stringify(dispatch.body));
  assert.equal(dispatch.body.data.eligibleStations.length, 2, JSON.stringify(dispatch.body));
  assert.equal(dispatch.body.data.dispatchStations.length, 2, JSON.stringify(dispatch.body));
  const queuesAfterDispatch = await request(`/v1/admin/test-queues?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: authHeaders });
  assert.equal(queuesAfterDispatch.response.status, 200, JSON.stringify(queuesAfterDispatch.body));
  assert.ok(new Set(queuesAfterDispatch.body.data.filter((item) => item.stationId).map((item) => item.stationId)).size >= 2, JSON.stringify(queuesAfterDispatch.body));
  const moveCandidate = queuesAfterDispatch.body.data.find((item) => item.status === 'waiting' && item.stationId);
  assert.ok(moveCandidate, JSON.stringify(queuesAfterDispatch.body));
  assert.ok(moveCandidate.stationName, JSON.stringify(moveCandidate));
  const originalStationId = moveCandidate.stationId;
  const destinationStationId = originalStationId === station.body.data.id ? parallelStation.body.data.id : station.body.data.id;
  const destinationStationCode = originalStationId === station.body.data.id ? parallelStation.body.data.stationCode : station.body.data.stationCode;
  const rejectedUnreadyAssignment = await request(`/v1/admin/test-queues/${encodeURIComponent(moveCandidate.id)}/assign`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ stationId: uncalibratedStation.body.data.id, expectedVersion: moveCandidate.stateVersion, reason: '验证未就绪测试点不可接收学生' })
  });
  assert.equal(rejectedUnreadyAssignment.response.status, 409, JSON.stringify(rejectedUnreadyAssignment.body));
  assert.equal(rejectedUnreadyAssignment.body.code, 'FIELD_STATION_NOT_READY');
  const assignedQueue = await request(`/v1/admin/test-queues/${encodeURIComponent(moveCandidate.id)}/assign`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ stationId: destinationStationId, expectedVersion: moveCandidate.stateVersion, reason: '集成测试模拟原测试点设备故障' })
  });
  assert.equal(assignedQueue.response.status, 200, JSON.stringify(assignedQueue.body));
  assert.equal(assignedQueue.body.data.stationId, destinationStationId);
  assert.equal(assignedQueue.body.data.stationCode, destinationStationCode);
  assert.equal(assignedQueue.body.data.previousStationId, originalStationId);
  assert.equal(assignedQueue.body.data.stateVersion, moveCandidate.stateVersion + 1);
  const staleQueueAssignment = await request(`/v1/admin/test-queues/${encodeURIComponent(moveCandidate.id)}/assign`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ stationId: originalStationId, expectedVersion: moveCandidate.stateVersion, reason: '验证旧版本不可覆盖现场更新' })
  });
  assert.equal(staleQueueAssignment.response.status, 409, JSON.stringify(staleQueueAssignment.body));
  assert.equal(staleQueueAssignment.body.code, 'FIELD_QUEUE_VERSION_CONFLICT');
  const calledMoveCandidate = await request(`/v1/admin/test-queues/${encodeURIComponent(moveCandidate.id)}/transition`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ status: 'called', expectedVersion: assignedQueue.body.data.stateVersion, reason: '验证进入叫号流程后锁定测试点' })
  });
  assert.equal(calledMoveCandidate.response.status, 200, JSON.stringify(calledMoveCandidate.body));
  const queueTimingPool = new Pool({ connectionString: databaseUrl });
  try {
    await queueTimingPool.query(`UPDATE test_queue_entries SET last_called_at=now()-interval '3 minutes' WHERE id=$1`, [moveCandidate.id]);
    const timedQueues = await request(`/v1/admin/test-queues?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: authHeaders });
    assert.equal(timedQueues.response.status, 200, JSON.stringify(timedQueues.body));
    const overdueQueue = timedQueues.body.data.find((item) => item.id === moveCandidate.id);
    assert.equal(overdueQueue.calledOverdue, true, JSON.stringify(overdueQueue));
    assert.equal(overdueQueue.timingSeverity, 'critical', JSON.stringify(overdueQueue));
    assert.ok(overdueQueue.stateAgeSeconds >= 180, JSON.stringify(overdueQueue));
    assert.ok(overdueQueue.lastCalledAt, JSON.stringify(overdueQueue));
  } finally {
    await queueTimingPool.end();
  }
  const busyCapabilityChange = await request(`/v1/admin/test-stations/${encodeURIComponent(destinationStationId)}`, {
    method: 'PATCH', headers: authHeaders,
    body: JSON.stringify({ itemCode: '连续双脚障碍跳' })
  });
  assert.equal(busyCapabilityChange.response.status, 409, JSON.stringify(busyCapabilityChange.body));
  assert.equal(busyCapabilityChange.body.code, 'FIELD_STATION_BUSY');
  const capacityBelowLoad = await request(`/v1/admin/test-stations/${encodeURIComponent(destinationStationId)}`, {
    method: 'PATCH', headers: authHeaders,
    body: JSON.stringify({ queueCapacity: 1 })
  });
  assert.equal(capacityBelowLoad.response.status, 409, JSON.stringify(capacityBelowLoad.body));
  assert.equal(capacityBelowLoad.body.code, 'FIELD_STATION_CAPACITY_BELOW_LOAD');
  const assignedRecallDevice = destinationStationId === station.body.data.id ? device.body.data.id : parallelDevice.body.data.id;
  const mismatchedRecallDevice = destinationStationId === station.body.data.id ? parallelDevice.body.data.id : device.body.data.id;
  const validRecall = await request('/v1/admin/device-commands', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `field-recall-valid-${suffix}` },
    body: JSON.stringify({ deviceId: assignedRecallDevice, commandType: 'recall', payload: { queueEntryId: moveCandidate.id, studentId: moveCandidate.studentId, studentName: moveCandidate.studentName }, expiresAt: new Date(Date.now() + 120_000).toISOString() })
  });
  assert.equal(validRecall.response.status, 201, JSON.stringify(validRecall.body));
  const mismatchedRecall = await request('/v1/admin/device-commands', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `field-recall-mismatch-${suffix}` },
    body: JSON.stringify({ deviceId: mismatchedRecallDevice, commandType: 'recall', payload: { queueEntryId: moveCandidate.id, studentId: moveCandidate.studentId, studentName: moveCandidate.studentName } })
  });
  assert.equal(mismatchedRecall.response.status, 409, JSON.stringify(mismatchedRecall.body));
  assert.equal(mismatchedRecall.body.code, 'FIELD_RECALL_STATION_MISMATCH');
  const unconfirmedCheckIn = await request(`/v1/admin/test-queues/${encodeURIComponent(moveCandidate.id)}/transition`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ status: 'checked_in', expectedVersion: calledMoveCandidate.body.data.stateVersion, reason: '缺少明确身份确认时不应签到' })
  });
  assert.equal(unconfirmedCheckIn.response.status, 400, JSON.stringify(unconfirmedCheckIn.body));
  assert.equal(unconfirmedCheckIn.body.code, 'FIELD_IDENTITY_CONFIRMATION_REQUIRED');
  const lockedQueueAssignment = await request(`/v1/admin/test-queues/${encodeURIComponent(moveCandidate.id)}/assign`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ stationId: originalStationId, expectedVersion: calledMoveCandidate.body.data.stateVersion, reason: '不应移动已叫号学生' })
  });
  assert.equal(lockedQueueAssignment.response.status, 409, JSON.stringify(lockedQueueAssignment.body));
  assert.equal(lockedQueueAssignment.body.code, 'FIELD_QUEUE_ASSIGNMENT_LOCKED');
  const restoredWaitingCandidate = await request(`/v1/admin/test-queues/${encodeURIComponent(moveCandidate.id)}/transition`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ status: 'waiting', expectedVersion: calledMoveCandidate.body.data.stateVersion, reason: '集成测试恢复候测' })
  });
  assert.equal(restoredWaitingCandidate.response.status, 200, JSON.stringify(restoredWaitingCandidate.body));
  const incompatibleQueuedCapabilityChange = await request(`/v1/admin/test-stations/${encodeURIComponent(destinationStationId)}`, {
    method: 'PATCH', headers: authHeaders,
    body: JSON.stringify({ itemCode: '连续双脚障碍跳' })
  });
  assert.equal(incompatibleQueuedCapabilityChange.response.status, 409, JSON.stringify(incompatibleQueuedCapabilityChange.body));
  assert.equal(incompatibleQueuedCapabilityChange.body.code, 'FIELD_STATION_QUEUE_INCOMPATIBLE');
  const invalidStatusRecall = await request('/v1/admin/device-commands', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `field-recall-status-${suffix}` },
    body: JSON.stringify({ deviceId: assignedRecallDevice, commandType: 'recall', payload: { queueEntryId: moveCandidate.id, studentId: moveCandidate.studentId, studentName: moveCandidate.studentName } })
  });
  assert.equal(invalidStatusRecall.response.status, 409, JSON.stringify(invalidStatusRecall.body));
  assert.equal(invalidStatusRecall.body.code, 'FIELD_RECALL_STATUS_INVALID');
  const restoredQueueAssignment = await request(`/v1/admin/test-queues/${encodeURIComponent(moveCandidate.id)}/assign`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ stationId: originalStationId, expectedVersion: restoredWaitingCandidate.body.data.stateVersion, reason: '集成测试恢复原测试点' })
  });
  assert.equal(restoredQueueAssignment.response.status, 200, JSON.stringify(restoredQueueAssignment.body));
  assert.equal(restoredQueueAssignment.body.data.stationId, originalStationId);
  const absentWithoutReason = await request(`/v1/admin/test-queues/${encodeURIComponent(moveCandidate.id)}/transition`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ status: 'absent', expectedVersion: restoredQueueAssignment.body.data.stateVersion })
  });
  assert.equal(absentWithoutReason.response.status, 400, JSON.stringify(absentWithoutReason.body));
  assert.equal(absentWithoutReason.body.code, 'FIELD_QUEUE_REASON_REQUIRED');
  const deviceInventory = await request('/v1/admin/test-devices?schoolId=school-1', { headers: authHeaders });
  assert.equal(deviceInventory.response.status, 200, JSON.stringify(deviceInventory.body));
  assert.equal(deviceInventory.body.data.find((item) => item.id === device.body.data.id)?.signedRequestReady, true, JSON.stringify(deviceInventory.body));
  assert.equal(deviceInventory.body.data.find((item) => item.id === device.body.data.id)?.apiKeyStatus, 'valid');
  const bootstrap = await request(`/v1/field/bootstrap?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: deviceHeaders });
  assert.equal(bootstrap.response.status, 200, JSON.stringify(bootstrap.body));
  assert.equal(bootstrap.body.data.device.name, '场地端一号采集主机');
  assert.equal(bootstrap.body.data.device.code, renamedDeviceCode);
  assert.equal(bootstrap.body.data.station.name, '场地端主测试点');
  assert.equal(bootstrap.body.data.station.stationCode, renamedStationCode);
  assert.equal(bootstrap.body.data.task.id, fieldTask.body.data.id);
  assert.equal(bootstrap.body.data.task.testDate, '2055-03-03');
  assert.ok(bootstrap.body.data.availableTasks.some((task) => task.id === fieldTask.body.data.id && task.totalCount >= 1), JSON.stringify(bootstrap.body));
  assert.equal(bootstrap.body.data.availableTasks.find((task) => task.id === fieldTask.body.data.id)?.testDate, '2055-03-03');
  assert.ok(bootstrap.body.data.queue.length >= 1);
  assert.ok(bootstrap.body.data.queue.every((entry) => entry.stationId === station.body.data.id), JSON.stringify(bootstrap.body));
  assert.ok(bootstrap.body.data.queueSummary.stationAssignedCount >= bootstrap.body.data.queue.length, JSON.stringify(bootstrap.body));
  assert.ok(bootstrap.body.data.queue.every((entry) => entry.studentNo && entry.birthDate && entry.gender), JSON.stringify(bootstrap.body));
  assert.ok(bootstrap.body.data.queue.every((entry) => /^\d{4}-\d{2}-\d{2}$/.test(entry.birthDate)), JSON.stringify(bootstrap.body));
  assert.equal(bootstrap.body.data.readiness.ready, true, JSON.stringify(bootstrap.body));
  assert.equal(bootstrap.body.data.readiness.calibrationVersion, `IT-CAL-${suffix}`);
  assert.equal(bootstrap.body.data.readiness.hardware.depthCameraCount, 2);
  assert.equal(bootstrap.body.data.readiness.hardware.rgbCameraCount, 1);
  assert.equal(bootstrap.body.data.readiness.hardware.frameSyncOffsetMs, 8.2);
  assert.ok(bootstrap.body.data.readiness.checks.length >= 10, JSON.stringify(bootstrap.body));
  assert.ok(bootstrap.body.data.readiness.checks.every((check) => check.status === 'passed'), JSON.stringify(bootstrap.body));
  assert.ok(bootstrap.body.data.standards.some((standard) => standard.standardVersion === `场地标准-${suffix}`), JSON.stringify(bootstrap.body));
  assert.equal(bootstrap.body.data.standards.find((standard) => standard.standardVersion === `场地标准-${suffix}`)?.effectiveDate, standardEffectiveDate);
  const parallelBootstrap = await request(`/v1/field/bootstrap?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: parallelDeviceHeaders });
  assert.equal(parallelBootstrap.response.status, 200, JSON.stringify(parallelBootstrap.body));
  assert.equal(parallelBootstrap.body.data.readiness.ready, true, JSON.stringify(parallelBootstrap.body));
  assert.ok(parallelBootstrap.body.data.queue.length >= 1, JSON.stringify(parallelBootstrap.body));
  assert.ok(parallelBootstrap.body.data.queue.every((entry) => entry.stationId === parallelStation.body.data.id), JSON.stringify(parallelBootstrap.body));
  const student = bootstrap.body.data.queue[0];
  const calibrationGuardPool = new Pool({ connectionString: databaseUrl });
  try {
    await calibrationGuardPool.query(`INSERT INTO test_sessions(client_session_id,school_id,task_id,student_id,station_id,edge_device_id,queue_entry_id,attempt_no,status,rule_version,calibration_version,algorithm_version,started_at)
      VALUES($1,'school-1',$2,$3,$4,$5,$6,99,'testing','integration-rule',$7,'integration-guard',now())`,
    [`calibration-guard-${suffix}`, fieldTask.body.data.id, student.studentId, station.body.data.id, device.body.data.id, student.id, `IT-CAL-${suffix}`]);
    const calibrationWhileTesting = await request(`/v1/admin/test-stations/${encodeURIComponent(station.body.data.id)}/calibrations`, {
      method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `calibration-busy-${suffix}` },
      body: JSON.stringify({ version: `IT-CAL-BUSY-${suffix}`, checksumSha256: 'c'.repeat(64), config: { cameraHeightCm: 131 } })
    });
    assert.equal(calibrationWhileTesting.response.status, 409, JSON.stringify(calibrationWhileTesting.body));
    assert.equal(calibrationWhileTesting.body.code, 'FIELD_CALIBRATION_STATION_BUSY');
  } finally {
    await calibrationGuardPool.query('DELETE FROM test_sessions WHERE client_session_id=$1', [`calibration-guard-${suffix}`]);
    await calibrationGuardPool.end();
  }
  const directCompletion = await request('/v1/field/queue/transition', {
    method: 'POST', headers: deviceHeaders,
    body: JSON.stringify({ queueEntryId: student.id, status: 'completed', expectedVersion: student.stateVersion, note: '不应绕过正式采集会话' })
  });
  assert.equal(directCompletion.response.status, 409, JSON.stringify(directCompletion.body));
  assert.equal(directCompletion.body.code, 'FIELD_SESSION_COMPLETION_REQUIRED');
  const directTesting = await request('/v1/field/queue/transition', {
    method: 'POST', headers: deviceHeaders,
    body: JSON.stringify({ queueEntryId: student.id, status: 'testing', expectedVersion: student.stateVersion, note: '不应绕过正式会话直接进入测试中' })
  });
  assert.equal(directTesting.response.status, 409, JSON.stringify(directTesting.body));
  assert.equal(directTesting.body.code, 'FIELD_SESSION_OPEN_REQUIRED');
  const missingQueueVersion = await request('/v1/field/queue/transition', {
    method: 'POST', headers: deviceHeaders,
    body: JSON.stringify({ queueEntryId: student.id, status: 'called', note: '不应接受缺少版本的队列操作' })
  });
  assert.equal(missingQueueVersion.response.status, 400, JSON.stringify(missingQueueVersion.body));
  assert.equal(missingQueueVersion.body.code, 'FIELD_QUEUE_VERSION_REQUIRED');
  const unsignedCheckInSession = await request('/v1/field/sessions', {
    method: 'POST', headers: deviceHeaders,
    body: JSON.stringify({ clientSessionId: `no-checkin-${suffix}`, taskId: fieldTask.body.data.id, studentId: student.studentId, startedAt: new Date().toISOString(), algorithmVersion: 'UY-IMCA-SCORE-1.3' })
  });
  assert.equal(unsignedCheckInSession.response.status, 409, JSON.stringify(unsignedCheckInSession.body));
  assert.equal(unsignedCheckInSession.body.code, 'FIELD_STUDENT_NOT_CHECKED_IN');
  const clientSessionId = `offline-session-${suffix}`;
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
  await request('/v1/field/heartbeat', { method: 'POST', headers: deviceHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth(`IT-CAL-${suffix}`, 'a'.repeat(64)) }) });
  const captureAction = { clientEventId: `action-${suffix}`, sequenceNo: 1, eventType: 'capture.started', happenedAt: new Date().toISOString(), payload: { framesPerSecond: 30 } };
  const batch = {
    clientBatchId: `batch-${suffix}`,
    events: [
      {
        clientEventId: `call-${suffix}`, eventType: 'queue.transition', happenedAt: new Date().toISOString(),
        payload: { queueEntryId: student.id, status: 'called', expectedVersion: student.stateVersion, note: '集成测试叫号' }
      },
      {
        clientEventId: `checkin-${suffix}`, eventType: 'queue.transition', happenedAt: new Date().toISOString(),
        payload: { queueEntryId: student.id, status: 'checked_in', expectedVersion: student.stateVersion + 1, identityVerified: true, note: '集成测试已核对学生身份并确认签到' }
      },
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
        payload: { sessionId: clientSessionId, algorithmVersion: 'UY-IMCA-SCORE-1.3', endedAt: new Date().toISOString(), scores: scoreItems.map((item, index) => ({ item, score: 4, confidence: 0.91, reviewStatus: index === 0 ? 'pendingReview' : 'passed' })), evidence: [{ fileId: evidencePresign.body.data.id, evidenceType: 'timeline', checksumSha256: evidenceUpload.body.data.checksumSha256, metadata: { frameSyncOffsetMs: 8.2 } }], summary: { source: 'integration', frameCount: 300 } }
      }
    ]
  };
  const synced = await request('/v1/field/sync/batches', { method: 'POST', headers: deviceHeaders, body: JSON.stringify(batch) });
  assert.equal(synced.response.status, 200, JSON.stringify(synced.body));
  assert.equal(synced.body.data.accepted, 6);
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
  assert.deepEqual(tamperedReplay.body.data.acceptedEventIds, []);
  assert.equal(tamperedReplay.body.data.failedEventId, batch.events[0].clientEventId);
  const sessions = await request(`/v1/admin/test-sessions?schoolId=school-1&taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: authHeaders });
  const syncedSession = sessions.body.data.find((item) => item.clientSessionId === clientSessionId);
  assert.ok(syncedSession, JSON.stringify(sessions.body));
  assert.equal(syncedSession.evidenceCount, 1);
  assert.equal(syncedSession.totalEvidenceCount, 1);
  const pagedAttentionSessions = await request(`/v1/admin/test-sessions?schoolId=school-1&taskId=${encodeURIComponent(fieldTask.body.data.id)}&paged=1&page=1&pageSize=1&view=attention&search=${encodeURIComponent(student.studentNo)}`, { headers: authHeaders });
  assert.equal(pagedAttentionSessions.response.status, 200, JSON.stringify(pagedAttentionSessions.body));
  assert.equal(pagedAttentionSessions.body.data.items.length, 1);
  assert.equal(pagedAttentionSessions.body.data.items[0].clientSessionId, clientSessionId);
  assert.equal(pagedAttentionSessions.body.data.page, 1);
  assert.equal(pagedAttentionSessions.body.data.pageSize, 1);
  assert.ok(pagedAttentionSessions.body.data.total >= 1);
  assert.ok(pagedAttentionSessions.body.data.counts.attention >= 1);
  assert.ok(pagedAttentionSessions.body.data.counts.all >= pagedAttentionSessions.body.data.counts.attention);
  const unmatchedSessions = await request(`/v1/admin/test-sessions?schoolId=school-1&paged=1&page=99&view=all&search=${encodeURIComponent(`不存在-${suffix}`)}`, { headers: authHeaders });
  assert.equal(unmatchedSessions.response.status, 200, JSON.stringify(unmatchedSessions.body));
  assert.equal(unmatchedSessions.body.data.total, 0);
  assert.equal(unmatchedSessions.body.data.page, 1);
  assert.deepEqual(unmatchedSessions.body.data.items, []);
  assert.equal(unmatchedSessions.body.data.counts.all, 0);
  const invalidSessionView = await request('/v1/admin/test-sessions?schoolId=school-1&paged=1&view=unknown', { headers: authHeaders });
  assert.equal(invalidSessionView.response.status, 400, JSON.stringify(invalidSessionView.body));
  assert.equal(invalidSessionView.body.code, 'FIELD_SESSION_VIEW_INVALID');
  const detail = await request(`/v1/admin/test-sessions/${syncedSession.id}`, { headers: authHeaders });
  assert.equal(detail.response.status, 200, JSON.stringify(detail.body));
  assert.equal(detail.body.data.status, 'needs_review');
  assert.equal(detail.body.data.studentNo, student.studentNo);
  assert.equal(detail.body.data.gender, student.gender);
  assert.equal(String(detail.body.data.birthDate).slice(0, 10), String(student.birthDate).slice(0, 10));
  assert.equal(detail.body.data.evidenceCount, 1);
  assert.equal(detail.body.data.totalEvidenceCount, 1);
  const operationReviews = await request('/v1/admin/operations/items?schoolId=school-1&type=reviews', { headers: authHeaders });
  assert.ok(operationReviews.body.data.every((item) => !item.sessionId), JSON.stringify(operationReviews.body));
  const fieldOperationSessions = await request('/v1/admin/operations/items?schoolId=school-1&type=fieldSessions', { headers: authHeaders });
  assert.ok(fieldOperationSessions.body.data.some((item) => item.sessionId === syncedSession.id), JSON.stringify(fieldOperationSessions.body));
  const exactSessionSearch = await request(`/v1/admin/test-sessions?schoolId=school-1&paged=1&view=attention&search=${encodeURIComponent(syncedSession.id)}`, { headers: authHeaders });
  assert.equal(exactSessionSearch.response.status, 200, JSON.stringify(exactSessionSearch.body));
  assert.equal(exactSessionSearch.body.data.items[0]?.id, syncedSession.id, JSON.stringify(exactSessionSearch.body));
  const bypassReview = await request(`/v1/admin/operations/reviews/${detail.body.data.scores[0].id}/status`, { method: 'PATCH', headers: { ...authHeaders, 'Idempotency-Key': `bypass-field-review-${suffix}` }, body: JSON.stringify({ status: 'passed' }) });
  assert.equal(bypassReview.response.status, 409, JSON.stringify(bypassReview.body));
  assert.equal(bypassReview.body.code, 'FIELD_SESSION_REVIEW_REQUIRED');
  const reviewKey = `field-session-review-${suffix}`;
  const reviewPayload = { action: 'approve', reason: '集成测试核对动作时间线并修正首项成绩', scores: detail.body.data.scores.map((score, index) => ({ scoreId: score.id, score: index === 0 ? 4.2 : score.score })) };
  const reviewed = await request(`/v1/admin/test-sessions/${syncedSession.id}/review`, { method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': reviewKey }, body: JSON.stringify(reviewPayload) });
  assert.equal(reviewed.response.status, 200, JSON.stringify(reviewed.body));
  assert.equal(reviewed.body.data.status, 'completed');
  assert.equal(reviewed.body.data.correctedScores, 1);
  const reviewReplay = await request(`/v1/admin/test-sessions/${syncedSession.id}/review`, { method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': reviewKey }, body: JSON.stringify(reviewPayload) });
  assert.equal(reviewReplay.response.status, 200, JSON.stringify(reviewReplay.body));
  const reviewedDetail = await request(`/v1/admin/test-sessions/${syncedSession.id}`, { headers: authHeaders });
  assert.equal(reviewedDetail.body.data.status, 'completed');
  assert.equal(reviewedDetail.body.data.standardVersion, `场地标准-${suffix}`);
  assert.equal(reviewedDetail.body.data.standardSnapshot.standardVersion, `场地标准-${suffix}`);
  assert.equal(reviewedDetail.body.data.events.length, 1);
  assert.equal(reviewedDetail.body.data.scores.length, 7);
  assert.equal(reviewedDetail.body.data.scores.filter((score) => score.humanReviewed).length, 7);
  assert.equal(reviewedDetail.body.data.evidence.length, 1);
  assert.equal(reviewedDetail.body.data.reviews.length, 7);
  assert.ok(reviewedDetail.body.data.reviews.every((item) => item.action === 'approve' && item.reviewerName), JSON.stringify(reviewedDetail.body));
  assert.ok(reviewedDetail.body.data.reviews.some((item) => Number(item.oldScore) !== Number(item.newScore)), JSON.stringify(reviewedDetail.body));
  assert.equal(reviewedDetail.body.data.evidence[0].evidenceType, 'timeline');
  assert.equal(reviewedDetail.body.data.evidence[0].purgedAt, null);
  assert.ok(Date.parse(reviewedDetail.body.data.evidence[0].retentionUntil) > Date.now() + 1000 * 86_400_000, JSON.stringify(reviewedDetail.body));
  const queueHistory = await request(`/v1/admin/test-queues/${encodeURIComponent(student.id)}/history`, { headers: authHeaders });
  assert.equal(queueHistory.response.status, 200, JSON.stringify(queueHistory.body));
  assert.equal(queueHistory.body.data.queue.studentId, student.studentId);
  assert.ok(queueHistory.body.data.events.some((item) => item.reason === '集成测试叫号' && item.actorName), JSON.stringify(queueHistory.body));
  assert.ok(queueHistory.body.data.sessions.some((item) => item.id === syncedSession.id && item.scoreCount === 7 && item.evidenceCount === 1), JSON.stringify(queueHistory.body));
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
  assert.equal(purgedDetail.body.data.evidenceCount, 0);
  assert.equal(purgedDetail.body.data.totalEvidenceCount, 1);
  const sessionsAfterPurge = await request(`/v1/admin/test-sessions?schoolId=school-1&taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: authHeaders });
  const purgedSessionSummary = sessionsAfterPurge.body.data.find((item) => item.id === syncedSession.id);
  assert.equal(purgedSessionSummary?.evidenceCount, 0);
  assert.equal(purgedSessionSummary?.totalEvidenceCount, 1);
  const manualContext = [
    ...bootstrap.body.data.queue.filter((entry) => entry.studentId !== student.studentId).map((entry) => ({ entry, headers: deviceHeaders, calibrationVersion: `IT-CAL-${suffix}`, calibrationChecksum: 'a'.repeat(64) })),
    ...parallelBootstrap.body.data.queue.filter((entry) => entry.studentId !== student.studentId).map((entry) => ({ entry, headers: parallelDeviceHeaders, calibrationVersion: `IT-B-CAL-${suffix}`, calibrationChecksum: 'b'.repeat(64) }))
  ][0];
  assert.ok(manualContext, '集成任务至少应包含两名候测学生，以验证低置信度复核链路');
  const manualStudent = manualContext.entry;
  const manualClientSessionId = `manual-session-${suffix}`;
  const forbiddenManualSession = await request('/v1/field/sessions', {
    method: 'POST', headers: manualContext.headers,
    body: JSON.stringify({ clientSessionId: `forbidden-manual-${suffix}`, taskId: fieldTask.body.data.id, studentId: manualStudent.studentId, algorithmVersion: 'field-client/0.1-manual-fallback' })
  });
  assert.equal(forbiddenManualSession.response.status, 409, JSON.stringify(forbiddenManualSession.body));
  assert.equal(forbiddenManualSession.body.code, 'FIELD_MANUAL_CAPTURE_FORBIDDEN');
  // The liveness worker deliberately has a one-second threshold in this suite;
  // renew both eligible edge hosts before exercising the second session flow.
  await request('/v1/field/heartbeat', { method: 'POST', headers: deviceHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth(`IT-CAL-${suffix}`, 'a'.repeat(64)) }) });
  await request('/v1/field/heartbeat', { method: 'POST', headers: parallelDeviceHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth(`IT-B-CAL-${suffix}`, 'b'.repeat(64)) }) });
  const manualBatch = {
    clientBatchId: `manual-batch-${suffix}`,
    events: [
      {
        clientEventId: `manual-call-${suffix}`, eventType: 'queue.transition', happenedAt: new Date().toISOString(),
        payload: { queueEntryId: manualStudent.id, status: 'called', expectedVersion: manualStudent.stateVersion, note: '低置信度复核流程叫号' }
      },
      {
        clientEventId: `manual-checkin-${suffix}`, eventType: 'queue.transition', happenedAt: new Date().toISOString(),
        payload: { queueEntryId: manualStudent.id, status: 'checked_in', expectedVersion: manualStudent.stateVersion + 1, identityVerified: true, note: '低置信度复核流程已核对身份并确认签到' }
      },
      {
        clientEventId: `manual-open-${suffix}`, eventType: 'session.open', happenedAt: new Date().toISOString(),
        payload: { clientSessionId: manualClientSessionId, taskId: fieldTask.body.data.id, studentId: manualStudent.studentId, algorithmVersion: 'certified-test-adapter/1.0', summary: { captureMode: 'certified-adapter' } }
      },
      {
        clientEventId: `manual-complete-${suffix}`, eventType: 'session.complete', happenedAt: new Date().toISOString(),
        payload: {
          sessionId: manualClientSessionId, algorithmVersion: 'certified-test-adapter/1.0', endedAt: new Date().toISOString(),
          scores: scoreItems.map((item) => ({ item, score: 3.5, confidence: 0, note: '低置信度自动复核' })),
          summary: { captureMode: 'certified-adapter', operatorConfirmed: true }
        }
      }
    ]
  };
  const manualSynced = await request('/v1/field/sync/batches', { method: 'POST', headers: manualContext.headers, body: JSON.stringify(manualBatch) });
  assert.equal(manualSynced.response.status, 200, JSON.stringify(manualSynced.body));
  assert.equal(manualSynced.body.data.accepted, 4);
  const manualSessions = await request(`/v1/admin/test-sessions?schoolId=school-1&taskId=${encodeURIComponent(fieldTask.body.data.id)}&status=needs_review`, { headers: authHeaders });
  const manualSession = manualSessions.body.data.find((item) => item.clientSessionId === manualClientSessionId);
  assert.ok(manualSession, JSON.stringify(manualSessions.body));
  assert.equal(manualSession.evidenceCount, 0);
  const manualDetail = await request(`/v1/admin/test-sessions/${manualSession.id}`, { headers: authHeaders });
  assert.equal(manualDetail.response.status, 200, JSON.stringify(manualDetail.body));
  assert.equal(manualDetail.body.data.status, 'needs_review');
  assert.ok(manualDetail.body.data.scores.every((score) => score.reviewStatus === 'pendingReview'));
  const missingEvidenceApproval = await request(`/v1/admin/test-sessions/${manualSession.id}/review`, { method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `missing-evidence-review-${suffix}` }, body: JSON.stringify({ action: 'approve', reason: '不应成功', scores: manualDetail.body.data.scores.map((score) => ({ scoreId: score.id, score: score.score })) }) });
  assert.equal(missingEvidenceApproval.response.status, 409, JSON.stringify(missingEvidenceApproval.body));
  assert.equal(missingEvidenceApproval.body.code, 'FIELD_SESSION_EVIDENCE_REQUIRED');
  const scheduledRetest = await request(`/v1/admin/test-sessions/${manualSession.id}/review`, { method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `schedule-retest-${suffix}` }, body: JSON.stringify({ action: 'retest', reason: '低置信度且缺少现场证据' }) });
  assert.equal(scheduledRetest.response.status, 200, JSON.stringify(scheduledRetest.body));
  assert.equal(scheduledRetest.body.data.status, 'retest');
  const queuesAfterRetest = await request(`/v1/admin/test-queues?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: authHeaders });
  const retestQueue = queuesAfterRetest.body.data.find((item) => item.studentId === manualStudent.studentId);
  assert.equal(retestQueue?.status, 'retest');
  const unifiedSummary = await request('/v1/admin/operations/summary?schoolId=school-1', { headers: authHeaders });
  assert.equal(unifiedSummary.response.status, 200, JSON.stringify(unifiedSummary.body));
  assert.ok(unifiedSummary.body.data.pendingRetests >= 1, JSON.stringify(unifiedSummary.body));
  for (const key of ['completionAnomalies', 'attentionFieldSessions', 'openFieldSyncConflicts', 'pendingReports']) assert.equal(Number.isInteger(unifiedSummary.body.data[key]), true, `${key}: ${JSON.stringify(unifiedSummary.body)}`);
  assert.equal(typeof unifiedSummary.body.data.fieldRuntime?.state, 'string', JSON.stringify(unifiedSummary.body));
  assert.equal(typeof unifiedSummary.body.data.fieldRuntime?.message, 'string', JSON.stringify(unifiedSummary.body));
  for (const key of ['publishedTaskCount', 'activeQueueCount', 'waitingCount', 'testingCount', 'overdueCount', 'totalDevices', 'onlineDevices', 'readyDevices', 'blockedDevices', 'neverConnectedDevices', 'unboundDevices']) {
    assert.equal(Number.isInteger(unifiedSummary.body.data.fieldRuntime?.[key]), true, `fieldRuntime.${key}: ${JSON.stringify(unifiedSummary.body)}`);
  }
  assert.equal(typeof unifiedSummary.body.data.fieldRuntime?.primaryAction?.target, 'string', JSON.stringify(unifiedSummary.body));
  assert.equal(typeof unifiedSummary.body.data.fieldRuntime?.primaryAction?.label, 'string', JSON.stringify(unifiedSummary.body));
  assert.equal(typeof unifiedSummary.body.data.fieldRuntime?.selectedTaskId, 'string', JSON.stringify(unifiedSummary.body));
  assert.equal(typeof unifiedSummary.body.data.fieldRuntime?.selectedTaskTitle, 'string', JSON.stringify(unifiedSummary.body));
  assert.match(unifiedSummary.body.data.fieldRuntime?.selectedTaskDate || '', /^\d{4}-\d{2}-\d{2}$/);
  const retestOperations = await request('/v1/admin/operations/items?schoolId=school-1&type=retests', { headers: authHeaders });
  assert.equal(retestOperations.response.status, 200, JSON.stringify(retestOperations.body));
  assert.ok(retestOperations.body.data.some((item) => item.taskId === fieldTask.body.data.id && item.studentId === manualStudent.studentId && item.queueStatus === 'retest'), JSON.stringify(retestOperations.body));
  await request('/v1/field/heartbeat', { method: 'POST', headers: manualContext.headers, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth(manualContext.calibrationVersion, manualContext.calibrationChecksum) }) });
  const interruptedClientSessionId = `interrupted-session-${suffix}`;
  const interruptedBatch = await request('/v1/field/sync/batches', {
    method: 'POST', headers: manualContext.headers,
    body: JSON.stringify({
      clientBatchId: `interrupted-batch-${suffix}`,
      events: [
        { clientEventId: `interrupted-call-${suffix}`, eventType: 'queue.transition', happenedAt: new Date().toISOString(), payload: { queueEntryId: retestQueue.id, status: 'called', expectedVersion: retestQueue.stateVersion, note: '中断恢复测试重新叫号' } },
        { clientEventId: `interrupted-checkin-${suffix}`, eventType: 'queue.transition', happenedAt: new Date().toISOString(), payload: { queueEntryId: retestQueue.id, status: 'checked_in', expectedVersion: retestQueue.stateVersion + 1, identityVerified: true, note: '中断恢复测试已重新核对身份并签到' } },
        { clientEventId: `interrupted-open-${suffix}`, eventType: 'session.open', happenedAt: new Date().toISOString(), payload: { clientSessionId: interruptedClientSessionId, taskId: fieldTask.body.data.id, studentId: manualStudent.studentId, algorithmVersion: 'certified-test-adapter/1.0', summary: { captureMode: 'certified-adapter' } } },
        { clientEventId: `interrupted-abort-${suffix}`, eventType: 'session.abort', happenedAt: new Date().toISOString(), payload: { sessionId: interruptedClientSessionId, endedAt: new Date().toISOString(), reason: '集成测试模拟 Windows 异常退出' } }
      ]
    })
  });
  assert.equal(interruptedBatch.response.status, 200, JSON.stringify(interruptedBatch.body));
  assert.equal(interruptedBatch.body.data.accepted, 4);
  const interruptedSessions = await request(`/v1/admin/test-sessions?schoolId=school-1&taskId=${encodeURIComponent(fieldTask.body.data.id)}&status=aborted`, { headers: authHeaders });
  assert.ok(interruptedSessions.body.data.some((item) => item.clientSessionId === interruptedClientSessionId), JSON.stringify(interruptedSessions.body));
  const queueAfterAbort = await request(`/v1/admin/test-queues?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: authHeaders });
  assert.equal(queueAfterAbort.body.data.find((item) => item.studentId === manualStudent.studentId)?.status, 'retest');
  assert.ok(queueAfterAbort.body.data.every((entry) => entry.studentNo && entry.birthDate && entry.gender), JSON.stringify(queueAfterAbort.body));
  const recoveryEntry = queueAfterAbort.body.data.find((item) => item.studentId === manualStudent.studentId);
  await request('/v1/field/heartbeat', { method: 'POST', headers: manualContext.headers, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth(manualContext.calibrationVersion, manualContext.calibrationChecksum) }) });
  const recoveryClientSessionId = `admin-recovery-session-${suffix}`;
  const recoveryOpen = await request('/v1/field/sync/batches', {
    method: 'POST', headers: manualContext.headers,
    body: JSON.stringify({
      clientBatchId: `admin-recovery-open-${suffix}`,
      events: [
        { clientEventId: `admin-recovery-call-${suffix}`, eventType: 'queue.transition', happenedAt: new Date().toISOString(), payload: { queueEntryId: recoveryEntry.id, status: 'called', expectedVersion: recoveryEntry.stateVersion, note: '后台异常恢复测试叫号' } },
        { clientEventId: `admin-recovery-checkin-${suffix}`, eventType: 'queue.transition', happenedAt: new Date().toISOString(), payload: { queueEntryId: recoveryEntry.id, status: 'checked_in', expectedVersion: recoveryEntry.stateVersion + 1, identityVerified: true, note: '后台异常恢复测试已核对身份' } },
        { clientEventId: `admin-recovery-session-open-${suffix}`, eventType: 'session.open', happenedAt: new Date().toISOString(), payload: { clientSessionId: recoveryClientSessionId, taskId: fieldTask.body.data.id, studentId: manualStudent.studentId, algorithmVersion: 'certified-test-adapter/1.0', summary: { captureMode: 'certified-adapter' } } },
        { clientEventId: `admin-recovery-progress-${suffix}`, eventType: 'session.events', happenedAt: new Date().toISOString(), payload: { sessionId: recoveryClientSessionId, events: [{ clientEventId: `admin-recovery-action-${suffix}`, sequenceNo: 1, eventType: 'item.started', happenedAt: new Date().toISOString(), payload: { item: '侧向滑步', message: '学生已进入采集区域', progress: 0.25 } }] } }
      ]
    })
  });
  assert.equal(recoveryOpen.response.status, 200, JSON.stringify(recoveryOpen.body));
  assert.equal(recoveryOpen.body.data.accepted, 4, JSON.stringify(recoveryOpen.body));
  const activeQueueProgress = await request(`/v1/admin/test-queues?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: authHeaders });
  const progressEntry = activeQueueProgress.body.data.find((item) => item.id === recoveryEntry.id);
  assert.equal(progressEntry?.activeSessionId != null, true, JSON.stringify(progressEntry));
  assert.equal(progressEntry?.captureEventCount, 1, JSON.stringify(progressEntry));
  assert.equal(progressEntry?.latestCaptureEventType, 'item.started', JSON.stringify(progressEntry));
  assert.equal(progressEntry?.latestCapturePayload?.item, '侧向滑步', JSON.stringify(progressEntry));
  assert.ok(progressEntry?.lastCaptureEventAt, JSON.stringify(progressEntry));
  const activeBootstrapProgress = await request(`/v1/field/bootstrap?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: manualContext.headers });
  const bootstrapProgressEntry = activeBootstrapProgress.body.data.queue.find((item) => item.id === recoveryEntry.id);
  assert.equal(bootstrapProgressEntry?.captureEventCount, 1, JSON.stringify(bootstrapProgressEntry));
  assert.equal(bootstrapProgressEntry?.latestCapturePayload?.item, '侧向滑步', JSON.stringify(bootstrapProgressEntry));
  const activeRecoverySessions = await request(`/v1/admin/test-sessions?schoolId=school-1&taskId=${encodeURIComponent(fieldTask.body.data.id)}&status=testing`, { headers: authHeaders });
  const recoverySession = activeRecoverySessions.body.data.find((item) => item.clientSessionId === recoveryClientSessionId);
  assert.ok(recoverySession, JSON.stringify(activeRecoverySessions.body));
  const blockedRecovery = await request(`/v1/admin/test-sessions/${recoverySession.id}/recover`, {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `admin-recovery-blocked-${suffix}` }, body: JSON.stringify({ reason: '设备仍在线时不应收口' })
  });
  assert.equal(blockedRecovery.response.status, 409, JSON.stringify(blockedRecovery.body));
  assert.equal(blockedRecovery.body.code, 'FIELD_SESSION_DEVICE_ACTIVE');
  const recoveryPool = new Pool({ connectionString: databaseUrl });
  try {
    await recoveryPool.query(`UPDATE test_devices SET status='offline',last_heartbeat_at=now()-interval '5 minutes'
      WHERE id=(SELECT edge_device_id FROM test_sessions WHERE id=$1)`, [recoverySession.id]);
  } finally { await recoveryPool.end(); }
  const recoverableSessions = await request(`/v1/admin/test-sessions?schoolId=school-1&paged=1&view=attention&search=${encodeURIComponent(recoveryClientSessionId)}`, { headers: authHeaders });
  assert.equal(recoverableSessions.response.status, 200, JSON.stringify(recoverableSessions.body));
  assert.equal(recoverableSessions.body.data.items[0]?.id, recoverySession.id, JSON.stringify(recoverableSessions.body));
  assert.equal(recoverableSessions.body.data.items[0]?.recoveryEligible, true, JSON.stringify(recoverableSessions.body));
  const recoveryOperationsSummary = await request('/v1/admin/operations/summary?schoolId=school-1', { headers: authHeaders });
  assert.ok(recoveryOperationsSummary.body.data.attentionFieldSessions >= 1, JSON.stringify(recoveryOperationsSummary.body));
  const recoveryOperationItems = await request('/v1/admin/operations/items?schoolId=school-1&type=fieldSessions', { headers: authHeaders });
  assert.ok(recoveryOperationItems.body.data.some((item) => item.sessionId === recoverySession.id && item.recoveryEligible === true), JSON.stringify(recoveryOperationItems.body));
  const recoveredSession = await request(`/v1/admin/test-sessions/${recoverySession.id}/recover`, {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `admin-recovery-${suffix}` }, body: JSON.stringify({ reason: '集成测试模拟场地设备掉线，收口原会话并重新补测' })
  });
  assert.equal(recoveredSession.response.status, 200, JSON.stringify(recoveredSession.body));
  assert.equal(recoveredSession.body.data.status, 'aborted');
  assert.equal(recoveredSession.body.data.queueStatus, 'retest');
  const recoveryReplay = await request(`/v1/admin/test-sessions/${recoverySession.id}/recover`, {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `admin-recovery-${suffix}` }, body: JSON.stringify({ reason: '集成测试模拟场地设备掉线，收口原会话并重新补测' })
  });
  assert.equal(recoveryReplay.response.status, 200, JSON.stringify(recoveryReplay.body));
  const queueAfterRecovery = await request(`/v1/admin/test-queues?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: authHeaders });
  assert.equal(queueAfterRecovery.body.data.find((item) => item.studentId === manualStudent.studentId)?.status, 'retest');
  const lateCompletion = await request(`/v1/field/sessions/${recoverySession.id}/complete`, {
    method: 'POST', headers: manualContext.headers,
    body: JSON.stringify({ algorithmVersion: 'certified-test-adapter/1.0', endedAt: new Date().toISOString(), scores: scoreItems.map((item) => ({ item, score: 5, confidence: 1 })), evidence: [], summary: { source: 'late-after-admin-recovery' } })
  });
  assert.equal(lateCompletion.response.status, 409, JSON.stringify(lateCompletion.body));
  assert.equal(lateCompletion.body.code, 'FIELD_SESSION_ABORTED');
  const emergencyHeartbeat = await request('/v1/field/heartbeat', {
    method: 'POST', headers: deviceHeaders,
    body: JSON.stringify({ softwareVersion: 'it/1.0', health: { ...healthyFieldHealth(`IT-CAL-${suffix}`, 'a'.repeat(64)), emergencyStop: true } })
  });
  assert.equal(emergencyHeartbeat.response.status, 200, JSON.stringify(emergencyHeartbeat.body));
  const emergencyBootstrap = await request(`/v1/field/bootstrap?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: deviceHeaders });
  assert.equal(emergencyBootstrap.body.data.readiness.ready, false, JSON.stringify(emergencyBootstrap.body));
  assert.ok(emergencyBootstrap.body.data.readiness.blockers.includes('场地端处于紧急停止状态'), JSON.stringify(emergencyBootstrap.body));
  const emergencyInventory = await request('/v1/admin/test-devices?schoolId=school-1', { headers: authHeaders });
  assert.ok(emergencyInventory.body.data.find((item) => item.id === device.body.data.id)?.readiness.blockers.includes('场地端处于紧急停止状态'), JSON.stringify(emergencyInventory.body));
  const clearEmergencyHeartbeat = await request('/v1/field/heartbeat', { method: 'POST', headers: deviceHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth(`IT-CAL-${suffix}`, 'a'.repeat(64)) }) });
  assert.equal(clearEmergencyHeartbeat.response.status, 200, JSON.stringify(clearEmergencyHeartbeat.body));
  const pauseCommand = await request('/v1/admin/device-commands', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `field-pause-${suffix}` },
    body: JSON.stringify({ deviceId: device.body.data.id, commandType: 'pause', payload: { reason: '集成测试暂停现场' } })
  });
  assert.equal(pauseCommand.response.status, 201, JSON.stringify(pauseCommand.body));
  assert.equal(pauseCommand.body.data.controlState, 'paused');
  const pauseReplay = await request('/v1/admin/device-commands', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `field-pause-${suffix}` },
    body: JSON.stringify({ deviceId: device.body.data.id, commandType: 'pause', payload: { reason: '集成测试暂停现场' } })
  });
  assert.equal(pauseReplay.response.status, 201, JSON.stringify(pauseReplay.body));
  assert.equal(pauseReplay.body.data.id, pauseCommand.body.data.id);
  const pausedBootstrap = await request(`/v1/field/bootstrap?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: deviceHeaders });
  assert.equal(pausedBootstrap.body.data.device.controlState, 'paused', JSON.stringify(pausedBootstrap.body));
  assert.equal(pausedBootstrap.body.data.readiness.ready, false, JSON.stringify(pausedBootstrap.body));
  assert.ok(pausedBootstrap.body.data.readiness.blockers.includes('中央管理端已暂停现场操作'), JSON.stringify(pausedBootstrap.body));
  const pausedInventory = await request('/v1/admin/test-devices?schoolId=school-1', { headers: authHeaders });
  assert.equal(pausedInventory.body.data.find((item) => item.id === device.body.data.id)?.controlState, 'paused', JSON.stringify(pausedInventory.body));
  const resumeCommand = await request('/v1/admin/device-commands', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `field-resume-${suffix}` },
    body: JSON.stringify({ deviceId: device.body.data.id, commandType: 'resume', payload: { reason: '集成测试恢复现场' } })
  });
  assert.equal(resumeCommand.response.status, 201, JSON.stringify(resumeCommand.body));
  assert.equal(resumeCommand.body.data.controlState, 'running');
  const resumedBootstrap = await request(`/v1/field/bootstrap?taskId=${encodeURIComponent(fieldTask.body.data.id)}`, { headers: deviceHeaders });
  assert.equal(resumedBootstrap.body.data.device.controlState, 'running', JSON.stringify(resumedBootstrap.body));
  assert.equal(resumedBootstrap.body.data.readiness.ready, true, JSON.stringify(resumedBootstrap.body));
  const command = await request('/v1/admin/device-commands', { method: 'POST', headers: authHeaders, body: JSON.stringify({ deviceId: device.body.data.id, commandType: 'refresh_config', payload: { calibration: true } }) });
  assert.equal(command.response.status, 201, JSON.stringify(command.body));
  const commands = await request('/v1/field/commands', { headers: deviceHeaders });
  assert.equal(commands.response.status, 200, JSON.stringify(commands.body));
  assert.ok(commands.body.data.commands.some((item) => item.id === command.body.data.id));
  const acknowledged = await request(`/v1/field/commands/${command.body.data.id}/ack`, { method: 'POST', headers: deviceHeaders, body: '{}' });
  assert.equal(acknowledged.response.status, 200, JSON.stringify(acknowledged.body));
  const partialEntry = resumedBootstrap.body.data.queue[0];
  const partialBatchId = crypto.randomUUID();
  const partialAcceptedId = crypto.randomUUID();
  const partialFailedId = crypto.randomUUID();
  const partialUnprocessedId = crypto.randomUUID();
  const partialEvents = [
    { clientEventId: partialAcceptedId, eventType: 'queue.transition', happenedAt: new Date().toISOString(), payload: { queueEntryId: partialEntry.id, status: partialEntry.status, expectedVersion: partialEntry.stateVersion, note: '部分回执首条成功' } },
    { clientEventId: partialFailedId, eventType: 'queue.transition', happenedAt: new Date().toISOString(), payload: { queueEntryId: partialEntry.id, status: partialEntry.status, expectedVersion: partialEntry.stateVersion, note: '部分回执故意使用旧版本' } },
    { clientEventId: partialUnprocessedId, eventType: 'queue.transition', happenedAt: new Date().toISOString(), payload: { queueEntryId: partialEntry.id, status: partialEntry.status, expectedVersion: partialEntry.stateVersion + 1, note: '部分回执后续应可续传' } }
  ];
  const partialFailure = await request('/v1/field/sync/batches', {
    method: 'POST', headers: deviceHeaders,
    body: JSON.stringify({ clientBatchId: partialBatchId, events: partialEvents })
  });
  assert.equal(partialFailure.response.status, 409, JSON.stringify(partialFailure.body));
  assert.equal(partialFailure.body.code, 'FIELD_QUEUE_VERSION_CONFLICT');
  assert.equal(partialFailure.body.data.clientBatchId, partialBatchId);
  assert.deepEqual(partialFailure.body.data.acceptedEventIds, [partialAcceptedId]);
  assert.equal(partialFailure.body.data.failedEventId, partialFailedId);
  assert.deepEqual(partialFailure.body.data.unprocessedEventIds, [partialUnprocessedId]);
  const partialContinuation = await request('/v1/field/sync/batches', {
    method: 'POST', headers: deviceHeaders,
    body: JSON.stringify({ clientBatchId: crypto.randomUUID(), events: [partialEvents[2]] })
  });
  assert.equal(partialContinuation.response.status, 200, JSON.stringify(partialContinuation.body));
  assert.equal(partialContinuation.body.data.accepted, 1);
  const openSyncConflicts = await request('/v1/admin/field-sync-conflicts?schoolId=school-1&view=open&page=1&pageSize=20', { headers: authHeaders });
  assert.equal(openSyncConflicts.response.status, 200, JSON.stringify(openSyncConflicts.body));
  const partialConflict = openSyncConflicts.body.data.items.find((item) => item.clientBatchId === partialBatchId);
  assert.ok(partialConflict, JSON.stringify(openSyncConflicts.body));
  assert.equal(partialConflict.failedEvent.queueEntryId, partialEntry.id);
  assert.equal(partialConflict.failedEvent.expectedVersion, partialEntry.stateVersion);
  assert.ok(partialConflict.studentName, JSON.stringify(partialConflict));
  const resolvedConflict = await request(`/v1/admin/field-sync-conflicts/${encodeURIComponent(partialConflict.id)}/resolve`, {
    method: 'POST', headers: authHeaders,
    body: JSON.stringify({ note: '集成测试已核对中央队列与现场记录，以中央当前状态为准' })
  });
  assert.equal(resolvedConflict.response.status, 200, JSON.stringify(resolvedConflict.body));
  assert.equal(resolvedConflict.body.data.resolutionStatus, 'resolved');
  const conflictResolutions = await request('/v1/field/sync/conflict-resolutions', { headers: deviceHeaders });
  assert.equal(conflictResolutions.response.status, 200, JSON.stringify(conflictResolutions.body));
  const deviceResolution = conflictResolutions.body.data.find((item) => item.clientBatchId === partialBatchId);
  assert.ok(deviceResolution, JSON.stringify(conflictResolutions.body));
  assert.deepEqual(new Set(deviceResolution.eventIds), new Set([partialAcceptedId, partialFailedId, partialUnprocessedId]));

  // A task may be closed centrally while an edge host is offline. The signed
  // outbox must preserve those late facts without reopening the task, queue or
  // student lifecycle and without creating avoidable operator conflicts.
  const retiredTask = await request('/v1/admin/tasks', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `retired-field-task-${suffix}` },
    body: JSON.stringify({ schoolId: 'school-1', gradeId: 'grade-3', classId: 'class-3', title: `离线关闭验收-${suffix}`, testDate: '2055-03-04', items: ['连续双脚障碍跳'] })
  });
  assert.equal(retiredTask.response.status, 201, JSON.stringify(retiredTask.body));
  await request('/v1/field/heartbeat', { method: 'POST', headers: deviceHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth(`IT-CAL-${suffix}`, 'a'.repeat(64)) }) });
  await request('/v1/field/heartbeat', { method: 'POST', headers: parallelDeviceHeaders, body: JSON.stringify({ softwareVersion: 'it/1.0', health: healthyFieldHealth(`IT-B-CAL-${suffix}`, 'b'.repeat(64)) }) });
  const retiredDispatch = await request('/v1/admin/test-queues/rebalance', {
    method: 'POST', headers: { ...authHeaders, 'Idempotency-Key': `retired-field-dispatch-${suffix}` }, body: JSON.stringify({ taskId: retiredTask.body.data.id })
  });
  assert.equal(retiredDispatch.response.status, 200, JSON.stringify(retiredDispatch.body));
  const retiredPrimaryBootstrap = await request(`/v1/field/bootstrap?taskId=${encodeURIComponent(retiredTask.body.data.id)}`, { headers: deviceHeaders });
  const retiredParallelBootstrap = await request(`/v1/field/bootstrap?taskId=${encodeURIComponent(retiredTask.body.data.id)}`, { headers: parallelDeviceHeaders });
  const retiredContext = retiredPrimaryBootstrap.body.data.queue.length
    ? { headers: deviceHeaders, entry: retiredPrimaryBootstrap.body.data.queue[0] }
    : { headers: parallelDeviceHeaders, entry: retiredParallelBootstrap.body.data.queue[0] };
  assert.ok(retiredContext.entry, JSON.stringify({ retiredPrimaryBootstrap: retiredPrimaryBootstrap.body, retiredParallelBootstrap: retiredParallelBootstrap.body }));
  const retiredClientSessionId = `retired-offline-${suffix}`;
  const retiredEventIds = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
  const retiredStartedAt = new Date(Date.now() - 60_000).toISOString();
  const retiredClosed = await request(`/v1/admin/tasks/${encodeURIComponent(retiredTask.body.data.id)}/status`, {
    method: 'PATCH', headers: { ...authHeaders, 'Idempotency-Key': `retired-field-close-${suffix}` },
    body: JSON.stringify({ status: 'closed', reason: '模拟场地端断网期间后台收尾', unfinishedAction: 'close_incomplete' })
  });
  assert.equal(retiredClosed.response.status, 200, JSON.stringify(retiredClosed.body));
  const rejectedClosedTransition = await request('/v1/field/queue/transition', {
    method: 'POST', headers: retiredContext.headers,
    body: JSON.stringify({ taskId: retiredTask.body.data.id, queueEntryId: retiredContext.entry.id, status: 'called', expectedVersion: retiredContext.entry.stateVersion, happenedAt: retiredStartedAt, note: '在线接口不得重开已关闭任务' })
  });
  assert.equal(rejectedClosedTransition.response.status, 409, JSON.stringify(rejectedClosedTransition.body));
  assert.equal(rejectedClosedTransition.body.code, 'FIELD_TASK_INACTIVE');
  const rejectedClosedSession = await request('/v1/field/sessions', {
    method: 'POST', headers: retiredContext.headers,
    body: JSON.stringify({ clientSessionId: retiredClientSessionId, taskId: retiredTask.body.data.id, studentId: retiredContext.entry.studentId, startedAt: retiredStartedAt, algorithmVersion: 'certified-test-adapter/1.0' })
  });
  assert.equal(rejectedClosedSession.response.status, 409, JSON.stringify(rejectedClosedSession.body));
  assert.equal(rejectedClosedSession.body.code, 'FIELD_TASK_INACTIVE');
  const retiredBatchId = crypto.randomUUID();
  const retiredBatch = await request('/v1/field/sync/batches', {
    method: 'POST', headers: retiredContext.headers,
    body: JSON.stringify({
      clientBatchId: retiredBatchId,
      events: [
        { clientEventId: retiredEventIds[0], eventType: 'queue.transition', happenedAt: retiredStartedAt, payload: { taskId: retiredTask.body.data.id, queueEntryId: retiredContext.entry.id, status: 'called', expectedVersion: retiredContext.entry.stateVersion, note: '离线叫号事实' } },
        { clientEventId: retiredEventIds[1], eventType: 'queue.transition', happenedAt: new Date(Date.now() - 50_000).toISOString(), payload: { taskId: retiredTask.body.data.id, queueEntryId: retiredContext.entry.id, status: 'checked_in', expectedVersion: retiredContext.entry.stateVersion + 1, identityVerified: true, note: '离线身份核验与签到事实' } },
        { clientEventId: retiredEventIds[2], eventType: 'session.open', happenedAt: retiredStartedAt, payload: { clientSessionId: retiredClientSessionId, taskId: retiredTask.body.data.id, studentId: retiredContext.entry.studentId, startedAt: retiredStartedAt, algorithmVersion: 'certified-test-adapter/1.0', summary: { captureMode: 'certified-adapter', taskRetiredRecovery: true } } },
        { clientEventId: retiredEventIds[3], eventType: 'session.abort', happenedAt: new Date().toISOString(), payload: { sessionId: retiredClientSessionId, endedAt: new Date().toISOString(), reason: '后台关闭任务后场地端封存旧采集上下文' } }
      ]
    })
  });
  assert.equal(retiredBatch.response.status, 200, JSON.stringify(retiredBatch.body));
  assert.equal(retiredBatch.body.data.accepted, 4, JSON.stringify(retiredBatch.body));
  assert.equal(retiredBatch.body.data.outcomes[0].data.lateAfterTaskClosure, true, JSON.stringify(retiredBatch.body));
  assert.equal(retiredBatch.body.data.outcomes[2].data.status, 'aborted', JSON.stringify(retiredBatch.body));
  const retiredVerificationPool = new Pool({ connectionString: databaseUrl });
  try {
    const taskState = await retiredVerificationPool.query('SELECT status FROM assessment_tasks WHERE id=$1', [retiredTask.body.data.id]);
    const rosterState = await retiredVerificationPool.query('SELECT status FROM task_students WHERE task_id=$1 AND student_id=$2', [retiredTask.body.data.id, retiredContext.entry.studentId]);
    const queueState = await retiredVerificationPool.query('SELECT status FROM test_queue_entries WHERE id=$1', [retiredContext.entry.id]);
    const lateQueueEvents = await retiredVerificationPool.query('SELECT old_status,new_status,reason FROM queue_events WHERE client_event_id=ANY($1::text[]) ORDER BY happened_at', [retiredEventIds.slice(0, 2)]);
    const retiredSession = await retiredVerificationPool.query('SELECT status,summary_json FROM test_sessions WHERE client_session_id=$1', [retiredClientSessionId]);
    const batchState = await retiredVerificationPool.query('SELECT status,resolution_status FROM field_sync_batches WHERE device_id=(SELECT edge_device_id FROM test_sessions WHERE client_session_id=$1) AND client_batch_id=$2', [retiredClientSessionId, retiredBatchId]);
    assert.equal(taskState.rows[0].status, 'closed');
    assert.equal(rosterState.rows[0].status, '未完成');
    assert.equal(queueState.rows[0].status, 'cancelled');
    assert.equal(lateQueueEvents.rowCount, 2, JSON.stringify(lateQueueEvents.rows));
    assert.ok(lateQueueEvents.rows.every((event) => event.old_status === 'cancelled' && event.new_status === 'cancelled' && event.reason.includes('离线现场事实')), JSON.stringify(lateQueueEvents.rows));
    assert.equal(retiredSession.rows[0].status, 'aborted');
    assert.equal(retiredSession.rows[0].summary_json.lateAfterTaskClosure, true);
    assert.deepEqual(batchState.rows[0], { status: 'completed', resolution_status: 'not_applicable' });
  } finally { await retiredVerificationPool.end(); }

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
  // Report-refresh jobs share the embedded test worker with liveness. Allow a
  // bounded extra window for the next reconcile pass after those jobs drain;
  // the device timeout itself remains the test-only one second configured above.
  for (let attempt = 0; attempt < 12; attempt += 1) {
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
