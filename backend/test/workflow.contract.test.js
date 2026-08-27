import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const openapi = await fs.readFile(new URL('../openapi.yaml', import.meta.url), 'utf8');
const server = await fs.readFile(new URL('../src/server.js', import.meta.url), 'utf8');
const authClaims = await fs.readFile(new URL('../src/authClaims.js', import.meta.url), 'utf8');
const activityRoutes = await fs.readFile(new URL('../src/routes/activities.js', import.meta.url), 'utf8');
const expertAppointmentRoutes = await fs.readFile(new URL('../src/routes/expertAppointments.js', import.meta.url), 'utf8');
const classPostRoutes = await fs.readFile(new URL('../src/routes/classPosts.js', import.meta.url), 'utf8');
const familyHealthRoutes = await fs.readFile(new URL('../src/routes/familyHealth.js', import.meta.url), 'utf8');
const courseRoutes = await fs.readFile(new URL('../src/routes/courses.js', import.meta.url), 'utf8');
const notificationRoutes = await fs.readFile(new URL('../src/routes/notifications.js', import.meta.url), 'utf8');
const notificationDelivery = await fs.readFile(new URL('../src/notificationDelivery.js', import.meta.url), 'utf8');
const privacyRoutes = await fs.readFile(new URL('../src/routes/privacy.js', import.meta.url), 'utf8');
const messageRoutes = await fs.readFile(new URL('../src/routes/messages.js', import.meta.url), 'utf8');
const supportRoutes = await fs.readFile(new URL('../src/routes/support.js', import.meta.url), 'utf8');
const productEventRoutes = await fs.readFile(new URL('../src/routes/productEvents.js', import.meta.url), 'utf8');
const contentOperationRoutes = await fs.readFile(new URL('../src/routes/contentOperations.js', import.meta.url), 'utf8');
const teacherTaskRoutes = await fs.readFile(new URL('../src/routes/teacherTasks.js', import.meta.url), 'utf8');
const fileRoutes = await fs.readFile(new URL('../src/routes/files.js', import.meta.url), 'utf8');
const remoteWorkflowSmoke = await fs.readFile(new URL('../scripts/remote-workflow-smoke.js', import.meta.url), 'utf8');
const { validateProductEventBatch } = await import('../src/routes/productEvents.js');
// Workflow assertions intentionally inspect the composed HTTP surface. Route
// modules may move independently of the entrypoint, but their validation and
// authorization rules must remain part of the same shipped service.
const routeHandlers = `${server}\n${activityRoutes}\n${expertAppointmentRoutes}\n${classPostRoutes}\n${familyHealthRoutes}\n${courseRoutes}\n${notificationRoutes}\n${privacyRoutes}\n${messageRoutes}\n${supportRoutes}\n${productEventRoutes}\n${contentOperationRoutes}\n${teacherTaskRoutes}\n${fileRoutes}`;
const jobs = await fs.readFile(new URL('../src/jobs.js', import.meta.url), 'utf8');
const schema = await fs.readFile(new URL('../db/schema.sql', import.meta.url), 'utf8');

function section(route) {
  return openapi.split(`  ${route}:\n`)[1]?.split('\n  /')[0] || '';
}

test('workflow APIs document bounded request contracts', () => {
  const expectations = [
    ['/v1/activities/{activityId}/registrations', 'required: [contactName, phone]', 'pattern: \'^1\\\\d{10}$\''],
    ['/v1/expert-appointments', 'expertId', 'slotId', 'maxLength: 1000'],
    ['/v1/courses/uploads', 'required: [attachmentName, attendanceCount]', 'maximum: 10000'],
    ['/v1/class-posts', 'required: [content]', 'maxLength: 2000'],
    ['/v1/support/messages', 'required: [content]', 'maxLength: 2000']
  ];
  for (const [route, ...needles] of expectations) {
    const body = section(route);
    assert.notEqual(body, '', `${route} must be documented`);
    for (const needle of needles) assert.ok(body.includes(needle), `${route} is missing ${needle}`);
  }
});

