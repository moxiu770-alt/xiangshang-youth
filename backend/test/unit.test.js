import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { test } from 'node:test';
import { assertEnum, assertPassword, assertPhone, requiredString } from '../src/validation.js';
import { taskStatusAllowed } from '../src/policy.js';
import { MOVEMENT_ITEM_CODES, evaluateMovementScores, normalizeScoreRows } from '../src/scoring.js';
import { scorePostureSnapshots } from '../src/postureScoring.js';
import { scoreGrowth } from '../src/growthScoring.js';
import { createStorage } from '../src/storage.js';
import { MODEL_CALIBRATION, MODEL_CALIBRATION_STATUS, MODEL_CALIBRATION_VERSION } from '../src/modelCalibration.js';
import { MODEL_REGISTRY, MODEL_REGISTRY_VERSION, modelManifest, postureClassificationIsPublished } from '../src/modelRegistry.js';
import { clientIp } from '../src/request.js';
import { archiveBackup, backupArchivePrefix } from '../src/backupArchive.js';
import { postgresCliEnv, postgresDatabaseName } from '../src/postgresCli.js';
import { normalizePath } from '../src/observability.js';
import { assessmentStandardSnapshot, resolveAssessmentStandard } from '../src/assessmentStandards.js';
import { fieldReadiness } from '../src/fieldReadiness.js';
import { summarizeFieldOperations } from '../src/fieldOperationsSummary.js';
import { normalizeFieldTaskItems, normalizeStationItemCode, scoreScopeDifference, stationTaskCompatibility } from '../src/fieldTaskScope.js';
import { dateOnlyText } from '../src/dateOnly.js';
import { BASELINE_ASSESSMENT_PROTOCOL_ITEMS, baselineAssessmentProtocolSnapshot, protocolSnapshotFromTask } from '../src/assessmentProtocols.js';
import { decryptPushToken, encryptPushToken, pushTokenHash } from '../src/pushTokens.js';

test('push installation tokens are encrypted, authenticated and provider-scoped', () => {
  const secret = 'unit-test-push-token-encryption-key-32-bytes';
  const token = 'device-token-with-sufficient-length-1234567890';
  const encrypted = encryptPushToken(token, secret);
  assert.notEqual(encrypted, token);
  assert.equal(decryptPushToken(encrypted, secret), token);
  assert.notEqual(pushTokenHash('apns', token), pushTokenHash('fcm', token));
  const tampered = encrypted.split('.');
  tampered[2] = `${tampered[2][0] === 'A' ? 'B' : 'A'}${tampered[2].slice(1)}`;
  assert.throws(() => decryptPushToken(tampered.join('.'), secret), /无法解密/);
  assert.throws(() => encryptPushToken(token, 'short'), /加密密钥未配置/);
});

test('baseline field protocol preserves the fixed seven-action complete-lane order', () => {
  const snapshot = baselineAssessmentProtocolSnapshot(MOVEMENT_ITEM_CODES);
  assert.equal(snapshot.items.length, 7);
  assert.deepEqual(snapshot.items.map((item) => item.code), MOVEMENT_ITEM_CODES);
  assert.deepEqual(snapshot.items.map((item) => item.sequenceNo), [1, 2, 3, 4, 5, 6, 7]);
  assert.ok(BASELINE_ASSESSMENT_PROTOCOL_ITEMS.every((item) => item.required));
  assert.deepEqual(protocolSnapshotFromTask({ items: MOVEMENT_ITEM_CODES }).items.map((item) => item.name), MOVEMENT_ITEM_CODES);
});

test('date-only database values keep their calendar day across JSON boundaries', () => {
  assert.equal(dateOnlyText('2026-08-27'), '2026-08-27');
  assert.equal(dateOnlyText(new Date(2026, 7, 27)), '2026-08-27');
  assert.equal(dateOnlyText('not-a-date'), null);
});

test('client IP trusts a forwarding header only behind an explicit trusted proxy', () => {
  const request = { socket: { remoteAddress: '172.18.0.5' }, headers: { 'x-forwarded-for': '203.0.113.8, 172.18.0.1' } };
  assert.equal(clientIp(request), '172.18.0.5');
  assert.equal(clientIp(request, { trustProxy: true }), '203.0.113.8');
  assert.equal(clientIp({ socket: { remoteAddress: '127.0.0.1' }, headers: { 'x-forwarded-for': 'not-an-ip' } }, { trustProxy: true }), '127.0.0.1');
});

