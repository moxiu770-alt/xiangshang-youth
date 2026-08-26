/** Device-authenticated field routes, isolated from user-session routes. */
export async function handleFieldDeviceRoutes(context) {
  const {
    req, res, url, parts, currentFieldDevice, fail, body, fieldObject, query,
    publishFieldUpdate, ok, fieldBootstrap, queryValue, safeFileName,
    allowedContentTypes, maxUploadBytes, crypto, path, created, rawBody,
    fileSignatureMatches, storage, sha256, transitionFieldQueue,
    openFieldSession, appendFieldSessionEvents, accepted, completeFieldSession,
    fieldInputString, requestBodyHash, recordMetric, logger, requestId, fieldIsoDate
  } = context;
  if (!url.pathname.startsWith('/v1/field/')) return false;
  const device = await currentFieldDevice(req);
  if (!device) return fail(res, 401, 'FIELD_DEVICE_UNAUTHORIZED', '场地设备身份无效、已停用或已过期');
  if (req.method === 'POST' && url.pathname === '/v1/field/heartbeat') {
    const input = await body(req);
    const health = fieldObject(input.health);
    const capabilities = fieldObject(input.capabilities);
    const updated = await query(`UPDATE test_devices SET status='online',software_version=$1,health_json=$2,
      capabilities_json=CASE WHEN $3::jsonb='{}'::jsonb THEN capabilities_json ELSE $3::jsonb END,last_heartbeat_at=now(),updated_at=now()
      WHERE id=$4 RETURNING id,status,software_version AS "softwareVersion",last_heartbeat_at AS "lastHeartbeatAt"`,
    [String(input.softwareVersion || device.software_version || '').slice(0, 120), health, capabilities, device.id]);
    // A display, speaker or card reader heartbeat cannot make a testing
    // station eligible. Only its registered edge host controls the online
    // state used by the formal-score gate.
    if (device.station_id && device.device_type === 'edge_host') await query(`UPDATE test_stations SET status=CASE WHEN status='disabled' THEN status ELSE 'online' END,last_seen_at=now(),updated_at=now() WHERE id=$1`, [device.station_id]);
    void publishFieldUpdate(device.school_id, 'device.heartbeat', { deviceId: device.id, stationId: device.station_id || null, status: 'online', health });
    return ok(res, { ...updated.rows[0], serverTime: new Date().toISOString() });
  }
  if (req.method === 'GET' && url.pathname === '/v1/field/bootstrap') return ok(res, await fieldBootstrap(device, queryValue(url, 'taskId')));
  if (req.method === 'GET' && url.pathname === '/v1/field/commands') {
    const commands = await query(`UPDATE device_commands SET status='delivered'
      WHERE device_id=$1 AND status='pending' AND (expires_at IS NULL OR expires_at>now())
      RETURNING id,command_type AS "commandType",payload_json AS payload,status,created_at AS "createdAt",expires_at AS "expiresAt"`, [device.id]);
    const delivered = await query(`SELECT id,command_type AS "commandType",payload_json AS payload,status,created_at AS "createdAt",expires_at AS "expiresAt"
      FROM device_commands WHERE device_id=$1 AND status='delivered' AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at LIMIT 50`, [device.id]);
    return ok(res, { commands: [...commands.rows, ...delivered.rows.filter((row) => !commands.rows.some((item) => item.id === row.id))] });
  }
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'field' && parts[2] === 'commands' && parts[3] && parts[4] === 'ack') {
    const input = await body(req);
    const acknowledged = await query(`UPDATE device_commands SET status=$1,acknowledged_at=now()
      WHERE id=$2 AND device_id=$3 AND status IN ('pending','delivered')
      RETURNING id,command_type AS "commandType",status,acknowledged_at AS "acknowledgedAt"`,
    [input.failed === true ? 'failed' : 'acknowledged', parts[3], device.id]);
    if (!acknowledged.rows[0]) return fail(res, 404, 'FIELD_COMMAND_NOT_FOUND', '设备指令不存在或已处理');
    return ok(res, acknowledged.rows[0]);
  }
  if (req.method === 'POST' && url.pathname === '/v1/field/files/presign') {
    const input = await body(req);
    const name = safeFileName(input.fileName || input.name || 'evidence.bin');
    const contentType = String(input.contentType || 'application/octet-stream');
    const fileSize = Number(input.fileSize || 0);
    if (!allowedContentTypes.has(contentType)) return fail(res, 400, 'FILE_TYPE_NOT_ALLOWED', '证据文件类型不受支持');
    if (!Number.isInteger(fileSize) || fileSize < 0 || fileSize > maxUploadBytes) return fail(res, 400, 'FILE_SIZE_INVALID', '证据文件大小不合法或超过 20MB');
    const fileId = crypto.randomUUID();
    const result = await query(`INSERT INTO files(id,owner_id,object_key,file_type,purpose,content_type,file_size,expires_at)
      VALUES($1,NULL,$2,$3,'field_evidence',$4,$5,now()+interval '30 minutes')
      RETURNING id,object_key AS "objectKey",content_type AS "contentType",status,expires_at AS "expiresAt"`,
    [fileId, `field/${device.id}/${fileId}-${name}`, path.extname(name).slice(1) || 'bin', contentType, fileSize]);
    return created(res, { ...result.rows[0], uploadUrl: `/v1/field/files/${fileId}/content` });
  }
  if (req.method === 'PUT' && parts[0] === 'v1' && parts[1] === 'field' && parts[2] === 'files' && parts[4] === 'content') {
    const fileResult = await query(`SELECT * FROM files WHERE id=$1 AND purpose='field_evidence' AND object_key LIKE $2`, [parts[3], `field/${device.id}/%`]);
    const file = fileResult.rows[0];
    if (!file) return fail(res, 404, 'FILE_NOT_FOUND', '证据文件不存在或不属于本设备');
    if (file.status !== 'pending') return fail(res, 409, 'FILE_UPLOAD_STATE_INVALID', '证据文件已上传或正在清理，不能重复写入');
    if (file.expires_at && new Date(file.expires_at) < new Date()) return fail(res, 410, 'FILE_UPLOAD_EXPIRED', '证据上传凭证已过期');
    const bytes = await rawBody(req);
    if (bytes.length > maxUploadBytes || (Number(file.file_size) > 0 && bytes.length > Number(file.file_size))) return fail(res, 413, 'FILE_SIZE_INVALID', '实际文件大小超过限制');
    if (!fileSignatureMatches(bytes, file.content_type)) return fail(res, 400, 'FILE_SIGNATURE_INVALID', '文件内容与声明类型不匹配');
    await storage.put(file.object_key, bytes, file.content_type);
    const uploaded = await query(`UPDATE files SET file_size=$1,checksum_sha256=$2,status='uploaded',uploaded_at=now() WHERE id=$3
      RETURNING id,file_size AS "fileSize",checksum_sha256 AS "checksumSha256",status,uploaded_at AS "uploadedAt"`, [bytes.length, sha256(bytes), file.id]);
    return ok(res, uploaded.rows[0]);
  }
  if (req.method === 'POST' && url.pathname === '/v1/field/queue/transition') return ok(res, await transitionFieldQueue(device, await body(req), { type: 'device', id: device.id }));
  if (req.method === 'POST' && url.pathname === '/v1/field/sessions') return created(res, await openFieldSession(device, await body(req)));
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'field' && parts[2] === 'sessions' && parts[3] && parts[4] === 'events') {
    const input = await body(req);
    return accepted(res, await appendFieldSessionEvents(device, parts[3], input.events));
  }
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'field' && parts[2] === 'sessions' && parts[3] && parts[4] === 'complete') return ok(res, await completeFieldSession(device, parts[3], await body(req)));
  if (req.method === 'POST' && url.pathname === '/v1/field/sync/batches') {
    const input = await body(req);
    const clientBatchId = fieldInputString(input.clientBatchId, '客户端批次 ID');
    const events = Array.isArray(input.events) ? input.events : [];
    if (!events.length || events.length > 200) return fail(res, 400, 'FIELD_BATCH_INVALID', '同步批次事件数量必须在 1 到 200 条之间');
    const existing = await query(`SELECT status,response_json AS response,received_at AS "receivedAt" FROM field_sync_batches WHERE device_id=$1 AND client_batch_id=$2`, [device.id, clientBatchId]);
    if (existing.rows[0]?.status === 'completed') return ok(res, { ...existing.rows[0].response, idempotent: true });
    if (existing.rows[0]?.status === 'processing' && Date.now() - new Date(existing.rows[0].receivedAt).getTime() < 5 * 60_000) return fail(res, 409, 'FIELD_BATCH_IN_PROGRESS', '同步批次正在处理中，请稍后重试');
    await query(`INSERT INTO field_sync_batches(device_id,client_batch_id,event_count,status) VALUES($1,$2,$3,'processing')
      ON CONFLICT(device_id,client_batch_id) DO UPDATE SET event_count=EXCLUDED.event_count,status='processing',received_at=now(),response_json='{}'::jsonb`, [device.id, clientBatchId, events.length]);
    const outcomes = [];
    try {
      for (const event of events) {
        const clientEventId = fieldInputString(event?.clientEventId, '客户端事件 ID');
        const eventType = fieldInputString(event?.eventType, '同步事件类型', 64);
        const payload = fieldObject(event?.payload);
        const payloadHash = requestBodyHash(payload);
        const replay = await query('SELECT event_type AS "eventType",payload_hash AS "payloadHash" FROM field_sync_events WHERE device_id=$1 AND client_event_id=$2', [device.id, clientEventId]);
        if (replay.rows[0]) {
          if (replay.rows[0].eventType !== eventType || replay.rows[0].payloadHash !== payloadHash) {
            recordMetric('xiangshang_field_sync_conflicts_total', { reason: 'replay_mismatch' });
            logger.warn('field.sync_replay_mismatch', { deviceId: device.id, clientEventId, eventType, originalEventType: replay.rows[0].eventType, requestId: requestId(req) });
            throw Object.assign(new Error('客户端事件 ID 与已接收内容不一致，已拒绝覆盖中央记录'), { status: 409, code: 'FIELD_EVENT_REPLAY_MISMATCH' });
          }
          outcomes.push({ clientEventId, eventType, replayed: true });
          continue;
        }
        let data;
        if (eventType === 'queue.transition') data = await transitionFieldQueue(device, { ...payload, clientEventId, happenedAt: event.happenedAt }, { type: 'device', id: device.id });
        else if (eventType === 'session.open') data = await openFieldSession(device, payload);
        else if (eventType === 'session.events') data = await appendFieldSessionEvents(device, fieldInputString(payload.sessionId, '会话 ID'), payload.events);
        else if (eventType === 'session.complete') data = await completeFieldSession(device, fieldInputString(payload.sessionId, '会话 ID'), payload);
        else throw Object.assign(new Error('同步事件类型不受支持'), { status: 400, code: 'FIELD_SYNC_EVENT_UNSUPPORTED' });
        await query(`INSERT INTO field_sync_events(device_id,client_event_id,event_type,session_id,happened_at,payload_hash)
          VALUES($1,$2,$3,$4,$5,$6)`, [device.id, clientEventId, eventType, data?.id || payload.sessionId || null, fieldIsoDate(event?.happenedAt), payloadHash]);
        outcomes.push({ clientEventId, eventType, data });
      }
      const response = { clientBatchId, accepted: outcomes.length, outcomes };
      await query(`UPDATE field_sync_batches SET status='completed',response_json=$1,completed_at=now() WHERE device_id=$2 AND client_batch_id=$3`, [response, device.id, clientBatchId]);
      return ok(res, response);
    } catch (error) {
      await query(`UPDATE field_sync_batches SET status='failed',response_json=$1,completed_at=now() WHERE device_id=$2 AND client_batch_id=$3`, [{ code: error.code || 'FIELD_SYNC_FAILED', message: error.message }, device.id, clientBatchId]);
      throw error;
    }
  }
  return fail(res, 404, 'FIELD_ROUTE_NOT_FOUND', '场地端接口不存在');
}

