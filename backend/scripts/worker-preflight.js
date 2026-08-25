import { config } from '../src/config.js';

const fail = (message) => { throw new Error(`Worker 生产预检失败：${message}`); };

if (!config.isProduction) fail('NODE_ENV 必须为 production');
if (config.jobWorkerMode !== 'external' && config.jobWorkerMode !== 'worker') fail('JOB_WORKER_MODE 必须为 external 或 worker');
if (!config.jobWorkerEnabled) fail('JOB_WORKER_ENABLED 不能为 false');
if (config.auditLogSigningKey.length < 32) fail('AUDIT_LOG_SIGNING_KEY 至少应为 32 个随机字符，后台任务不得绕过审计哈希链');
if (config.workerHeartbeatMaxAgeSeconds < config.workerHeartbeatIntervalSeconds * 2) fail('WORKER_HEARTBEAT_MAX_AGE_SECONDS 至少应为 WORKER_HEARTBEAT_INTERVAL_SECONDS 的两倍');

console.log(JSON.stringify({ ready: true, mode: config.jobWorkerMode, intervalMs: config.jobWorkerIntervalMs, concurrency: config.jobWorkerConcurrency, shutdownTimeoutMs: config.jobWorkerShutdownTimeoutMs, auditChain: true }));
