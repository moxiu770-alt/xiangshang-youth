import { config } from '../config.js';

/**
 * Notification campaign lifecycle: scoped teacher drafts, delivery, and
 * guardian receipts. Server middleware and generic response helpers remain
 * injected so this module has no hidden global authorization dependencies.
 */
export async function handleNotificationRoutes(context) {
  const {
    req, res, user, url, query, pool, hasRole, parentOnly, teacherOnly,
    teacherClassIds, schoolAllowed, userHasCapability, queryValue,
    noticeClassIds, body, fail, beginIdempotentRequest, requestBodyHash,
    audit, createdIdempotently, okIdempotently, ok
  } = context;

if (req.method === 'GET' && url.pathname === '/v1/admin/notifications/campaigns') {
  if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权查看通知批次');
  const schoolId = queryValue(url, 'schoolId') || user.roles.find((role) => role.school_id)?.school_id;
  if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
  const result = await query(`SELECT id,school_id AS "schoolId",title,content,audience_type AS "audienceType",audience_filter AS "audienceFilter",channel,status,sent_count AS "sentCount",failed_count AS "failedCount",created_at AS "createdAt",sent_at AS "sentAt" FROM notification_campaigns WHERE school_id=$1 ORDER BY created_at DESC LIMIT 100`, [schoolId]);
  return ok(res, result.rows);
}
if (req.method === 'GET' && url.pathname === '/v1/classes/notifications/drafts') {
  if (!hasRole(user, 'teacher')) return fail(res, 403, 'NO_PERMISSION', '只有教师可以查看班级通知草稿');
  const schoolId = queryValue(url, 'schoolId') || user.roles.find((role) => role.school_id)?.school_id;
  if (!schoolId || !schoolAllowed(user, schoolId) || !await userHasCapability(user, 'PUBLISH_CLASS_NOTICE', schoolId, null)) return fail(res, 403, 'CAPABILITY_DENIED', '当前账号无发布班级通知权限');
  const result = await query(`SELECT id AS "notificationId",school_id AS "schoolId",created_by AS "senderTeacherId",title,content,
    COALESCE(audience_filter->'targetClassIds', audience_filter->'classIds', CASE WHEN audience_filter ? 'classId' THEN jsonb_build_array(audience_filter->>'classId') ELSE '[]'::jsonb END) AS "targetClassIds",
    COALESCE(audience_filter->>'recipientScope', audience_type) AS "recipientScope",
    audience_filter AS "audienceFilter",scheduled_at AS "scheduledAt",status,draft_version AS "draftVersion",created_at AS "createdAt",sent_at AS "sentAt",failure_reason AS "failureReason",parent_receipt_enabled AS "parentReceiptEnabled"
    FROM notification_campaigns WHERE school_id=$1 AND created_by=$2 AND status='draft' ORDER BY created_at DESC LIMIT 100`, [schoolId, user.id]);
  return ok(res, result.rows);
}
if (req.method === 'GET' && /^\/v1\/classes\/notifications\/[^/]+$/.test(url.pathname)) {
  const notificationId = url.pathname.split('/').pop();
  const result = await query(`SELECT nc.id AS "notificationId",nc.school_id AS "schoolId",nc.created_by AS "senderTeacherId",nc.title,nc.content,
      COALESCE(nc.audience_filter->'targetClassIds', nc.audience_filter->'classIds', CASE WHEN nc.audience_filter ? 'classId' THEN jsonb_build_array(nc.audience_filter->>'classId') ELSE '[]'::jsonb END) AS "targetClassIds",
      COALESCE(nc.audience_filter->>'recipientScope', nc.audience_type) AS "recipientScope",
      nc.status,nc.draft_version AS "draftVersion",nc.scheduled_at AS "scheduledAt",nc.sent_at AS "sentAt",nc.failure_reason AS "failureReason",nc.parent_receipt_enabled AS "parentReceiptEnabled",
      nr.status AS "userReceiptStatus",nr.acknowledged_at AS "acknowledgedAt",
      COALESCE((SELECT json_build_object(
        'pending', COUNT(*) FILTER (WHERE status='pending')::int,
        'acknowledged', COUNT(*) FILTER (WHERE status='acknowledged')::int,
        'total', COUNT(*)::int
      ) FROM notification_receipts WHERE campaign_id=nc.id),'{"pending":0,"acknowledged":0,"total":0}'::json) AS "receiptStats"
    FROM notification_campaigns nc
    LEFT JOIN notification_receipts nr ON nr.campaign_id=nc.id AND nr.receiver_user_id=$2
    WHERE nc.id=$1`, [notificationId, user.id]);
  const row = result.rows[0];
  if (!row || !schoolAllowed(user, row.schoolId)) return fail(res, 404, 'NOTIFICATION_NOT_FOUND', '通知不存在或无权访问');
  const classIds = Array.isArray(row.targetClassIds) ? row.targetClassIds.map(String) : [];
  if (teacherOnly(user) && row.senderTeacherId !== user.id && !classIds.some((classId) => teacherClassIds(user, row.schoolId).includes(classId))) return fail(res, 404, 'NOTIFICATION_NOT_FOUND', '通知不存在或无权访问');
  if (parentOnly(user)) {
    const delivered = await query('SELECT 1 FROM messages WHERE receiver_user_id=$1 AND business_route=$2 AND business_id=$3 LIMIT 1', [user.id, 'classNotice', notificationId]);
    if (!delivered.rowCount) return fail(res, 404, 'NOTIFICATION_NOT_FOUND', '通知不存在或无权访问');
    delete row.receiptStats;
  }
  return ok(res, row);
}
if (req.method === 'POST' && /^\/v1\/classes\/notifications\/[^/]+\/receipt$/.test(url.pathname)) {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家长可以确认通知回执');
  const notificationId = url.pathname.split('/').at(-2);
  const campaign = await query('SELECT * FROM notification_campaigns WHERE id=$1', [notificationId]);
  const row = campaign.rows[0];
  if (!row || !schoolAllowed(user, row.school_id)) return fail(res, 404, 'NOTIFICATION_NOT_FOUND', '通知不存在或无权访问');
  if (!row.parent_receipt_enabled) return fail(res, 409, 'RECEIPT_NOT_REQUIRED', '该通知不需要家长确认回执');
  const delivered = await query('SELECT 1 FROM messages WHERE receiver_user_id=$1 AND business_route=$2 AND business_id=$3 LIMIT 1', [user.id, 'classNotice', notificationId]);
  if (!delivered.rowCount) return fail(res, 404, 'NOTIFICATION_NOT_FOUND', '通知不存在或无权访问');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ notificationId, action: 'acknowledge' }));
  if (idempotency === false) return;
  const updated = await query(`INSERT INTO notification_receipts(campaign_id,receiver_user_id,status,acknowledged_at)
    VALUES($1,$2,'acknowledged',now())
    ON CONFLICT(campaign_id,receiver_user_id) DO UPDATE SET
      status='acknowledged',
      acknowledged_at=COALESCE(notification_receipts.acknowledged_at,now()),
      version=notification_receipts.version + CASE WHEN notification_receipts.status='acknowledged' THEN 0 ELSE 1 END,
      updated_at=now()
    RETURNING id,campaign_id AS "notificationId",receiver_user_id AS "receiverUserId",status,acknowledged_at AS "acknowledgedAt",version`, [notificationId, user.id]);
  await audit(user, req, 'notification.receipt.acknowledge', 'notification_receipt', updated.rows[0].id, null, updated.rows[0], row.school_id);
  return okIdempotently(res, user, idempotency, updated.rows[0]);
}
if (req.method === 'PUT' && /^\/v1\/classes\/notifications\/[^/]+$/.test(url.pathname)) {
  if (!hasRole(user, 'teacher')) return fail(res, 403, 'NO_PERMISSION', '只有教师可以编辑班级通知');
  const notificationId = url.pathname.split('/').pop();
  const input = await body(req);
  const existing = await query('SELECT * FROM notification_campaigns WHERE id=$1', [notificationId]);
  const row = existing.rows[0];
  const classIds = noticeClassIds(input);
  const fallbackClassIds = noticeClassIds(row?.audience_filter || {});
  if (!row || row.created_by !== user.id || !schoolAllowed(user, row.school_id)) return fail(res, 404, 'NOTIFICATION_NOT_FOUND', '通知草稿不存在或无权编辑');
  const capabilityClassIds = classIds.length ? classIds : fallbackClassIds;
  for (const classId of capabilityClassIds) {
    if (!await userHasCapability(user, 'PUBLISH_CLASS_NOTICE', row.school_id, classId)) return fail(res, 404, 'NOTIFICATION_NOT_FOUND', '通知草稿不存在或无权编辑');
  }
  if (row.status !== 'draft') return fail(res, 409, 'NOTIFICATION_NOT_EDITABLE', '已发送通知不能继续编辑');
  if (Number.isInteger(input.draftVersion) && Number(row.draft_version) !== Number(input.draftVersion)) return fail(res, 409, 'VERSION_CONFLICT', '通知草稿已被更新，请刷新后继续编辑');
  if (!input.title || !input.content || !classIds.length) return fail(res, 400, 'INVALID_ARGUMENT', '通知标题、正文和接收班级不能为空');
  const allowedClassIds = teacherClassIds(user, row.school_id);
  if (!classIds.every((classId) => allowedClassIds.includes(classId))) return fail(res, 403, 'TEACHER_CLASS_SCOPE_INVALID', '教师只能向本人管理的班级发送通知');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ notificationId, ...input }));
  if (idempotency === false) return;
  const audienceFilter = { ...input, classId: classIds[0], classIds, targetClassIds: classIds, recipientScope: input.recipientScope || 'class' };
  const updated = await query(`UPDATE notification_campaigns SET title=$1,content=$2,audience_type='class',audience_filter=$3,scheduled_at=$4,draft_version=draft_version+1,parent_receipt_enabled=COALESCE($5,parent_receipt_enabled),updated_at=now() WHERE id=$6 RETURNING id AS "notificationId",school_id AS "schoolId",created_by AS "senderTeacherId",title,content,COALESCE(audience_filter->'targetClassIds', audience_filter->'classIds') AS "targetClassIds",COALESCE(audience_filter->>'recipientScope', audience_type) AS "recipientScope",status,draft_version AS "draftVersion",scheduled_at AS "scheduledAt",sent_at AS "sentAt",failure_reason AS "failureReason",parent_receipt_enabled AS "parentReceiptEnabled"`, [input.title, input.content, audienceFilter, input.scheduledAt || null, input.parentReceiptEnabled, notificationId]);
  await audit(user, req, 'notification.draft.update', 'notification_campaign', notificationId, row, updated.rows[0], row.school_id);
  return okIdempotently(res, user, idempotency, updated.rows[0]);
}
if (req.method === 'DELETE' && /^\/v1\/classes\/notifications\/[^/]+$/.test(url.pathname)) {
  if (!hasRole(user, 'teacher')) return fail(res, 403, 'NO_PERMISSION', '只有教师可以删除班级通知草稿');
  const notificationId = url.pathname.split('/').pop();
  const existing = await query('SELECT * FROM notification_campaigns WHERE id=$1', [notificationId]);
  const row = existing.rows[0];
  if (!row || row.created_by !== user.id || row.status !== 'draft' || !schoolAllowed(user, row.school_id)) return fail(res, 404, 'NOTIFICATION_NOT_FOUND', '通知草稿不存在或无权删除');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ notificationId, action: 'discard' }));
  if (idempotency === false) return;
  await query('DELETE FROM notification_campaigns WHERE id=$1 AND status=$2', [notificationId, 'draft']);
  await audit(user, req, 'notification.draft.discard', 'notification_campaign', notificationId, row, null, row.school_id);
  return okIdempotently(res, user, idempotency, { notificationId, status: 'discarded' });
}
const draftAction = url.pathname.match(/^\/v1\/classes\/notifications\/([^/]+)\/(send|retry)$/);
if (req.method === 'POST' && draftAction) {
  const draft = await query('SELECT * FROM notification_campaigns WHERE id=$1', [draftAction[1]]);
  if (!draft.rowCount || !schoolAllowed(user, draft.rows[0].school_id) || draft.rows[0].created_by !== user.id) return fail(res, 404, 'NOTIFICATION_NOT_FOUND', '通知草稿不存在或无权发送');
  const scopedClassIds = noticeClassIds(draft.rows[0].audience_filter);
  if (!scopedClassIds.length) return fail(res, 400, 'INVALID_ARGUMENT', '通知草稿缺少接收班级');
  if (teacherOnly(user)) {
    const allowedClassIds = teacherClassIds(user, draft.rows[0].school_id);
    if (!scopedClassIds.every((classId) => allowedClassIds.includes(classId))) return fail(res, 403, 'TEACHER_CLASS_SCOPE_INVALID', '教师只能向本人管理的班级发送通知');
    for (const classId of scopedClassIds) {
      if (!await userHasCapability(user, 'PUBLISH_CLASS_NOTICE', draft.rows[0].school_id, classId)) return fail(res, 403, 'CAPABILITY_DENIED', '当前账号无发布班级通知权限');
    }
  }
  if (draftAction[2] === 'send' && draft.rows[0].status !== 'draft') return fail(res, 409, 'NOTIFICATION_ALREADY_SENT', '通知已经发送');
  if (draftAction[2] === 'retry' && draft.rows[0].status !== 'failed') return fail(res, 409, 'NOTIFICATION_NOT_RETRYABLE', '当前通知不需要重试');
}
if (req.method === 'POST' && (url.pathname === '/v1/admin/notifications/campaigns' || url.pathname === '/v1/classes/notifications' || draftAction)) {
  if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权发送学校通知');
  const draft = draftAction ? (await query('SELECT * FROM notification_campaigns WHERE id=$1', [draftAction[1]])).rows[0] : null;
  const input = draft ? { ...(draft.audience_filter || {}), schoolId: draft.school_id, title: draft.title, content: draft.content, audienceType: draft.audience_type, channel: draft.channel, scheduledAt: draft.scheduled_at, parentReceiptEnabled: draft.parent_receipt_enabled } : await body(req);
  if (!input.title || !input.content) return fail(res, 400, 'INVALID_ARGUMENT', '通知标题和内容不能为空');
  const schoolId = input.schoolId || user.roles.find((role) => role.school_id)?.school_id;
  if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权向该学校发送通知');
  const classIds = noticeClassIds(input);
  if (teacherOnly(user)) {
    for (const classId of classIds) {
      if (!await userHasCapability(user, 'PUBLISH_CLASS_NOTICE', schoolId, classId)) return fail(res, 403, 'CAPABILITY_DENIED', '当前账号无发布班级通知权限');
    }
  }
  const audienceType = ['school', 'grade', 'class', 'users'].includes(input.audienceType) ? input.audienceType : 'school';
  if (teacherOnly(user) && audienceType !== 'class') return fail(res, 403, 'TEACHER_AUDIENCE_SCOPE_INVALID', '教师通知仅允许发送给本人管理的班级');
  if (audienceType === 'grade' && !input.gradeId) return fail(res, 400, 'INVALID_ARGUMENT', '指定年级发送通知时必须提供 gradeId');
  if (audienceType === 'class' && !classIds.length) return fail(res, 400, 'INVALID_ARGUMENT', '指定班级发送通知时必须提供 classId');
  if (audienceType === 'users' && (!Array.isArray(input.userIds) || !input.userIds.length)) return fail(res, 400, 'INVALID_ARGUMENT', '指定用户发送通知时必须提供 userIds');
  if (audienceType === 'grade' && !(await query('SELECT 1 FROM grades WHERE id=$1 AND school_id=$2', [input.gradeId, schoolId])).rowCount) return fail(res, 400, 'GRADE_SCOPE_INVALID', '年级不属于该学校');
  if (audienceType === 'class') {
    const classScope = await query('SELECT id FROM classes WHERE school_id=$1 AND id=ANY($2)', [schoolId, classIds]);
    if (classScope.rowCount !== classIds.length) return fail(res, 400, 'CLASS_SCOPE_INVALID', '班级不属于该学校');
  }
  if (teacherOnly(user) && !classIds.every((classId) => teacherClassIds(user, schoolId).includes(classId))) return fail(res, 403, 'TEACHER_CLASS_SCOPE_INVALID', '教师只能向本人管理的班级发送通知');
  const channel = input.channel || 'in_app';
  if (!['in_app', 'push', 'sms', 'wechat'].includes(channel)) return fail(res, 400, 'INVALID_ARGUMENT', '通知渠道不支持');
  if (input.scheduledAt && Number.isNaN(Date.parse(input.scheduledAt))) return fail(res, 400, 'INVALID_ARGUMENT', '定时发送时间格式无效');
  if (input.status === 'draft') {
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ ...input, status: 'draft' }));
    if (idempotency === false) return;
    const audienceFilter = { ...input, classId: classIds[0], classIds, targetClassIds: classIds, recipientScope: input.recipientScope || audienceType };
    const draft = await query(`INSERT INTO notification_campaigns(school_id,created_by,sender_teacher_id,title,content,audience_type,audience_filter,channel,status,draft_version,scheduled_at,parent_receipt_enabled,idempotency_key) VALUES($1,$2,$2,$3,$4,$5,$6,$7,'draft',1,$8,$9,$10) RETURNING id AS "notificationId",school_id AS "schoolId",created_by AS "senderTeacherId",title,content,COALESCE(audience_filter->'targetClassIds', audience_filter->'classIds') AS "targetClassIds",COALESCE(audience_filter->>'recipientScope', audience_type) AS "recipientScope",status,draft_version AS "draftVersion",scheduled_at AS "scheduledAt",sent_at AS "sentAt",failure_reason AS "failureReason",parent_receipt_enabled AS "parentReceiptEnabled"`, [schoolId, user.id, input.title, input.content, audienceType, audienceFilter, channel, input.scheduledAt || null, input.parentReceiptEnabled === true, req.headers['idempotency-key'] || null]);
    await audit(user, req, 'notification.draft.create', 'notification_campaign', draft.rows[0].notificationId, null, draft.rows[0], schoolId);
    return createdIdempotently(res, user, idempotency, draft.rows[0]);
  }
  if (channel !== 'in_app' && !config.notificationWebhookUrl) return fail(res, 503, 'DELIVERY_PROVIDER_NOT_CONFIGURED', '当前环境尚未配置短信、微信或推送服务商网关');
  let audience;
  if (audienceType === 'users') {
    const ids = Array.isArray(input.userIds) ? input.userIds : [];
    audience = await query(`SELECT DISTINCT u.id FROM users u JOIN user_roles ur ON ur.user_id=u.id WHERE ur.school_id=$1 AND u.id=ANY($2)`, [schoolId, ids]);
  } else if (audienceType === 'grade') {
    audience = await query(`SELECT DISTINCT u.id FROM users u JOIN user_roles ur ON ur.user_id=u.id WHERE ur.school_id=$1 UNION SELECT DISTINCT pb.parent_user_id FROM parent_student_bindings pb JOIN students st ON st.id=pb.student_id WHERE st.school_id=$1 AND st.grade_id=$2`, [schoolId, input.gradeId]);
  } else if (audienceType === 'class') {
    audience = await query(`SELECT DISTINCT u.id FROM users u JOIN user_roles ur ON ur.user_id=u.id WHERE ur.school_id=$1 AND ur.class_id=ANY($2)
      UNION SELECT DISTINCT pb.parent_user_id FROM parent_student_bindings pb JOIN students st ON st.id=pb.student_id WHERE st.school_id=$1 AND st.class_id=ANY($2)`, [schoolId, classIds]);
  } else {
    audience = await query(`SELECT DISTINCT u.id FROM users u JOIN user_roles ur ON ur.user_id=u.id WHERE ur.school_id=$1 UNION SELECT DISTINCT pb.parent_user_id FROM parent_student_bindings pb JOIN students st ON st.id=pb.student_id WHERE st.school_id=$1`, [schoolId]);
  }
  if (!audience.rowCount) return fail(res, 409, 'NOTIFICATION_AUDIENCE_EMPTY', '当前接收范围内没有可投递用户，请修改接收范围');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
  if (idempotency === false) return;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const audienceFilter = { ...input, classId: classIds[0], classIds, targetClassIds: classIds, recipientScope: input.recipientScope || audienceType };
    const campaign = draft
      ? await client.query(`UPDATE notification_campaigns SET status='queued',failure_reason=NULL,sent_count=0,failed_count=0,sent_at=NULL,updated_at=now() WHERE id=$1 RETURNING id,title,status`, [draft.id])
      : await client.query(`INSERT INTO notification_campaigns(school_id,created_by,title,content,audience_type,audience_filter,channel,status,sender_teacher_id,parent_receipt_enabled,idempotency_key,scheduled_at) VALUES($1,$2,$3,$4,$5,$6,$7,'queued',$2,$8,$9,$10) RETURNING id,title,status`, [schoolId, user.id, input.title, input.content, audienceType, audienceFilter, channel, input.parentReceiptEnabled === true, req.headers['idempotency-key'] || null, input.scheduledAt || null]);
    const requestedAt = input.scheduledAt ? new Date(input.scheduledAt) : new Date();
    const availableAt = requestedAt.getTime() > Date.now() ? requestedAt : new Date();
    for (const receiver of audience.rows) {
      const delivery = await client.query(`INSERT INTO notification_deliveries(campaign_id,receiver_user_id,channel,status,error_message,delivered_at)
        VALUES($1,$2,$3,'queued',NULL,NULL)
        ON CONFLICT(campaign_id,receiver_user_id,channel) DO UPDATE SET status='queued',error_message=NULL,delivered_at=NULL
        RETURNING id`, [campaign.rows[0].id, receiver.id, channel]);
      await client.query(`INSERT INTO job_queue(job_type,payload,available_at) VALUES('notification.deliver',$1,$2)`, [{ deliveryId: delivery.rows[0].id }, availableAt]);
    }
    await client.query('COMMIT');
    await audit(user, req, 'notification.campaign.queue', 'notification_campaign', campaign.rows[0].id, null, { audienceType, queuedCount: audience.rowCount, channel, scheduledAt: input.scheduledAt || null }, schoolId);
    return createdIdempotently(res, user, idempotency, { ...campaign.rows[0], sentCount: 0, queuedCount: audience.rowCount, channel, scheduledAt: input.scheduledAt || null });
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}
}