test('backup archive writes a checksum manifest to a bounded object prefix', async () => {
  const source = '/tmp/xiangshang-backup-archive-unit.dump';
  try {
    await fs.writeFile(source, 'backup-content');
    const uploads = [];
    const manifest = await archiveBackup({ storage: { put: async (...args) => uploads.push(args) }, filePath: source, prefix: 'xiangshang/database', createdAt: '2026-01-01T00:00:00.000Z' });
    assert.equal(manifest.objectKey, 'xiangshang/database/xiangshang-backup-archive-unit.dump');
    assert.equal(manifest.bytes, 14);
    assert.equal(uploads.length, 2);
    assert.equal(uploads[1][0], `${manifest.objectKey}.manifest.json`);
    assert.throws(() => backupArchivePrefix('../escape'));
  } finally { await fs.rm(source, { force: true }); }
});

test('PostgreSQL CLI receives connection parts without forwarding the database URL', () => {
  const environment = postgresCliEnv('postgresql://backup_user:p%40ssword@[2001:db8::7]:6432/xiangshang?sslmode=verify-full&application_name=backup-drill', { PATH: '/usr/bin', DATABASE_URL: 'must-not-be-forwarded' });
  assert.equal(environment.PGHOST, '2001:db8::7');
  assert.equal(environment.PGPORT, '6432');
  assert.equal(environment.PGDATABASE, 'xiangshang');
  assert.equal(environment.PGUSER, 'backup_user');
  assert.equal(environment.PGPASSWORD, 'p@ssword');
  assert.equal(environment.PGSSLMODE, 'verify-full');
  assert.equal(environment.PGAPPNAME, 'backup-drill');
  assert.equal(environment.DATABASE_URL, undefined);
  assert.equal(postgresDatabaseName('postgresql://backup_user:p%40ssword@db.example.test:6432/restore%5Fverify'), 'restore_verify');
  assert.throws(() => postgresCliEnv('https://database.example.test/app'), /postgres/i);
});

test('metrics route normalization never keeps UUIDs as high-cardinality labels', () => {
  assert.equal(normalizePath('/v1/files/550e8400-e29b-41d4-a716-446655440000/content?download=1'), '/v1/files/:id/content');
  assert.equal(normalizePath('/v1/field/sessions/0123456789abcdef0123456789abcdef'), '/v1/field/sessions/:id');
});

test('assessment standards resolve an effective configuration and retain a safe baseline', async () => {
  const context = { schoolId: 'school-1', gradeId: 'grade-3', region: '山区', povertyArea: true, testDate: '2027-03-03', fallbackVersion: '任务标准 v1' };
  const baseline = assessmentStandardSnapshot(null, context);
  assert.equal(baseline.source, 'baseline');
  assert.equal(baseline.standardVersion, '任务标准 v1');
  const configured = await resolveAssessmentStandard({ query: async () => ({ rows: [{ id: 'standard-1', schoolId: 'school-1', gradeId: 'grade-3', region: '山区', povertyArea: true, standardVersion: '山区三年级 v2', ruleConfig: { itemCount: 7 }, reportConfig: { template: 'A' }, courseConfig: {} , effectiveDate: '2027-03-01' }] }) }, context);
  assert.equal(configured.id, 'standard-1');
  assert.equal(configured.standardVersion, '山区三年级 v2');
  assert.equal(configured.source, 'configured');
});

test('central validation accepts bounded values and rejects unsafe input', () => {
  assert.equal(requiredString('  任务  ', '标题'), '任务');
  assert.equal(assertPhone('13800000000'), '13800000000');
  assert.equal(assertPassword('ChangeMe123!'), 'ChangeMe123!');
  assert.equal(assertEnum('teacher', ['parent', 'teacher'], '角色'), 'teacher');
  assert.throws(() => assertPhone('not-a-phone'), { code: 'PHONE_INVALID' });
  assert.throws(() => requiredString({ value: '任务' }, '标题'), { code: 'INVALID_ARGUMENT' });
  assert.throws(() => assertPhone(13800000000), { code: 'INVALID_ARGUMENT' });
  assert.throws(() => assertPassword({ value: 'ChangeMe123!' }), { code: 'PASSWORD_INVALID' });
  assert.throws(() => assertPassword('short'), { code: 'PASSWORD_INVALID' });
  assert.throws(() => assertEnum('root', ['parent', 'teacher'], '角色'), { code: 'INVALID_ARGUMENT' });
});

