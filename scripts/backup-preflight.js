import { config } from '../src/config.js';
import { createStorage } from '../src/storage.js';
import { backupArchivePrefix } from '../src/backupArchive.js';

const fail = (message) => { throw new Error(`备份预检失败：${message}`); };

if (!config.backupEnabled) fail('BACKUP_ENABLED 必须为 true');
if (process.env.BACKUP_ARCHIVE_ENABLED !== 'true') fail('BACKUP_ARCHIVE_ENABLED 必须为 true，生产备份不得只留在容器本地');
if (config.backupHeartbeatMaxAgeSeconds < config.backupHeartbeatIntervalSeconds * 2) fail('BACKUP_HEARTBEAT_MAX_AGE_SECONDS 至少应为 BACKUP_HEARTBEAT_INTERVAL_SECONDS 的两倍');
try {
  const endpoint = new URL(String(process.env.BACKUP_S3_ENDPOINT || ''));
  if (endpoint.protocol !== 'https:') fail('BACKUP_S3_ENDPOINT 必须使用 HTTPS');
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
  if (String(error.message || '').startsWith('备份预检失败：')) throw error;
  fail(`归档存储配置无效：${error.message}`);
}
console.log(JSON.stringify({ ready: true, intervalSeconds: config.backupIntervalSeconds, heartbeatIntervalSeconds: config.backupHeartbeatIntervalSeconds }));
