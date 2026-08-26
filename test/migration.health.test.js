import assert from 'node:assert/strict';
import test from 'node:test';
import { evaluateMigrationVersions, expectedMigrations, expectedMigrationVersions, readMigrationHealth } from '../src/migrationHealth.js';

test('migration health requires every migration shipped with the API image', () => {
  const healthy = evaluateMigrationVersions(expectedMigrations);
  assert.equal(healthy.healthy, true);
  assert.equal(healthy.missing.length, 0);

  const missing = evaluateMigrationVersions(expectedMigrations.slice(0, -1));
  assert.equal(missing.healthy, false);
  assert.deepEqual(missing.missing, [expectedMigrationVersions.at(-1)]);
});

test('migration health fails closed when an applied migration checksum differs', () => {
  const rows = expectedMigrations.map((migration) => ({ ...migration }));
  rows[0].checksumSha256 = '0'.repeat(64);
  const health = evaluateMigrationVersions(rows);
  assert.equal(health.healthy, false);
  assert.deepEqual(health.checksumMismatches, [expectedMigrationVersions[0]]);
});

test('migration health fails closed when migration metadata cannot be read', async () => {
  const health = await readMigrationHealth(async () => { throw new Error('relation schema_migrations does not exist'); });
  assert.equal(health.healthy, false);
  assert.equal(health.appliedCount, 0);
  assert.equal(health.missing.length, expectedMigrationVersions.length);
});
