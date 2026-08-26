import crypto from 'node:crypto';

/**
 * Guardian data consent and privacy-request lifecycle. Raw media is never
 * accepted here; this module owns only auditable structured consent records
 * and export/deletion job requests.
 */
export async function handlePrivacyRoutes(context) {
  const {
    req, res, user, url, parts, query, hasRole, guardianStudentForUser,
    queryValue, body, fail, beginIdempotentRequest, requestBodyHash,
    failIdempotently, acceptedIdempotently, okIdempotently, ok, audit,
    enqueueJob
  } = context;

if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'consent') {
  const student = await guardianStudentForUser(user, parts[2]);
  if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
  const result = await query(`SELECT id,consent_id AS "consentId",student_id AS "studentId",parent_user_id AS "parentUserId",consent_version AS "consentVersion",purpose,
      privacy_policy_version AS "privacyPolicyVersion",camera_consent_version AS "cameraConsentVersion",algorithm_notice_version AS "algorithmNoticeVersion",
      device_info_hash AS "deviceInfoHash",app_version AS "appVersion",data_retention_notice_accepted AS "dataRetentionNoticeAccepted",
      granted_at AS "grantedAt",revoked_at AS "revokedAt",expires_at AS "expiresAt",created_at AS "createdAt"
    FROM data_consents WHERE student_id=$1 AND ($2::text IS NULL OR parent_user_id=$2) ORDER BY created_at DESC`, [parts[2], hasRole(user, 'parent') ? user.id : null]);
  return ok(res, result.rows);
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'privacy-requests') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家长可以查看孩子的数据申请');
  const student = await guardianStudentForUser(user, parts[2]);
  if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或未绑定');
  const result = await query(`SELECT id,request_type AS "requestType",status,created_at AS "createdAt",completed_at AS "completedAt",
    CASE WHEN status='completed' AND request_type='export' THEN result_json ELSE NULL END AS "result"
    FROM privacy_requests WHERE student_id=$1 AND requested_by=$2 ORDER BY created_at DESC LIMIT 20`, [parts[2], user.id]);
  return ok(res, result.rows);
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'privacy-requests') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家长可以提交孩子的数据申请');
  const student = await guardianStudentForUser(user, parts[2]);
  if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或未绑定');
  const input = await body(req);
  const requestType = String(input.requestType || '');
  if (!['export', 'delete'].includes(requestType)) return fail(res, 400, 'PRIVACY_REQUEST_TYPE_INVALID', '仅支持数据导出或删除申请');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentId: parts[2], requestType }));
  if (idempotency === false) return;
  const active = await query(`SELECT id,status,created_at AS "createdAt" FROM privacy_requests
    WHERE student_id=$1 AND requested_by=$2 AND request_type=$3 AND status IN ('pending','approved','processing')
    ORDER BY created_at DESC LIMIT 1`, [parts[2], user.id, requestType]);
  if (active.rows[0]) return acceptedIdempotently(res, user, idempotency, { ...active.rows[0], requestType, reused: true });
  const request = await query(`INSERT INTO privacy_requests(student_id,requested_by,request_type,status)
    VALUES($1,$2,$3,'pending') RETURNING id,request_type AS "requestType",status,created_at AS "createdAt"`, [parts[2], user.id, requestType]);
  let jobId = null;
  if (requestType === 'export') {
    const job = await enqueueJob('privacy.export', { requestId: request.rows[0].id, studentId: parts[2], requestedBy: user.id });
    jobId = job.id;
  }
  await audit(user, req, `privacy.${requestType}.request`, 'student', parts[2], null, { requestId: request.rows[0].id, requestType, jobId }, student.school_id);
  return acceptedIdempotently(res, user, idempotency, { ...request.rows[0], jobId });
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'consent') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家长可以提交家庭数据使用同意');
  const student = await guardianStudentForUser(user, parts[2]);
  if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或未绑定');
  const input = await body(req);
  const consentVersion = String(input.consentVersion || 'v1');
  const purpose = String(input.purpose || 'body_assessment');
  const granted = input.granted !== false;
  const expiresAt = input.expiresAt || null;
  const consentId = String(input.consentId || '').trim() || crypto.randomUUID();
  const privacyPolicyVersion = String(input.privacyPolicyVersion || consentVersion).slice(0, 80);
  const cameraConsentVersion = String(input.cameraConsentVersion || consentVersion).slice(0, 80);
  const algorithmNoticeVersion = String(input.algorithmNoticeVersion || '').slice(0, 120) || null;
  const deviceInfoHash = String(input.deviceInfoHash || '').slice(0, 128) || null;
  const appVersion = String(input.appVersion || '').slice(0, 80) || null;
  const retentionAccepted = input.dataRetentionNoticeAccepted === true;
  if (granted && purpose === 'body_assessment' && !retentionAccepted) return fail(res, 400, 'CONSENT_RETENTION_NOTICE_REQUIRED', '请确认数据保留说明后再继续');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentId: parts[2], ...input }));
  if (idempotency === false) return;
  const result = await query(`INSERT INTO data_consents(student_id,parent_user_id,consent_version,purpose,granted_at,revoked_at,expires_at,consent_id,privacy_policy_version,camera_consent_version,algorithm_notice_version,device_info_hash,app_version,data_retention_notice_accepted)
    VALUES($1,$2,$3,$4,CASE WHEN $5 THEN now() ELSE NULL END,CASE WHEN $5 THEN NULL ELSE now() END,$6,$7,$8,$9,$10,$11,$12,$13)
    ON CONFLICT(student_id,parent_user_id,consent_version,purpose) DO UPDATE SET granted_at=CASE WHEN $5 THEN now() ELSE data_consents.granted_at END,
      revoked_at=CASE WHEN $5 THEN NULL ELSE now() END,expires_at=EXCLUDED.expires_at,consent_id=EXCLUDED.consent_id,privacy_policy_version=EXCLUDED.privacy_policy_version,camera_consent_version=EXCLUDED.camera_consent_version,algorithm_notice_version=EXCLUDED.algorithm_notice_version,device_info_hash=EXCLUDED.device_info_hash,app_version=EXCLUDED.app_version,data_retention_notice_accepted=EXCLUDED.data_retention_notice_accepted
    RETURNING id,consent_id AS "consentId",student_id AS "studentId",parent_user_id AS "parentUserId",consent_version AS "consentVersion",purpose,privacy_policy_version AS "privacyPolicyVersion",camera_consent_version AS "cameraConsentVersion",algorithm_notice_version AS "algorithmNoticeVersion",device_info_hash AS "deviceInfoHash",app_version AS "appVersion",data_retention_notice_accepted AS "dataRetentionNoticeAccepted",granted_at AS "grantedAt",revoked_at AS "revokedAt",expires_at AS "expiresAt"`, [parts[2], user.id, consentVersion, purpose, granted, expiresAt, consentId, privacyPolicyVersion, cameraConsentVersion, algorithmNoticeVersion, deviceInfoHash, appVersion, retentionAccepted]);
  await audit(user, req, granted ? 'data_consent.grant' : 'data_consent.revoke', 'data_consent', result.rows[0].id, null, result.rows[0], student.school_id);
  return okIdempotently(res, user, idempotency, result.rows[0]);
}
if (req.method === 'DELETE' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'consent') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有已绑定监护人可以撤销家庭数据使用同意');
  const student = await guardianStudentForUser(user, parts[2]);
  if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
  const consentVersion = queryValue(url, 'consentVersion') || 'v1';
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentId: parts[2], consentVersion, action: 'revoke' }));
  if (idempotency === false) return;
  const result = await query(`UPDATE data_consents SET revoked_at=now() WHERE student_id=$1 AND consent_version=$2 AND ($3::text IS NULL OR parent_user_id=$3) AND revoked_at IS NULL RETURNING id,student_id AS "studentId",consent_version AS "consentVersion",revoked_at AS "revokedAt"`, [parts[2], consentVersion, hasRole(user, 'parent') ? user.id : null]);
  if (!result.rowCount) return failIdempotently(req, res, 404, 'CONSENT_NOT_FOUND', '有效同意记录不存在');
  await audit(user, req, 'data_consent.revoke', 'data_consent', result.rows[0].id, null, result.rows[0], student.school_id);
  return okIdempotently(res, user, idempotency, result.rows[0]);
}
}

