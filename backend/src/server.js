import http from 'node:http';
import crypto from 'node:crypto';
import { createReadStream } from 'node:fs';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, URL } from 'node:url';
import { assertServerRuntimeConfig, config } from './config.js';
import { pool, query } from './db.js';
import { logger, metricsText, recordMetric, recordRequest } from './observability.js';
import { enqueueJob, jobWorkerStatus, startJobWorker, stopJobWorker } from './jobs.js';
import { hasRole, parentOnly, schoolAllowed, schoolStaffAllowed, taskStatusAllowed, teacherClassIds, teacherOnly } from './policy.js';
import { createStorage } from './storage.js';
import { MOVEMENT_ALGORITHM_VERSION, MOVEMENT_ITEM_CODES, MOVEMENT_SCORE_RULES, evaluateMovementScores, normalizeReviewStatus, normalizeScore, normalizeTotalScore, normalizeConfidence, normalizeScoreRows } from './scoring.js';
import { normalizeFieldTaskItems, normalizeStationItemCode, scoreScopeDifference, stationTaskCompatibility } from './fieldTaskScope.js';
import { protocolSnapshotFromTask, protocolTaskItems, resolveAssessmentProtocol } from './assessmentProtocols.js';
import { POSTURE_ALGORITHM_VERSION } from './postureScoring.js';
import { finiteScalar, publicationSafeBodyReport, scoreBodyAssessment } from './bodyScoring.js';
import { MODEL_CALIBRATION_VERSION } from './modelCalibration.js';
import { validateMarkerPnpProfile } from './mobileCaptureCalibration.js';
import { MODEL_REGISTRY_VERSION } from './modelRegistry.js';
import { ageMonthsFromBirthDate } from './age.js';
import { assertPassword, assertPhone, requiredString } from './validation.js';
import { clientIp } from './request.js';
import { resolveAssessmentStandard } from './assessmentStandards.js';
import { createRecoveryCodes, createTotpSecret, decryptMfaSecret, encryptMfaSecret, normalizeRecoveryCode, recoveryCodeHash, verifyTotp } from './mfa.js';
import { auditEvent } from './audit.js';
import { decryptFieldDeviceSigningSecret, encryptFieldDeviceSigningSecret } from './deviceAuth.js';
import { readMigrationHealth } from './migrationHealth.js';
import { refreshReportForStudent } from './reportRefresh.js';
import { normalizeStudentImportRows } from './studentImport.js';
import { handleActivityRoutes } from './routes/activities.js';
import { handleExpertAppointmentRoutes } from './routes/expertAppointments.js';
import { handleClassPostRoutes } from './routes/classPosts.js';
import { handleFamilyHealthRoutes } from './routes/familyHealth.js';
import { handleCourseRoutes } from './routes/courses.js';
import { handleNotificationRoutes } from './routes/notifications.js';
import { handlePrivacyRoutes } from './routes/privacy.js';
import { handleMessageRoutes } from './routes/messages.js';
import { handleDeviceInstallationRoutes } from './routes/deviceInstallations.js';
import { handleSupportRoutes } from './routes/support.js';
import { handleProductEventRoutes } from './routes/productEvents.js';
import { handleContentOperationRoutes } from './routes/contentOperations.js';
import { handleTeacherTaskRoutes } from './routes/teacherTasks.js';
import { handleFieldDeviceRoutes } from './routes/fieldDevice.js';
import { handleFieldAdminRoutes } from './routes/fieldAdmin.js';
import { createAuthClaimsService } from './authClaims.js';
import { handleFileRoutes } from './routes/files.js';
import { fieldReadiness } from './fieldReadiness.js';
import { summarizeFieldOperations } from './fieldOperationsSummary.js';
import { dateOnlyText } from './dateOnly.js';
import { BODY_SCREENING_DECISION_POLICY_VERSION, containsRawMedia, decideBodyScreening } from './bodyScreeningDecision.js';
import { bodyScreeningEvidenceMetrics, sanitizeHouseholdBodyMetrics } from './bodyScreeningEvidence.js';
import { abortFieldSession, appendFieldSessionEvents, completeFieldSession, configureFieldSessionService, effectiveDate, ensureFieldQueue, fieldBootstrap, fieldInputString, fieldIsoDate, fieldObject, fieldQueueStatusMap, openFieldSession, operationalTaskOrder, rebalanceFieldQueue, transitionFieldQueue, validTaskCompletionPredicate } from './fieldSessionService.js';

const { port, isProduction, accessTokenTtlMinutes, refreshTokenTtlDays, maxSessionsPerUser, mfaEncryptionKey, verificationCodePepper, requireMfaForPrivileged, auditLogSigningKey, requireHealthConsent, healthRetentionDays, allowPublicRegistration, smsWebhookUrl, smsWebhookAuthorization, wechatAppId, wechatAppSecret, wechatRedirectUri, oauthStateTtlSeconds, corsOrigin, trustProxy, metricsToken, jobWorkerEnabled, jobWorkerMode, jobWorkerIntervalMs, jobWorkerShutdownTimeoutMs, fieldDeviceKeyTtlDays, fieldDeviceSigningEncryptionKey, fieldDeviceSignedRequestsRequired, fieldDeviceSignatureMaxAgeSeconds, fieldDeviceOfflineAfterSeconds, fieldEvidenceVideoRetentionDays, fieldEvidenceDerivedRetentionDays, workerHeartbeatMaxAgeSeconds, backupEnabled, backupIntervalSeconds, backupHeartbeatMaxAgeSeconds } = config;
assertServerRuntimeConfig();
const evaluateFieldReadiness = (device, station, calibration, options = {}) => fieldReadiness(device, station, calibration, { ...options, heartbeatMaxAgeSeconds: fieldDeviceOfflineAfterSeconds });
const storage = createStorage(config);
const fieldClientReleaseDir = path.resolve(process.env.FIELD_CLIENT_RELEASE_DIR || fileURLToPath(new URL('../storage/releases/', import.meta.url)));
const fieldClientArchiveName = 'xiangshang-field-client-windows-x64.zip';
const fieldClientManifestPath = path.join(fieldClientReleaseDir, 'field-client-release.json');
const fieldClientArchivePath = path.join(fieldClientReleaseDir, fieldClientArchiveName);

const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
  ...(corsOrigin ? { 'Access-Control-Allow-Origin': corsOrigin, Vary: 'Origin' } : {}),
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, Idempotency-Key, X-Request-Id, X-Device-Id, X-Device-Key, X-Device-Timestamp, X-Device-Nonce, X-Device-Body-Hash, X-Device-Signature',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  ...(corsOrigin && corsOrigin !== '*' ? { 'Access-Control-Allow-Credentials': 'true' } : {})
};

const send = (res, status, body) => {
  res.writeHead(status, jsonHeaders);
  res.end(JSON.stringify(body));
};

const ok = (res, data) => send(res, 200, { code: 'OK', message: 'success', data });
const created = (res, data) => send(res, 201, { code: 'OK', message: 'created', data });
const accepted = (res, data) => send(res, 202, { code: 'OK', message: 'accepted', data });
const fail = (res, status, code, message, data = null) => send(res, status, { code, message, data });

const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const randomToken = () => crypto.randomBytes(32).toString('base64url');
const wechatConfigured = Boolean(wechatAppId && wechatAppSecret && wechatRedirectUri);
const oauthStateHash = (value) => sha256(`oauth-state:${value}`);
const oauthString = (value, field, max = 512) => {
  const normalized = String(value || '').trim();
  if (!normalized || normalized.length > max) throw Object.assign(new Error(`${field}不能为空`), { status: 400, code: 'INVALID_ARGUMENT' });
  return normalized;
};
const fetchJsonWithTimeout = async (url, timeoutMs = 8_000) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { headers: { Accept: 'application/json' }, signal: controller.signal });
    const payload = await response.json();
    if (!response.ok) throw Object.assign(new Error(`OAuth provider returned ${response.status}`), { status: 502, code: 'OAUTH_PROVIDER_UNAVAILABLE' });
    return payload;
  } catch (error) {
    if (error.code) throw error;
    throw Object.assign(new Error('微信授权服务暂时不可用'), { status: 502, code: 'OAUTH_PROVIDER_UNAVAILABLE' });
  } finally { clearTimeout(timeout); }
};

const refreshCookieName = isProduction ? '__Host-xiangshang_refresh' : 'xiangshang_refresh';
const cookieOptions = (maxAge) => `HttpOnly; SameSite=Lax; Path=/; Max-Age=${maxAge}${isProduction ? '; Secure' : ''}`;
const setRefreshCookie = (res, token, maxAge) => res.setHeader('Set-Cookie', `${refreshCookieName}=${encodeURIComponent(token)}; ${cookieOptions(maxAge)}`);
const clearRefreshCookie = (res) => res.setHeader('Set-Cookie', `${refreshCookieName}=; ${cookieOptions(0)}`);
const parseCookies = (req) => Object.fromEntries(String(req.headers.cookie || '').split(';').map((part) => part.trim().split('=')).filter(([key, value]) => key && value).map(([key, value]) => [key, decodeURIComponent(value)]));

const requestId = (req) => {
  if (!req._requestId) {
    const supplied = String(req.headers['x-request-id'] || '');
    req._requestId = /^[a-zA-Z0-9._:-]{1,100}$/.test(supplied) ? supplied : crypto.randomUUID();
  }
  return req._requestId;
};

const scrypt = (password, salt) => new Promise((resolve, reject) => {
  crypto.scrypt(password, salt, 64, (error, derived) => error ? reject(error) : resolve(derived.toString('hex')));
});

const hashPassword = async (password) => {
  const salt = crypto.randomBytes(16).toString('hex');
  return `scrypt$${salt}$${await scrypt(password, salt)}`;
};

const verifyPassword = async (password, encoded) => {
  if (!encoded?.startsWith('scrypt$')) return false;
  const [, salt, expected] = encoded.split('$');
  if (!salt || !expected || expected.length !== 128) return false;
  const actual = await scrypt(password, salt);
  return crypto.timingSafeEqual(Buffer.from(actual, 'hex'), Buffer.from(expected, 'hex'));
};

const body = async (req) => {
  let raw = '';
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 2_000_000) throw Object.assign(new Error('请求体过大'), { status: 413, code: 'BODY_TOO_LARGE' });
  }
  if (!raw) return {};
  try { return JSON.parse(raw); } catch { throw Object.assign(new Error('请求体不是有效 JSON'), { status: 400, code: 'INVALID_JSON' }); }
};

const canonicalize = (value) => {
  if (Array.isArray(value)) return `[${value.map(canonicalize).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalize(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
};
const requestBodyHash = (value) => sha256(canonicalize(value));
const noticeClassIds = (input = {}) => {
  const raw = Array.isArray(input.targetClassIds) && input.targetClassIds.length
    ? input.targetClassIds
    : Array.isArray(input.classIds) && input.classIds.length
      ? input.classIds
      : input.classId
        ? [input.classId]
        : [];
  return [...new Set(raw.map((item) => String(item || '').trim()).filter(Boolean))];
};

const rawBody = async (req, maxBytes = 20_000_000) => {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > maxBytes) throw Object.assign(new Error('文件过大'), { status: 413, code: 'FILE_TOO_LARGE' });
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
};

const pagination = (url, max = 100) => {
  const page = Math.max(1, Number.parseInt(queryValue(url, 'page') || '1', 10) || 1);
  const pageSize = Math.min(max, Math.max(1, Number.parseInt(queryValue(url, 'pageSize') || '20', 10) || 20));
  return { page, pageSize, offset: (page - 1) * pageSize, paged: queryValue(url, 'paged') === '1' };
};

const listResult = (url, rows, total) => {
  const page = pagination(url);
  return page.paged ? { items: rows, page: page.page, pageSize: page.pageSize, total } : rows;
};

const safeFileName = (value) => String(value || 'file').replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 120);
const maxUploadBytes = 20 * 1024 * 1024;
const allowedContentTypes = new Set(['application/pdf', 'text/plain', 'image/jpeg', 'image/png', 'video/mp4', ...(isProduction ? [] : ['application/octet-stream'])]);
const fileSignatureMatches = (bytes, contentType) => {
  if (contentType === 'image/png') return bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  if (contentType === 'image/jpeg') return bytes.subarray(0, 3).equals(Buffer.from([255, 216, 255]));
  if (contentType === 'application/pdf') return bytes.subarray(0, 5).toString() === '%PDF-';
  if (contentType === 'video/mp4') return bytes.subarray(4, 8).toString() === 'ftyp';
  if (contentType === 'text/plain') return !bytes.includes(0) && !bytes.toString('utf8').includes('\uFFFD');
  return !isProduction && contentType === 'application/octet-stream';
};
const maskPhone = (value) => {
  const phone = String(value || '');
  return phone.length >= 7 ? `${phone.slice(0, 3)}****${phone.slice(-4)}` : '已隐藏';
};

async function fieldClientRelease() {
  try {
    const [rawManifest, archive] = await Promise.all([
      fs.readFile(fieldClientManifestPath, 'utf8'),
      fs.stat(fieldClientArchivePath)
    ]);
    const manifest = JSON.parse(rawManifest);
    const sha = String(manifest.sha256 || '').toLowerCase();
    const version = String(manifest.version || '').trim();
    if (manifest.fileName !== fieldClientArchiveName || !/^\d+\.\d+\.\d+(?:[-+][a-zA-Z0-9.-]+)?$/.test(version) || !/^[a-f0-9]{64}$/.test(sha) || !archive.isFile()) {
      throw new Error('Windows 场地端发布清单无效');
    }
    return {
      available: true,
      version,
      platform: String(manifest.platform || 'Windows 10/11 x64'),
      runtime: String(manifest.runtime || 'win-x64 self-contained'),
      sizeBytes: archive.size,
      sha256: sha,
      generatedAt: manifest.generatedAt || archive.mtime.toISOString(),
      unsigned: manifest.unsigned !== false,
      downloadUrl: `/downloads/${fieldClientArchiveName}`,
      executable: 'FieldClient.Windows.exe'
    };
  } catch (error) {
    if (error.code !== 'ENOENT') logger.warn('field_client.release_unavailable', { error: error.message });
    return {
      available: false,
      version: null,
      platform: 'Windows 10/11 x64',
      runtime: 'win-x64 self-contained',
      sizeBytes: 0,
      sha256: null,
      generatedAt: null,
      unsigned: true,
      downloadUrl: null,
      executable: 'FieldClient.Windows.exe'
    };
  }
}

const pathParts = (url) => url.pathname.split('/').filter(Boolean).map(decodeURIComponent);
const queryValue = (url, key) => url.searchParams.get(key) || undefined;

async function consumePersistentRateLimit(key, windowMs, max) {
  const keyHash = sha256(`${key}:${windowMs}:${max}`);
  const result = await query(`INSERT INTO auth_rate_limits(key_hash,window_started_at,request_count,updated_at)
    VALUES($1,now(),1,now())
    ON CONFLICT(key_hash) DO UPDATE SET
      window_started_at=CASE WHEN auth_rate_limits.window_started_at <= now() - ($2::bigint * interval '1 millisecond') THEN now() ELSE auth_rate_limits.window_started_at END,
      request_count=CASE WHEN auth_rate_limits.window_started_at <= now() - ($2::bigint * interval '1 millisecond') THEN 1 ELSE auth_rate_limits.request_count + 1 END,
      updated_at=now()
    RETURNING request_count, EXTRACT(EPOCH FROM (window_started_at + ($2::bigint * interval '1 millisecond') - now()))::int AS remaining_seconds`, [keyHash, windowMs]);
  const row = result.rows[0];
  return { allowed: Number(row.request_count) <= max, retryAfter: Math.max(1, Number(row.remaining_seconds) || 1), keyHash };
}

const clearPersistentRateLimit = (keyHash) => query('DELETE FROM auth_rate_limits WHERE key_hash=$1', [keyHash]);

const verificationCodeHash = (phone, purpose, code) => crypto.createHmac('sha256', verificationCodePepper).update(`${phone}:${purpose}:${code}`).digest('hex');

async function deliverVerificationCode(phone, purpose, code, expiresAt) {
  if (!smsWebhookUrl) throw Object.assign(new Error('短信服务尚未配置，请联系学校管理员或稍后重试'), { status: 503, code: 'SMS_SERVICE_NOT_CONFIGURED' });
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8_000);
  try {
    const response = await fetch(smsWebhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(smsWebhookAuthorization ? { Authorization: smsWebhookAuthorization } : {})
      },
      body: JSON.stringify({ phone, purpose, code, expiresAt: expiresAt.toISOString() }),
      signal: controller.signal
    });
    if (!response.ok) throw Object.assign(new Error('短信服务暂时不可用，请稍后重试'), { status: 503, code: 'SMS_DELIVERY_FAILED' });
  } catch (error) {
    if (error?.code === 'SMS_DELIVERY_FAILED') throw error;
    throw Object.assign(new Error('短信服务暂时不可用，请稍后重试'), { status: 503, code: 'SMS_DELIVERY_FAILED' });
  } finally { clearTimeout(timer); }
}

async function issueVerificationCode(phone, purpose, req) {
  const code = String(crypto.randomInt(100_000, 1_000_000));
  const expiresAt = new Date(Date.now() + 5 * 60_000);
  await deliverVerificationCode(phone, purpose, code, expiresAt);
  await query('UPDATE auth_verification_codes SET consumed_at=now() WHERE phone=$1 AND purpose=$2 AND consumed_at IS NULL', [phone, purpose]);
  await query('INSERT INTO auth_verification_codes(phone,purpose,code_hash,expires_at,request_ip) VALUES($1,$2,$3,$4,$5)', [phone, purpose, verificationCodeHash(phone, purpose, code), expiresAt, clientIp(req, { trustProxy })]);
  return expiresAt;
}

async function consumeVerificationCode(phone, purpose, suppliedCode) {
  const code = String(suppliedCode || '').trim();
  if (!/^\d{6}$/.test(code)) throw Object.assign(new Error('请输入 6 位短信验证码'), { status: 400, code: 'VERIFICATION_CODE_INVALID' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(`SELECT id,code_hash,expires_at,attempts FROM auth_verification_codes
      WHERE phone=$1 AND purpose=$2 AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1 FOR UPDATE`, [phone, purpose]);
    const record = result.rows[0];
    if (!record || new Date(record.expires_at) <= new Date()) {
      if (record) await client.query('UPDATE auth_verification_codes SET consumed_at=now() WHERE id=$1', [record.id]);
      await client.query('COMMIT');
      throw Object.assign(new Error('验证码无效或已过期，请重新获取'), { status: 400, code: 'VERIFICATION_CODE_EXPIRED' });
    }
    if (Number(record.attempts) >= 5 || record.code_hash !== verificationCodeHash(phone, purpose, code)) {
      await client.query('UPDATE auth_verification_codes SET attempts=attempts+1,consumed_at=CASE WHEN attempts+1>=5 THEN now() ELSE consumed_at END WHERE id=$1', [record.id]);
      await client.query('COMMIT');
      throw Object.assign(new Error('验证码错误，请重新输入'), { status: 400, code: 'VERIFICATION_CODE_INVALID' });
    }
    await client.query('UPDATE auth_verification_codes SET consumed_at=now() WHERE id=$1', [record.id]);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally { client.release(); }
}

async function beginIdempotentRequest(req, user, res, requestHash) {
  const rawKey = req.headers['idempotency-key'];
  if (!rawKey) return null;
  if (String(rawKey).length > 128) {
    fail(res, 400, 'IDEMPOTENCY_KEY_INVALID', '幂等键不能超过 128 个字符');
    return false;
  }
  const userId = user?.id || null;
  const keyHash = sha256(`${userId || 'public'}:${rawKey}`);
  const claim = await query(`INSERT INTO idempotency_keys(key_hash,user_id,request_hash,status,response_json,locked_at,expires_at)
    VALUES($1,$2,$3,'processing','{}'::jsonb,now(),now()+interval '10 minutes')
    ON CONFLICT(key_hash) DO UPDATE SET status='processing',locked_at=now(),expires_at=now()+interval '10 minutes'
      WHERE idempotency_keys.request_hash=$3 AND (idempotency_keys.status='failed' OR idempotency_keys.expires_at<=now())
    RETURNING status,response_json`, [keyHash, userId, requestHash]);
  if (claim.rows[0]) {
    req._idempotencyKeyHash = keyHash;
    return { keyHash, userId };
  }
  const existing = await query('SELECT status,response_json,request_hash FROM idempotency_keys WHERE key_hash=$1', [keyHash]);
  const cached = existing.rows[0];
  if (cached?.request_hash && cached.request_hash !== requestHash) {
    fail(res, 409, 'IDEMPOTENCY_KEY_REUSED', '幂等键已用于其他请求内容');
    return false;
  }
  if (cached?.status === 'succeeded' && cached.response_json?.body) {
    send(res, cached.response_json.status, cached.response_json.body);
  } else {
    fail(res, 409, 'IDEMPOTENCY_IN_PROGRESS', '相同请求正在处理中，请稍后重试');
  }
  return false;
}

async function commitIdempotentRequest(meta, user, status, responseBody) {
  if (!meta) return;
  await query(`UPDATE idempotency_keys SET status='succeeded',response_json=$1,response_status=$2,locked_at=NULL,expires_at=now()+interval '24 hours'
    WHERE key_hash=$3 AND (user_id=$4 OR ($4::text IS NULL AND user_id IS NULL))`, [JSON.stringify({ status, body: responseBody }), status, meta.keyHash, meta.userId ?? user?.id ?? null]);
}

async function failIdempotently(req, res, status, code, message) {
  const responseBody = { code, message, data: null };
  if (req._idempotencyKeyHash) {
    await query(`UPDATE idempotency_keys SET status='failed',response_json=$1,response_status=$2,locked_at=NULL,expires_at=now()+interval '10 minutes'
      WHERE key_hash=$3`, [JSON.stringify({ status, body: responseBody }), status, req._idempotencyKeyHash])
      .catch((error) => logger.warn('idempotency.release_failed', { requestId: requestId(req), error: error.message }));
    req._idempotencyKeyHash = null;
  }
  return send(res, status, responseBody);
}

async function createdIdempotently(res, user, meta, data) {
  const responseBody = { code: 'OK', message: 'created', data };
  await commitIdempotentRequest(meta, user, 201, responseBody);
  return send(res, 201, responseBody);
}

async function okIdempotently(res, user, meta, data) {
  const responseBody = { code: 'OK', message: 'success', data };
  await commitIdempotentRequest(meta, user, 200, responseBody);
  return send(res, 200, responseBody);
}

async function acceptedIdempotently(res, user, meta, data) {
  const responseBody = { code: 'OK', message: 'accepted', data };
  await commitIdempotentRequest(meta, user, 202, responseBody);
  return send(res, 202, responseBody);
}

async function currentUser(req) {
  const auth = req.headers.authorization || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) return null;
  const result = await query(
    `SELECT u.id, u.phone, u.name, u.status, s.expires_at, s.id AS session_id
       FROM refresh_sessions s JOIN users u ON u.id = s.user_id
      WHERE (s.access_token_hash = $1 OR (s.access_token_hash IS NULL AND s.token_hash = $1))
        AND s.revoked_at IS NULL AND COALESCE(s.access_expires_at,s.expires_at) > now() AND u.status = 'active'`,
    [sha256(token)]
  );
  if (!result.rows[0]) return null;
  void query('UPDATE refresh_sessions SET last_used_at=now() WHERE id=$1', [result.rows[0].session_id]).catch((error) => logger.warn('session.last_used_failed', { requestId: requestId(req), error: error.message }));
  const roleResult = await query(
    `SELECT r.code, ur.school_id, ur.class_id
       FROM user_roles ur JOIN roles r ON r.id = ur.role_id
       LEFT JOIN schools scoped_school ON scoped_school.id = ur.school_id
      WHERE ur.user_id = $1 AND (ur.school_id IS NULL OR scoped_school.status = 'active')`,
    [result.rows[0].id]
  );
  return { ...result.rows[0], roles: roleResult.rows };
}

async function currentFieldDevice(req) {
  const deviceId = String(req.headers['x-device-id'] || '').trim();
  const deviceKey = String(req.headers['x-device-key'] || '').trim();
  const timestamp = String(req.headers['x-device-timestamp'] || '').trim();
  const nonce = String(req.headers['x-device-nonce'] || '').trim();
  const bodyHash = String(req.headers['x-device-body-hash'] || '').trim().toLowerCase();
  const signature = String(req.headers['x-device-signature'] || '').trim().toLowerCase();
  if (!deviceId) return null;
  const result = await query(`SELECT d.*,s.station_code,s.name AS station_name,s.status AS station_status
    FROM test_devices d LEFT JOIN test_stations s ON s.id=d.station_id
    WHERE d.id=$1 AND d.status <> 'disabled'
      AND (d.api_key_expires_at IS NULL OR d.api_key_expires_at>now())`, [deviceId]);
  const device = result.rows[0];
  if (!device) return null;
  if (timestamp || nonce || signature) {
    const timestampMs = Number(timestamp);
    if (!Number.isSafeInteger(timestampMs) || Math.abs(Date.now() - timestampMs) > fieldDeviceSignatureMaxAgeSeconds * 1000) return null;
    if (!/^[a-zA-Z0-9_-]{16,128}$/.test(nonce) || !/^[a-f0-9]{64}$/.test(bodyHash) || !/^[a-f0-9]{64}$/.test(signature)) return null;
    if (!device.signing_secret_encrypted) return null;
    const signed = `${req.method.toUpperCase()}\n${req.url}\n${timestamp}\n${nonce}\n${bodyHash}`;
    const signingSecret = decryptFieldDeviceSigningSecret(device.signing_secret_encrypted, fieldDeviceSigningEncryptionKey);
    const expected = crypto.createHmac('sha256', signingSecret).update(signed).digest('hex');
    if (!crypto.timingSafeEqual(Buffer.from(signature, 'hex'), Buffer.from(expected, 'hex'))) return null;
    const consumed = await query(`INSERT INTO field_device_request_nonces(device_id,nonce_hash,expires_at)
      VALUES($1,$2,now()+($3::int * interval '1 second')) ON CONFLICT(device_id,nonce_hash) DO NOTHING RETURNING device_id`, [device.id, sha256(nonce), fieldDeviceSignatureMaxAgeSeconds]);
    return consumed.rows[0] ? device : null;
  }
  if (fieldDeviceSignedRequestsRequired || !deviceKey) return null;
  return crypto.timingSafeEqual(Buffer.from(device.api_key_hash, 'hex'), Buffer.from(sha256(deviceKey), 'hex')) ? device : null;
}

async function currentWorkerHealth() {
  const local = jobWorkerStatus();
  if (jobWorkerMode !== 'external') {
    const lastRunAt = local.lastRunAt ? new Date(local.lastRunAt).getTime() : null;
    const ageSeconds = lastRunAt == null ? null : Math.max(0, Math.round((Date.now() - lastRunAt) / 1000));
    return { ...local, mode: jobWorkerMode, healthy: Boolean(local.enabled && !local.lastError), lastSeenAt: local.lastRunAt, ageSeconds };
  }
  try {
    const result = await query(`SELECT MAX(last_seen_at) AS "lastSeenAt",COUNT(*)::int AS instances
      FROM runtime_heartbeats WHERE component='worker'`);
    const row = result.rows[0];
    const lastSeenAt = row?.lastSeenAt || null;
    const ageSeconds = lastSeenAt ? Math.max(0, Math.round((Date.now() - new Date(lastSeenAt).getTime()) / 1000)) : null;
    return { ...local, mode: jobWorkerMode, healthy: ageSeconds != null && ageSeconds <= workerHeartbeatMaxAgeSeconds, lastSeenAt, ageSeconds, instances: Number(row?.instances || 0) };
  } catch (error) {
    logger.error('worker.health_query_failed', { error: error.message });
    return { ...local, mode: jobWorkerMode, healthy: false, lastSeenAt: null, ageSeconds: null, instances: 0, lastError: error.message };
  }
}

const workerMetricsText = (worker) => {
  const mode = String(worker.mode || 'unknown').replaceAll('"', '\\"');
  const age = worker.ageSeconds == null ? -1 : worker.ageSeconds;
  return `# HELP xiangshang_worker_healthy Whether the background worker is healthy (1) or stale/unavailable (0).\n# TYPE xiangshang_worker_healthy gauge\nxiangshang_worker_healthy{mode="${mode}"} ${worker.healthy ? 1 : 0}\n# HELP xiangshang_worker_heartbeat_age_seconds Age of the most recent worker heartbeat; -1 means unavailable.\n# TYPE xiangshang_worker_heartbeat_age_seconds gauge\nxiangshang_worker_heartbeat_age_seconds{mode="${mode}"} ${age}\n`;
};

