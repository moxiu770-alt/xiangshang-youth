import { config, serverRuntimeConfigErrors } from '../src/config.js';
import { createStorage } from '../src/storage.js';
import { backupArchivePrefix } from '../src/backupArchive.js';

const errors = [...serverRuntimeConfigErrors()];
const publicHost = String(process.env.PUBLIC_HOST || '').trim().toLowerCase();
const acmeEmail = String(process.env.ACME_EMAIL || '').trim();
const add = (condition, message) => { if (condition) errors.push(message); };
const validateUrl = (value, label) => {
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:') errors.push(`${label} 必须使用 HTTPS`);
    return url;
  } catch { errors.push(`${label} 必须是有效的 HTTPS 地址`); return null; }
};

add(!/^(?=.{1,253}$)(?!-)[a-z0-9-]+(?:\.[a-z0-9-]+)+$/i.test(publicHost), 'PUBLIC_HOST 必须是可公开解析的域名，不能包含协议、端口或路径');
add(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(acmeEmail), 'ACME_EMAIL 必须是用于证书到期通知的有效邮箱');
add(process.env.ALLOW_PUBLIC_REGISTRATION === 'true', '生产环境不得开启 ALLOW_PUBLIC_REGISTRATION');
add(config.workerHeartbeatMaxAgeSeconds < config.workerHeartbeatIntervalSeconds * 2, 'WORKER_HEARTBEAT_MAX_AGE_SECONDS 至少应为 WORKER_HEARTBEAT_INTERVAL_SECONDS 的两倍');
add(!config.backupEnabled, '生产环境必须启用 BACKUP_ENABLED=true');
add(config.backupHeartbeatMaxAgeSeconds < config.backupHeartbeatIntervalSeconds * 2, 'BACKUP_HEARTBEAT_MAX_AGE_SECONDS 至少应为 BACKUP_HEARTBEAT_INTERVAL_SECONDS 的两倍');
add(config.storageDriver !== 's3', '生产环境必须使用 FILE_STORAGE_DRIVER=s3，不能使用本地证据存储');
const storageEndpoint = validateUrl(config.storageEndpoint, 'S3_STORAGE_ENDPOINT');
const origin = validateUrl(config.corsOrigin, 'CORS_ORIGIN');
if (origin && publicHost && origin.hostname.toLowerCase() !== publicHost) errors.push('CORS_ORIGIN 必须是与 PUBLIC_HOST 相同的 HTTPS Origin');
if (config.storageDriver === 's3' && storageEndpoint) {
  try { createStorage(config); } catch (error) { errors.push(`对象存储配置无效：${error.message}`); }
}

const backupArchiveEnabled = process.env.BACKUP_ARCHIVE_ENABLED === 'true';
if (!backupArchiveEnabled) {
  errors.push('生产环境必须启用 BACKUP_ARCHIVE_ENABLED=true，将数据库备份归档到独立存储');
} else {
  const backupEndpoint = validateUrl(String(process.env.BACKUP_S3_ENDPOINT || ''), 'BACKUP_S3_ENDPOINT');
  if (backupEndpoint) {
    try {
      createStorage({ storageDriver: 's3', storageEndpoint: process.env.BACKUP_S3_ENDPOINT, storageBucket: process.env.BACKUP_S3_BUCKET, storageAccessKey: process.env.BACKUP_S3_ACCESS_KEY, storageSecretKey: process.env.BACKUP_S3_SECRET_KEY, storageRegion: process.env.BACKUP_S3_REGION || 'auto' });
      backupArchivePrefix(process.env.BACKUP_ARCHIVE_PREFIX || 'xiangshang/database');
    } catch (error) { errors.push(`数据库备份归档配置无效：${error.message}`); }
  }
}

if (errors.length > 0) {
  console.error(JSON.stringify({ ready: false, blockingConfiguration: [...new Set(errors)] }, null, 2));
  process.exitCode = 1;
} else {
  console.log(JSON.stringify({ ready: true, publicHost, storageDriver: config.storageDriver, backupArchiveEnabled, trustedProxy: config.trustProxy }));
}
