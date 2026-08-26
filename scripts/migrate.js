import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';
import { Pool } from 'pg';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const root = path.dirname(fileURLToPath(import.meta.url));
const schema = await fs.readFile(new URL('../db/schema.sql', import.meta.url), 'utf8');
const migrationDir = path.join(root, '../db/migrations');
const lockClient = await pool.connect();

try {
  // A Pool can hand consecutive queries to different connections.  For an
  // isolated integration schema that allowed the bootstrap schema to resolve
  // some tables in the configured schema and some in public.  Run the whole
  // bootstrap/migration transaction stream on the locked connection and pin
  // its already-authoritative current schema explicitly.
  const schemaResult = await lockClient.query('SELECT current_schema() AS name');
  const schemaName = String(schemaResult.rows[0]?.name || 'public');
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(schemaName)) throw new Error(`Unsafe database schema name: ${schemaName}`);
  await lockClient.query(`SET search_path TO ${schemaName}`);
  await lockClient.query("SELECT pg_advisory_lock(hashtext('xiangshang:migrations'))");
  await lockClient.query(schema);
  await lockClient.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    checksum_sha256 TEXT,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`);
  await lockClient.query('ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS checksum_sha256 TEXT');
  const files = (await fs.readdir(migrationDir)).filter((name) => /^\d+_.+\.sql$/.test(name)).sort();
  for (const file of files) {
    const version = file.replace(/\.sql$/, '');
    const source = await fs.readFile(path.join(migrationDir, file), 'utf8');
    const checksum = crypto.createHash('sha256').update(source).digest('hex');
    const existing = await lockClient.query('SELECT checksum_sha256 FROM schema_migrations WHERE version=$1', [version]);
    if (existing.rowCount) {
      const appliedChecksum = existing.rows[0].checksum_sha256;
      if (appliedChecksum && appliedChecksum !== checksum) throw new Error(`迁移校验和不匹配：${version} 已被修改；请新增迁移而不是改写已应用文件`);
      if (!appliedChecksum) {
        await lockClient.query('UPDATE schema_migrations SET checksum_sha256=$2 WHERE version=$1', [version, checksum]);
        console.log(`Recorded checksum for legacy migration ${version}`);
      }
      continue;
    }
    try {
      await lockClient.query('BEGIN');
      await lockClient.query(source);
      await lockClient.query('INSERT INTO schema_migrations(version,checksum_sha256) VALUES($1,$2)', [version, checksum]);
      await lockClient.query('COMMIT');
      console.log(`Applied migration ${version}`);
    } catch (error) {
      await lockClient.query('ROLLBACK');
      throw error;
    }
  }
  console.log('Database migrations applied. Seed data is a separate operation: npm run seed');
} finally {
  await lockClient.query("SELECT pg_advisory_unlock(hashtext('xiangshang:migrations'))").catch(() => {});
  lockClient.release();
  await pool.end();
}
