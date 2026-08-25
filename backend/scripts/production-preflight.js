import { assertServerRuntimeConfig, config } from '../src/config.js';
import { createStorage } from '../src/storage.js';
import { backupArchivePrefix } from '../src/backupArchive.js';

const publicHost = String(process.env.PUBLIC_HOST || '').trim().toLowerCase();
const acmeEmail = String(process.env.ACME_EMAIL || '').trim();
const fail = (message) => { throw new Error(`生产预检失败：${message}`); };

assertServerRuntimeConfig();

if (!/^(?=.{1,253}$)(?!-)[a-z0-9-]+(?:\.[a-z0-9-]+)+$/i.test(publicHost)) fail('PUBLIC_HOST 必须是可公开解析的域名，不能包含协议、端口或路径');
if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(acmeEmail)) fail('ACME_EMAIL 必须是用于证书到期通知的有效邮箱');
if (process.env.ALLOW_PUBLIC_REGISTRATION === 'true') fail('生产环境不得开启 ALLOW_PUBLIC_REGISTRATION');
if (config.mfaEncryptionKey.length < 32) fail('MFA_ENCRYPTION_KEY 至少应为 32 个随机字符，用于加密双重验证密钥');
if (config.auditLogSigningKey.length < 32) fail('AUDIT_LOG_SIGNING_KEY 至少应为 32 个随机字符，用于签名审计哈希链');
if (config.workerHeartbeatMaxAgeSeconds < config.workerHeartbeatIntervalSeconds * 2) fail('WORKER_HEARTBEAT_MAX_AGE_SECONDS 至少应为 WORKER_HEARTBEAT_INTERVAL_SECONDS 的两倍');
if (!config.fieldDeviceSignedRequestsRequired) fail('生产环境必须启用 FIELD_DEVICE_SIGNED_REQUESTS_REQUIRED=true，禁止每次请求传递设备密钥');
if (config.fieldDeviceSigningEncryptionKey.length < 32) fail('FIELD_DEVICE_SIGNING_ENCRYPTION_KEY 至少应为 32 个随机字符，用于加密设备签名材料');
if (!config.backupEnabled) fail('生产环境必须启用 BACKUP_ENABLED=true');
if (config.backupHeartbeatMaxAgeSeconds < config.backupHeartbeatIntervalSeconds * 2) fail('BACKUP_HEARTBEAT_MAX_AGE_SECONDS 至少应为 BACKUP_HEARTBEAT_INTERVAL_SECONDS 的两倍');
if (config.storageDriver !== 's3') fail('生产环境必须使用 FILE_STORAGE_DRIVER=s3，不能使用本地证据存储');
try {
  const endpoint = new URL(config.storageEndpoint);
  if (endpoint.protocol !== 'https:') fail('S3_STORAGE_ENDPOINT 必须使用 HTTPS');
} catch (error) {
  if (String(error.message || '').startsWith('生产预检失败：')) throw error;
  fail('S3_STORAGE_ENDPOINT 必须是有效的 HTTPS 地址');
}
try {
  const origin = new URL(config.corsOrigin);
  if (origin.protocol !== 'https:' || origin.hostname.toLowerCase() !== publicHost) fail('CORS_ORIGIN 必须是与 PUBLIC_HOST 相同的 HTTPS Origin');
} catch (error) {
  if (String(error.message || '').startsWith('生产预检失败：')) throw error;
  fail('CORS_ORIGIN 必须是有效的 HTTPS Origin');
}

// createStorage performs all S3 credential and bucket checks without network I/O.
createStorage(config);
let backupArchiveEnabled = false;
if (process.env.BACKUP_ARCHIVE_ENABLED === 'true') {
  backupArchiveEnabled = true;
  try {
    const endpoint = new URL(String(process.env.BACKUP_S3_ENDPOINT || ''));
    if (endpoint.protocol !== 'https:') fail('BACKUP_S3_ENDPOINT 必须使用 HTTPS');
  } catch (error) {
    if (String(error.message || '').startsWith('生产预检失败：')) throw error;
    fail('BACKUP_S3_ENDPOINT 必须是有效的 HTTPS 地址');
  }
  try {
    createStorage({
      storageDriver: 's3',
      storageEndpoint: process.env.BACKUP_S3_ENDPOINT,
      storageBucket: process.env.BACKUP_S3_BUCKET,
      storageAccessKey: process.env.BACKUP_S3_ACCESS_KEY,
      storageSecretKey: process.env.BACKUP_S3_SECRET_KEY,
      storageRegion: process.env.BACKUP_S3_REGION || 'auto'
    });
    backupArchivePrefix(process.env.BACKUP_ARCHIVE_PREFIX || 'xiangshang/database');
  } catch (error) {
    if (String(error.message || '').startsWith('生产预检失败：')) throw error;
    fail(`数据库备份归档配置无效：${error.message}`);
  }
}
if (!backupArchiveEnabled) fail('生产环境必须启用 BACKUP_ARCHIVE_ENABLED=true，将数据库备份归档到独立存储');
console.log(JSON.stringify({ ready: true, publicHost, storageDriver: config.storageDriver, backupArchiveEnabled, trustedProxy: config.trustProxy }));
