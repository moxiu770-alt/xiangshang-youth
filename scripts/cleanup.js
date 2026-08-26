import { Pool } from 'pg';
import { config } from '../src/config.js';
import { createStorage } from '../src/storage.js';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const storage = createStorage(config);

try {
  const expired = await pool.query(`DELETE FROM idempotency_keys WHERE expires_at < now() RETURNING key_hash`);
  const rateLimits = await pool.query(`DELETE FROM auth_rate_limits WHERE updated_at < now() - interval '1 day' RETURNING key_hash`);
  const sessions = await pool.query(`DELETE FROM refresh_sessions WHERE expires_at < now() OR (revoked_at IS NOT NULL AND revoked_at < now() - interval '30 days') RETURNING id`);
  const passwordResets = await pool.query(`DELETE FROM account_password_resets WHERE expires_at < now() OR used_at IS NOT NULL AND used_at < now() - interval '30 days' RETURNING id`);
  const bindingCodes = await pool.query(`DELETE FROM student_binding_codes WHERE expires_at < now() OR used_at IS NOT NULL AND used_at < now() - interval '30 days' RETURNING id`);
  const deviceRequestNonces = await pool.query(`DELETE FROM field_device_request_nonces WHERE expires_at < now() RETURNING device_id`);
  const oauthStates = await pool.query(`DELETE FROM auth_oauth_states WHERE expires_at < now() OR consumed_at < now() - interval '1 day' RETURNING id`);
  const jobs = await pool.query(`DELETE FROM job_queue WHERE status IN ('completed','failed') AND created_at < now() - interval '30 days' RETURNING id`);
  const runtimeHeartbeats = await pool.query(`DELETE FROM runtime_heartbeats WHERE last_seen_at < now() - interval '7 days' RETURNING instance_id`);
  const healthRetention = await pool.query(`DELETE FROM body_assessments WHERE retention_until IS NOT NULL AND retention_until < now() RETURNING id`);
  const auditRetention = await pool.query(`DELETE FROM audit_logs WHERE retention_until IS NOT NULL AND retention_until < now() RETURNING id`);
  const productEvents = await pool.query(`DELETE FROM product_events WHERE received_at < now() - ($1::int * interval '1 day') RETURNING event_id`, [config.productEventRetentionDays]);
  const files = await pool.query(`SELECT id,object_key,purpose,status,retention_until AS "retentionUntil" FROM files
    WHERE (purpose='field_evidence' AND (
      (status <> 'uploaded' AND expires_at < now())
      OR (status='uploaded' AND retention_until IS NOT NULL AND retention_until < now())
      OR (status='uploaded' AND retention_until IS NULL AND uploaded_at < now() - ($1::int * interval '1 hour'))
    )) OR (purpose <> 'field_evidence' AND (
      (expires_at < now() AND status <> 'uploaded')
      OR (status='uploaded' AND created_at < now() - interval '365 days')
    ))`, [config.fieldEvidenceOrphanRetentionHours]);
  let removedFiles = 0;
  let purgedFieldEvidence = 0;
  let failedFileRemovals = 0;
  for (const file of files.rows) {
    const claimed = await pool.query(`UPDATE files SET status='deleting' WHERE id=$1 AND status=$2 RETURNING id`, [file.id, file.status]);
    if (!claimed.rowCount) continue;
    try {
      await storage.remove(file.object_key);
      if (file.purpose === 'field_evidence' && file.status === 'uploaded' && file.retentionUntil) {
        const purged = await pool.query(`UPDATE session_evidence SET purged_at=COALESCE(purged_at,now()),purge_reason=COALESCE(purge_reason,'retention_expired') WHERE file_id=$1`, [file.id]);
        purgedFieldEvidence += purged.rowCount;
      }
      await pool.query('DELETE FROM files WHERE id=$1', [file.id]);
      removedFiles += 1;
    } catch (error) {
      failedFileRemovals += 1;
      await pool.query(`UPDATE files SET status=$1 WHERE id=$2 AND status='deleting'`, [file.status, file.id]).catch(() => {});
      console.error(JSON.stringify({ event: 'file.cleanup_failed', fileId: file.id, purpose: file.purpose, error: error.message }));
    }
  }
  console.log(JSON.stringify({ expiredIdempotencyKeys: expired.rowCount, expiredRateLimits: rateLimits.rowCount, expiredSessions: sessions.rowCount, expiredPasswordResets: passwordResets.rowCount, expiredBindingCodes: bindingCodes.rowCount, expiredDeviceRequestNonces: deviceRequestNonces.rowCount, expiredOauthStates: oauthStates.rowCount, removedJobs: jobs.rowCount, removedRuntimeHeartbeats: runtimeHeartbeats.rowCount, removedHealthAssessments: healthRetention.rowCount, removedAuditLogs: auditRetention.rowCount, removedProductEvents: productEvents.rowCount, removedFiles, purgedFieldEvidence, failedFileRemovals }));
} finally {
  await pool.end();
}
