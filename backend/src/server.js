import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import ExcelJS from 'exceljs';
import { URL } from 'node:url';
import { assertServerRuntimeConfig, config } from './config.js';
import { pool, query } from './db.js';
import { logger, metricsText, recordMetric, recordRequest } from './observability.js';
import { enqueueJob, jobWorkerStatus, startJobWorker, stopJobWorker } from './jobs.js';
import { hasRole, parentOnly, schoolAllowed, schoolStaffAllowed, taskStatusAllowed, teacherClassIds, teacherOnly } from './policy.js';
import { createStorage } from './storage.js';
import { MOVEMENT_ALGORITHM_VERSION, MOVEMENT_ITEM_CODES, MOVEMENT_SCORE_RULES, evaluateMovementScores, normalizeReviewStatus, normalizeScore, normalizeTotalScore, normalizeConfidence, normalizeScoreRows } from './scoring.js';
import { POSTURE_ALGORITHM_VERSION } from './postureScoring.js';
import { finiteScalar, scoreBodyAssessment } from './bodyScoring.js';
import { MODEL_CALIBRATION_VERSION } from './modelCalibration.js';
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
import { handleActivityRoutes } from './routes/activities.js';
import { handleExpertAppointmentRoutes } from './routes/expertAppointments.js';
import { handleClassPostRoutes } from './routes/classPosts.js';
import { handleFamilyHealthRoutes } from './routes/familyHealth.js';
import { handleCourseRoutes } from './routes/courses.js';
import { handleNotificationRoutes } from './routes/notifications.js';
import { handlePrivacyRoutes } from './routes/privacy.js';
import { handleMessageRoutes } from './routes/messages.js';
import { handleSupportRoutes } from './routes/support.js';

const { port, isProduction, accessTokenTtlMinutes, refreshTokenTtlDays, maxSessionsPerUser, mfaEncryptionKey, verificationCodePepper, requireMfaForPrivileged, auditLogSigningKey, requireHealthConsent, healthRetentionDays, allowPublicRegistration, smsWebhookUrl, smsWebhookAuthorization, wechatAppId, wechatAppSecret, wechatRedirectUri, oauthStateTtlSeconds, corsOrigin, trustProxy, metricsToken, jobWorkerEnabled, jobWorkerMode, jobWorkerIntervalMs, jobWorkerShutdownTimeoutMs, fieldDeviceKeyTtlDays, fieldDeviceSigningEncryptionKey, fieldDeviceSignedRequestsRequired, fieldDeviceSignatureMaxAgeSeconds, fieldEvidenceVideoRetentionDays, fieldEvidenceDerivedRetentionDays, workerHeartbeatMaxAgeSeconds, backupEnabled, backupIntervalSeconds, backupHeartbeatMaxAgeSeconds } = config;
assertServerRuntimeConfig();
const storage = createStorage(config);

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
const fail = (res, status, code, message) => send(res, status, { code, message, data: null });

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

const pathParts = (url) => url.pathname.split('/').filter(Boolean).map(decodeURIComponent);
const queryValue = (url, key) => url.searchParams.get(key) || undefined;

const csvCell = (value) => String(value ?? '').trim();
const parseCsv = (source) => {
  const text = String(source || '').replace(/^\uFEFF/, '');
  const rows = [];
  let row = [];
  let cell = '';
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];
    if (char === '"' && quoted && next === '"') { cell += '"'; index += 1; continue; }
    if (char === '"') { quoted = !quoted; continue; }
    if (char === ',' && !quoted) { row.push(cell); cell = ''; continue; }
    if ((char === '\n' || char === '\r') && !quoted) {
      if (char === '\r' && next === '\n') index += 1;
      row.push(cell); cell = '';
      if (row.some((value) => csvCell(value))) rows.push(row);
      row = [];
      continue;
    }
    cell += char;
  }
  if (cell || row.length) { row.push(cell); if (row.some((value) => csvCell(value))) rows.push(row); }
  if (rows.length < 2) return [];
  const headers = rows.shift().map((value) => csvCell(value).replace(/^\uFEFF/, ''));
  return rows.map((values) => Object.fromEntries(headers.map((header, index) => [header, csvCell(values[index])])))
    .filter((value) => Object.values(value).some(Boolean));
};

const importField = (row, ...names) => {
  for (const name of names) {
    if (row[name] !== undefined && csvCell(row[name])) return csvCell(row[name]);
  }
  return '';
};

const booleanCell = (value) => ['1', 'true', 'yes', '是', '重点帮扶', '重点'].includes(String(value || '').trim().toLowerCase());

const parseSpreadsheetRows = async (input) => {
  if (!input.fileBase64) return [];
  let bytes;
  try { bytes = Buffer.from(String(input.fileBase64), 'base64'); } catch { throw Object.assign(new Error('Excel 文件编码无效'), { status: 400, code: 'IMPORT_FILE_INVALID' }); }
  if (!bytes.length || bytes.length > 8 * 1024 * 1024) throw Object.assign(new Error('Excel 文件为空或超过 8MB'), { status: 400, code: 'IMPORT_FILE_TOO_LARGE' });
  try {
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(bytes);
    const sheet = workbook.worksheets[0];
    if (!sheet || sheet.rowCount < 2) return [];
    const headers = sheet.getRow(1).values.slice(1).map((value) => String(value ?? '').trim());
    const rows = [];
    sheet.eachRow((row, rowNumber) => {
      if (rowNumber === 1) return;
      const values = row.values.slice(1);
      const item = Object.fromEntries(headers.map((header, index) => [header, values[index] == null ? '' : String(values[index])]))
      if (Object.values(item).some(Boolean)) rows.push(item);
    });
    return rows;
  } catch {
    throw Object.assign(new Error('Excel 文件无法解析，请使用 .xlsx 格式'), { status: 400, code: 'IMPORT_FILE_INVALID' });
  }
};

async function normalizeStudentImportRows(user, input) {
  const rawRows = Array.isArray(input.rows) ? input.rows : (input.fileBase64 ? await parseSpreadsheetRows(input) : parseCsv(input.csvText || input.csv || ''));
  if (!rawRows.length) throw Object.assign(new Error('导入文件没有有效数据行'), { status: 400, code: 'IMPORT_EMPTY' });
  if (rawRows.length > 5000) throw Object.assign(new Error('单次最多导入 5000 名学生'), { status: 400, code: 'IMPORT_TOO_LARGE' });
  const normalized = [];
  const errors = [];
  const seen = new Set();
  for (const [index, row] of rawRows.entries()) {
    const line = index + 2;
    const schoolValue = importField(row, 'schoolId', '学校ID', '学校') || input.schoolId || '';
    const gradeValue = importField(row, 'gradeId', '年级ID', 'grade', '年级');
    const classValue = importField(row, 'classId', '班级ID', 'class', '班级');
    const studentNo = importField(row, 'studentNo', '学号', '学生编号');
    const name = importField(row, 'name', '姓名', '学生姓名');
    const school = schoolValue ? (await query('SELECT id,name,status FROM schools WHERE id=$1 OR name=$1 LIMIT 1', [schoolValue])).rows[0] : null;
    const grade = school && gradeValue ? (await query(`SELECT id,name,school_id,period_id FROM grades WHERE school_id=$1 AND (id=$2 OR name=$2) ORDER BY academic_year DESC NULLS LAST LIMIT 1`, [school.id, gradeValue])).rows[0] : null;
    const classRow = school && classValue ? (await query(`SELECT id,name,school_id,grade_id,period_id FROM classes WHERE school_id=$1 AND (id=$2 OR name=$2) ${grade ? 'AND grade_id=$3' : ''} ORDER BY name LIMIT 1`, grade ? [school.id, classValue, grade.id] : [school.id, classValue])).rows[0] : null;
    const rowErrors = [];
    if (!schoolValue) rowErrors.push('缺少学校');
    else if (!school) rowErrors.push('学校不存在');
    else if (school.status !== 'active') rowErrors.push('学校已停用');
    else if (!schoolAllowed(user, school.id)) rowErrors.push('无权操作该学校');
    if (!gradeValue) rowErrors.push('缺少年级');
    else if (!grade) rowErrors.push('年级不存在或不属于该学校');
    if (!classValue) rowErrors.push('缺少班级');
    else if (!classRow) rowErrors.push('班级不存在或不属于该年级');
    if (!name) rowErrors.push('缺少姓名');
    const birthDate = importField(row, 'birthDate', '出生日期', '生日');
    if (birthDate && !/^\d{4}-\d{2}-\d{2}$/.test(birthDate)) rowErrors.push('出生日期必须是 YYYY-MM-DD');
    const key = `${school?.id || schoolValue}:${studentNo || `${classRow?.id || classValue}:${name}`}`;
    if (seen.has(key)) rowErrors.push('文件内存在重复学生');
    seen.add(key);
    if (rowErrors.length) errors.push({ line, name, errors: rowErrors });
    else normalized.push({
      schoolId: school.id,
      schoolName: school.name,
      gradeId: grade.id,
      gradeName: grade.name,
      classId: classRow.id,
      className: classRow.name,
      periodId: classRow.period_id || grade.period_id || input.periodId || null,
      studentNo: studentNo || null,
      name,
      gender: importField(row, 'gender', '性别'),
      birthDate: birthDate || null,
      region: importField(row, 'region', '地区'),
      isPovertyArea: booleanCell(importField(row, 'isPovertyArea', '重点帮扶', '重点地区'))
    });
  }
  return { rawRows, normalized, errors };
}

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

const fieldQueueStatusMap = Object.freeze({
  waiting: '未签到',
  called: '已签到',
  checked_in: '候测',
  testing: '测试中',
  completed: '已完成',
  retest: '待补测',
  absent: '缺席',
  skipped: '缺席',
  cancelled: '缺席',
  paused: '候测'
});

const queueStatusTransitions = Object.freeze({
  waiting: ['called', 'checked_in', 'absent', 'cancelled', 'paused'],
  called: ['waiting', 'checked_in', 'absent', 'skipped', 'paused'],
  checked_in: ['called', 'testing', 'retest', 'absent', 'paused'],
  testing: ['completed', 'retest', 'paused', 'cancelled'],
  completed: ['retest'],
  retest: ['waiting', 'called', 'checked_in', 'testing', 'cancelled'],
  absent: ['waiting', 'checked_in'],
  skipped: ['waiting', 'checked_in'],
  paused: ['waiting', 'called', 'checked_in', 'testing', 'retest', 'cancelled'],
  cancelled: []
});

const fieldQueueTransitionAllowed = (from, to) => from === to || Boolean(queueStatusTransitions[from]?.includes(to));
const fieldIsoDate = (value, fallback = new Date()) => {
  if (!value) return fallback;
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) ? parsed : fallback;
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

const mobileEntryAllowedForRole = (roleCode) => ['parent', 'teacher'].includes(roleCode);

/**
 * Builds the sole authorization contract consumed by native clients.  It is
 * deliberately independent from display names: a teacher may share a name
 * with another teacher without sharing a class or an operational capability.
 */
async function authClaimsForUser(user) {
  const scopedRoles = await query(`SELECT ur.id AS "userRoleId", ur.role_id AS "roleId", r.code, r.name,
      ur.school_id AS "schoolId", ur.class_id AS "classId"
    FROM user_roles ur JOIN roles r ON r.id=ur.role_id
    LEFT JOIN schools scoped_school ON scoped_school.id=ur.school_id
    WHERE ur.user_id=$1 AND (ur.school_id IS NULL OR scoped_school.status='active')
    ORDER BY CASE r.code WHEN 'parent' THEN 1 WHEN 'teacher' THEN 2 WHEN 'principal' THEN 3 ELSE 4 END, ur.created_at, ur.id`, [user.id]);
  const roleRows = scopedRoles.rows;
  const roleIds = [...new Set(roleRows.map((row) => row.roleId))];
  const roleCapabilities = roleIds.length
    ? await query(`SELECT role_id AS "roleId", capability_code AS "capabilityCode" FROM role_capabilities WHERE role_id = ANY($1::text[])`, [roleIds])
    : { rows: [] };
  const overrides = await query(`SELECT capability_code AS "capabilityCode",allowed,
      school_id AS "schoolId",class_id AS "classId"
    FROM user_capability_overrides
    WHERE user_id=$1 AND (expires_at IS NULL OR expires_at>now())`, [user.id]);
  const capsByRole = new Map();
  for (const row of roleCapabilities.rows) {
    const current = capsByRole.get(row.roleId) || new Set();
    current.add(row.capabilityCode);
    capsByRole.set(row.roleId, current);
  }
  const groups = new Map();
  for (const row of roleRows) {
    const key = `${row.code}|${row.schoolId || ''}`;
    const current = groups.get(key) || {
      roleCode: row.code,
      name: row.name,
      schoolId: row.schoolId || null,
      campusIds: [],
      authorizedGradeIds: [],
      authorizedClassIds: [],
      capabilities: new Set()
    };
    if (row.classId && !current.authorizedClassIds.includes(row.classId)) current.authorizedClassIds.push(row.classId);
    for (const capability of capsByRole.get(row.roleId) || []) current.capabilities.add(capability);
    groups.set(key, current);
  }
  // Resolve user-specific grants/denials after role grants.  A class-specific
  // override applies only to its class claim; global/school overrides apply to
  // the whole role+school group.
  for (const group of groups.values()) {
    for (const override of overrides.rows) {
      if (override.schoolId && override.schoolId !== group.schoolId) continue;
      if (override.classId && !group.authorizedClassIds.includes(override.classId)) continue;
      if (override.allowed) group.capabilities.add(override.capabilityCode);
      else group.capabilities.delete(override.capabilityCode);
    }
  }
  const classIds = [...new Set([...groups.values()].flatMap((group) => group.authorizedClassIds))];
  const gradeRows = classIds.length
    ? await query('SELECT DISTINCT grade_id AS "gradeId" FROM classes WHERE id = ANY($1::text[])', [classIds])
    : { rows: [] };
  const gradeIds = gradeRows.rows.map((row) => row.gradeId);
  const accountRoles = [...groups.values()].map((group) => ({
    roleCode: group.roleCode,
    name: group.name,
    schoolId: group.schoolId,
    campusIds: group.campusIds,
    authorizedGradeIds: group.authorizedClassIds.length ? gradeIds : [],
    authorizedClassIds: group.authorizedClassIds,
    capabilities: [...group.capabilities].sort(),
    mobileEntryAllowed: mobileEntryAllowedForRole(group.roleCode)
  }));
  const primary = accountRoles[0] || { roleCode: 'parent', schoolId: null, capabilities: [], authorizedClassIds: [] };
  const schoolName = primary.schoolId ? (await query('SELECT name FROM schools WHERE id=$1', [primary.schoolId])).rows[0]?.name || '' : '';
  const roleLabels = { parent: '家长', teacher: '教师', principal: '校长', admin: '管理员' };
  return {
    claimsVersion: 1,
    activeRole: primary.roleCode,
    accountRoles,
    user: {
      id: user.id,
      name: user.name,
      phone: user.phone || '未绑定手机号',
      role: roleLabels[primary.roleCode] || primary.roleCode,
      roleCode: primary.roleCode,
      schoolId: primary.schoolId,
      schoolName,
      avatarInitials: String(user.name).slice(0, 1),
      authorizedGradeIds: primary.authorizedGradeIds || gradeIds,
      authorizedClassIds: primary.authorizedClassIds || [],
      capabilities: primary.capabilities || [],
      mobileEntryAllowed: mobileEntryAllowedForRole(primary.roleCode)
    },
    // Retained during mobile rollout so older clients can decode the response.
    roles: accountRoles.map((role) => ({ code: role.roleCode, name: role.name, schoolId: role.schoolId, classIds: role.authorizedClassIds, capabilities: role.capabilities }))
  };
}

/**
 * Server-side authorization guard.  UI visibility is advisory only: every
 * teacher action must also match the capability and the scoped school/class
 * carried by the authoritative role claim.
 */