async function currentBackupHealth() {
  if (!backupEnabled) return { enabled: false, healthy: true, successWithinSlo: true, lastSeenAt: null, lastSuccessAt: null, heartbeatAgeSeconds: 0, lastSuccessAgeSeconds: 0, status: 'disabled' };
  try {
    const result = await query(`SELECT last_seen_at AS "lastSeenAt",metadata_json AS metadata
      FROM runtime_heartbeats WHERE component='backup' ORDER BY last_seen_at DESC LIMIT 1`);
    const row = result.rows[0];
    const metadata = row?.metadata || {};
    const lastSeenAt = row?.lastSeenAt || null;
    const lastSuccessAt = metadata.lastSuccessAt || null;
    const heartbeatAgeSeconds = lastSeenAt ? Math.max(0, Math.round((Date.now() - new Date(lastSeenAt).getTime()) / 1000)) : null;
    const lastSuccessAgeSeconds = lastSuccessAt ? Math.max(0, Math.round((Date.now() - new Date(lastSuccessAt).getTime()) / 1000)) : null;
    const successSloSeconds = Math.max(3600, backupIntervalSeconds * 2);
    return { enabled: true, status: metadata.status || 'unknown', lastSeenAt, lastSuccessAt, heartbeatAgeSeconds, lastSuccessAgeSeconds, healthy: heartbeatAgeSeconds != null && heartbeatAgeSeconds <= backupHeartbeatMaxAgeSeconds && metadata.status !== 'failed', successWithinSlo: lastSuccessAgeSeconds != null && lastSuccessAgeSeconds <= successSloSeconds };
  } catch (error) {
    logger.error('backup.health_query_failed', { error: error.message });
    return { enabled: true, healthy: false, successWithinSlo: false, lastSeenAt: null, lastSuccessAt: null, heartbeatAgeSeconds: null, lastSuccessAgeSeconds: null, status: 'error', lastError: error.message };
  }
}

const backupMetricsText = (backup) => {
  const enabled = backup.enabled ? 'true' : 'false';
  const heartbeatAge = backup.heartbeatAgeSeconds == null ? -1 : backup.heartbeatAgeSeconds;
  const successAge = backup.lastSuccessAgeSeconds == null ? -1 : backup.lastSuccessAgeSeconds;
  return `# HELP xiangshang_backup_healthy Whether the scheduled backup executor is healthy.\n# TYPE xiangshang_backup_healthy gauge\nxiangshang_backup_healthy{enabled="${enabled}"} ${backup.healthy ? 1 : 0}\n# HELP xiangshang_backup_last_success_within_slo Whether a successful backup was completed within the configured SLO.\n# TYPE xiangshang_backup_last_success_within_slo gauge\nxiangshang_backup_last_success_within_slo{enabled="${enabled}"} ${backup.successWithinSlo ? 1 : 0}\n# HELP xiangshang_backup_heartbeat_age_seconds Age of the latest backup executor heartbeat; -1 means unavailable.\n# TYPE xiangshang_backup_heartbeat_age_seconds gauge\nxiangshang_backup_heartbeat_age_seconds{enabled="${enabled}"} ${heartbeatAge}\n# HELP xiangshang_backup_last_success_age_seconds Age of the latest successful backup; -1 means unavailable.\n# TYPE xiangshang_backup_last_success_age_seconds gauge\nxiangshang_backup_last_success_age_seconds{enabled="${enabled}"} ${successAge}\n`;
};

async function currentMigrationHealth() {
  const health = await readMigrationHealth(query);
  if (!health.healthy && health.error) logger.error('database.migration_health_query_failed', { error: health.error });
  return health;
}

const migrationMetricsText = (migration) => {
  const missing = migration.missing.length;
  const checksumMismatches = migration.checksumMismatches.length;
  return `# HELP xiangshang_database_schema_healthy Whether every migration required by this API image has been applied with its expected checksum.\n# TYPE xiangshang_database_schema_healthy gauge\nxiangshang_database_schema_healthy ${migration.healthy ? 1 : 0}\n# HELP xiangshang_database_schema_missing_migrations Number of migrations required by this API image that are missing from the database.\n# TYPE xiangshang_database_schema_missing_migrations gauge\nxiangshang_database_schema_missing_migrations ${missing}\n# HELP xiangshang_database_schema_checksum_mismatches Number of applied migrations whose checksum differs from this API image.\n# TYPE xiangshang_database_schema_checksum_mismatches gauge\nxiangshang_database_schema_checksum_mismatches ${checksumMismatches}\n`;
};

async function currentJobQueueHealth() {
  const result = await query(`SELECT status,COUNT(*)::int AS count,MIN(created_at) AS "oldestAt"
    FROM job_queue GROUP BY status`);
  const rows = new Map(result.rows.map((row) => [row.status, row]));
  return ['queued', 'processing', 'completed', 'failed'].map((status) => {
    const row = rows.get(status);
    const oldestAt = row?.oldestAt || null;
    return { status, count: Number(row?.count || 0), oldestAgeSeconds: oldestAt ? Math.max(0, Math.round((Date.now() - new Date(oldestAt).getTime()) / 1000)) : 0 };
  });
}

const jobQueueMetricsText = (jobs) => {
  const lines = ['# HELP xiangshang_job_queue_jobs Number of background jobs by state.', '# TYPE xiangshang_job_queue_jobs gauge', '# HELP xiangshang_job_queue_oldest_age_seconds Age of the oldest background job by state.', '# TYPE xiangshang_job_queue_oldest_age_seconds gauge'];
  for (const job of jobs) {
    lines.push(`xiangshang_job_queue_jobs{status="${job.status}"} ${job.count}`);
    lines.push(`xiangshang_job_queue_oldest_age_seconds{status="${job.status}"} ${job.oldestAgeSeconds}`);
  }
  return `${lines.join('\n')}\n`;
};

const fieldDeviceKeyExpiresAt = (value) => {
  const now = Date.now();
  const maximum = now + fieldDeviceKeyTtlDays * 86_400_000;
  const requested = value ? new Date(value).getTime() : maximum;
  if (!Number.isFinite(requested) || requested <= now || requested > maximum) {
    throw Object.assign(new Error(`设备密钥有效期必须在未来且不超过 ${fieldDeviceKeyTtlDays} 天`), { status: 400, code: 'FIELD_DEVICE_KEY_EXPIRY_INVALID' });
  }
  return new Date(requested);
};

// A Postgres-backed fan-out keeps device/status updates coherent when the API
// runs in more than one process.  SSE subscriptions are local, while LISTEN /
// NOTIFY moves the compact event between instances without making a browser or
// Windows client poll a shared in-memory map.
const fieldRealtimeInstanceId = crypto.randomUUID();
const fieldStreamSubscribers = new Map();
let fieldRealtimeClient = null;
const writeFieldStream = (res, event, payload) => {
  if (res.writableEnded || res.destroyed) return;
  res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
};
const dispatchFieldUpdate = (message) => {
  const subscribers = fieldStreamSubscribers.get(message.schoolId);
  if (!subscribers) return;
  for (const res of subscribers) writeFieldStream(res, message.type || 'field.update', message);
};
const publishFieldUpdate = async (schoolId, type, payload = {}) => {
  const message = { origin: fieldRealtimeInstanceId, schoolId, type, payload, at: new Date().toISOString() };
  dispatchFieldUpdate(message);
  try { await query('SELECT pg_notify($1,$2)', ['field_updates', JSON.stringify(message)]); } catch (error) { logger.warn('field.realtime_publish_failed', { schoolId, type, error: error.message }); }
};
const startFieldRealtime = async () => {
  try {
    fieldRealtimeClient = await pool.connect();
    fieldRealtimeClient.on('notification', (notification) => {
      if (notification.channel !== 'field_updates' || !notification.payload) return;
      try {
        const message = JSON.parse(notification.payload);
        if (message.origin !== fieldRealtimeInstanceId && message.schoolId) dispatchFieldUpdate(message);
      } catch (error) { logger.warn('field.realtime_payload_invalid', { error: error.message }); }
    });
    fieldRealtimeClient.on('error', (error) => logger.warn('field.realtime_listener_error', { error: error.message }));
    await fieldRealtimeClient.query('LISTEN field_updates');
  } catch (error) { logger.warn('field.realtime_listener_start_failed', { error: error.message }); }
};

const { authClaimsForUser, userHasCapability } = createAuthClaimsService({ query, hasRole });

async function authPayload(user, accessToken, refreshToken, accessExpiresAt, refreshExpiresAt) {
  return {
    accessToken,
    refreshToken,
    expiresAt: accessExpiresAt,
    refreshExpiresAt,
    ...(await authClaimsForUser(user))
  };
}

async function issueAuthSession(user, req, res) {
  const accessToken = randomToken();
  const refreshToken = randomToken();
  const accessExpiresAt = new Date(Date.now() + accessTokenTtlMinutes * 60_000);
  const refreshExpiresAt = new Date(Date.now() + refreshTokenTtlDays * 86_400_000);
  await query('INSERT INTO refresh_sessions(user_id,token_hash,access_token_hash,access_expires_at,expires_at,user_agent,ip,last_used_at) VALUES($1,$2,$3,$4,$5,$6,$7,now())', [user.id, sha256(refreshToken), sha256(accessToken), accessExpiresAt, refreshExpiresAt, req.headers['user-agent'] || null, clientIp(req, { trustProxy })]);
  await query(`UPDATE refresh_sessions SET revoked_at=now() WHERE id IN (
    SELECT id FROM refresh_sessions WHERE user_id=$1 AND revoked_at IS NULL ORDER BY created_at DESC OFFSET $2
  )`, [user.id, Math.max(0, maxSessionsPerUser)]);
  setRefreshCookie(res, refreshToken, refreshTokenTtlDays * 86_400);
  return authPayload(user, accessToken, refreshToken, accessExpiresAt, refreshExpiresAt);
}

const requireWechatConfiguration = (res) => {
  if (wechatConfigured) return true;
  fail(res, 503, 'WECHAT_NOT_CONFIGURED', '微信登录尚未配置，请使用手机号或账号密码登录');
  return false;
};

async function createWechatAuthorizationState(req) {
  const state = randomToken();
  const expiresAt = new Date(Date.now() + oauthStateTtlSeconds * 1000);
  await query(`INSERT INTO auth_oauth_states(provider,state_hash,redirect_uri,request_ip,expires_at)
    VALUES('wechat',$1,$2,$3,$4)`, [oauthStateHash(state), wechatRedirectUri, clientIp(req, { trustProxy }), expiresAt]);
  const params = new URLSearchParams({ appid: wechatAppId, redirect_uri: wechatRedirectUri, response_type: 'code', scope: 'snsapi_userinfo', state });
  return { state, expiresAt, authorizeUrl: `https://open.weixin.qq.com/connect/oauth2/authorize?${params.toString()}#wechat_redirect` };
}

async function exchangeWechatAuthorization(req, res, code, state) {
  const normalizedCode = oauthString(code, '微信授权码', 1024);
  const normalizedState = oauthString(state, '微信授权状态', 256);
  const stateRow = await query(`UPDATE auth_oauth_states SET consumed_at=now()
    WHERE provider='wechat' AND state_hash=$1 AND consumed_at IS NULL AND expires_at>now()
    RETURNING redirect_uri`, [oauthStateHash(normalizedState)]);
  if (!stateRow.rows[0]) return fail(res, 401, 'OAUTH_STATE_INVALID', '微信授权已失效，请重新开始登录');

  const tokenUrl = new URL('https://api.weixin.qq.com/sns/oauth2/access_token');
  tokenUrl.search = new URLSearchParams({ appid: wechatAppId, secret: wechatAppSecret, code: normalizedCode, grant_type: 'authorization_code' }).toString();
  const tokenPayload = await fetchJsonWithTimeout(tokenUrl);
  if (tokenPayload.errcode || !tokenPayload.access_token || !tokenPayload.openid) return fail(res, 401, 'OAUTH_CODE_INVALID', '微信授权码无效或已使用');

  const userInfoUrl = new URL('https://api.weixin.qq.com/sns/userinfo');
  userInfoUrl.search = new URLSearchParams({ access_token: tokenPayload.access_token, openid: tokenPayload.openid, lang: 'zh_CN' }).toString();
  const userInfo = await fetchJsonWithTimeout(userInfoUrl);
  if (userInfo.errcode) return fail(res, 502, 'OAUTH_PROFILE_UNAVAILABLE', '微信用户信息暂时不可用，请稍后重试');
  const subject = oauthString(userInfo.unionid || tokenPayload.unionid || tokenPayload.openid, '微信身份标识', 256);
  const displayName = String(userInfo.nickname || '微信用户').trim().slice(0, 80) || '微信用户';

  const client = await pool.connect();
  let account;
  try {
    await client.query('BEGIN');
    // Serialize the same provider subject so two callbacks cannot create two
    // family accounts during a network retry.
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`wechat:${subject}`]);
    let identity = await client.query(`SELECT u.* FROM auth_identities ai JOIN users u ON u.id=ai.user_id
      WHERE ai.provider='wechat' AND ai.subject=$1 FOR UPDATE`, [subject]);
    if (identity.rows[0] && identity.rows[0].status !== 'active') {
      throw Object.assign(new Error('该微信账号已停用，请联系学校管理员'), { status: 403, code: 'ACCOUNT_DISABLED' });
    }
    if (!identity.rows[0]) {
      const inserted = await client.query(`INSERT INTO users(phone,name,password_hash) VALUES(NULL,$1,NULL) RETURNING id,phone,name,status`, [displayName]);
      const role = await client.query("SELECT id FROM roles WHERE code='parent'");
      if (!role.rows[0]) throw Object.assign(new Error('家长角色尚未初始化'), { status: 500, code: 'ROLE_NOT_INITIALIZED' });
      await client.query('INSERT INTO user_roles(user_id,role_id) VALUES($1,$2)', [inserted.rows[0].id, role.rows[0].id]);
      await client.query(`INSERT INTO auth_identities(provider,subject,user_id,profile_json) VALUES('wechat',$1,$2,$3)`, [subject, inserted.rows[0].id, { nickname: displayName, unionid: Boolean(userInfo.unionid || tokenPayload.unionid) }]);
      identity = inserted;
    } else {
      await client.query(`UPDATE auth_identities SET profile_json=$1,updated_at=now() WHERE provider='wechat' AND subject=$2`, [{ nickname: displayName, unionid: Boolean(userInfo.unionid || tokenPayload.unionid) }, subject]);
    }
    account = identity.rows[0];
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
  await audit(account, req, 'auth.oauth.wechat.login', 'user', account.id, null, { provider: 'wechat' });
  return ok(res, await issueAuthSession(account, req, res));
}

async function createMfaChallenge(user, req, purpose = 'verify') {
  const challengeToken = randomToken();
  const expiresAt = new Date(Date.now() + (purpose === 'enroll' ? 10 : 5) * 60_000);
  await query('INSERT INTO auth_mfa_challenges(user_id,token_hash,purpose,expires_at,user_agent,ip) VALUES($1,$2,$3,$4,$5,$6)', [user.id, sha256(challengeToken), purpose, expiresAt, req.headers['user-agent'] || null, clientIp(req, { trustProxy })]);
  return { ...(purpose === 'enroll' ? { mfaEnrollmentRequired: true } : { mfaRequired: true }), challengeToken, expiresAt };
}

async function requireUser(req, res) {
  const user = await currentUser(req);
  if (!user) {
    fail(res, 401, 'AUTH_EXPIRED', '登录已过期，请重新登录');
    return null;
  }
  return user;
}

const studentRow = (row) => ({
  id: row.id,
  name: row.name,
  gender: row.gender,
  grade: row.grade_name,
  className: row.class_name,
  classId: row.class_id,
  region: row.region,
  isPovertyArea: row.is_poverty_area,
  taskStatus: row.task_status || '未签到',
  taskVersion: Number.isInteger(Number(row.task_version)) ? Number(row.task_version) : null,
  totalScore: (() => {
    if (row.total_score == null) return null;
    const value = Number(row.total_score);
    return Number.isFinite(value) ? normalizeTotalScore(value) : null;
  })(),
  birthDate: dateOnlyText(row.birth_date)
});

async function studentForUser(user, studentId) {
  const result = await query(
    `SELECT st.*, g.name AS grade_name, c.name AS class_name,
            ts.status AS task_status, dr.total_score
       FROM students st
       JOIN grades g ON g.id = st.grade_id
       JOIN classes c ON c.id = st.class_id
       LEFT JOIN LATERAL (
         SELECT status,version AS task_version FROM task_students WHERE student_id = st.id ORDER BY created_at DESC LIMIT 1
       ) ts ON true
       LEFT JOIN LATERAL (
         SELECT total_score FROM diagnosis_reports WHERE student_id = st.id AND status = 'published'
          ORDER BY generated_at DESC LIMIT 1
       ) dr ON true
      WHERE st.id = $1 AND st.status = 'active'`, [studentId]
  );
  const row = result.rows[0];
  if (!row) return null;
  if (parentOnly(user)) {
    const binding = await query(
      `SELECT 1 FROM parent_student_bindings WHERE parent_user_id = $1 AND student_id = $2 AND status = 'active'`,
      [user.id, studentId]
    );
    return binding.rowCount ? row : null;
  }
  if (hasRole(user, 'admin', 'principal') && schoolAllowed(user, row.school_id)) return row;
  if (hasRole(user, 'teacher') && schoolAllowed(user, row.school_id)) {
    return teacherClassIds(user, row.school_id).includes(row.class_id) ? row : null;
  }
  return null;
}

/**
 * Family-only health, consent and privacy records must never inherit a
 * teacher's class scope.  This is deliberately separate from studentForUser:
 * a person may have both accounts, but can only read/write a child's private
 * record when that same account has an active guardian binding.
 */
async function guardianStudentForUser(user, studentId) {
  if (!hasRole(user, 'parent')) return null;
  const binding = await query(`SELECT 1 FROM parent_student_bindings
    WHERE parent_user_id=$1 AND student_id=$2 AND status='active' LIMIT 1`, [user.id, studentId]);
  if (!binding.rowCount) return null;
  return studentForUser(user, studentId);
}

/**
 * Files referenced by a class-circle post are readable by the same scoped
 * audience as the post. A file id alone must not grant access to another
 * family's child photo, so the access check is derived from the post's
 * school/class scope instead of the uploader flag.
 */
async function classPostFileVisibleToUser(user, fileId) {
  if (hasRole(user, 'admin')) return true;
  const posts = await query(
    `SELECT * FROM class_posts
      WHERE deleted_at IS NULL
        AND (attachments @> $1::jsonb OR attachments @> $2::jsonb)
      ORDER BY created_at DESC`,
    [JSON.stringify([{ objectId: fileId }]), JSON.stringify([{ id: fileId }])]
  );
  for (const row of posts.rows) {
    if (await classPostVisibleToUser(user, row)) return true;
  }
  return false;
}

/**
 * A class-circle post is scoped by school, class, visibility and moderation.
 * This guard is shared by feed reads, comments, reports and attachment reads;
 * an opaque post/file id must never become an alternate authorization path.
 */
async function classPostVisibleToUser(user, row, { allowOwnPending = true } = {}) {
  if (!row || (row.school_id && !schoolAllowed(user, row.school_id))) return false;
  const staff = schoolStaffAllowed(user, row.school_id);
  const moderation = String(row.moderation_status || '').toLowerCase();
  const moderationVisible = ['approved', 'published'].includes(moderation);
  if (!moderationVisible && !(allowOwnPending && row.user_id === user.id) && !staff) return false;
  if (hasRole(user, 'admin', 'principal')) return true;
  if (row.visibility_scope === 'teacher_only') {
    return hasRole(user, 'teacher') && Boolean(row.class_id) && teacherClassIds(user, row.school_id).includes(row.class_id);
  }
  if (row.visibility_scope === 'school_staff') return staff;
  if (!row.class_id) return staff;
  if (hasRole(user, 'teacher')) return teacherClassIds(user, row.school_id).includes(row.class_id);
  if (hasRole(user, 'parent')) {
    const binding = await query(
      `SELECT 1 FROM parent_student_bindings pb
        JOIN students st ON st.id=pb.student_id
       WHERE pb.parent_user_id=$1 AND pb.status='active'
         AND st.class_id=$2 AND st.status='active' LIMIT 1`,
      [user.id, row.class_id]
    );
    return binding.rowCount > 0;
  }
  return false;
}

async function audit(user, req, action, resourceType, resourceId, before = null, after = null, schoolId = null) {
  return auditEvent({ operatorId: user?.id || null, schoolId, action, resourceType, resourceId, before, after, ip: clientIp(req, { trustProxy }), requestId: requestId(req) });
}

async function verifyAuditChain(schoolId) {
  if (auditLogSigningKey.length < 32) throw Object.assign(new Error('未配置 AUDIT_LOG_SIGNING_KEY，无法校验审计完整性'), { status: 503, code: 'AUDIT_INTEGRITY_UNAVAILABLE' });
  const rows = await query(`SELECT id,operator_id AS "operatorId",school_id AS "schoolId",action,resource_type AS "resourceType",resource_id AS "resourceId",
    before_json AS "before",after_json AS "after",ip,request_id AS "requestId",created_at AS "createdAt",previous_hash AS "previousHash",entry_hash AS "entryHash"
    FROM audit_logs WHERE school_id IS NOT DISTINCT FROM $1 AND entry_hash IS NOT NULL ORDER BY created_at,id`, [schoolId]);
  let previousHash = null;
  for (const row of rows.rows) {
    const record = { id: row.id, previousHash: row.previousHash || null, operatorId: row.operatorId || null, schoolId: row.schoolId || null, action: row.action, resourceType: row.resourceType, resourceId: row.resourceId || null, before: row.before || null, after: row.after || null, ip: row.ip || null, requestId: row.requestId || null, createdAt: new Date(row.createdAt).toISOString() };
    const expected = crypto.createHmac('sha256', auditLogSigningKey).update(canonicalize(record)).digest('hex');
    const expectedBytes = Buffer.from(expected, 'hex');
    const actualBytes = Buffer.from(String(row.entryHash), 'hex');
    if (record.previousHash !== previousHash || expectedBytes.length !== actualBytes.length || !crypto.timingSafeEqual(expectedBytes, actualBytes)) {
      return { valid: false, checked: rows.rows.length, failedEntryId: row.id, lastValidHash: previousHash };
    }
    previousHash = row.entryHash;
  }
  const state = await query('SELECT last_hash AS "lastHash" FROM audit_chain_state WHERE scope_key=$1', [schoolId || '__platform__']);
  return { valid: Boolean(state.rows[0] ? state.rows[0].lastHash === previousHash : rows.rows.length === 0), checked: rows.rows.length, failedEntryId: null, lastValidHash: previousHash };
}

async function dashboard(user, schoolId, options = {}) {
  if (!schoolAllowed(user, schoolId)) throw Object.assign(new Error('无权访问该学校'), { status: 403, code: 'NO_PERMISSION' });
  const isParentScope = parentOnly(user);
  const isTeacherScope = teacherOnly(user);
  const scopedClassIds = isTeacherScope ? teacherClassIds(user, schoolId) : [];
  let studentSql = `
    SELECT st.*, g.name AS grade_name, c.name AS class_name,
           ts.status AS task_status, ts.task_version, dr.total_score
      FROM students st JOIN grades g ON g.id = st.grade_id JOIN classes c ON c.id = st.class_id
    LEFT JOIN LATERAL (
      SELECT ts.status,ts.version AS task_version
        FROM task_students ts JOIN assessment_tasks task ON task.id=ts.task_id
       WHERE ts.student_id=st.id AND task.school_id=st.school_id AND task.status='published'
       ORDER BY ${operationalTaskOrder('task')},task.created_at DESC LIMIT 1
    ) ts ON true
      LEFT JOIN LATERAL (SELECT total_score FROM diagnosis_reports WHERE student_id = st.id AND status='published' ORDER BY generated_at DESC LIMIT 1) dr ON true
     WHERE st.school_id = $1 AND st.status = 'active'`;
  const studentParams = [schoolId];
  if (isParentScope) {
    studentSql += ` AND EXISTS (SELECT 1 FROM parent_student_bindings pb WHERE pb.parent_user_id=$2 AND pb.student_id=st.id AND pb.status='active')`;
    studentParams.push(user.id);
  } else if (isTeacherScope) {
    if (scopedClassIds.length) {
      studentSql += ` AND st.class_id = ANY($2)`;
      studentParams.push(scopedClassIds);
    } else {
      studentSql += ' AND FALSE';
    }
  }
  const studentPage = Number.isInteger(Number(options.studentPage)) && Number(options.studentPage) > 0 ? Number(options.studentPage) : null;
  const studentPageSize = studentPage ? Math.min(100, Math.max(1, Number(options.studentPageSize) || 20)) : null;
  const studentQuery = studentPage ? `${studentSql} ORDER BY st.name LIMIT ${studentPageSize} OFFSET ${(studentPage - 1) * studentPageSize}` : studentSql;
  const studentWhereIndex = studentSql.indexOf('WHERE st.school_id');
  const studentCountQuery = studentPage ? query(`SELECT COUNT(*)::int AS total FROM students st WHERE ${studentSql.slice(studentWhereIndex + 6)}`, studentParams) : Promise.resolve({ rows: [] });
  const gradesQuery = isParentScope
    ? query(`SELECT DISTINCT g.id,g.name,g.standard_version AS "standardVersion" FROM grades g JOIN students st ON st.grade_id=g.id JOIN parent_student_bindings pb ON pb.student_id=st.id AND pb.parent_user_id=$2 AND pb.status='active' WHERE g.school_id=$1 ORDER BY g.name`, [schoolId, user.id])
    : isTeacherScope
      ? query(`SELECT DISTINCT g.id,g.name,g.standard_version AS "standardVersion" FROM grades g JOIN classes c ON c.grade_id=g.id WHERE g.school_id=$1 AND c.id=ANY($2) ORDER BY g.name`, [schoolId, scopedClassIds.length ? scopedClassIds : ['__none__']])
      : query(`SELECT id, name, standard_version AS "standardVersion" FROM grades WHERE school_id=$1 ORDER BY name`, [schoolId]);
  const classesQuery = isParentScope
    ? query(`SELECT c.id,c.name,c.grade_id AS "gradeId",COALESCE(u.name,'未分配') AS "teacherName",COUNT(st.id)::int AS "studentCount",COALESCE(ROUND(100.0*COUNT(*) FILTER(WHERE COALESCE(ts."validCompletion",FALSE))/NULLIF(COUNT(st.id),0)),0)::int AS "completionRate"
        FROM classes c LEFT JOIN users u ON u.id=c.teacher_id JOIN students st ON st.class_id=c.id AND st.status='active' JOIN parent_student_bindings pb ON pb.student_id=st.id AND pb.parent_user_id=$2 AND pb.status='active'
        LEFT JOIN LATERAL (SELECT ${validTaskCompletionPredicate('ts', 'task')} AS "validCompletion" FROM task_students ts JOIN assessment_tasks task ON task.id=ts.task_id WHERE ts.student_id=st.id AND task.school_id=st.school_id AND task.status='published' ORDER BY ${operationalTaskOrder('task')},task.created_at DESC LIMIT 1) ts ON true WHERE c.school_id=$1 GROUP BY c.id,u.name ORDER BY c.name`, [schoolId, user.id])
    : isTeacherScope
      ? query(`SELECT c.id,c.name,c.grade_id AS "gradeId",COALESCE(u.name,'未分配') AS "teacherName",COUNT(st.id)::int AS "studentCount",COALESCE(ROUND(100.0*COUNT(*) FILTER(WHERE COALESCE(ts."validCompletion",FALSE))/NULLIF(COUNT(st.id),0)),0)::int AS "completionRate"
          FROM classes c LEFT JOIN users u ON u.id=c.teacher_id LEFT JOIN students st ON st.class_id=c.id AND st.status='active' LEFT JOIN LATERAL (SELECT ${validTaskCompletionPredicate('ts', 'task')} AS "validCompletion" FROM task_students ts JOIN assessment_tasks task ON task.id=ts.task_id WHERE ts.student_id=st.id AND task.school_id=st.school_id AND task.status='published' ORDER BY ${operationalTaskOrder('task')},task.created_at DESC LIMIT 1) ts ON true WHERE c.school_id=$1 AND c.id=ANY($2) GROUP BY c.id,u.name ORDER BY c.name`, [schoolId, scopedClassIds.length ? scopedClassIds : ['__none__']])
      : query(`SELECT c.id, c.name, c.grade_id AS "gradeId", COALESCE(u.name,'未分配') AS "teacherName",COUNT(st.id)::int AS "studentCount",COALESCE(ROUND(100.0 * COUNT(*) FILTER (WHERE COALESCE(ts."validCompletion",FALSE)) / NULLIF(COUNT(st.id),0)),0)::int AS "completionRate" FROM classes c LEFT JOIN users u ON u.id=c.teacher_id LEFT JOIN students st ON st.class_id=c.id AND st.status='active' LEFT JOIN LATERAL (SELECT ${validTaskCompletionPredicate('ts', 'task')} AS "validCompletion" FROM task_students ts JOIN assessment_tasks task ON task.id=ts.task_id WHERE ts.student_id=st.id AND task.school_id=st.school_id AND task.status='published' ORDER BY ${operationalTaskOrder('task')},task.created_at DESC LIMIT 1) ts ON true WHERE c.school_id=$1 GROUP BY c.id,u.name ORDER BY c.name`, [schoolId]);
  const tasksQuery = isParentScope
    ? query(`SELECT t.id,t.title,t.test_date::text AS date,t.location,COALESCE(g.name,'全校') AS "gradeName",COALESCE(c.name,'全校') AS "className",t.items,t.rule_version AS "ruleVersion",t.protocol_snapshot_json AS "protocolSnapshot",t.status,CASE WHEN t.class_id IS NULL THEN ARRAY[]::text[] ELSE ARRAY[t.class_id] END AS "classIds",ARRAY_AGG(DISTINCT ts.student_id) AS "studentIds",COUNT(ts.id)::int AS "totalCount",COUNT(ts.id) FILTER(WHERE ${validTaskCompletionPredicate('ts', 't')})::int AS "completedCount" FROM assessment_tasks t LEFT JOIN grades g ON g.id=t.grade_id LEFT JOIN classes c ON c.id=t.class_id JOIN task_students ts ON ts.task_id=t.id JOIN parent_student_bindings pb ON pb.student_id=ts.student_id AND pb.parent_user_id=$2 AND pb.status='active' WHERE t.school_id=$1 GROUP BY t.id,g.name,c.name,t.class_id ORDER BY ${operationalTaskOrder('t')},t.created_at DESC LIMIT 50`, [schoolId, user.id])
    : isTeacherScope
      ? query(`SELECT t.id,t.title,t.test_date::text AS date,t.location,COALESCE(g.name,'全校') AS "gradeName",COALESCE(c.name,'全校') AS "className",t.items,t.rule_version AS "ruleVersion",t.protocol_snapshot_json AS "protocolSnapshot",t.status,CASE WHEN t.class_id IS NULL THEN ARRAY[]::text[] ELSE ARRAY[t.class_id] END AS "classIds",ARRAY_AGG(DISTINCT ts.student_id) AS "studentIds",COUNT(ts.id)::int AS "totalCount",COUNT(ts.id) FILTER(WHERE ${validTaskCompletionPredicate('ts', 't')})::int AS "completedCount" FROM assessment_tasks t LEFT JOIN grades g ON g.id=t.grade_id LEFT JOIN classes c ON c.id=t.class_id JOIN task_students ts ON ts.task_id=t.id JOIN students st ON st.id=ts.student_id AND st.class_id=ANY($2) WHERE t.school_id=$1 GROUP BY t.id,g.name,c.name,t.class_id ORDER BY ${operationalTaskOrder('t')},t.created_at DESC LIMIT 50`, [schoolId, scopedClassIds.length ? scopedClassIds : ['__none__']])
      : query(`SELECT t.id,t.title,t.test_date::text AS date,t.location,COALESCE(g.name,'全校') AS "gradeName",COALESCE(c.name,'全校') AS "className",t.items,t.rule_version AS "ruleVersion",t.protocol_snapshot_json AS "protocolSnapshot",t.status,CASE WHEN t.class_id IS NULL THEN ARRAY[]::text[] ELSE ARRAY[t.class_id] END AS "classIds",COALESCE(ARRAY_AGG(DISTINCT ts.student_id) FILTER(WHERE ts.student_id IS NOT NULL), ARRAY[]::text[]) AS "studentIds",COUNT(ts.id)::int AS "totalCount",COUNT(ts.id) FILTER(WHERE ${validTaskCompletionPredicate('ts', 't')})::int AS "completedCount" FROM assessment_tasks t LEFT JOIN grades g ON g.id=t.grade_id LEFT JOIN classes c ON c.id=t.class_id LEFT JOIN task_students ts ON ts.task_id=t.id WHERE t.school_id=$1 GROUP BY t.id,g.name,c.name,t.class_id ORDER BY ${operationalTaskOrder('t')},t.created_at DESC LIMIT 50`, [schoolId]);
  const [school, grades, classes, students, studentCount, tasks, messages, bindings] = await Promise.all([
    query(`SELECT id, name, campus, region, is_poverty_area AS "isPovertyArea" FROM schools WHERE id=$1`, [schoolId]),
    gradesQuery,
    classesQuery,
    query(studentQuery, studentParams),
    studentCountQuery,
    tasksQuery,
    query(`SELECT id, title, content, to_char(created_at,'YYYY-MM-DD HH24:MI') AS time, is_read AS "isRead", category,
                    message_type AS "messageType", business_id AS "businessId", business_route AS "businessRoute",
                    child_id AS "childId", task_id AS "taskId", course_id AS "courseId", lesson_id AS "lessonId",
                    action_label AS "actionLabel", read_at AS "readAt", expires_at AS "expiresAt"
             FROM messages WHERE receiver_user_id=$1 ORDER BY created_at DESC LIMIT 50`, [user.id]),
    hasRole(user, 'parent') ? query(`SELECT b.id, b.parent_user_id AS "parentId", b.relation, st.*, g.name AS grade_name, c.name AS class_name
             FROM parent_student_bindings b JOIN students st ON st.id=b.student_id JOIN grades g ON g.id=st.grade_id JOIN classes c ON c.id=st.class_id
            WHERE b.parent_user_id=$1 AND b.status='active'`, [user.id]) : { rows: [] }
  ]);
  const schoolRow = school.rows[0] || null;
  return {
    school: schoolRow,
    grades: grades.rows,
    classes: classes.rows,
    students: students.rows.map(studentRow),
    tasks: tasks.rows.map((row) => {
      const progressStatus = row.completedCount === row.totalCount && row.totalCount > 0
        ? '已完成'
        : row.status === 'published' ? '未签到'
          : row.status === 'closed' ? '已关闭' : row.status;
      return { ...row, items: row.items || [], lifecycleStatus: row.status, progressStatus, status: progressStatus };
    }),
    parentChildren: bindings.rows.map((row) => ({ id: row.id, parentId: row.parentId, relation: row.relation, student: studentRow(row) })),
    children: bindings.rows.map((row) => ({ id: row.id, parentId: row.parentId, relation: row.relation, student: studentRow(row) })),
    messages: messages.rows,
    ...(studentPage ? { studentTotal: Number(studentCount.rows[0]?.total || 0), studentPage, studentPageSize } : {})
  };
}

