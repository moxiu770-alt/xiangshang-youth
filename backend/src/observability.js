const requestMetrics = new Map();
const durationBuckets = [50, 100, 250, 500, 1000, 2500, 5000];
const requestHistograms = new Map();
const counters = new Map();

export function normalizePath(path) {
  return String(path || '/').split('?')[0]
    .replace(/\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b/gi, ':id')
    .replace(/\b[0-9a-f]{20,}\b/gi, ':id')
    .replace(/\b\d+\b/g, ':id');
}

export const logger = {
  info(event, fields = {}) { console.log(JSON.stringify({ level: 'info', event, time: new Date().toISOString(), ...fields })); },
  warn(event, fields = {}) { console.warn(JSON.stringify({ level: 'warn', event, time: new Date().toISOString(), ...fields })); },
  error(event, fields = {}) { console.error(JSON.stringify({ level: 'error', event, time: new Date().toISOString(), ...fields })); }
};

export function recordMetric(name, labels = {}, value = 1) {
  const labelText = Object.entries(labels).sort(([a], [b]) => a.localeCompare(b)).map(([key, label]) => `${key}="${String(label).replaceAll('"', '\\"')}"`).join(',');
  const key = `${name}|${labelText}`;
  counters.set(key, (counters.get(key) || 0) + value);
}

export function recordRequest(method, path, status, durationMs) {
  const key = `${method} ${normalizePath(path)} ${status}`;
  const current = requestMetrics.get(key) || { count: 0, durationMs: 0 };
  current.count += 1;
  current.durationMs += durationMs;
  requestMetrics.set(key, current);
  const histogramKey = `${method} ${normalizePath(path)}`;
  const histogram = requestHistograms.get(histogramKey) || { buckets: Array(durationBuckets.length + 1).fill(0), sum: 0, count: 0 };
  const bucket = durationBuckets.findIndex((limit) => durationMs <= limit);
  histogram.buckets[bucket === -1 ? durationBuckets.length : bucket] += 1;
  histogram.sum += durationMs;
  histogram.count += 1;
  requestHistograms.set(histogramKey, histogram);
}

export function metricsText() {
  const lines = [
    '# HELP xiangshang_http_requests_total Total HTTP requests by method, route and status.',
    '# TYPE xiangshang_http_requests_total counter',
    '# HELP xiangshang_http_request_duration_ms_total Accumulated HTTP request duration in milliseconds.',
    '# TYPE xiangshang_http_request_duration_ms_total counter'
  ];
  for (const [key, value] of requestMetrics) {
    const [method, route, status] = key.split(' ');
    const labels = `method="${method}",route="${route}",status="${status}"`;
    lines.push(`xiangshang_http_requests_total{${labels}} ${value.count}`);
    lines.push(`xiangshang_http_request_duration_ms_total{${labels}} ${value.durationMs}`);
  }
  for (const [key, value] of requestHistograms) {
    const [method, route] = key.split(' ');
    for (let index = 0; index < value.buckets.length; index += 1) {
      const le = index < durationBuckets.length ? durationBuckets[index] : '+Inf';
      const cumulative = value.buckets.slice(0, index + 1).reduce((sum, count) => sum + count, 0);
      lines.push(`xiangshang_http_request_duration_ms_bucket{method="${method}",route="${route}",le="${le}"} ${cumulative}`);
    }
    lines.push(`xiangshang_http_request_duration_ms_sum{method="${method}",route="${route}"} ${value.sum}`);
    lines.push(`xiangshang_http_request_duration_ms_count{method="${method}",route="${route}"} ${value.count}`);
  }
  for (const [key, value] of counters) {
    const [name, labelText] = key.split('|');
    lines.push(`${name}${labelText ? `{${labelText}}` : ''} ${value}`);
  }
  return `${lines.join('\n')}\n`;
}
