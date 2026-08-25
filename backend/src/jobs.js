import { pool, query } from './db.js';
import { logger, recordMetric } from './observability.js';
import { config } from './config.js';
import { reconcileFieldLiveness } from './fieldLiveness.js';
import { auditEvent } from './audit.js';
import { refreshReportForStudentId } from './reportRefresh.js';

const state = { enabled: false, running: false, stopping: false, active: 0, lastRunAt: null, lastError: null, processed: 0 };
let timer;
let lastLivenessReconcileAt = 0;
const idleWaiters = new Set();

const notifyIdle = () => {
  if (state.running) return;
  for (const resolve of idleWaiters) resolve(true);
  idleWaiters.clear();
};

const waitForIdle = (timeoutMs) => {
  if (!state.running) return Promise.resolve(true);
  return new Promise((resolve) => {
    const timeout = setTimeout(() => { idleWaiters.delete(done); resolve(false); }, timeoutMs);
    const done = () => { clearTimeout(timeout); resolve(true); };
    idleWaiters.add(done);
  });
};

async function reconcileStaleFieldDevices() {
  const intervalMs = config.fieldLivenessReconcileIntervalSeconds * 1000;
  if (Date.now() - lastLivenessReconcileAt < intervalMs) return;
  lastLivenessReconcileAt = Date.now();
  const result = await reconcileFieldLiveness({ query }, config.fieldDeviceOfflineAfterSeconds);
  for (const device of result.devices) {
    recordMetric('xiangshang_field_devices_offline_total');
    const message = { origin: 'field-liveness-worker', schoolId: device.schoolId, type: 'device.offline', payload: device, at: new Date().toISOString() };
    await query('SELECT pg_notify($1,$2)', ['field_updates', JSON.stringify(message)]).catch((error) => logger.warn('field.liveness_publish_failed', { deviceId: device.id, error: error.message }));
  }
  if (result.devices.length || result.stations.length) logger.warn('field.liveness_reconciled', { offlineDevices: result.devices.length, offlineStations: result.stations.length });
}

export async function enqueueJob(jobType, payload = {}, availableAt = new Date()) {
  const result = await query(`INSERT INTO job_queue(job_type,payload,available_at) VALUES($1,$2,$3) RETURNING id,job_type AS "jobType",status,created_at AS "createdAt"`, [jobType, payload, availableAt]);
  return result.rows[0];
}

async function exportStudent(requestId, payload) {
  await query(`UPDATE privacy_requests SET status='processing' WHERE id=$1 AND status IN ('pending','processing')`, [requestId]);
  const [student, assessments, consents, reports, tasks, scores] = await Promise.all([
    query(`SELECT st.id,st.school_id AS "schoolId",st.name,st.gender,st.birth_date AS "birthDate",st.region,st.is_poverty_area AS "isPovertyArea",g.name AS grade,c.name AS "className"
      FROM students st JOIN grades g ON g.id=st.grade_id JOIN classes c ON c.id=st.class_id WHERE st.id=$1`, [payload.studentId]),
    query(`SELECT id,height_cm AS "heightCm",weight_kg AS "weightKg",bmi,overall_level AS "overallLevel",algorithm_version AS "algorithmVersion",consent_version AS "consentVersion",measured_at AS "measuredAt",data_json AS data FROM body_assessments WHERE student_id=$1 ORDER BY measured_at DESC`, [payload.studentId]),
    query(`SELECT id,consent_version AS "consentVersion",purpose,granted_at AS "grantedAt",revoked_at AS "revokedAt",expires_at AS "expiresAt" FROM data_consents WHERE student_id=$1 ORDER BY created_at DESC`, [payload.studentId]),
    query(`SELECT id,task_id AS "taskId",risk_level AS "riskLevel",total_score AS "totalScore",rule_version AS "ruleVersion",status,current_version AS "currentVersion",generated_at AS "generatedAt",published_at AS "publishedAt" FROM diagnosis_reports WHERE student_id=$1 ORDER BY generated_at DESC`, [payload.studentId]),
    query(`SELECT ts.id,ts.task_id AS "taskId",ts.status,ts.note,ts.check_in_at AS "checkInAt",ts.completed_at AS "completedAt",t.title,t.test_date AS "testDate",t.rule_version AS "ruleVersion" FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id WHERE ts.student_id=$1 ORDER BY t.test_date DESC`, [payload.studentId]),
    query(`SELECT id,task_id AS "taskId",item_code AS "itemCode",score,confidence,note,source,review_status AS "reviewStatus",manual_reviewed AS "manualReviewed",algorithm_version AS "algorithmVersion",created_at AS "createdAt" FROM assessment_scores WHERE student_id=$1 ORDER BY created_at DESC`, [payload.studentId])
  ]);
  if (!student.rows[0]) throw Object.assign(new Error('学生不存在'), { code: 'STUDENT_NOT_FOUND' });
  const exportData = { exportedAt: new Date().toISOString(), student: student.rows[0], assessments: assessments.rows, consents: consents.rows, reports: reports.rows, tasks: tasks.rows, scores: scores.rows };
  await query(`UPDATE privacy_requests SET status='completed',result_json=$1,completed_at=now() WHERE id=$2`, [exportData, requestId]);
  await auditEvent({ operatorId: payload.requestedBy || null, schoolId: student.rows[0].schoolId, action: 'privacy.export.completed', resourceType: 'privacy_request', resourceId: requestId, before: { status: 'processing' }, after: { status: 'completed', studentId: payload.studentId, recordCounts: { assessments: assessments.rows.length, consents: consents.rows.length, reports: reports.rows.length, tasks: tasks.rows.length, scores: scores.rows.length } }, requestId: `worker:privacy-export:${requestId}` });
}

