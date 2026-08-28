import crypto from 'node:crypto';
import { config } from '../config.js';
import { encryptPushToken, pushTokenHash } from '../pushTokens.js';

const allowed = (value, values, field) => {
  const normalized = String(value || '').trim().toLowerCase();
  if (!values.includes(normalized)) throw Object.assign(new Error(`${field}不支持`), { status: 400, code: 'INVALID_ARGUMENT' });
  return normalized;
};

const bounded = (value, field, min, max) => {
  const normalized = String(value || '').trim();
  if (normalized.length < min || normalized.length > max) throw Object.assign(new Error(`${field}长度不合法`), { status: 400, code: 'INVALID_ARGUMENT' });
  return normalized;
};

const publicProjection = (row) => ({
  installationId: row.installationId,
  platform: row.platform,
  provider: row.provider,
  environment: row.environment,
  status: row.status,
  appVersion: row.appVersion || null,
  locale: row.locale || null,
  tokenLastFour: row.tokenLastFour,
  lastRegisteredAt: row.lastRegisteredAt,
  createdAt: row.createdAt
});

/** Self-scoped APNs/FCM installation registry. Raw tokens are encrypted at rest
 * and never returned by the API or included in audit records. */
export async function handleDeviceInstallationRoutes(context) {
  const { req, res, user, parts, query, body, fail, ok, created, audit } = context;
  if (parts[0] !== 'v1' || parts[1] !== 'notification-devices') return;

  if (req.method === 'GET' && parts.length === 2) {
    const result = await query(`SELECT id AS "installationId",platform,provider,environment,status,app_version AS "appVersion",locale,
      token_last_four AS "tokenLastFour",last_registered_at AS "lastRegisteredAt",created_at AS "createdAt"
      FROM device_installations WHERE user_id=$1 AND status='active' ORDER BY last_registered_at DESC`, [user.id]);
    return ok(res, result.rows.map(publicProjection));
  }

  if (req.method === 'POST' && parts.length === 2) {
    const input = await body(req);
    const platform = allowed(input.platform, ['ios', 'android'], 'platform');
    const provider = allowed(input.provider, platform === 'ios' ? ['apns'] : ['fcm'], 'provider');
    const environment = allowed(input.environment, ['sandbox', 'production'], 'environment');
    const deviceInstanceId = bounded(input.deviceInstanceId, 'deviceInstanceId', 12, 256);
    const token = bounded(input.pushToken, 'pushToken', 20, 4096);
    const appVersion = String(input.appVersion || '').trim().slice(0, 64) || null;
    const locale = String(input.locale || '').trim().slice(0, 32) || null;
    const tokenHash = pushTokenHash(provider, token);
    const tokenCiphertext = encryptPushToken(token, config.pushTokenEncryptionKey);
    const deviceInstanceHash = crypto.createHash('sha256').update(deviceInstanceId).digest('hex');
    await query(`UPDATE device_installations SET status='revoked',invalidated_at=now(),updated_at=now()
      WHERE user_id=$1 AND platform=$2 AND device_instance_hash=$3 AND token_hash<>$4 AND status='active'`, [user.id, platform, deviceInstanceHash, tokenHash]);
    const result = await query(`INSERT INTO device_installations(user_id,platform,provider,environment,device_instance_hash,token_hash,token_ciphertext,token_last_four,status,app_version,locale,last_registered_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,'active',$9,$10,now())
      ON CONFLICT(token_hash) DO UPDATE SET user_id=EXCLUDED.user_id,platform=EXCLUDED.platform,provider=EXCLUDED.provider,
        environment=EXCLUDED.environment,device_instance_hash=EXCLUDED.device_instance_hash,token_ciphertext=EXCLUDED.token_ciphertext,
        token_last_four=EXCLUDED.token_last_four,status='active',app_version=EXCLUDED.app_version,locale=EXCLUDED.locale,
        last_registered_at=now(),invalidated_at=NULL,updated_at=now()
      RETURNING id AS "installationId",platform,provider,environment,status,app_version AS "appVersion",locale,
        token_last_four AS "tokenLastFour",last_registered_at AS "lastRegisteredAt",created_at AS "createdAt"`,
    [user.id, platform, provider, environment, deviceInstanceHash, tokenHash, tokenCiphertext, token.slice(-4), appVersion, locale]);
    const response = publicProjection(result.rows[0]);
    await audit(user, req, 'notification_device.register', 'device_installation', response.installationId, null, { ...response, tokenLastFour: '[REDACTED]' });
    return created(res, response);
  }

  if (req.method === 'DELETE' && parts.length === 3) {
    const installationId = String(parts[2] || '');
    const result = await query(`UPDATE device_installations SET status='revoked',invalidated_at=now(),updated_at=now()
      WHERE id=$1 AND user_id=$2 AND status='active' RETURNING id AS "installationId"`, [installationId, user.id]);
    if (!result.rowCount) return fail(res, 404, 'DEVICE_INSTALLATION_NOT_FOUND', '推送设备不存在或已撤销');
    await audit(user, req, 'notification_device.revoke', 'device_installation', installationId, { status: 'active' }, { status: 'revoked' });
    return ok(res, { installationId, status: 'revoked' });
  }
}