test('field task scope prevents dispatching or completing work at the wrong project station', () => {
  const fullTask = normalizeFieldTaskItems(MOVEMENT_ITEM_CODES);
  assert.deepEqual(fullTask, MOVEMENT_ITEM_CODES);
  assert.equal(stationTaskCompatibility(null, fullTask).compatible, true);
  assert.equal(stationTaskCompatibility('连续双脚障碍跳', ['连续双脚障碍跳']).compatible, true);
  assert.equal(stationTaskCompatibility('连续双脚障碍跳', fullTask).compatible, false);
  assert.equal(stationTaskCompatibility('run', fullTask).mode, 'invalid_station');
  assert.equal(normalizeStationItemCode('all'), null);
  assert.throws(() => normalizeStationItemCode('run'), { code: 'FIELD_STATION_ITEM_INVALID' });
  assert.throws(() => normalizeFieldTaskItems(['连续双脚障碍跳', '自定义项目']), { code: 'FIELD_TASK_ITEMS_INVALID' });
  assert.deepEqual(scoreScopeDifference(['连续双脚障碍跳', '侧向滑步'], ['连续双脚障碍跳']), {
    expected: ['连续双脚障碍跳', '侧向滑步'], missing: ['侧向滑步'], unexpected: []
  });
});

test('field readiness exposes an actionable checklist without weakening the formal gate', () => {
  const blocked = fieldReadiness({ device_type: 'edge_host', control_state: 'running', station_id: 'station-1', health_json: {} }, { id: 'station-1', status: 'offline' }, null);
  assert.equal(blocked.ready, false);
  assert.ok(blocked.blockers.includes('尚未下发有效标定配置'));
  assert.equal(blocked.checks.find((item) => item.key === 'station_online').status, 'blocked');
  assert.match(blocked.checks.find((item) => item.key === 'station_online').remediation, /Windows 场地端/);
  assert.match(blocked.checks.find((item) => item.key === 'capture_adapter').remediation, /采集设备.*DLL/);
  assert.equal(blocked.checks.find((item) => item.key === 'calibration_check').status, 'pending');

  const checksum = 'a'.repeat(64);
  const healthyDevice = {
    device_type: 'edge_host', control_state: 'running', station_id: 'station-1', status: 'online', last_heartbeat_at: '2026-08-28T00:00:30Z',
    health_json: {
      schemaVersion: 'field-health/v1',
      selfTest: { passed: true, completedAt: '2026-08-28T00:00:00Z' },
      capture: { adapterReady: true, adapterName: 'certified/1.0', depthCameraCount: 2, rgbCameraCount: 1, gpuReady: true, frameSyncOffsetMs: 10 },
      storage: { freeMb: 10_240 },
      calibration: { passed: true, version: 'CAL-1', checksumSha256: checksum, errorCm: 2 },
      emergencyStop: false
    }
  };
  const ready = fieldReadiness(healthyDevice, { id: 'station-1', status: 'online' }, { version: 'CAL-1', checksumSha256: checksum }, { now: new Date('2026-08-28T00:01:00Z') });
  assert.equal(ready.ready, true);
  assert.deepEqual(ready.blockers, []);
  assert.ok(ready.checks.length >= 10);
  assert.ok(ready.checks.every((item) => item.status === 'passed'));

  const stale = fieldReadiness(healthyDevice, { id: 'station-1', status: 'online' }, { version: 'CAL-1', checksumSha256: checksum }, { now: new Date('2026-08-28T00:03:00Z') });
  assert.equal(stale.ready, false);
  assert.equal(stale.checks.find((item) => item.key === 'device_online').status, 'blocked');
  assert.match(stale.checks.find((item) => item.key === 'device_online').detail, /90 秒/);
  const deploymentThreshold = fieldReadiness(healthyDevice, { id: 'station-1', status: 'online' }, { version: 'CAL-1', checksumSha256: checksum }, { now: new Date('2026-08-28T00:01:01Z'), heartbeatMaxAgeSeconds: 30 });
  assert.equal(deploymentThreshold.ready, false);
  assert.match(deploymentThreshold.checks.find((item) => item.key === 'device_online').detail, /30 秒/);
  const malformedHeartbeat = fieldReadiness({ ...healthyDevice, last_heartbeat_at: 'not-a-date' }, { id: 'station-1', status: 'online' }, { version: 'CAL-1', checksumSha256: checksum }, { now: new Date('2026-08-28T00:01:00Z') });
  assert.equal(malformedHeartbeat.checks.find((item) => item.key === 'device_online').status, 'blocked');

  const mismatch = fieldReadiness(healthyDevice, { id: 'station-1', status: 'online' }, { version: 'CAL-2', checksumSha256: 'b'.repeat(64) }, { now: new Date('2026-08-28T00:01:00Z') });
  assert.equal(mismatch.ready, false);
  assert.equal(mismatch.checks.find((item) => item.key === 'calibration_version').status, 'blocked');
  assert.equal(mismatch.checks.find((item) => item.key === 'calibration_checksum').status, 'blocked');
});

