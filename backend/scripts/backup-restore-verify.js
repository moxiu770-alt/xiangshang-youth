import fs from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { Pool } from 'pg';
import { postgresCliEnv, postgresDatabaseName } from '../src/postgresCli.js';

const backupFile = process.env.BACKUP_FILE;
const sourceDatabaseUrl = process.env.DATABASE_URL;
const restoreDatabaseUrl = process.env.RESTORE_DATABASE_URL;
const restoreSchema = process.env.RESTORE_SCHEMA || 'public';
const expectData = process.env.RESTORE_EXPECT_DATA === 'true';

if (!backupFile) throw new Error('BACKUP_FILE is required');
if (!sourceDatabaseUrl || !restoreDatabaseUrl) throw new Error('DATABASE_URL and RESTORE_DATABASE_URL are required');
if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(restoreSchema)) throw new Error('RESTORE_SCHEMA must be a PostgreSQL identifier');
await fs.access(backupFile);

const source = new URL(sourceDatabaseUrl);
const target = new URL(restoreDatabaseUrl);
if (source.hostname === target.hostname && source.port === target.port && source.pathname === target.pathname) {
  throw new Error('RESTORE_DATABASE_URL must point to a dedicated database, never the source database');
}
const targetDatabase = postgresDatabaseName(restoreDatabaseUrl);

await new Promise((resolve, reject) => {
  const child = spawn(process.env.PG_RESTORE_BIN || 'pg_restore', [
    '--no-password', '--dbname', targetDatabase, '--clean', '--if-exists', '--no-owner', '--exit-on-error', backupFile
  ], { stdio: 'inherit', env: postgresCliEnv(restoreDatabaseUrl) });
  child.once('error', reject);
  child.once('exit', (code) => code === 0 ? resolve() : reject(new Error(`pg_restore exited with code ${code}`)));
});

const quoteIdentifier = (value) => `"${value.replaceAll('"', '""')}"`;
const schema = quoteIdentifier(restoreSchema);
const pool = new Pool({ connectionString: restoreDatabaseUrl });
try {
  const requiredTables = ['schema_migrations', 'users', 'students', 'assessment_tasks', 'test_sessions'];
  for (const table of requiredTables) {
    const relation = await pool.query('SELECT to_regclass($1) AS relation', [`${restoreSchema}.${table}`]);
    if (!relation.rows[0]?.relation) throw new Error(`restored backup is missing ${restoreSchema}.${table}`);
  }
  const migrations = await pool.query(`SELECT COUNT(*)::int AS count FROM ${schema}.schema_migrations`);
  if (Number(migrations.rows[0].count) < 1) throw new Error('restored backup has no migration history');
  if (expectData) {
    const users = await pool.query(`SELECT COUNT(*)::int AS count FROM ${schema}.users`);
    if (Number(users.rows[0].count) < 1) throw new Error('restored backup does not contain expected seeded data');
  }
  console.log(JSON.stringify({ restored: true, backupFile, restoreSchema, migrationCount: Number(migrations.rows[0].count) }));
} finally {
  await pool.end();
}
