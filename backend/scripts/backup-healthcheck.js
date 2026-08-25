import { config } from '../src/config.js';
import { pool } from '../src/db.js';

try {
  const result = await pool.query(`SELECT EXTRACT(EPOCH FROM now()-MAX(last_seen_at))::int AS "ageSeconds"
    FROM runtime_heartbeats WHERE component='backup'`);
  const ageSeconds = result.rows[0]?.ageSeconds;
  if (ageSeconds == null || Number(ageSeconds) > config.backupHeartbeatMaxAgeSeconds) throw new Error(`backup heartbeat is stale (${ageSeconds ?? 'missing'} seconds)`);
  console.log(JSON.stringify({ healthy: true, ageSeconds: Number(ageSeconds) }));
} finally {
  await pool.end();
}
