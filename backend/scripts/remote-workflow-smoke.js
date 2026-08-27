import crypto from 'node:crypto';

const baseUrl = String(process.env.REMOTE_E2E_BASE_URL || '').replace(/\/$/, '');
const schoolId = String(process.env.REMOTE_E2E_SCHOOL_ID || '');
const parentAccount = String(process.env.REMOTE_E2E_PARENT_ACCOUNT || '');
const parentPassword = String(process.env.REMOTE_E2E_PARENT_PASSWORD || '');
const teacherAccount = String(process.env.REMOTE_E2E_TEACHER_ACCOUNT || '');
const teacherPassword = String(process.env.REMOTE_E2E_TEACHER_PASSWORD || '');
const allowWrites = String(process.env.REMOTE_E2E_ALLOW_WRITES || '') === '1';
const fixtureTaskId = String(process.env.REMOTE_E2E_TASK_ID || '');
const fixtureStudentId = String(process.env.REMOTE_E2E_STUDENT_ID || '');

if (!/^https:\/\//.test(baseUrl)) throw new Error('REMOTE_E2E_BASE_URL 必须是 HTTPS 地址');
if (!schoolId) throw new Error('缺少 REMOTE_E2E_SCHOOL_ID');
if (!parentAccount || !parentPassword) throw new Error('缺少家长专用验收账号');
if (!teacherAccount || !teacherPassword) throw new Error('缺少教师专用验收账号');
if (allowWrites && (!fixtureTaskId || !fixtureStudentId)) {
  throw new Error('写入验收只允许使用显式 REMOTE_E2E_TASK_ID 和 REMOTE_E2E_STUDENT_ID');
}

const evidence = [];
const redact = (value) => typeof value === 'string' && value.length > 12 ? `${value.slice(0, 4)}…${value.slice(-4)}` : value;
const check = (condition, name, detail = '') => {
  if (!condition) throw new Error(`${name} failed${detail ? `: ${detail}` : ''}`);
  evidence.push({ name, ok: true, detail });
};

async function request(pathname, { token, method = 'GET', body, idempotencyKey, expected = [200] } = {}) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    method,
    headers: {
      Accept: 'application/json',
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {})
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const raw = await response.text();
  let payload;
  try { payload = raw ? JSON.parse(raw) : null; } catch { throw new Error(`${method} ${pathname} returned non-JSON HTTP ${response.status}`); }
  if (!expected.includes(response.status)) {
    throw new Error(`${method} ${pathname} expected ${expected.join('/')} but got ${response.status} ${payload?.code || ''}`);
  }
  return { status: response.status, code: payload?.code, data: payload?.data, message: payload?.message };
}

async function login(account, password, expectedRole) {
  const result = await request('/v1/auth/login', { method: 'POST', body: { account, password } });
  check(Boolean(result.data?.accessToken), `${expectedRole}.login.token`);
  check(!result.data?.mfaRequired, `${expectedRole}.login.fixture-mfa`, '验收账号不得启用交互式 MFA');
  const session = await request('/v1/auth/session', { token: result.data.accessToken });
  const roles = session.data?.accountRoles || [];
  check(roles.some((item) => item.roleCode === expectedRole), `${expectedRole}.session.role`);
  check(session.data?.userId === result.data?.user?.id || Boolean(session.data?.userId), `${expectedRole}.session.user-id`);
  return { token: result.data.accessToken, session: session.data };
}

const ready = await request('/readyz');
check(ready.data?.database === 'up', 'service.readyz.database');
check(ready.data?.migrations?.healthy === true, 'service.readyz.migrations');