async function anonymizeStudent(requestId, payload) {
  const client = await pool.connect();
  let schoolId = null;
  try {
    await client.query('BEGIN');
    const request = await client.query(`SELECT pr.id,pr.status,pr.request_type,pr.requested_by,st.id AS student_id,st.school_id
      FROM privacy_requests pr JOIN students st ON st.id=pr.student_id WHERE pr.id=$1 FOR UPDATE OF pr,st`, [requestId]);
    const row = request.rows[0];
    if (!row || !['delete', 'anonymize'].includes(row.request_type)) throw Object.assign(new Error('隐私删除申请不存在或类型不支持'), { code: 'PRIVACY_DELETE_INVALID' });
    schoolId = row.school_id;
    await client.query(`UPDATE privacy_requests SET status='processing',completed_at=NULL WHERE id=$1 AND status IN ('pending','approved','processing')`, [requestId]);
    // Remove child-specific health records and assessment reports. Operational
    // task rows remain as anonymized audit counts, but can no longer identify a
    // child through the student record or parent binding.
    await client.query('DELETE FROM body_assessments WHERE student_id=$1', [row.student_id]);
    await client.query('DELETE FROM diagnosis_reports WHERE student_id=$1', [row.student_id]);
    await client.query('DELETE FROM assessment_scores WHERE student_id=$1', [row.student_id]);
    await client.query('DELETE FROM task_students WHERE student_id=$1', [row.student_id]);
    await client.query('DELETE FROM course_progress WHERE student_id=$1', [row.student_id]);
    await client.query('DELETE FROM data_consents WHERE student_id=$1', [row.student_id]);
    await client.query('DELETE FROM parent_student_bindings WHERE student_id=$1', [row.student_id]);
    await client.query('DELETE FROM student_binding_codes WHERE student_id=$1', [row.student_id]);
    await client.query(`UPDATE students SET name='已删除学生',student_no=NULL,gender='',birth_date=NULL,region='',is_poverty_area=FALSE,status='inactive',updated_at=now() WHERE id=$1`, [row.student_id]);
    const result = { anonymized: true, deletedHealthRecords: true, studentId: row.student_id, completedAt: new Date().toISOString() };
    await client.query(`UPDATE privacy_requests SET status='completed',result_json=$1,completed_at=now() WHERE id=$2`, [result, requestId]);
    await client.query('COMMIT');
    await auditEvent({ operatorId: payload.requestedBy || row.requested_by || null, schoolId, action: 'privacy.delete.completed', resourceType: 'privacy_request', resourceId: requestId, before: { status: 'processing' }, after: result, requestId: `worker:privacy-delete:${requestId}` });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally { client.release(); }
}

async function anonymizeAccount(requestId, payload) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const request = await client.query(`SELECT adr.id,adr.status,adr.requested_by,u.id AS user_id,u.name,u.phone
      FROM account_deletion_requests adr JOIN users u ON u.id=adr.user_id WHERE adr.id=$1 FOR UPDATE OF adr,u`, [requestId]);
    const row = request.rows[0];
    if (!row || !['pending', 'approved', 'processing'].includes(row.status)) throw Object.assign(new Error('账户注销申请不存在或状态不支持'), { code: 'ACCOUNT_DELETE_INVALID' });
    await client.query(`UPDATE account_deletion_requests SET status='processing',completed_at=NULL WHERE id=$1`, [requestId]);

    // Keep school-side audit/health rows addressable by an immutable user id,
    // but remove the account's direct identity, sessions and user-authored
    // content. This is an anonymization operation, not an unsafe hard delete.
    await client.query(`UPDATE users SET name='已注销用户',phone=NULL,password_hash=NULL,status='disabled',updated_at=now() WHERE id=$1`, [row.user_id]);
    await client.query(`UPDATE refresh_sessions SET revoked_at=COALESCE(revoked_at,now()) WHERE user_id=$1`, [row.user_id]);
    await client.query('DELETE FROM auth_identities WHERE user_id=$1', [row.user_id]);
    await client.query('DELETE FROM user_mfa_totp WHERE user_id=$1', [row.user_id]);
    await client.query('DELETE FROM account_password_resets WHERE user_id=$1', [row.user_id]);
    await client.query(`UPDATE files SET owner_id=NULL,status='expired',expires_at=COALESCE(expires_at,now()) WHERE owner_id=$1`, [row.user_id]);
    await client.query(`UPDATE parent_student_bindings SET status='revoked',binding_code=NULL,expires_at=now() WHERE parent_user_id=$1`, [row.user_id]);
    await client.query(`UPDATE data_consents SET revoked_at=COALESCE(revoked_at,now()) WHERE parent_user_id=$1`, [row.user_id]);
    await client.query(`UPDATE activity_registrations SET contact_name='已注销用户',phone='' WHERE user_id=$1`, [row.user_id]);
    await client.query(`UPDATE expert_appointments SET note='[已注销账户内容已清理]' WHERE user_id=$1`, [row.user_id]);
    await client.query(`UPDATE course_uploads SET notes='[已注销账户内容已清理]',attachment_name='',attachment_file_id=NULL WHERE user_id=$1`, [row.user_id]);
    await client.query(`UPDATE class_posts SET author='已注销用户',content='[已注销账户内容已清理]' WHERE user_id=$1`, [row.user_id]);
    await client.query(`UPDATE support_messages SET content='[已注销账户内容已清理]' WHERE user_id=$1`, [row.user_id]);
    await client.query('DELETE FROM messages WHERE receiver_user_id=$1', [row.user_id]);

    const result = { anonymized: true, sessionsRevoked: true, userId: row.user_id, completedAt: new Date().toISOString() };
    await client.query(`UPDATE account_deletion_requests SET status='completed',result_json=$1,completed_at=now() WHERE id=$2`, [result, requestId]);
    await client.query('COMMIT');
    await auditEvent({ operatorId: payload.requestedBy || row.requested_by || null, action: 'account.delete.completed', resourceType: 'account_deletion_request', resourceId: requestId, before: { status: 'processing', userId: row.user_id }, after: result, requestId: `worker:account-delete:${requestId}` });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally { client.release(); }
}

