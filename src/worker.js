import crypto from 'node:crypto';
import { config } from './config.js';
import { pool, query } from './db.js';
import { jobWorkerStatus, startJobWorker, stopJobWorker } from './jobs.js';
import { logger } from './observability.js';

const instanceId = process.env.WORKER_INSTANCE_ID || crypto.randomUUID();
const heartbeat = async () => {
  await query(`INSERT INTO runtime_heartbeats(component,instance_id,metadata_json,last_seen_at)
    VALUES('worker',$1,$2,now()) ON CONFLICT(component,instance_id)
    DO UPDATE SET metadata_json=EXCLUDED.metadata_json,last_seen_at=now()`, [instanceId, { pid: process.pid, intervalMs: config.jobWorkerIntervalMs, concurrency: config.jobWorkerConcurrency }]);
};
await heartbeat();
const heartbeatTimer = setInterval(() => void heartbeat().catch((error) => logger.error('worker.heartbeat_failed', { error: error.message })), config.workerHeartbeatIntervalSeconds * 1000);
startJobWorker({ enabled: config.jobWorkerEnabled, intervalMs: config.jobWorkerIntervalMs, concurrency: config.jobWorkerConcurrency, keepProcessAlive: true });
logger.info('worker.started', { instanceId, intervalMs: config.jobWorkerIntervalMs, concurrency: config.jobWorkerConcurrency, heartbeatIntervalSeconds: config.workerHeartbeatIntervalSeconds, fieldLivenessIntervalSeconds: config.fieldLivenessReconcileIntervalSeconds });

let stopping = false;
const shutdown = async (signal) => {
  if (stopping) return;
  stopping = true;
  logger.info('worker.shutdown_started', { signal });
  clearInterval(heartbeatTimer);
  const drained = await stopJobWorker({ drainMs: config.jobWorkerShutdownTimeoutMs });
  if (!drained) logger.warn('worker.shutdown_drain_timeout', { active: jobWorkerStatus().active, timeoutMs: config.jobWorkerShutdownTimeoutMs });
  await pool.end();
  logger.info('worker.shutdown_finished');
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('uncaughtException', (error) => { logger.error('worker.uncaught_exception', { error: error.stack || error.message }); void shutdown('uncaughtException'); });
process.on('unhandledRejection', (error) => logger.error('worker.unhandled_rejection', { error: error?.stack || String(error) }));