test('field operations summary exposes the real task queue device runway on the admin home page', () => {
  const now = new Date('2026-08-28T00:01:00Z');
  const checksum = 'a'.repeat(64);
  const device = {
    id: 'device-1', name: 'A 区采集主机', deviceCode: 'EDGE-A-01', stationName: 'A 区测试点', signedRequestReady: true,
    status: 'online', controlState: 'running', stationId: 'station-1', stationStatus: 'online', deviceType: 'edge_host', lastHeartbeatAt: '2026-08-28T00:00:30Z',
    activeCalibrationVersion: 'CAL-1', activeCalibrationChecksumSha256: checksum,
    health: {
      schemaVersion: 'field-health/v1', selfTest: { passed: true, completedAt: '2026-08-28T00:00:00Z' },
      capture: { adapterReady: true, adapterName: 'certified/1.0', depthCameraCount: 2, rgbCameraCount: 1, gpuReady: true, frameSyncOffsetMs: 10 },
      storage: { freeMb: 10_240 }, calibration: { passed: true, version: 'CAL-1', checksumSha256: checksum, errorCm: 2 }, emergencyStop: false
    }
  };
  const queue = { publishedTaskCount: 3, selectedTaskId: 'task-1', selectedTaskTitle: '秋季体测', selectedTaskDate: '2026-08-28', activeQueueCount: 8, waitingCount: 6, testingCount: 1, overdueCount: 0 };
  const ready = summarizeFieldOperations({ devices: [device], queue, now });
  assert.equal(ready.state, 'ready');
  assert.equal(ready.onlineDevices, 1);
  assert.equal(ready.readyDevices, 1);
  assert.equal(ready.activeQueueCount, 8);
  assert.equal(ready.publishedTaskCount, 3);
  assert.equal(ready.selectedTaskId, 'task-1');
  assert.equal(ready.selectedTaskTitle, '秋季体测');
  assert.equal(ready.selectedTaskDate, '2026-08-28');
  assert.match(ready.message, /秋季体测/);
  assert.equal(ready.primaryAction.target, 'queue');

  const stale = summarizeFieldOperations({ devices: [{ ...device, lastHeartbeatAt: '2026-08-27T23:55:00Z' }], queue, now });
  assert.equal(stale.state, 'offline');
  assert.equal(stale.onlineDevices, 0);
  assert.equal(stale.readyDevices, 0);
  assert.equal(stale.primaryAction.target, 'devices');
  assert.equal(stale.focusDevice.id, 'device-1');

  const noQueue = summarizeFieldOperations({ devices: [], queue: { ...queue, activeQueueCount: 0 }, now });
  assert.equal(noQueue.state, 'no_queue');
  assert.equal(noQueue.primaryAction.target, 'generate');

  const attention = summarizeFieldOperations({ devices: [device], queue: { ...queue, overdueCount: 2 }, now });
  assert.equal(attention.state, 'attention');
  assert.match(attention.message, /2 名学生/);
  assert.equal(attention.primaryAction.target, 'timing');

  const neverConnected = summarizeFieldOperations({ devices: [{ ...device, status: 'offline', lastHeartbeatAt: null, name: '首次接入主机' }], queue, now });
  assert.equal(neverConnected.neverConnectedDevices, 1);
  assert.equal(neverConnected.focusDevice.id, 'device-1');
  assert.match(neverConnected.message, /首次接入主机/);
});