async function processJob(job) {
  if (job.job_type === 'privacy.export') return exportStudent(job.payload.requestId, job.payload);
  if (job.job_type === 'privacy.anonymize') return anonymizeStudent(job.payload.requestId, job.payload);
  if (job.job_type === 'account.anonymize') return anonymizeAccount(job.payload.requestId, job.payload);
  if (job.job_type === 'report.refresh') return refreshReportForStudentId({ studentId: job.payload.studentId, taskId: job.payload.taskId || null, requestId: `worker:report-refresh:${job.id}` });
  throw Object.assign(new Error(`未知任务类型: ${job.job_type}`), { code: 'JOB_TYPE_UNKNOWN' });
}

async function claimJobs(limit) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(`SELECT id,job_type,payload,attempts FROM job_queue
      WHERE (status='queued' AND available_at<=now()) OR (status='processing' AND locked_at<now()-interval '5 minutes')
      ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT $1`, [limit]);
    const jobs = result.rows;
    if (jobs.length) await client.query(`UPDATE job_queue SET status='processing',attempts=attempts+1,locked_at=now(),last_error=NULL WHERE id=ANY($1::text[])`, [jobs.map((job) => job.id)]);
    await client.query('COMMIT');
    return jobs;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally { client.release(); }
}

async function processClaimedJob(job) {
  const startedAt = Date.now();
  try {
    await processJob(job);
    await query(`UPDATE job_queue SET status='completed',completed_at=now(),locked_at=NULL WHERE id=$1`, [job.id]);
    state.processed += 1;
    recordMetric('xiangshang_jobs_processed_total', { job_type: job.job_type, outcome: 'completed' });
    recordMetric('xiangshang_job_processing_duration_ms_total', { job_type: job.job_type }, Date.now() - startedAt);
    return null;
  } catch (error) {
    const nextStatus = Number(job.attempts) + 1 >= 3 ? 'failed' : 'queued';
    await query(`UPDATE job_queue SET status=$1,available_at=now() + CASE WHEN $1='queued' THEN interval '30 seconds' ELSE interval '0 seconds' END,locked_at=NULL,last_error=$2 WHERE id=$3`, [nextStatus, error.message, job.id]);
    recordMetric('xiangshang_jobs_processed_total', { job_type: job.job_type, outcome: nextStatus });
    recordMetric('xiangshang_job_processing_duration_ms_total', { job_type: job.job_type }, Date.now() - startedAt);
    if (nextStatus === 'failed') recordMetric('xiangshang_jobs_failed_total', { job_type: job.job_type });
    if (nextStatus === 'failed' && ['privacy.export', 'privacy.anonymize'].includes(job.job_type) && job.payload?.requestId) {
      await query(`UPDATE privacy_requests SET status='failed',result_json=$1,completed_at=now() WHERE id=$2`, [{ error: error.message }, job.payload.requestId]);
      const request = await query(`SELECT pr.id,pr.requested_by AS "requestedBy",st.school_id AS "schoolId",pr.student_id AS "studentId"
        FROM privacy_requests pr JOIN students st ON st.id=pr.student_id WHERE pr.id=$1`, [job.payload.requestId]);
      if (request.rows[0]) {
        const action = job.job_type === 'privacy.anonymize' ? 'privacy.delete.failed' : 'privacy.export.failed';
        await auditEvent({ operatorId: request.rows[0].requestedBy || null, schoolId: request.rows[0].schoolId, action, resourceType: 'privacy_request', resourceId: request.rows[0].id, before: { status: 'processing' }, after: { status: 'failed', studentId: request.rows[0].studentId, error: error.message.slice(0, 500) }, requestId: `worker:${job.job_type}:${request.rows[0].id}` }).catch((auditError) => logger.error('job.audit_failed', { jobId: job.id, error: auditError.message }));
      }
    }
    if (nextStatus === 'failed' && job.job_type === 'account.anonymize' && job.payload?.requestId) {
      await query(`UPDATE account_deletion_requests SET status='failed',result_json=$1,completed_at=now() WHERE id=$2`, [{ error: error.message }, job.payload.requestId]);
      const request = await query(`SELECT id,user_id AS "userId",requested_by AS "requestedBy" FROM account_deletion_requests WHERE id=$1`, [job.payload.requestId]);
      if (request.rows[0]) {
        await auditEvent({ operatorId: request.rows[0].requestedBy || null, action: 'account.delete.failed', resourceType: 'account_deletion_request', resourceId: request.rows[0].id, before: { status: 'processing', userId: request.rows[0].userId }, after: { status: 'failed', userId: request.rows[0].userId, error: error.message.slice(0, 500) }, requestId: `worker:${job.job_type}:${request.rows[0].id}` }).catch((auditError) => logger.error('job.audit_failed', { jobId: job.id, error: auditError.message }));
      }
    }
    logger.error('job.process_failed', { jobId: job.id, jobType: job.job_type, error: error.message, status: nextStatus });
    return error;
  }
}

