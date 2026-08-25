import fs from 'node:fs/promises';
import { spawn } from 'node:child_process';

const backupFile = process.env.BACKUP_FILE;
if (!backupFile) throw new Error('BACKUP_FILE is required');
await fs.access(backupFile);

await new Promise((resolve, reject) => {
  const child = spawn(process.env.PG_RESTORE_BIN || 'pg_restore', ['--list', backupFile], { stdio: ['ignore', 'pipe', 'inherit'] });
  let output = '';
  child.stdout.on('data', (chunk) => { output += chunk; });
  child.once('error', reject);
  child.once('exit', (code) => {
    if (code !== 0) return reject(new Error('pg_restore --list exited with code ' + code));
    if (!output.includes('TABLE DATA') && !output.includes('TABLE')) return reject(new Error('backup archive does not contain PostgreSQL table entries'));
    resolve();
  });
});

console.log(JSON.stringify({ verified: true, backupFile }));
