const baseUrl = String(process.env.SMOKE_BASE_URL || 'http://127.0.0.1:8080').replace(/\/$/, '');
const concurrency = Math.max(1, Number(process.env.SMOKE_CONCURRENCY || 20) || 20);
const requestsPerWorker = Math.max(1, Number(process.env.SMOKE_REQUESTS_PER_WORKER || 10) || 10);
const p95LimitMs = Math.max(1, Number(process.env.SMOKE_P95_LIMIT_MS || 1000) || 1000);
const maxErrorRate = Math.min(1, Math.max(0, Number(process.env.SMOKE_MAX_ERROR_RATE || 0) || 0));
const schoolId = String(process.env.SMOKE_SCHOOL_ID || '').trim();
const account = String(process.env.SMOKE_ADMIN_ACCOUNT || '').trim();
const password = String(process.env.SMOKE_ADMIN_PASSWORD || '');

if (Boolean(account) !== Boolean(password)) throw new Error('SMOKE_ADMIN_ACCOUNT 和 SMOKE_ADMIN_PASSWORD 必须同时配置；未配置时仅执行就绪探测');
if (account && !schoolId) throw new Error('使用认证业务冒烟压测时必须配置 SMOKE_SCHOOL_ID');

const timings = new Map();
const errors = [];
const percentile = (values, ratio) => values[Math.min(values.length - 1, Math.ceil(values.length * ratio) - 1)];
const record = (name, durationMs) => {
  const list = timings.get(name) || [];
  list.push(durationMs);
  timings.set(name, list);
};
const requestJson = async (name, pathname, options = {}) => {
  const startedAt = performance.now();
  try {
    const response = await fetch(`${baseUrl}${pathname}`, options);
    const raw = await response.text();
    let payload = null;
    try { payload = raw ? JSON.parse(raw) : null; } catch { /* response check below reports the unexpected body */ }
    const durationMs = performance.now() - startedAt;
    if (!response.ok || payload?.code !== 'OK') throw new Error(`HTTP ${response.status} ${payload?.code || 'INVALID_RESPONSE'}`);
    record(name, durationMs);
    return payload.data;
  } catch (error) {
    record(name, performance.now() - startedAt);
    errors.push({ name, message: error.message });
    return null;
  }
};

const health = await requestJson('readyz', '/readyz');
if (!health || health.database !== 'up') throw new Error(`initial readiness check failed: ${JSON.stringify(errors.slice(0, 3))}`);

let authorization = null;
if (account) {
  const login = await requestJson('login', '/v1/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ account, password }) });
  if (!login?.accessToken) throw new Error(`smoke login failed: ${JSON.stringify(errors.slice(0, 3))}`);
  if (login.mfaRequired) throw new Error('smoke account 启用了 MFA；请使用专用、无需 MFA 的只读压测账户，或改用受控端到端压测环境');
  authorization = { Authorization: `Bearer ${login.accessToken}` };
}

const scenarios = authorization
  ? [
      ['readyz', '/readyz'],
      ['me', '/v1/me'],
      ['dashboard', `/v1/schools/${encodeURIComponent(schoolId)}/dashboard?studentPage=1&studentPageSize=20`],
      ['tasks', `/v1/schools/${encodeURIComponent(schoolId)}/tasks?paged=1&page=1&pageSize=20`],
      ['field_stations', `/v1/admin/test-stations?schoolId=${encodeURIComponent(schoolId)}`]
    ]
  : [['readyz', '/readyz']];

await Promise.all(Array.from({ length: concurrency }, async () => {
  for (let index = 0; index < requestsPerWorker; index += 1) {
    for (const [name, pathname] of scenarios) await requestJson(name, pathname, authorization ? { headers: authorization } : undefined);
  }
}));

const metrics = Object.fromEntries([...timings.entries()].map(([name, values]) => {
  values.sort((left, right) => left - right);
  return [name, { requests: values.length, p50Ms: Math.round(percentile(values, 0.5)), p95Ms: Math.round(percentile(values, 0.95)), maxMs: Math.round(values.at(-1)) }];
}));
const requestCount = [...timings.values()].reduce((total, values) => total + values.length, 0);
const errorRate = requestCount ? errors.length / requestCount : 1;
const result = { baseUrl, mode: authorization ? 'authenticated-read-only' : 'readiness-only', concurrency, requestsPerWorker, requests: requestCount, errors: errors.length, errorRate: Number(errorRate.toFixed(4)), p95LimitMs, metrics };
const p95Exceeded = Object.entries(metrics).find(([, metric]) => metric.p95Ms > p95LimitMs);
if (errors.length && errorRate > maxErrorRate) throw new Error(`load smoke error budget exceeded: ${JSON.stringify({ ...result, samples: errors.slice(0, 5) })}`);
if (p95Exceeded) throw new Error(`load smoke p95 latency exceeded for ${p95Exceeded[0]}: ${JSON.stringify(result)}`);
console.log(JSON.stringify(result));