async function runOnce(concurrency = config.jobWorkerConcurrency) {
  if (state.running || state.stopping) return;
  state.running = true;
  state.lastRunAt = new Date().toISOString();
  try {
    try { await reconcileStaleFieldDevices(); } catch (error) { logger.error('field.liveness_reconcile_failed', { error: error.message }); }
    if (state.stopping) return;
    const jobs = await claimJobs(Math.min(20, Math.max(1, Number(concurrency) || 1)));
    state.active = jobs.length;
    if (!jobs.length) { state.lastError = null; return; }
    const results = await Promise.allSettled(jobs.map((job) => processClaimedJob(job)));
    const rejected = results.find((result) => result.status === 'rejected');
    const handledFailure = results.find((result) => result.status === 'fulfilled' && result.value);
    state.lastError = rejected?.reason?.message || handledFailure?.value?.message || null;
  } catch (error) {
    state.lastError = error.message;
    logger.error('job.claim_failed', { error: error.message });
  } finally {
    state.active = 0;
    state.running = false;
    notifyIdle();
  }
}

export function startJobWorker({ enabled = true, intervalMs = 1000, concurrency = config.jobWorkerConcurrency, keepProcessAlive = false } = {}) {
  if (!enabled || timer) return state;
  state.enabled = true;
  state.stopping = false;
  timer = setInterval(() => void runOnce(concurrency), Math.max(250, intervalMs));
  if (!keepProcessAlive) timer.unref?.();
  void runOnce(concurrency);
  return state;
}

export async function stopJobWorker({ drainMs = 0 } = {}) {
  if (timer) clearInterval(timer);
  timer = undefined;
  state.enabled = false;
  state.stopping = true;
  return waitForIdle(Math.max(0, drainMs));
}

export function jobWorkerStatus() { return { ...state }; }
