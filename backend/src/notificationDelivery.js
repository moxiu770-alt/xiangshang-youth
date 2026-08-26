import { pool, query } from './db.js';
import { config } from './config.js';

const providerError = (code, message) => Object.assign(new Error(message), { code });

function assertProviderEndpoint() {
  if (!config.notificationWebhookUrl) throw providerError('DELIVERY_PROVIDER_NOT_CONFIGURED', '通知服务商网关尚未配置');
  let endpoint;
  try { endpoint = new URL(config.notificationWebhookUrl); } catch { throw providerError('DELIVERY_PROVIDER_URL_INVALID', '通知服务商网关地址无效'); }
  const localDevelopment = !config.isProduction && ['localhost', '127.0.0.1', '::1'].includes(endpoint.hostname);
  if (endpoint.protocol !== 'https:' && !localDevelopment) throw providerError('DELIVERY_PROVIDER_URL_INSECURE', '通知服务商网关必须使用 HTTPS');
  return endpoint;
}

async function dispatchToProvider(delivery) {
  const endpoint = assertProviderEndpoint();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.notificationWebhookTimeoutMs);
  try {
    const response = await fetch(endpoint, {
      method: 'POST', signal: controller.signal,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': delivery.deliveryId,
        ...(config.notificationWebhookAuthorization ? { authorization: config.notificationWebhookAuthorization } : {})
      },
      body: JSON.stringify({
        deliveryId: delivery.deliveryId, campaignId: delivery.campaignId,
        channel: delivery.channel, receiverUserId: delivery.receiverUserId,
        title: delivery.title, content: delivery.content,
        businessRoute: 'classNotice', businessId: delivery.campaignId
      })
    });
    if (!response.ok) throw providerError('DELIVERY_PROVIDER_REJECTED', `通知服务商返回 HTTP ${response.status}`);
  } catch (error) {
    if (error?.name === 'AbortError') throw providerError('DELIVERY_PROVIDER_TIMEOUT', '通知服务商请求超时');
    throw error;
  } finally { clearTimeout(timeout); }
}

async function refreshCampaignState(client, campaignId) {
  const counts = await client.query(`SELECT
      COUNT(*) FILTER (WHERE status='sent')::int AS sent,
      COUNT(*) FILTER (WHERE status='failed')::int AS failed,
      COUNT(*) FILTER (WHERE status='queued')::int AS queued
    FROM notification_deliveries WHERE campaign_id=$1`, [campaignId]);
  const { sent = 0, failed = 0, queued = 0 } = counts.rows[0] || {};
  const status = queued > 0 ? 'queued' : failed > 0 && sent > 0 ? 'partial' : failed > 0 ? 'failed' : 'sent';
  await client.query(`UPDATE notification_campaigns SET status=$1,sent_count=$2,failed_count=$3,
      failure_reason=CASE WHEN $1 IN ('failed','partial') THEN '部分或全部通知投递失败' ELSE NULL END,
      sent_at=CASE WHEN $4=0 THEN COALESCE(sent_at,now()) ELSE NULL END,updated_at=now()
    WHERE id=$5`, [status, sent, failed, queued, campaignId]);
  return { status, sentCount: sent, failedCount: failed, queuedCount: queued };
}

/** Deliver one durable outbox record. Raw child health data never enters this boundary. */
export async function deliverNotificationDelivery(deliveryId) {
  const loaded = await query(`SELECT nd.id AS "deliveryId",nd.campaign_id AS "campaignId",nd.receiver_user_id AS "receiverUserId",nd.channel,nd.status,
      nc.title,nc.content,nc.parent_receipt_enabled AS "parentReceiptEnabled"
    FROM notification_deliveries nd JOIN notification_campaigns nc ON nc.id=nd.campaign_id WHERE nd.id=$1`, [deliveryId]);
  const delivery = loaded.rows[0];
  if (!delivery) throw providerError('NOTIFICATION_DELIVERY_NOT_FOUND', '通知投递记录不存在');
  if (delivery.status === 'sent') return { deliveryId, status: 'sent', duplicate: true };
  if (delivery.channel !== 'in_app') await dispatchToProvider(delivery);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const locked = await client.query('SELECT status FROM notification_deliveries WHERE id=$1 FOR UPDATE', [deliveryId]);
    if (!locked.rowCount) throw providerError('NOTIFICATION_DELIVERY_NOT_FOUND', '通知投递记录不存在');
    if (locked.rows[0].status !== 'sent') {
      await client.query(`INSERT INTO messages(receiver_user_id,title,content,category,message_type,business_id,business_route,action_label,expires_at)
        SELECT $1,$2,$3,'campaign','classNotice',$4,'classNotice','查看通知',NULL
        WHERE NOT EXISTS (SELECT 1 FROM messages WHERE receiver_user_id=$1 AND business_route='classNotice' AND business_id=$4)`, [delivery.receiverUserId, delivery.title, delivery.content, delivery.campaignId]);
      if (delivery.parentReceiptEnabled) {
        await client.query(`INSERT INTO notification_receipts(campaign_id,receiver_user_id,status)
          SELECT $1,$2,'pending' WHERE EXISTS (
            SELECT 1 FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=$2 AND r.code='parent'
          ) ON CONFLICT(campaign_id,receiver_user_id) DO NOTHING`, [delivery.campaignId, delivery.receiverUserId]);
      }
      await client.query(`UPDATE notification_deliveries SET status='sent',error_message=NULL,delivered_at=now() WHERE id=$1`, [deliveryId]);
    }
    const campaign = await refreshCampaignState(client, delivery.campaignId);
    await client.query('COMMIT');
    return { deliveryId, status: 'sent', campaign };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally { client.release(); }
}

export async function markNotificationDeliveryFailed(deliveryId, errorMessage) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const delivery = await client.query(`UPDATE notification_deliveries SET status='failed',error_message=$1,delivered_at=NULL
      WHERE id=$2 AND status<>'sent' RETURNING campaign_id AS "campaignId"`, [String(errorMessage || '通知投递失败').slice(0, 500), deliveryId]);
    if (delivery.rows[0]) await refreshCampaignState(client, delivery.rows[0].campaignId);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally { client.release(); }
}
