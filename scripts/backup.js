import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createStorage } from '../src/storage.js';
import { archiveBackup } from '../src/backupArchive.js';
import { postgresCliEnv } from '../src/postgresCli.js';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');
const outputDir = path.resolve(process.env.BACKUP_DIR || './backups');
await fs.mkdir(outputDir, { recursive: true });
const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
const target = path.join(outputDir, `xiangshang-${timestamp}.dump`);

await new Promise((resolve, reject) => {
  const child = spawn(process.env.PG_DUMP_BIN || 'pg_dump', ['--no-password', '--format=custom', '--no-owner', '--file', target], { stdio: 'inherit', env: postgresCliEnv(databaseUrl) });
  child.once('error', reject);
  child.once('exit', (code) => code === 0 ? resolve() : reject(new Error(`pg_dump exited with code ${code}`)));
});
const retentionDays = Math.max(1, Number(process.env.BACKUP_RETENTION_DAYS || 30) || 30);
const entries = await fs.readdir(outputDir, { withFileTypes: true });
const cutoff = Date.now() - retentionDays * 86_400_000;
for (const entry of entries) {
  if (!entry.isFile() || !entry.name.endsWith('.dump')) continue;
  const candidate = path.join(outputDir, entry.name);
  const stat = await fs.stat(candidate);
  if (stat.mtimeMs < cutoff) await fs.rm(candidate, { force: true });
}
let archive = null;
if (process.env.BACKUP_ARCHIVE_ENABLED === 'true') {
  const storage = createStorage({
    storageDriver: 's3',
    storageEndpoint: process.env.BACKUP_S3_ENDPOINT,
    storageBucket: process.env.BACKUP_S3_BUCKET,
    storageAccessKey: process.env.BACKUP_S3_ACCESS_KEY,
    storageSecretKey: process.env.BACKUP_S3_SECRET_KEY,
    storageRegion: process.env.BACKUP_S3_REGION || 'auto'
  });
  archive = await archiveBackup({ storage, filePath: target, prefix: process.env.BACKUP_ARCHIVE_PREFIX || 'xiangshang/database' });
}
console.log(JSON.stringify({ backup: target, archive, createdAt: new Date().toISOString() }));