test('workflow handlers enforce the same server-side validation as the API contract', () => {
  assert.match(routeHandlers, /SELECT id,school_id,status,capacity,registration_start_at,registration_end_at FROM activities WHERE id=\$1/);
  assert.match(routeHandlers, /只有家庭账号可以报名活动/);
  assert.match(routeHandlers, /ACTIVITY_NOT_AVAILABLE/);
  assert.match(routeHandlers, /只有家庭账号可以预约专家/);
  assert.match(routeHandlers, /const contactName = requiredString\(input\.contactName, '联系人姓名'/);
  assert.match(routeHandlers, /const phone = assertPhone\(input\.phone\)/);
  assert.match(routeHandlers, /const expertName = input\.expertName \? requiredString\(input\.expertName, '专家'/);
  assert.match(routeHandlers, /const attendanceCount = Number\(input\.attendanceCount\)/);
  assert.match(routeHandlers, /const content = requiredString\(input\.content, '动态内容'/);
  assert.match(routeHandlers, /const content = requiredString\(input\.content, '咨询内容'/);
});

test('product events are explicit opt-in compatible and reject identity or health fields', () => {
  const body = section('/v1/mobile/events');
  assert.notEqual(body, '', 'product event endpoint must be documented');
  assert.match(body, /additionalProperties: false/);
  const now = new Date('2026-08-26T08:00:00.000Z');
  const accepted = validateProductEventBatch({ events: [{
    eventId: '11111111-1111-4111-8111-111111111111',
    eventName: 'growth_report_opened',
    coarseValue: '本周',
    platform: 'ios',
    appVersion: '1.0.0',
    clientSessionId: '22222222-2222-4222-8222-222222222222',
    occurredAt: now.toISOString()
  }] }, now);
  assert.equal(accepted.length, 1);
  assert.equal(accepted[0].clientSessionHash.length, 64);
  assert.equal('clientSessionId' in accepted[0], false);
  assert.throws(() => validateProductEventBatch({ events: [{
    eventId: '11111111-1111-4111-8111-111111111111', eventName: 'growth_report_opened',
    platform: 'android', appVersion: '1.0', clientSessionId: '22222222-2222-4222-8222-222222222222',
    occurredAt: now.toISOString(), childId: 'child-private'
  }] }, now), /不允许的字段/);
  assert.doesNotMatch(schema.split('CREATE TABLE IF NOT EXISTS product_events')[1].split(');')[0], /user_id|child_id|student_id|health/i);
  assert.match(productEventRoutes, /product-events:\$\{user\.id\}/);
});

test('consent endpoint exposes an auditable withdrawal path', () => {
  const body = section('/v1/students/{studentId}/consent');
  assert.notEqual(body, '', 'consent endpoint must be documented');
  assert.match(body, /granted: \{ type: boolean \}/);
  assert.match(routeHandlers, /const granted = input\.granted !== false/);
  assert.match(routeHandlers, /data_consent\.revoke/);
});

test('message inbox keeps receiver scope and explicit read receipts', () => {
  assert.match(messageRoutes, /receiver_user_id=\$1/);
  assert.match(messageRoutes, /parts\[2\] !== user\.id/);
  assert.match(messageRoutes, /MESSAGE_NOT_FOUND/);
  assert.match(messageRoutes, /business_route AS "businessRoute"/);
  assert.match(messageRoutes, /read_at=COALESCE\(read_at,now\(\)\)/);
});

test('mobile session claims are documented and server-owned', () => {
  const session = section('/v1/auth/session');
  assert.notEqual(session, '', 'mobile session endpoint must be documented');
  assert.match(session, /MobileAuthClaims/);
  assert.match(openapi, /authorizedClassIds/);
  assert.match(openapi, /mobileEntryAllowed/);
  assert.match(authClaims, /async function authClaimsForUser/);
  assert.match(authClaims, /user_capability_overrides/);
  assert.match(server, /createAuthClaimsService/);
  assert.match(server, /url\.pathname === '\/v1\/auth\/session'/);
});

test('public registration cannot self-provision a teacher workbench', () => {
  // A client-side role picker is only presentation. Keep the denial at the
  // HTTP boundary so a crafted registration body cannot grant school access.
  assert.match(server, /url\.pathname === '\/v1\/auth\/register'/);
  assert.match(server, /input\.roleCode && input\.roleCode !== 'parent'/);
  assert.match(server, /ROLE_PROVISION_REQUIRED/);
  assert.match(server, /const role = 'parent'/);
});

test('account deletion exposes approval, idempotency, and anonymization paths', () => {
  const self = section('/v1/me/deletion-request');
  const admin = section('/v1/admin/account-deletion-requests/{requestId}');
  assert.notEqual(self, '', 'self account deletion endpoint must be documented');
  assert.match(self, /IdempotencyKey/);
  assert.notEqual(admin, '', 'admin account deletion review endpoint must be documented');
  assert.match(admin, /enum: \[approved, rejected\]/);
  assert.match(server, /account.delete.request/);
  assert.match(server, /account\.delete\.\$\{nextStatus\}/);
  assert.match(server, /enqueueJob\('account\.anonymize'/);
  assert.match(jobs, /account.delete.completed/);
});

test('class notification drafts expose remote lifecycle and scoped delivery', () => {
  const createDraft = section('/v1/classes/notifications');
  const drafts = section('/v1/classes/notifications/drafts');
  const updateDraft = section('/v1/classes/notifications/{notificationId}');
  const sendDraft = section('/v1/classes/notifications/{notificationId}/send');
  const retryDraft = section('/v1/classes/notifications/{notificationId}/retry');
  const receipt = section('/v1/classes/notifications/{notificationId}/receipt');
  assert.notEqual(createDraft, '', 'class notification create endpoint must be documented');
  assert.notEqual(drafts, '', 'class notification drafts endpoint must be documented');
  assert.notEqual(updateDraft, '', 'class notification update endpoint must be documented');
  assert.notEqual(sendDraft, '', 'class notification send endpoint must be documented');
  assert.notEqual(retryDraft, '', 'class notification retry endpoint must be documented');
  assert.notEqual(receipt, '', 'class notification receipt endpoint must be documented');
  assert.match(createDraft, /targetClassIds/);
  assert.match(createDraft, /scheduledAt/);
  assert.match(createDraft, /parentReceiptEnabled/);
  assert.match(updateDraft, /draftVersion/);
  assert.match(updateDraft, /delete:/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS notification_receipts/);
  assert.match(routeHandlers, /notification\.receipt\.acknowledge/);
  assert.match(routeHandlers, /parent_receipt_enabled/);
  assert.match(server, /function noticeClassIds|const noticeClassIds/);
  assert.match(routeHandlers, /VERSION_CONFLICT/);
  assert.match(routeHandlers, /notification\.draft\.discard/);
  assert.match(routeHandlers, /ur\.class_id=ANY\(\$2\)/);
  assert.match(routeHandlers, /teacherClassIds\(user, schoolId\)\.includes\(classId\)/);
  assert.match(notificationRoutes, /notification\.deliver/, 'notification delivery must use the durable job outbox');
  assert.match(notificationDelivery, /idempotency-key/, 'provider delivery must be idempotent');
  assert.match(notificationDelivery, /channel !== 'in_app'/, 'in-app delivery must not depend on an external provider');
  assert.match(notificationDelivery, /WHERE NOT EXISTS/, 'worker retries must not duplicate inbox messages');
  assert.doesNotMatch(notificationRoutes, /channel !== 'in_app'\) return fail\(res, 503/, 'configured external channels must not be rejected unconditionally');
});

test('class circle exposes paged comments with ownership and attachment moderation hooks', () => {
  const comments = section('/v1/class-posts/{postId}/comments');
  assert.notEqual(comments, '', 'class post comments endpoint must be documented');
  assert.match(comments, /get:/);
  assert.match(comments, /pageSize/);
  assert.match(routeHandlers, /ownedByCurrentUser/);
  assert.match(routeHandlers, /class_post\.comment\.delete/);
  assert.match(routeHandlers, /class_post\.moderation/);
  assert.match(routeHandlers, /class_post_attachment/);
  assert.match(routeHandlers, /parentOnly,/);
  assert.match(routeHandlers, /CLASS_REQUIRED/);
  assert.match(routeHandlers, /只能向已绑定孩子所在班级发布动态/);
  assert.match(server, /hasRole, parentOnly, teacherOnly/);
  assert.match(openapi, /ownedByCurrentUser/);
  assert.match(schema, /idx_class_post_comments_post_created/);
});

test('file routes keep owner scope, content validation, and idempotent upload metadata', () => {
  assert.match(server, /handleFileRoutes/);
  assert.match(fileRoutes, /beginIdempotentRequest/);
  assert.match(fileRoutes, /FILE_TYPE_NOT_ALLOWED/);
  assert.match(fileRoutes, /FILE_SIGNATURE_INVALID/);
  assert.match(fileRoutes, /file\.owner_id !== user\.id/);
  assert.match(fileRoutes, /classPostFileVisibleToUser/);
  assert.match(fileRoutes, /Cache-Control': 'private, no-store'/);
});

test('activity lifecycle exposes list detail edit cancel history and capacity guard', () => {
  for (const route of [
    '/v1/activities',
    '/v1/activities/{activityId}',
    '/v1/activities/registrations/history',
    '/v1/activities/{activityId}/registrations/{registrationId}',
    '/v1/activities/{activityId}/registrations/{registrationId}/cancel'
  ]) {
    assert.notEqual(section(route), '', `${route} must be documented`);
  }
  assert.match(openapi, /childId: \{ type: string \}/);
  assert.match(openapi, /expectedVersion: \{ type: integer \}/);
  assert.match(routeHandlers, /ACTIVITY_FULL/);
  assert.match(routeHandlers, /ACTIVITY_REGISTRATION_CLOSED/);
  assert.match(routeHandlers, /activity\.registration\.update/);
  assert.match(routeHandlers, /activity\.registration\.cancel/);
  assert.match(routeHandlers, /报名信息已更新，请刷新后重试/);
  assert.match(section('/v1/activities/{activityId}/registrations/{registrationId}/cancel'), /expectedVersion/);
  assert.match(routeHandlers, /status NOT IN \('cancelled','rejected'\)/);
});

test('expert appointment lifecycle uses stable expert slot and appointment ids', () => {
  for (const route of [
    '/v1/experts',
    '/v1/experts/{expertId}',
    '/v1/experts/{expertId}/available-slots',
    '/v1/expert-appointments/history',
    '/v1/expert-appointments/{appointmentId}/reschedule',
    '/v1/expert-appointments/{appointmentId}/cancel'
  ]) {
    assert.notEqual(section(route), '', `${route} must be documented`);
  }
  assert.match(openapi, /slotId: \{ type: string \}/);
  assert.match(openapi, /expertId: \{ type: string \}/);
  assert.match(openapi, /required: \[slotId\]/);
  assert.match(routeHandlers, /SLOT_FULL/);
  assert.match(routeHandlers, /VERSION_CONFLICT/);
  assert.match(routeHandlers, /expert\.appointment\.reschedule/);
  assert.match(routeHandlers, /expert\.appointment\.cancel/);
  assert.match(routeHandlers, /预约已更新，请刷新后重试/);
  assert.match(section('/v1/expert-appointments/{appointmentId}/cancel'), /expectedVersion/);
  assert.match(routeHandlers, /FOR UPDATE/);
});

test('class circle documents commercial moderation attachments and actions', () => {
  for (const route of [
    '/v1/class-posts',
    '/v1/class-posts/{postId}',
    '/v1/class-posts/{postId}/comments',
    '/v1/class-posts/{postId}/report',
    '/v1/class-posts/{postId}/pin'
  ]) {
    assert.notEqual(section(route), '', `${route} must be documented`);
  }
  assert.match(openapi, /attachments:/);
  assert.match(openapi, /visibilityScope/);
  assert.match(openapi, /displayName/);
  assert.match(openapi, /authorRole/);
  assert.match(routeHandlers, /authorRole/);
  assert.match(routeHandlers, /moderation_status/);
  assert.match(routeHandlers, /class_post_reports/);
  assert.match(routeHandlers, /class_post_comments/);
  assert.match(routeHandlers, /class_post\.pin/);
  assert.match(routeHandlers, /deleted_at/);
  assert.match(routeHandlers, /classPostVisibleToUser/);
  assert.match(routeHandlers, /FILE_NOT_READY/);
  assert.match(routeHandlers, /class_post\.comment\.delete/);
  assert.match(routeHandlers, /class_post\.moderation/);
  assert.match(openapi, /comments\/\{commentId\}/);
  assert.match(openapi, /admin\/class-posts\/\{postId\}\/moderation/);
});

test('family health observations are structured and child-scoped', () => {
  const route = section('/v1/students/{studentId}/health-observations');
  assert.notEqual(route, '', 'health observation endpoint must be documented');
  assert.match(route, /questionId/);
  assert.match(route, /selectedOptionIds/);
  assert.match(route, /formVersion/);
  assert.match(route, /questionType/);
  assert.match(route, /enum: \[single, multiple, frequency, severity, text\]/);
  assert.match(route, /expectedVersion/);
  assert.match(routeHandlers, /family_health_observations/);
  assert.match(routeHandlers, /只有已绑定监护人可以查看家庭观察记录/);
  assert.match(routeHandlers, /只有已绑定监护人可以提交家庭观察记录/);
  assert.match(server, /async function guardianStudentForUser/);
  assert.match(server, /parent_student_bindings/);
  assert.match(routeHandlers, /guardianStudentForUser\(user, parts\[2\]\)/);
  assert.match(routeHandlers, /家庭观察记录已在其他设备更新/);
  assert.match(routeHandlers, /family_health_observation\.upsert/);
});

test('guided training sessions are structured, child-scoped, and never accept raw media', () => {
  const route = section('/v1/students/{studentId}/training-sessions');
  assert.notEqual(route, '', 'training session endpoint must be documented');
  for (const field of ['sessionId', 'dayId', 'completionRatio', 'qualityScore', 'modelVersion', 'visualUnits']) {
    assert.match(route, new RegExp(field), `${field} must be documented`);
  }
  assert.match(routeHandlers, /training_sessions/);
  assert.match(routeHandlers, /guardianStudentForUser\(user, parts\[2\]\)/);
  assert.match(routeHandlers, /跟练记录编号已被占用/);
  assert.match(routeHandlers, /training_session\.upsert/);
  assert.doesNotMatch(server, /cameraFrame|rawVideo|rawPhoto/);
});

test('content operations publish immutable mobile manifests with scoped versions', () => {
  for (const route of [
    '/v1/mobile/content-manifest',
    '/v1/admin/content/releases',
    '/v1/admin/content/releases/{releaseId}/items',
    '/v1/admin/content/releases/{releaseId}/publish',
    '/v1/admin/content/releases/{releaseId}/withdraw'
  ]) assert.notEqual(section(route), '', `${route} must be documented`);
  assert.match(contentOperationRoutes, /content_release_items/);
  assert.match(contentOperationRoutes, /CONTENT_RELEASE_EMPTY/);
  assert.match(contentOperationRoutes, /schoolAllowed\(user, schoolId\)/);
  assert.match(contentOperationRoutes, /beginIdempotentRequest/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS content_releases/);
});

test('family exercise check-ins are date-scoped, versioned, and child-authorized', () => {
  const route = section('/v1/students/{studentId}/health-checkins');
  assert.notEqual(route, '', 'health check-in endpoint must be documented');
  for (const field of ['checkInDate', 'activityType', 'durationMinutes', 'intensity', 'completedRecommended', 'parentNote', 'expectedVersion']) {
    assert.match(route, new RegExp(field), `${field} must be documented`);
  }
  assert.match(routeHandlers, /health_checkins/);
  assert.match(routeHandlers, /只有家庭账号可以提交运动打卡/);
  assert.match(routeHandlers, /不能记录未来日期/);
  assert.match(routeHandlers, /打卡已在其他设备更新/);
  assert.match(routeHandlers, /health_checkin\.upsert/);
  assert.match(schema, /UNIQUE\(user_id, child_id, check_in_date\)/);
});

test('remote workflow acceptance follows the real session schema and exercises isolated lifecycles', () => {
  assert.match(remoteWorkflowSmoke, /ready\.data\?\.migration\?\.healthy/);
  assert.doesNotMatch(remoteWorkflowSmoke, /ready\.data\?\.migrations/);
  assert.match(remoteWorkflowSmoke, /session\.data\?\.user\?\.id/);
  assert.doesNotMatch(remoteWorkflowSmoke, /session\.data\?\.userId/);
  assert.doesNotMatch(remoteWorkflowSmoke, /parent\.session\.userId/);
  assert.match(remoteWorkflowSmoke, /REMOTE_E2E_ALLOW_LIFECYCLE_WRITES/);
  assert.match(remoteWorkflowSmoke, /parent\.activity\.lifecycle/);
  assert.match(remoteWorkflowSmoke, /parent\.appointment\.lifecycle/);
  assert.match(remoteWorkflowSmoke, /parent\.activity\.optimistic-conflict/);
  assert.match(remoteWorkflowSmoke, /parent\.appointment\.optimistic-conflict/);
  assert.match(remoteWorkflowSmoke, /expected: \[409\]/);
});