async function reportFor(user, studentId) {
  const student = await studentForUser(user, studentId);
  if (!student) throw Object.assign(new Error('学生不存在或无权访问'), { status: 404, code: 'STUDENT_NOT_FOUND' });
  const result = await query(
    `SELECT rv.report_json FROM diagnosis_reports dr JOIN report_versions rv ON rv.report_id=dr.id AND rv.version=dr.published_version
      WHERE dr.student_id=$1 AND dr.status='published' ORDER BY dr.generated_at DESC LIMIT 1`, [studentId]
  );
  if (!result.rows[0]) throw Object.assign(new Error('报告尚未发布'), { status: 404, code: 'REPORT_NOT_PUBLISHED' });
  const report = result.rows[0].report_json || {};
  const evaluated = evaluateMovementScores(report.scores);
  // Re-normalize published JSON at the API boundary too. Older report
  // versions may have been generated before duplicate/low-confidence guards
  // were introduced; the family and teacher clients must see one canonical
  // seven-item interpretation regardless of report version.
  return {
    ...report,
    algorithmVersion: MOVEMENT_ALGORITHM_VERSION,
    calibrationVersion: MODEL_CALIBRATION_VERSION,
    modelRegistryVersion: MODEL_REGISTRY_VERSION,
    scores: evaluated.scores,
    scoreCompletionRatio: evaluated.scoreCompletionRatio,
    meanConfidence: evaluated.meanConfidence,
    reviewItems: evaluated.reviewItems,
    requiresReview: evaluated.requiresReview,
    totalScore: evaluated.totalScore,
    riskLevel: evaluated.riskLevel
  };
}

async function refreshReport(user, req, studentId) {
  const student = await studentForUser(user, studentId);
  if (!student) throw Object.assign(new Error('学生不存在或无权访问'), { status: 404, code: 'STUDENT_NOT_FOUND' });
  return refreshReportForStudent({ student, operatorId: user.id, requestId: requestId(req), ip: clientIp(req, { trustProxy }) });
}

async function taskStudentForUser(user, taskId, studentId) {
  const result = await query(`SELECT ts.*, t.school_id, t.rule_version, t.items, st.class_id
    FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id JOIN students st ON st.id=ts.student_id
    WHERE ts.task_id=$1 AND ts.student_id=$2`, [taskId, studentId]);
  const row = result.rows[0];
  if (!row || !schoolAllowed(user, row.school_id)) return null;
  if (parentOnly(user)) {
    const binding = await query(`SELECT 1 FROM parent_student_bindings WHERE parent_user_id=$1 AND student_id=$2 AND status='active'`, [user.id, studentId]);
    if (!binding.rowCount) return null;
  }
  if (teacherOnly(user)) {
    const classIds = teacherClassIds(user, row.school_id);
    if (!classIds.includes(row.class_id)) return null;
  }
  return row;
}

const guidedCaptureChecks = Object.freeze(['device-level', 'full-body', 'single-person', 'landmark-confidence', 'multi-frame-robust']);

function submittedCaptureTrace(snapshot) {
  const metrics = snapshot?.metrics && typeof snapshot.metrics === 'object' ? snapshot.metrics : {};
  const nested = metrics.captureMetadata && typeof metrics.captureMetadata === 'object' ? metrics.captureMetadata : {};
  const calibration = nested.calibration && typeof nested.calibration === 'object' ? nested.calibration
    : metrics.captureCalibration && typeof metrics.captureCalibration === 'object' ? metrics.captureCalibration : {};
  const checks = Array.isArray(snapshot?.qualityChecks) ? snapshot.qualityChecks
    : Array.isArray(nested.qualityChecks) ? nested.qualityChecks
      : Array.isArray(metrics.qualityChecks) ? metrics.qualityChecks : [];
  return {
    protocolVersion: String(snapshot?.captureProtocolVersion || nested.captureProtocolVersion || metrics.captureProtocolVersion || '').trim(),
    cameraFacing: String(snapshot?.cameraFacing || nested.cameraFacing || metrics.cameraFacing || '').trim(),
    qualityChecks: checks.filter((item) => typeof item === 'string').map((item) => item.trim()).filter(Boolean),
    calibration
  };
}

function validateSubmittedCaptureTrace(snapshot) {
  const trace = submittedCaptureTrace(snapshot);
  // Legacy history may not have provenance. It remains readable and is
  // explicitly labelled untraced by the scorer, but a new protocol claim is
  // never accepted without the evidence it claims to have used.
  if (!trace.protocolVersion) return;
  const guided = trace.protocolVersion.startsWith('UY-CAPTURE-GUIDED-');
  const markerPnp = trace.protocolVersion.startsWith('UY-CAPTURE-MARKER-PNP-');
  if (!guided && !markerPnp) throw Object.assign(new Error('不支持的姿态采集协议版本'), { status: 400, code: 'CAPTURE_PROTOCOL_INVALID' });
  if (trace.cameraFacing !== 'rear-1x') throw Object.assign(new Error('正式姿态采集必须使用后置 1× 镜头'), { status: 400, code: 'CAPTURE_CAMERA_INVALID' });
  if (!guidedCaptureChecks.every((check) => trace.qualityChecks.includes(check))) {
    throw Object.assign(new Error('姿态采集质量门未全部通过，请重新完成完整入镜与稳定性检查'), { status: 400, code: 'CAPTURE_QUALITY_INCOMPLETE' });
  }
  if (/^UY-CAPTURE-GUIDED-(2|3)\./.test(trace.protocolVersion) && !trace.qualityChecks.includes('two-take-repeatability')) {
    throw Object.assign(new Error('该采集协议需要两次独立记录一致性通过后才能提交'), { status: 400, code: 'CAPTURE_REPEATABILITY_INCOMPLETE' });
  }
  if (markerPnp) {
    const reprojectionErrorPx = finiteScalar(trace.calibration.reprojectionErrorPx);
    if (trace.calibration.mode !== 'marker-pnp' || trace.calibration.boardDetected !== true
      || !String(trace.calibration.boardId || '').trim() || !String(trace.calibration.intrinsicsId || '').trim()
      || !String(trace.calibration.lensId || '').trim() || !String(trace.calibration.resolution || '').trim()
      || reprojectionErrorPx == null || reprojectionErrorPx > 2) {
      throw Object.assign(new Error('标定板/PnP 证据不完整或重投影误差未达标'), { status: 400, code: 'CAPTURE_CALIBRATION_INCOMPLETE' });
    }
    const profileValidation = validateMarkerPnpProfile(trace.calibration);
    if (!profileValidation.valid) throw Object.assign(new Error(profileValidation.message), { status: 400, code: profileValidation.code });
  }
}

