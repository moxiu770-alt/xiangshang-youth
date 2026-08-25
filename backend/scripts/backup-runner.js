import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { config } from '../src/config.js';
import { pool, query } from '../src/db.js';
import { logger } from '../src/observability.js';

const instanceId = process.env.BACKUP_INSTANCE_ID || crypto.randomUUID();
let stopping = false;
let running = null;
let state = { status: 'starting', lastSuccessAt: null, lastError: null, lastDurationMs: null };

const heartbeat = async () => {
  await query(`INSERT INTO runtime_heartbeats(component,instance_id,metadata_json,last_seen_at)
    VALUES('backup',$1,$2,now()) ON CONFLICT(component,instance_id)
    DO UPDATE SET metadata_json=EXCLUDED.metadata_json,last_seen_at=now()`, [instanceId, state]);
};

const executeBackup = () => new Promise((resolve, reject) => {
  const child = spawn(process.execPath, ['scripts/backup.js'], { stdio: ['ignore', 'pipe', 'pipe'], env: process.env });
  let output = '';
  let errors = '';
  child.stdout.on('data', (chunk) => { output += chunk; process.stdout.write(chunk); });
  child.stderr.on('data', (chunk) => { errors += chunk; process.stderr.write(chunk); });
  child.once('error', reject);
  child.once('exit', (code) => {
    if (code !== 0) return reject(new Error(`backup exited ${code}: ${errors.slice(-1000)}`));
    const line = output.trim().split('\n').at(-1);
    try { resolve(JSON.parse(line)); } catch { resolve({ output: line }); }
  });
});

const run = async () => {
  if (stopping || running) return running;
  running = (async () => {
    const startedAt = Date.now();
    state = { ...state, status: 'running', lastError: null };
    await heartbeat();
    try {
      const result = await executeBackup();
      state = { status: 'ready', lastSuccessAt: new Date().toISOString(), lastError: null, lastDurationMs: Date.now() - startedAt, archive: result.archive || null };
      logger.info('backup.completed', { instanceId, durationMs: state.lastDurationMs, archive: result.archive?.objectKey || null });
    } catch (error) {
      state = { ...state, status: 'failed', lastError: error.message.slice(0, 1000), lastDurationMs: Date.now() - startedAt };
      logger.error('backup.failed', { instanceId, durationMs: state.lastDurationMs, error: error.message });
    } finally {
      await heartbeat().catch((error) => logger.error('backup.heartbeat_failed', { error: error.message }));
      running = null;
    }
  })();
  return running;
};

await heartbeat();
const heartbeatTimer = setInterval(() => void heartbeat().catch((error) => logger.error('backup.heartbeat_failed', { error: error.message })), config.backupHeartbeatIntervalSeconds * 1000);
const scheduleTimer = setInterval(() => void run(), config.backupIntervalSeconds * 1000);
void run();
logger.info('backup.started', { instanceId, intervalSeconds: config.backupIntervalSeconds, heartbeatIntervalSeconds: config.backupHeartbeatIntervalSeconds });

const shutdown = async (signal) => {
  if (stopping) return;
  stopping = true;
  logger.info('backup.shutdown_started', { signal, running: Boolean(running) });
  clearInterval(heartbeatTimer);
  clearInterval(scheduleTimer);
  await running?.catch(() => {});
  await pool.end();
  logger.info('backup.shutdown_finished');
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