const parent = await login(parentAccount, parentPassword, 'parent');
const parentDashboard = await request(`/v1/schools/${encodeURIComponent(schoolId)}/dashboard?studentPage=1&studentPageSize=20`, { token: parent.token });
const children = parentDashboard.data?.children || [];
check(children.length > 0, 'parent.dashboard.bound-child', '专用家长账号必须预先绑定测试孩子');
const child = children[0]?.student || children[0];
check(Boolean(child?.id), 'parent.dashboard.child-id');
await request(`/v1/students/${encodeURIComponent(child.id)}/report`, { token: parent.token });
evidence.push({ name: 'parent.report.authorized', ok: true, detail: redact(child.id) });
await request(`/v1/students/${encodeURIComponent(child.id)}/courses`, { token: parent.token });
evidence.push({ name: 'parent.courses.authorized', ok: true, detail: redact(child.id) });
await request('/v1/activities', { token: parent.token });
await request('/v1/activities/registrations/history', { token: parent.token });
await request('/v1/experts', { token: parent.token });
await request('/v1/expert-appointments/history', { token: parent.token });
await request(`/v1/users/${encodeURIComponent(parent.session.userId)}/messages`, { token: parent.token });
evidence.push({ name: 'parent.read-workflows', ok: true, detail: 'report,courses,activities,experts,messages' });

const teacher = await login(teacherAccount, teacherPassword, 'teacher');
const teacherClaim = teacher.session.accountRoles.find((item) => item.roleCode === 'teacher');
check((teacherClaim?.authorizedClassIds || []).length > 0, 'teacher.session.class-scope');
check((teacherClaim?.capabilities || []).includes('VIEW_TEST_TASKS'), 'teacher.session.capability');
const teacherDashboard = await request(`/v1/schools/${encodeURIComponent(schoolId)}/dashboard?studentPage=1&studentPageSize=20`, { token: teacher.token });
check(Boolean(teacherDashboard.data), 'teacher.dashboard');
const tasks = await request(`/v1/schools/${encodeURIComponent(schoolId)}/tasks?paged=1&page=1&pageSize=20`, { token: teacher.token });
const taskRows = tasks.data?.items || tasks.data || [];
check(Array.isArray(taskRows), 'teacher.tasks.list');
const taskId = fixtureTaskId || taskRows[0]?.id;
if (taskId) {
  await request(`/v1/tasks/${encodeURIComponent(taskId)}/students?page=1&pageSize=20`, { token: teacher.token });
  evidence.push({ name: 'teacher.task-roster.authorized', ok: true, detail: redact(taskId) });
}
await request('/v1/classes/notifications/drafts', { token: teacher.token });
evidence.push({ name: 'teacher.notification-drafts.authorized', ok: true, detail: '' });

if (allowWrites) {
  const roster = await request(`/v1/tasks/${encodeURIComponent(fixtureTaskId)}/students?page=1&pageSize=100`, { token: teacher.token });
  const row = (roster.data?.items || roster.data || []).find((item) => item.studentId === fixtureStudentId);
  check(Boolean(row), 'teacher.write.fixture-row');
  const operationId = `remote-e2e-${Date.now()}-${crypto.randomUUID()}`;
  const currentStatus = row.status || 'not_checked_in';
  const update = await request(`/v1/tasks/${encodeURIComponent(fixtureTaskId)}/students/${encodeURIComponent(fixtureStudentId)}/status`, {
    token: teacher.token,
    method: 'PATCH',
    idempotencyKey: operationId,
    body: { status: currentStatus, expectedVersion: row.version, clientOperationId: operationId }
  });
  check(Number.isInteger(update.data?.version), 'teacher.write.server-version');
  const conflict = await request(`/v1/tasks/${encodeURIComponent(fixtureTaskId)}/students/${encodeURIComponent(fixtureStudentId)}/status`, {
    token: teacher.token,
    method: 'PATCH',
    idempotencyKey: `${operationId}-conflict`,
    body: { status: currentStatus, expectedVersion: row.version, clientOperationId: `${operationId}-conflict` },
    expected: [409]
  });
  check(conflict.code === 'VERSION_CONFLICT', 'teacher.write.optimistic-conflict');
}

console.log(JSON.stringify({
  ok: true,
  baseUrl,
  mode: allowWrites ? 'fixture-write' : 'read-only',
  checkedAt: new Date().toISOString(),
  evidence
}, null, 2));
