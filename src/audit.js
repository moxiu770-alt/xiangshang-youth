import crypto from 'node:crypto';
import { config } from './config.js';
import { pool, query } from './db.js';

const canonicalize = (value) => {
  if (Array.isArray(value)) return `[${value.map(canonicalize).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalize(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
};
const maskPhone = (value) => {
  const phone = String(value || '');
  return /^1\d{10}$/.test(phone) ? `${phone.slice(0, 3)}****${phone.slice(-4)}` : phone;
};
const auditJson = (value) => {
  if (value == null) return null;
  if (typeof value === 'string') return value;
  return JSON.stringify(value, (key, nested) => {
    if (['password', 'password_hash', 'token', 'token_hash', 'accessToken', 'refreshToken', 'access_token_hash', 'secret', 'secret_encrypted', 'pending_secret_encrypted', 'recoveryCodes', 'recovery_code_hashes'].includes(key)) return '[REDACTED]';
    if (key === 'phone') return maskPhone(nested);
    return nested;
  });
};
const chainValue = (value) => {
  if (value == null) return null;
  try { return JSON.parse(value); } catch { return value; }
};

// A single implementation is used by both HTTP handlers and independent workers,
// so asynchronous privacy jobs cannot bypass the production audit hash chain.
export async function auditEvent({ operatorId = null, schoolId = null, action, resourceType, resourceId = null, before = null, after = null, ip = null, requestId = null }) {
  const beforeJson = auditJson(before);
  const afterJson = auditJson(after);
  if (config.auditLogSigningKey.length < 32) {
    await query(`INSERT INTO audit_logs(operator_id,school_id,action,resource_type,resource_id,before_json,after_json,ip,request_id)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, [operatorId, schoolId, action, resourceType, resourceId, beforeJson, afterJson, ip, requestId]);
    return;
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const scopeKey = schoolId || '__platform__';
    await client.query('INSERT INTO audit_chain_state(scope_key) VALUES($1) ON CONFLICT(scope_key) DO NOTHING', [scopeKey]);
    const state = await client.query('SELECT last_hash AS "lastHash" FROM audit_chain_state WHERE scope_key=$1 FOR UPDATE', [scopeKey]);
    const createdAt = new Date();
    const id = crypto.randomUUID();
    const record = { id, previousHash: state.rows[0]?.lastHash || null, operatorId, schoolId, action, resourceType, resourceId, before: chainValue(beforeJson), after: chainValue(afterJson), ip, requestId, createdAt: createdAt.toISOString() };
    const entryHash = crypto.createHmac('sha256', config.auditLogSigningKey).update(canonicalize(record)).digest('hex');
    await client.query(`INSERT INTO audit_logs(id,operator_id,school_id,action,resource_type,resource_id,before_json,after_json,ip,request_id,created_at,previous_hash,entry_hash)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`, [id, operatorId, schoolId, action, resourceType, resourceId, beforeJson, afterJson, ip, requestId, createdAt, record.previousHash, entryHash]);
    await client.query('UPDATE audit_chain_state SET last_entry_id=$1,last_hash=$2,updated_at=now() WHERE scope_key=$3', [id, entryHash, scopeKey]);
    await client.query('COMMIT');
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}