test('model calibration manifest is versioned and cannot masquerade as validated', () => {
  assert.equal(MODEL_CALIBRATION.version, MODEL_CALIBRATION_VERSION);
  assert.equal(MODEL_CALIBRATION.status, MODEL_CALIBRATION_STATUS);
  assert.equal(MODEL_CALIBRATION_STATUS, 'pending-human-validation');
  assert.equal(MODEL_CALIBRATION.datasetId, null);
});

test('all model families have an immutable versioned registry entry', () => {
  assert.equal(modelManifest().version, MODEL_REGISTRY_VERSION);
  for (const family of ['movement', 'posture', 'bmi', 'height', 'followAlong', 'growth']) {
    assert.match(MODEL_REGISTRY[family].algorithmVersion, /^UY-/);
    assert.equal(MODEL_REGISTRY[family].calibrationVersion, MODEL_CALIBRATION_VERSION);
    assert.equal(MODEL_REGISTRY[family].status, 'pending-human-validation');
  }
  assert.equal(Object.keys(MODEL_REGISTRY.posture.domainValidation).length, 8);
  assert.equal(postureClassificationIsPublished(), false);
});

test('policy and storage boundaries reject unauthorized transitions and path traversal', async () => {
  assert.equal(taskStatusAllowed('未签到', '已签到'), true);
  assert.equal(taskStatusAllowed('未签到', '已完成'), false);
  assert.equal(taskStatusAllowed('未完成', '已签到'), false);
  const storage = createStorage({ storageDriver: 'local', storageRoot: '/tmp/xiangshang-unit-storage' });
  await assert.rejects(() => storage.put('../escape.txt', Buffer.from('blocked')), { code: 'FILE_PATH_INVALID' });
});

test('movement scoring normalizes malformed rows and never lets duplicates inflate a report', () => {
  const rows = [
    { item: MOVEMENT_ITEM_CODES[0], score: 6, confidence: 0.4, reviewStatus: 'passed' },
    { item: MOVEMENT_ITEM_CODES[0], score: 4.2, confidence: 0.95, reviewStatus: 'passed' },
    { item: MOVEMENT_ITEM_CODES[1], score: -1, confidence: 1, reviewStatus: 'passed' },
    { item: 'unknown-item', score: 5, confidence: 1, reviewStatus: 'passed' }
  ];
  const normalized = normalizeScoreRows(rows);
  assert.equal(normalized.length, 2);
  assert.equal(normalized[0].score, 4.2);
  assert.equal(normalized[1].score, 0);
  assert.equal(normalizeScoreRows([
    { item: MOVEMENT_ITEM_CODES[2], score: null, confidence: 1, reviewStatus: 'passed' },
    { item: MOVEMENT_ITEM_CODES[3], score: '', confidence: 1, reviewStatus: 'passed' },
    { item: MOVEMENT_ITEM_CODES[4], score: false, confidence: 1, reviewStatus: 'passed' },
    { item: MOVEMENT_ITEM_CODES[5], score: [], confidence: 1, reviewStatus: 'passed' }
  ]).length, 0);

  const complete = evaluateMovementScores(MOVEMENT_ITEM_CODES.map((item, index) => ({ item, score: index === 0 ? 2.5 : 3.5, confidence: 0.95, reviewStatus: 'passed' })));
  assert.equal(complete.modelRegistryVersion, 'UY-MODELS-1.1');
  assert.equal(complete.isComplete, true);
  assert.equal(complete.totalScore, 23.5);
  assert.equal(complete.riskLevel, 'attention');

  const lowConfidence = evaluateMovementScores(MOVEMENT_ITEM_CODES.map((item) => ({ item, score: 4, confidence: 0.7, reviewStatus: 'passed' })));
  assert.equal(lowConfidence.requiresReview, true);
  assert.equal(lowConfidence.scores.every((row) => row.reviewStatus === 'pendingReview'), true);
  assert.equal(lowConfidence.riskLevel, 'unavailable');
  const humanApproved = evaluateMovementScores(MOVEMENT_ITEM_CODES.map((item) => ({ item, score: 4, confidence: 0.7, reviewStatus: 'passed', humanReviewed: true })));
  assert.equal(humanApproved.riskLevel, 'low');
  assert.equal(humanApproved.requiresReview, false);
  const humanReviewedButPending = evaluateMovementScores(MOVEMENT_ITEM_CODES.map((item) => ({ item, score: 4, confidence: 0.95, reviewStatus: 'pendingReview', humanReviewed: true })));
  assert.equal(humanReviewedButPending.riskLevel, 'unavailable');
  assert.equal(humanReviewedButPending.requiresReview, true);
  assert.equal(humanReviewedButPending.scores.every((row) => row.reviewStatus === 'pendingReview'), true);

  const missingEvidence = evaluateMovementScores(MOVEMENT_ITEM_CODES.map((item) => ({ item, score: 4, reviewStatus: 'passed' })));
  assert.equal(missingEvidence.scores.every((row) => row.confidence === 0 && row.reviewStatus === 'pendingReview'), true);
  assert.equal(missingEvidence.riskLevel, 'unavailable');
});

