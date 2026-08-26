import crypto from 'node:crypto';

const EVENT_NAMES = new Set([
  'growth_report_opened',
  'growth_report_period_changed',
  'adaptive_plan_opened_courses'
]);
const COARSE_VALUES = new Set(['本周', '本月']);
const PLATFORMS = new Set(['ios', 'android']);
const ALLOWED_FIELDS = new Set([
  'eventId', 'eventName', 'coarseValue', 'platform', 'appVersion',
  'clientSessionId', 'occurredAt'
]);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APP_VERSION_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,39}$/;
const invalid = (code, message) => Object.assign(new Error(message), { status: 400, code });

/** Reject unknown fields so callers cannot accidentally send child identity,
 * health measurements, phone numbers or free-form content. */
export function validateProductEventBatch(input, now = new Date()) {
  if (!input || !Array.isArray(input.events) || input.events.length < 1 || input.events.length > 20) {
    throw invalid('PRODUCT_EVENT_BATCH_INVALID', '每批产品事件必须为 1 至 20 条');
  }
  if (Object.keys(input).some((key) => key !== 'events')) throw invalid('PRODUCT_EVENT_FIELD_NOT_ALLOWED', '产品事件包含不允许的字段');
  const earliest = now.getTime() - 7 * 24 * 60 * 60 * 1000;
  const latest = now.getTime() + 5 * 60 * 1000;
  return input.events.map((event) => {
    if (!event || typeof event !== 'object' || Array.isArray(event)) throw invalid('PRODUCT_EVENT_INVALID', '产品事件格式无效');
    if (Object.keys(event).some((key) => !ALLOWED_FIELDS.has(key))) throw invalid('PRODUCT_EVENT_FIELD_NOT_ALLOWED', '产品事件包含不允许的字段');
    if (!UUID_PATTERN.test(event.eventId || '') || !UUID_PATTERN.test(event.clientSessionId || '')) throw invalid('PRODUCT_EVENT_ID_INVALID', '产品事件编号格式无效');
    if (!EVENT_NAMES.has(event.eventName)) throw invalid('PRODUCT_EVENT_NAME_INVALID', '产品事件类型不受支持');
    if (event.coarseValue != null && !COARSE_VALUES.has(event.coarseValue)) throw invalid('PRODUCT_EVENT_VALUE_INVALID', '产品事件值不受支持');
    if (!PLATFORMS.has(event.platform)) throw invalid('PRODUCT_EVENT_PLATFORM_INVALID', '产品事件平台无效');
    if (!APP_VERSION_PATTERN.test(event.appVersion || '')) throw invalid('PRODUCT_EVENT_VERSION_INVALID', 'App 版本格式无效');
    const occurredAt = new Date(event.occurredAt);
    if (!Number.isFinite(occurredAt.getTime()) || occurredAt.getTime() < earliest || occurredAt.getTime() > latest) throw invalid('PRODUCT_EVENT_TIME_INVALID', '产品事件时间无效');
    return {
      eventId: event.eventId,
      eventName: event.eventName,
      coarseValue: event.coarseValue ?? null,
      platform: event.platform,
      appVersion: event.appVersion,
      clientSessionHash: crypto.createHash('sha256').update(event.clientSessionId).digest('hex'),
      occurredAt: occurredAt.toISOString()
    };
  });
}

export async function handleProductEventRoutes(context) {
  const { req, res, user, url, body, query, fail, ok, consumePersistentRateLimit } = context;
  if (!(req.method === 'POST' && url.pathname === '/v1/mobile/events')) return;
  const rate = await consumePersistentRateLimit(`product-events:${user.id}`, 60_000, 60);
  if (!rate.allowed) {
    res.setHeader('Retry-After', String(Math.max(1, Math.ceil(rate.retryAfter / 1000))));
    return fail(res, 429, 'PRODUCT_EVENT_RATE_LIMITED', '产品事件提交过于频繁');
  }
  const events = validateProductEventBatch(await body(req));
  let acceptedCount = 0;
  let duplicateCount = 0;
  for (const event of events) {
    const result = await query(`INSERT INTO product_events(
      event_id,event_name,coarse_value,platform,app_version,client_session_hash,occurred_at
    ) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(event_id) DO NOTHING`, [
      event.eventId, event.eventName, event.coarseValue, event.platform,
      event.appVersion, event.clientSessionHash, event.occurredAt
    ]);
    if (result.rowCount) acceptedCount += 1;
    else duplicateCount += 1;
  }
  return ok(res, { acceptedCount, duplicateCount });
}
