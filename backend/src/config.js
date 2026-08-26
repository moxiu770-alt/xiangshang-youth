const isProduction = process.env.NODE_ENV === 'production';
// The release-preflight command must be able to report every missing setting
// in one run. Runtime processes remain fail-closed and still reject a missing
// database URL before opening a listener.
const preflightDiagnostics = process.env.PREFLIGHT_DIAGNOSTICS === 'true';
const fieldLivenessMinimumSeconds = isProduction ? 30 : 1;
const fieldLivenessReconcileMinimumSeconds = isProduction ? 10 : 1;

export const config = {
  port: Number(process.env.PORT || 8080),
  isProduction,
  accessTokenTtlMinutes: Number(process.env.ACCESS_TOKEN_TTL_MINUTES || 30),
  refreshTokenTtlDays: Number(process.env.REFRESH_TOKEN_TTL_DAYS || 30),
  mfaEncryptionKey: process.env.MFA_ENCRYPTION_KEY || '',
  verificationCodePepper: process.env.VERIFICATION_CODE_PEPPER || (isProduction ? '' : 'local-development-verification-code-pepper'),
  requireMfaForPrivileged: process.env.REQUIRE_MFA_FOR_PRIVILEGED === 'true' || isProduction,
  auditLogSigningKey: process.env.AUDIT_LOG_SIGNING_KEY || '',
  maxSessionsPerUser: Math.max(1, Number(process.env.MAX_SESSIONS_PER_USER || 5) || 5),
  allowPublicRegistration: process.env.ALLOW_PUBLIC_REGISTRATION === 'true' || (process.env.ALLOW_PUBLIC_REGISTRATION === undefined && !isProduction),
  /** HTTPS webhook owned by the selected SMS provider or notification gateway. */
  smsWebhookUrl: process.env.SMS_WEBHOOK_URL || '',
  smsWebhookAuthorization: process.env.SMS_WEBHOOK_AUTHORIZATION || '',
  wechatAppId: process.env.WECHAT_APP_ID || '',
  wechatAppSecret: process.env.WECHAT_APP_SECRET || '',
  wechatRedirectUri: process.env.WECHAT_REDIRECT_URI || '',
  oauthStateTtlSeconds: Math.min(600, Math.max(60, Number(process.env.OAUTH_STATE_TTL_SECONDS || 300) || 300)),
  corsOrigin: process.env.CORS_ORIGIN || (isProduction ? '' : '*'),
  trustProxy: process.env.TRUST_PROXY === 'true',
  requireHealthConsent: process.env.REQUIRE_HEALTH_CONSENT === 'true' || (process.env.REQUIRE_HEALTH_CONSENT === undefined && isProduction),
  healthRetentionDays: Math.max(30, Number(process.env.HEALTH_DATA_RETENTION_DAYS || 2555) || 2555),
  metricsToken: process.env.METRICS_TOKEN || '',
  storageDriver: process.env.FILE_STORAGE_DRIVER || 'local',
  storageRoot: process.env.STORAGE_ROOT || '',
  storageEndpoint: process.env.S3_STORAGE_ENDPOINT || '',
  storageBucket: process.env.S3_BUCKET || '',
  storageAccessKey: process.env.S3_ACCESS_KEY || '',
  storageSecretKey: process.env.S3_SECRET_KEY || '',
  storageRegion: process.env.S3_REGION || 'auto',
  jobWorkerEnabled: process.env.JOB_WORKER_ENABLED !== 'false',
  jobWorkerMode: process.env.JOB_WORKER_MODE || (process.env.JOB_WORKER_ENABLED === 'false' ? 'external' : 'embedded'),
  jobWorkerIntervalMs: Math.max(250, Number(process.env.JOB_WORKER_INTERVAL_MS || 1000) || 1000),
  jobWorkerConcurrency: Math.min(20, Math.max(1, Number(process.env.JOB_WORKER_CONCURRENCY || 4) || 4)),
  jobWorkerShutdownTimeoutMs: Math.min(25_000, Math.max(1_000, Number(process.env.JOB_WORKER_SHUTDOWN_TIMEOUT_MS || 25_000) || 25_000)),
  fieldDeviceKeyTtlDays: Math.min(365, Math.max(1, Number(process.env.FIELD_DEVICE_KEY_TTL_DAYS || 90) || 90)),
  fieldDeviceSigningEncryptionKey: process.env.FIELD_DEVICE_SIGNING_ENCRYPTION_KEY || (isProduction ? '' : 'local-development-field-device-signing-encryption-key'),
  fieldDeviceSignedRequestsRequired: process.env.FIELD_DEVICE_SIGNED_REQUESTS_REQUIRED === 'true' || isProduction,
  fieldDeviceSignatureMaxAgeSeconds: Math.min(600, Math.max(30, Number(process.env.FIELD_DEVICE_SIGNATURE_MAX_AGE_SECONDS || 300) || 300)),
  fieldDeviceOfflineAfterSeconds: Math.min(3600, Math.max(fieldLivenessMinimumSeconds, Number(process.env.FIELD_DEVICE_OFFLINE_AFTER_SECONDS || 90) || 90)),
  fieldLivenessReconcileIntervalSeconds: Math.min(600, Math.max(fieldLivenessReconcileMinimumSeconds, Number(process.env.FIELD_LIVENESS_RECONCILE_INTERVAL_SECONDS || 30) || 30)),
  fieldEvidenceVideoRetentionDays: Math.min(3650, Math.max(30, Number(process.env.FIELD_EVIDENCE_VIDEO_RETENTION_DAYS || 180) || 180)),
  fieldEvidenceDerivedRetentionDays: Math.min(3650, Math.max(90, Number(process.env.FIELD_EVIDENCE_DERIVED_RETENTION_DAYS || 1095) || 1095)),
  fieldEvidenceOrphanRetentionHours: Math.min(168, Math.max(1, Number(process.env.FIELD_EVIDENCE_ORPHAN_RETENTION_HOURS || 24) || 24)),
  workerHeartbeatIntervalSeconds: Math.min(60, Math.max(5, Number(process.env.WORKER_HEARTBEAT_INTERVAL_SECONDS || 15) || 15)),
  workerHeartbeatMaxAgeSeconds: Math.min(300, Math.max(15, Number(process.env.WORKER_HEARTBEAT_MAX_AGE_SECONDS || 60) || 60)),
  backupEnabled: process.env.BACKUP_ENABLED === 'true' || (process.env.BACKUP_ENABLED === undefined && isProduction),
  backupIntervalSeconds: Math.min(604800, Math.max(3600, Number(process.env.BACKUP_INTERVAL_SECONDS || 86400) || 86400)),
  backupHeartbeatIntervalSeconds: Math.min(60, Math.max(5, Number(process.env.BACKUP_HEARTBEAT_INTERVAL_SECONDS || 15) || 15)),
  backupHeartbeatMaxAgeSeconds: Math.min(300, Math.max(15, Number(process.env.BACKUP_HEARTBEAT_MAX_AGE_SECONDS || 60) || 60))
};