test('movement scoring fails closed on an unknown review status', () => {
  const result = evaluateMovementScores(MOVEMENT_ITEM_CODES.map((item) => ({
    item, score: 5, confidence: 0.99, reviewStatus: 'not-a-real-state'
  })));
  assert.equal(result.riskLevel, 'unavailable');
  assert.equal(result.scores.every((row) => row.reviewStatus === 'pendingReview'), true);
});

test('malformed posture metrics fail closed instead of becoming zero evidence', () => {
  const report = scorePostureSnapshots([
    { captureTask: 'standingBack', sampleCount: 12, confidence: 0.9, metrics: { shoulderHeightDifferenceCm: [] } },
    { captureTask: 'forwardBend', sampleCount: 12, confidence: 0.9, metrics: { spinalMidlineDeviationCm: 0 } },
    { captureTask: 'seatedPosture', sampleCount: 12, confidence: 0.9, metrics: { spinalMidlineDeviationCm: 0 } },
    { captureTask: 'gaitVideo', sampleCount: 12, confidence: 0.9, metrics: { gaitTrunkSwayCm: 0 } }
  ], 120);
  assert.equal(report.complete, false);
  assert.equal(report.overallLevel, 'pending');
});

test('malformed growth totals fail closed instead of triggering a score-based plan', () => {
  const report = scoreGrowth({ totalScore: [], checkInDates: [], planDates: [], now: new Date('2026-08-22T00:00:00+08:00') });
  assert.equal(report.planTitle, '轻量习惯计划');
  assert.equal(report.assessmentCount, 0);
});

test('S3-compatible storage signs and routes object operations', async () => {
  const calls = [];
  const previousFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    calls.push({ url: String(url), options });
    return new Response(options.method === 'GET' ? Buffer.from('hello') : null, { status: 200 });
  };
  try {
    const storage = createStorage({
      storageDriver: 's3',
      storageEndpoint: 'https://objects.example.test',
      storageBucket: 'xiangshang',
      storageAccessKey: 'access',
      storageSecretKey: 'secret',
      storageRegion: 'auto'
    });
    await storage.put('reports/student-1.txt', Buffer.from('hello'), 'text/plain');
    assert.equal((await storage.get('reports/student-1.txt')).toString(), 'hello');
    await storage.remove('reports/student-1.txt');
    assert.equal(calls.length, 3);
    assert.ok(calls.every((call) => call.options.headers.authorization.startsWith('AWS4-HMAC-SHA256 ')));
    assert.ok(calls[0].url.endsWith('/xiangshang/reports/student-1.txt'));
  } finally {
    globalThis.fetch = previousFetch;
  }
});

test('Tencent COS uses the required virtual-hosted S3 endpoint', async () => {
  const calls = [];
  const previousFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    calls.push({ url: String(url), options });
    return new Response(null, { status: 200 });
  };
  try {
    const storage = createStorage({
      storageDriver: 's3',
      storageEndpoint: 'https://cos.ap-guangzhou.myqcloud.com',
      storageBucket: 'xiangshang-evidence-1250000000',
      storageAccessKey: 'access',
      storageSecretKey: 'secret',
      storageRegion: 'ap-guangzhou'
    });
    await storage.put('evidence/student-1.json', Buffer.from('{}'), 'application/json');
    assert.equal(calls[0].url, 'https://xiangshang-evidence-1250000000.cos.ap-guangzhou.myqcloud.com/evidence/student-1.json');
    assert.equal(calls[0].options.headers.host, 'xiangshang-evidence-1250000000.cos.ap-guangzhou.myqcloud.com');
    assert.match(calls[0].options.headers.authorization, /\/ap-guangzhou\/s3\/aws4_request/);
  } finally {
    globalThis.fetch = previousFetch;
  }
});
