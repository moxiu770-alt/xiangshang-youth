import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';

const migrationDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../db/migrations');

// The application image contains the migrations it is compatible with. A
// database that is reachable but behind that image must never receive traffic.
const migrationFiles = (await fs.readdir(migrationDirectory))
  .filter((name) => /^\d+_.+\.sql$/.test(name))
  .sort();

export const expectedMigrations = Object.freeze(await Promise.all(migrationFiles.map(async (file) => ({
  version: file.replace(/\.sql$/, ''),
  checksumSha256: crypto.createHash('sha256').update(await fs.readFile(path.join(migrationDirectory, file))).digest('hex')
}))));

export const expectedMigrationVersions = Object.freeze(expectedMigrations.map((migration) => migration.version));

export const evaluateMigrationVersions = (rows = []) => {
  const applied = new Map(rows.map((row) => [String(row.version), row.checksumSha256 || row.checksum_sha256 || null]));
  const missing = expectedMigrations.filter((migration) => !applied.has(migration.version)).map((migration) => migration.version);
  const checksumMismatches = expectedMigrations
    .filter((migration) => applied.has(migration.version) && applied.get(migration.version) !== migration.checksumSha256)
    .map((migration) => migration.version);
  return {
    healthy: missing.length === 0 && checksumMismatches.length === 0,
    expectedCount: expectedMigrationVersions.length,
    appliedCount: applied.size,
    missing,
    checksumMismatches
  };
};

export const readMigrationHealth = async (query) => {
  try {
    const result = await query('SELECT version,checksum_sha256 AS "checksumSha256" FROM schema_migrations');
    return evaluateMigrationVersions(result.rows);
  } catch (error) {
    return {
      healthy: false,
      expectedCount: expectedMigrationVersions.length,
      appliedCount: 0,
      missing: expectedMigrationVersions,
      checksumMismatches: [],
      error: error.message
    };
  }
};