export const poolOptions = {
  connectionString: process.env.DATABASE_URL,
  max: Number(process.env.DB_POOL_MAX || 20),
  idleTimeoutMillis: Number(process.env.DB_IDLE_TIMEOUT_MS || 30_000),
  connectionTimeoutMillis: Number(process.env.DB_CONNECTION_TIMEOUT_MS || 5_000),
  statement_timeout: Number(process.env.DB_STATEMENT_TIMEOUT_MS || 15_000)
};

if (!poolOptions.connectionString && !preflightDiagnostics) throw new Error('DATABASE_URL is required');

// API-only requirements intentionally live behind an explicit assertion. Workers
// and the backup executor import the common timing/database configuration but
// must not be given browser-facing or device-signing secrets unnecessarily.
export const serverRuntimeConfigErrors = () => {
  if (!isProduction) return [];
  const errors = [];
  if (!poolOptions.connectionString) errors.push('DATABASE_URL');
  if (!config.corsOrigin || config.corsOrigin === '*') errors.push('明确的 CORS_ORIGIN');
  if (config.metricsToken.length < 24) errors.push('至少 24 位 METRICS_TOKEN');
  if (!config.trustProxy) errors.push('TRUST_PROXY=true');
  if (config.mfaEncryptionKey.length < 32) errors.push('至少 32 位 MFA_ENCRYPTION_KEY');
  if (config.verificationCodePepper.length < 32) errors.push('至少 32 位 VERIFICATION_CODE_PEPPER');
  if (config.auditLogSigningKey.length < 32) errors.push('至少 32 位 AUDIT_LOG_SIGNING_KEY');
  if (!config.fieldDeviceSignedRequestsRequired) errors.push('FIELD_DEVICE_SIGNED_REQUESTS_REQUIRED=true');
  if (config.fieldDeviceSigningEncryptionKey.length < 32) errors.push('至少 32 位 FIELD_DEVICE_SIGNING_ENCRYPTION_KEY');
  const wechatConfig = [config.wechatAppId, config.wechatAppSecret, config.wechatRedirectUri];
  if (wechatConfig.some(Boolean) && (!config.wechatAppId || !config.wechatAppSecret || !config.wechatRedirectUri || !/^https:\/\//.test(config.wechatRedirectUri))) {
    errors.push('完整的 HTTPS 微信授权配置（WECHAT_APP_ID、WECHAT_APP_SECRET、WECHAT_REDIRECT_URI）');
  }
  return errors;
};

export const assertServerRuntimeConfig = () => {
  const errors = serverRuntimeConfigErrors();
  if (errors.length > 0) throw new Error(`生产环境缺少或无效配置：${errors.join('；')}`);
};