async function userHasCapability(user, capability, schoolId = null, classId = null) {
  if (hasRole(user, 'admin', 'principal')) return true;
  const claims = await authClaimsForUser(user);
  return claims.accountRoles.some((role) => {
    if (role.roleCode !== 'teacher' || !role.capabilities.includes(capability)) return false;
    if (schoolId && role.schoolId && role.schoolId !== schoolId) return false;
    if (classId && !role.authorizedClassIds.includes(classId)) return false;
    return true;
  });
}

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
  birthDate: row.birth_date
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
    LEFT JOIN LATERAL (SELECT status,version AS task_version FROM task_students WHERE student_id = st.id ORDER BY created_at DESC LIMIT 1) ts ON true
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
    ? query(`SELECT c.id,c.name,c.grade_id AS "gradeId",COALESCE(u.name,'未分配') AS "teacherName",COUNT(st.id)::int AS "studentCount",COALESCE(ROUND(100.0*COUNT(*) FILTER(WHERE ts.status='已完成')/NULLIF(COUNT(st.id),0)),0)::int AS "completionRate"
        FROM classes c LEFT JOIN users u ON u.id=c.teacher_id JOIN students st ON st.class_id=c.id AND st.status='active' JOIN parent_student_bindings pb ON pb.student_id=st.id AND pb.parent_user_id=$2 AND pb.status='active'
        LEFT JOIN LATERAL (SELECT status FROM task_students WHERE student_id=st.id ORDER BY created_at DESC LIMIT 1) ts ON true WHERE c.school_id=$1 GROUP BY c.id,u.name ORDER BY c.name`, [schoolId, user.id])
    : isTeacherScope
      ? query(`SELECT c.id,c.name,c.grade_id AS "gradeId",COALESCE(u.name,'未分配') AS "teacherName",COUNT(st.id)::int AS "studentCount",COALESCE(ROUND(100.0*COUNT(*) FILTER(WHERE ts.status='已完成')/NULLIF(COUNT(st.id),0)),0)::int AS "completionRate"
          FROM classes c LEFT JOIN users u ON u.id=c.teacher_id LEFT JOIN students st ON st.class_id=c.id AND st.status='active' LEFT JOIN LATERAL (SELECT status FROM task_students WHERE student_id=st.id ORDER BY created_at DESC LIMIT 1) ts ON true WHERE c.school_id=$1 AND c.id=ANY($2) GROUP BY c.id,u.name ORDER BY c.name`, [schoolId, scopedClassIds.length ? scopedClassIds : ['__none__']])
      : query(`SELECT c.id, c.name, c.grade_id AS "gradeId", COALESCE(u.name,'未分配') AS "teacherName",COUNT(st.id)::int AS "studentCount",COALESCE(ROUND(100.0 * COUNT(*) FILTER (WHERE ts.status='已完成') / NULLIF(COUNT(st.id),0)),0)::int AS "completionRate" FROM classes c LEFT JOIN users u ON u.id=c.teacher_id LEFT JOIN students st ON st.class_id=c.id AND st.status='active' LEFT JOIN LATERAL (SELECT status FROM task_students WHERE student_id=st.id ORDER BY created_at DESC LIMIT 1) ts ON true WHERE c.school_id=$1 GROUP BY c.id,u.name ORDER BY c.name`, [schoolId]);
  const tasksQuery = isParentScope
    ? query(`SELECT t.id,t.title,t.test_date AS date,t.location,COALESCE(g.name,'全校') AS "gradeName",COALESCE(c.name,'全校') AS "className",t.items,t.rule_version AS "ruleVersion",t.status,CASE WHEN t.class_id IS NULL THEN ARRAY[]::text[] ELSE ARRAY[t.class_id] END AS "classIds",ARRAY_AGG(DISTINCT ts.student_id) AS "studentIds",COUNT(ts.id)::int AS "totalCount",COUNT(ts.id) FILTER(WHERE ts.status='已完成')::int AS "completedCount" FROM assessment_tasks t LEFT JOIN grades g ON g.id=t.grade_id LEFT JOIN classes c ON c.id=t.class_id JOIN task_students ts ON ts.task_id=t.id JOIN parent_student_bindings pb ON pb.student_id=ts.student_id AND pb.parent_user_id=$2 AND pb.status='active' WHERE t.school_id=$1 GROUP BY t.id,g.name,c.name,t.class_id ORDER BY t.test_date DESC LIMIT 50`, [schoolId, user.id])
    : isTeacherScope
      ? query(`SELECT t.id,t.title,t.test_date AS date,t.location,COALESCE(g.name,'全校') AS "gradeName",COALESCE(c.name,'全校') AS "className",t.items,t.rule_version AS "ruleVersion",t.status,CASE WHEN t.class_id IS NULL THEN ARRAY[]::text[] ELSE ARRAY[t.class_id] END AS "classIds",ARRAY_AGG(DISTINCT ts.student_id) AS "studentIds",COUNT(ts.id)::int AS "totalCount",COUNT(ts.id) FILTER(WHERE ts.status='已完成')::int AS "completedCount" FROM assessment_tasks t LEFT JOIN grades g ON g.id=t.grade_id LEFT JOIN classes c ON c.id=t.class_id JOIN task_students ts ON ts.task_id=t.id JOIN students st ON st.id=ts.student_id AND st.class_id=ANY($2) WHERE t.school_id=$1 GROUP BY t.id,g.name,c.name,t.class_id ORDER BY t.test_date DESC LIMIT 50`, [schoolId, scopedClassIds.length ? scopedClassIds : ['__none__']])
      : query(`SELECT t.id,t.title,t.test_date AS date,t.location,COALESCE(g.name,'全校') AS "gradeName",COALESCE(c.name,'全校') AS "className",t.items,t.rule_version AS "ruleVersion",t.status,CASE WHEN t.class_id IS NULL THEN ARRAY[]::text[] ELSE ARRAY[t.class_id] END AS "classIds",COALESCE(ARRAY_AGG(DISTINCT ts.student_id) FILTER(WHERE ts.student_id IS NOT NULL), ARRAY[]::text[]) AS "studentIds",COUNT(ts.id)::int AS "totalCount",COUNT(ts.id) FILTER(WHERE ts.status='已完成')::int AS "completedCount" FROM assessment_tasks t LEFT JOIN grades g ON g.id=t.grade_id LEFT JOIN classes c ON c.id=t.class_id LEFT JOIN task_students ts ON ts.task_id=t.id WHERE t.school_id=$1 GROUP BY t.id,g.name,c.name,t.class_id ORDER BY t.test_date DESC LIMIT 50`, [schoolId]);
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
    tasks: tasks.rows.map((row) => ({ ...row, items: row.items || [], status: row.completedCount === row.totalCount && row.totalCount > 0 ? '已完成' : row.status === 'published' ? '未签到' : row.status === 'closed' ? '已完成' : row.status })),
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
  const result = await query(`SELECT ts.*, t.school_id, t.rule_version, st.class_id
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

const fieldInputString = (value, name, max = 160) => {
  const result = String(value || '').trim();
  if (!result || result.length > max) throw Object.assign(new Error(`${name}不合法`), { status: 400, code: 'FIELD_INPUT_INVALID' });
  return result;
};

const fieldObject = (value) => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const fieldEvidenceRetentionDaysFor = (evidenceType) => ['video', 'image'].includes(evidenceType) ? fieldEvidenceVideoRetentionDays : fieldEvidenceDerivedRetentionDays;

const assessmentStandardContext = (student, task) => ({
  schoolId: student.school_id,
  gradeId: student.grade_id || task.grade_id || null,
  region: student.region || '',
  povertyArea: Boolean(student.is_poverty_area),
  testDate: task.test_date,
  fallbackVersion: task.rule_version
});

const effectiveDate = (value, name = '生效日期') => {
  const date = String(value || '').trim();
  const parsed = new Date(`${date}T00:00:00.000Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(parsed.valueOf()) || parsed.toISOString().slice(0, 10) !== date) {
    throw Object.assign(new Error(`${name}不合法`), { status: 400, code: 'FIELD_INPUT_INVALID' });
  }
  return date;
};

async function fieldTaskForDevice(device, taskId, client = null) {
  const executor = client || { query };
  const result = await executor.query(`SELECT t.* FROM assessment_tasks t
    WHERE t.id=$1 AND t.school_id=$2`, [taskId, device.school_id]);
  if (!result.rows[0]) throw Object.assign(new Error('测评任务不存在或不属于本设备学校'), { status: 404, code: 'FIELD_TASK_NOT_FOUND' });
  if (result.rows[0].status !== 'published') throw Object.assign(new Error('只有已发布的测评任务可以下发到场地端'), { status: 409, code: 'FIELD_TASK_INACTIVE' });
  return result.rows[0];
}

