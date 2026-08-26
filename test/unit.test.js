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
import { MODEL_REGISTRY, MODEL_REGISTRY_VERSION, modelManifest } from '../src/modelRegistry.js';
import { clientIp } from '../src/request.js';
import { archiveBackup, backupArchivePrefix } from '../src/backupArchive.js';
import { postgresCliEnv } from '../src/postgresCli.js';
import { normalizePath } from '../src/observability.js';
import { assessmentStandardSnapshot, resolveAssessmentStandard } from '../src/assessmentStandards.js';

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
});

test('policy and storage boundaries reject unauthorized transitions and path traversal', async () => {
  assert.equal(taskStatusAllowed('未签到', '已签到'), true);
  assert.equal(taskStatusAllowed('未签到', '已完成'), false);
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
  assert.equal(complete.modelRegistryVersion, 'UY-MODELS-1.0');
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