async function bodyAssessmentForUser(user, studentId, input, req) {
  if (!hasRole(user, 'parent')) throw Object.assign(new Error('只有家长可以提交家庭测评'), { status: 403, code: 'NO_PERMISSION' });
  const student = await guardianStudentForUser(user, studentId);
  if (!student) throw Object.assign(new Error('学生不存在或未绑定'), { status: 404, code: 'STUDENT_NOT_FOUND' });
  const consentVersion = String(input.consentVersion || 'v1');
  let consentRecord = null;
  if (requireHealthConsent) {
    const consent = await query(`SELECT id,consent_id FROM data_consents
      WHERE student_id=$1 AND parent_user_id=$2 AND purpose='body_assessment' AND consent_version=$3
        AND granted_at IS NOT NULL AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())`, [studentId, user.id, consentVersion]);
    if (!consent.rowCount) throw Object.assign(new Error('提交家庭测评前需要取得有效的数据使用同意'), { status: 403, code: 'CONSENT_REQUIRED' });
    consentRecord = consent.rows[0];
  }
  if (containsRawMedia(input)) throw Object.assign(new Error('家庭身体筛查仅接收结构化指标，禁止上传原始照片、视频或摄像头帧'), { status: 400, code: 'RAW_MEDIA_NOT_ALLOWED' });
  const height = finiteScalar(input.heightCm);
  const weight = finiteScalar(input.weightKg);
  // Keep the API boundary identical to both native clients' child-measurement
  // model. Values outside the supported child range are unavailable, not a
  // reason to generate an extreme BMI classification.
  if (!Number.isFinite(height) || height < 90 || height > 190 || !Number.isFinite(weight) || weight < 15 || weight > 90) {
    throw Object.assign(new Error('身高或体重不在有效范围'), { status: 400, code: 'MEASUREMENT_INVALID' });
  }
  const allowedCaptureTasks = new Set(['standingFront', 'standingBack', 'standingSide', 'forwardBend', 'dynamicKneeControl', 'gaitVideo', 'seatedPosture', 'footArch']);
  const rawSnapshots = Array.isArray(input.snapshots) ? input.snapshots : [];
  if (rawSnapshots.length > allowedCaptureTasks.size) throw Object.assign(new Error('姿态任务数量不合法'), { status: 400, code: 'SNAPSHOTS_INVALID' });
  const snapshots = rawSnapshots.map((snapshot) => {
    const captureTask = String(snapshot?.captureTask || '');
    const sampleCount = finiteScalar(snapshot?.sampleCount);
    const confidence = finiteScalar(snapshot?.confidence);
    if (!allowedCaptureTasks.has(captureTask) || !Number.isInteger(sampleCount) || sampleCount < 0 || sampleCount > 10000 || !Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
      throw Object.assign(new Error('姿态任务数据不合法'), { status: 400, code: 'SNAPSHOT_INVALID' });
    }
    validateSubmittedCaptureTrace(snapshot);
    return { captureTask, sampleCount, confidence, metrics: sanitizeHouseholdBodyMetrics(snapshot?.metrics, captureTask) };
  });
  if (new Set(snapshots.map((snapshot) => snapshot.captureTask)).size !== snapshots.length) throw Object.assign(new Error('姿态任务不能重复'), { status: 400, code: 'SNAPSHOT_DUPLICATE' });
  // The client may preview a level, but it cannot choose the persisted health
  // state. Re-score the normalized evidence on the server so a forged red/green
  // value or stale native implementation cannot bypass the publication gate.
  const ageMonths = ageMonthsFromBirthDate(student.birth_date);
  const candidateBodyReport = scoreBodyAssessment({ heightCm: height, weightKg: weight, ageMonths, gender: student.gender, snapshots });
  const screeningDecision = decideBodyScreening({ snapshots, postureReport: candidateBodyReport.postureReport });
  const bodyReport = publicationSafeBodyReport(candidateBodyReport);
  const { bmi, postureReport, overallLevel } = bodyReport;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const algorithmVersion = POSTURE_ALGORITHM_VERSION;
    const data = { ...(input.data && typeof input.data === 'object' && !Array.isArray(input.data) ? input.data : {}), bodyReport };
    const assessment = await client.query(`INSERT INTO body_assessments(student_id,parent_user_id,height_cm,weight_kg,bmi,overall_level,algorithm_version,consent_version,data_json,retention_until)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,now()+($10::int * interval '1 day')) RETURNING *`, [studentId, user.id, height, weight, bmi, overallLevel, algorithmVersion, consentVersion, data, healthRetentionDays]);
    for (const snapshot of snapshots) {
      await client.query(`INSERT INTO posture_snapshots(body_assessment_id,capture_task,sample_count,confidence,metrics_json)
        VALUES($1,$2,$3,$4,$5) ON CONFLICT(body_assessment_id,capture_task) DO UPDATE SET sample_count=EXCLUDED.sample_count,confidence=EXCLUDED.confidence,metrics_json=EXCLUDED.metrics_json`, [assessment.rows[0].id, snapshot.captureTask, Number(snapshot.sampleCount || 0), Number(snapshot.confidence || 0), snapshot.metrics || {}]);
    }
    const firstTrace = snapshots[0]?.metrics || {};
    const sessionStatus = screeningDecision.route === 'auto_archive' ? 'auto_archived' : screeningDecision.route;
    const screeningSession = await client.query(`INSERT INTO body_screening_sessions(student_id,guardian_user_id,consent_id,body_assessment_id,status,protocol_version,model_version,threshold_version,decision_policy_version,device_model,camera_lens,completed_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,now()) RETURNING id,status,version,completed_at AS "completedAt"`, [studentId, user.id, consentRecord?.consent_id || null, assessment.rows[0].id, sessionStatus, String(firstTrace.captureProtocolVersion || 'unknown').slice(0, 120), POSTURE_ALGORITHM_VERSION, String(candidateBodyReport.postureReport?.rulesSourceVersion || 'unknown').slice(0, 120), BODY_SCREENING_DECISION_POLICY_VERSION, String(input.data?.deviceModel || '').slice(0, 120) || null, String(firstTrace.cameraFacing || '').slice(0, 60) || null]);
    for (const snapshot of snapshots) {
      const metrics = snapshot.metrics || {};
      const attemptCount = Math.max(1, Math.min(10, Number(metrics.captureAttemptCount || 1)));
      await client.query(`INSERT INTO body_screening_attempts(session_id,capture_task,attempt_number,attempt_count,sample_count,confidence,quality_score,quality_events_json,metrics_json,repeatability_difference)
        VALUES($1,$2,$3,$3,$4,$5,$6,$7,$8,$9)`, [screeningSession.rows[0].id, snapshot.captureTask, attemptCount, snapshot.sampleCount, snapshot.confidence, candidateBodyReport.postureReport?.qualityScore ?? null, JSON.stringify(Array.isArray(metrics.qualityChecks) ? metrics.qualityChecks : []), metrics, Number.isFinite(Number(metrics.repeatabilityMaximumDifference)) ? Number(metrics.repeatabilityMaximumDifference) : null]);
    }
    const decisionRow = await client.query(`INSERT INTO body_screening_decisions(session_id,route,outcome_level,reason_codes,model_confidence,model_uncertainty,quality_score,review_required,policy_version)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id,route,outcome_level AS "outcomeLevel",reason_codes AS "reasonCodes",model_confidence AS "modelConfidence",model_uncertainty AS "modelUncertainty",quality_score AS "qualityScore",review_required AS "reviewRequired",policy_version AS "decisionPolicyVersion",version,decided_at AS "decidedAt"`, [screeningSession.rows[0].id, screeningDecision.route, screeningDecision.outcomeLevel, JSON.stringify(screeningDecision.reasonCodes), null, candidateBodyReport.postureReport?.validationStatus === 'human-validated' ? 0 : 1, candidateBodyReport.postureReport?.qualityScore ?? null, screeningDecision.reviewRequired, screeningDecision.decisionPolicyVersion]);
    if (screeningDecision.reviewRequired) await client.query(`INSERT INTO body_screening_reviews(session_id,status) VALUES($1,'pending')`, [screeningSession.rows[0].id]);
    await client.query('COMMIT');
    await audit(user, req, 'body_assessment.create', 'body_assessment', assessment.rows[0].id, null, { studentId, bmi, overallLevel, screeningRoute: screeningDecision.route }, student.school_id);
    return { ...assessment.rows[0], heightCm: Number(assessment.rows[0].height_cm), weightKg: Number(assessment.rows[0].weight_kg), bmi: Number(assessment.rows[0].bmi), snapshots, ...bodyReport, screeningSession: screeningSession.rows[0], screeningDecision: decisionRow.rows[0] };
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

configureFieldSessionService({ publishFieldUpdate, audit });

async function handle(req, res) {
  const startedAt = Date.now();
  res.setHeader('X-Request-Id', requestId(req));
  res.setHeader('X-Trace-Id', requestId(req));
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'camera=(self), microphone=(), geolocation=(), payment=(), usb=()');
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  res.once('finish', () => {
    const durationMs = Date.now() - startedAt;
    const requestPath = req.url?.split('?')[0] || '/';
    recordRequest(req.method, requestPath, res.statusCode, durationMs);
    logger.info('http.request', { requestId: requestId(req), method: req.method, path: requestPath, status: res.statusCode, durationMs });
  });
  if (req.method === 'OPTIONS') return send(res, 204, null);
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const parts = pathParts(url);
  try {
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/admin')) {
      const html = await fs.readFile(new URL('../public/index.html', import.meta.url), 'utf8');
      res.setHeader('Content-Security-Policy', "default-src 'self'; style-src 'self'; style-src-attr 'unsafe-inline'; script-src 'self'; script-src-attr 'none'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'");
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(html);
    }
    if (req.method === 'GET' && ['/admin.css', '/admin.js', '/field-operations-policy.js', '/admin-enhancements.js', '/admin-workspaces.js', '/content-operations.css', '/content-operations.js', '/commercial-polish.css'].includes(url.pathname)) {
      const assetName = url.pathname.slice(1);
      const asset = await fs.readFile(new URL(`../public/${assetName}`, import.meta.url));
      const contentType = assetName.endsWith('.css') ? 'text/css; charset=utf-8' : 'text/javascript; charset=utf-8';
      res.setHeader('Cache-Control', 'no-cache');
      res.writeHead(200, { 'Content-Type': contentType });
      return res.end(asset);
    }
    if (req.method === 'GET' && url.pathname === '/v1/public/field-client-release') return ok(res, await fieldClientRelease());
    if ((req.method === 'GET' || req.method === 'HEAD') && url.pathname === `/downloads/${fieldClientArchiveName}`) {
      const release = await fieldClientRelease();
      if (!release.available) return fail(res, 404, 'FIELD_CLIENT_RELEASE_NOT_FOUND', 'Windows 场地端安装包尚未生成');
      res.writeHead(200, {
        'Content-Type': 'application/zip',
        'Content-Length': String(release.sizeBytes),
        'Content-Disposition': `attachment; filename="${fieldClientArchiveName}"`,
        'Cache-Control': 'private, no-cache',
        'X-Checksum-Sha256': release.sha256
      });
      if (req.method === 'HEAD') return res.end();
      const stream = createReadStream(fieldClientArchivePath);
      stream.once('error', (error) => {
        logger.error('field_client.download_failed', { requestId: requestId(req), error: error.message });
        res.destroy(error);
      });
      stream.pipe(res);
      return;
    }
    if (req.method === 'GET' && url.pathname === '/favicon.ico') return send(res, 204, null);
    if (req.method === 'GET' && url.pathname === '/metrics') {
      if (metricsToken && req.headers.authorization !== `Bearer ${metricsToken}`) return fail(res, 401, 'METRICS_UNAUTHORIZED', '指标接口未授权');
      const [worker, jobs, backup, migration] = await Promise.all([currentWorkerHealth(), currentJobQueueHealth(), currentBackupHealth(), currentMigrationHealth()]);
      res.writeHead(200, { 'Content-Type': 'text/plain; version=0.0.4; charset=utf-8', 'Cache-Control': 'no-store' });
      return res.end(`${metricsText()}${workerMetricsText(worker)}${jobQueueMetricsText(jobs)}${backupMetricsText(backup)}${migrationMetricsText(migration)}`);
    }
    if (req.method === 'GET' && url.pathname === '/livez') return ok(res, { service: 'xiangshang-youth-api', status: 'alive' });
    if (req.method === 'GET' && (url.pathname === '/health' || url.pathname === '/readyz')) {
      await query('SELECT 1');
      const [worker, migration] = await Promise.all([currentWorkerHealth(), currentMigrationHealth()]);
      const data = { service: 'xiangshang-youth-api', database: 'up', migration, worker, time: new Date().toISOString() };
      if (!migration.healthy) return send(res, 503, { code: 'SERVICE_NOT_READY', message: '数据库迁移未完成，服务尚未就绪', data });
      return ok(res, data);
    }
    if (req.method === 'POST' && url.pathname === '/v1/auth/oauth/wechat/start') {
      if (!requireWechatConfiguration(res)) return;
      const limit = await consumePersistentRateLimit(`oauth:wechat:${clientIp(req, { trustProxy })}`, 60_000, 10);
      if (!limit.allowed) { res.setHeader('Retry-After', String(limit.retryAfter)); return fail(res, 429, 'RATE_LIMITED', '授权请求过于频繁，请稍后重试'); }
      return ok(res, await createWechatAuthorizationState(req));
    }
    if (req.method === 'GET' && url.pathname === '/v1/auth/oauth/wechat/callback') {
      if (!requireWechatConfiguration(res)) return;
      const code = queryValue(url, 'code');
      const state = queryValue(url, 'state');
      if (!code || !state) return fail(res, 400, 'OAUTH_CALLBACK_INVALID', '微信回调缺少授权参数');
      // The provider callback is a short-lived relay. The one-time code and
      // state are exchanged by the native client over HTTPS; no session or
      // user data is ever placed in this redirect.
      const relay = new URL('xiangshang-youth://open');
      relay.search = new URLSearchParams({ target: 'wechat-callback', code, state }).toString();
      res.writeHead(302, { Location: relay.toString(), 'Cache-Control': 'no-store' });
      return res.end();
    }
    if (req.method === 'POST' && url.pathname === '/v1/auth/oauth/wechat/exchange') {
      if (!requireWechatConfiguration(res)) return;
      const input = await body(req);
      return exchangeWechatAuthorization(req, res, input.code, input.state);
    }
    if (req.method === 'POST' && url.pathname === '/v1/auth/verification-codes') {
      const input = await body(req);
      const phone = assertPhone(input.phone || input.account);
      const purpose = String(input.purpose || '');
      if (!['login', 'register', 'reset-password'].includes(purpose)) return fail(res, 400, 'VERIFICATION_PURPOSE_INVALID', '验证码用途不支持');
      const limit = await consumePersistentRateLimit(`sms:${purpose}:${clientIp(req, { trustProxy })}:${phone}`, 10 * 60_000, 3);
      if (!limit.allowed) {
        res.setHeader('Retry-After', String(limit.retryAfter));
        return fail(res, 429, 'RATE_LIMITED', '验证码请求过于频繁，请稍后重试');
      }
      const expiresAt = await issueVerificationCode(phone, purpose, req);
      return accepted(res, { purpose, expiresAt });
    }
    if (req.method === 'POST' && url.pathname === '/v1/auth/register') {
      if (!allowPublicRegistration) return fail(res, 403, 'PUBLIC_REGISTRATION_DISABLED', '当前学校未开放自助注册，请联系学校管理员开通账号');
      const input = await body(req);
      const phone = assertPhone(input.phone || input.account);
      const name = requiredString(input.name, '姓名', { max: 80 });
      const password = assertPassword(input.password);
      if (input.roleCode && input.roleCode !== 'parent') return fail(res, 403, 'ROLE_PROVISION_REQUIRED', '教师和学校管理账号须由学校管理员创建');
      const registrationKey = `${clientIp(req, { trustProxy })}:${input.phone}`;
      const registrationLimit = await consumePersistentRateLimit(registrationKey, 60_000, 5);
      if (!registrationLimit.allowed) {
        res.setHeader('Retry-After', String(registrationLimit.retryAfter));
        return fail(res, 429, 'RATE_LIMITED', '注册请求过于频繁，请稍后重试');
      }
      const idempotency = await beginIdempotentRequest(req, null, res, requestBodyHash({ phone, name, schoolId: input.schoolId || null, verificationCode: input.verificationCode || '' }));
      if (idempotency === false) return;
      await consumeVerificationCode(phone, 'register', input.verificationCode);
      const existing = await query('SELECT id FROM users WHERE phone=$1', [phone]);
      if (existing.rowCount) return failIdempotently(req, res, 409, 'ACCOUNT_EXISTS', '该手机号已注册，请直接登录或重置密码');
      const role = 'parent';
      const roleRow = await query('SELECT id FROM roles WHERE code=$1', [role]);
      if (!roleRow.rows[0]) return fail(res, 400, 'INVALID_ROLE', '角色不存在');
      const user = await query('INSERT INTO users(phone,name,password_hash) VALUES($1,$2,$3) RETURNING id,phone,name,status', [phone, name, await hashPassword(password)]);
      await query('INSERT INTO user_roles(user_id,role_id,school_id) VALUES($1,$2,$3)', [user.rows[0].id, roleRow.rows[0].id, input.schoolId || null]);
      return createdIdempotently(res, null, idempotency, await issueAuthSession(user.rows[0], req, res));
    }
    if (req.method === 'POST' && url.pathname === '/v1/auth/reset-password') {
      const input = await body(req);
      const token = String(input.token || '');
      const newPassword = assertPassword(input.newPassword, '新密码');
      if (!token) {
        const phone = assertPhone(input.phone || input.account);
        const user = await query('SELECT id,status FROM users WHERE phone=$1', [phone]);
        if (!user.rows[0] || user.rows[0].status !== 'active') return fail(res, 400, 'PASSWORD_RESET_INVALID', '验证码无效或账号不可用');
        await consumeVerificationCode(phone, 'reset-password', input.verificationCode);
        await query('UPDATE users SET password_hash=$1,updated_at=now() WHERE id=$2', [await hashPassword(newPassword), user.rows[0].id]);
        await query('UPDATE refresh_sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL', [user.rows[0].id]);
        return ok(res, { passwordChanged: true, sessionsRevoked: true });
      }
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const reset = await client.query(`SELECT apr.id,apr.user_id,u.status
          FROM account_password_resets apr JOIN users u ON u.id=apr.user_id
          WHERE apr.token_hash=$1 AND apr.used_at IS NULL AND apr.expires_at>now() FOR UPDATE`, [sha256(token)]);
        if (!reset.rows[0] || reset.rows[0].status !== 'active') {
          await client.query('ROLLBACK');
          return fail(res, 400, 'PASSWORD_RESET_INVALID', '重置链接无效或已过期');
        }
        const passwordHash = await hashPassword(newPassword);
        await client.query('UPDATE users SET password_hash=$1,updated_at=now() WHERE id=$2', [passwordHash, reset.rows[0].user_id]);
        await client.query('UPDATE account_password_resets SET used_at=now() WHERE id=$1', [reset.rows[0].id]);
        await client.query('UPDATE refresh_sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL', [reset.rows[0].user_id]);
        await client.query('COMMIT');
        return ok(res, { passwordChanged: true, sessionsRevoked: true });
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally { client.release(); }
    }
    if (req.method === 'POST' && url.pathname === '/v1/auth/refresh') {
      const input = await body(req);
      const refreshToken = input.refreshToken || parseCookies(req)[refreshCookieName] || (req.headers.authorization || '').slice(7);
      if (!refreshToken) return fail(res, 401, 'AUTH_INVALID', '缺少刷新令牌');
      const session = await query(`SELECT u.id,u.phone,u.name,u.status FROM refresh_sessions s JOIN users u ON u.id=s.user_id
        WHERE s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at>now() AND u.status='active'`, [sha256(refreshToken)]);
      if (!session.rows[0]) { recordMetric('xiangshang_auth_failures_total', { action: 'refresh' }); return fail(res, 401, 'AUTH_EXPIRED', '刷新令牌已过期'); }
      const nextAccessToken = randomToken();
      const nextRefreshToken = randomToken();
      const accessExpiresAt = new Date(Date.now() + accessTokenTtlMinutes * 60_000);
      const refreshExpiresAt = new Date(Date.now() + refreshTokenTtlDays * 86_400_000);
      const rotated = await query(`UPDATE refresh_sessions SET token_hash=$1,access_token_hash=$2,access_expires_at=$3,expires_at=$4,last_used_at=now(),user_agent=$5,ip=$6
        WHERE token_hash=$7 AND revoked_at IS NULL RETURNING id`, [sha256(nextRefreshToken), sha256(nextAccessToken), accessExpiresAt, refreshExpiresAt, req.headers['user-agent'] || null, clientIp(req, { trustProxy }), sha256(refreshToken)]);
      if (!rotated.rowCount) return fail(res, 409, 'AUTH_REFRESH_CONFLICT', '刷新令牌已被其他请求使用，请重新登录');
      setRefreshCookie(res, nextRefreshToken, refreshTokenTtlDays * 86_400);
      return ok(res, await authPayload(session.rows[0], nextAccessToken, nextRefreshToken, accessExpiresAt, refreshExpiresAt));
    }
    if (req.method === 'POST' && url.pathname === '/v1/auth/login') {
      const input = await body(req);
      const account = String(input.account || input.phone || '').trim();
      const loginKey = `${clientIp(req, { trustProxy })}:${account}`;
      const loginLimit = await consumePersistentRateLimit(loginKey, 60_000, 10);
      if (!loginLimit.allowed) {
        res.setHeader('Retry-After', String(loginLimit.retryAfter));
        return fail(res, 429, 'RATE_LIMITED', '登录尝试过于频繁，请稍后重试');
      }
      const userResult = await query('SELECT * FROM users WHERE phone=$1 AND status=\'active\'', [account]);
      const user = userResult.rows[0];
      if (!user) { recordMetric('xiangshang_auth_failures_total', { action: 'login' }); return fail(res, 401, 'AUTH_INVALID', '账号或密码错误'); }
      if (input.verificationCode) await consumeVerificationCode(account, 'login', input.verificationCode);
      else if (!(await verifyPassword(input.password || '', user.password_hash))) { recordMetric('xiangshang_auth_failures_total', { action: 'login' }); return fail(res, 401, 'AUTH_INVALID', '账号或密码错误'); }
      await clearPersistentRateLimit(loginLimit.keyHash);
      const mfa = await query('SELECT user_id FROM user_mfa_totp WHERE user_id=$1 AND enabled_at IS NOT NULL AND secret_encrypted IS NOT NULL', [user.id]);
      if (mfa.rowCount) return ok(res, await createMfaChallenge(user, req));
      if (requireMfaForPrivileged) {
        const roles = await query(`SELECT r.code FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=$1 AND r.code IN ('admin','principal')`, [user.id]);
        if (roles.rowCount) return ok(res, await createMfaChallenge(user, req, 'enroll'));
      }
      return ok(res, await issueAuthSession(user, req, res));
    }
    if (req.method === 'POST' && url.pathname === '/v1/auth/mfa/totp') {
      const input = await body(req);
      const challengeToken = String(input.challengeToken || '');
      if (!challengeToken) return fail(res, 400, 'MFA_CHALLENGE_INVALID', '缺少双重验证挑战令牌');
      const client = await pool.connect();
      let account;
      try {
        await client.query('BEGIN');
        const challenge = await client.query(`SELECT c.*,u.id,u.phone,u.name,u.status FROM auth_mfa_challenges c JOIN users u ON u.id=c.user_id
          WHERE c.token_hash=$1 AND c.used_at IS NULL AND c.expires_at>now() FOR UPDATE`, [sha256(challengeToken)]);
        const row = challenge.rows[0];
        if (!row || row.purpose !== 'verify' || row.status !== 'active' || Number(row.attempts) >= 5) {
          await client.query('ROLLBACK');
          return fail(res, 401, 'MFA_CHALLENGE_INVALID', '双重验证已失效，请重新登录');
        }
        const credentialResult = await client.query('SELECT * FROM user_mfa_totp WHERE user_id=$1 AND enabled_at IS NOT NULL AND secret_encrypted IS NOT NULL FOR UPDATE', [row.user_id]);
        const credential = credentialResult.rows[0];
        if (!credential) {
          await client.query('UPDATE auth_mfa_challenges SET used_at=now() WHERE id=$1', [row.id]);
          await client.query('COMMIT');
          return fail(res, 401, 'MFA_CHALLENGE_INVALID', '双重验证配置已变更，请重新登录');
        }
        const mfaLimit = await consumePersistentRateLimit(`${clientIp(req, { trustProxy })}:mfa:${row.user_id}`, 60_000, 10);
        if (!mfaLimit.allowed) {
          await client.query('ROLLBACK');
          res.setHeader('Retry-After', String(mfaLimit.retryAfter));
          return fail(res, 429, 'RATE_LIMITED', '双重验证尝试过于频繁，请稍后重试');
        }
        const counter = verifyTotp(decryptMfaSecret(credential.secret_encrypted, mfaEncryptionKey), input.code);
        const suppliedRecoveryHash = recoveryCodeHash(input.code, mfaEncryptionKey);
        const recoveryCodes = Array.isArray(credential.recovery_code_hashes) ? credential.recovery_code_hashes : [];
        const recoveryIndex = recoveryCodes.findIndex((value) => value === suppliedRecoveryHash);
        const validTotp = counter != null && (credential.last_used_counter == null || counter > Number(credential.last_used_counter));
        if (!validTotp && recoveryIndex < 0) {
          await client.query('UPDATE auth_mfa_challenges SET attempts=attempts+1 WHERE id=$1', [row.id]);
          await client.query('COMMIT');
          recordMetric('xiangshang_auth_failures_total', { action: 'mfa' });
          return fail(res, 401, 'MFA_CODE_INVALID', '动态口令或恢复码不正确');
        }
        await client.query(`UPDATE user_mfa_totp SET last_used_counter=CASE WHEN $1::bigint IS NULL THEN last_used_counter ELSE $1 END,
          recovery_code_hashes=$2,updated_at=now() WHERE user_id=$3`, [validTotp ? counter : null, JSON.stringify(recoveryIndex < 0 ? recoveryCodes : recoveryCodes.filter((_, index) => index !== recoveryIndex)), row.user_id]);
        await client.query('UPDATE auth_mfa_challenges SET used_at=now() WHERE id=$1', [row.id]);
        await client.query('COMMIT');
        await clearPersistentRateLimit(mfaLimit.keyHash);
        account = { id: row.user_id, phone: row.phone, name: row.name, status: row.status };
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
      await audit(account, req, 'auth.mfa.login', 'user', account.id, null, { method: 'totp_or_recovery' });
      return ok(res, await issueAuthSession(account, req, res));
    }
    if (req.method === 'POST' && url.pathname === '/v1/auth/mfa/enroll/setup') {
      const input = await body(req);
      const challengeToken = String(input.challengeToken || '');
      if (!challengeToken) return fail(res, 400, 'MFA_CHALLENGE_INVALID', '缺少双重验证注册令牌');
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const challenge = await client.query(`SELECT c.*,u.phone,u.status FROM auth_mfa_challenges c JOIN users u ON u.id=c.user_id
          WHERE c.token_hash=$1 AND c.purpose='enroll' AND c.used_at IS NULL AND c.expires_at>now() FOR UPDATE`, [sha256(challengeToken)]);
        const row = challenge.rows[0];
        if (!row || row.status !== 'active') {
          await client.query('ROLLBACK');
          return fail(res, 401, 'MFA_CHALLENGE_INVALID', '双重验证注册已失效，请重新登录');
        }
        const secret = row.pending_secret_encrypted ? decryptMfaSecret(row.pending_secret_encrypted, mfaEncryptionKey) : createTotpSecret();
        if (!row.pending_secret_encrypted) await client.query('UPDATE auth_mfa_challenges SET pending_secret_encrypted=$1 WHERE id=$2', [encryptMfaSecret(secret, mfaEncryptionKey), row.id]);
        await client.query('COMMIT');
        const label = `${encodeURIComponent('向上少年')}:${encodeURIComponent(row.phone)}`;
        return ok(res, { secret, otpauthUri: `otpauth://totp/${label}?secret=${secret}&issuer=${encodeURIComponent('向上少年')}&algorithm=SHA1&digits=6&period=30`, expiresAt: row.expires_at });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'POST' && url.pathname === '/v1/auth/mfa/enroll/confirm') {
      const input = await body(req);
      const challengeToken = String(input.challengeToken || '');
      if (!challengeToken) return fail(res, 400, 'MFA_CHALLENGE_INVALID', '缺少双重验证注册令牌');
      const client = await pool.connect();
      let account;
      let recoveryCodes;
      try {
        await client.query('BEGIN');
        const challenge = await client.query(`SELECT c.*,u.id,u.phone,u.name,u.status FROM auth_mfa_challenges c JOIN users u ON u.id=c.user_id
          WHERE c.token_hash=$1 AND c.purpose='enroll' AND c.used_at IS NULL AND c.expires_at>now() FOR UPDATE`, [sha256(challengeToken)]);
        const row = challenge.rows[0];
        if (!row || row.status !== 'active' || !row.pending_secret_encrypted) {
          await client.query('ROLLBACK');
          return fail(res, 401, 'MFA_CHALLENGE_INVALID', '双重验证注册已失效，请重新登录');
        }
        const counter = verifyTotp(decryptMfaSecret(row.pending_secret_encrypted, mfaEncryptionKey), input.code);
        if (counter == null) {
          await client.query('UPDATE auth_mfa_challenges SET attempts=attempts+1 WHERE id=$1', [row.id]);
          await client.query('COMMIT');
          return fail(res, 401, 'MFA_CODE_INVALID', '动态口令不正确');
        }
        recoveryCodes = createRecoveryCodes();
        await client.query(`INSERT INTO user_mfa_totp(user_id,secret_encrypted,recovery_code_hashes,last_used_counter,enabled_at,updated_at)
          VALUES($1,$2,$3,$4,now(),now()) ON CONFLICT(user_id) DO UPDATE SET secret_encrypted=EXCLUDED.secret_encrypted,
          recovery_code_hashes=EXCLUDED.recovery_code_hashes,last_used_counter=EXCLUDED.last_used_counter,enabled_at=now(),pending_secret_encrypted=NULL,pending_expires_at=NULL,updated_at=now()`, [row.user_id, row.pending_secret_encrypted, JSON.stringify(recoveryCodes.map((code) => recoveryCodeHash(code, mfaEncryptionKey))), counter]);
        await client.query('UPDATE auth_mfa_challenges SET used_at=now(),pending_secret_encrypted=NULL WHERE id=$1', [row.id]);
        await client.query('COMMIT');
        account = { id: row.user_id, phone: row.phone, name: row.name, status: row.status };
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
      await audit(account, req, 'auth.mfa.enrollment_completed', 'user', account.id, null, { recoveryCodes: recoveryCodes.length });
      return ok(res, { ...(await issueAuthSession(account, req, res)), mfaEnrollmentCompleted: true, recoveryCodes });
    }

    const fieldDeviceResult = await handleFieldDeviceRoutes({
      req, res, url, parts, currentFieldDevice, fail, body, fieldObject, query,
      publishFieldUpdate, ok, fieldBootstrap, queryValue, safeFileName,
      allowedContentTypes, maxUploadBytes, crypto, path, created, rawBody,
      fileSignatureMatches, storage, sha256, transitionFieldQueue,
      openFieldSession, appendFieldSessionEvents, accepted, completeFieldSession, abortFieldSession,
      fieldInputString, requestBodyHash, recordMetric, logger, requestId, fieldIsoDate
    });
    if (fieldDeviceResult !== false) return fieldDeviceResult;

    const user = await requireUser(req, res);
    if (!user) return;
    if (req.method === 'POST' && url.pathname === '/v1/auth/logout') {
      const token = (req.headers.authorization || '').slice(7);
      await query('UPDATE refresh_sessions SET revoked_at=now() WHERE access_token_hash=$1 OR token_hash=$1', [sha256(token)]);
      clearRefreshCookie(res);
      return ok(res, null);
    }
    if (req.method === 'GET' && url.pathname === '/v1/auth/session') {
      return ok(res, await authClaimsForUser(user));
    }
    if (req.method === 'GET' && url.pathname === '/v1/me') {
      const claims = await authClaimsForUser(user);
      // Retain the legacy flat shape while exposing the same claims used by
      // /v1/auth/session. Existing clients can upgrade without a flag day.
      return ok(res, { ...claims.user, activeRole: claims.activeRole, accountRoles: claims.accountRoles, claimsVersion: claims.claimsVersion, roles: claims.roles });
    }
    if (req.method === 'GET' && url.pathname === '/v1/me/mfa') {
      const credential = await query(`SELECT enabled_at AS "enabledAt",pending_expires_at AS "pendingExpiresAt",
        jsonb_array_length(recovery_code_hashes)::int AS "recoveryCodesRemaining" FROM user_mfa_totp WHERE user_id=$1`, [user.id]);
      const row = credential.rows[0];
      return ok(res, { enabled: Boolean(row?.enabledAt), enabledAt: row?.enabledAt || null, pendingExpiresAt: row?.pendingExpiresAt || null, recoveryCodesRemaining: Number(row?.recoveryCodesRemaining || 0) });
    }
    if (req.method === 'POST' && url.pathname === '/v1/me/mfa/totp/setup') {
      const input = await body(req);
      const account = await query('SELECT password_hash FROM users WHERE id=$1', [user.id]);
      if (!account.rows[0] || !(await verifyPassword(input.currentPassword || '', account.rows[0].password_hash))) return fail(res, 400, 'PASSWORD_CURRENT_INVALID', '当前密码不正确');
      const secret = createTotpSecret();
      const pendingExpiresAt = new Date(Date.now() + 10 * 60_000);
      await query(`INSERT INTO user_mfa_totp(user_id,pending_secret_encrypted,pending_expires_at,updated_at) VALUES($1,$2,$3,now())
        ON CONFLICT(user_id) DO UPDATE SET pending_secret_encrypted=EXCLUDED.pending_secret_encrypted,pending_expires_at=EXCLUDED.pending_expires_at,updated_at=now()`, [user.id, encryptMfaSecret(secret, mfaEncryptionKey), pendingExpiresAt]);
      const label = `${encodeURIComponent('向上少年')}:${encodeURIComponent(user.phone)}`;
      return ok(res, { secret, otpauthUri: `otpauth://totp/${label}?secret=${secret}&issuer=${encodeURIComponent('向上少年')}&algorithm=SHA1&digits=6&period=30`, pendingExpiresAt });
    }
    if (req.method === 'POST' && url.pathname === '/v1/me/mfa/totp/confirm') {
      const input = await body(req);
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const credentialResult = await client.query('SELECT * FROM user_mfa_totp WHERE user_id=$1 FOR UPDATE', [user.id]);
        const credential = credentialResult.rows[0];
        if (!credential?.pending_secret_encrypted || !credential.pending_expires_at || new Date(credential.pending_expires_at) <= new Date()) {
          await client.query('ROLLBACK');
          return fail(res, 400, 'MFA_SETUP_EXPIRED', '双重验证设置已过期，请重新开始');
        }
        const secret = decryptMfaSecret(credential.pending_secret_encrypted, mfaEncryptionKey);
        const counter = verifyTotp(secret, input.code, Date.now(), 1);
        if (counter == null) {
          await client.query('ROLLBACK');
          return fail(res, 400, 'MFA_CODE_INVALID', '动态口令不正确');
        }
        const recoveryCodes = createRecoveryCodes();
        await client.query(`UPDATE user_mfa_totp SET secret_encrypted=$1,recovery_code_hashes=$2,last_used_counter=$3,enabled_at=now(),
          pending_secret_encrypted=NULL,pending_expires_at=NULL,updated_at=now() WHERE user_id=$4`, [credential.pending_secret_encrypted, JSON.stringify(recoveryCodes.map((code) => recoveryCodeHash(code, mfaEncryptionKey))), counter, user.id]);
        await client.query('UPDATE refresh_sessions SET revoked_at=now() WHERE user_id=$1 AND id<>$2 AND revoked_at IS NULL', [user.id, user.session_id]);
        await client.query('COMMIT');
        await audit(user, req, 'user.mfa.enabled', 'user', user.id, null, { recoveryCodes: recoveryCodes.length });
        return ok(res, { enabled: true, recoveryCodes });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'POST' && url.pathname === '/v1/me/mfa/totp/disable') {
      const input = await body(req);
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const [accountResult, credentialResult] = await Promise.all([
          client.query('SELECT password_hash FROM users WHERE id=$1', [user.id]),
          client.query('SELECT * FROM user_mfa_totp WHERE user_id=$1 AND enabled_at IS NOT NULL AND secret_encrypted IS NOT NULL FOR UPDATE', [user.id])
        ]);
        const credential = credentialResult.rows[0];
        if (!accountResult.rows[0] || !(await verifyPassword(input.currentPassword || '', accountResult.rows[0].password_hash))) {
          await client.query('ROLLBACK');
          return fail(res, 400, 'PASSWORD_CURRENT_INVALID', '当前密码不正确');
        }
        if (!credential) {
          await client.query('ROLLBACK');
          return fail(res, 409, 'MFA_NOT_ENABLED', '双重验证尚未启用');
        }
        const counter = verifyTotp(decryptMfaSecret(credential.secret_encrypted, mfaEncryptionKey), input.code);
        const recoveryCodes = Array.isArray(credential.recovery_code_hashes) ? credential.recovery_code_hashes : [];
        const recoveryIndex = recoveryCodes.indexOf(recoveryCodeHash(input.code, mfaEncryptionKey));
        if (counter == null && recoveryIndex < 0) {
          await client.query('ROLLBACK');
          return fail(res, 400, 'MFA_CODE_INVALID', '动态口令或恢复码不正确');
        }
        await client.query('DELETE FROM user_mfa_totp WHERE user_id=$1', [user.id]);
        await client.query('UPDATE refresh_sessions SET revoked_at=now() WHERE user_id=$1 AND id<>$2 AND revoked_at IS NULL', [user.id, user.session_id]);
        await client.query('COMMIT');
        await audit(user, req, 'user.mfa.disabled', 'user', user.id, { enabled: true }, { enabled: false });
        return ok(res, { enabled: false });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    const fieldAdminResult = await handleFieldAdminRoutes({
      req, res, user, url, parts, hasRole, fail, fieldInputString, queryValue,
      schoolAllowed, corsOrigin, fieldStreamSubscribers, writeFieldStream, query,
      ok, body, beginIdempotentRequest, requestBodyHash, fieldObject, audit,
      createdIdempotently, fieldReadiness: evaluateFieldReadiness, randomToken, sha256,
      encryptFieldDeviceSigningSecret, fieldDeviceSigningEncryptionKey,
      fieldDeviceKeyExpiresAt, created, pool, teacherOnly, teacherClassIds,
      pagination, normalizeScoreRows, ensureFieldQueue, rebalanceFieldQueue, okIdempotently,
      publishFieldUpdate, transitionFieldQueue, fieldIsoDate, normalizeStationItemCode, stationTaskCompatibility
    });
    if (fieldAdminResult !== false) return fieldAdminResult;
    if (req.method === 'POST' && url.pathname === '/v1/auth/password') {
      const input = await body(req);
      if (!input.currentPassword || !input.newPassword || String(input.newPassword).length < 8) return fail(res, 400, 'PASSWORD_INVALID', '新密码至少需要 8 位');
      const account = await query('SELECT password_hash FROM users WHERE id=$1', [user.id]);
      if (!account.rows[0] || !(await verifyPassword(input.currentPassword, account.rows[0].password_hash))) return fail(res, 400, 'PASSWORD_CURRENT_INVALID', '当前密码不正确');
      await query('UPDATE users SET password_hash=$1,updated_at=now() WHERE id=$2', [await hashPassword(input.newPassword), user.id]);
      await query('UPDATE refresh_sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL', [user.id]);
      await audit(user, req, 'user.password.update', 'user', user.id, null, { passwordChanged: true });
      clearRefreshCookie(res);
      return ok(res, { passwordChanged: true, sessionsRevoked: true });
    }
    if (req.method === 'GET' && url.pathname === '/v1/me/sessions') {
      const sessions = await query(`SELECT id,user_agent AS "userAgent",created_at AS "createdAt",last_used_at AS "lastUsedAt",expires_at AS "expiresAt",revoked_at AS "revokedAt"
        FROM refresh_sessions WHERE user_id=$1 ORDER BY created_at DESC LIMIT 20`, [user.id]);
      return ok(res, sessions.rows);
    }
    if (req.method === 'DELETE' && parts[0] === 'v1' && parts[1] === 'me' && parts[2] === 'sessions' && parts[3]) {
      const result = await query('UPDATE refresh_sessions SET revoked_at=now() WHERE id=$1 AND user_id=$2 RETURNING id', [parts[3], user.id]);
      if (!result.rowCount) return fail(res, 404, 'SESSION_NOT_FOUND', '会话不存在');
      return ok(res, { revoked: true, id: parts[3] });
    }
    if (req.method === 'GET' && url.pathname === '/v1/me/deletion-request') {
      const result = await query(`SELECT id,status,created_at AS "createdAt",completed_at AS "completedAt",result_json AS result
        FROM account_deletion_requests WHERE user_id=$1 ORDER BY created_at DESC LIMIT 1`, [user.id]);
      return ok(res, result.rows[0] || null);
    }
    if (req.method === 'POST' && url.pathname === '/v1/me/deletion-request') {
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ action: 'account.delete.request' }));
      if (idempotency === false) return;
      const active = await query(`SELECT id,status,created_at AS "createdAt" FROM account_deletion_requests
        WHERE user_id=$1 AND status IN ('pending','approved','processing') ORDER BY created_at DESC LIMIT 1`, [user.id]);
      if (active.rows[0]) return acceptedIdempotently(res, user, idempotency, { ...active.rows[0], reused: true });
      const request = await query(`INSERT INTO account_deletion_requests(user_id,requested_by,status)
        VALUES($1,$1,'pending') RETURNING id,status,created_at AS "createdAt"`, [user.id]);
      await audit(user, req, 'account.delete.request', 'account_deletion_request', request.rows[0].id, null, { ...request.rows[0], userId: user.id });
      return acceptedIdempotently(res, user, idempotency, request.rows[0]);
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/audit-logs') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以查看审计日志');
      const page = pagination(url);
      const schoolId = queryValue(url, 'schoolId') || null;
      const action = queryValue(url, 'action') || null;
      const params = [schoolId, action];
      const count = await query(`SELECT COUNT(*)::int AS total FROM audit_logs WHERE ($1::text IS NULL OR school_id=$1) AND ($2::text IS NULL OR action=$2)`, params);
      const result = await query(`SELECT id,action,resource_type AS "resourceType",resource_id AS "resourceId",school_id AS "schoolId",request_id AS "requestId",created_at AS "createdAt",before_json AS "before",after_json AS "after"
        FROM audit_logs WHERE ($1::text IS NULL OR school_id=$1) AND ($2::text IS NULL OR action=$2) ORDER BY created_at DESC LIMIT $3 OFFSET $4`, [...params, page.pageSize, page.offset]);
      return ok(res, listResult(url, result.rows, count.rows[0].total));
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/audit-integrity') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以校验审计完整性');
      const schoolId = queryValue(url, 'schoolId') || null;
      if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权校验该学校审计记录');
      return ok(res, { scope: schoolId || 'platform', ...(await verifyAuditChain(schoolId)) });
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/jobs') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以查看后台任务');
      const status = queryValue(url, 'status') || 'failed';
      if (!['queued', 'processing', 'completed', 'failed'].includes(status)) return fail(res, 400, 'JOB_STATUS_INVALID', '任务状态不正确');
      const page = pagination(url);
      const count = await query('SELECT COUNT(*)::int AS total FROM job_queue WHERE status=$1', [status]);
      const jobs = await query(`SELECT id,job_type AS "jobType",status,attempts,available_at AS "availableAt",locked_at AS "lockedAt",completed_at AS "completedAt",last_error AS "lastError",created_at AS "createdAt",
        payload->>'requestId' AS "requestId" FROM job_queue WHERE status=$1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`, [status, page.pageSize, page.offset]);
      return ok(res, listResult(url, jobs.rows, count.rows[0].total));
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'jobs' && parts[3] && parts[4] === 'retry') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以重试后台任务');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ jobId: parts[3], action: 'job.retry' }));
      if (idempotency === false) return;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const current = await client.query('SELECT id,job_type,payload,status,attempts,last_error FROM job_queue WHERE id=$1 FOR UPDATE', [parts[3]]);
        const job = current.rows[0];
        if (!job) { await client.query('ROLLBACK'); return failIdempotently(req, res, 404, 'JOB_NOT_FOUND', '后台任务不存在'); }
        if (job.status !== 'failed') { await client.query('ROLLBACK'); return failIdempotently(req, res, 409, 'JOB_RETRY_NOT_ALLOWED', '只有失败任务可以人工重试'); }
        const retried = await client.query(`UPDATE job_queue SET status='queued',attempts=0,available_at=now(),locked_at=NULL,completed_at=NULL,last_error=NULL
          WHERE id=$1 RETURNING id,job_type AS "jobType",status,attempts,available_at AS "availableAt"`, [job.id]);
        if (['privacy.export', 'privacy.anonymize'].includes(job.job_type) && job.payload?.requestId) await client.query(`UPDATE privacy_requests SET status='pending',completed_at=NULL,result_json=NULL WHERE id=$1 AND status='failed'`, [job.payload.requestId]);
        if (job.job_type === 'account.anonymize' && job.payload?.requestId) await client.query(`UPDATE account_deletion_requests SET status='approved',completed_at=NULL,result_json=NULL WHERE id=$1 AND status='failed'`, [job.payload.requestId]);
        await client.query('COMMIT');
        await audit(user, req, 'job.retry', 'job_queue', job.id, { status: job.status, attempts: job.attempts, lastError: job.last_error }, { ...retried.rows[0], requestId: job.payload?.requestId || null });
        return okIdempotently(res, user, idempotency, retried.rows[0]);
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/operations/summary') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以查看运营中心');
      const schoolId = queryValue(url, 'schoolId') || user.roles.find((role) => role.school_id)?.school_id || null;
      if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
      const scopedUser = `EXISTS (SELECT 1 FROM user_roles ur WHERE ur.user_id = x.user_id AND ur.school_id = $1)`;
      const fieldAttentionPredicate = `(session.status IN ('needs_review','aborted','sync_conflict') OR (session.status IN ('created','checked_in','testing') AND (session.edge_device_id IS NULL OR field_device.id IS NULL OR field_device.status<>'online' OR field_device.last_heartbeat_at IS NULL OR field_device.last_heartbeat_at<now()-interval '90 seconds' OR field_device.control_state='stopped')) OR (session.status='completed' AND NOT EXISTS (SELECT 1 FROM session_evidence evidence WHERE evidence.session_id=session.id)))`;
      const [reviews, reports, fieldSessions, retests, completionAnomalies, syncConflicts, bodyAssessments, activities, appointments, courses, support, privacy, auditToday, fieldQueue, fieldDevices] = await Promise.all([
        query(`SELECT COUNT(*)::int AS count FROM assessment_scores x WHERE x.review_status='pendingReview' AND x.session_id IS NULL AND EXISTS (SELECT 1 FROM students st WHERE st.id=x.student_id AND st.school_id=$1)`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM diagnosis_reports report JOIN students st ON st.id=report.student_id WHERE st.school_id=$1 AND report.risk_level IN ('high','attention','unavailable') AND report.status IS DISTINCT FROM 'published'`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM test_sessions session LEFT JOIN test_devices field_device ON field_device.id=session.edge_device_id WHERE session.school_id=$1 AND ${fieldAttentionPredicate}`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id WHERE t.school_id=$1 AND t.status='published' AND ts.status='待补测'`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id WHERE t.school_id=$1 AND t.status IN ('published','closed') AND ts.status='已完成' AND NOT ${validTaskCompletionPredicate('ts', 't')}`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM field_sync_batches batch JOIN test_devices device ON device.id=batch.device_id WHERE device.school_id=$1 AND batch.status='failed' AND batch.resolution_status='open'`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM body_assessments x JOIN students st ON st.id=x.student_id WHERE st.school_id=$1 AND x.measured_at >= now()-interval '30 days'`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM activity_registrations x WHERE x.status='pending' AND ${scopedUser}`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM expert_appointments x WHERE x.status='pending' AND ${scopedUser}`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM course_uploads x WHERE x.status='pending' AND ${scopedUser}`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM support_messages x WHERE x.status IN ('open','pending') AND ${scopedUser}`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM privacy_requests x JOIN students st ON st.id=x.student_id WHERE x.status IN ('pending','approved','processing') AND st.school_id=$1`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM audit_logs WHERE school_id=$1 AND created_at >= now()-interval '24 hours'`, [schoolId]),
        query(`WITH published_tasks AS (
            SELECT t.id,t.title,t.test_date FROM assessment_tasks t WHERE t.school_id=$1 AND t.status='published'
          ), selected_task AS (
            SELECT t.id,t.title,t.test_date FROM assessment_tasks t WHERE t.school_id=$1 AND t.status='published'
            ORDER BY ${operationalTaskOrder('t')},t.created_at DESC LIMIT 1
          )
          SELECT (SELECT COUNT(*)::int FROM published_tasks) AS "publishedTaskCount",
            (SELECT id FROM selected_task) AS "selectedTaskId",
            (SELECT title FROM selected_task) AS "selectedTaskTitle",
            (SELECT test_date::text FROM selected_task) AS "selectedTaskDate",
            COUNT(q.id) FILTER(WHERE q.status IN ('waiting','called','checked_in','testing','retest','paused'))::int AS "activeQueueCount",
            COUNT(q.id) FILTER(WHERE q.status IN ('waiting','retest'))::int AS "waitingCount",
            COUNT(q.id) FILTER(WHERE q.status='testing')::int AS "testingCount",
            COUNT(q.id) FILTER(WHERE (q.status='called' AND q.updated_at<now()-interval '2 minutes') OR (q.status IN ('waiting','retest') AND q.updated_at<now()-interval '15 minutes'))::int AS "overdueCount"
          FROM test_queue_entries q WHERE q.task_id=(SELECT id FROM selected_task)`, [schoolId]),
        query(`SELECT d.id,d.device_code AS "deviceCode",d.name,d.status,d.control_state AS "controlState",d.station_id AS "stationId",d.device_type AS "deviceType",d.software_version AS "softwareVersion",d.last_heartbeat_at AS "lastHeartbeatAt",d.health_json AS health,
          (d.signing_secret_encrypted IS NOT NULL) AS "signedRequestReady",station.name AS "stationName",station.status AS "stationStatus",cal.version AS "activeCalibrationVersion",cal.checksum_sha256 AS "activeCalibrationChecksumSha256"
          FROM test_devices d LEFT JOIN test_stations station ON station.id=d.station_id
          LEFT JOIN LATERAL (SELECT version,checksum_sha256 FROM station_calibrations WHERE station_id=station.id AND status='active' ORDER BY effective_at DESC LIMIT 1) cal ON TRUE
          WHERE d.school_id=$1 AND d.device_type='edge_host' AND d.status<>'disabled' ORDER BY d.id`, [schoolId])
      ]);
      const count = (result) => Number(result.rows[0]?.count || 0);
      const fieldRuntime = summarizeFieldOperations({ devices: fieldDevices.rows, queue: fieldQueue.rows[0] || {}, now: new Date(), heartbeatMaxAgeSeconds: fieldDeviceOfflineAfterSeconds });
      return ok(res, {
        schoolId, updatedAt: new Date().toISOString(), pendingReviews: count(reviews), pendingReports: count(reports),
        attentionFieldSessions: count(fieldSessions), pendingRetests: count(retests),
        completionAnomalies: count(completionAnomalies), openFieldSyncConflicts: count(syncConflicts),
        bodyAssessmentsLast30Days: count(bodyAssessments), pendingActivities: count(activities),
        pendingAppointments: count(appointments), pendingCourseUploads: count(courses),
        pendingSupportMessages: count(support), pendingPrivacyRequests: count(privacy),
        auditEventsLast24Hours: count(auditToday), fieldRuntime
      });
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/data-retention') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以查看数据治理配置');
      const evidence = await query(`SELECT evidence_type AS "evidenceType",COUNT(*) FILTER(WHERE purged_at IS NULL)::int AS "activeCount",COUNT(*) FILTER(WHERE purged_at IS NOT NULL)::int AS "purgedCount",MIN(retention_until) FILTER(WHERE purged_at IS NULL) AS "nextRetentionAt"
        FROM session_evidence GROUP BY evidence_type ORDER BY evidence_type`);
      return ok(res, {
        healthDataRetentionDays: healthRetentionDays,
        auditLogRetentionDays: 2555,
        fileUploadExpiryMinutes: 30,
        fieldEvidence: {
          videoAndImageRetentionDays: fieldEvidenceVideoRetentionDays,
          derivedEvidenceRetentionDays: fieldEvidenceDerivedRetentionDays,
          orphanUploadRetentionHours: config.fieldEvidenceOrphanRetentionHours,
          summary: evidence.rows
        },
        bindingCodeExpiryMinutes: 30,
        passwordResetExpiryMinutes: 30
      });
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'students' && parts[4] === 'export') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以导出学生数据');
      const student = await studentForUser(user, parts[3]);
      if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentId: parts[3], action: 'privacy.export' }));
      if (idempotency === false) return;
      const request = await query(`INSERT INTO privacy_requests(student_id,requested_by,request_type,status)
        VALUES($1,$2,'export','pending') RETURNING id,status,created_at AS "createdAt"`, [parts[3], user.id]);
      const job = await enqueueJob('privacy.export', { requestId: request.rows[0].id, studentId: parts[3], requestedBy: user.id });
      await audit(user, req, 'privacy.export.request', 'student', parts[3], null, { requestId: request.rows[0].id, jobId: job.id }, student.school_id);
      return acceptedIdempotently(res, user, idempotency, { ...request.rows[0], jobId: job.id });
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'privacy-requests' && parts[3]) {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以查看数据申请');
      const result = await query(`SELECT pr.id,pr.request_type AS "requestType",pr.status,pr.result_json AS data,pr.created_at AS "createdAt",pr.completed_at AS "completedAt",st.school_id AS "schoolId"
        FROM privacy_requests pr JOIN students st ON st.id=pr.student_id WHERE pr.id=$1`, [parts[3]]);
      const request = result.rows[0];
      if (!request || !schoolAllowed(user, request.schoolId)) return fail(res, 404, 'PRIVACY_REQUEST_NOT_FOUND', '数据申请不存在或无权访问');
      return ok(res, request);
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/account-deletion-requests') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以处理账户注销申请');
      const status = queryValue(url, 'status') || null;
      if (status && !['pending', 'approved', 'processing', 'completed', 'rejected', 'failed'].includes(status)) return fail(res, 400, 'ACCOUNT_DELETE_STATUS_INVALID', '账户注销状态不正确');
      const page = pagination(url);
      const count = await query(`SELECT COUNT(*)::int AS total FROM account_deletion_requests WHERE ($1::text IS NULL OR status=$1)`, [status]);
      const result = await query(`SELECT adr.id,adr.user_id AS "userId",adr.status,adr.created_at AS "createdAt",adr.completed_at AS "completedAt",adr.result_json AS result,
          adr.reviewed_by AS "reviewedBy",u.name,u.phone
        FROM account_deletion_requests adr JOIN users u ON u.id=adr.user_id
        WHERE ($1::text IS NULL OR adr.status=$1) ORDER BY adr.created_at DESC LIMIT $2 OFFSET $3`, [status, page.pageSize, page.offset]);
      const rows = result.rows.map((row) => ({ ...row, phone: undefined, phoneMasked: maskPhone(row.phone) }));
      return ok(res, listResult(url, rows, count.rows[0].total));
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'account-deletion-requests' && parts[3]) {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以处理账户注销申请');
      const input = await body(req);
      const nextStatus = String(input.status || '');
      if (!['approved', 'rejected'].includes(nextStatus)) return fail(res, 400, 'ACCOUNT_DELETE_STATUS_INVALID', '仅支持批准或拒绝账户注销申请');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ requestId: parts[3], status: nextStatus }));
      if (idempotency === false) return;
      const current = await query(`SELECT id,user_id AS "userId",status,created_at AS "createdAt" FROM account_deletion_requests WHERE id=$1`, [parts[3]]);
      const request = current.rows[0];
      if (!request) return failIdempotently(req, res, 404, 'ACCOUNT_DELETE_NOT_FOUND', '账户注销申请不存在');
      if (request.status !== 'pending') return failIdempotently(req, res, 409, 'ACCOUNT_DELETE_STATE_INVALID', '当前状态不允许再次审核');
      const updated = await query(`UPDATE account_deletion_requests SET status=$1,reviewed_by=$2,completed_at=CASE WHEN $1='rejected' THEN now() ELSE NULL END
        WHERE id=$3 RETURNING id,user_id AS "userId",status,created_at AS "createdAt",completed_at AS "completedAt"`, [nextStatus, user.id, request.id]);
      let jobId = null;
      if (nextStatus === 'approved') {
        const job = await enqueueJob('account.anonymize', { requestId: request.id, userId: request.userId, requestedBy: request.userId });
        jobId = job.id;
      }
      await audit(user, req, `account.delete.${nextStatus}`, 'account_deletion_request', request.id, request, { ...updated.rows[0], jobId });
      return okIdempotently(res, user, idempotency, { ...updated.rows[0], jobId });
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'students' && parts[4] === 'anonymize') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以提交匿名化申请');
      const student = await query('SELECT id,school_id,name FROM students WHERE id=$1 AND status=\'active\'', [parts[3]]);
      if (!student.rows[0] || !schoolAllowed(user, student.rows[0].school_id)) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
      const existing = await query(`SELECT id,status,created_at AS "createdAt" FROM privacy_requests WHERE student_id=$1 AND request_type='anonymize' AND status IN ('pending','approved','processing') ORDER BY created_at DESC LIMIT 1`, [parts[3]]);
      if (existing.rows[0]) return ok(res, existing.rows[0]);
      const request = await query(`INSERT INTO privacy_requests(student_id,requested_by,request_type) VALUES($1,$2,'anonymize') RETURNING id,status,created_at AS "createdAt"`, [parts[3], user.id]);
      await audit(user, req, 'privacy.anonymize.request', 'student', parts[3], null, request.rows[0], student.rows[0].school_id);
      return created(res, request.rows[0]);
    }

    if (req.method === 'GET' && url.pathname === '/v1/admin/accounts') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以查看账户分桶');
      const schoolId = queryValue(url, 'schoolId') || null;
      const roleCode = queryValue(url, 'role') || null;
      const status = queryValue(url, 'status') || null;
      const search = queryValue(url, 'search') || null;
      const page = pagination(url);
      const filterParams = [schoolId, roleCode, status, search ? `%${search}%` : null];
      const scopeParams = [schoolId, status];
      const scopeSql = `WHERE ($1::text IS NULL OR EXISTS (SELECT 1 FROM user_roles fur WHERE fur.user_id=u.id AND fur.school_id=$1))
        AND ($2::text IS NULL OR u.status=$2)`;
      const filterSql = `${scopeSql.replaceAll('$2', '$3')} AND ($2::text IS NULL OR EXISTS (SELECT 1 FROM user_roles fur JOIN roles fr ON fr.id=fur.role_id WHERE fur.user_id=u.id AND fr.code=$2))
        AND ($4::text IS NULL OR u.name ILIKE $4 OR u.phone ILIKE $4)`;
      const count = await query(`SELECT COUNT(*)::int AS total FROM users u ${filterSql}`, filterParams);
      const scopeCount = await query(`SELECT COUNT(*)::int AS total FROM users u ${scopeSql}`, scopeParams);
      const result = await query(`SELECT u.id,u.name,u.phone,u.status,u.created_at AS "createdAt",
          COALESCE(json_agg(DISTINCT jsonb_build_object('code',r.code,'name',r.name,'schoolId',ur.school_id,'classId',ur.class_id)) FILTER (WHERE r.id IS NOT NULL),'[]'::json) AS roles,
          COALESCE(string_agg(DISTINCT s.name,'、') FILTER (WHERE s.id IS NOT NULL),'未分配') AS "schoolNames"
        FROM users u LEFT JOIN user_roles ur ON ur.user_id=u.id LEFT JOIN roles r ON r.id=ur.role_id LEFT JOIN schools s ON s.id=ur.school_id
        ${filterSql} GROUP BY u.id ORDER BY u.created_at DESC LIMIT $5 OFFSET $6`, [...filterParams, page.pageSize, page.offset]);
      const bucketResult = await query(`SELECT r.code,r.name,COUNT(DISTINCT u.id)::int AS count
        FROM users u JOIN user_roles ur ON ur.user_id=u.id JOIN roles r ON r.id=ur.role_id
        ${scopeSql} GROUP BY r.code,r.name ORDER BY CASE r.code WHEN 'admin' THEN 1 WHEN 'principal' THEN 2 WHEN 'teacher' THEN 3 WHEN 'parent' THEN 4 ELSE 5 END`, scopeParams);
      const total = Number(count.rows[0].total);
      const scopeTotal = Number(scopeCount.rows[0].total);
      const buckets = bucketResult.rows.map((row) => ({ key: row.code, label: row.name, count: row.count, percent: scopeTotal ? Math.round(Number(row.count) / scopeTotal * 100) : 0 }));
      return ok(res, { buckets, items: result.rows.map((row) => ({ ...row, phone: undefined, phoneMasked: maskPhone(row.phone), roles: row.roles || [], schoolNames: row.schoolNames || '未分配' })), page: page.page, pageSize: page.pageSize, total, scopeTotal });
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/accounts') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以创建账户');
      const input = await body(req);
      const roleCode = input.role || 'teacher';
      if (!input.phone || !input.name || !input.password || !['parent', 'teacher', 'principal', 'admin'].includes(roleCode)) return fail(res, 400, 'INVALID_ARGUMENT', '姓名、手机号、密码和角色不能为空');
      const phone = assertPhone(input.phone);
      const password = assertPassword(input.password);
      if (roleCode !== 'admin' && !input.schoolId) return fail(res, 400, 'INVALID_ARGUMENT', '学校账户必须绑定学校');
      if (input.schoolId) {
        const school = await query('SELECT id FROM schools WHERE id=$1 AND status=\'active\'', [input.schoolId]);
        if (!school.rowCount) return fail(res, 400, 'SCHOOL_NOT_FOUND', '学校不存在或已停用');
      }
      if (input.classId) {
        const classScope = await query('SELECT id FROM classes WHERE id=$1 AND school_id=$2', [input.classId, input.schoolId]);
        if (!classScope.rowCount) return fail(res, 400, 'CLASS_SCOPE_INVALID', '班级不属于所选学校');
      }
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const roleResult = await client.query('SELECT id,name FROM roles WHERE code=$1', [roleCode]);
        if (!roleResult.rows[0]) throw Object.assign(new Error('角色不存在'), { status: 400, code: 'INVALID_ROLE' });
        const account = await client.query(`INSERT INTO users(phone,name,password_hash) VALUES($1,$2,$3) RETURNING id,name,phone,status,created_at AS "createdAt"`, [phone, input.name, await hashPassword(password)]);
        await client.query('INSERT INTO user_roles(user_id,role_id,school_id,class_id) VALUES($1,$2,$3,$4)', [account.rows[0].id, roleResult.rows[0].id, input.schoolId || null, input.classId || null]);
        await client.query('COMMIT');
        await audit(user, req, 'account.create', 'user', account.rows[0].id, null, { ...account.rows[0], role: roleCode, schoolId: input.schoolId || null });
        return createdIdempotently(res, user, idempotency, { ...account.rows[0], phone: undefined, phoneMasked: maskPhone(account.rows[0].phone), role: roleResult.rows[0] });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'accounts' && parts[4] === 'status') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以修改账户状态');
      if (parts[3] === user.id) return fail(res, 400, 'SELF_STATUS_CHANGE_FORBIDDEN', '不能修改当前登录账户状态');
      const input = await body(req);
      if (!['active', 'disabled'].includes(input.status)) return fail(res, 400, 'INVALID_STATUS', '账户状态不正确');
      const before = await query('SELECT id,name,phone,status FROM users WHERE id=$1', [parts[3]]);
      if (!before.rows[0]) return fail(res, 404, 'ACCOUNT_NOT_FOUND', '账户不存在');
      const updated = await query('UPDATE users SET status=$1,updated_at=now() WHERE id=$2 RETURNING id,name,status,updated_at AS "updatedAt"', [input.status, parts[3]]);
      if (input.status === 'disabled') await query('UPDATE refresh_sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL', [parts[3]]);
      await audit(user, req, 'account.status.update', 'user', parts[3], before.rows[0], updated.rows[0]);
      return ok(res, updated.rows[0]);
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'accounts' && parts[3] && !parts[4]) {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以编辑账户');
      if (parts[3] === user.id) return fail(res, 400, 'SELF_ROLE_CHANGE_FORBIDDEN', '不能直接修改当前登录账户权限');
      const input = await body(req);
      if (!input.name) return fail(res, 400, 'INVALID_ARGUMENT', '姓名不能为空');
      const replaceScopes = Array.isArray(input.roles) || input.replaceScopes === true;
      const legacyRole = input.role || 'teacher';
      const requestedRoles = Array.isArray(input.roles) ? input.roles : [{ role: legacyRole, schoolId: input.schoolId || null, classId: input.classId || null }];
      if (replaceScopes && (!requestedRoles.length || requestedRoles.length > 20)) return fail(res, 400, 'INVALID_ARGUMENT', '账户权限范围不能为空或过多');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ accountId: parts[3], ...input }));
      if (idempotency === false) return;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const before = await client.query('SELECT id,name,phone,status FROM users WHERE id=$1 FOR UPDATE', [parts[3]]);
        if (!before.rows[0]) { await client.query('ROLLBACK'); return failIdempotently(req, res, 404, 'ACCOUNT_NOT_FOUND', '账户不存在'); }
        const updated = await client.query('UPDATE users SET name=$1,updated_at=now() WHERE id=$2 RETURNING id,name,status,updated_at AS "updatedAt"', [input.name, parts[3]]);
        if (replaceScopes) {
          const normalizedRoles = [];
          for (const scope of requestedRoles) {
            const roleCode = String(scope.role || scope.code || '');
            if (!['parent', 'teacher', 'principal', 'admin'].includes(roleCode)) throw Object.assign(new Error('角色不存在'), { status: 400, code: 'INVALID_ROLE' });
            const schoolId = scope.schoolId || null;
            const classId = scope.classId || null;
            if (roleCode !== 'admin' && !schoolId) throw Object.assign(new Error('学校账户必须绑定学校'), { status: 400, code: 'SCHOOL_REQUIRED' });
            if (schoolId && !(await client.query("SELECT 1 FROM schools WHERE id=$1 AND status='active'", [schoolId])).rowCount) throw Object.assign(new Error('学校不存在或已停用'), { status: 400, code: 'SCHOOL_NOT_FOUND' });
            if (classId && (roleCode !== 'teacher' || !(await client.query('SELECT 1 FROM classes WHERE id=$1 AND school_id=$2', [classId, schoolId])).rowCount)) throw Object.assign(new Error('班级不属于所选学校或角色不支持班级范围'), { status: 400, code: 'CLASS_SCOPE_INVALID' });
            const role = await client.query('SELECT id,name FROM roles WHERE code=$1', [roleCode]);
            if (!role.rows[0]) throw Object.assign(new Error('角色不存在'), { status: 400, code: 'INVALID_ROLE' });
            normalizedRoles.push({ roleCode, schoolId, classId, role: role.rows[0] });
          }
          await client.query('DELETE FROM user_roles WHERE user_id=$1', [parts[3]]);
          for (const scope of normalizedRoles) await client.query('INSERT INTO user_roles(user_id,role_id,school_id,class_id) VALUES($1,$2,$3,$4)', [parts[3], scope.role.id, scope.schoolId, scope.roleCode === 'teacher' ? scope.classId : null]);
        }
        await client.query('COMMIT');
        await audit(user, req, 'account.update', 'user', parts[3], before.rows[0], { ...updated.rows[0], scopesReplaced: replaceScopes });
        const roleResult = await query(`SELECT r.code,r.name,ur.school_id AS "schoolId",ur.class_id AS "classId" FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=$1`, [parts[3]]);
        return okIdempotently(res, user, idempotency, { ...updated.rows[0], roles: roleResult.rows });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'accounts' && parts[4] === 'reset-password') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以重置账户密码');
      const before = await query('SELECT id,name,phone,status FROM users WHERE id=$1', [parts[3]]);
      if (!before.rows[0]) return fail(res, 404, 'ACCOUNT_NOT_FOUND', '账户不存在');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ accountId: parts[3], action: 'password-reset' }));
      if (idempotency === false) return;
      const setupToken = randomToken();
      const expiresAt = new Date(Date.now() + 30 * 60_000);
      await query('UPDATE account_password_resets SET used_at=now() WHERE user_id=$1 AND used_at IS NULL', [parts[3]]);
      await query('INSERT INTO account_password_resets(user_id,token_hash,expires_at,created_by) VALUES($1,$2,$3,$4)', [parts[3], sha256(setupToken), expiresAt, user.id]);
      await query('UPDATE refresh_sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL', [parts[3]]);
      await audit(user, req, 'account.password.reset_requested', 'user', parts[3], before.rows[0], { passwordResetRequested: true, expiresAt });
      return okIdempotently(res, user, idempotency, { id: parts[3], setupToken, expiresAt, sessionsRevoked: true });
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'accounts' && parts[4] === 'reset-mfa') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以执行双重验证恢复');
      const input = await body(req);
      const reason = requiredString(input.reason, '恢复原因', { max: 500 });
      if (reason.length < 8) return fail(res, 400, 'MFA_RESET_REASON_REQUIRED', '恢复原因至少需要 8 个字符');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ accountId: parts[3], action: 'mfa-reset', reason }));
      if (idempotency === false) return;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const account = await client.query('SELECT id,name,phone,status FROM users WHERE id=$1 FOR UPDATE', [parts[3]]);
        if (!account.rows[0]) { await client.query('ROLLBACK'); return failIdempotently(req, res, 404, 'ACCOUNT_NOT_FOUND', '账户不存在'); }
        const credential = await client.query('SELECT enabled_at AS "enabledAt" FROM user_mfa_totp WHERE user_id=$1 FOR UPDATE', [parts[3]]);
        await client.query('DELETE FROM user_mfa_totp WHERE user_id=$1', [parts[3]]);
        await client.query('UPDATE auth_mfa_challenges SET used_at=now(),pending_secret_encrypted=NULL WHERE user_id=$1 AND used_at IS NULL', [parts[3]]);
        await client.query('UPDATE refresh_sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL', [parts[3]]);
        await client.query('COMMIT');
        const result = { id: parts[3], mfaReset: Boolean(credential.rows[0]?.enabledAt), sessionsRevoked: true, mustReenroll: requireMfaForPrivileged };
        await audit(user, req, 'account.mfa.reset', 'user', parts[3], { mfaEnabled: Boolean(credential.rows[0]?.enabledAt) }, { ...result, reason });
        return okIdempotently(res, user, idempotency, result);
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }

    if (req.method === 'GET' && url.pathname === '/v1/admin/schools') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以查看学校列表');
      const page = pagination(url);
      const count = await query('SELECT COUNT(*)::int AS total FROM schools');
      const result = await query(`SELECT id,name,campus,region,is_poverty_area AS "isPovertyArea",status FROM schools ORDER BY name LIMIT $1 OFFSET $2`, [page.pageSize, page.offset]);
      return ok(res, listResult(url, result.rows, count.rows[0].total));
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/schools') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以创建学校');
      const input = await body(req);
      if (!input.name) return fail(res, 400, 'INVALID_ARGUMENT', '学校名称不能为空');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const result = await query(`INSERT INTO schools(name,campus,region,is_poverty_area) VALUES($1,$2,$3,$4) RETURNING id,name,campus,region,is_poverty_area AS "isPovertyArea",status`, [input.name, input.campus || '', input.region || '', Boolean(input.isPovertyArea)]);
      await audit(user, req, 'school.create', 'school', result.rows[0].id, null, result.rows[0]);
      return createdIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'schools' && parts[3] && parts[4] === 'status') {
      if (!hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有平台管理员可以停用学校');
      const input = await body(req);
      if (!['active', 'inactive'].includes(input.status)) return fail(res, 400, 'INVALID_ARGUMENT', '学校状态不合法');
      const before = await query('SELECT * FROM schools WHERE id=$1', [parts[3]]);
      if (!before.rows[0]) return fail(res, 404, 'SCHOOL_NOT_FOUND', '学校不存在');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ schoolId: parts[3], status: input.status }));
      if (idempotency === false) return;
      const result = await query(`UPDATE schools SET status=$1,updated_at=now() WHERE id=$2 RETURNING id,name,status,updated_at AS "updatedAt"`, [input.status, parts[3]]);
      await audit(user, req, `school.status.${input.status}`, 'school', parts[3], before.rows[0], result.rows[0], parts[3]);
      return okIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/grades') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权查看年级');
      const schoolId = queryValue(url, 'schoolId') || user.roles.find((role) => role.school_id)?.school_id;
      if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
      const result = await query(`SELECT id,name,school_id AS "schoolId",standard_version AS "standardVersion",academic_year AS "academicYear",period_id AS "periodId" FROM grades WHERE school_id=$1 ORDER BY academic_year DESC,name`, [schoolId]);
      return ok(res, result.rows);
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/assessment-standards') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权查看测评标准');
      const schoolId = queryValue(url, 'schoolId') || user.roles.find((role) => role.school_id)?.school_id || null;
      if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
      if (!schoolId && !hasRole(user, 'admin')) return fail(res, 400, 'INVALID_ARGUMENT', '请选择学校');
      const result = await query(`SELECT s.id,s.school_id AS "schoolId",s.grade_id AS "gradeId",s.region,s.poverty_area AS "povertyArea",
        s.standard_version AS "standardVersion",s.rule_config AS "ruleConfig",s.report_config AS "reportConfig",s.course_config AS "courseConfig",
        s.effective_date::text AS "effectiveDate",s.status,s.created_at AS "createdAt",s.updated_at AS "updatedAt",u.name AS "createdBy"
        FROM assessment_standards s LEFT JOIN users u ON u.id=s.created_by
        WHERE ($1::text IS NULL OR s.school_id IS NULL OR s.school_id=$1) AND ($2::text IS NULL OR s.grade_id=$2)
          AND ($3::text IS NULL OR s.status=$3)
        ORDER BY s.effective_date DESC,s.created_at DESC`, [schoolId, queryValue(url, 'gradeId') || null, queryValue(url, 'status') || null]);
      return ok(res, result.rows);
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/assessment-standards') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权创建测评标准');
      const input = await body(req);
      const schoolId = input.schoolId || null;
      if (!schoolId && !hasRole(user, 'admin')) return fail(res, 400, 'INVALID_ARGUMENT', '学校管理员只能创建本校标准');
      if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权为该学校创建标准');
      const gradeId = input.gradeId || null;
      if (gradeId && !schoolId) return fail(res, 400, 'INVALID_ARGUMENT', '年级标准必须指定学校');
      if (gradeId) {
        const grade = await query('SELECT 1 FROM grades WHERE id=$1 AND school_id=$2', [gradeId, schoolId]);
        if (!grade.rowCount) return fail(res, 400, 'GRADE_SCOPE_INVALID', '年级不属于所选学校');
      }
      const standardVersion = fieldInputString(input.standardVersion, '标准版本', 120);
      const region = String(input.region || '').trim();
      if (region.length > 80) return fail(res, 400, 'INVALID_ARGUMENT', '地区长度不能超过 80 个字符');
      const povertyArea = input.povertyArea === undefined || input.povertyArea === null ? null : input.povertyArea;
      if (povertyArea !== null && typeof povertyArea !== 'boolean') return fail(res, 400, 'INVALID_ARGUMENT', '困难地区标识必须为布尔值');
      const status = input.status || 'draft';
      if (!['draft', 'active'].includes(status)) return fail(res, 400, 'INVALID_ARGUMENT', '新标准状态只能是草稿或生效');
      const standardEffectiveDate = effectiveDate(input.effectiveDate);
      if (status === 'active') {
        const conflict = await query(`SELECT id FROM assessment_standards
          WHERE status='active' AND school_id IS NOT DISTINCT FROM $1 AND grade_id IS NOT DISTINCT FROM $2
            AND region=$3 AND poverty_area IS NOT DISTINCT FROM $4 AND effective_date=$5`, [schoolId, gradeId, region, povertyArea, standardEffectiveDate]);
        if (conflict.rowCount) return fail(res, 409, 'ASSESSMENT_STANDARD_EFFECTIVE_CONFLICT', '相同适用范围和生效日期已有生效中的标准，请先调整日期或归档旧版本');
      }
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const result = await query(`INSERT INTO assessment_standards(school_id,grade_id,region,poverty_area,standard_version,rule_config,report_config,course_config,effective_date,status,created_by)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
        RETURNING id,school_id AS "schoolId",grade_id AS "gradeId",region,poverty_area AS "povertyArea",standard_version AS "standardVersion",
        rule_config AS "ruleConfig",report_config AS "reportConfig",course_config AS "courseConfig",effective_date::text AS "effectiveDate",status,created_at AS "createdAt"`,
      [schoolId, gradeId, region, povertyArea, standardVersion, fieldObject(input.ruleConfig), fieldObject(input.reportConfig), fieldObject(input.courseConfig), standardEffectiveDate, status, user.id]);
      await audit(user, req, 'assessment_standard.create', 'assessment_standard', result.rows[0].id, null, result.rows[0], schoolId);
      return createdIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'assessment-standards' && parts[3] && parts[4] === 'status') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权变更测评标准状态');
      const input = await body(req);
      if (!['active', 'archived'].includes(input.status)) return fail(res, 400, 'INVALID_ARGUMENT', '标准状态只能设为生效或归档');
      const before = await query('SELECT * FROM assessment_standards WHERE id=$1', [parts[3]]);
      if (!before.rows[0] || (before.rows[0].school_id && !schoolAllowed(user, before.rows[0].school_id)) || (!before.rows[0].school_id && !hasRole(user, 'admin'))) return fail(res, 404, 'ASSESSMENT_STANDARD_NOT_FOUND', '测评标准不存在或无权访问');
      if (input.status === 'active') {
        const conflict = await query(`SELECT id FROM assessment_standards
          WHERE id<>$1 AND status='active' AND school_id IS NOT DISTINCT FROM $2 AND grade_id IS NOT DISTINCT FROM $3
            AND region=$4 AND poverty_area IS NOT DISTINCT FROM $5 AND effective_date=$6`, [before.rows[0].id, before.rows[0].school_id, before.rows[0].grade_id, before.rows[0].region, before.rows[0].poverty_area, before.rows[0].effective_date]);
        if (conflict.rowCount) return fail(res, 409, 'ASSESSMENT_STANDARD_EFFECTIVE_CONFLICT', '相同适用范围和生效日期已有生效中的标准，请先归档旧版本');
      }
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ id: parts[3], status: input.status }));
      if (idempotency === false) return;
      const result = await query(`UPDATE assessment_standards SET status=$1,updated_at=now() WHERE id=$2
        RETURNING id,school_id AS "schoolId",grade_id AS "gradeId",region,poverty_area AS "povertyArea",standard_version AS "standardVersion",effective_date::text AS "effectiveDate",status,updated_at AS "updatedAt"`, [input.status, parts[3]]);
      await audit(user, req, 'assessment_standard.status.update', 'assessment_standard', parts[3], before.rows[0], result.rows[0], before.rows[0].school_id);
      return okIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/classes') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权查看班级');
      const schoolId = queryValue(url, 'schoolId') || user.roles.find((role) => role.school_id)?.school_id;
      const gradeId = queryValue(url, 'gradeId') || null;
      if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
      const result = await query(`SELECT c.id,c.name,c.school_id AS "schoolId",c.grade_id AS "gradeId",c.teacher_id AS "teacherId",COALESCE(u.name,'未分配') AS "teacherName",c.period_id AS "periodId" FROM classes c LEFT JOIN users u ON u.id=c.teacher_id WHERE c.school_id=$1 AND ($2::text IS NULL OR c.grade_id=$2) ORDER BY c.name`, [schoolId, gradeId]);
      return ok(res, result.rows);
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/grades') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权创建年级');
      const input = await body(req);
      if (!input.schoolId || !input.name || !schoolAllowed(user, input.schoolId)) return fail(res, 400, 'INVALID_ARGUMENT', '学校和年级名称不能为空');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const result = await query(`INSERT INTO grades(school_id,name,standard_version,academic_year,period_id) VALUES($1,$2,$3,$4,$5) RETURNING id,name,standard_version AS "standardVersion",academic_year AS "academicYear",period_id AS "periodId"`, [input.schoolId, input.name, input.standardVersion || '运动能力标准 v1.0', input.academicYear || '', input.periodId || null]);
      await audit(user, req, 'grade.create', 'grade', result.rows[0].id, null, result.rows[0], input.schoolId);
      return createdIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'grades' && parts[3]) {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权编辑年级');
      const input = await body(req);
      const before = await query('SELECT * FROM grades WHERE id=$1', [parts[3]]);
      if (!before.rows[0] || !schoolAllowed(user, before.rows[0].school_id)) return fail(res, 404, 'GRADE_NOT_FOUND', '年级不存在或无权访问');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ id: parts[3], ...input }));
      if (idempotency === false) return;
      const result = await query(`UPDATE grades SET name=COALESCE($1,name),standard_version=COALESCE($2,standard_version),academic_year=COALESCE($3,academic_year),period_id=COALESCE($4,period_id) WHERE id=$5 RETURNING id,name,standard_version AS "standardVersion",academic_year AS "academicYear",period_id AS "periodId"`, [input.name || null, input.standardVersion || null, input.academicYear || null, input.periodId || null, parts[3]]);
      await audit(user, req, 'grade.update', 'grade', parts[3], before.rows[0], result.rows[0], before.rows[0].school_id);
      return okIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/classes') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权创建班级');
      const input = await body(req);
      if (!input.schoolId || !input.gradeId || !input.name || !schoolAllowed(user, input.schoolId)) return fail(res, 400, 'INVALID_ARGUMENT', '学校、年级和班级名称不能为空');
      const gradeScope = await query('SELECT id FROM grades WHERE id=$1 AND school_id=$2', [input.gradeId, input.schoolId]);
      if (!gradeScope.rowCount) return fail(res, 400, 'GRADE_SCOPE_INVALID', '年级不属于所选学校');
      if (input.teacherId) {
        const teacherScope = await query(`SELECT 1 FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=$1 AND ur.school_id=$2 AND r.code='teacher'`, [input.teacherId, input.schoolId]);
        if (!teacherScope.rowCount) return fail(res, 400, 'TEACHER_SCOPE_INVALID', '班主任不属于所选学校');
      }
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const result = await query(`INSERT INTO classes(school_id,grade_id,name,teacher_id,period_id) VALUES($1,$2,$3,$4,$5) RETURNING id,name,grade_id AS "gradeId",teacher_id AS "teacherId",period_id AS "periodId"`, [input.schoolId, input.gradeId, input.name, input.teacherId || null, input.periodId || null]);
      await audit(user, req, 'class.create', 'class', result.rows[0].id, null, result.rows[0], input.schoolId);
      return createdIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'classes' && parts[3]) {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权编辑班级');
      const input = await body(req);
      const before = await query('SELECT * FROM classes WHERE id=$1', [parts[3]]);
      const current = before.rows[0];
      if (!current || !schoolAllowed(user, current.school_id)) return fail(res, 404, 'CLASS_NOT_FOUND', '班级不存在或无权访问');
      const gradeId = input.gradeId || current.grade_id;
      const grade = await query('SELECT id FROM grades WHERE id=$1 AND school_id=$2', [gradeId, current.school_id]);
      if (!grade.rowCount) return fail(res, 400, 'GRADE_SCOPE_INVALID', '年级不属于该学校');
      if (input.teacherId) {
        const teacher = await query(`SELECT 1 FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=$1 AND ur.school_id=$2 AND r.code='teacher'`, [input.teacherId, current.school_id]);
        if (!teacher.rowCount) return fail(res, 400, 'TEACHER_SCOPE_INVALID', '班主任不属于该学校');
      }
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ id: parts[3], ...input }));
      if (idempotency === false) return;
      const result = await query(`UPDATE classes SET name=COALESCE($1,name),grade_id=$2,teacher_id=$3,period_id=COALESCE($4,period_id) WHERE id=$5 RETURNING id,name,grade_id AS "gradeId",teacher_id AS "teacherId",period_id AS "periodId"`, [input.name || null, gradeId, input.teacherId === undefined ? current.teacher_id : (input.teacherId || null), input.periodId || null, parts[3]]);
      await audit(user, req, 'class.update', 'class', parts[3], current, result.rows[0], current.school_id);
      return okIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/school-periods') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权查看学年学期');
      const schoolId = queryValue(url, 'schoolId') || user.roles.find((role) => role.school_id)?.school_id;
      if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
      const result = await query(`SELECT id,school_id AS "schoolId",academic_year AS "academicYear",term,starts_on AS "startsOn",ends_on AS "endsOn",status,created_at AS "createdAt"
        FROM school_periods WHERE school_id=$1 ORDER BY academic_year DESC, term`, [schoolId]);
      return ok(res, result.rows);
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/school-periods') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以创建学年学期');
      const input = await body(req);
      if (!input.schoolId || !input.academicYear || !schoolAllowed(user, input.schoolId)) return fail(res, 400, 'INVALID_ARGUMENT', '学校和学年不能为空');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const result = await query(`INSERT INTO school_periods(school_id,academic_year,term,starts_on,ends_on)
        VALUES($1,$2,$3,$4,$5) RETURNING id,school_id AS "schoolId",academic_year AS "academicYear",term,starts_on AS "startsOn",ends_on AS "endsOn",status`, [input.schoolId, input.academicYear, input.term || '全年', input.startsOn || null, input.endsOn || null]);
      await audit(user, req, 'school_period.create', 'school_period', result.rows[0].id, null, result.rows[0], input.schoolId);
      return createdIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'school-periods' && parts[3] && parts[4] === 'status') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权归档学年学期');
      const input = await body(req);
      if (!['active', 'archived'].includes(input.status)) return fail(res, 400, 'INVALID_ARGUMENT', '学年学期状态不合法');
      const before = await query('SELECT * FROM school_periods WHERE id=$1', [parts[3]]);
      if (!before.rows[0] || !schoolAllowed(user, before.rows[0].school_id)) return fail(res, 404, 'PERIOD_NOT_FOUND', '学年学期不存在或无权访问');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ id: parts[3], status: input.status }));
      if (idempotency === false) return;
      const result = await query(`UPDATE school_periods SET status=$1,updated_at=now() WHERE id=$2 RETURNING id,school_id AS "schoolId",academic_year AS "academicYear",term,status`, [input.status, parts[3]]);
      await audit(user, req, 'school_period.status.update', 'school_period', parts[3], before.rows[0], result.rows[0], before.rows[0].school_id);
      return okIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/students/import/template') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权下载导入模板');
      return ok(res, { columns: ['schoolId', 'gradeId', 'classId', 'studentNo', 'name', 'gender', 'birthDate', 'region', 'isPovertyArea'], example: [{ schoolId: 'school-1', gradeId: 'grade-1', classId: 'class-1', studentNo: 'S001', name: '王小明', gender: '男', birthDate: '2017-03-12', region: '本地', isPovertyArea: false }] });
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/students/imports') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权查看导入记录');
      const schoolId = queryValue(url, 'schoolId') || null;
      if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
      const page = pagination(url);
      const params = schoolId ? [schoolId] : [];
      const where = schoolId ? 'WHERE si.school_id=$1' : '';
      const count = await query(`SELECT COUNT(*)::int AS total FROM student_imports si ${where}`, params);
      const result = await query(`SELECT si.id,si.school_id AS "schoolId",COALESCE(s.name,'多学校') AS "schoolName",si.filename,si.duplicate_policy AS "duplicatePolicy",si.status,si.total_rows AS "totalRows",si.imported_count AS "importedCount",si.skipped_count AS "skippedCount",si.failed_count AS "failedCount",si.errors_json AS errors,si.created_at AS "createdAt",si.completed_at AS "completedAt",u.name AS "requestedBy"
        FROM student_imports si LEFT JOIN schools s ON s.id=si.school_id JOIN users u ON u.id=si.requested_by ${where} ORDER BY si.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`, [...params, page.pageSize, page.offset]);
      return ok(res, listResult(url, result.rows, count.rows[0].total));
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/students/import/preview') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以预览学生导入');
      const input = await body(req);
      const result = await normalizeStudentImportRows(user, input, { query, schoolAllowed });
      const importSchoolIds = [...new Set(result.normalized.map((row) => row.schoolId))];
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ ...input, mode: 'preview' }));
      if (idempotency === false) return;
      const history = await query(`INSERT INTO student_imports(requested_by,school_id,filename,duplicate_policy,status,total_rows,failed_count,errors_json)
        VALUES($1,$2,$3,$4,'previewed',$5,$6,$7) RETURNING id`, [user.id, importSchoolIds.length === 1 ? importSchoolIds[0] : null, input.filename || '', input.duplicatePolicy || 'skip', result.rawRows.length, result.errors.length, result.errors]);
      return okIdempotently(res, user, idempotency, { importId: history.rows[0].id, totalRows: result.rawRows.length, validRows: result.normalized.length, errorRows: result.errors.length, errors: result.errors, preview: result.normalized.slice(0, 100) });
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/students/import') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以导入学生');
      const input = await body(req);
      const result = await normalizeStudentImportRows(user, input, { query, schoolAllowed });
      if (result.errors.length) return send(res, 422, { code: 'IMPORT_VALIDATION_FAILED', message: '导入数据存在错误，请修正后重试', data: { totalRows: result.rawRows.length, validRows: result.normalized.length, errorRows: result.errors.length, errors: result.errors } });
      const policy = ['skip', 'update'].includes(input.duplicatePolicy) ? input.duplicatePolicy : 'skip';
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ ...input, mode: 'import' }));
      if (idempotency === false) return;
      const client = await pool.connect();
      let importedCount = 0;
      let skippedCount = 0;
      try {
        await client.query('BEGIN');
        const importSchoolIds = [...new Set(result.normalized.map((row) => row.schoolId))];
        const history = await client.query(`INSERT INTO student_imports(requested_by,school_id,filename,duplicate_policy,status,total_rows)
          VALUES($1,$2,$3,$4,'imported',$5) RETURNING id`, [user.id, importSchoolIds.length === 1 ? importSchoolIds[0] : null, input.filename || '', policy, result.normalized.length]);
        for (const row of result.normalized) {
          const existing = await client.query(`SELECT * FROM students WHERE school_id=$1 AND ((student_no IS NOT NULL AND student_no=$2) OR (student_no IS NULL AND $2::text IS NULL AND name=$3 AND class_id=$4)) FOR UPDATE`, [row.schoolId, row.studentNo, row.name, row.classId]);
          if (existing.rows[0]) {
            if (policy === 'skip') { skippedCount += 1; continue; }
            await client.query(`UPDATE students SET grade_id=$1,class_id=$2,period_id=$3,name=$4,student_no=$5,gender=$6,birth_date=$7,region=$8,is_poverty_area=$9,status='active',updated_at=now() WHERE id=$10`, [row.gradeId, row.classId, row.periodId, row.name, row.studentNo, row.gender, row.birthDate, row.region, row.isPovertyArea, existing.rows[0].id]);
            await client.query(`INSERT INTO student_lifecycle_events(student_id,event_type,from_grade_id,from_class_id,to_grade_id,to_class_id,from_status,to_status,note,operator_id) VALUES($1,'updated',$2,$3,$4,$5,$6,'active','批量导入更新',$7)`, [existing.rows[0].id, existing.rows[0].grade_id, existing.rows[0].class_id, row.gradeId, row.classId, existing.rows[0].status, user.id]);
            importedCount += 1;
            continue;
          }
          const inserted = await client.query(`INSERT INTO students(school_id,grade_id,class_id,period_id,student_no,name,gender,birth_date,region,is_poverty_area)
            VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`, [row.schoolId, row.gradeId, row.classId, row.periodId, row.studentNo, row.name, row.gender, row.birthDate, row.region, row.isPovertyArea]);
          await client.query(`INSERT INTO student_lifecycle_events(student_id,event_type,to_grade_id,to_class_id,to_status,note,operator_id) VALUES($1,'created',$2,$3,'active','批量导入',$4)`, [inserted.rows[0].id, row.gradeId, row.classId, user.id]);
          importedCount += 1;
        }
        await client.query(`UPDATE student_imports SET imported_count=$1,skipped_count=$2,completed_at=now() WHERE id=$3`, [importedCount, skippedCount, history.rows[0].id]);
        await client.query('COMMIT');
        await audit(user, req, 'student.import', 'student_import', history.rows[0].id, null, { importedCount, skippedCount }, importSchoolIds.length === 1 ? importSchoolIds[0] : null);
        return createdIdempotently(res, user, idempotency, { importId: history.rows[0].id, totalRows: result.rawRows.length, importedCount, skippedCount, errorRows: 0 });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'students' && parts[4] === 'history') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权查看学生变更记录');
      const student = await query('SELECT id,school_id FROM students WHERE id=$1', [parts[3]]);
      if (!student.rows[0] || !schoolAllowed(user, student.rows[0].school_id)) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
      const result = await query(`SELECT e.id,e.event_type AS "eventType",e.from_grade_id AS "fromGradeId",fg.name AS "fromGradeName",e.from_class_id AS "fromClassId",fc.name AS "fromClassName",e.to_grade_id AS "toGradeId",tg.name AS "toGradeName",e.to_class_id AS "toClassId",tc.name AS "toClassName",e.from_status AS "fromStatus",e.to_status AS "toStatus",e.note,e.created_at AS "createdAt",u.name AS "operatorName"
        FROM student_lifecycle_events e LEFT JOIN grades fg ON fg.id=e.from_grade_id LEFT JOIN classes fc ON fc.id=e.from_class_id LEFT JOIN grades tg ON tg.id=e.to_grade_id LEFT JOIN classes tc ON tc.id=e.to_class_id LEFT JOIN users u ON u.id=e.operator_id
        WHERE e.student_id=$1 ORDER BY e.created_at DESC`, [parts[3]]);
      return ok(res, result.rows);
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'students' && parts[3] && !parts[4]) {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以编辑学生');
      const input = await body(req);
      const before = await query('SELECT * FROM students WHERE id=$1', [parts[3]]);
      const current = before.rows[0];
      if (!current || !schoolAllowed(user, current.school_id)) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
      const gradeId = input.gradeId || current.grade_id;
      const classId = input.classId || current.class_id;
      const scope = await query(`SELECT c.id AS class_id,c.grade_id,g.school_id FROM classes c JOIN grades g ON g.id=c.grade_id WHERE c.id=$1 AND c.grade_id=$2 AND c.school_id=$3 AND g.school_id=$3`, [classId, gradeId, current.school_id]);
      if (!scope.rowCount) return fail(res, 400, 'STUDENT_SCOPE_INVALID', '班级和年级不属于该学校或彼此不匹配');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ id: parts[3], ...input }));
      if (idempotency === false) return;
      const result = await query(`UPDATE students SET grade_id=$1,class_id=$2,period_id=COALESCE($3,period_id),student_no=$4,name=$5,gender=$6,birth_date=$7,region=$8,is_poverty_area=$9,updated_at=now() WHERE id=$10
        RETURNING id,school_id AS "schoolId",grade_id AS "gradeId",class_id AS "classId",student_no AS "studentNo",name,gender,birth_date::text AS "birthDate",region,is_poverty_area AS "isPovertyArea",status`, [gradeId, classId, input.periodId || null, input.studentNo ?? current.student_no, input.name || current.name, input.gender ?? current.gender, input.birthDate ?? current.birth_date, input.region ?? current.region, input.isPovertyArea ?? current.is_poverty_area, parts[3]]);
      const eventType = current.grade_id !== gradeId ? 'promoted' : (current.class_id !== classId ? 'class_transfer' : 'updated');
      await query(`INSERT INTO student_lifecycle_events(student_id,event_type,from_grade_id,from_class_id,to_grade_id,to_class_id,from_status,to_status,note,operator_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, [parts[3], eventType, current.grade_id, current.class_id, gradeId, classId, current.status, current.status, input.note || '后台档案维护', user.id]);
      await audit(user, req, `student.${eventType}`, 'student', parts[3], current, result.rows[0], current.school_id);
      return okIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'students' && parts[4] === 'status') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以调整学生状态');
      const input = await body(req);
      if (!['active', 'inactive'].includes(input.status)) return fail(res, 400, 'INVALID_ARGUMENT', '学生状态不合法');
      const before = await query('SELECT * FROM students WHERE id=$1', [parts[3]]);
      if (!before.rows[0] || !schoolAllowed(user, before.rows[0].school_id)) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ id: parts[3], status: input.status, note: input.note || '' }));
      if (idempotency === false) return;
      const result = await query(`UPDATE students SET status=$1,updated_at=now() WHERE id=$2 RETURNING id,status`, [input.status, parts[3]]);
      const eventType = input.status === 'active' ? 'reactivated' : (input.eventType === 'transferred_out' ? 'transferred_out' : 'deactivated');
      await query(`INSERT INTO student_lifecycle_events(student_id,event_type,from_status,to_status,note,operator_id) VALUES($1,$2,$3,$4,$5,$6)`, [parts[3], eventType, before.rows[0].status, input.status, input.note || '', user.id]);
      await audit(user, req, `student.${eventType}`, 'student', parts[3], before.rows[0], result.rows[0], before.rows[0].school_id);
      return okIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/students/batch-promote') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以批量升班');
      const input = await body(req);
      let moves = input.moves;
      if ((!Array.isArray(moves) || !moves.length) && input.sourceClassId && input.toGradeId && input.toClassId) {
        const source = await query('SELECT id,school_id FROM classes WHERE id=$1', [input.sourceClassId]);
        const target = await query('SELECT c.id,g.school_id FROM classes c JOIN grades g ON g.id=c.grade_id WHERE c.id=$1 AND c.grade_id=$2', [input.toClassId, input.toGradeId]);
        if (!source.rows[0] || !target.rows[0] || source.rows[0].school_id !== target.rows[0].school_id || !schoolAllowed(user, source.rows[0].school_id)) return fail(res, 400, 'STUDENT_SCOPE_INVALID', '来源班级和目标班级不匹配');
        const students = await query(`SELECT id FROM students WHERE class_id=$1 AND school_id=$2 AND status='active' ORDER BY id LIMIT 5000`, [input.sourceClassId, source.rows[0].school_id]);
        moves = students.rows.map((student) => ({ studentId: student.id, toGradeId: input.toGradeId, toClassId: input.toClassId, periodId: input.periodId || null, note: input.note || '批量升班' }));
      }
      if (!Array.isArray(moves) || !moves.length || moves.length > 5000) return fail(res, 400, 'INVALID_ARGUMENT', '批量升班名单不能为空且最多 5000 人');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const client = await pool.connect();
      let updatedCount = 0;
      try {
        await client.query('BEGIN');
        for (const move of moves) {
          const student = await client.query('SELECT * FROM students WHERE id=$1 FOR UPDATE', [move.studentId]);
          const current = student.rows[0];
          if (!current || !schoolAllowed(user, current.school_id)) throw Object.assign(new Error('学生不存在或无权操作'), { status: 403, code: 'NO_PERMISSION' });
          const target = await client.query(`SELECT c.id AS class_id,c.grade_id,g.school_id FROM classes c JOIN grades g ON g.id=c.grade_id WHERE c.id=$1 AND c.grade_id=$2 AND c.school_id=$3`, [move.toClassId, move.toGradeId, current.school_id]);
          if (!target.rowCount) throw Object.assign(new Error('目标班级和年级不匹配'), { status: 400, code: 'STUDENT_SCOPE_INVALID' });
          await client.query(`UPDATE students SET grade_id=$1,class_id=$2,period_id=COALESCE($3,period_id),updated_at=now() WHERE id=$4`, [move.toGradeId, move.toClassId, move.periodId || null, move.studentId]);
          await client.query(`INSERT INTO student_lifecycle_events(student_id,event_type,from_grade_id,from_class_id,to_grade_id,to_class_id,from_status,to_status,note,operator_id) VALUES($1,'promoted',$2,$3,$4,$5,$6,$6,$7,$8)`, [move.studentId, current.grade_id, current.class_id, move.toGradeId, move.toClassId, current.status, move.note || '批量升班', user.id]);
          updatedCount += 1;
        }
        await client.query('COMMIT');
        await audit(user, req, 'student.batch_promote', 'student', null, null, { updatedCount });
        return okIdempotently(res, user, idempotency, { updatedCount });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'tasks' && parts[3] && !parts[4]) {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权编辑测评任务');
      const input = await body(req);
      const before = await query('SELECT * FROM assessment_tasks WHERE id=$1', [parts[3]]);
      const current = before.rows[0];
      if (!current || !schoolAllowed(user, current.school_id)) return fail(res, 404, 'TASK_NOT_FOUND', '测评任务不存在或无权访问');
      if (teacherOnly(user) && (!current.class_id || !teacherClassIds(user, current.school_id).includes(current.class_id))) return fail(res, 403, 'NO_PERMISSION', '教师只能编辑所负责班级的任务');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ id: parts[3], ...input }));
      if (idempotency === false) return;
      const gradeId = input.gradeId === undefined ? current.grade_id : (input.gradeId || null);
      const classId = input.classId === undefined ? current.class_id : (input.classId || null);
      if (teacherOnly(user) && (!classId || !teacherClassIds(user, current.school_id).includes(classId))) return failIdempotently(req, res, 403, 'NO_PERMISSION', '教师只能将任务保留在所负责班级');
      if (gradeId) {
        const grade = await query('SELECT id FROM grades WHERE id=$1 AND school_id=$2', [gradeId, current.school_id]);
        if (!grade.rowCount) return fail(res, 400, 'GRADE_SCOPE_INVALID', '年级不属于该学校');
      }
      if (classId) {
        const classScope = await query('SELECT id,grade_id FROM classes WHERE id=$1 AND school_id=$2', [classId, current.school_id]);
        if (!classScope.rowCount || (gradeId && classScope.rows[0].grade_id !== gradeId)) return fail(res, 400, 'CLASS_SCOPE_INVALID', '班级不属于该学校或不属于所选年级');
      }
      const requestedItems = input.items === undefined ? current.items : normalizeFieldTaskItems(input.items);
      const protocol = input.protocolId
        ? await resolveAssessmentProtocol({ query }, { schoolId: current.school_id, protocolId: input.protocolId, testDate: input.testDate || current.test_date })
        : input.items === undefined ? protocolSnapshotFromTask(current) : await resolveAssessmentProtocol({ query }, { schoolId: current.school_id, taskItems: requestedItems, testDate: input.testDate || current.test_date });
      const taskItems = input.protocolId ? protocolTaskItems(protocol) : requestedItems;
      const result = await query(`UPDATE assessment_tasks SET title=COALESCE($1,title),test_date=COALESCE($2,test_date),location=COALESCE($3,location),grade_id=$4,class_id=$5,items=$6,protocol_id=$7,protocol_version=$8,protocol_snapshot_json=$9,updated_at=now() WHERE id=$10 RETURNING id,title,test_date::text AS "testDate",location,grade_id AS "gradeId",class_id AS "classId",items,protocol_snapshot_json AS "protocolSnapshot",status`, [input.title || null, input.testDate || null, input.location === undefined ? null : input.location, gradeId, classId, JSON.stringify(taskItems), protocol.id, protocol.version, protocol, parts[3]]);
      await audit(user, req, 'task.update', 'assessment_task', parts[3], current, result.rows[0], current.school_id);
      return okIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'tasks' && parts[4] === 'status') {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权调整测评任务状态');
      const input = await body(req);
      if (!['draft', 'published', 'closed'].includes(input.status)) return fail(res, 400, 'INVALID_ARGUMENT', '测评任务状态不合法');
      const before = await query('SELECT * FROM assessment_tasks WHERE id=$1', [parts[3]]);
      const current = before.rows[0];
      if (!current || !schoolAllowed(user, current.school_id)) return fail(res, 404, 'TASK_NOT_FOUND', '测评任务不存在或无权访问');
      if (current.status === 'closed' && input.status !== 'closed') return fail(res, 409, 'TASK_CLOSED', '已关闭任务不能重新打开');
      if (teacherOnly(user) && (!current.class_id || !teacherClassIds(user, current.school_id).includes(current.class_id))) return fail(res, 403, 'NO_PERMISSION', '教师只能管理所负责班级的任务');
      const closing = input.status === 'closed';
      const closeReason = closing ? String(input.reason || '').trim() : '';
      const unfinishedAction = closing ? String(input.unfinishedAction || '').trim() : '';
      const followUpTitle = closing ? String(input.followUpTitle || '').trim() : '';
      const followUpDate = closing && input.followUpDate ? effectiveDate(input.followUpDate, '后续任务日期') : null;
      if (closing && current.status !== 'closed' && (!closeReason || closeReason.length > 500)) return fail(res, 400, 'TASK_CLOSE_REASON_REQUIRED', '关闭原因必填，且不能超过 500 个字符');
      if (closing && current.status !== 'closed' && !['close_incomplete', 'create_followup'].includes(unfinishedAction)) return fail(res, 400, 'TASK_CLOSE_ACTION_REQUIRED', '请选择未完成学生的后续处理方式');
      if (unfinishedAction === 'create_followup' && !followUpDate) return fail(res, 400, 'TASK_CLOSE_FOLLOWUP_DATE_REQUIRED', '创建后续任务时必须填写测评日期');
      if (followUpTitle.length > 160) return fail(res, 400, 'TASK_CLOSE_FOLLOWUP_TITLE_INVALID', '后续任务标题不能超过 160 个字符');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ id: parts[3], ...input }));
      if (idempotency === false) return;
      if (!closing) {
        const result = await query(`UPDATE assessment_tasks SET status=$1,updated_at=now() WHERE id=$2 RETURNING id,status,updated_at AS "updatedAt"`, [input.status, parts[3]]);
        if (input.status === 'published') await ensureFieldQueue({ query }, { school_id: current.school_id }, parts[3]);
        await audit(user, req, `task.status.${input.status}`, 'assessment_task', parts[3], current, result.rows[0], current.school_id);
        return okIdempotently(res, user, idempotency, result.rows[0]);
      }
      if (current.status === 'closed') {
        const summary = await query(`SELECT COUNT(*)::int AS "totalCount",COUNT(*) FILTER(WHERE ${validTaskCompletionPredicate('ts', 't')})::int AS "completedCount",
          COUNT(*) FILTER(WHERE NOT ${validTaskCompletionPredicate('ts', 't')})::int AS "incompleteStudentCount"
          FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id WHERE ts.task_id=$1`, [parts[3]]);
        return okIdempotently(res, user, idempotency, { id: parts[3], status: 'closed', alreadyClosed: true, ...summary.rows[0] });
      }
      const client = await pool.connect();
      let response;
      try {
        await client.query('BEGIN');
        const locked = await client.query('SELECT * FROM assessment_tasks WHERE id=$1 FOR UPDATE', [parts[3]]);
        const lockedTask = locked.rows[0];
        if (!lockedTask || lockedTask.status === 'closed') throw Object.assign(new Error('任务状态已变化，请刷新后重试'), { status: 409, code: 'TASK_CLOSE_STATE_CHANGED' });
        const active = await client.query(`SELECT COUNT(DISTINCT active.student_id)::int AS count FROM (
          SELECT student_id FROM test_sessions WHERE task_id=$1 AND status IN ('created','checked_in','testing')
          UNION SELECT student_id FROM test_queue_entries WHERE task_id=$1 AND status='testing'
        ) active`, [parts[3]]);
        if (Number(active.rows[0]?.count || 0) > 0) throw Object.assign(new Error(`还有 ${active.rows[0].count} 名学生正在测试，须先完成或安全结束会话`), { status: 409, code: 'TASK_CLOSE_ACTIVE_SESSIONS' });
        const reviews = await client.query(`SELECT COUNT(DISTINCT pending.student_id)::int AS count FROM (
          SELECT student_id FROM test_sessions WHERE task_id=$1 AND status IN ('needs_review','sync_conflict')
          UNION SELECT student_id FROM task_students WHERE task_id=$1 AND status='待复核'
          UNION SELECT student_id FROM assessment_scores WHERE task_id=$1 AND review_status='pendingReview'
        ) pending`, [parts[3]]);
        if (Number(reviews.rows[0]?.count || 0) > 0) throw Object.assign(new Error(`还有 ${reviews.rows[0].count} 名学生存在待复核成绩或同步冲突，须先处理后再关闭`), { status: 409, code: 'TASK_CLOSE_PENDING_REVIEWS' });
        const anomalies = await client.query(`SELECT COUNT(*)::int AS count FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id
          WHERE ts.task_id=$1 AND ts.status='已完成' AND NOT ${validTaskCompletionPredicate('ts', 't')}`, [parts[3]]);
        if (Number(anomalies.rows[0]?.count || 0) > 0) throw Object.assign(new Error(`还有 ${anomalies.rows[0].count} 条完成记录缺少有效成绩，须先处理完成异常`), { status: 409, code: 'TASK_CLOSE_COMPLETION_ANOMALIES' });
        const counts = await client.query(`SELECT COUNT(*)::int AS "totalCount",COUNT(*) FILTER(WHERE ${validTaskCompletionPredicate('ts', 't')})::int AS "completedCount",
          COUNT(*) FILTER(WHERE NOT ${validTaskCompletionPredicate('ts', 't')})::int AS "incompleteStudentCount"
          FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id WHERE ts.task_id=$1`, [parts[3]]);
        const incompleteStudentCount = Number(counts.rows[0]?.incompleteStudentCount || 0);
        if (unfinishedAction === 'create_followup' && incompleteStudentCount === 0) throw Object.assign(new Error('当前没有未完成学生，无需创建后续任务'), { status: 409, code: 'TASK_CLOSE_FOLLOWUP_EMPTY' });
        const closureNote = `任务关闭：${closeReason}`;
        const cancelledQueue = await client.query(`WITH targets AS (
            SELECT id,status AS old_status,station_id FROM test_queue_entries
            WHERE task_id=$1 AND status IN ('waiting','called','checked_in','retest','paused') FOR UPDATE
          ), updated AS (
            UPDATE test_queue_entries q SET status='cancelled',note=$2,state_version=q.state_version+1,updated_at=now()
            FROM targets target WHERE q.id=target.id RETURNING q.id,q.station_id,target.old_status
          ) INSERT INTO queue_events(queue_entry_id,old_status,new_status,reason,actor_type,actor_id,station_id)
            SELECT id,old_status,'cancelled',$2,$3,$4,station_id FROM updated RETURNING queue_entry_id`,
          [parts[3], closureNote, hasRole(user, 'admin') ? 'admin' : 'teacher', user.id]);
        const incompleteEvents = await client.query(`WITH targets AS (
            SELECT ts.id,ts.student_id,ts.status AS old_status,ts.version AS old_version FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id
            WHERE ts.task_id=$1 AND NOT ${validTaskCompletionPredicate('ts', 't')} FOR UPDATE OF ts
          ), updated AS (
            UPDATE task_students ts SET status='未完成',note=CASE WHEN COALESCE(ts.note,'')='' THEN $2 ELSE ts.note || E'\\n' || $2 END,
              completed_at=NULL,version=ts.version+1 FROM targets target WHERE ts.id=target.id
            RETURNING ts.student_id,ts.version,target.old_status,target.old_version
          ) INSERT INTO task_student_status_events(task_id,student_id,from_status,to_status,note,reason_code,operator_teacher_id,expected_version,resulting_version)
            SELECT $1,student_id,old_status,'未完成',$2,'task_closed',$3,old_version,version FROM updated RETURNING student_id`,
          [parts[3], closureNote, user.id]);
        let followUpTask = null;
        if (unfinishedAction === 'create_followup') {
          const followUp = await client.query(`INSERT INTO assessment_tasks(school_id,title,test_date,location,grade_id,class_id,items,rule_version,protocol_id,protocol_version,protocol_snapshot_json,status,created_by)
            VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'draft',$12)
            RETURNING id,title,test_date::text AS "testDate",status`, [lockedTask.school_id, followUpTitle || `${lockedTask.title}（后续补测）`, followUpDate, lockedTask.location, lockedTask.grade_id, lockedTask.class_id, JSON.stringify(lockedTask.items || []), lockedTask.rule_version, lockedTask.protocol_id, lockedTask.protocol_version, lockedTask.protocol_snapshot_json, user.id]);
          await client.query(`INSERT INTO task_students(task_id,student_id)
            SELECT $1,student_id FROM task_students WHERE task_id=$2 AND status='未完成'`, [followUp.rows[0].id, parts[3]]);
          followUpTask = { ...followUp.rows[0], studentCount: incompleteStudentCount };
        }
        const updatedTask = await client.query(`UPDATE assessment_tasks SET status='closed',updated_at=now() WHERE id=$1
          RETURNING id,status,updated_at AS "updatedAt"`, [parts[3]]);
        await client.query('COMMIT');
        response = {
          ...updatedTask.rows[0], reason: closeReason, unfinishedAction,
          totalCount: Number(counts.rows[0]?.totalCount || 0), completedStudentCount: Number(counts.rows[0]?.completedCount || 0),
          incompleteStudentCount: incompleteEvents.rowCount, cancelledQueueCount: cancelledQueue.rowCount,
          followUpTask
        };
      } catch (error) {
        await client.query('ROLLBACK').catch(() => {});
        if (error.status && error.code) return failIdempotently(req, res, error.status, error.code, error.message);
        throw error;
      } finally { client.release(); }
      await audit(user, req, 'task.status.closed', 'assessment_task', parts[3], current, response, current.school_id);
      if (response.followUpTask) await audit(user, req, 'task.followup.created', 'assessment_task', response.followUpTask.id, null, { sourceTaskId: parts[3], studentCount: response.followUpTask.studentCount }, current.school_id);
      void publishFieldUpdate(current.school_id, 'task.closed', { taskId: parts[3], reason: closeReason, incompleteStudentCount: response.incompleteStudentCount, followUpTaskId: response.followUpTask?.id || null });
      return okIdempotently(res, user, idempotency, response);
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'tasks' && parts[4] === 'sync-students') {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权同步测评名单');
      const task = await query('SELECT * FROM assessment_tasks WHERE id=$1', [parts[3]]);
      const current = task.rows[0];
      if (!current || !schoolAllowed(user, current.school_id)) return fail(res, 404, 'TASK_NOT_FOUND', '测评任务不存在或无权访问');
      if (teacherOnly(user) && (!current.class_id || !teacherClassIds(user, current.school_id).includes(current.class_id))) return fail(res, 403, 'NO_PERMISSION', '教师只能同步所负责班级的测评名单');
      if (current.status === 'closed') return fail(res, 409, 'TASK_CLOSED', '已关闭任务不能同步学生');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ taskId: parts[3], action: 'sync-students' }));
      if (idempotency === false) return;
      const result = await query(`INSERT INTO task_students(task_id,student_id) SELECT $1,st.id FROM students st WHERE st.school_id=$2 AND st.status='active' AND ($3::text IS NULL OR st.grade_id=$3) AND ($4::text IS NULL OR st.class_id=$4) ON CONFLICT(task_id,student_id) DO NOTHING`, [parts[3], current.school_id, current.grade_id, current.class_id]);
      if (current.status === 'published') await ensureFieldQueue({ query }, { school_id: current.school_id }, parts[3]);
      await query('UPDATE assessment_tasks SET updated_at=now() WHERE id=$1', [parts[3]]);
      await audit(user, req, 'task.students.sync', 'assessment_task', parts[3], null, { addedCount: result.rowCount }, current.school_id);
      return okIdempotently(res, user, idempotency, { addedCount: result.rowCount });
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'tasks' && parts[4] === 'clone') {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权复制测评任务');
      const input = await body(req);
      const source = await query('SELECT * FROM assessment_tasks WHERE id=$1', [parts[3]]);
      const current = source.rows[0];
      if (!current || !schoolAllowed(user, current.school_id)) return fail(res, 404, 'TASK_NOT_FOUND', '测评任务不存在或无权访问');
      if (teacherOnly(user) && (!current.class_id || !teacherClassIds(user, current.school_id).includes(current.class_id))) return fail(res, 403, 'NO_PERMISSION', '教师只能复制所负责班级的测评任务');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ sourceTaskId: parts[3], ...input }));
      if (idempotency === false) return;
      const result = await query(`INSERT INTO assessment_tasks(school_id,title,test_date,location,grade_id,class_id,items,rule_version,protocol_id,protocol_version,protocol_snapshot_json,status,created_by)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'draft',$12) RETURNING id,title,status,grade_id AS "gradeId",class_id AS "classId"`, [current.school_id, input.title || `${current.title}（副本）`, input.testDate || current.test_date, input.location ?? current.location, current.grade_id, current.class_id, current.items, current.rule_version, current.protocol_id, current.protocol_version, current.protocol_snapshot_json, user.id]);
      await query(`INSERT INTO task_students(task_id,student_id) SELECT $1,student_id FROM task_students WHERE task_id=$2`, [result.rows[0].id, current.id]);
      await audit(user, req, 'task.clone', 'assessment_task', result.rows[0].id, null, { sourceTaskId: current.id }, current.school_id);
      return createdIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'schools' && parts[3] === 'grade-stats') {
      const schoolId = parts[2];
      if (!schoolStaffAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '只有学校工作人员可以查看统计');
      const scopedClasses = teacherOnly(user) ? teacherClassIds(user, schoolId) : null;
      const result = await query(`WITH active_task AS (SELECT id,items FROM assessment_tasks WHERE school_id=$1 AND status='published' ORDER BY ${operationalTaskOrder()},created_at DESC LIMIT 1)
        SELECT g.id,g.name,g.standard_version AS "standardVersion",COUNT(st.id)::int AS "studentCount",
        COUNT(*) FILTER(WHERE ${validTaskCompletionPredicate('ts', 'at')})::int AS "completedCount",
        COALESCE(ROUND(100.0*COUNT(*) FILTER(WHERE ${validTaskCompletionPredicate('ts', 'at')})/NULLIF(COUNT(st.id),0)),0)::int AS "completionRate"
        FROM grades g LEFT JOIN students st ON st.grade_id=g.id AND st.status='active'
        LEFT JOIN active_task at ON true
        LEFT JOIN task_students ts ON ts.student_id=st.id AND ts.task_id=at.id
        WHERE g.school_id=$1 AND ($2::text[] IS NULL OR st.class_id=ANY($2)) GROUP BY g.id HAVING ($2::text[] IS NULL OR COUNT(st.id)>0) ORDER BY g.name`, [schoolId, scopedClasses]);
      return ok(res, result.rows);
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'schools' && parts[3] === 'class-stats') {
      const schoolId = parts[2];
      if (!schoolStaffAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '只有学校工作人员可以查看统计');
      const gradeId = queryValue(url, 'gradeId') || null;
      const scopedClasses = teacherOnly(user) ? teacherClassIds(user, schoolId) : null;
      const result = await query(`WITH active_task AS (SELECT id,items FROM assessment_tasks WHERE school_id=$1 AND status='published' ORDER BY ${operationalTaskOrder()},created_at DESC LIMIT 1)
        SELECT c.id,c.name,c.grade_id AS "gradeId",COALESCE(u.name,'未分配') AS "teacherName",COUNT(st.id)::int AS "studentCount",
        COALESCE(ROUND(100.0*COUNT(*) FILTER(WHERE ${validTaskCompletionPredicate('ts', 'at')})/NULLIF(COUNT(st.id),0)),0)::int AS "completionRate"
        FROM classes c LEFT JOIN users u ON u.id=c.teacher_id LEFT JOIN students st ON st.class_id=c.id AND st.status='active'
        LEFT JOIN active_task at ON true
        LEFT JOIN task_students ts ON ts.student_id=st.id AND ts.task_id=at.id
        WHERE c.school_id=$1 AND ($2::text IS NULL OR c.grade_id=$2) AND ($3::text[] IS NULL OR c.id=ANY($3)) GROUP BY c.id,u.name ORDER BY c.name`, [schoolId, gradeId, scopedClasses]);
      return ok(res, result.rows);
    }
    await handleFileRoutes({
      req, res, user, parts, storage, query, body, rawBody, fail, ok,
      beginIdempotentRequest, requestBodyHash, createdIdempotently,
      classPostFileVisibleToUser, hasRole, corsOrigin, allowedContentTypes,
      fileSignatureMatches, maxUploadBytes, safeFileName
    });
    if (res.writableEnded) return;
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'students' && parts.length === 3) {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以创建学生');
      const input = await body(req);
      if (!input.schoolId || !input.gradeId || !input.classId || !input.name) return fail(res, 400, 'INVALID_ARGUMENT', '学校、年级、班级和姓名不能为空');
      if (!schoolAllowed(user, input.schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权操作该学校');
      const studentScope = await query(`SELECT c.id FROM classes c JOIN grades g ON g.id=c.grade_id
        WHERE c.id=$1 AND c.school_id=$2 AND g.id=$3 AND g.school_id=$2`, [input.classId, input.schoolId, input.gradeId]);
      if (!studentScope.rowCount) return fail(res, 400, 'STUDENT_SCOPE_INVALID', '班级和年级不属于所选学校或彼此不匹配');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const result = await query(`INSERT INTO students(school_id,grade_id,class_id,student_no,name,gender,birth_date,region,is_poverty_area)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id,name,student_no`, [input.schoolId, input.gradeId, input.classId, input.studentNo || null, input.name, input.gender || '', input.birthDate || null, input.region || '', Boolean(input.isPovertyArea)]);
      await audit(user, req, 'student.create', 'student', result.rows[0].id, null, result.rows[0], input.schoolId);
      return createdIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'tasks' && parts.length === 3) {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权创建测评任务');
      const input = await body(req);
      if (!input.schoolId || !input.title || !input.testDate) return fail(res, 400, 'INVALID_ARGUMENT', '学校、标题和测评日期不能为空');
      if (!schoolAllowed(user, input.schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权操作该学校');
      const taskScope = await query(`SELECT g.id AS grade_id,c.id AS class_id,c.grade_id AS class_grade_id
        FROM (SELECT $1::text AS school_id, $2::text AS grade_id, $3::text AS class_id) input
        LEFT JOIN grades g ON g.id=input.grade_id AND g.school_id=input.school_id
        LEFT JOIN classes c ON c.id=input.class_id AND c.school_id=input.school_id`, [input.schoolId, input.gradeId || null, input.classId || null]);
      const taskScopeRow = taskScope.rows[0];
      if (input.gradeId && !taskScopeRow?.grade_id) return fail(res, 400, 'GRADE_SCOPE_INVALID', '年级不属于所选学校');
      if (input.classId && (!taskScopeRow?.class_id || (input.gradeId && taskScopeRow.class_grade_id !== input.gradeId))) return fail(res, 400, 'CLASS_SCOPE_INVALID', '班级不属于所选学校或不属于所选年级');
      if (teacherOnly(user) && (!input.classId || !teacherClassIds(user, input.schoolId).includes(input.classId))) {
        return fail(res, 403, 'NO_PERMISSION', '教师只能创建所负责班级的测评任务');
      }
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const requestedItems = normalizeFieldTaskItems(input.items);
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const protocol = await resolveAssessmentProtocol(client, { schoolId: input.schoolId, protocolId: input.protocolId || null, taskItems: requestedItems, testDate: input.testDate });
        const taskItems = input.protocolId ? protocolTaskItems(protocol) : requestedItems;
        const task = await client.query(`INSERT INTO assessment_tasks(school_id,title,test_date,location,grade_id,class_id,items,rule_version,protocol_id,protocol_version,protocol_snapshot_json,status,created_by)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'published',$12) RETURNING id`, [input.schoolId, input.title, input.testDate, input.location || '', input.gradeId || null, input.classId || null, JSON.stringify(taskItems), input.ruleVersion || '运动能力标准 v1.0', protocol.id, protocol.version, protocol, user.id]);
        const students = await client.query(`SELECT id FROM students WHERE school_id=$1 AND status='active' AND ($2::text IS NULL OR grade_id=$2) AND ($3::text IS NULL OR class_id=$3)`, [input.schoolId, input.gradeId || null, input.classId || null]);
        for (const student of students.rows) await client.query(`INSERT INTO task_students(task_id,student_id) VALUES($1,$2) ON CONFLICT DO NOTHING`, [task.rows[0].id, student.id]);
        await ensureFieldQueue(client, { school_id: input.schoolId }, task.rows[0].id);
        await client.query('COMMIT');
        await audit(user, req, 'task.create', 'assessment_task', task.rows[0].id, null, input, input.schoolId);
        return createdIdempotently(res, user, idempotency, { id: task.rows[0].id, studentCount: students.rowCount });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }

    await handleTeacherTaskRoutes({
      req, res, user, url, parts, query, pool, teacherOnly,
      userHasCapability, fail, schoolAllowed, teacherClassIds, queryValue,
      movementItemCodes: MOVEMENT_ITEM_CODES, ok, dashboard, pagination,
      parentOnly, hasRole, listResult, studentRow, beginIdempotentRequest,
      requestBodyHash, randomToken, sha256, audit, createdIdempotently,
      failIdempotently, body, requiredString, isProduction,
      taskStatusAllowed, okIdempotently, taskStudentForUser, studentForUser,
      movementScoreRules: MOVEMENT_SCORE_RULES, normalizeScoreRows,
      normalizeScore, normalizeConfidence, normalizeReviewStatus
    });
    if (res.writableEnded) return;
    if (req.method === 'GET' && url.pathname === '/v1/admin/operations/items') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权查看运营队列');
      const schoolId = queryValue(url, 'schoolId') || user.roles.find((role) => role.school_id)?.school_id;
      if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
      const type = queryValue(url, 'type') || 'all';
      const items = [];
      const safeTaskItems = `CASE WHEN jsonb_typeof(t.items)='array' THEN t.items ELSE '[]'::jsonb END`;
      if (type === 'all' || type === 'reviews') {
        const result = await query(`SELECT s.id,s.review_status AS status,'reviews' AS type,s.item_code AS title,st.name AS "studentName",c.name AS "className",s.created_at AS "createdAt",s.confidence,t.title AS "taskTitle",s.session_id AS "sessionId"
          FROM assessment_scores s JOIN assessment_tasks t ON t.id=s.task_id JOIN students st ON st.id=s.student_id JOIN classes c ON c.id=st.class_id
          WHERE s.review_status='pendingReview' AND s.session_id IS NULL AND st.school_id=$1 ORDER BY s.created_at DESC LIMIT 100`, [schoolId]);
        items.push(...result.rows);
      }
      if (type === 'all' || type === 'reports') {
        const result = await query(`SELECT report.id,report.status,'reports' AS type,report.risk_level AS "riskLevel",report.generated_at AS "createdAt",report.task_id AS "taskId",st.name AS "studentName",c.name AS "className",t.title AS "taskTitle"
          FROM diagnosis_reports report JOIN students st ON st.id=report.student_id JOIN classes c ON c.id=st.class_id LEFT JOIN assessment_tasks t ON t.id=report.task_id
          WHERE st.school_id=$1 AND report.risk_level IN ('high','attention','unavailable') AND report.status IS DISTINCT FROM 'published'
          ORDER BY report.generated_at DESC LIMIT 100`, [schoolId]);
        items.push(...result.rows);
      }
      if (type === 'all' || type === 'fieldSessions') {
        const result = await query(`SELECT session.id,'fieldSessions' AS type,session.id AS "sessionId",session.status,st.name AS "studentName",st.student_no AS "studentNo",c.name AS "className",t.title AS "taskTitle",session.created_at AS "createdAt",
          (session.status IN ('created','checked_in','testing') AND (session.edge_device_id IS NULL OR field_device.id IS NULL OR field_device.status<>'online' OR field_device.last_heartbeat_at IS NULL OR field_device.last_heartbeat_at<now()-interval '90 seconds' OR field_device.control_state='stopped')) AS "recoveryEligible",
          (SELECT COUNT(*)::int FROM session_evidence evidence WHERE evidence.session_id=session.id AND evidence.purged_at IS NULL) AS "evidenceCount"
          FROM test_sessions session JOIN assessment_tasks t ON t.id=session.task_id JOIN students st ON st.id=session.student_id JOIN classes c ON c.id=st.class_id LEFT JOIN test_devices field_device ON field_device.id=session.edge_device_id
          WHERE session.school_id=$1 AND (session.status IN ('needs_review','aborted','sync_conflict') OR (session.status IN ('created','checked_in','testing') AND (session.edge_device_id IS NULL OR field_device.id IS NULL OR field_device.status<>'online' OR field_device.last_heartbeat_at IS NULL OR field_device.last_heartbeat_at<now()-interval '90 seconds' OR field_device.control_state='stopped')) OR (session.status='completed' AND NOT EXISTS (SELECT 1 FROM session_evidence evidence WHERE evidence.session_id=session.id)))
          ORDER BY session.created_at DESC LIMIT 100`, [schoolId]);
        items.push(...result.rows);
      }
      if (type === 'all' || type === 'retests') {
        const result = await query(`SELECT ts.id,'retests' AS type,ts.status,ts.task_id AS "taskId",ts.student_id AS "studentId",st.name AS "studentName",st.student_no AS "studentNo",c.name AS "className",t.title AS "taskTitle",COALESCE(ts.completed_at,ts.created_at) AS "createdAt",
          queue.id AS "queueEntryId",queue.status AS "queueStatus",queue.retest_count AS "retestCount",station.station_code AS "stationCode",ts.note
          FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id JOIN students st ON st.id=ts.student_id JOIN classes c ON c.id=st.class_id
          LEFT JOIN test_queue_entries queue ON queue.task_id=ts.task_id AND queue.student_id=ts.student_id LEFT JOIN test_stations station ON station.id=queue.station_id
          WHERE t.school_id=$1 AND t.status='published' AND ts.status='待补测' ORDER BY COALESCE(ts.completed_at,ts.created_at) DESC LIMIT 100`, [schoolId]);
        items.push(...result.rows);
      }
      if (type === 'all' || type === 'completionAnomalies') {
        const result = await query(`SELECT ts.id,'completionAnomalies' AS type,ts.status,ts.task_id AS "taskId",ts.student_id AS "studentId",st.name AS "studentName",st.student_no AS "studentNo",c.name AS "className",t.title AS "taskTitle",COALESCE(ts.completed_at,ts.created_at) AS "createdAt",
          jsonb_array_length(${safeTaskItems})::int AS "requiredItemCount",
          (SELECT COUNT(DISTINCT score.item_code)::int FROM assessment_scores score WHERE score.task_id=ts.task_id AND score.student_id=ts.student_id AND score.item_code IN (SELECT jsonb_array_elements_text(${safeTaskItems}))) AS "measuredItemCount",
          (SELECT COUNT(*)::int FROM assessment_scores score WHERE score.task_id=ts.task_id AND score.student_id=ts.student_id AND score.review_status='pendingReview' AND score.item_code IN (SELECT jsonb_array_elements_text(${safeTaskItems}))) AS "pendingReviewCount"
          FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id JOIN students st ON st.id=ts.student_id JOIN classes c ON c.id=st.class_id
          WHERE t.school_id=$1 AND t.status IN ('published','closed') AND ts.status='已完成' AND NOT ${validTaskCompletionPredicate('ts', 't')}
          ORDER BY COALESCE(ts.completed_at,ts.created_at) DESC LIMIT 100`, [schoolId]);
        items.push(...result.rows);
      }
      if (type === 'all' || type === 'syncConflicts') {
        const result = await query(`SELECT batch.id,'syncConflicts' AS type,batch.resolution_status AS status,batch.client_batch_id AS "clientBatchId",batch.completed_at AS "createdAt",device.name AS "deviceName",device.device_code AS "deviceCode",station.station_code AS "stationCode",batch.response_json->>'message' AS message
          FROM field_sync_batches batch JOIN test_devices device ON device.id=batch.device_id LEFT JOIN test_stations station ON station.id=device.station_id
          WHERE device.school_id=$1 AND batch.status='failed' AND batch.resolution_status='open' ORDER BY batch.completed_at DESC LIMIT 100`, [schoolId]);
        items.push(...result.rows);
      }
      if (type === 'all' || type === 'activities') {
        const result = await query(`SELECT ar.id,ar.status,'activities' AS type,a.title,ar.contact_name AS "contactName",ar.phone,ar.created_at AS "createdAt" FROM activity_registrations ar JOIN activities a ON a.id=ar.activity_id WHERE a.school_id=$1 AND ar.status='pending' ORDER BY ar.created_at DESC LIMIT 100`, [schoolId]);
        items.push(...result.rows);
      }
      if (type === 'all' || type === 'appointments') {
        const result = await query(`SELECT id,status,'appointments' AS type,expert_name AS "expertName",preferred_date AS "preferredDate",note,created_at AS "createdAt" FROM expert_appointments WHERE school_id=$1 AND status='pending' ORDER BY created_at DESC LIMIT 100`, [schoolId]);
        items.push(...result.rows);
      }
      if (type === 'all' || type === 'courseUploads') {
        const result = await query(`SELECT id,status,'courseUploads' AS type,attachment_name AS "attachmentName",attendance_count AS "attendanceCount",notes,created_at AS "createdAt" FROM course_uploads WHERE school_id=$1 AND status='pending' ORDER BY created_at DESC LIMIT 100`, [schoolId]);
        items.push(...result.rows);
      }
      if (type === 'all' || type === 'support') {
        const result = await query(`SELECT sm.id,sm.status,'support' AS type,sm.content,sm.created_at AS "createdAt",u.name AS "userName" FROM support_messages sm JOIN users u ON u.id=sm.user_id WHERE sm.school_id=$1 AND sm.status IN ('open','pending') ORDER BY sm.created_at DESC LIMIT 100`, [schoolId]);
        items.push(...result.rows);
      }
      if (type === 'all' || type === 'privacy') {
        const result = await query(`SELECT pr.id,pr.status,'privacy' AS type,pr.request_type AS "requestType",st.name AS "studentName",pr.created_at AS "createdAt" FROM privacy_requests pr JOIN students st ON st.id=pr.student_id WHERE st.school_id=$1 AND pr.status IN ('pending','approved','processing') ORDER BY pr.created_at DESC LIMIT 100`, [schoolId]);
        items.push(...result.rows);
      }
      items.sort((left, right) => new Date(right.createdAt) - new Date(left.createdAt));
      return ok(res, items.slice(0, 300));
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'operations' && parts[3] && parts[4] && parts[5] === 'status') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权处理运营事项');
      const input = await body(req);
      const type = parts[3];
      const id = parts[4];
      const allowedStatuses = {
        reviews: ['passed', 'pendingReview'],
        activities: ['confirmed', 'rejected'],
        appointments: ['confirmed', 'rejected'],
        courseUploads: ['approved', 'rejected'],
        support: ['processing', 'resolved', 'closed'],
        privacy: ['approved', 'rejected', 'processing', 'completed']
      }[type];
      if (!allowedStatuses?.includes(input.status)) return fail(res, 400, 'INVALID_ARGUMENT', '运营事项状态不合法');
      let resource;
      if (type === 'reviews') resource = await query(`SELECT s.*,st.school_id FROM assessment_scores s JOIN students st ON st.id=s.student_id WHERE s.id=$1`, [id]);
      if (type === 'activities') resource = await query(`SELECT ar.*,a.school_id FROM activity_registrations ar JOIN activities a ON a.id=ar.activity_id WHERE ar.id=$1`, [id]);
      if (type === 'appointments') resource = await query('SELECT * FROM expert_appointments WHERE id=$1', [id]);
      if (type === 'courseUploads') resource = await query('SELECT * FROM course_uploads WHERE id=$1', [id]);
      if (type === 'support') resource = await query('SELECT * FROM support_messages WHERE id=$1', [id]);
      if (type === 'privacy') resource = await query(`SELECT pr.*,st.school_id FROM privacy_requests pr JOIN students st ON st.id=pr.student_id WHERE pr.id=$1`, [id]);
      const row = resource?.rows[0];
      const schoolId = row?.school_id || row?.schoolId || null;
      if (!row || (schoolId && !schoolAllowed(user, schoolId))) return fail(res, 404, 'OPERATION_NOT_FOUND', '运营事项不存在或无权访问');
      if (type === 'reviews' && row.session_id) return fail(res, 409, 'FIELD_SESSION_REVIEW_REQUIRED', '场地成绩必须在现场会话中结合证据复核');
      const anonymizationRequest = type === 'privacy' && ['delete', 'anonymize'].includes(row.request_type);
      if (anonymizationRequest && input.status === 'completed' && !hasRole(user, 'admin')) return fail(res, 403, 'PRIVACY_DELETE_ADMIN_REQUIRED', '删除申请必须由平台管理员最终确认');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ type, id, status: input.status, note: input.note || '' }));
      if (idempotency === false) return;
      let updated;
      let jobId = null;
      if (type === 'reviews') updated = await query(`UPDATE assessment_scores SET review_status=$1,manual_reviewed=$2,note=COALESCE($3,note),updated_at=now() WHERE id=$4 RETURNING id,review_status AS status,manual_reviewed AS "humanReviewed"`, [input.status, input.status === 'passed', input.note || null, id]);
      if (anonymizationRequest && input.status === 'completed') {
        const job = await enqueueJob('privacy.anonymize', { requestId: id, studentId: row.student_id, requestedBy: user.id });
        jobId = job.id;
        updated = await query(`UPDATE privacy_requests SET status='processing',reviewed_by=$1,completed_at=NULL WHERE id=$2 RETURNING id,status`, [user.id, id]);
      }
      if (type === 'privacy' && !(anonymizationRequest && input.status === 'completed')) updated = await query(`UPDATE privacy_requests SET status=$1,reviewed_by=$2,completed_at=CASE WHEN $1 IN ('completed','rejected') THEN now() ELSE completed_at END WHERE id=$3 RETURNING id,status`, [input.status, user.id, id]);
      if (type === 'activities') updated = await query(`UPDATE activity_registrations SET status=$1 WHERE id=$2 RETURNING id,status`, [input.status, id]);
      if (type === 'appointments') updated = await query(`UPDATE expert_appointments SET status=$1 WHERE id=$2 RETURNING id,status`, [input.status, id]);
      if (type === 'courseUploads') updated = await query(`UPDATE course_uploads SET status=$1 WHERE id=$2 RETURNING id,status`, [input.status, id]);
      if (type === 'support') updated = await query(`UPDATE support_messages SET status=$1 WHERE id=$2 RETURNING id,status`, [input.status, id]);
      await audit(user, req, `operation.${type}.status`, type, id, row, { ...updated.rows[0], note: input.note || '' }, schoolId);
      return okIdempotently(res, user, idempotency, { ...updated.rows[0], ...(jobId ? { jobId } : {}) });
    }
    await handleNotificationRoutes({
      req, res, user, url, query, pool, hasRole, parentOnly, teacherOnly,
      teacherClassIds, schoolAllowed, userHasCapability, queryValue,
      noticeClassIds, body, fail, beginIdempotentRequest, requestBodyHash,
      audit, createdIdempotently, okIdempotently, ok
    });
    if (res.writableEnded) return;
    await handleCourseRoutes({ req, res, user, parts, query, hasRole, schoolAllowed, guardianStudentForUser, body, fail, requiredString, beginIdempotentRequest, requestBodyHash, failIdempotently, createdIdempotently, okIdempotently, ok, randomToken });
    if (res.writableEnded) return;
    await handleActivityRoutes({
      req, res, user, url, parts,
      query, pool, hasRole, queryValue, studentForUser, fail,
      body, requiredString, schoolAllowed, assertPhone, beginIdempotentRequest,
      requestBodyHash, failIdempotently, audit, createdIdempotently,
      okIdempotently, ok
    });
    if (res.writableEnded) return;
    await handleExpertAppointmentRoutes({
      req, res, user, parts,
      query, pool, hasRole, schoolAllowed, studentForUser, fail,
      body, requiredString, beginIdempotentRequest, requestBodyHash,
      failIdempotently, audit, okIdempotently, createdIdempotently, ok
    });
    if (res.writableEnded) return;
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'task-status') {
      // Kept as a deliberate migration error rather than inferring a student's
      // "latest" task.  A student may be in several tasks concurrently; only
      // /v1/tasks/{taskId}/students/{studentId}/status is safe to mutate.
      return fail(res, 410, 'TASK_ID_REQUIRED', '请使用包含任务编号的测评状态接口');
    }
    await handleClassPostRoutes({
      req, res, user, url, parts,
      query, hasRole, parentOnly, teacherOnly, teacherClassIds, schoolAllowed,
      userHasCapability, classPostVisibleToUser, body, requiredString,
      fail, beginIdempotentRequest, requestBodyHash, failIdempotently,
      audit, createdIdempotently, okIdempotently, created, ok
    });
    if (res.writableEnded) return;
    await handleFamilyHealthRoutes({
      req, res, user, url, parts,
      query, pool, hasRole, guardianStudentForUser, queryValue, fieldObject,
      body, requiredString, fail, beginIdempotentRequest, requestBodyHash,
      failIdempotently, audit, createdIdempotently, okIdempotently, ok
    });
    if (res.writableEnded) return;
    await handleSupportRoutes({ req, res, user, parts, query, body, requiredString, schoolAllowed, fail, beginIdempotentRequest, requestBodyHash, createdIdempotently, audit });
    if (res.writableEnded) return;
    await handleProductEventRoutes({ req, res, user, url, body, query, fail, ok, consumePersistentRateLimit });
    if (res.writableEnded) return;
    await handleContentOperationRoutes({
      req, res, user, url, parts, query, pool, hasRole, schoolAllowed,
      body, fail, requiredString, beginIdempotentRequest, requestBodyHash,
      failIdempotently, audit, createdIdempotently, okIdempotently, ok
    });
    if (res.writableEnded) return;
    if (req.method === 'GET' && url.pathname === '/v1/reports') {
      const schoolId = queryValue(url, 'schoolId');
      if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问报告列表');
      const page = pagination(url);
      const riskLevel = queryValue(url, 'riskLevel') || null;
      let reportScope = '';
      const scopeParams = [schoolId, riskLevel];
      if (parentOnly(user)) {
        scopeParams.push(user.id);
        reportScope = ` AND dr.status='published' AND EXISTS (SELECT 1 FROM parent_student_bindings pb WHERE pb.parent_user_id=$3 AND pb.student_id=st.id AND pb.status='active')`;
      } else if (teacherOnly(user)) {
        scopeParams.push(teacherClassIds(user, schoolId));
        reportScope = ` AND st.class_id=ANY($3)`;
      } else if (!hasRole(user, 'admin', 'principal')) {
        return fail(res, 403, 'NO_PERMISSION', '无权访问报告列表');
      }
      const count = await query(`SELECT COUNT(*)::int AS total FROM diagnosis_reports dr JOIN students st ON st.id=dr.student_id WHERE st.school_id=$1 AND ($2::text IS NULL OR dr.risk_level=$2)${reportScope}`, scopeParams);
      const result = await query(`SELECT dr.id,dr.student_id AS "studentId",st.name AS "studentName",c.name AS "className",g.name AS "gradeName",dr.task_id AS "taskId",dr.risk_level AS "riskLevel",dr.total_score AS "totalScore",dr.rule_version AS "ruleVersion",dr.status,dr.current_version AS "currentVersion",dr.published_version AS "publishedVersion",(dr.published_version IS NOT NULL AND dr.current_version <> dr.published_version) AS "hasDraft",dr.generated_at AS "generatedAt",dr.published_at AS "publishedAt"
        FROM diagnosis_reports dr JOIN students st ON st.id=dr.student_id JOIN classes c ON c.id=st.class_id JOIN grades g ON g.id=st.grade_id
        WHERE st.school_id=$1 AND ($2::text IS NULL OR dr.risk_level=$2)${reportScope} ORDER BY dr.generated_at DESC LIMIT $${scopeParams.length + 1} OFFSET $${scopeParams.length + 2}`, [...scopeParams, page.pageSize, page.offset]);
      return ok(res, listResult(url, result.rows, count.rows[0].total));
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'reports' && parts[3] === 'publish') {
      if (!hasRole(user, 'teacher', 'principal', 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有学校工作人员可以发布报告');
      const reportResult = await query(`SELECT dr.*,st.school_id,st.class_id FROM diagnosis_reports dr JOIN students st ON st.id=dr.student_id WHERE dr.id=$1`, [parts[2]]);
      const reportRow = reportResult.rows[0];
      if (!reportRow || !schoolAllowed(user, reportRow.school_id)) return fail(res, 404, 'REPORT_NOT_FOUND', '报告不存在或无权访问');
      if (teacherOnly(user) && !teacherClassIds(user, reportRow.school_id).includes(reportRow.class_id)) return fail(res, 403, 'NO_PERMISSION', '教师只能发布所负责班级的报告');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ reportId: parts[2], action: 'publish' }));
      if (idempotency === false) return;
      if (!reportRow.current_version) return failIdempotently(req, res, 409, 'REPORT_VERSION_INVALID', '报告没有可发布版本');
      const updated = await query(`UPDATE diagnosis_reports SET status='published',published_at=now(),published_version=current_version WHERE id=$1 RETURNING id,status,published_at AS "publishedAt",current_version AS "currentVersion",published_version AS "publishedVersion"`, [parts[2]]);
      await audit(user, req, 'report.publish', 'diagnosis_report', parts[2], reportRow, updated.rows[0], reportRow.school_id);
      return okIdempotently(res, user, idempotency, updated.rows[0]);
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'reports' && parts[3] === 'withdraw') {
      if (!hasRole(user, 'teacher', 'principal', 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有学校工作人员可以撤回报告');
      const reportResult = await query(`SELECT dr.*,st.school_id,st.class_id FROM diagnosis_reports dr JOIN students st ON st.id=dr.student_id WHERE dr.id=$1`, [parts[2]]);
      const reportRow = reportResult.rows[0];
      if (!reportRow || !schoolAllowed(user, reportRow.school_id)) return fail(res, 404, 'REPORT_NOT_FOUND', '报告不存在或无权访问');
      if (teacherOnly(user) && !teacherClassIds(user, reportRow.school_id).includes(reportRow.class_id)) return fail(res, 403, 'NO_PERMISSION', '教师只能撤回所负责班级的报告');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ reportId: parts[2], action: 'withdraw' }));
      if (idempotency === false) return;
      const updated = await query(`UPDATE diagnosis_reports SET status='withdrawn' WHERE id=$1 RETURNING id,status`, [parts[2]]);
      await audit(user, req, 'report.withdraw', 'diagnosis_report', parts[2], reportRow, updated.rows[0], reportRow.school_id);
      return okIdempotently(res, user, idempotency, updated.rows[0]);
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'body-assessments') {
      const input = await body(req);
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      return createdIdempotently(res, user, idempotency, await bodyAssessmentForUser(user, parts[2], input, req));
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'body-assessments' && parts[4] === 'latest') {
      if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家长可以查看家庭测评');
      const student = await guardianStudentForUser(user, parts[2]);
      if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或未绑定');
      const result = await query(`SELECT ba.*,ba.height_cm AS "heightCm",ba.weight_kg AS "weightKg",ba.algorithm_version AS "algorithmVersion",ba.consent_version AS "consentVersion",ba.measured_at AS "measuredAt",ba.data_json AS data,
        COALESCE(json_agg(json_build_object('captureTask',ps.capture_task,'sampleCount',ps.sample_count,'confidence',ps.confidence,'metrics',ps.metrics_json)) FILTER(WHERE ps.id IS NOT NULL),'[]'::json) AS snapshots
        FROM body_assessments ba LEFT JOIN posture_snapshots ps ON ps.body_assessment_id=ba.id WHERE ba.student_id=$1 AND ba.parent_user_id=$2 GROUP BY ba.id ORDER BY ba.measured_at DESC LIMIT 1`, [parts[2], user.id]);
      if (!result.rows[0]) return fail(res, 404, 'BODY_ASSESSMENT_NOT_FOUND', '暂无家庭测评记录');
      const row = result.rows[0];
      const storedAge = row.data?.bodyReport && Number.isInteger(row.data.bodyReport.ageMonths)
        ? row.data.bodyReport.ageMonths
        : null;
      const measuredAt = row.measuredAt instanceof Date ? row.measuredAt : new Date(row.measuredAt);
      const ageAtMeasurement = storedAge ?? ageMonthsFromBirthDate(student.birth_date, measuredAt);
      const bodyReport = publicationSafeBodyReport(scoreBodyAssessment({ heightCm: row.heightCm, weightKg: row.weightKg, ageMonths: ageAtMeasurement, gender: student.gender, snapshots: row.snapshots || [] }));
      const screening = await query(`SELECT s.id AS "sessionId",s.status,s.version,d.id AS "decisionId",d.route,d.outcome_level AS "outcomeLevel",d.reason_codes AS "reasonCodes",d.model_confidence::float8 AS "modelConfidence",d.model_uncertainty::float8 AS "modelUncertainty",d.quality_score AS "qualityScore",d.review_required AS "reviewRequired",d.policy_version AS "decisionPolicyVersion",d.decided_at AS "decidedAt",
        r.status AS "reviewStatus",r.decision AS "reviewDecision",r.comment AS "reviewComment",COALESCE(r.requested_recapture_tasks,'[]'::jsonb) AS "requestedRecaptureTasks",r.version AS "reviewVersion",r.reviewed_at AS "reviewedAt"
        FROM body_screening_sessions s JOIN body_screening_decisions d ON d.session_id=s.id
        LEFT JOIN LATERAL (SELECT br.status,br.decision,br.comment,br.requested_recapture_tasks,br.version,br.reviewed_at FROM body_screening_reviews br WHERE br.session_id=s.id ORDER BY br.created_at DESC LIMIT 1) r ON true
        WHERE s.body_assessment_id=$1`, [row.id]);
      return ok(res, {
        ...row,
        heightCm: Number(row.heightCm),
        weightKg: Number(row.weightKg),
        bmi: Number(row.bmi),
        overallLevel: bodyReport.overallLevel,
        algorithmVersion: POSTURE_ALGORITHM_VERSION,
        snapshots: row.snapshots || [],
        ...bodyReport,
        screeningDecision: screening.rows[0] || null
      });
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'body-screening' && parts[2] === 'reviews') {
      const schoolId = String(url.searchParams.get('schoolId') || '');
      if (!schoolId || !schoolStaffAllowed(user, schoolId) || !await userHasCapability(user, 'REVIEW_RESULT', schoolId)) return fail(res, 403, 'NO_PERMISSION', '没有该学校身体筛查复核权限');
      const classIds = teacherOnly(user) ? teacherClassIds(user, schoolId) : [];
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') || 30)));
      const result = await query(`SELECT r.id AS "reviewId",r.session_id AS "sessionId",r.status,r.version,r.created_at AS "createdAt",s.student_id AS "studentId",st.class_id AS "classId",concat(left(st.name,1),'同学') AS "studentDisplayName",d.route,d.outcome_level AS "outcomeLevel",d.reason_codes AS "reasonCodes",d.quality_score AS "qualityScore",d.model_confidence::float8 AS "modelConfidence",d.model_uncertainty::float8 AS "modelUncertainty",d.decided_at AS "decidedAt",s.protocol_version AS "protocolVersion",s.model_version AS "modelVersion",s.threshold_version AS "thresholdVersion",ba.measured_at AS "measuredAt",
        COALESCE((SELECT jsonb_agg(jsonb_build_object('captureTask',a.capture_task,'attemptCount',a.attempt_count,'sampleCount',a.sample_count,'confidence',a.confidence::float8,'qualityScore',a.quality_score,'qualityEvents',a.quality_events_json,'repeatabilityDifference',a.repeatability_difference::float8,'capturedAt',a.captured_at,'metrics',a.metrics_json) ORDER BY a.capture_task) FROM body_screening_attempts a WHERE a.session_id=s.id),'[]'::jsonb) AS attempts
        FROM body_screening_reviews r JOIN body_screening_sessions s ON s.id=r.session_id JOIN students st ON st.id=s.student_id JOIN body_screening_decisions d ON d.session_id=s.id LEFT JOIN body_assessments ba ON ba.id=s.body_assessment_id
        WHERE st.school_id=$1 AND r.status IN ('pending','in_review') AND ($2::text[] IS NULL OR st.class_id=ANY($2::text[])) ORDER BY r.created_at ASC LIMIT $3`, [schoolId, teacherOnly(user) ? classIds : null, limit]);
      const reviews = result.rows.map((row) => ({
        ...row,
        attempts: (Array.isArray(row.attempts) ? row.attempts : []).map(({ metrics, ...attempt }) => ({
          ...attempt,
          evidenceMetrics: bodyScreeningEvidenceMetrics(metrics, attempt.captureTask)
        }))
      }));
      return ok(res, reviews);
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'body-screening' && parts[2] === 'reviews' && parts[4] === 'decision') {
      const input = await body(req);
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const found = await client.query(`SELECT r.*,s.student_id,s.guardian_user_id,st.school_id,st.class_id FROM body_screening_reviews r JOIN body_screening_sessions s ON s.id=r.session_id JOIN students st ON st.id=s.student_id WHERE r.id=$1 FOR UPDATE OF r`, [parts[3]]);
        const review = found.rows[0];
        if (!review || !schoolStaffAllowed(user, review.school_id) || !await userHasCapability(user, 'REVIEW_RESULT', review.school_id, review.class_id)) throw Object.assign(new Error('复核记录不存在或无权访问'), { status: 404, code: 'REVIEW_NOT_FOUND' });
        const expectedVersion = Number(input.expectedVersion);
        if (!Number.isInteger(expectedVersion) || expectedVersion !== review.version) throw Object.assign(new Error('复核记录已被其他人员更新，请刷新后重试'), { status: 409, code: 'VERSION_CONFLICT', data: { currentVersion: review.version } });
        const decision = String(input.decision || '');
        if (!['archive','continue_observation','refer_for_professional_assessment','recapture'].includes(decision)) throw Object.assign(new Error('复核决定不合法'), { status: 400, code: 'REVIEW_DECISION_INVALID' });
        const reviewComment = String(input.comment || '').trim().slice(0, 2000);
        if (!reviewComment) throw Object.assign(new Error('请填写复核依据和后续处理说明'), { status: 400, code: 'REVIEW_COMMENT_REQUIRED' });
        const recaptureTasks = Array.isArray(input.requestedRecaptureTasks) ? [...new Set(input.requestedRecaptureTasks.map(String))] : [];
        if (decision === 'recapture' && (!recaptureTasks.length || recaptureTasks.some((task) => !['standingBack','forwardBend','seatedPosture','gaitVideo'].includes(task)))) throw Object.assign(new Error('请求重拍时必须指定有效动作'), { status: 400, code: 'RECAPTURE_TASKS_REQUIRED' });
        const nextStatus = decision === 'recapture' ? 'recapture_requested' : 'completed';
        const updated = await client.query(`UPDATE body_screening_reviews SET reviewer_user_id=$1,status=$2,decision=$3,comment=$4,requested_recapture_tasks=$5,version=version+1,reviewed_at=CASE WHEN $2='completed' THEN now() ELSE NULL END,updated_at=now() WHERE id=$6 RETURNING id AS "reviewId",session_id AS "sessionId",status,decision,comment,requested_recapture_tasks AS "requestedRecaptureTasks",version,reviewed_at AS "reviewedAt"`, [user.id, nextStatus, decision, reviewComment, recaptureTasks, review.id]);
        await client.query(`UPDATE body_screening_sessions SET status=$1,version=version+1,updated_at=now() WHERE id=$2`, [decision === 'recapture' ? 'recapture_required' : 'review_completed', review.session_id]);
        const parentMessage = decision === 'recapture'
          ? { title: '身体观察需要重新采集', content: '学校专业人员已完成复核，请按页面提示重新采集指定动作。', action: '重新采集' }
          : decision === 'refer_for_professional_assessment'
            ? { title: '身体观察复核已完成', content: '学校专业人员建议进一步进行线下专业评估，请查看处理说明并联系学校。', action: '查看复核结果' }
            : { title: '身体观察复核已完成', content: '学校专业人员已完成本次家庭身体观察复核，请查看最新处理结果。', action: '查看复核结果' };
        await client.query(`INSERT INTO messages(receiver_user_id,title,content,category,message_type,business_id,business_route,child_id,action_label)
          VALUES($1,$2,$3,'健康提醒','bodyScreeningReview',$4,'bodyAssessment',$5,$6)`, [review.guardian_user_id, parentMessage.title, parentMessage.content, `${review.id}:v${updated.rows[0].version}`, review.student_id, parentMessage.action]);
        await client.query('COMMIT');
        await audit(user, req, 'body_screening.review.decision', 'body_screening_review', review.id, { status: review.status, version: review.version }, updated.rows[0], review.school_id);
        return okIdempotently(res, user, idempotency, updated.rows[0]);
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally { client.release(); }
    }
    await handlePrivacyRoutes({
      req, res, user, url, parts, query, hasRole, guardianStudentForUser,
      queryValue, body, fail, beginIdempotentRequest, requestBodyHash,
      failIdempotently, acceptedIdempotently, okIdempotently, ok, audit,
      enqueueJob
    });
    if (res.writableEnded) return;
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'report') return ok(res, await reportFor(user, parts[2]));
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'report' && parts[4] === 'refresh') {
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentId: parts[2], action: 'report.refresh' }));
      if (idempotency === false) return;
      return okIdempotently(res, user, idempotency, await refreshReport(user, req, parts[2]));
    }
    await handleMessageRoutes({ req, res, user, parts, hasRole, query, fail, ok });
    if (res.writableEnded) return;
    await handleDeviceInstallationRoutes({ req, res, user, parts, query, body, fail, ok, created, audit });
    if (res.writableEnded) return;
    return fail(res, 404, 'NOT_FOUND', '接口不存在');
  } catch (error) {
    logger.error('http.request_failed', { requestId: requestId(req), method: req.method, path: req.url?.split('?')[0], error: error.message, code: error.code });
    const status = error.code === '23505' ? 409 : (error.status || 500);
    const code = error.code === '23505' ? 'DUPLICATE_RESOURCE' : (error.code || 'SERVER_ERROR');
    const message = error.code === '23505' ? '数据已存在' : (error.status ? error.message : '服务内部错误');
    if (req._idempotencyKeyHash) {
      await query(`UPDATE idempotency_keys SET status='failed',response_json=$1,response_status=$2,locked_at=NULL,expires_at=now()+interval '10 minutes' WHERE key_hash=$3`, [JSON.stringify({ status, body: { code, message, data: null } }), status, req._idempotencyKeyHash]).catch((releaseError) => logger.warn('idempotency.release_failed', { requestId: requestId(req), error: releaseError.message }));
    }
    return fail(res, status, code, message, error.data || null);
  }
}

const server = http.createServer((req, res) => handle(req, res));
server.requestTimeout = Number(process.env.REQUEST_TIMEOUT_MS || 30_000);
server.headersTimeout = Number(process.env.HEADERS_TIMEOUT_MS || 10_000);
server.keepAliveTimeout = Number(process.env.KEEP_ALIVE_TIMEOUT_MS || 5_000);
startJobWorker({ enabled: jobWorkerEnabled, intervalMs: jobWorkerIntervalMs });
void startFieldRealtime();
server.listen(port, () => console.log(`Xiangshang Youth API listening on http://localhost:${port}`));
let shuttingDown = false;
const shutdown = async (signal) => {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info('server.shutdown_started', { signal });
  const forceExit = setTimeout(() => {
    logger.error('server.shutdown_forced', { timeoutMs: jobWorkerShutdownTimeoutMs + 5000 });
    process.exit(1);
  }, jobWorkerShutdownTimeoutMs + 5000);
  forceExit.unref();
  const closed = new Promise((resolve) => server.close(resolve));
  const drained = await stopJobWorker({ drainMs: jobWorkerShutdownTimeoutMs });
  if (!drained) logger.warn('server.shutdown_drain_timeout', { activeJobs: jobWorkerStatus().active, timeoutMs: jobWorkerShutdownTimeoutMs });
  await closed;
  fieldRealtimeClient?.release();
  await pool.end();
  clearTimeout(forceExit);
  logger.info('server.shutdown_finished');
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('uncaughtException', (error) => { logger.error('process.uncaught_exception', { error: error.stack || error.message }); void shutdown('uncaughtException'); });
process.on('unhandledRejection', (error) => logger.error('process.unhandled_rejection', { error: error?.stack || String(error) }));