const fieldHealthNumber = (value) => {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

// Formal scores are only accepted from an edge host that has explicitly
// attested its preflight state. The source hardware remains vendor-specific,
// but the safety contract is not: two depth cameras, one RGB camera, a GPU,
// frame synchronisation, calibration validation and enough local evidence
// storage must all be healthy before a session can begin.
const fieldHardwareReadiness = (device, calibration) => {
  const health = fieldObject(device?.health_json);
  const selfTest = fieldObject(health.selfTest);
  const capture = fieldObject(health.capture);
  const calibrationCheck = fieldObject(health.calibration);
  const storage = fieldObject(health.storage);
  const blockers = [];
  const storageFreeMb = fieldHealthNumber(storage.freeMb ?? health.storageFreeMb);
  const frameSyncOffsetMs = fieldHealthNumber(capture.frameSyncOffsetMs);
  const calibrationErrorCm = fieldHealthNumber(calibrationCheck.errorCm);
  const depthCameraCount = fieldHealthNumber(capture.depthCameraCount);
  const rgbCameraCount = fieldHealthNumber(capture.rgbCameraCount);

  if (health.schemaVersion !== 'field-health/v1') blockers.push('未上报 field-health/v1 场地自检结果');
  if (selfTest.passed !== true) blockers.push('边缘主机自检未通过');
  if (device?.device_type !== 'edge_host') blockers.push('正式采集必须由已注册的边缘主机发起');
  if (capture.adapterReady !== true || !String(capture.adapterName || '').trim()) blockers.push('视觉采集适配器未就绪');
  if (depthCameraCount == null || depthCameraCount < 2) blockers.push('双深度摄像头未全部通过自检');
  if (rgbCameraCount == null || rgbCameraCount < 1) blockers.push('高速 RGB 摄像头未通过自检');
  if (capture.gpuReady !== true) blockers.push('边缘 GPU 推理环境未就绪');
  if (frameSyncOffsetMs == null || frameSyncOffsetMs > 33.4) blockers.push('多机帧同步未达标（需不超过 33.4ms）');
  if (storageFreeMb == null || storageFreeMb < 5_120) blockers.push('本地证据存储空间不足（至少 5GB）');
  if (calibration) {
    if (calibrationCheck.passed !== true) blockers.push('场地标定复核未通过');
    if (String(calibrationCheck.version || '') !== String(calibration.version)) blockers.push('设备标定版本与中央下发版本不一致');
    if (String(calibrationCheck.checksumSha256 || '').toLowerCase() !== String(calibration.checksumSha256 || calibration.checksum_sha256 || '').toLowerCase()) blockers.push('设备标定校验和与中央下发版本不一致');
    if (calibrationErrorCm == null || calibrationErrorCm > 5) blockers.push('场地标定误差未达标（需不超过 5cm）');
  }
  if (health.emergencyStop === true) blockers.push('场地端处于紧急停止状态');
  return {
    ready: blockers.length === 0,
    blockers,
    summary: {
      schemaVersion: String(health.schemaVersion || ''),
      selfTestPassed: selfTest.passed === true,
      selfTestAt: selfTest.completedAt || null,
      adapterName: String(capture.adapterName || '') || null,
      depthCameraCount,
      rgbCameraCount,
      gpuReady: capture.gpuReady === true,
      frameSyncOffsetMs,
      storageFreeMb,
      calibrationVersion: String(calibrationCheck.version || '') || null,
      calibrationErrorCm,
      emergencyStop: health.emergencyStop === true
    }
  };
};

const fieldReadiness = (device, station, calibration) => {
  const blockers = [];
  if (!device.station_id) blockers.push('设备尚未绑定测试点');
  if (!station) blockers.push('测试点不存在或已删除');
  else if (station.status !== 'online') blockers.push(`测试点状态为 ${station.status}，请先检查设备心跳或维护状态`);
  if (!calibration) blockers.push('尚未下发有效标定配置');
  const hardware = fieldHardwareReadiness(device, calibration);
  blockers.push(...hardware.blockers);
  return {
    ready: blockers.length === 0,
    stationStatus: station?.status || null,
    calibrationVersion: calibration?.version || null,
    hardware: hardware.summary,
    blockers
  };
};

async function ensureFieldQueue(client, device, taskId) {
  await fieldTaskForDevice(device, taskId, client);
  await client.query(`INSERT INTO test_queue_entries(school_id,task_id,student_id,station_id,queue_order)
    SELECT $1,$2,ts.student_id,NULL,ROW_NUMBER() OVER (ORDER BY c.name,st.name)::int
      FROM task_students ts JOIN students st ON st.id=ts.student_id JOIN classes c ON c.id=st.class_id
     WHERE ts.task_id=$2
    ON CONFLICT(task_id,student_id) DO NOTHING`, [device.school_id, taskId]);
}

// Only unstarted students may move. Called, checked-in and testing students
// retain their station so identity, evidence and operator context never split
// across two physical points mid-flow.
async function rebalanceFieldQueue(client, task) {
  const stationRows = await client.query(`SELECT s.id AS "stationId",s.station_code AS "stationCode",s.queue_capacity AS "queueCapacity",s.status,
      d.*,cal.version AS "calibrationVersion",cal.checksum_sha256 AS "calibrationChecksumSha256"
    FROM test_stations s JOIN test_devices d ON d.station_id=s.id
    JOIN LATERAL (SELECT version,checksum_sha256 FROM station_calibrations WHERE station_id=s.id AND status='active' ORDER BY effective_at DESC LIMIT 1) cal ON TRUE
    WHERE s.school_id=$1 AND s.status='online' AND d.status='online' AND d.device_type='edge_host'
    ORDER BY s.station_code,d.id`, [task.school_id]);
  const stationsById = new Map();
  for (const row of stationRows.rows) {
    if (stationsById.has(row.stationId)) continue;
    const readiness = fieldReadiness(row, { id: row.stationId, status: row.status }, { version: row.calibrationVersion, checksumSha256: row.calibrationChecksumSha256 });
    if (readiness.ready) stationsById.set(row.stationId, { id: row.stationId, stationCode: row.stationCode, queueCapacity: Number(row.queueCapacity), load: 0 });
  }
  const eligibleStations = [...stationsById.values()];
  const eligibleIds = eligibleStations.map((station) => station.id);
  if (eligibleIds.length) {
    await client.query(`UPDATE test_queue_entries SET station_id=NULL,state_version=state_version+1,updated_at=now()
      WHERE task_id=$1 AND status='waiting' AND station_id IS NOT NULL AND NOT (station_id=ANY($2::text[]))`, [task.id, eligibleIds]);
  } else {
    await client.query(`UPDATE test_queue_entries SET station_id=NULL,state_version=state_version+1,updated_at=now()
      WHERE task_id=$1 AND status='waiting' AND station_id IS NOT NULL`, [task.id]);
  }
  const entries = await client.query(`SELECT id,station_id,status,priority,queue_order AS "queueOrder",created_at AS "createdAt"
    FROM test_queue_entries WHERE task_id=$1 AND status IN ('waiting','called','checked_in','testing')
    ORDER BY priority DESC,queue_order,created_at FOR UPDATE`, [task.id]);
  for (const entry of entries.rows) {
    const station = entry.station_id ? stationsById.get(entry.station_id) : null;
    if (station) station.load += 1;
  }
  const assignments = [];
  for (const entry of entries.rows.filter((item) => item.status === 'waiting' && !item.station_id)) {
    const target = eligibleStations
      .filter((station) => station.load < station.queueCapacity)
      .sort((left, right) => (left.load / left.queueCapacity) - (right.load / right.queueCapacity) || left.stationCode.localeCompare(right.stationCode))[0];
    if (!target) break;
    target.load += 1;
    await client.query(`UPDATE test_queue_entries SET station_id=$1,queue_order=$2,state_version=state_version+1,updated_at=now() WHERE id=$3`, [target.id, target.load, entry.id]);
    assignments.push({ queueEntryId: entry.id, stationId: target.id, stationCode: target.stationCode, queueOrder: target.load });
  }
  const remaining = await client.query(`SELECT COUNT(*)::int AS count FROM test_queue_entries WHERE task_id=$1 AND status='waiting' AND station_id IS NULL`, [task.id]);
  return { eligibleStations: eligibleStations.map(({ load, ...station }) => ({ ...station, assignedCount: load })), assignments, unassignedCount: Number(remaining.rows[0]?.count || 0) };
}

async function fieldBootstrap(device, taskId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    let selectedTaskId = taskId ? fieldInputString(taskId, '任务 ID') : null;
    if (!selectedTaskId) {
      const active = await client.query(`SELECT id FROM assessment_tasks WHERE school_id=$1 AND status='published'
        ORDER BY test_date DESC,created_at DESC LIMIT 1`, [device.school_id]);
      selectedTaskId = active.rows[0]?.id || null;
    }
    let task = null;
    let queue = [];
    let dispatch = null;
    if (selectedTaskId) {
      task = await fieldTaskForDevice(device, selectedTaskId, client);
      await ensureFieldQueue(client, device, selectedTaskId);
      dispatch = await rebalanceFieldQueue(client, task);
      const entries = await client.query(`SELECT q.id,q.task_id AS "taskId",q.student_id AS "studentId",q.station_id AS "stationId",q.status,
          q.priority,q.queue_order AS "queueOrder",q.retest_count AS "retestCount",q.state_version AS "stateVersion",q.note,
          q.last_called_at AS "lastCalledAt",q.updated_at AS "updatedAt",st.name AS "studentName",st.gender,st.birth_date AS "birthDate",
          st.student_no AS "studentNo",st.grade_id AS "gradeId",st.region,st.is_poverty_area AS "isPovertyArea",g.name AS "gradeName",c.name AS "className",ts.status AS "taskStatus",ts.version AS "taskVersion"
        FROM test_queue_entries q JOIN students st ON st.id=q.student_id JOIN grades g ON g.id=st.grade_id
          JOIN classes c ON c.id=st.class_id JOIN task_students ts ON ts.task_id=q.task_id AND ts.student_id=q.student_id
        WHERE q.task_id=$1 AND (q.station_id IS NULL OR q.station_id=$2)
        ORDER BY q.priority DESC,q.queue_order,q.created_at`, [selectedTaskId, device.station_id || null]);
      queue = entries.rows;
    }
    const [station, calibration, commands] = await Promise.all([
      client.query(`SELECT id,station_code AS "stationCode",name,item_code AS "itemCode",queue_capacity AS "queueCapacity",status,
          metadata_json AS metadata,last_seen_at AS "lastSeenAt",updated_at AS "updatedAt" FROM test_stations WHERE id=$1`, [device.station_id || null]),
      client.query(`SELECT version,checksum_sha256 AS "checksumSha256",config_json AS config,effective_at AS "effectiveAt"
        FROM station_calibrations WHERE station_id=$1 AND status='active' ORDER BY effective_at DESC LIMIT 1`, [device.station_id || null]),
      client.query(`SELECT id,command_type AS "commandType",payload_json AS payload,created_at AS "createdAt",expires_at AS "expiresAt"
        FROM device_commands WHERE device_id=$1 AND status IN ('pending','delivered') AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at LIMIT 50`, [device.id])
    ]);
    await client.query('COMMIT');
    const standardContexts = [...new Map(queue.map((entry) => {
      const context = assessmentStandardContext({ school_id: device.school_id, grade_id: entry.gradeId, region: entry.region, is_poverty_area: entry.isPovertyArea }, task);
      return [`${context.gradeId || ''}|${context.region}|${context.povertyArea}`, context];
    })).values()];
    const standards = await Promise.all(standardContexts.map(async (context) => ({
      ...(await resolveAssessmentStandard(client, context)),
      appliesTo: { gradeId: context.gradeId, region: context.region, povertyArea: context.povertyArea }
    })));
    const readiness = fieldReadiness(device, station.rows[0] || null, calibration.rows[0] || null);
    if (dispatch?.assignments.length) void publishFieldUpdate(device.school_id, 'queue.rebalanced', { taskId: task.id, assignments: dispatch.assignments, unassignedCount: dispatch.unassignedCount });
    return {
      serverTime: new Date().toISOString(),
      device: { id: device.id, code: device.device_code, name: device.name, type: device.device_type, softwareVersion: device.software_version },
      station: station.rows[0] || null,
      calibration: calibration.rows[0] || null,
      readiness,
      task: task ? { id: task.id, title: task.title, testDate: task.test_date, location: task.location, items: task.items || [], ruleVersion: task.rule_version, status: task.status } : null,
      queue,
      dispatch,
      standards,
      commands: commands.rows
    };
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

async function transitionFieldQueue(device, input, actor = { type: 'device', id: null }) {
  const queueEntryId = fieldInputString(input.queueEntryId || input.id, '队列记录 ID');
  const nextStatus = fieldInputString(input.status, '队列状态', 32);
  const expectedVersion = input.expectedVersion == null ? null : Number(input.expectedVersion);
  if (!Object.hasOwn(fieldQueueStatusMap, nextStatus)) throw Object.assign(new Error('队列状态不合法'), { status: 400, code: 'FIELD_QUEUE_STATUS_INVALID' });
  if (expectedVersion != null && (!Number.isInteger(expectedVersion) || expectedVersion < 1)) throw Object.assign(new Error('队列版本不合法'), { status: 400, code: 'FIELD_QUEUE_VERSION_INVALID' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(`SELECT q.*,t.school_id,ts.id AS task_student_id,ts.status AS task_student_status
      FROM test_queue_entries q JOIN assessment_tasks t ON t.id=q.task_id
        JOIN task_students ts ON ts.task_id=q.task_id AND ts.student_id=q.student_id
      WHERE q.id=$1 FOR UPDATE`, [queueEntryId]);
    const row = current.rows[0];
    if (!row || row.school_id !== device.school_id || (device.station_id && row.station_id && row.station_id !== device.station_id)) throw Object.assign(new Error('队列记录不存在或不属于本设备'), { status: 404, code: 'FIELD_QUEUE_NOT_FOUND' });
    if (!fieldQueueTransitionAllowed(row.status, nextStatus)) throw Object.assign(new Error(`不能从 ${row.status} 变更为 ${nextStatus}`), { status: 409, code: 'FIELD_QUEUE_TRANSITION_INVALID' });
    if (expectedVersion != null && Number(row.state_version) !== expectedVersion) throw Object.assign(new Error('队列已被其他终端更新，请重新同步'), { status: 409, code: 'FIELD_QUEUE_VERSION_CONFLICT' });
    const happenedAt = fieldIsoDate(input.happenedAt);
    const updated = await client.query(`UPDATE test_queue_entries SET status=$1,note=$2,state_version=state_version+1,
      last_called_at=CASE WHEN $1='called' THEN $3 ELSE last_called_at END,
      completed_at=CASE WHEN $1='completed' THEN COALESCE(completed_at,$3) ELSE completed_at END,updated_at=now()
      WHERE id=$4 RETURNING id,task_id AS "taskId",student_id AS "studentId",station_id AS "stationId",status,priority,
      queue_order AS "queueOrder",retest_count AS "retestCount",state_version AS "stateVersion",note,last_called_at AS "lastCalledAt",updated_at AS "updatedAt"`,
    [nextStatus, String(input.note || '').slice(0, 500), happenedAt, row.id]);
    const taskStatus = fieldQueueStatusMap[nextStatus];
    await client.query(`UPDATE task_students SET status=$1,note=COALESCE(NULLIF($2,''),note),
      check_in_at=CASE WHEN $1='已签到' THEN COALESCE(check_in_at,$3) ELSE check_in_at END,
      completed_at=CASE WHEN $1='已完成' THEN COALESCE(completed_at,$3) ELSE completed_at END,version=version+1
      WHERE id=$4`, [taskStatus, String(input.note || '').slice(0, 500), happenedAt, row.task_student_id]);
    await client.query(`INSERT INTO queue_events(queue_entry_id,client_event_id,old_status,new_status,reason,actor_type,actor_id,station_id,happened_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(client_event_id) DO NOTHING`,
    [row.id, input.clientEventId ? fieldInputString(input.clientEventId, '客户端事件 ID') : null, row.status, nextStatus, String(input.reason || input.note || '').slice(0, 500), actor.type, actor.id, device.station_id || null, happenedAt]);
    await client.query('COMMIT');
    void publishFieldUpdate(row.school_id, 'queue.updated', { queueEntryId: row.id, taskId: row.task_id, studentId: row.student_id, stationId: row.station_id, status: nextStatus, stateVersion: Number(updated.rows[0].stateVersion) });
    return updated.rows[0];
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

async function openFieldSession(device, input) {
  const clientSessionId = fieldInputString(input.clientSessionId, '客户端会话 ID');
  const taskId = fieldInputString(input.taskId, '任务 ID');
  const studentId = fieldInputString(input.studentId, '学生 ID');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1),hashtext($2))', [taskId, studentId]);
    const existing = await client.query(`SELECT id,client_session_id AS "clientSessionId",status,attempt_no AS "attemptNo",started_at AS "startedAt",sync_version AS "syncVersion"
      FROM test_sessions WHERE client_session_id=$1`, [clientSessionId]);
    if (existing.rows[0]) { await client.query('COMMIT'); return existing.rows[0]; }
    const task = await fieldTaskForDevice(device, taskId, client);
    const [stationResult, calibrationResult] = await Promise.all([
      client.query(`SELECT id,status FROM test_stations WHERE id=$1`, [device.station_id || null]),
      client.query(`SELECT version,checksum_sha256 AS "checksumSha256" FROM station_calibrations WHERE station_id=$1 AND status='active' ORDER BY effective_at DESC LIMIT 1`, [device.station_id || null])
    ]);
    const readiness = fieldReadiness(device, stationResult.rows[0] || null, calibrationResult.rows[0] || null);
    if (!readiness.ready) throw Object.assign(new Error(`场地端未就绪：${readiness.blockers.join('；')}`), { status: 409, code: 'FIELD_STATION_NOT_READY' });
    const roster = await client.query(`SELECT ts.id AS task_student_id,ts.status,st.grade_id,st.region,st.is_poverty_area FROM task_students ts
      JOIN students st ON st.id=ts.student_id WHERE ts.task_id=$1 AND ts.student_id=$2 AND st.school_id=$3 FOR UPDATE`, [taskId, studentId, device.school_id]);
    if (!roster.rows[0]) throw Object.assign(new Error('学生不在当前测评名单内'), { status: 404, code: 'FIELD_ROSTER_NOT_FOUND' });
    const standard = await resolveAssessmentStandard(client, assessmentStandardContext({ school_id: device.school_id, ...roster.rows[0] }, task));
    await ensureFieldQueue(client, device, taskId);
    await rebalanceFieldQueue(client, task);
    const queueResult = await client.query(`SELECT * FROM test_queue_entries WHERE task_id=$1 AND student_id=$2 FOR UPDATE`, [taskId, studentId]);
    const queue = queueResult.rows[0];
    if (queue?.station_id && queue.station_id !== device.station_id) throw Object.assign(new Error('学生已由其他测试点接管，请在对应测试点继续'), { status: 409, code: 'FIELD_QUEUE_ASSIGNED_ELSEWHERE' });
    const existingAttempts = await client.query('SELECT COALESCE(MAX(attempt_no),0)::int AS max_attempt FROM test_sessions WHERE task_id=$1 AND student_id=$2', [taskId, studentId]);
    const startedAt = fieldIsoDate(input.startedAt);
    const session = await client.query(`INSERT INTO test_sessions(client_session_id,school_id,task_id,student_id,station_id,edge_device_id,queue_entry_id,attempt_no,status,rule_version,standard_id,standard_version,standard_snapshot_json,calibration_version,algorithm_version,started_at,device_started_at,summary_json)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,'testing',$9,$10,$11,$12,$13,$14,$15,$15,$16)
      RETURNING id,client_session_id AS "clientSessionId",task_id AS "taskId",student_id AS "studentId",station_id AS "stationId",attempt_no AS "attemptNo",status,rule_version AS "ruleVersion",standard_id AS "standardId",standard_version AS "standardVersion",calibration_version AS "calibrationVersion",algorithm_version AS "algorithmVersion",started_at AS "startedAt",sync_version AS "syncVersion"`,
    [clientSessionId, device.school_id, taskId, studentId, device.station_id || null, device.id, queue?.id || null, Number(existingAttempts.rows[0].max_attempt) + 1, task.rule_version, standard.id, standard.standardVersion, standard, calibrationResult.rows[0]?.version || '', String(input.algorithmVersion || device.software_version || '').slice(0, 120), startedAt, fieldObject(input.summary)]);
    if (queue) {
      await client.query(`UPDATE test_queue_entries SET status='testing',state_version=state_version+1,updated_at=now() WHERE id=$1`, [queue.id]);
      await client.query(`INSERT INTO queue_events(queue_entry_id,old_status,new_status,reason,actor_type,actor_id,station_id,happened_at)
        VALUES($1,$2,'testing','场地端开始测试','device',$3,$4,$5)`, [queue.id, queue.status, device.id, device.station_id || null, startedAt]);
    }
    await client.query(`UPDATE task_students SET status='测试中',check_in_at=COALESCE(check_in_at,$1),version=version+1 WHERE id=$2`, [startedAt, roster.rows[0].task_student_id]);
    await client.query('COMMIT');
    void publishFieldUpdate(device.school_id, 'session.opened', { sessionId: session.rows[0].id, taskId, studentId, stationId: device.station_id || null, deviceId: device.id });
    return session.rows[0];
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

async function appendFieldSessionEvents(device, sessionId, events) {
  if (!Array.isArray(events) || !events.length || events.length > 500) throw Object.assign(new Error('采集事件数量必须在 1 到 500 条之间'), { status: 400, code: 'FIELD_EVENTS_INVALID' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const sessionResult = await client.query(`SELECT id,client_session_id,school_id,edge_device_id,status FROM test_sessions WHERE (id=$1 OR client_session_id=$1) FOR UPDATE`, [sessionId]);
    const session = sessionResult.rows[0];
    if (!session || session.school_id !== device.school_id || session.edge_device_id !== device.id) throw Object.assign(new Error('测试会话不存在或不属于本设备'), { status: 404, code: 'FIELD_SESSION_NOT_FOUND' });
    if (!['created', 'checked_in', 'testing'].includes(session.status)) throw Object.assign(new Error('当前会话不能继续写入采集事件'), { status: 409, code: 'FIELD_SESSION_CLOSED' });
    const saved = [];
    let insertedCount = 0;
    for (const event of events) {
      const clientEventId = fieldInputString(event?.clientEventId, '客户端事件 ID');
      const sequenceNo = Number(event?.sequenceNo);
      if (!Number.isInteger(sequenceNo) || sequenceNo < 0) throw Object.assign(new Error('事件序号不合法'), { status: 400, code: 'FIELD_EVENT_SEQUENCE_INVALID' });
      const eventType = fieldInputString(event?.eventType, '事件类型', 64);
      const happenedAt = fieldIsoDate(event?.happenedAt);
      const payload = fieldObject(event?.payload);
      const sameEvent = (row) => row.session_id === session.id
        && Number(row.sequence_no) === sequenceNo
        && row.event_type === eventType
        && new Date(row.happened_at).getTime() === new Date(happenedAt).getTime()
        && requestBodyHash(row.payload_json) === requestBodyHash(payload);
      const replay = await client.query('SELECT id,session_id,sequence_no,event_type,happened_at,payload_json FROM session_action_events WHERE client_event_id=$1', [clientEventId]);
      if (replay.rows[0]) {
        if (!sameEvent(replay.rows[0])) {
          recordMetric('xiangshang_field_sync_conflicts_total', { reason: 'action_replay_mismatch' });
          logger.warn('field.action_replay_mismatch', { deviceId: device.id, sessionId: session.id, clientEventId });
          throw Object.assign(new Error('采集事件 ID 已被用于不同内容，已拒绝覆盖原始时间线'), { status: 409, code: 'FIELD_ACTION_REPLAY_MISMATCH' });
        }
        saved.push({ id: replay.rows[0].id, clientEventId, sequenceNo, eventType, happenedAt });
        continue;
      }
      const sequence = await client.query('SELECT client_event_id AS "clientEventId" FROM session_action_events WHERE session_id=$1 AND sequence_no=$2', [session.id, sequenceNo]);
      if (sequence.rows[0]) throw Object.assign(new Error('采集事件序号已被其他事件占用，请重新同步会话时间线'), { status: 409, code: 'FIELD_EVENT_SEQUENCE_CONFLICT' });
      const result = await client.query(`INSERT INTO session_action_events(session_id,client_event_id,sequence_no,event_type,happened_at,payload_json)
        VALUES($1,$2,$3,$4,$5,$6)
        RETURNING id,client_event_id AS "clientEventId",sequence_no AS "sequenceNo",event_type AS "eventType",happened_at AS "happenedAt"`,
      [session.id, clientEventId, sequenceNo, eventType, happenedAt, payload]);
      if (result.rows[0]) { saved.push(result.rows[0]); insertedCount += 1; }
    }
    if (insertedCount) await client.query('UPDATE test_sessions SET sync_version=sync_version+1,updated_at=now() WHERE id=$1', [session.id]);
    await client.query('COMMIT');
    return { id: session.id, sessionId: session.id, clientSessionId: session.client_session_id, accepted: saved.length, events: saved };
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

async function completeFieldSession(device, sessionId, input) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(`SELECT s.*,t.school_id,ts.id AS task_student_id FROM test_sessions s
      JOIN assessment_tasks t ON t.id=s.task_id JOIN task_students ts ON ts.task_id=s.task_id AND ts.student_id=s.student_id
      WHERE (s.id=$1 OR s.client_session_id=$1) FOR UPDATE`, [sessionId]);
    const session = result.rows[0];
    if (!session || session.school_id !== device.school_id || session.edge_device_id !== device.id) throw Object.assign(new Error('测试会话不存在或不属于本设备'), { status: 404, code: 'FIELD_SESSION_NOT_FOUND' });
    if (['completed', 'needs_review', 'retest'].includes(session.status)) { await client.query('COMMIT'); return { id: session.id, status: session.status, idempotent: true }; }
    if (!Array.isArray(input.scores) || !input.scores.length || input.scores.length > MOVEMENT_SCORE_RULES.itemCount) throw Object.assign(new Error('必须提交 1 到 7 项成绩'), { status: 400, code: 'FIELD_SCORES_INVALID' });
    const items = new Set();
    const savedScores = [];
    const evidence = Array.isArray(input.evidence) ? input.evidence : [];
    const endedAt = fieldIsoDate(input.endedAt);
    if (evidence.length > 30) throw Object.assign(new Error('证据文件超过上限'), { status: 400, code: 'FIELD_EVIDENCE_INVALID' });
    for (const item of input.scores) {
      const itemCode = fieldInputString(item?.item, '体测项目', 64);
      const score = normalizeScore(item?.score);
      const confidence = normalizeConfidence(item?.confidence == null ? 0 : item.confidence);
      if (!MOVEMENT_ITEM_CODES.includes(itemCode) || score == null || confidence == null || items.has(itemCode)) throw Object.assign(new Error('成绩项目、分数或置信度不合法'), { status: 400, code: 'FIELD_SCORE_INVALID' });
      items.add(itemCode);
      const reviewStatus = normalizeReviewStatus(item?.reviewStatus, confidence);
      const saved = await client.query(`INSERT INTO assessment_scores(task_id,student_id,item_code,score,confidence,note,source,review_status,manual_reviewed,created_by,session_id,algorithm_version,evidence_json)
        VALUES($1,$2,$3,$4,$5,$6,'field',$7,FALSE,NULL,$8,$9,$10)
        ON CONFLICT(task_id,student_id,item_code) DO UPDATE SET score=EXCLUDED.score,confidence=EXCLUDED.confidence,note=EXCLUDED.note,source='field',review_status=EXCLUDED.review_status,manual_reviewed=FALSE,created_by=NULL,session_id=EXCLUDED.session_id,algorithm_version=EXCLUDED.algorithm_version,evidence_json=EXCLUDED.evidence_json,updated_at=now()
        RETURNING id,item_code AS item,score,confidence,review_status AS "reviewStatus"`,
      [session.task_id, session.student_id, itemCode, score, confidence, String(item?.note || '').slice(0, 1000), reviewStatus, session.id, String(input.algorithmVersion || session.algorithm_version || '').slice(0, 120), fieldObject(item?.evidence)]);
      savedScores.push({ ...saved.rows[0], score: Number(saved.rows[0].score), confidence: Number(saved.rows[0].confidence) });
    }
    for (const [ordinal, entry] of evidence.entries()) {
      const fileId = fieldInputString(entry?.fileId, '证据文件 ID');
      const file = await client.query(`SELECT id FROM files WHERE id=$1 AND status='uploaded' AND purpose='field_evidence' AND object_key LIKE $2`, [fileId, `field/${device.id}/%`]);
      if (!file.rows[0]) throw Object.assign(new Error('证据文件不存在、未上传或不属于本设备'), { status: 400, code: 'FIELD_EVIDENCE_NOT_FOUND' });
      const evidenceType = fieldInputString(entry?.evidenceType || 'other', '证据类型', 32);
      if (!['video', 'image', 'skeleton', 'timeline', 'calibration', 'log', 'other'].includes(evidenceType)) throw Object.assign(new Error('证据类型不合法'), { status: 400, code: 'FIELD_EVIDENCE_INVALID' });
      const retentionDays = fieldEvidenceRetentionDaysFor(evidenceType);
      await client.query(`INSERT INTO session_evidence(session_id,file_id,evidence_type,ordinal,checksum_sha256,metadata_json,retention_until,purged_at,purge_reason)
        VALUES($1,$2,$3,$4,$5,$6,$7::timestamptz+($8::int * interval '1 day'),NULL,NULL)
        ON CONFLICT(file_id) DO UPDATE SET session_id=EXCLUDED.session_id,evidence_type=EXCLUDED.evidence_type,ordinal=EXCLUDED.ordinal,metadata_json=EXCLUDED.metadata_json,retention_until=EXCLUDED.retention_until,purged_at=NULL,purge_reason=NULL`,
      [session.id, fileId, evidenceType, ordinal, entry?.checksumSha256 || null, fieldObject(entry?.metadata), endedAt, retentionDays]);
      await client.query(`UPDATE files SET retention_until=$1::timestamptz+($2::int * interval '1 day'),expires_at=NULL WHERE id=$3`, [endedAt, retentionDays, fileId]);
    }
    const needsReview = savedScores.some((score) => score.reviewStatus === 'pendingReview');
    const isRetest = input.outcome === 'retest';
    const sessionStatus = isRetest ? 'retest' : (needsReview ? 'needs_review' : 'completed');
    const queueStatus = isRetest ? 'retest' : 'completed';
    await client.query(`UPDATE test_sessions SET status=$1,ended_at=$2,device_ended_at=$2,algorithm_version=$3,summary_json=$4,sync_version=sync_version+1,updated_at=now() WHERE id=$5`,
    [sessionStatus, endedAt, String(input.algorithmVersion || session.algorithm_version || '').slice(0, 120), fieldObject(input.summary), session.id]);
    if (session.queue_entry_id) {
      const queue = await client.query('SELECT status FROM test_queue_entries WHERE id=$1 FOR UPDATE', [session.queue_entry_id]);
      await client.query(`UPDATE test_queue_entries SET status=$1,retest_count=retest_count+CASE WHEN $1='retest' THEN 1 ELSE 0 END,state_version=state_version+1,
        completed_at=CASE WHEN $1='completed' THEN COALESCE(completed_at,$2) ELSE completed_at END,updated_at=now() WHERE id=$3`, [queueStatus, endedAt, session.queue_entry_id]);
      await client.query(`INSERT INTO queue_events(queue_entry_id,old_status,new_status,reason,actor_type,actor_id,station_id,happened_at)
        VALUES($1,$2,$3,$4,'device',$5,$6,$7)`, [session.queue_entry_id, queue.rows[0]?.status || 'testing', queueStatus, String(input.reason || '').slice(0, 500), device.id, device.station_id || null, endedAt]);
    }
    const taskStatus = isRetest ? '待补测' : (needsReview ? '待复核' : '已完成');
    await client.query(`UPDATE task_students SET status=$1,completed_at=CASE WHEN $1='已完成' THEN COALESCE(completed_at,$2) ELSE completed_at END,version=version+1 WHERE id=$3`, [taskStatus, endedAt, session.task_student_id]);
    if (!isRetest) await client.query(`INSERT INTO job_queue(job_type,payload,available_at) VALUES('report.refresh',$1,now())`, [{ studentId: session.student_id, taskId: session.task_id, sessionId: session.id, schoolId: session.school_id }]);
    await client.query('COMMIT');
    await audit(null, { ...input, socket: { remoteAddress: null }, _requestId: input.requestId || crypto.randomUUID() }, 'field.session.complete', 'test_session', session.id, null, { deviceId: device.id, status: sessionStatus, scoreCount: savedScores.length }, session.school_id);
    void publishFieldUpdate(session.school_id, 'session.completed', { sessionId: session.id, taskId: session.task_id, studentId: session.student_id, stationId: session.station_id, status: sessionStatus, scoreCount: savedScores.length });
    return { id: session.id, status: sessionStatus, scores: savedScores, evidenceCount: evidence.length };
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

async function bodyAssessmentForUser(user, studentId, input, req) {
  if (!hasRole(user, 'parent')) throw Object.assign(new Error('只有家长可以提交家庭测评'), { status: 403, code: 'NO_PERMISSION' });
  const student = await guardianStudentForUser(user, studentId);
  if (!student) throw Object.assign(new Error('学生不存在或未绑定'), { status: 404, code: 'STUDENT_NOT_FOUND' });
  const consentVersion = String(input.consentVersion || 'v1');
  if (requireHealthConsent) {
    const consent = await query(`SELECT 1 FROM data_consents
      WHERE student_id=$1 AND parent_user_id=$2 AND purpose='body_assessment' AND consent_version=$3
        AND granted_at IS NOT NULL AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())`, [studentId, user.id, consentVersion]);
    if (!consent.rowCount) throw Object.assign(new Error('提交家庭测评前需要取得有效的数据使用同意'), { status: 403, code: 'CONSENT_REQUIRED' });
  }
  const height = finiteScalar(input.heightCm);
  const weight = finiteScalar(input.weightKg);
  // Keep the API boundary identical to both native clients' child-measurement
  // model. Values outside the supported child range are unavailable, not a
  // reason to generate an extreme BMI classification.
  if (!Number.isFinite(height) || height < 90 || height > 190 || !Number.isFinite(weight) || weight < 15 || weight > 90) {
    throw Object.assign(new Error('身高或体重不在有效范围'), { status: 400, code: 'MEASUREMENT_INVALID' });
  }
  const allowedCaptureTasks = new Set(['standingBack', 'forwardBend', 'seatedPosture', 'gaitVideo']);
  const rawSnapshots = Array.isArray(input.snapshots) ? input.snapshots : [];
  if (rawSnapshots.length > allowedCaptureTasks.size) throw Object.assign(new Error('姿态任务数量不合法'), { status: 400, code: 'SNAPSHOTS_INVALID' });
  const snapshots = rawSnapshots.map((snapshot) => {
    const captureTask = String(snapshot?.captureTask || '');
    const sampleCount = finiteScalar(snapshot?.sampleCount);
    const confidence = finiteScalar(snapshot?.confidence);
    if (!allowedCaptureTasks.has(captureTask) || !Number.isInteger(sampleCount) || sampleCount < 0 || sampleCount > 10000 || !Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
      throw Object.assign(new Error('姿态任务数据不合法'), { status: 400, code: 'SNAPSHOT_INVALID' });
    }
    return { ...snapshot, captureTask, sampleCount, confidence, metrics: snapshot?.metrics && typeof snapshot.metrics === 'object' ? snapshot.metrics : {} };
  });
  if (new Set(snapshots.map((snapshot) => snapshot.captureTask)).size !== snapshots.length) throw Object.assign(new Error('姿态任务不能重复'), { status: 400, code: 'SNAPSHOT_DUPLICATE' });
  // The client may preview a level, but it cannot choose the persisted health
  // state. Re-score the normalized evidence on the server so a forged red/green
  // value or stale native implementation cannot bypass the publication gate.
  const ageMonths = ageMonthsFromBirthDate(student.birth_date);
  const bodyReport = scoreBodyAssessment({ heightCm: height, weightKg: weight, ageMonths, gender: student.gender, snapshots });
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
    await client.query('COMMIT');
    await audit(user, req, 'body_assessment.create', 'body_assessment', assessment.rows[0].id, null, { studentId, bmi, overallLevel }, student.school_id);
    return { ...assessment.rows[0], heightCm: Number(assessment.rows[0].height_cm), weightKg: Number(assessment.rows[0].weight_kg), bmi: Number(assessment.rows[0].bmi), snapshots, ...bodyReport };
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

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
    if (req.method === 'GET' && ['/admin.css', '/admin.js', '/admin-enhancements.js'].includes(url.pathname)) {
      const assetName = url.pathname.slice(1);
      const asset = await fs.readFile(new URL(`../public/${assetName}`, import.meta.url));
      const contentType = assetName.endsWith('.css') ? 'text/css; charset=utf-8' : 'text/javascript; charset=utf-8';
      res.setHeader('Cache-Control', 'no-cache');
      res.writeHead(200, { 'Content-Type': contentType });
      return res.end(asset);
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

    // The Windows field client deliberately uses a device credential instead
    // of an operator access token.  It stays usable when teachers are busy or
    // the network reconnects later, while each write remains attributable to
    // one registered edge host.
    if (url.pathname.startsWith('/v1/field/')) {
      const device = await currentFieldDevice(req);
      if (!device) return fail(res, 401, 'FIELD_DEVICE_UNAUTHORIZED', '场地设备身份无效、已停用或已过期');
      if (req.method === 'POST' && url.pathname === '/v1/field/heartbeat') {
        const input = await body(req);
        const health = fieldObject(input.health);
        const capabilities = fieldObject(input.capabilities);
        const updated = await query(`UPDATE test_devices SET status='online',software_version=$1,health_json=$2,
          capabilities_json=CASE WHEN $3::jsonb='{}'::jsonb THEN capabilities_json ELSE $3::jsonb END,last_heartbeat_at=now(),updated_at=now()
          WHERE id=$4 RETURNING id,status,software_version AS "softwareVersion",last_heartbeat_at AS "lastHeartbeatAt"`,
        [String(input.softwareVersion || device.software_version || '').slice(0, 120), health, capabilities, device.id]);
        // A display, speaker or card reader heartbeat cannot make a testing
        // station eligible. Only its registered edge host controls the online
        // state used by the formal-score gate.
        if (device.station_id && device.device_type === 'edge_host') await query(`UPDATE test_stations SET status=CASE WHEN status='disabled' THEN status ELSE 'online' END,last_seen_at=now(),updated_at=now() WHERE id=$1`, [device.station_id]);
        void publishFieldUpdate(device.school_id, 'device.heartbeat', { deviceId: device.id, stationId: device.station_id || null, status: 'online', health });
        return ok(res, { ...updated.rows[0], serverTime: new Date().toISOString() });
      }
      if (req.method === 'GET' && url.pathname === '/v1/field/bootstrap') return ok(res, await fieldBootstrap(device, queryValue(url, 'taskId')));
      if (req.method === 'GET' && url.pathname === '/v1/field/commands') {
        const commands = await query(`UPDATE device_commands SET status='delivered'
          WHERE device_id=$1 AND status='pending' AND (expires_at IS NULL OR expires_at>now())
          RETURNING id,command_type AS "commandType",payload_json AS payload,status,created_at AS "createdAt",expires_at AS "expiresAt"`, [device.id]);
        const delivered = await query(`SELECT id,command_type AS "commandType",payload_json AS payload,status,created_at AS "createdAt",expires_at AS "expiresAt"
          FROM device_commands WHERE device_id=$1 AND status='delivered' AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at LIMIT 50`, [device.id]);
        return ok(res, { commands: [...commands.rows, ...delivered.rows.filter((row) => !commands.rows.some((item) => item.id === row.id))] });
      }
      if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'field' && parts[2] === 'commands' && parts[3] && parts[4] === 'ack') {
        const input = await body(req);
        const acknowledged = await query(`UPDATE device_commands SET status=$1,acknowledged_at=now()
          WHERE id=$2 AND device_id=$3 AND status IN ('pending','delivered')
          RETURNING id,command_type AS "commandType",status,acknowledged_at AS "acknowledgedAt"`,
        [input.failed === true ? 'failed' : 'acknowledged', parts[3], device.id]);
        if (!acknowledged.rows[0]) return fail(res, 404, 'FIELD_COMMAND_NOT_FOUND', '设备指令不存在或已处理');
        return ok(res, acknowledged.rows[0]);
      }
      if (req.method === 'POST' && url.pathname === '/v1/field/files/presign') {
        const input = await body(req);
        const name = safeFileName(input.fileName || input.name || 'evidence.bin');
        const contentType = String(input.contentType || 'application/octet-stream');
        const fileSize = Number(input.fileSize || 0);
        if (!allowedContentTypes.has(contentType)) return fail(res, 400, 'FILE_TYPE_NOT_ALLOWED', '证据文件类型不受支持');
        if (!Number.isInteger(fileSize) || fileSize < 0 || fileSize > maxUploadBytes) return fail(res, 400, 'FILE_SIZE_INVALID', '证据文件大小不合法或超过 20MB');
        const fileId = crypto.randomUUID();
        const result = await query(`INSERT INTO files(id,owner_id,object_key,file_type,purpose,content_type,file_size,expires_at)
          VALUES($1,NULL,$2,$3,'field_evidence',$4,$5,now()+interval '30 minutes')
          RETURNING id,object_key AS "objectKey",content_type AS "contentType",status,expires_at AS "expiresAt"`,
        [fileId, `field/${device.id}/${fileId}-${name}`, path.extname(name).slice(1) || 'bin', contentType, fileSize]);
        return created(res, { ...result.rows[0], uploadUrl: `/v1/field/files/${fileId}/content` });
      }
      if (req.method === 'PUT' && parts[0] === 'v1' && parts[1] === 'field' && parts[2] === 'files' && parts[4] === 'content') {
        const fileResult = await query(`SELECT * FROM files WHERE id=$1 AND purpose='field_evidence' AND object_key LIKE $2`, [parts[3], `field/${device.id}/%`]);
        const file = fileResult.rows[0];
        if (!file) return fail(res, 404, 'FILE_NOT_FOUND', '证据文件不存在或不属于本设备');
        if (file.status !== 'pending') return fail(res, 409, 'FILE_UPLOAD_STATE_INVALID', '证据文件已上传或正在清理，不能重复写入');
        if (file.expires_at && new Date(file.expires_at) < new Date()) return fail(res, 410, 'FILE_UPLOAD_EXPIRED', '证据上传凭证已过期');
        const bytes = await rawBody(req);
        if (bytes.length > maxUploadBytes || (Number(file.file_size) > 0 && bytes.length > Number(file.file_size))) return fail(res, 413, 'FILE_SIZE_INVALID', '实际文件大小超过限制');
        if (!fileSignatureMatches(bytes, file.content_type)) return fail(res, 400, 'FILE_SIGNATURE_INVALID', '文件内容与声明类型不匹配');
        await storage.put(file.object_key, bytes, file.content_type);
        const uploaded = await query(`UPDATE files SET file_size=$1,checksum_sha256=$2,status='uploaded',uploaded_at=now() WHERE id=$3
          RETURNING id,file_size AS "fileSize",checksum_sha256 AS "checksumSha256",status,uploaded_at AS "uploadedAt"`, [bytes.length, sha256(bytes), file.id]);
        return ok(res, uploaded.rows[0]);
      }
      if (req.method === 'POST' && url.pathname === '/v1/field/queue/transition') return ok(res, await transitionFieldQueue(device, await body(req), { type: 'device', id: device.id }));
      if (req.method === 'POST' && url.pathname === '/v1/field/sessions') return created(res, await openFieldSession(device, await body(req)));
      if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'field' && parts[2] === 'sessions' && parts[3] && parts[4] === 'events') {
        const input = await body(req);
        return accepted(res, await appendFieldSessionEvents(device, parts[3], input.events));
      }
      if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'field' && parts[2] === 'sessions' && parts[3] && parts[4] === 'complete') return ok(res, await completeFieldSession(device, parts[3], await body(req)));
      if (req.method === 'POST' && url.pathname === '/v1/field/sync/batches') {
        const input = await body(req);
        const clientBatchId = fieldInputString(input.clientBatchId, '客户端批次 ID');
        const events = Array.isArray(input.events) ? input.events : [];
        if (!events.length || events.length > 200) return fail(res, 400, 'FIELD_BATCH_INVALID', '同步批次事件数量必须在 1 到 200 条之间');
        const existing = await query(`SELECT status,response_json AS response,received_at AS "receivedAt" FROM field_sync_batches WHERE device_id=$1 AND client_batch_id=$2`, [device.id, clientBatchId]);
        if (existing.rows[0]?.status === 'completed') return ok(res, { ...existing.rows[0].response, idempotent: true });
        if (existing.rows[0]?.status === 'processing' && Date.now() - new Date(existing.rows[0].receivedAt).getTime() < 5 * 60_000) return fail(res, 409, 'FIELD_BATCH_IN_PROGRESS', '同步批次正在处理中，请稍后重试');
        await query(`INSERT INTO field_sync_batches(device_id,client_batch_id,event_count,status) VALUES($1,$2,$3,'processing')
          ON CONFLICT(device_id,client_batch_id) DO UPDATE SET event_count=EXCLUDED.event_count,status='processing',received_at=now(),response_json='{}'::jsonb`, [device.id, clientBatchId, events.length]);
        const outcomes = [];
        try {
          for (const event of events) {
            const clientEventId = fieldInputString(event?.clientEventId, '客户端事件 ID');
            const eventType = fieldInputString(event?.eventType, '同步事件类型', 64);
            const payload = fieldObject(event?.payload);
            const payloadHash = requestBodyHash(payload);
            const replay = await query('SELECT event_type AS "eventType",payload_hash AS "payloadHash" FROM field_sync_events WHERE device_id=$1 AND client_event_id=$2', [device.id, clientEventId]);
            if (replay.rows[0]) {
              if (replay.rows[0].eventType !== eventType || replay.rows[0].payloadHash !== payloadHash) {
                recordMetric('xiangshang_field_sync_conflicts_total', { reason: 'replay_mismatch' });
                logger.warn('field.sync_replay_mismatch', { deviceId: device.id, clientEventId, eventType, originalEventType: replay.rows[0].eventType, requestId: requestId(req) });
                throw Object.assign(new Error('客户端事件 ID 与已接收内容不一致，已拒绝覆盖中央记录'), { status: 409, code: 'FIELD_EVENT_REPLAY_MISMATCH' });
              }
              outcomes.push({ clientEventId, eventType, replayed: true });
              continue;
            }
            let data;
            if (eventType === 'queue.transition') data = await transitionFieldQueue(device, { ...payload, clientEventId, happenedAt: event.happenedAt }, { type: 'device', id: device.id });
            else if (eventType === 'session.open') data = await openFieldSession(device, payload);
            else if (eventType === 'session.events') data = await appendFieldSessionEvents(device, fieldInputString(payload.sessionId, '会话 ID'), payload.events);
            else if (eventType === 'session.complete') data = await completeFieldSession(device, fieldInputString(payload.sessionId, '会话 ID'), payload);
            else throw Object.assign(new Error('同步事件类型不受支持'), { status: 400, code: 'FIELD_SYNC_EVENT_UNSUPPORTED' });
            await query(`INSERT INTO field_sync_events(device_id,client_event_id,event_type,session_id,happened_at,payload_hash)
              VALUES($1,$2,$3,$4,$5,$6)`, [device.id, clientEventId, eventType, data?.id || payload.sessionId || null, fieldIsoDate(event?.happenedAt), payloadHash]);
            outcomes.push({ clientEventId, eventType, data });
          }
          const response = { clientBatchId, accepted: outcomes.length, outcomes };
          await query(`UPDATE field_sync_batches SET status='completed',response_json=$1,completed_at=now() WHERE device_id=$2 AND client_batch_id=$3`, [response, device.id, clientBatchId]);
          return ok(res, response);
        } catch (error) {
          await query(`UPDATE field_sync_batches SET status='failed',response_json=$1,completed_at=now() WHERE device_id=$2 AND client_batch_id=$3`, [{ code: error.code || 'FIELD_SYNC_FAILED', message: error.message }, device.id, clientBatchId]);
          throw error;
        }
      }
      return fail(res, 404, 'FIELD_ROUTE_NOT_FOUND', '场地端接口不存在');
    }

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
    if (req.method === 'GET' && url.pathname === '/v1/admin/field/stream') {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权订阅场地实时状态');
      const schoolId = fieldInputString(queryValue(url, 'schoolId'), '学校 ID');
      if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权订阅该学校场地状态');
      res.writeHead(200, {
        'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-cache, no-transform', Connection: 'keep-alive',
        ...(corsOrigin ? { 'Access-Control-Allow-Origin': corsOrigin } : {})
      });
      res.write(': field realtime connected\n\n');
      const subscribers = fieldStreamSubscribers.get(schoolId) || new Set();
      subscribers.add(res); fieldStreamSubscribers.set(schoolId, subscribers);
      writeFieldStream(res, 'ready', { schoolId, at: new Date().toISOString() });
      const heartbeat = setInterval(() => res.write(': keepalive\n\n'), 25_000);
      req.once('close', () => {
        clearInterval(heartbeat); subscribers.delete(res);
        if (!subscribers.size) fieldStreamSubscribers.delete(schoolId);
      });
      return;
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/test-stations') {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地测试点');
      const schoolId = queryValue(url, 'schoolId');
      if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校场地测试点');
      const stations = await query(`SELECT s.id,s.school_id AS "schoolId",s.station_code AS "stationCode",s.name,s.item_code AS "itemCode",s.queue_capacity AS "queueCapacity",s.status,
        s.metadata_json AS metadata,s.last_seen_at AS "lastSeenAt",s.updated_at AS "updatedAt",cal.version AS "activeCalibrationVersion",cal.effective_at AS "calibrationEffectiveAt",COUNT(d.id)::int AS "deviceCount",
        COUNT(d.id) FILTER(WHERE d.status='online')::int AS "onlineDeviceCount"
        FROM test_stations s LEFT JOIN test_devices d ON d.station_id=s.id
        LEFT JOIN LATERAL (SELECT version,effective_at FROM station_calibrations WHERE station_id=s.id AND status='active' ORDER BY effective_at DESC LIMIT 1) cal ON TRUE
        WHERE s.school_id=$1 GROUP BY s.id,cal.version,cal.effective_at ORDER BY s.station_code`, [schoolId]);
      return ok(res, stations.rows);
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/test-stations') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权创建场地测试点');
      const input = await body(req);
      const schoolId = fieldInputString(input.schoolId, '学校 ID');
      if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权操作该学校');
      const stationCode = fieldInputString(input.stationCode, '测试点编码', 64);
      const name = fieldInputString(input.name, '测试点名称', 120);
      const queueCapacity = input.queueCapacity == null ? 20 : Number(input.queueCapacity);
      if (!Number.isInteger(queueCapacity) || queueCapacity < 1 || queueCapacity > 500) return fail(res, 400, 'FIELD_STATION_INVALID', '队列容量必须在 1 到 500 之间');
      const status = input.status == null ? 'offline' : String(input.status);
      if (!['online', 'offline', 'maintenance', 'paused', 'disabled'].includes(status)) return fail(res, 400, 'FIELD_STATION_INVALID', '测试点状态不合法');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const station = await query(`INSERT INTO test_stations(school_id,station_code,name,item_code,queue_capacity,status,metadata_json)
        VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id,school_id AS "schoolId",station_code AS "stationCode",name,item_code AS "itemCode",queue_capacity AS "queueCapacity",status,metadata_json AS metadata`,
      [schoolId, stationCode, name, String(input.itemCode || '').slice(0, 64) || null, queueCapacity, status, fieldObject(input.metadata)]);
      await audit(user, req, 'field.station.create', 'test_station', station.rows[0].id, null, station.rows[0], schoolId);
      return createdIdempotently(res, user, idempotency, station.rows[0]);
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-stations' && parts[3]) {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权修改场地测试点');
      const input = await body(req);
      const existing = await query('SELECT * FROM test_stations WHERE id=$1', [parts[3]]);
      const row = existing.rows[0];
      if (!row || !schoolAllowed(user, row.school_id)) return fail(res, 404, 'FIELD_STATION_NOT_FOUND', '场地测试点不存在或无权访问');
      const status = input.status == null ? row.status : String(input.status);
      if (!['online', 'offline', 'maintenance', 'paused', 'disabled'].includes(status)) return fail(res, 400, 'FIELD_STATION_INVALID', '测试点状态不合法');
      const queueCapacity = input.queueCapacity == null ? Number(row.queue_capacity) : Number(input.queueCapacity);
      if (!Number.isInteger(queueCapacity) || queueCapacity < 1 || queueCapacity > 500) return fail(res, 400, 'FIELD_STATION_INVALID', '队列容量必须在 1 到 500 之间');
      const updated = await query(`UPDATE test_stations SET name=$1,item_code=$2,queue_capacity=$3,status=$4,metadata_json=$5,updated_at=now() WHERE id=$6
        RETURNING id,school_id AS "schoolId",station_code AS "stationCode",name,item_code AS "itemCode",queue_capacity AS "queueCapacity",status,metadata_json AS metadata,updated_at AS "updatedAt"`,
      [input.name == null ? row.name : fieldInputString(input.name, '测试点名称', 120), input.itemCode == null ? row.item_code : (String(input.itemCode).slice(0, 64) || null), queueCapacity, status, input.metadata == null ? row.metadata_json : fieldObject(input.metadata), row.id]);
      await audit(user, req, 'field.station.update', 'test_station', row.id, row, updated.rows[0], row.school_id);
      return ok(res, updated.rows[0]);
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/test-devices') {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地设备');
      const schoolId = queryValue(url, 'schoolId');
      if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校场地设备');
      const devices = await query(`SELECT d.id,d.school_id AS "schoolId",d.station_id AS "stationId",s.station_code AS "stationCode",s.status AS "stationStatus",d.device_code AS "deviceCode",d.name,d.device_type AS "deviceType",
        d.serial_number AS "serialNumber",d.software_version AS "softwareVersion",d.status,d.capabilities_json AS capabilities,d.health_json AS health,
        d.last_heartbeat_at AS "lastHeartbeatAt",d.api_key_expires_at AS "apiKeyExpiresAt",(d.signing_secret_encrypted IS NOT NULL) AS "signedRequestReady",
        cal.version AS "activeCalibrationVersion",cal."checksumSha256" AS "activeCalibrationChecksumSha256",
        CASE WHEN d.signing_secret_encrypted IS NULL THEN 'rotation_required' WHEN d.api_key_expires_at IS NULL THEN 'legacy_unbounded' WHEN d.api_key_expires_at<=now() THEN 'expired'
          WHEN d.api_key_expires_at<=now()+interval '14 days' THEN 'expiring' ELSE 'valid' END AS "apiKeyStatus",d.updated_at AS "updatedAt"
        FROM test_devices d LEFT JOIN test_stations s ON s.id=d.station_id
        LEFT JOIN LATERAL (SELECT version,checksum_sha256 AS "checksumSha256" FROM station_calibrations WHERE station_id=s.id AND status='active' ORDER BY effective_at DESC LIMIT 1) cal ON TRUE
        WHERE d.school_id=$1 ORDER BY d.device_code`, [schoolId]);
      return ok(res, devices.rows.map((device) => ({
        ...device,
        readiness: fieldReadiness({ ...device, health_json: device.health }, device.stationId ? { id: device.stationId, status: device.stationStatus } : null, device.activeCalibrationVersion ? { version: device.activeCalibrationVersion, checksumSha256: device.activeCalibrationChecksumSha256 } : null)
      })));
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/test-devices') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权注册场地设备');
      const input = await body(req);
      const schoolId = fieldInputString(input.schoolId, '学校 ID');
      if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权操作该学校');
      const deviceType = fieldInputString(input.deviceType, '设备类型', 32);
      if (!['edge_host', 'depth_camera', 'rgb_camera', 'display', 'speaker', 'reader', 'ups', 'network'].includes(deviceType)) return fail(res, 400, 'FIELD_DEVICE_INVALID', '设备类型不合法');
      const stationId = input.stationId ? fieldInputString(input.stationId, '测试点 ID') : null;
      if (stationId) {
        const station = await query('SELECT id FROM test_stations WHERE id=$1 AND school_id=$2', [stationId, schoolId]);
        if (!station.rows[0]) return fail(res, 400, 'FIELD_STATION_NOT_FOUND', '测试点不存在或不属于该学校');
      }
      const deviceKey = randomToken();
      const device = await query(`INSERT INTO test_devices(school_id,station_id,device_code,name,device_type,serial_number,software_version,api_key_hash,signing_secret_encrypted,api_key_expires_at,status,capabilities_json)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'offline',$11)
        RETURNING id,school_id AS "schoolId",station_id AS "stationId",device_code AS "deviceCode",name,device_type AS "deviceType",status,api_key_expires_at AS "apiKeyExpiresAt"`,
      [schoolId, stationId, fieldInputString(input.deviceCode, '设备编码', 64), fieldInputString(input.name, '设备名称', 120), deviceType, String(input.serialNumber || '').slice(0, 120) || null, String(input.softwareVersion || '').slice(0, 120), sha256(deviceKey), encryptFieldDeviceSigningSecret(deviceKey, fieldDeviceSigningEncryptionKey), fieldDeviceKeyExpiresAt(input.apiKeyExpiresAt), fieldObject(input.capabilities)]);
      await audit(user, req, 'field.device.create', 'test_device', device.rows[0].id, null, { ...device.rows[0], apiKeyIssued: true }, schoolId);
      return created(res, { ...device.rows[0], deviceKey });
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-devices' && parts[3] && parts[4] === 'rotate-key') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权轮换设备密钥');
      const input = await body(req);
      const row = await query('SELECT * FROM test_devices WHERE id=$1', [parts[3]]);
      if (!row.rows[0] || !schoolAllowed(user, row.rows[0].school_id)) return fail(res, 404, 'FIELD_DEVICE_NOT_FOUND', '场地设备不存在或无权访问');
      const deviceKey = randomToken();
      const result = await query(`UPDATE test_devices SET api_key_hash=$1,signing_secret_encrypted=$2,api_key_expires_at=$3,status='offline',updated_at=now() WHERE id=$4
        RETURNING id,device_code AS "deviceCode",status,api_key_expires_at AS "apiKeyExpiresAt"`, [sha256(deviceKey), encryptFieldDeviceSigningSecret(deviceKey, fieldDeviceSigningEncryptionKey), fieldDeviceKeyExpiresAt(input.apiKeyExpiresAt), parts[3]]);
      await audit(user, req, 'field.device.rotate_key', 'test_device', parts[3], null, { deviceKeyRotated: true }, row.rows[0].school_id);
      return ok(res, { ...result.rows[0], deviceKey });
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-stations' && parts[3] && parts[4] === 'calibrations') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权维护标定配置');
      const input = await body(req);
      const station = await query('SELECT * FROM test_stations WHERE id=$1', [parts[3]]);
      if (!station.rows[0] || !schoolAllowed(user, station.rows[0].school_id)) return fail(res, 404, 'FIELD_STATION_NOT_FOUND', '场地测试点不存在或无权访问');
      const version = fieldInputString(input.version, '标定版本', 64);
      const checksum = fieldInputString(input.checksumSha256, '标定校验和', 128);
      if (!/^[a-f0-9]{64}$/i.test(checksum)) return fail(res, 400, 'FIELD_CALIBRATION_INVALID', '标定校验和必须是 64 位 SHA-256 十六进制值');
      const calibrationConfig = fieldObject(input.config);
      if (!Object.keys(calibrationConfig).length) return fail(res, 400, 'FIELD_CALIBRATION_INVALID', '标定配置不能为空');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ stationId: parts[3], ...input }));
      if (idempotency === false) return;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        if (input.activate !== false) await client.query(`UPDATE station_calibrations SET status='archived' WHERE station_id=$1 AND status='active'`, [station.rows[0].id]);
        const calibration = await client.query(`INSERT INTO station_calibrations(station_id,version,checksum_sha256,config_json,status,verified_by,verified_at,effective_at)
          VALUES($1,$2,$3,$4,$5,$6,CASE WHEN $5='active' THEN now() ELSE NULL END,now())
          RETURNING id,station_id AS "stationId",version,checksum_sha256 AS "checksumSha256",config_json AS config,status,effective_at AS "effectiveAt"`,
        [station.rows[0].id, version, checksum, calibrationConfig, input.activate === false ? 'draft' : 'active', user.id]);
        await client.query('COMMIT');
        await audit(user, req, 'field.calibration.create', 'station_calibration', calibration.rows[0].id, null, calibration.rows[0], station.rows[0].school_id);
        return createdIdempotently(res, user, idempotency, calibration.rows[0]);
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/test-sessions') {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地测试会话');
      const schoolId = queryValue(url, 'schoolId');
      if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校测试会话');
      const page = pagination(url);
      const scopedClasses = teacherOnly(user) ? teacherClassIds(user, schoolId) : null;
      const sessions = await query(`SELECT s.id,s.client_session_id AS "clientSessionId",s.task_id AS "taskId",t.title AS "taskTitle",s.student_id AS "studentId",st.name AS "studentName",
        s.station_id AS "stationId",station.station_code AS "stationCode",s.edge_device_id AS "deviceId",device.device_code AS "deviceCode",s.attempt_no AS "attemptNo",s.status,
        s.rule_version AS "ruleVersion",s.standard_id AS "standardId",s.standard_version AS "standardVersion",s.calibration_version AS "calibrationVersion",s.algorithm_version AS "algorithmVersion",s.started_at AS "startedAt",s.ended_at AS "endedAt",s.summary_json AS summary
        FROM test_sessions s JOIN assessment_tasks t ON t.id=s.task_id JOIN students st ON st.id=s.student_id LEFT JOIN test_stations station ON station.id=s.station_id
        LEFT JOIN test_devices device ON device.id=s.edge_device_id WHERE s.school_id=$1 AND ($2::text IS NULL OR s.task_id=$2) AND ($3::text IS NULL OR s.station_id=$3) AND ($4::text IS NULL OR s.status=$4)
        AND ($5::text[] IS NULL OR st.class_id=ANY($5)) ORDER BY s.created_at DESC LIMIT $6 OFFSET $7`, [schoolId, queryValue(url, 'taskId') || null, queryValue(url, 'stationId') || null, queryValue(url, 'status') || null, scopedClasses, page.pageSize, page.offset]);
      return ok(res, sessions.rows);
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-sessions' && parts[3]) {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地测试会话');
      const session = await query(`SELECT s.*,s.standard_id AS "standardId",s.standard_version AS "standardVersion",s.standard_snapshot_json AS "standardSnapshot",st.name AS "studentName",st.class_id,t.title AS "taskTitle",station.station_code AS "stationCode",device.device_code AS "deviceCode"
        FROM test_sessions s JOIN students st ON st.id=s.student_id JOIN assessment_tasks t ON t.id=s.task_id LEFT JOIN test_stations station ON station.id=s.station_id
        LEFT JOIN test_devices device ON device.id=s.edge_device_id WHERE s.id=$1`, [parts[3]]);
      if (!session.rows[0] || !schoolAllowed(user, session.rows[0].school_id)) return fail(res, 404, 'FIELD_SESSION_NOT_FOUND', '测试会话不存在或无权访问');
      if (teacherOnly(user) && !teacherClassIds(user, session.rows[0].school_id).includes(session.rows[0].class_id)) return fail(res, 404, 'FIELD_SESSION_NOT_FOUND', '测试会话不存在或无权访问');
      const [events, evidence, scores] = await Promise.all([
        query(`SELECT client_event_id AS "clientEventId",sequence_no AS "sequenceNo",event_type AS "eventType",happened_at AS "happenedAt",payload_json AS payload FROM session_action_events WHERE session_id=$1 ORDER BY sequence_no`, [parts[3]]),
        query(`SELECT e.id,e.evidence_type AS "evidenceType",e.ordinal,e.checksum_sha256 AS "checksumSha256",e.metadata_json AS metadata,e.file_id AS "fileId",e.retention_until AS "retentionUntil",e.purged_at AS "purgedAt",e.purge_reason AS "purgeReason",f.content_type AS "contentType",f.file_size AS "fileSize" FROM session_evidence e LEFT JOIN files f ON f.id=e.file_id WHERE e.session_id=$1 ORDER BY e.evidence_type,e.ordinal`, [parts[3]]),
        query(`SELECT id,item_code AS item,score,confidence,review_status AS "reviewStatus",note,source,algorithm_version AS "algorithmVersion" FROM assessment_scores WHERE session_id=$1 ORDER BY item_code`, [parts[3]])
      ]);
      return ok(res, { ...session.rows[0], events: events.rows, evidence: evidence.rows, scores: normalizeScoreRows(scores.rows) });
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/test-queues') {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地排队');
      const taskId = fieldInputString(queryValue(url, 'taskId'), '任务 ID');
      const task = await query('SELECT school_id FROM assessment_tasks WHERE id=$1', [taskId]);
      if (!task.rows[0] || !schoolAllowed(user, task.rows[0].school_id)) return fail(res, 404, 'FIELD_TASK_NOT_FOUND', '测评任务不存在或无权访问');
      const scopedClasses = teacherOnly(user) ? teacherClassIds(user, task.rows[0].school_id) : null;
      const queues = await query(`SELECT q.id,q.student_id AS "studentId",st.name AS "studentName",c.name AS "className",q.station_id AS "stationId",station.station_code AS "stationCode",q.status,q.priority,q.queue_order AS "queueOrder",q.retest_count AS "retestCount",q.state_version AS "stateVersion",q.note,q.updated_at AS "updatedAt"
        FROM test_queue_entries q JOIN students st ON st.id=q.student_id JOIN classes c ON c.id=st.class_id LEFT JOIN test_stations station ON station.id=q.station_id
        WHERE q.task_id=$1 AND ($2::text IS NULL OR q.station_id=$2) AND ($3::text[] IS NULL OR st.class_id=ANY($3)) ORDER BY q.priority DESC,q.queue_order`, [taskId, queryValue(url, 'stationId') || null, scopedClasses]);
      return ok(res, queues.rows);
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/test-queues/rebalance') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以重新分流场地队列');
      const input = await body(req);
      const taskId = fieldInputString(input.taskId, '任务 ID');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ action: 'field.queue.rebalance', taskId }));
      if (idempotency === false) return;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const task = await client.query(`SELECT * FROM assessment_tasks WHERE id=$1 FOR UPDATE`, [taskId]);
        const row = task.rows[0];
        if (!row || !schoolAllowed(user, row.school_id)) throw Object.assign(new Error('测评任务不存在或无权操作'), { status: 404, code: 'FIELD_TASK_NOT_FOUND' });
        if (row.status !== 'published') throw Object.assign(new Error('只有已发布的任务可以分流'), { status: 409, code: 'FIELD_TASK_INACTIVE' });
        const dispatch = await rebalanceFieldQueue(client, row);
        await client.query('COMMIT');
        await audit(user, req, 'field.queue.rebalance', 'assessment_task', row.id, null, dispatch, row.school_id);
        void publishFieldUpdate(row.school_id, 'queue.rebalanced', { taskId: row.id, ...dispatch });
        return okIdempotently(res, user, idempotency, dispatch);
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-queues' && parts[3] && parts[4] === 'transition') {
      if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权调度场地队列');
      const input = await body(req);
      const queueSchool = await query(`SELECT t.school_id,st.class_id FROM test_queue_entries q JOIN assessment_tasks t ON t.id=q.task_id JOIN students st ON st.id=q.student_id WHERE q.id=$1`, [parts[3]]);
      if (!queueSchool.rows[0] || !schoolAllowed(user, queueSchool.rows[0].school_id)) return fail(res, 404, 'FIELD_QUEUE_NOT_FOUND', '队列记录不存在或无权访问');
      if (teacherOnly(user) && !teacherClassIds(user, queueSchool.rows[0].school_id).includes(queueSchool.rows[0].class_id)) return fail(res, 403, 'NO_PERMISSION', '教师只能调度所负责班级');
      return ok(res, await transitionFieldQueue({ school_id: queueSchool.rows[0].school_id, station_id: input.stationId || null }, { ...input, queueEntryId: parts[3] }, { type: hasRole(user, 'admin', 'principal') ? 'admin' : 'teacher', id: user.id }));
    }
    if (req.method === 'POST' && url.pathname === '/v1/admin/device-commands') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以下发设备级指令');
      const input = await body(req);
      const deviceId = fieldInputString(input.deviceId, '设备 ID');
      const device = await query('SELECT * FROM test_devices WHERE id=$1', [deviceId]);
      if (!device.rows[0] || !schoolAllowed(user, device.rows[0].school_id)) return fail(res, 404, 'FIELD_DEVICE_NOT_FOUND', '场地设备不存在或无权访问');
      const commandType = fieldInputString(input.commandType, '指令类型', 32);
      if (!['pause', 'resume', 'stop', 'call_next', 'recall', 'skip', 'retest', 'refresh_config'].includes(commandType)) return fail(res, 400, 'FIELD_COMMAND_INVALID', '场地指令不合法');
      const command = await query(`INSERT INTO device_commands(school_id,station_id,device_id,command_type,payload_json,issued_by,expires_at)
        VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id,command_type AS "commandType",payload_json AS payload,status,created_at AS "createdAt",expires_at AS "expiresAt"`,
      [device.rows[0].school_id, device.rows[0].station_id, device.rows[0].id, commandType, fieldObject(input.payload), user.id, input.expiresAt ? fieldIsoDate(input.expiresAt) : null]);
      await audit(user, req, 'field.command.create', 'device_command', command.rows[0].id, null, command.rows[0], device.rows[0].school_id);
      void publishFieldUpdate(device.rows[0].school_id, 'command.issued', { commandId: command.rows[0].id, deviceId: device.rows[0].id, stationId: device.rows[0].station_id, commandType });
      return created(res, command.rows[0]);
    }
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
      const [reviews, bodyAssessments, activities, appointments, courses, support, privacy, auditToday] = await Promise.all([
        query(`SELECT COUNT(*)::int AS count FROM assessment_scores x WHERE x.review_status='pendingReview' AND EXISTS (SELECT 1 FROM students st WHERE st.id=x.student_id AND st.school_id=$1)`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM body_assessments x JOIN students st ON st.id=x.student_id WHERE st.school_id=$1 AND x.measured_at >= now()-interval '30 days'`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM activity_registrations x WHERE x.status='pending' AND ${scopedUser}`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM expert_appointments x WHERE x.status='pending' AND ${scopedUser}`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM course_uploads x WHERE x.status='pending' AND ${scopedUser}`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM support_messages x WHERE x.status IN ('open','pending') AND ${scopedUser}`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM privacy_requests x JOIN students st ON st.id=x.student_id WHERE x.status IN ('pending','approved','processing') AND st.school_id=$1`, [schoolId]),
        query(`SELECT COUNT(*)::int AS count FROM audit_logs WHERE school_id=$1 AND created_at >= now()-interval '24 hours'`, [schoolId])
      ]);
      const count = (result) => Number(result.rows[0]?.count || 0);
      return ok(res, { schoolId, updatedAt: new Date().toISOString(), pendingReviews: count(reviews), bodyAssessmentsLast30Days: count(bodyAssessments), pendingActivities: count(activities), pendingAppointments: count(appointments), pendingCourseUploads: count(courses), pendingSupportMessages: count(support), pendingPrivacyRequests: count(privacy), auditEventsLast24Hours: count(auditToday) });
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
        s.effective_date AS "effectiveDate",s.status,s.created_at AS "createdAt",s.updated_at AS "updatedAt",u.name AS "createdBy"
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
        rule_config AS "ruleConfig",report_config AS "reportConfig",course_config AS "courseConfig",effective_date AS "effectiveDate",status,created_at AS "createdAt"`,
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
        RETURNING id,school_id AS "schoolId",grade_id AS "gradeId",region,poverty_area AS "povertyArea",standard_version AS "standardVersion",effective_date AS "effectiveDate",status,updated_at AS "updatedAt"`, [input.status, parts[3]]);
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
      const result = await normalizeStudentImportRows(user, input);
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
      const result = await normalizeStudentImportRows(user, input);
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
        RETURNING id,school_id AS "schoolId",grade_id AS "gradeId",class_id AS "classId",student_no AS "studentNo",name,gender,birth_date AS "birthDate",region,is_poverty_area AS "isPovertyArea",status`, [gradeId, classId, input.periodId || null, input.studentNo ?? current.student_no, input.name || current.name, input.gender ?? current.gender, input.birthDate ?? current.birth_date, input.region ?? current.region, input.isPovertyArea ?? current.is_poverty_area, parts[3]]);
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
      const result = await query(`UPDATE assessment_tasks SET title=COALESCE($1,title),test_date=COALESCE($2,test_date),location=COALESCE($3,location),grade_id=$4,class_id=$5,items=COALESCE($6,items),updated_at=now() WHERE id=$7 RETURNING id,title,test_date AS "testDate",location,grade_id AS "gradeId",class_id AS "classId",items,status`, [input.title || null, input.testDate || null, input.location === undefined ? null : input.location, gradeId, classId, Array.isArray(input.items) ? JSON.stringify(input.items) : null, parts[3]]);
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
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ id: parts[3], status: input.status }));
      if (idempotency === false) return;
      const result = await query(`UPDATE assessment_tasks SET status=$1,updated_at=now() WHERE id=$2 RETURNING id,status,updated_at AS "updatedAt"`, [input.status, parts[3]]);
      await audit(user, req, `task.status.${input.status}`, 'assessment_task', parts[3], current, result.rows[0], current.school_id);
      return okIdempotently(res, user, idempotency, result.rows[0]);
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
      const result = await query(`INSERT INTO assessment_tasks(school_id,title,test_date,location,grade_id,class_id,items,rule_version,status,created_by)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,'draft',$9) RETURNING id,title,status,grade_id AS "gradeId",class_id AS "classId"`, [current.school_id, input.title || `${current.title}（副本）`, input.testDate || current.test_date, input.location ?? current.location, current.grade_id, current.class_id, current.items, current.rule_version, user.id]);
      await query(`INSERT INTO task_students(task_id,student_id) SELECT $1,student_id FROM task_students WHERE task_id=$2`, [result.rows[0].id, current.id]);
      await audit(user, req, 'task.clone', 'assessment_task', result.rows[0].id, null, { sourceTaskId: current.id }, current.school_id);
      return createdIdempotently(res, user, idempotency, result.rows[0]);
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'schools' && parts[3] === 'grade-stats') {
      const schoolId = parts[2];
      if (!schoolStaffAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '只有学校工作人员可以查看统计');
      const scopedClasses = teacherOnly(user) ? teacherClassIds(user, schoolId) : null;
      const result = await query(`WITH active_task AS (SELECT id FROM assessment_tasks WHERE school_id=$1 ORDER BY test_date DESC, created_at DESC LIMIT 1)
        SELECT g.id,g.name,g.standard_version AS "standardVersion",COUNT(st.id)::int AS "studentCount",
        COUNT(*) FILTER(WHERE ts.status='已完成')::int AS "completedCount",
        COALESCE(ROUND(100.0*COUNT(*) FILTER(WHERE ts.status='已完成')/NULLIF(COUNT(st.id),0)),0)::int AS "completionRate"
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
      const result = await query(`WITH active_task AS (SELECT id FROM assessment_tasks WHERE school_id=$1 ORDER BY test_date DESC, created_at DESC LIMIT 1)
        SELECT c.id,c.name,c.grade_id AS "gradeId",COALESCE(u.name,'未分配') AS "teacherName",COUNT(st.id)::int AS "studentCount",
        COALESCE(ROUND(100.0*COUNT(*) FILTER(WHERE ts.status='已完成')/NULLIF(COUNT(st.id),0)),0)::int AS "completionRate"
        FROM classes c LEFT JOIN users u ON u.id=c.teacher_id LEFT JOIN students st ON st.class_id=c.id AND st.status='active'
        LEFT JOIN active_task at ON true
        LEFT JOIN task_students ts ON ts.student_id=st.id AND ts.task_id=at.id
        WHERE c.school_id=$1 AND ($2::text IS NULL OR c.grade_id=$2) AND ($3::text[] IS NULL OR c.id=ANY($3)) GROUP BY c.id,u.name ORDER BY c.name`, [schoolId, gradeId, scopedClasses]);
      return ok(res, result.rows);
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'files' && parts[2] === 'presign') {
      const input = await body(req);
      const name = safeFileName(input.fileName || input.name || 'upload.bin');
      const contentType = String(input.contentType || 'application/octet-stream');
      const fileSize = Number(input.fileSize || 0);
      if (!allowedContentTypes.has(contentType)) return fail(res, 400, 'FILE_TYPE_NOT_ALLOWED', '文件类型不受支持');
      if (!Number.isInteger(fileSize) || fileSize < 0 || fileSize > maxUploadBytes) return fail(res, 400, 'FILE_SIZE_INVALID', '文件大小不合法或超过 20MB');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const fileId = crypto.randomUUID();
      const objectKey = `${user.id}/${fileId}-${name}`;
      const expiresAt = new Date(Date.now() + 30 * 60_000);
      const result = await query(`INSERT INTO files(id,owner_id,object_key,file_type,purpose,content_type,file_size,expires_at)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id,object_key AS "objectKey",content_type AS "contentType",status,expires_at AS "expiresAt"`, [fileId, user.id, objectKey, path.extname(name).slice(1) || 'bin', input.purpose || 'general', contentType, fileSize, expiresAt]);
      return createdIdempotently(res, user, idempotency, { ...result.rows[0], uploadUrl: `/v1/files/${fileId}/content` });
    }
    if (req.method === 'PUT' && parts[0] === 'v1' && parts[1] === 'files' && parts[3] === 'content') {
      const fileResult = await query('SELECT * FROM files WHERE id=$1', [parts[2]]);
      const file = fileResult.rows[0];
      if (!file || (file.owner_id !== user.id && !hasRole(user, 'admin'))) return fail(res, 404, 'FILE_NOT_FOUND', '文件不存在');
      if (file.expires_at && new Date(file.expires_at) < new Date()) return fail(res, 410, 'FILE_UPLOAD_EXPIRED', '上传凭证已过期');
      const bytes = await rawBody(req);
      if (bytes.length > maxUploadBytes || (Number(file.file_size) > 0 && bytes.length > Number(file.file_size))) return fail(res, 413, 'FILE_SIZE_INVALID', '实际文件大小超过限制');
      if (!fileSignatureMatches(bytes, file.content_type)) return fail(res, 400, 'FILE_SIGNATURE_INVALID', '文件内容与声明类型不匹配');
      await storage.put(file.object_key, bytes, file.content_type);
      const result = await query(`UPDATE files SET file_size=$1,checksum_sha256=$2,status='uploaded',uploaded_at=now() WHERE id=$3 RETURNING id,file_size AS "fileSize",checksum_sha256 AS "checksumSha256",status,uploaded_at AS "uploadedAt"`, [bytes.length, sha256(bytes), file.id]);
      return ok(res, result.rows[0]);
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'files' && parts[3] === 'content') {
      const fileResult = await query('SELECT * FROM files WHERE id=$1 AND status=\'uploaded\'', [parts[2]]);
      const file = fileResult.rows[0];
      if (!file || (file.owner_id !== user.id && !(await classPostFileVisibleToUser(user, parts[2])))) return fail(res, 404, 'FILE_NOT_FOUND', '文件不存在');
      let bytes;
      try { bytes = await storage.get(file.object_key); } catch { return fail(res, 404, 'FILE_NOT_FOUND', '文件内容不存在'); }
      res.writeHead(200, { 'Content-Type': file.content_type, 'Content-Length': bytes.length, 'Content-Disposition': `inline; filename="${safeFileName(file.object_key.split('/').pop())}"`, 'Cache-Control': 'private, no-store', ...(corsOrigin ? { 'Access-Control-Allow-Origin': corsOrigin } : {}) });
      return res.end(bytes);
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'files' && parts.length === 3) {
      const result = await query('SELECT id,owner_id AS "ownerId",object_key AS "objectKey",file_type AS "fileType",purpose,content_type AS "contentType",file_size AS "fileSize",status,expires_at AS "expiresAt",uploaded_at AS "uploadedAt" FROM files WHERE id=$1', [parts[2]]);
      const file = result.rows[0];
      if (!file || (file.ownerId !== user.id && !(await classPostFileVisibleToUser(user, parts[2])))) return fail(res, 404, 'FILE_NOT_FOUND', '文件不存在');
      return ok(res, file);
    }

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
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const task = await client.query(`INSERT INTO assessment_tasks(school_id,title,test_date,location,grade_id,class_id,items,rule_version,status,created_by)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8,'published',$9) RETURNING id`, [input.schoolId, input.title, input.testDate, input.location || '', input.gradeId || null, input.classId || null, JSON.stringify(input.items || []), input.ruleVersion || '运动能力标准 v1.0', user.id]);
        const students = await client.query(`SELECT id FROM students WHERE school_id=$1 AND status='active' AND ($2::text IS NULL OR grade_id=$2) AND ($3::text IS NULL OR class_id=$3)`, [input.schoolId, input.gradeId || null, input.classId || null]);
        for (const student of students.rows) await client.query(`INSERT INTO task_students(task_id,student_id) VALUES($1,$2) ON CONFLICT DO NOTHING`, [task.rows[0].id, student.id]);
        await client.query('COMMIT');
        await audit(user, req, 'task.create', 'assessment_task', task.rows[0].id, null, input, input.schoolId);
        return createdIdempotently(res, user, idempotency, { id: task.rows[0].id, studentCount: students.rowCount });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }

    if (req.method === 'GET' && url.pathname === '/v1/teacher/analytics/overview') {
      if (!teacherOnly(user) || !await userHasCapability(user, 'VIEW_CLASS_DASHBOARD')) return fail(res, 403, 'CAPABILITY_DENIED', '当前账号无查看班级看板权限');
      const schoolId = queryValue(url, 'schoolId');
      const classId = queryValue(url, 'classId');
      const taskId = queryValue(url, 'taskId');
      if (!schoolId || !classId || !taskId) return fail(res, 400, 'ANALYTICS_FILTER_REQUIRED', '请选择学校、班级和测评任务');
      if (!schoolAllowed(user, schoolId) || !teacherClassIds(user, schoolId).includes(classId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该班级看板');
      const task = await query('SELECT id,rule_version FROM assessment_tasks WHERE id=$1 AND school_id=$2', [taskId, schoolId]);
      if (!task.rows[0]) return fail(res, 404, 'TASK_NOT_FOUND', '测评任务不存在或不属于该学校');
      const standardVersion = queryValue(url, 'standardVersion');
      if (standardVersion && standardVersion !== task.rows[0].rule_version) return fail(res, 409, 'STANDARD_VERSION_MISMATCH', '评分标准已更新，请刷新看板');
      const summary = await query(`SELECT COUNT(ts.id)::int AS "totalCount",
        COUNT(ts.id) FILTER(WHERE ts.status='已完成')::int AS "completedCount",
        COUNT(ts.id) FILTER(WHERE ts.status='未签到')::int AS "notCheckedInCount",
        COUNT(ts.id) FILTER(WHERE ts.status='已签到')::int AS "checkedInCount",
        COUNT(ts.id) FILTER(WHERE ts.status='候测')::int AS "waitingCount",
        COUNT(ts.id) FILTER(WHERE ts.status='测试中')::int AS "testingCount",
        COUNT(ts.id) FILTER(WHERE ts.status='待复核')::int AS "reviewCount",
        COUNT(ts.id) FILTER(WHERE ts.status='待补测')::int AS "retestCount",
        COUNT(ts.id) FILTER(WHERE ts.status='缺席')::int AS "absentCount",
        COUNT(DISTINCT ts.student_id) FILTER(WHERE ts.status IN ('待复核','待补测') OR EXISTS (
          SELECT 1 FROM assessment_scores risk_score WHERE risk_score.task_id=ts.task_id AND risk_score.student_id=ts.student_id
            AND (risk_score.score < 3 OR risk_score.review_status='pendingReview')
        ))::int AS "riskCount",
        COUNT(DISTINCT ts.student_id) FILTER(WHERE EXISTS (
          SELECT 1 FROM assessment_scores low_score WHERE low_score.task_id=ts.task_id AND low_score.student_id=ts.student_id AND low_score.score < 3
        ))::int AS "lowScoreCount"
        FROM task_students ts JOIN students st ON st.id=ts.student_id WHERE ts.task_id=$1 AND st.class_id=$2`, [taskId, classId]);
      // Cross join the canonical seven-item catalogue with this class's task
      // roster. This deliberately returns zero-measurement rows instead of
      // removing an item that has not started yet; clients can distinguish
      // absence of data from a missing component of the standard.
      const items = await query(`WITH item_codes(item_code) AS (SELECT unnest($3::text[]))
        SELECT code.item_code AS "itemCode",COUNT(DISTINCT ts.student_id)::int AS "totalCount",
          COUNT(DISTINCT ts.student_id) FILTER(WHERE score.id IS NOT NULL)::int AS "measuredCount",
          COALESCE(ROUND(AVG(score.score)::numeric,2),0)::float AS "averageScore",
          COUNT(DISTINCT ts.student_id) FILTER(WHERE score.review_status IN ('risk','retest','review','pendingReview'))::int AS "riskCount"
        FROM item_codes code
        LEFT JOIN task_students ts ON ts.task_id=$1
        LEFT JOIN students st ON st.id=ts.student_id AND st.class_id=$2
        LEFT JOIN assessment_scores score ON score.task_id=ts.task_id AND score.student_id=ts.student_id AND score.item_code=code.item_code
        WHERE st.id IS NOT NULL
        GROUP BY code.item_code ORDER BY code.item_code`, [taskId, classId, MOVEMENT_ITEM_CODES]);
      const byItem = new Map(items.rows.map((item) => [item.itemCode, item]));
      const normalizedItems = MOVEMENT_ITEM_CODES.map((itemCode) => {
        const item = byItem.get(itemCode) || { itemCode, totalCount: Number(summary.rows[0].totalCount || 0), measuredCount: 0, averageScore: 0, riskCount: 0 };
        return { ...item, completionRate: item.totalCount ? Math.round(item.measuredCount * 100 / item.totalCount) : 0 };
      });
      return ok(res, { ...summary.rows[0], schoolId, classId, taskId, standardVersion: task.rows[0].rule_version, itemStats: normalizedItems, dataAvailable: summary.rows[0].totalCount > 0, history: [] });
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'schools' && parts[3] === 'dashboard') {
      return ok(res, await dashboard(user, parts[2], { studentPage: queryValue(url, 'studentPage'), studentPageSize: queryValue(url, 'studentPageSize') }));
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'schools' && parts[3] === 'students') {
      const schoolId = parts[2];
      if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
      const requestedClass = queryValue(url, 'classId') || null;
      const search = queryValue(url, 'search') || null;
      const page = pagination(url);
      const params = [schoolId];
      let classFilter = '';
      let searchFilter = '';
      if (parentOnly(user)) { params.push(user.id); classFilter = ` AND EXISTS (SELECT 1 FROM parent_student_bindings pb WHERE pb.parent_user_id=$2 AND pb.student_id=st.id AND pb.status='active')`; }
      else if (hasRole(user, 'teacher') && !hasRole(user, 'principal', 'admin')) {
        const allowedClassIds = teacherClassIds(user, schoolId);
        params.push(requestedClass ? (allowedClassIds.includes(requestedClass) ? requestedClass : '__none__') : (allowedClassIds.length ? allowedClassIds : ['__none__']));
        classFilter = requestedClass ? ' AND st.class_id=$2' : ' AND st.class_id=ANY($2)';
      } else if (requestedClass) { params.push(requestedClass); classFilter = ' AND st.class_id=$2'; }
      if (search) { params.push(`%${search}%`); searchFilter = ` AND (st.name ILIKE $${params.length} OR COALESCE(st.student_no,'') ILIKE $${params.length})`; }
      const count = await query(`SELECT COUNT(*)::int AS total FROM students st WHERE st.school_id=$1 AND st.status='active'${classFilter}${searchFilter}`, params);
      params.push(page.pageSize, page.offset);
      const result = await query(`SELECT st.*,g.name AS grade_name,c.name AS class_name FROM students st JOIN grades g ON g.id=st.grade_id JOIN classes c ON c.id=st.class_id
        WHERE st.school_id=$1 AND st.status='active'${classFilter}${searchFilter} ORDER BY st.name LIMIT $${params.length - 1} OFFSET $${params.length}`, params);
      return ok(res, listResult(url, result.rows.map(studentRow), count.rows[0].total));
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'students' && parts[4] === 'binding-code') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以生成绑定码');
      const student = await query('SELECT id,school_id,name FROM students WHERE id=$1 AND status=\'active\'', [parts[3]]);
      if (!student.rows[0] || !schoolAllowed(user, student.rows[0].school_id)) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentId: parts[3], action: 'binding-code' }));
      if (idempotency === false) return;
      const bindingCode = randomToken().slice(0, 12).toUpperCase();
      const expiresAt = new Date(Date.now() + 30 * 60_000);
      await query('UPDATE student_binding_codes SET used_at=COALESCE(used_at,now()) WHERE student_id=$1 AND used_at IS NULL', [parts[3]]);
      const result = await query(`INSERT INTO student_binding_codes(student_id,code_hash,expires_at,created_by)
        VALUES($1,$2,$3,$4) RETURNING id,student_id AS "studentId",expires_at AS "expiresAt"`, [parts[3], sha256(bindingCode), expiresAt, user.id]);
      await audit(user, req, 'student.binding_code.create', 'student', parts[3], null, { ...result.rows[0], codeIssued: true }, student.rows[0].school_id);
      return createdIdempotently(res, user, idempotency, { ...result.rows[0], bindingCode, studentName: student.rows[0].name });
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'bind') {
      if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家长可以绑定孩子');
      const student = await query('SELECT * FROM students WHERE id=$1 AND status=\'active\'', [parts[2]]);
      const code = queryValue(url, 'code');
      if (!student.rows[0] || !code) return fail(res, 400, 'BINDING_CODE_INVALID', '绑定码无效');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentId: parts[2], code: String(code).trim().toUpperCase() }));
      if (idempotency === false) return;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const issued = await client.query(`SELECT id FROM student_binding_codes WHERE student_id=$1 AND code_hash=$2 AND used_at IS NULL AND expires_at>now() FOR UPDATE`, [parts[2], sha256(String(code).trim().toUpperCase())]);
        if (!issued.rows[0] && !( !isProduction && code === student.rows[0].student_no)) {
          await client.query('ROLLBACK');
          return fail(res, 400, 'BINDING_CODE_INVALID', '绑定码无效或已过期');
        }
        const result = await client.query(`INSERT INTO parent_student_bindings(parent_user_id,student_id,relation,binding_code) VALUES($1,$2,$3,NULL)
          ON CONFLICT(parent_user_id,student_id) DO UPDATE SET status='active',expires_at=NULL RETURNING id,parent_user_id AS "parentId",student_id,relation`, [user.id, parts[2], '监护人']);
        if (issued.rows[0]) await client.query('UPDATE student_binding_codes SET used_at=now(),used_by=$1 WHERE id=$2', [user.id, issued.rows[0].id]);
        await client.query('COMMIT');
        await audit(user, req, 'student.bind', 'student', parts[2], null, result.rows[0], student.rows[0].school_id);
        const detail = await studentForUser(user, parts[2]);
        return createdIdempotently(res, user, idempotency, { ...result.rows[0], student: studentRow(detail) });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'POST' && url.pathname === '/v1/students/bind') {
      if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家长可以绑定孩子');
      const input = await body(req);
      const studentName = requiredString(input.studentName, '学生姓名', { max: 80 });
      const code = requiredString(input.code, '绑定码', { max: 128 }).toUpperCase();
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentName, code }));
      if (idempotency === false) return;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const studentResult = await client.query(`SELECT st.*, g.name AS grade_name, c.name AS class_name
          FROM students st JOIN grades g ON g.id=st.grade_id JOIN classes c ON c.id=st.class_id
          WHERE st.name=$1 AND st.status='active' ORDER BY st.created_at DESC LIMIT 10 FOR UPDATE OF st`, [studentName]);
        let matched = null;
        for (const candidate of studentResult.rows) {
          const issued = await client.query(`SELECT id FROM student_binding_codes WHERE student_id=$1 AND code_hash=$2 AND used_at IS NULL AND expires_at>now() FOR UPDATE`, [candidate.id, sha256(code)]);
          if (issued.rows[0] || (!isProduction && candidate.student_no === code)) { matched = { student: candidate, issued: issued.rows[0] || null }; break; }
        }
        if (!matched) { await client.query('ROLLBACK'); return failIdempotently(req, res, 400, 'BINDING_CODE_INVALID', '姓名或绑定码无效或已过期'); }
        const result = await client.query(`INSERT INTO parent_student_bindings(parent_user_id,student_id,relation,binding_code)
          VALUES($1,$2,$3,NULL) ON CONFLICT(parent_user_id,student_id) DO UPDATE SET status='active',expires_at=NULL
          RETURNING id,parent_user_id AS "parentId",student_id`, [user.id, matched.student.id, '监护人']);
        if (matched.issued) await client.query('UPDATE student_binding_codes SET used_at=now(),used_by=$1 WHERE id=$2', [user.id, matched.issued.id]);
        await client.query('COMMIT');
        await audit(user, req, 'student.bind', 'student', matched.student.id, null, result.rows[0], matched.student.school_id);
        const detail = await studentForUser(user, matched.student.id);
        return createdIdempotently(res, user, idempotency, { ...result.rows[0], student: studentRow(detail) });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'schools' && parts[3] === 'tasks') {
      const schoolId = parts[2];
      if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
      const page = pagination(url);
      const gradeId = queryValue(url, 'gradeId') || null;
      const classId = queryValue(url, 'classId') || null;
      const parentScope = parentOnly(user);
      const scopeJoin = parentScope ? ` JOIN task_students visible_ts ON visible_ts.task_id=t.id
        JOIN parent_student_bindings visible_pb ON visible_pb.student_id=visible_ts.student_id AND visible_pb.parent_user_id=$4 AND visible_pb.status='active'` : '';
      const countParams = parentScope ? [schoolId, gradeId, classId, user.id] : [schoolId, gradeId, classId];
      const count = await query(`SELECT COUNT(DISTINCT t.id)::int AS total FROM assessment_tasks t${scopeJoin}
        WHERE t.school_id=$1 AND ($2::text IS NULL OR t.grade_id=$2) AND ($3::text IS NULL OR t.class_id=$3)`, countParams);
      const taskParams = parentScope ? [schoolId, gradeId, classId, user.id, page.pageSize, page.offset] : [schoolId, gradeId, classId, page.pageSize, page.offset];
      const parentGroup = parentScope ? ',visible_pb.parent_user_id' : '';
      const limitIndex = parentScope ? 5 : 4;
      const offsetIndex = parentScope ? 6 : 5;
      const visibleTaskAlias = parentScope ? 'visible_ts' : 'ts';
      const visibleTaskId = `${visibleTaskAlias}.id`;
      const result = await query(`SELECT t.id,t.title,t.test_date AS date,t.location,COALESCE(g.name,'全校') AS "gradeName",COALESCE(c.name,'全校') AS "className",t.items,t.rule_version AS "ruleVersion",t.status,
        CASE WHEN t.class_id IS NULL THEN ARRAY[]::text[] ELSE ARRAY[t.class_id] END AS "classIds",COALESCE(ARRAY_AGG(DISTINCT ${visibleTaskAlias}.student_id) FILTER(WHERE ${visibleTaskAlias}.student_id IS NOT NULL), ARRAY[]::text[]) AS "studentIds",COUNT(DISTINCT ${visibleTaskId})::int AS "totalCount",COUNT(DISTINCT ${visibleTaskId}) FILTER(WHERE ${visibleTaskAlias}.status='已完成')::int AS "completedCount" FROM assessment_tasks t LEFT JOIN grades g ON g.id=t.grade_id LEFT JOIN classes c ON c.id=t.class_id LEFT JOIN task_students ts ON ts.task_id=t.id${scopeJoin}
        WHERE t.school_id=$1 AND ($2::text IS NULL OR t.grade_id=$2) AND ($3::text IS NULL OR t.class_id=$3) GROUP BY t.id,g.name,c.name,t.class_id${parentGroup} ORDER BY t.test_date DESC LIMIT $${limitIndex} OFFSET $${offsetIndex}`, taskParams);
      return ok(res, listResult(url, result.rows.map((row) => ({ ...row, items: row.items || [], status: row.completedCount === row.totalCount && row.totalCount > 0 ? '已完成' : row.status === 'published' ? '未签到' : row.status === 'closed' ? '已完成' : row.status })), count.rows[0].total));
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'tasks' && parts[2] && parts[3] === 'students' && parts.length === 4) {
      const taskResult = await query('SELECT id,school_id FROM assessment_tasks WHERE id=$1', [parts[2]]);
      const task = taskResult.rows[0];
      if (!task || !schoolAllowed(user, task.school_id)) return fail(res, 404, 'TASK_NOT_FOUND', '任务不存在或无权访问');
      if (teacherOnly(user) && !await userHasCapability(user, 'VIEW_TEST_TASKS', task.school_id)) return fail(res, 403, 'CAPABILITY_DENIED', '当前账号无查看测评任务权限');
      const params = [parts[2]];
      const page = pagination(url, 200);
      const statusFilter = queryValue(url, 'status');
      const keyword = queryValue(url, 'keyword');
      let scope = '';
      if (hasRole(user, 'teacher') && !hasRole(user, 'principal', 'admin')) {
        const classIds = teacherClassIds(user, task.school_id);
        params.push(classIds.length ? classIds : ['__none__']);
        scope = ` AND st.class_id=ANY($2)`;
      }
      if (parentOnly(user)) {
        params.push(user.id);
        scope = ` AND EXISTS (SELECT 1 FROM parent_student_bindings visible_pb WHERE visible_pb.parent_user_id=$${params.length} AND visible_pb.student_id=st.id AND visible_pb.status='active')`;
      }
      if (statusFilter) { params.push(statusFilter); scope += ` AND ts.status=$${params.length}`; }
      if (keyword) { params.push(`%${keyword}%`); scope += ` AND (st.name ILIKE $${params.length} OR c.name ILIKE $${params.length})`; }
      const limitIndex = params.length + 1;
      const offsetIndex = params.length + 2;
      const result = await query(`SELECT ts.id,ts.task_id AS "taskId",ts.student_id AS "studentId",ts.status,ts.version,st.name AS "studentName",st.gender AS "studentGender",st.grade_id AS "gradeId",g.name AS "gradeName",st.class_id AS "classId",c.name AS "className"
        FROM task_students ts JOIN students st ON st.id=ts.student_id JOIN classes c ON c.id=st.class_id LEFT JOIN grades g ON g.id=st.grade_id
        WHERE ts.task_id=$1${scope} ORDER BY c.name,st.name LIMIT $${limitIndex} OFFSET $${offsetIndex}`, [...params, page.pageSize, page.offset]);
      if (!page.paged) return ok(res, result.rows);
      const count = await query(`SELECT COUNT(*)::int AS total FROM task_students ts JOIN students st ON st.id=ts.student_id JOIN classes c ON c.id=st.class_id WHERE ts.task_id=$1${scope}`, params);
      return ok(res, { items: result.rows, page: page.page, pageSize: page.pageSize, total: count.rows[0]?.total || 0 });
    }
    if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'tasks' && parts[3] === 'students' && parts[5] === 'status') {
      if (!hasRole(user, 'teacher', 'principal', 'admin')) return fail(res, 403, 'NO_PERMISSION', '无权修改测评状态');
      const input = await body(req);
      const result = await query(`SELECT ts.*,t.school_id,st.class_id FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id JOIN students st ON st.id=ts.student_id WHERE ts.task_id=$1 AND ts.student_id=$2`, [parts[2], parts[4]]);
      const row = result.rows[0];
      if (!row || !schoolAllowed(user, row.school_id)) return fail(res, 404, 'TASK_STUDENT_NOT_FOUND', '任务学生不存在');
      if (hasRole(user, 'teacher') && !hasRole(user, 'principal', 'admin') && !teacherClassIds(user, row.school_id).includes(row.class_id)) return fail(res, 403, 'NO_PERMISSION', '无权修改该班级测评状态');
      if (teacherOnly(user) && !await userHasCapability(user, 'UPDATE_TEST_STATUS', row.school_id, row.class_id)) return fail(res, 403, 'CAPABILITY_DENIED', '当前账号无更新测评状态权限');
      if (!taskStatusAllowed(row.status, input.status)) return fail(res, 409, 'TASK_STATUS_INVALID', `不能从${row.status}变更为${input.status}`);
      const expectedVersion = input.expectedVersion == null ? null : Number(input.expectedVersion);
      if (expectedVersion != null && (!Number.isInteger(expectedVersion) || expectedVersion < 1)) return fail(res, 400, 'VERSION_INVALID', '版本号不合法');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ taskId: parts[2], studentId: parts[4], ...input }));
      if (idempotency === false) return;
      const updated = await query(`UPDATE task_students SET status=$1,note=$2,check_in_at=CASE WHEN $1='已签到' THEN COALESCE(check_in_at,now()) ELSE check_in_at END,
        completed_at=CASE WHEN $1='已完成' THEN COALESCE(completed_at,now()) ELSE completed_at END,version=version+1 WHERE task_id=$3 AND student_id=$4 AND ($5::int IS NULL OR version=$5) RETURNING *`, [input.status, input.note || null, parts[2], parts[4], expectedVersion]);
      if (!updated.rowCount) return failIdempotently(req, res, 409, 'VERSION_CONFLICT', '记录已被其他人更新，请刷新后重试');
      await query(`INSERT INTO task_student_status_events(task_id,student_id,from_status,to_status,note,reason_code,operator_teacher_id,expected_version,resulting_version,client_operation_id)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, [parts[2], parts[4], row.status, input.status, input.note || null, input.reasonCode || null, user.id, expectedVersion, updated.rows[0].version, input.clientOperationId || null]);
      await audit(user, req, 'task.status.update', 'task_student', row.id, row, updated.rows[0], row.school_id);
      return okIdempotently(res, user, idempotency, updated.rows[0]);
    }
    if (req.method === 'POST' && (url.pathname === '/v1/admin/tasks/batch-status' || (parts[0] === 'v1' && parts[1] === 'tasks' && parts[2] && parts[3] === 'students' && parts[4] === 'batch-status'))) {
      if (!hasRole(user, 'teacher', 'principal', 'admin')) return fail(res, 403, 'NO_PERMISSION', '无权批量修改测评状态');
      const input = await body(req);
      if (!Array.isArray(input.updates) || input.updates.length < 1 || input.updates.length > 100) return fail(res, 400, 'BATCH_INVALID', '批量更新数量必须在 1 到 100 条之间');
      const scopedTaskId = parts[0] === 'v1' && parts[1] === 'tasks' ? parts[2] : null;
      if (scopedTaskId && input.updates.some((item) => item.taskId && item.taskId !== scopedTaskId)) return fail(res, 400, 'BATCH_TASK_MISMATCH', '批量操作只能包含当前任务的学生');
      if (scopedTaskId) input.updates = input.updates.map((item) => ({ ...item, taskId: scopedTaskId }));
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const client = await pool.connect();
      const saved = [];
      try {
        await client.query('BEGIN');
        for (const item of input.updates) {
          const rowResult = await client.query(`SELECT ts.*,t.school_id,st.class_id FROM task_students ts
            JOIN assessment_tasks t ON t.id=ts.task_id JOIN students st ON st.id=ts.student_id
            WHERE ts.task_id=$1 AND ts.student_id=$2 FOR UPDATE`, [item.taskId, item.studentId]);
          const row = rowResult.rows[0];
          if (!row || !schoolAllowed(user, row.school_id)) throw Object.assign(new Error('任务学生不存在或无权访问'), { status: 404, code: 'TASK_STUDENT_NOT_FOUND' });
          if (hasRole(user, 'teacher') && !hasRole(user, 'principal', 'admin') && !teacherClassIds(user, row.school_id).includes(row.class_id)) throw Object.assign(new Error('无权修改该班级测评状态'), { status: 403, code: 'NO_PERMISSION' });
          if (teacherOnly(user) && !await userHasCapability(user, 'UPDATE_TEST_STATUS', row.school_id, row.class_id)) throw Object.assign(new Error('当前账号无更新测评状态权限'), { status: 403, code: 'CAPABILITY_DENIED' });
          if (!taskStatusAllowed(row.status, item.status)) throw Object.assign(new Error(`不能从${row.status}变更为${item.status}`), { status: 409, code: 'TASK_STATUS_INVALID' });
          const expectedVersion = item.expectedVersion == null ? null : Number(item.expectedVersion);
          const updated = await client.query(`UPDATE task_students SET status=$1,note=$2,version=version+1,
            check_in_at=CASE WHEN $1='已签到' THEN COALESCE(check_in_at,now()) ELSE check_in_at END,
            completed_at=CASE WHEN $1='已完成' THEN COALESCE(completed_at,now()) ELSE completed_at END
            WHERE task_id=$3 AND student_id=$4 AND ($5::int IS NULL OR version=$5) RETURNING *`, [item.status, item.note || null, item.taskId, item.studentId, expectedVersion]);
          if (!updated.rowCount) throw Object.assign(new Error('记录已被其他人更新，请刷新后重试'), { status: 409, code: 'VERSION_CONFLICT' });
          await client.query(`INSERT INTO task_student_status_events(task_id,student_id,from_status,to_status,note,reason_code,operator_teacher_id,expected_version,resulting_version,client_operation_id)
            VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, [item.taskId, item.studentId, row.status, item.status, item.note || null, item.reasonCode || null, user.id, expectedVersion, updated.rows[0].version, item.clientOperationId || null]);
          saved.push({ ...updated.rows[0], schoolId: row.school_id });
        }
        await client.query('COMMIT');
        for (const item of saved) await audit(user, req, 'task.status.batch_update', 'task_student', item.id, null, item, item.schoolId);
        return createdIdempotently(res, user, idempotency, { updated: saved.length, items: saved });
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'tasks' && parts[3] === 'students' && parts[5] === 'status-history') {
      const taskStudent = await taskStudentForUser(user, parts[2], parts[4]);
      if (!taskStudent) return fail(res, 404, 'TASK_STUDENT_NOT_FOUND', '任务学生不存在或无权访问');
      if (teacherOnly(user) && !await userHasCapability(user, 'VIEW_TEST_TASKS', taskStudent.school_id, taskStudent.class_id)) return fail(res, 403, 'CAPABILITY_DENIED', '当前账号无查看测评任务权限');
      const history = await query(`SELECT id,task_id AS "taskId",student_id AS "studentId",from_status AS "fromStatus",to_status AS "toStatus",note,
          reason_code AS "reasonCode",operator_teacher_id AS "operatorTeacherId",expected_version AS "expectedVersion",resulting_version AS "resultingVersion",
          client_operation_id AS "clientOperationId",created_at AS "createdAt"
        FROM task_student_status_events WHERE task_id=$1 AND student_id=$2 ORDER BY created_at DESC,id DESC LIMIT 100`, [parts[2], parts[4]]);
      return ok(res, history.rows);
    }
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'tasks' && parts[3] === 'students' && parts[5] === 'scores') {
      const taskStudent = await taskStudentForUser(user, parts[2], parts[4]);
      if (!taskStudent) return fail(res, 404, 'TASK_STUDENT_NOT_FOUND', '任务学生不存在或无权访问');
      const result = await query(`SELECT id,item_code AS item,score,note,confidence,review_status AS "reviewStatus",manual_reviewed AS "humanReviewed",source,created_at AS "createdAt",updated_at AS "updatedAt"
        FROM assessment_scores WHERE task_id=$1 AND student_id=$2 ORDER BY item_code`, [parts[2], parts[4]]);
      return ok(res, normalizeScoreRows(result.rows));
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'tasks' && parts[3] === 'students' && parts[5] === 'scores') {
      if (!hasRole(user, 'teacher', 'principal', 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有学校工作人员可以录入成绩');
      const taskStudent = await taskStudentForUser(user, parts[2], parts[4]);
      if (!taskStudent) return fail(res, 404, 'TASK_STUDENT_NOT_FOUND', '任务学生不存在或无权访问');
      const input = await body(req);
      if (!Array.isArray(input.scores) || input.scores.length === 0) return fail(res, 400, 'SCORES_REQUIRED', '至少需要提交一项成绩');
      if (input.scores.length > MOVEMENT_SCORE_RULES.itemCount) return fail(res, 400, 'SCORES_TOO_MANY', `最多提交${MOVEMENT_SCORE_RULES.itemCount}项成绩`);
      const itemCodes = new Set();
      for (const item of input.scores) {
        if (!MOVEMENT_ITEM_CODES.includes(String(item?.item || '').trim())) throw Object.assign(new Error('体测项目不合法'), { status: 400, code: 'SCORE_ITEM_INVALID' });
        const itemCode = String(item.item).trim();
        if (itemCodes.has(itemCode)) throw Object.assign(new Error('同一请求不能重复提交体测项目'), { status: 400, code: 'SCORE_ITEM_DUPLICATE' });
        itemCodes.add(itemCode);
      }
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
      if (idempotency === false) return;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const saved = [];
        for (const item of input.scores) {
          const score = normalizeScore(item.score);
          const confidence = normalizeConfidence(item.confidence == null ? 0 : item.confidence);
          if (score == null || confidence == null) {
            throw Object.assign(new Error('成绩或置信度不合法'), { status: 400, code: 'SCORE_INVALID' });
          }
          const reviewStatus = normalizeReviewStatus(item.reviewStatus, confidence);
          const result = await client.query(`INSERT INTO assessment_scores(task_id,student_id,item_code,score,confidence,note,source,review_status,manual_reviewed,created_by)
            VALUES($1,$2,$3,$4,$5,$6,$7,$8,FALSE,$9)
            ON CONFLICT(task_id,student_id,item_code) DO UPDATE SET score=EXCLUDED.score,confidence=EXCLUDED.confidence,note=EXCLUDED.note,source=EXCLUDED.source,review_status=EXCLUDED.review_status,manual_reviewed=FALSE,updated_at=now()
            RETURNING id,item_code AS item,score,note,confidence,review_status AS "reviewStatus"`, [parts[2], parts[4], item.item, score, confidence, item.note || '', item.source || 'teacher', reviewStatus, user.id]);
          saved.push({ ...result.rows[0], score: Number(result.rows[0].score), confidence: Number(result.rows[0].confidence) });
        }
        if (input.markCompleted === true) await client.query(`UPDATE task_students SET status='已完成',completed_at=COALESCE(completed_at,now()),version=version+1 WHERE task_id=$1 AND student_id=$2`, [parts[2], parts[4]]);
        await client.query('COMMIT');
        await audit(user, req, 'scores.upsert', 'task_student', `${parts[2]}:${parts[4]}`, null, saved, taskStudent.school_id);
        return createdIdempotently(res, user, idempotency, saved);
      } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    }
    if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'scores' && parts[3] === 'review') {
      if (!hasRole(user, 'teacher', 'principal', 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有学校工作人员可以复核成绩');
      const scoreResult = await query(`SELECT s.*,t.school_id,st.class_id FROM assessment_scores s JOIN assessment_tasks t ON t.id=s.task_id JOIN students st ON st.id=s.student_id WHERE s.id=$1`, [parts[2]]);
      const scoreRow = scoreResult.rows[0];
      if (!scoreRow || !schoolAllowed(user, scoreRow.school_id)) return fail(res, 404, 'SCORE_NOT_FOUND', '成绩不存在或无权访问');
      if (hasRole(user, 'teacher') && !hasRole(user, 'principal', 'admin') && !teacherClassIds(user, scoreRow.school_id).includes(scoreRow.class_id)) return fail(res, 403, 'NO_PERMISSION', '无权复核该班级成绩');
      const input = await body(req);
      const newScore = input.score == null ? normalizeScore(scoreRow.score) : normalizeScore(input.score);
      if (newScore == null) return fail(res, 400, 'SCORE_INVALID', '成绩必须在 0 到 5 之间');
      if (input.action != null && !['approve', 'reject'].includes(String(input.action))) return fail(res, 400, 'REVIEW_ACTION_INVALID', '复核动作不合法');
      const reviewStatus = input.action === 'reject' ? 'pendingReview' : 'passed';
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ scoreId: parts[2], ...input }));
      if (idempotency === false) return;
      const humanReviewed = input.action !== 'reject';
      const updated = await query(`UPDATE assessment_scores SET score=$1,review_status=$2,manual_reviewed=$3,note=$4,updated_at=now() WHERE id=$5 RETURNING id,item_code AS item,score,note,confidence,review_status AS "reviewStatus",manual_reviewed AS "humanReviewed"`, [newScore, reviewStatus, humanReviewed, input.reason || scoreRow.note || '', parts[2]]);
      await query(`INSERT INTO score_reviews(score_id,reviewer_id,action,old_score,new_score,reason) VALUES($1,$2,$3,$4,$5,$6)`, [parts[2], user.id, input.action || 'approve', scoreRow.score, newScore, input.reason || '']);
      await audit(user, req, 'score.review', 'assessment_score', parts[2], scoreRow, updated.rows[0], scoreRow.school_id);
      return okIdempotently(res, user, idempotency, { ...updated.rows[0], score: Number(updated.rows[0].score), confidence: Number(updated.rows[0].confidence) });
    }
    if (req.method === 'GET' && url.pathname === '/v1/admin/operations/items') {
      if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权查看运营队列');
      const schoolId = queryValue(url, 'schoolId') || user.roles.find((role) => role.school_id)?.school_id;
      if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
      const type = queryValue(url, 'type') || 'all';
      const items = [];
      if (type === 'all' || type === 'reviews') {
        const result = await query(`SELECT s.id,s.review_status AS status,'reviews' AS type,s.item_code AS title,st.name AS "studentName",c.name AS "className",s.created_at AS "createdAt",s.confidence,t.title AS "taskTitle"
          FROM assessment_scores s JOIN assessment_tasks t ON t.id=s.task_id JOIN students st ON st.id=s.student_id JOIN classes c ON c.id=st.class_id
          WHERE s.review_status='pendingReview' AND st.school_id=$1 ORDER BY s.created_at DESC LIMIT 100`, [schoolId]);
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
      if (type === 'privacy' && row.request_type === 'delete' && input.status === 'completed' && !hasRole(user, 'admin')) return fail(res, 403, 'PRIVACY_DELETE_ADMIN_REQUIRED', '删除申请必须由平台管理员最终确认');
      const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ type, id, status: input.status, note: input.note || '' }));
      if (idempotency === false) return;
      let updated;
      let jobId = null;
      if (type === 'reviews') updated = await query(`UPDATE assessment_scores SET review_status=$1,manual_reviewed=$2,note=COALESCE($3,note),updated_at=now() WHERE id=$4 RETURNING id,review_status AS status,manual_reviewed AS "humanReviewed"`, [input.status, input.status === 'passed', input.note || null, id]);
      if (type === 'privacy' && row.request_type === 'delete' && input.status === 'completed') {
        const job = await enqueueJob('privacy.anonymize', { requestId: id, studentId: row.student_id, requestedBy: user.id });
        jobId = job.id;
        updated = await query(`UPDATE privacy_requests SET status='processing',reviewed_by=$1,completed_at=NULL WHERE id=$2 RETURNING id,status`, [user.id, id]);
      }
      if (type === 'privacy' && !(row.request_type === 'delete' && input.status === 'completed')) updated = await query(`UPDATE privacy_requests SET status=$1,reviewed_by=$2,completed_at=CASE WHEN $1 IN ('completed','rejected') THEN now() ELSE completed_at END WHERE id=$3 RETURNING id,status`, [input.status, user.id, id]);
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
    await handleCourseRoutes({ req, res, user, parts, query, hasRole, schoolAllowed, guardianStudentForUser, body, fail, requiredString, beginIdempotentRequest, requestBodyHash, failIdempotently, createdIdempotently, okIdempotently, ok });
    if (res.writableEnded) return;
    await handleActivityRoutes({
      req, res, user, url, parts,
      query, pool, hasRole, queryValue, studentForUser, fail,
      requiredString, schoolAllowed, assertPhone, beginIdempotentRequest,
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
      const bodyReport = scoreBodyAssessment({ heightCm: row.heightCm, weightKg: row.weightKg, ageMonths: ageAtMeasurement, gender: student.gender, snapshots: row.snapshots || [] });
      return ok(res, {
        ...row,
        heightCm: Number(row.heightCm),
        weightKg: Number(row.weightKg),
        bmi: Number(row.bmi),
        overallLevel: bodyReport.overallLevel,
        algorithmVersion: POSTURE_ALGORITHM_VERSION,
        snapshots: row.snapshots || [],
        ...bodyReport
      });
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
    return fail(res, 404, 'NOT_FOUND', '接口不存在');
  } catch (error) {
    logger.error('http.request_failed', { requestId: requestId(req), method: req.method, path: req.url?.split('?')[0], error: error.message, code: error.code });
    const status = error.code === '23505' ? 409 : (error.status || 500);
    const code = error.code === '23505' ? 'DUPLICATE_RESOURCE' : (error.code || 'SERVER_ERROR');
    const message = error.code === '23505' ? '数据已存在' : (error.status ? error.message : '服务内部错误');
    if (req._idempotencyKeyHash) {
      await query(`UPDATE idempotency_keys SET status='failed',response_json=$1,response_status=$2,locked_at=NULL,expires_at=now()+interval '10 minutes' WHERE key_hash=$3`, [JSON.stringify({ status, body: { code, message, data: null } }), status, req._idempotencyKeyHash]).catch((releaseError) => logger.warn('idempotency.release_failed', { requestId: requestId(req), error: releaseError.message }));
    }
    return fail(res, status, code, message);
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
