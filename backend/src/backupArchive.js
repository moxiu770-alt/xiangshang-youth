import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

export function backupArchivePrefix(value = 'xiangshang/database') {
  const prefix = String(value || '').replace(/^\/+|\/+$/g, '');
  if (!prefix || prefix.split('/').some((part) => !part || part === '.' || part === '..' || !/^[A-Za-z0-9._-]+$/.test(part))) {
    throw new Error('BACKUP_ARCHIVE_PREFIX 不合法');
  }
  return prefix;
}

export async function archiveBackup({ storage, filePath, prefix, createdAt = new Date().toISOString() }) {
  const bytes = await fs.readFile(filePath);
  if (!bytes.length) throw new Error('备份文件为空，拒绝归档');
  const fileName = path.basename(filePath);
  if (!/^[A-Za-z0-9._-]+\.dump$/.test(fileName)) throw new Error('备份文件名不合法');
  const objectPrefix = backupArchivePrefix(prefix);
  const objectKey = `${objectPrefix}/${fileName}`;
  const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const manifest = { schema: 'xiangshang-backup/v1', createdAt, fileName, objectKey, bytes: bytes.length, sha256 };
  await storage.put(objectKey, bytes, 'application/octet-stream');
  await storage.put(`${objectKey}.manifest.json`, Buffer.from(JSON.stringify(manifest)), 'application/json');
  return manifest;
}
