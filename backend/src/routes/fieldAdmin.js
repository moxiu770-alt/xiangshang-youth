/** User-authenticated field administration routes. */
export async function handleFieldAdminRoutes(context) {
  const {
    req, res, user, url, parts, hasRole, fail, fieldInputString, queryValue,
    schoolAllowed, corsOrigin, fieldStreamSubscribers, writeFieldStream, query,
    ok, body, beginIdempotentRequest, requestBodyHash, fieldObject, audit,
    createdIdempotently, fieldReadiness, randomToken, sha256,
    encryptFieldDeviceSigningSecret, fieldDeviceSigningEncryptionKey,
    fieldDeviceKeyExpiresAt, created, pool, teacherOnly, teacherClassIds,
    pagination, normalizeScoreRows, ensureFieldQueue, rebalanceFieldQueue, okIdempotently,
    publishFieldUpdate, transitionFieldQueue, fieldIsoDate, normalizeStationItemCode,
    stationTaskCompatibility
  } = context;
  if (req.method === 'GET' && url.pathname === '/v1/admin/assessment-protocols') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看测试方案');
    const schoolId = fieldInputString(queryValue(url, 'schoolId'), '学校 ID');
    if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校测试方案');
    const protocols = await query(`SELECT protocol.id,protocol.school_id AS "schoolId",protocol.protocol_code AS code,protocol.name,protocol.version,protocol.description,protocol.status,protocol.effective_date::text AS "effectiveDate",
      COALESCE(jsonb_agg(jsonb_build_object('code',item.item_code,'name',item.item_name,'sequenceNo',item.sequence_no,'required',item.required,'sensorProfile',item.sensor_profile_json,'ruleConfig',item.rule_config_json) ORDER BY item.sequence_no) FILTER(WHERE item.id IS NOT NULL),'[]'::jsonb) AS items
      FROM assessment_protocols protocol LEFT JOIN assessment_protocol_items item ON item.protocol_id=protocol.id
      WHERE (protocol.school_id IS NULL OR protocol.school_id=$1) AND protocol.status<>'archived'
      GROUP BY protocol.id ORDER BY CASE WHEN protocol.school_id=$1 THEN 0 ELSE 1 END,protocol.effective_date DESC,protocol.name`, [schoolId]);
    return ok(res, protocols.rows);
  }
  if (req.method === 'GET' && url.pathname === '/v1/admin/field/stream') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权订阅场地实时状态');
    const schoolId = fieldInputString(queryValue(url, 'schoolId'), '学校 ID');
    if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权订阅该学校场地状态');
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-cache, no-transform', Connection: 'keep-alive',
      ...(corsOrigin ? { 'Access-Control-Allow-Origin': corsOrigin } : {})
    });
    res.write(': field realtime connected\n\n');
    const subscribers = fieldStreamSubscribers.get(schoolId) || new Set();
    subscribers.add(res); fieldStreamSubscribers.set(schoolId, subscribers);
    writeFieldStream(res, 'ready', { schoolId, at: new Date().toISOString() });
    const heartbeat = setInterval(() => res.write(': keepalive\n\n'), 25_000);
    req.once('close', () => {
      clearInterval(heartbeat); subscribers.delete(res);
      if (!subscribers.size) fieldStreamSubscribers.delete(schoolId);
    });
    return;
  }
  if (req.method === 'GET' && url.pathname === '/v1/admin/field-sync-conflicts') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地同步冲突');
    const schoolId = fieldInputString(queryValue(url, 'schoolId'), '学校 ID');
    if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校同步冲突');
    const view = String(queryValue(url, 'view') || 'open');
    if (!['open', 'resolved', 'all'].includes(view)) return fail(res, 400, 'FIELD_SYNC_CONFLICT_VIEW_INVALID', '同步冲突分组不合法');
    const page = pagination(url);
    const counts = await query(`SELECT COUNT(*)::int AS "all",
      (COUNT(*) FILTER(WHERE batch.resolution_status='open'))::int AS open,
      (COUNT(*) FILTER(WHERE batch.resolution_status='resolved'))::int AS resolved
      FROM field_sync_batches batch JOIN test_devices device ON device.id=batch.device_id
      WHERE device.school_id=$1 AND batch.status='failed'`, [schoolId]);
    const total = view === 'all' ? Number(counts.rows[0]?.all || 0) : Number(counts.rows[0]?.[view] || 0);
    const resultPage = Math.min(page.page, Math.max(1, Math.ceil(total / page.pageSize)));
    const conflicts = await query(`SELECT batch.id,batch.client_batch_id AS "clientBatchId",batch.event_count AS "eventCount",batch.response_json AS response,
      batch.resolution_status AS "resolutionStatus",batch.resolution_note AS "resolutionNote",batch.received_at AS "receivedAt",batch.completed_at AS "completedAt",
      batch.resolved_at AS "resolvedAt",resolver.name AS "resolvedByName",device.id AS "deviceId",device.device_code AS "deviceCode",device.name AS "deviceName",
      station.id AS "stationId",station.station_code AS "stationCode",station.name AS "stationName",student.id AS "studentId",student.name AS "studentName",student.student_no AS "studentNo"
      FROM field_sync_batches batch JOIN test_devices device ON device.id=batch.device_id
      LEFT JOIN test_stations station ON station.id=device.station_id LEFT JOIN users resolver ON resolver.id=batch.resolved_by
      LEFT JOIN test_queue_entries queue_entry ON queue_entry.id=batch.response_json#>>'{failedEvent,queueEntryId}'
      LEFT JOIN test_sessions failed_session ON failed_session.id=batch.response_json#>>'{failedEvent,sessionId}' OR failed_session.client_session_id=batch.response_json#>>'{failedEvent,clientSessionId}'
      LEFT JOIN students student ON student.id=COALESCE(queue_entry.student_id,failed_session.student_id)
      WHERE device.school_id=$1 AND batch.status='failed' AND ($2='all' OR batch.resolution_status=$2)
      ORDER BY CASE WHEN batch.resolution_status='open' THEN 0 ELSE 1 END,batch.completed_at DESC LIMIT $3 OFFSET $4`,
    [schoolId, view, page.pageSize, (resultPage - 1) * page.pageSize]);
    return ok(res, {
      items: conflicts.rows.map((row) => ({
        ...row,
        code: row.response?.code || 'FIELD_SYNC_FAILED', message: row.response?.message || '同步失败',
        acceptedEventIds: row.response?.acceptedEventIds || [], failedEventId: row.response?.failedEventId || null,
        unprocessedEventIds: row.response?.unprocessedEventIds || [], failedEvent: row.response?.failedEvent || null
      })),
      page: resultPage, pageSize: page.pageSize, total,
      counts: { all: Number(counts.rows[0]?.all || 0), open: Number(counts.rows[0]?.open || 0), resolved: Number(counts.rows[0]?.resolved || 0) }
    });
  }
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'field-sync-conflicts' && parts[3] && parts[4] === 'resolve') {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以确认同步冲突');
    const input = await body(req);
    const note = fieldInputString(input.note, '处理说明', 500);
    const current = await query(`SELECT batch.*,device.school_id,device.device_code FROM field_sync_batches batch
      JOIN test_devices device ON device.id=batch.device_id WHERE batch.id=$1`, [parts[3]]);
    const row = current.rows[0];
    if (!row || !schoolAllowed(user, row.school_id)) return fail(res, 404, 'FIELD_SYNC_CONFLICT_NOT_FOUND', '同步冲突不存在或无权访问');
    if (row.status !== 'failed') return fail(res, 409, 'FIELD_SYNC_CONFLICT_NOT_FAILED', '该同步批次当前不是失败状态');
    if (row.resolution_status === 'resolved') return ok(res, { id: row.id, resolutionStatus: 'resolved', resolutionNote: row.resolution_note, resolvedAt: row.resolved_at, idempotent: true });
    const updated = await query(`UPDATE field_sync_batches SET resolution_status='resolved',resolution_note=$1,resolved_by=$2,resolved_at=now()
      WHERE id=$3 AND status='failed' AND resolution_status='open'
      RETURNING id,client_batch_id AS "clientBatchId",resolution_status AS "resolutionStatus",resolution_note AS "resolutionNote",resolved_at AS "resolvedAt"`, [note, user.id, row.id]);
    if (!updated.rows[0]) return fail(res, 409, 'FIELD_SYNC_CONFLICT_CHANGED', '同步冲突已被其他人员处理，请刷新');
    await audit(user, req, 'field.sync_conflict.resolve', 'field_sync_batch', row.id, { resolutionStatus: row.resolution_status }, updated.rows[0], row.school_id);
    void publishFieldUpdate(row.school_id, 'sync.conflict.resolved', { batchId: row.id, clientBatchId: row.client_batch_id, deviceId: row.device_id });
    return ok(res, updated.rows[0]);
  }
  if (req.method === 'GET' && url.pathname === '/v1/admin/test-stations') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地测试点');
    const schoolId = queryValue(url, 'schoolId');
    if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校场地测试点');
    const stations = await query(`SELECT s.id,s.school_id AS "schoolId",s.station_code AS "stationCode",s.name,s.item_code AS "itemCode",s.queue_capacity AS "queueCapacity",s.status,
      s.status_reason AS "statusReason",s.status_changed_at AS "statusChangedAt",status_actor.name AS "statusChangedByName",s.metadata_json AS metadata,s.last_seen_at AS "lastSeenAt",s.updated_at AS "updatedAt",cal.version AS "activeCalibrationVersion",cal.effective_at AS "calibrationEffectiveAt",COUNT(d.id)::int AS "deviceCount",
      COUNT(d.id) FILTER(WHERE d.status='online')::int AS "onlineDeviceCount"
      FROM test_stations s LEFT JOIN test_devices d ON d.station_id=s.id
      LEFT JOIN users status_actor ON status_actor.id=s.status_changed_by
      LEFT JOIN LATERAL (SELECT version,effective_at FROM station_calibrations WHERE station_id=s.id AND status='active' ORDER BY effective_at DESC LIMIT 1) cal ON TRUE
      WHERE s.school_id=$1 GROUP BY s.id,status_actor.name,cal.version,cal.effective_at ORDER BY s.station_code`, [schoolId]);
    return ok(res, stations.rows);
  }
  if (req.method === 'POST' && url.pathname === '/v1/admin/test-stations') {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权创建场地测试点');
    const input = await body(req);
    const schoolId = fieldInputString(input.schoolId, '学校 ID');
    if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权操作该学校');
    const stationCode = fieldInputString(input.stationCode, '测试点编码', 64);
    const name = fieldInputString(input.name, '测试点名称', 120);
    const queueCapacity = input.queueCapacity == null ? 20 : Number(input.queueCapacity);
    if (!Number.isInteger(queueCapacity) || queueCapacity < 1 || queueCapacity > 500) return fail(res, 400, 'FIELD_STATION_INVALID', '队列容量必须在 1 到 500 之间');
    const status = input.status == null ? 'offline' : String(input.status);
    if (!['offline', 'maintenance', 'paused', 'disabled'].includes(status)) return fail(res, 400, 'FIELD_STATION_INVALID', '新测试点不能手工设为在线；在线状态必须由边缘主机真实心跳产生');
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
    if (idempotency === false) return;
    const station = await query(`INSERT INTO test_stations(school_id,station_code,name,item_code,queue_capacity,status,metadata_json)
      VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id,school_id AS "schoolId",station_code AS "stationCode",name,item_code AS "itemCode",queue_capacity AS "queueCapacity",status,status_reason AS "statusReason",status_changed_at AS "statusChangedAt",metadata_json AS metadata`,
    [schoolId, stationCode, name, normalizeStationItemCode(input.itemCode), queueCapacity, status, fieldObject(input.metadata)]);
    await audit(user, req, 'field.station.create', 'test_station', station.rows[0].id, null, station.rows[0], schoolId);
    return createdIdempotently(res, user, idempotency, station.rows[0]);
  }
  if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-stations' && parts[3]) {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权修改场地测试点');
    const input = await body(req);
    const client = await pool.connect();
    let row;
    let updated;
    let statusChanged = false;
    let reason = '';
    try {
      await client.query('BEGIN');
      const existing = await client.query('SELECT * FROM test_stations WHERE id=$1 FOR UPDATE', [parts[3]]);
      row = existing.rows[0];
      if (!row || !schoolAllowed(user, row.school_id)) throw Object.assign(new Error('场地测试点不存在或无权访问'), { status: 404, code: 'FIELD_STATION_NOT_FOUND' });
      const status = input.status === undefined ? row.status : String(input.status);
      if (input.status !== undefined && !['offline', 'maintenance', 'paused', 'disabled'].includes(status)) throw Object.assign(new Error('测试点只能手动设为离线、维护、暂停或停用；在线状态必须由边缘主机真实心跳产生'), { status: 400, code: 'FIELD_STATION_INVALID' });
      statusChanged = status !== row.status;
      reason = statusChanged ? fieldInputString(input.reason, '状态变更原因', 500) : String(input.reason || '').trim().slice(0, 500);
      const stationCode = input.stationCode === undefined ? row.station_code : fieldInputString(input.stationCode, '测试点编码', 64);
      const queueCapacity = input.queueCapacity == null ? Number(row.queue_capacity) : Number(input.queueCapacity);
      if (!Number.isInteger(queueCapacity) || queueCapacity < 1 || queueCapacity > 500) throw Object.assign(new Error('队列容量必须在 1 到 500 之间'), { status: 400, code: 'FIELD_STATION_INVALID' });
      const nextItemCode = input.itemCode === undefined ? row.item_code : normalizeStationItemCode(input.itemCode);
      const activeQueue = await client.query(`SELECT q.id,q.status,t.title,t.items AS task_items
        FROM test_queue_entries q JOIN assessment_tasks t ON t.id=q.task_id
        WHERE q.station_id=$1 AND q.status=ANY($2::text[]) ORDER BY q.queue_order FOR UPDATE OF q`,
      [row.id, ['waiting', 'called', 'checked_in', 'testing', 'retest', 'paused']]);
      if (queueCapacity < activeQueue.rows.length)
        throw Object.assign(new Error(`队列容量不能低于当前 ${activeQueue.rows.length} 名现场学生`), { status: 409, code: 'FIELD_STATION_CAPACITY_BELOW_LOAD' });
      if (nextItemCode !== row.item_code) {
        const inFlight = activeQueue.rows.filter((item) => ['called', 'checked_in', 'testing', 'paused'].includes(item.status));
        if (inFlight.length)
          throw Object.assign(new Error(`测试点有 ${inFlight.length} 名学生处于叫号、签到或采集中，完成或恢复候测后才能修改测试能力`), { status: 409, code: 'FIELD_STATION_BUSY' });
        const incompatible = activeQueue.rows.find((item) => !stationTaskCompatibility(nextItemCode, item.task_items).compatible);
        if (incompatible)
          throw Object.assign(new Error(`当前候测任务“${incompatible.title}”与新测试能力不兼容，请先重新分流学生`), { status: 409, code: 'FIELD_STATION_QUEUE_INCOMPATIBLE' });
      }
      if (status === 'disabled' && row.status !== 'disabled' && activeQueue.rows.length)
        throw Object.assign(new Error(`测试点仍有 ${activeQueue.rows.length} 名现场学生，不能直接停用；请先重新分流或关闭任务。需要临时停测时请选择“暂停”或“维护”`), { status: 409, code: 'FIELD_STATION_HAS_ACTIVE_QUEUE' });
      const result = await client.query(`UPDATE test_stations SET station_code=$1,name=$2,item_code=$3,queue_capacity=$4,status=$5,metadata_json=$6,
        status_reason=CASE WHEN $7::boolean THEN $8 ELSE status_reason END,status_changed_at=CASE WHEN $7::boolean THEN now() ELSE status_changed_at END,
        status_changed_by=CASE WHEN $7::boolean THEN $9 ELSE status_changed_by END,updated_at=now() WHERE id=$10
        RETURNING id,school_id AS "schoolId",station_code AS "stationCode",name,item_code AS "itemCode",queue_capacity AS "queueCapacity",status,status_reason AS "statusReason",status_changed_at AS "statusChangedAt",metadata_json AS metadata,updated_at AS "updatedAt"`,
      [stationCode, input.name == null ? row.name : fieldInputString(input.name, '测试点名称', 120), nextItemCode, queueCapacity, status, input.metadata == null ? row.metadata_json : fieldObject(input.metadata), statusChanged, reason || null, statusChanged ? user.id : null, row.id]);
      updated = result.rows[0];
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      if (error.code === '23505') throw Object.assign(new Error('该学校已存在相同的测试点编码，请换一个编码'), { status: 409, code: 'FIELD_STATION_CODE_CONFLICT' });
      throw error;
    } finally { client.release(); }
    await audit(user, req, statusChanged ? 'field.station.status_update' : 'field.station.update', 'test_station', row.id, row, { ...updated, reason }, row.school_id);
    void publishFieldUpdate(row.school_id, 'station.updated', { stationId: row.id, stationCode: updated.stationCode, status: updated.status, statusChanged });
    return ok(res, updated);
  }
  if (req.method === 'GET' && url.pathname === '/v1/admin/test-devices') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地设备');
    const schoolId = queryValue(url, 'schoolId');
    if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校场地设备');
    const devices = await query(`SELECT d.id,d.school_id AS "schoolId",d.station_id AS "stationId",s.station_code AS "stationCode",s.status AS "stationStatus",d.device_code AS "deviceCode",d.name,d.device_type AS "deviceType",
      d.serial_number AS "serialNumber",d.software_version AS "softwareVersion",d.status,d.capabilities_json AS capabilities,d.health_json AS health,
      d.control_state AS "controlState",d.control_state_updated_at AS "controlStateUpdatedAt",
      d.last_heartbeat_at AS "lastHeartbeatAt",d.api_key_expires_at AS "apiKeyExpiresAt",(d.signing_secret_encrypted IS NOT NULL) AS "signedRequestReady",
      cal.version AS "activeCalibrationVersion",cal."checksumSha256" AS "activeCalibrationChecksumSha256",
      CASE WHEN d.signing_secret_encrypted IS NULL THEN 'rotation_required' WHEN d.api_key_expires_at IS NULL THEN 'legacy_unbounded' WHEN d.api_key_expires_at<=now() THEN 'expired'
        WHEN d.api_key_expires_at<=now()+interval '14 days' THEN 'expiring' ELSE 'valid' END AS "apiKeyStatus",d.updated_at AS "updatedAt"
      FROM test_devices d LEFT JOIN test_stations s ON s.id=d.station_id
      LEFT JOIN LATERAL (SELECT version,checksum_sha256 AS "checksumSha256" FROM station_calibrations WHERE station_id=s.id AND status='active' ORDER BY effective_at DESC LIMIT 1) cal ON TRUE
      WHERE d.school_id=$1 ORDER BY d.device_code`, [schoolId]);
    return ok(res, devices.rows.map((device) => ({
      ...device,
      readiness: fieldReadiness({ ...device, station_id: device.stationId, device_type: device.deviceType, health_json: device.health }, device.stationId ? { id: device.stationId, status: device.stationStatus } : null, device.activeCalibrationVersion ? { version: device.activeCalibrationVersion, checksumSha256: device.activeCalibrationChecksumSha256 } : null)
    })));
  }
  if (req.method === 'POST' && url.pathname === '/v1/admin/test-devices') {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权注册场地设备');
    const input = await body(req);
    const schoolId = fieldInputString(input.schoolId, '学校 ID');
    if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权操作该学校');
    const deviceType = fieldInputString(input.deviceType, '设备类型', 32);
    if (!['edge_host', 'depth_camera', 'rgb_camera', 'display', 'speaker', 'reader', 'ups', 'network'].includes(deviceType)) return fail(res, 400, 'FIELD_DEVICE_INVALID', '设备类型不合法');
    const stationId = input.stationId ? fieldInputString(input.stationId, '测试点 ID') : null;
    if (stationId) {
      const station = await query('SELECT id FROM test_stations WHERE id=$1 AND school_id=$2', [stationId, schoolId]);
      if (!station.rows[0]) return fail(res, 400, 'FIELD_STATION_NOT_FOUND', '测试点不存在或不属于该学校');
    }
    const deviceKey = randomToken();
    const device = await query(`INSERT INTO test_devices(school_id,station_id,device_code,name,device_type,serial_number,software_version,api_key_hash,signing_secret_encrypted,api_key_expires_at,status,capabilities_json)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'offline',$11)
      RETURNING id,school_id AS "schoolId",station_id AS "stationId",device_code AS "deviceCode",name,device_type AS "deviceType",status,api_key_expires_at AS "apiKeyExpiresAt"`,
    [schoolId, stationId, fieldInputString(input.deviceCode, '设备编码', 64), fieldInputString(input.name, '设备名称', 120), deviceType, String(input.serialNumber || '').slice(0, 120) || null, String(input.softwareVersion || '').slice(0, 120), sha256(deviceKey), encryptFieldDeviceSigningSecret(deviceKey, fieldDeviceSigningEncryptionKey), fieldDeviceKeyExpiresAt(input.apiKeyExpiresAt), fieldObject(input.capabilities)]);
    await audit(user, req, 'field.device.create', 'test_device', device.rows[0].id, null, { ...device.rows[0], apiKeyIssued: true }, schoolId);
    return created(res, { ...device.rows[0], deviceKey });
  }
  if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-devices' && parts[3] && !parts[4]) {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以维护场地设备');
    const input = await body(req);
    const editableFields = ['name', 'deviceCode', 'stationId', 'serialNumber', 'status'];
    if (!editableFields.some((key) => Object.prototype.hasOwnProperty.call(input, key))) return fail(res, 400, 'FIELD_DEVICE_INVALID', '请至少修改一项设备信息');
    const client = await pool.connect();
    let row;
    let updated;
    try {
      await client.query('BEGIN');
      const existing = await client.query('SELECT * FROM test_devices WHERE id=$1 FOR UPDATE', [parts[3]]);
      row = existing.rows[0];
      if (!row || !schoolAllowed(user, row.school_id)) throw Object.assign(new Error('场地设备不存在或无权访问'), { status: 404, code: 'FIELD_DEVICE_NOT_FOUND' });
      const status = input.status === undefined ? row.status : String(input.status);
      if (input.status !== undefined && !['offline', 'maintenance', 'disabled'].includes(status))
        throw Object.assign(new Error('设备只能手动设为离线、维护或停用，在线状态必须由真实心跳产生'), { status: 400, code: 'FIELD_DEVICE_INVALID' });
      const name = input.name === undefined ? row.name : fieldInputString(input.name, '设备名称', 120);
      const deviceCode = input.deviceCode === undefined ? row.device_code : fieldInputString(input.deviceCode, '设备编码', 64);
      const stationId = input.stationId === undefined ? row.station_id : input.stationId == null || String(input.stationId).trim() === '' ? null : fieldInputString(input.stationId, '测试点 ID');
      let serialNumber = row.serial_number;
      if (input.serialNumber !== undefined) {
        serialNumber = input.serialNumber == null ? null : String(input.serialNumber).trim() || null;
        if (serialNumber && serialNumber.length > 120) throw Object.assign(new Error('设备序列号不能超过 120 个字符'), { status: 400, code: 'FIELD_DEVICE_INVALID' });
      }
      if (stationId) {
        const station = await client.query('SELECT id FROM test_stations WHERE id=$1 AND school_id=$2', [stationId, row.school_id]);
        if (!station.rows[0]) throw Object.assign(new Error('测试点不存在或不属于该学校'), { status: 400, code: 'FIELD_STATION_NOT_FOUND' });
      }
      if (stationId !== row.station_id) {
        const activeSession = await client.query(`SELECT id FROM test_sessions WHERE edge_device_id=$1 AND status=ANY($2::text[]) LIMIT 1 FOR UPDATE`, [row.id, ['created', 'checked_in', 'testing']]);
        const activeQueue = row.station_id ? await client.query(`SELECT id FROM test_queue_entries WHERE station_id=$1 AND status=ANY($2::text[]) LIMIT 1 FOR UPDATE`, [row.station_id, ['called', 'checked_in', 'testing', 'paused']]) : { rows: [] };
        const recentlyOnline = row.status === 'online' && row.last_heartbeat_at && Date.now() - new Date(row.last_heartbeat_at).getTime() < 90_000;
        if (activeSession.rows[0] || activeQueue.rows[0]) throw Object.assign(new Error('设备所属测试点正在处理学生，请先结束采集并恢复现场队列后再改绑'), { status: 409, code: 'FIELD_DEVICE_BUSY' });
        if (recentlyOnline) throw Object.assign(new Error('设备刚刚仍在线，请先退出场地端或设为维护，等待心跳停止后再改绑'), { status: 409, code: 'FIELD_DEVICE_ONLINE' });
      }
      const result = await client.query(`UPDATE test_devices SET station_id=$1,device_code=$2,name=$3,serial_number=$4,status=$5,updated_at=now() WHERE id=$6
        RETURNING id,school_id AS "schoolId",station_id AS "stationId",device_code AS "deviceCode",name,device_type AS "deviceType",serial_number AS "serialNumber",software_version AS "softwareVersion",status,updated_at AS "updatedAt"`,
      [stationId, deviceCode, name, serialNumber, status, row.id]);
      updated = result.rows[0];
      if (status === 'disabled') {
        await client.query(`UPDATE device_commands SET status='cancelled' WHERE device_id=$1 AND status IN ('pending','delivered')`, [row.id]);
        if (row.device_type === 'edge_host' && row.station_id) await client.query(`UPDATE test_stations SET status='offline',status_reason='边缘主机已停用，系统自动标记离线',status_changed_at=now(),status_changed_by=$3,updated_at=now()
          WHERE id=$1 AND status='online' AND NOT EXISTS(SELECT 1 FROM test_devices WHERE station_id=$1 AND id<>$2 AND device_type='edge_host' AND status='online')`, [row.station_id, row.id, user.id]);
      }
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      if (error.code === '23505') throw Object.assign(new Error('该学校已存在相同的设备编码，请换一个编码'), { status: 409, code: 'FIELD_DEVICE_CODE_CONFLICT' });
      throw error;
    } finally { client.release(); }
    const metadataChanged = ['name', 'deviceCode', 'stationId', 'serialNumber'].some((key) => Object.prototype.hasOwnProperty.call(input, key));
    await audit(user, req, metadataChanged ? 'field.device.update' : 'field.device.status_update', 'test_device', row.id, row, { ...updated, reason: String(input.reason || '').slice(0, 500) }, row.school_id);
    void publishFieldUpdate(row.school_id, 'device.updated', { deviceId: row.id, stationId: updated.stationId, deviceCode: updated.deviceCode, status: updated.status });
    return ok(res, updated);
  }
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-devices' && parts[3] && parts[4] === 'rotate-key') {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权轮换设备密钥');
    const input = await body(req);
    const row = await query('SELECT * FROM test_devices WHERE id=$1', [parts[3]]);
    if (!row.rows[0] || !schoolAllowed(user, row.rows[0].school_id)) return fail(res, 404, 'FIELD_DEVICE_NOT_FOUND', '场地设备不存在或无权访问');
    const deviceKey = randomToken();
    const result = await query(`UPDATE test_devices SET api_key_hash=$1,signing_secret_encrypted=$2,api_key_expires_at=$3,status='offline',updated_at=now() WHERE id=$4
      RETURNING id,device_code AS "deviceCode",status,api_key_expires_at AS "apiKeyExpiresAt"`, [sha256(deviceKey), encryptFieldDeviceSigningSecret(deviceKey, fieldDeviceSigningEncryptionKey), fieldDeviceKeyExpiresAt(input.apiKeyExpiresAt), parts[3]]);
    if (row.rows[0].device_type === 'edge_host' && row.rows[0].station_id) await query(`UPDATE test_stations SET status='offline',status_reason='边缘主机密钥已轮换，等待使用新密钥重新连接',status_changed_at=now(),status_changed_by=$3,updated_at=now()
      WHERE id=$1 AND status='online' AND NOT EXISTS(SELECT 1 FROM test_devices WHERE station_id=$1 AND id<>$2 AND device_type='edge_host' AND status='online')`, [row.rows[0].station_id, row.rows[0].id, user.id]);
    await audit(user, req, 'field.device.rotate_key', 'test_device', parts[3], null, { deviceKeyRotated: true }, row.rows[0].school_id);
    return ok(res, { ...result.rows[0], deviceKey });
  }
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-stations' && parts[3] && parts[4] === 'calibrations') {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权维护标定配置');
    const input = await body(req);
    const station = await query('SELECT * FROM test_stations WHERE id=$1', [parts[3]]);
    if (!station.rows[0] || !schoolAllowed(user, station.rows[0].school_id)) return fail(res, 404, 'FIELD_STATION_NOT_FOUND', '场地测试点不存在或无权访问');
    const version = fieldInputString(input.version, '标定版本', 64);
    const checksum = fieldInputString(input.checksumSha256, '标定校验和', 128);
    if (!/^[a-f0-9]{64}$/i.test(checksum)) return fail(res, 400, 'FIELD_CALIBRATION_INVALID', '标定校验和必须是 64 位 SHA-256 十六进制值');
    const calibrationConfig = fieldObject(input.config);
    if (!Object.keys(calibrationConfig).length) return fail(res, 400, 'FIELD_CALIBRATION_INVALID', '标定配置不能为空');
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ stationId: parts[3], ...input }));
    if (idempotency === false) return;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      if (input.activate !== false) {
        const activeSession = await client.query(`SELECT id FROM test_sessions WHERE station_id=$1 AND status=ANY($2::text[]) LIMIT 1 FOR UPDATE`, [station.rows[0].id, ['created', 'checked_in', 'testing']]);
        if (activeSession.rows[0]) throw Object.assign(new Error('测试点存在活动采集，结束或安排补测后才能激活新标定'), { status: 409, code: 'FIELD_CALIBRATION_STATION_BUSY' });
      }
      if (input.activate !== false) await client.query(`UPDATE station_calibrations SET status='archived' WHERE station_id=$1 AND status='active'`, [station.rows[0].id]);
      const calibration = await client.query(`INSERT INTO station_calibrations(station_id,version,checksum_sha256,config_json,status,verified_by,verified_at,effective_at)
        VALUES($1,$2,$3,$4,$5,$6,CASE WHEN $5='active' THEN now() ELSE NULL END,now())
        RETURNING id,station_id AS "stationId",version,checksum_sha256 AS "checksumSha256",config_json AS config,status,effective_at AS "effectiveAt"`,
      [station.rows[0].id, version, checksum, calibrationConfig, input.activate === false ? 'draft' : 'active', user.id]);
      await client.query('COMMIT');
      await audit(user, req, 'field.calibration.create', 'station_calibration', calibration.rows[0].id, null, calibration.rows[0], station.rows[0].school_id);
      return createdIdempotently(res, user, idempotency, calibration.rows[0]);
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
  if (req.method === 'GET' && url.pathname === '/v1/admin/test-sessions') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地测试会话');
    const schoolId = queryValue(url, 'schoolId');
    if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校测试会话');
    const page = pagination(url);
    const scopedClasses = teacherOnly(user) ? teacherClassIds(user, schoolId) : null;
    const search = String(queryValue(url, 'search') || '').trim().slice(0, 120);
    const view = String(queryValue(url, 'view') || 'all');
    if (!['attention', 'active', 'completed', 'all'].includes(view)) return fail(res, 400, 'FIELD_SESSION_VIEW_INVALID', '场地会话分组不合法');
    const interruptedActivePredicate = `(s.status IN ('created','checked_in','testing') AND (s.edge_device_id IS NULL OR device.id IS NULL OR device.status<>'online' OR device.last_heartbeat_at IS NULL OR device.last_heartbeat_at<now()-interval '90 seconds' OR device.control_state='stopped'))`;
    const attentionPredicate = `(s.status IN ('needs_review','retest','aborted','sync_conflict') OR ${interruptedActivePredicate} OR (s.status='completed' AND NOT EXISTS (SELECT 1 FROM session_evidence evidence WHERE evidence.session_id=s.id)))`;
    const activePredicate = `s.status IN ('created','checked_in','testing')`;
    const completedPredicate = `(s.status='completed' AND EXISTS (SELECT 1 FROM session_evidence evidence WHERE evidence.session_id=s.id))`;
    const viewPredicate = { attention: attentionPredicate, active: activePredicate, completed: completedPredicate, all: 'TRUE' }[view];
    const baseParameters = [schoolId, queryValue(url, 'taskId') || null, queryValue(url, 'stationId') || null, queryValue(url, 'status') || null, scopedClasses, search];
    const baseFrom = `FROM test_sessions s JOIN assessment_tasks t ON t.id=s.task_id JOIN students st ON st.id=s.student_id LEFT JOIN test_stations station ON station.id=s.station_id LEFT JOIN test_devices device ON device.id=s.edge_device_id`;
    const baseWhere = `WHERE s.school_id=$1 AND ($2::text IS NULL OR s.task_id=$2) AND ($3::text IS NULL OR s.station_id=$3) AND ($4::text IS NULL OR s.status=$4)
      AND ($5::text[] IS NULL OR st.class_id=ANY($5)) AND ($6::text='' OR CONCAT_WS(' ',s.id,s.client_session_id,st.name,st.student_no,t.title,station.station_code,device.device_code) ILIKE '%' || $6 || '%')`;
    const counts = await query(`SELECT COUNT(*)::int AS "all",(COUNT(*) FILTER (WHERE ${attentionPredicate}))::int AS attention,
      (COUNT(*) FILTER (WHERE ${activePredicate}))::int AS active,(COUNT(*) FILTER (WHERE ${completedPredicate}))::int AS completed,
      (COUNT(*) FILTER (WHERE ${viewPredicate}))::int AS "viewTotal" ${baseFrom} ${baseWhere}`, baseParameters);
    const countRow = counts.rows[0] || { all: 0, attention: 0, active: 0, completed: 0, viewTotal: 0 };
    const resultPage = page.paged ? Math.min(page.page, Math.max(1, Math.ceil(Number(countRow.viewTotal || 0) / page.pageSize))) : page.page;
    const sessions = await query(`SELECT s.id,s.client_session_id AS "clientSessionId",s.task_id AS "taskId",t.title AS "taskTitle",s.student_id AS "studentId",st.name AS "studentName",
      s.station_id AS "stationId",station.station_code AS "stationCode",s.edge_device_id AS "deviceId",device.device_code AS "deviceCode",s.attempt_no AS "attemptNo",s.status,
      s.rule_version AS "ruleVersion",s.standard_id AS "standardId",s.standard_version AS "standardVersion",s.calibration_version AS "calibrationVersion",s.algorithm_version AS "algorithmVersion",s.started_at AS "startedAt",s.ended_at AS "endedAt",s.summary_json AS summary,
      device.status AS "deviceStatus",device.last_heartbeat_at AS "deviceLastHeartbeatAt",device.control_state AS "deviceControlState",${interruptedActivePredicate} AS "recoveryEligible",
      (SELECT COUNT(*)::int FROM session_evidence evidence WHERE evidence.session_id=s.id AND evidence.purged_at IS NULL) AS "evidenceCount",
      (SELECT COUNT(*)::int FROM session_evidence evidence WHERE evidence.session_id=s.id) AS "totalEvidenceCount"
      ${baseFrom} ${baseWhere} AND (${viewPredicate}) ORDER BY s.created_at DESC LIMIT $7 OFFSET $8`, [...baseParameters, page.pageSize, (resultPage - 1) * page.pageSize]);
    if (!page.paged) return ok(res, sessions.rows);
    return ok(res, { items: sessions.rows, page: resultPage, pageSize: page.pageSize, total: countRow.viewTotal, counts: { all: countRow.all, attention: countRow.attention, active: countRow.active, completed: countRow.completed } });
  }
  if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-sessions' && parts[3]) {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地测试会话');
    const session = await query(`SELECT s.*,s.standard_id AS "standardId",s.standard_version AS "standardVersion",s.standard_snapshot_json AS "standardSnapshot",st.name AS "studentName",st.student_no AS "studentNo",st.gender,st.birth_date::text AS "birthDate",st.class_id,g.name AS "gradeName",c.name AS "className",t.title AS "taskTitle",station.station_code AS "stationCode",device.device_code AS "deviceCode",device.name AS "deviceName",
      device.status AS "deviceStatus",device.last_heartbeat_at AS "deviceLastHeartbeatAt",device.control_state AS "deviceControlState",
      (s.status IN ('created','checked_in','testing') AND (s.edge_device_id IS NULL OR device.id IS NULL OR device.status<>'online' OR device.last_heartbeat_at IS NULL OR device.last_heartbeat_at<now()-interval '90 seconds' OR device.control_state='stopped')) AS "recoveryEligible"
      FROM test_sessions s JOIN students st ON st.id=s.student_id JOIN grades g ON g.id=st.grade_id JOIN classes c ON c.id=st.class_id JOIN assessment_tasks t ON t.id=s.task_id LEFT JOIN test_stations station ON station.id=s.station_id
      LEFT JOIN test_devices device ON device.id=s.edge_device_id WHERE s.id=$1`, [parts[3]]);
    if (!session.rows[0] || !schoolAllowed(user, session.rows[0].school_id)) return fail(res, 404, 'FIELD_SESSION_NOT_FOUND', '测试会话不存在或无权访问');
    if (teacherOnly(user) && !teacherClassIds(user, session.rows[0].school_id).includes(session.rows[0].class_id)) return fail(res, 404, 'FIELD_SESSION_NOT_FOUND', '测试会话不存在或无权访问');
    const [events, evidence, scores, reviews, itemProgress] = await Promise.all([
      query(`SELECT client_event_id AS "clientEventId",sequence_no AS "sequenceNo",event_type AS "eventType",happened_at AS "happenedAt",payload_json AS payload FROM session_action_events WHERE session_id=$1 ORDER BY sequence_no`, [parts[3]]),
      query(`SELECT e.id,e.evidence_type AS "evidenceType",e.ordinal,e.checksum_sha256 AS "checksumSha256",e.metadata_json AS metadata,e.file_id AS "fileId",e.retention_until AS "retentionUntil",e.purged_at AS "purgedAt",e.purge_reason AS "purgeReason",f.content_type AS "contentType",f.file_size AS "fileSize" FROM session_evidence e LEFT JOIN files f ON f.id=e.file_id WHERE e.session_id=$1 ORDER BY e.evidence_type,e.ordinal`, [parts[3]]),
      query(`SELECT id,item_code AS item,score,confidence,review_status AS "reviewStatus",manual_reviewed AS "humanReviewed",note,source,algorithm_version AS "algorithmVersion" FROM assessment_scores WHERE session_id=$1 ORDER BY item_code`, [parts[3]]),
      query(`SELECT review.id,score.item_code AS item,review.action,review.old_score AS "oldScore",review.new_score AS "newScore",review.reason,review.created_at AS "createdAt",reviewer.name AS "reviewerName"
        FROM score_reviews review JOIN assessment_scores score ON score.id=review.score_id LEFT JOIN users reviewer ON reviewer.id=review.reviewer_id
        WHERE score.session_id=$1 ORDER BY review.created_at,review.id`, [parts[3]]),
      query(`SELECT item_code AS "itemCode",item_name AS "itemName",sequence_no AS "sequenceNo",required,status,attempt_no AS "attemptNo",score,confidence,started_at AS "startedAt",completed_at AS "completedAt",capture_summary_json AS "captureSummary"
        FROM test_session_items WHERE session_id=$1 ORDER BY sequence_no`, [parts[3]])
    ]);
    const activeEvidenceCount = evidence.rows.filter((item) => !item.purgedAt).length;
    return ok(res, { ...session.rows[0], events: events.rows, evidence: evidence.rows, evidenceCount: activeEvidenceCount, totalEvidenceCount: evidence.rowCount, scores: normalizeScoreRows(scores.rows), reviews: reviews.rows, itemProgress: itemProgress.rows });
  }
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-sessions' && parts[3] && parts[4] === 'recover') {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以收口异常中断会话');
    const input = await body(req);
    const reason = fieldInputString(input.reason, '异常恢复说明', 500);
    const scope = await query(`SELECT s.id,s.school_id FROM test_sessions s WHERE s.id=$1`, [parts[3]]);
    if (!scope.rows[0] || !schoolAllowed(user, scope.rows[0].school_id)) return fail(res, 404, 'FIELD_SESSION_NOT_FOUND', '测试会话不存在或无权访问');
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ sessionId: parts[3], reason }));
    if (idempotency === false) return;
    const client = await pool.connect();
    let before;
    let response;
    try {
      await client.query('BEGIN');
      const sessionResult = await client.query(`SELECT s.*,ts.id AS task_student_id FROM test_sessions s
        JOIN task_students ts ON ts.task_id=s.task_id AND ts.student_id=s.student_id WHERE s.id=$1 FOR UPDATE OF s`, [parts[3]]);
      const session = sessionResult.rows[0];
      before = session;
      if (!session || !schoolAllowed(user, session.school_id)) throw Object.assign(new Error('测试会话不存在或无权访问'), { status: 404, code: 'FIELD_SESSION_NOT_FOUND' });
      if (session.status === 'aborted') {
        await client.query('COMMIT');
        response = { id: session.id, status: 'aborted', queueStatus: 'retest', idempotent: true };
      } else {
        if (!['created', 'checked_in', 'testing'].includes(session.status)) throw Object.assign(new Error('只有未结束的现场会话可以进行中断恢复'), { status: 409, code: 'FIELD_SESSION_RECOVERY_STATE_INVALID' });
        let device = null;
        if (session.edge_device_id) {
          const deviceResult = await client.query('SELECT id,name,status,last_heartbeat_at,control_state FROM test_devices WHERE id=$1 FOR UPDATE', [session.edge_device_id]);
          device = deviceResult.rows[0] || null;
        }
        const heartbeatRecent = device?.last_heartbeat_at && Date.now() - new Date(device.last_heartbeat_at).getTime() < 90_000;
        const deviceStillActive = device && device.status === 'online' && heartbeatRecent && device.control_state !== 'stopped';
        if (deviceStillActive) throw Object.assign(new Error(`设备“${device.name || device.id}”仍在线，请先在设备详情中停止现场操作，再收口该会话`), { status: 409, code: 'FIELD_SESSION_DEVICE_ACTIVE' });
        const endedAt = new Date().toISOString();
        const recoveryDeviceState = device ? `${device.status}/${device.control_state || 'running'}` : 'missing';
        await client.query(`UPDATE test_sessions SET status='aborted',ended_at=$1,summary_json=summary_json || jsonb_build_object(
          'abortReason',$2::text,'abortedAt',$1::timestamptz,'recoveredBy',$3::text,'recoverySource','admin','recoveryDeviceState',$4::text),sync_version=sync_version+1,updated_at=now() WHERE id=$5`,
        [endedAt, reason, user.id, recoveryDeviceState, session.id]);
        if (session.queue_entry_id) {
          const queueResult = await client.query('SELECT * FROM test_queue_entries WHERE id=$1 FOR UPDATE', [session.queue_entry_id]);
          const queueEntry = queueResult.rows[0];
          if (queueEntry && queueEntry.status !== 'retest') {
            await client.query(`UPDATE test_queue_entries SET status='retest',retest_count=retest_count+1,completed_at=NULL,note=$1,state_version=state_version+1,updated_at=now() WHERE id=$2`, [reason, queueEntry.id]);
            await client.query(`INSERT INTO queue_events(queue_entry_id,old_status,new_status,reason,actor_type,actor_id,station_id,happened_at)
              VALUES($1,$2,'retest',$3,'admin',$4,$5,$6)`, [queueEntry.id, queueEntry.status, reason, user.id, queueEntry.station_id, endedAt]);
          }
        }
        await client.query(`UPDATE task_students SET status='待补测',completed_at=NULL,note=$1,version=version+1 WHERE id=$2`, [reason, session.task_student_id]);
        await client.query('COMMIT');
        response = { id: session.id, status: 'aborted', queueStatus: 'retest', reason, recoveredAt: endedAt };
      }
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    if (!response.idempotent) {
      await audit(user, req, 'field.session.recover', 'test_session', parts[3], before, response, scope.rows[0].school_id);
      void publishFieldUpdate(scope.rows[0].school_id, 'session.recovered', { sessionId: parts[3], status: 'aborted', queueStatus: 'retest' });
    }
    return okIdempotently(res, user, idempotency, response);
  }
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-sessions' && parts[3] && parts[4] === 'review') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权复核场地测试会话');
    const input = await body(req);
    const action = String(input.action || '');
    if (!['approve', 'retest'].includes(action)) return fail(res, 400, 'FIELD_SESSION_REVIEW_INVALID', '复核动作仅支持确认成绩或安排补测');
    const reason = String(input.reason || '').trim().slice(0, 1000);
    if (action === 'retest' && !reason) return fail(res, 400, 'FIELD_SESSION_REVIEW_REASON_REQUIRED', '安排补测必须填写原因');
    const corrections = Array.isArray(input.scores) ? input.scores : [];
    if (corrections.length > 7) return fail(res, 400, 'FIELD_SESSION_REVIEW_INVALID', '复核成绩数量超过上限');
    const correctionMap = new Map();
    for (const item of corrections) {
      const scoreId = fieldInputString(item?.scoreId, '成绩 ID');
      const score = Number(item?.score);
      if (!Number.isFinite(score) || score < 0 || score > 5) return fail(res, 400, 'FIELD_SESSION_REVIEW_INVALID', '复核成绩必须在 0 到 5 之间');
      if (correctionMap.has(scoreId)) return fail(res, 400, 'FIELD_SESSION_REVIEW_INVALID', '同一成绩不能重复修正');
      correctionMap.set(scoreId, score);
    }
    if (action !== 'approve' && correctionMap.size) return fail(res, 400, 'FIELD_SESSION_REVIEW_INVALID', '安排补测时不能同时修改成绩');
    const scope = await query(`SELECT s.id,s.school_id,st.class_id FROM test_sessions s JOIN students st ON st.id=s.student_id WHERE s.id=$1`, [parts[3]]);
    if (!scope.rows[0] || !schoolAllowed(user, scope.rows[0].school_id)) return fail(res, 404, 'FIELD_SESSION_NOT_FOUND', '测试会话不存在或无权访问');
    if (teacherOnly(user) && !teacherClassIds(user, scope.rows[0].school_id).includes(scope.rows[0].class_id)) return fail(res, 403, 'NO_PERMISSION', '教师只能复核所负责班级');
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ sessionId: parts[3], action, reason, scores: corrections }));
    if (idempotency === false) return;
    const client = await pool.connect();
    let before;
    let response;
    try {
      await client.query('BEGIN');
      const sessionResult = await client.query(`SELECT s.*,st.class_id FROM test_sessions s JOIN students st ON st.id=s.student_id WHERE s.id=$1 FOR UPDATE OF s`, [parts[3]]);
      const session = sessionResult.rows[0];
      before = session;
      if (!session || !schoolAllowed(user, session.school_id)) throw Object.assign(new Error('测试会话不存在或无权访问'), { status: 404, code: 'FIELD_SESSION_NOT_FOUND' });
      if (action === 'approve' && session.status !== 'needs_review') throw Object.assign(new Error('只有待复核会话可以确认成绩'), { status: 409, code: 'FIELD_SESSION_REVIEW_STATE_INVALID' });
      if (action === 'retest' && !['needs_review', 'completed'].includes(session.status)) throw Object.assign(new Error('当前会话不能安排补测'), { status: 409, code: 'FIELD_SESSION_REVIEW_STATE_INVALID' });
      const scores = await client.query(`SELECT id,score,review_status FROM assessment_scores WHERE session_id=$1 ORDER BY item_code FOR UPDATE`, [session.id]);
      if (!scores.rowCount) throw Object.assign(new Error('会话没有可复核成绩'), { status: 409, code: 'FIELD_SESSION_SCORES_MISSING' });
      const sessionScoreIds = new Set(scores.rows.map((item) => item.id));
      if ([...correctionMap.keys()].some((id) => !sessionScoreIds.has(id))) throw Object.assign(new Error('修正项不属于当前会话'), { status: 400, code: 'FIELD_SESSION_REVIEW_INVALID' });
      if (action === 'approve') {
        const evidence = await client.query('SELECT COUNT(*)::int AS count FROM session_evidence WHERE session_id=$1 AND purged_at IS NULL', [session.id]);
        if (Number(evidence.rows[0]?.count || 0) === 0) throw Object.assign(new Error('会话没有可复核证据，不能直接确认成绩，请安排补测'), { status: 409, code: 'FIELD_SESSION_EVIDENCE_REQUIRED' });
      }
      let correctedScoreCount = 0;
      for (const score of scores.rows) {
        const newScore = correctionMap.has(score.id) ? correctionMap.get(score.id) : Number(score.score);
        if (newScore !== Number(score.score) && !reason) throw Object.assign(new Error('修改成绩时必须填写复核说明'), { status: 400, code: 'FIELD_SESSION_REVIEW_REASON_REQUIRED' });
        if (newScore !== Number(score.score)) correctedScoreCount += 1;
        if (action === 'approve') await client.query(`UPDATE assessment_scores SET score=$1,review_status='passed',manual_reviewed=TRUE,updated_at=now() WHERE id=$2`, [newScore, score.id]);
        await client.query(`INSERT INTO score_reviews(score_id,reviewer_id,action,old_score,new_score,reason) VALUES($1,$2,$3,$4,$5,$6)`, [score.id, user.id, action, score.score, newScore, reason]);
      }
      const nextStatus = action === 'approve' ? 'completed' : 'retest';
      await client.query(`UPDATE test_sessions SET status=$1,summary_json=summary_json || jsonb_build_object('reviewedAt',now(),'reviewedBy',$2::text,'reviewAction',$3::text,'reviewReason',$4::text),sync_version=sync_version+1,updated_at=now() WHERE id=$5`, [nextStatus, user.id, action, reason, session.id]);
      if (session.queue_entry_id) {
        const queue = await client.query('SELECT * FROM test_queue_entries WHERE id=$1 FOR UPDATE', [session.queue_entry_id]);
        const queueRow = queue.rows[0];
        if (queueRow && action === 'retest' && queueRow.status !== 'retest') {
          await client.query(`UPDATE test_queue_entries SET status='retest',retest_count=retest_count+1,completed_at=NULL,note=$1,state_version=state_version+1,updated_at=now() WHERE id=$2`, [reason, queueRow.id]);
          await client.query(`INSERT INTO queue_events(queue_entry_id,old_status,new_status,reason,actor_type,actor_id,station_id,happened_at) VALUES($1,$2,'retest',$3,$4,$5,$6,now())`, [queueRow.id, queueRow.status, reason, hasRole(user, 'admin', 'principal') ? 'admin' : 'teacher', user.id, queueRow.station_id]);
        }
      }
      await client.query(`UPDATE task_students SET status=$1,completed_at=CASE WHEN $1='已完成' THEN COALESCE(completed_at,now()) ELSE NULL END,note=COALESCE(NULLIF($2,''),note),version=version+1 WHERE task_id=$3 AND student_id=$4`, [action === 'approve' ? '已完成' : '待补测', reason, session.task_id, session.student_id]);
      if (action === 'approve') await client.query(`INSERT INTO job_queue(job_type,payload,available_at) VALUES('report.refresh',$1,now())`, [{ studentId: session.student_id, taskId: session.task_id, sessionId: session.id, schoolId: session.school_id }]);
      await client.query('COMMIT');
      response = { id: session.id, status: nextStatus, reviewedScores: scores.rowCount, correctedScores: correctedScoreCount, reason };
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    await audit(user, req, 'field.session.review', 'test_session', parts[3], before, response, scope.rows[0].school_id);
    void publishFieldUpdate(scope.rows[0].school_id, 'session.reviewed', { sessionId: parts[3], status: response.status, action });
    return okIdempotently(res, user, idempotency, response);
  }
  if (req.method === 'GET' && url.pathname === '/v1/admin/test-queues') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地排队');
    const taskId = fieldInputString(queryValue(url, 'taskId'), '任务 ID');
    const task = await query('SELECT school_id FROM assessment_tasks WHERE id=$1', [taskId]);
    if (!task.rows[0] || !schoolAllowed(user, task.rows[0].school_id)) return fail(res, 404, 'FIELD_TASK_NOT_FOUND', '测评任务不存在或无权访问');
    const scopedClasses = teacherOnly(user) ? teacherClassIds(user, task.rows[0].school_id) : null;
    const queues = await query(`SELECT q.id,q.student_id AS "studentId",st.name AS "studentName",st.student_no AS "studentNo",st.gender,st.birth_date::text AS "birthDate",g.name AS "gradeName",c.name AS "className",q.station_id AS "stationId",station.station_code AS "stationCode",station.name AS "stationName",q.status,q.priority,q.queue_order AS "queueOrder",q.retest_count AS "retestCount",q.state_version AS "stateVersion",q.note,q.last_called_at AS "lastCalledAt",q.updated_at AS "updatedAt",
      active_session.id AS "activeSessionId",active_session.started_at AS "captureStartedAt",active_session.event_count AS "captureEventCount",active_session.last_event_at AS "lastCaptureEventAt",
      latest_event.event_type AS "latestCaptureEventType",latest_event.payload_json AS "latestCapturePayload",
      GREATEST(0,FLOOR(EXTRACT(EPOCH FROM (now()-COALESCE(CASE WHEN q.status='called' THEN q.last_called_at END,q.updated_at)))))::int AS "stateAgeSeconds",
      (q.status='called' AND q.last_called_at IS NOT NULL AND q.last_called_at<now()-interval '2 minutes') AS "calledOverdue",
      CASE WHEN q.status='called' AND q.last_called_at IS NOT NULL AND q.last_called_at<now()-interval '2 minutes' THEN 'critical'
        WHEN q.status IN ('waiting','retest') AND q.updated_at<now()-interval '30 minutes' THEN 'critical'
        WHEN q.status IN ('waiting','retest') AND q.updated_at<now()-interval '15 minutes' THEN 'warning'
        ELSE 'normal' END AS "timingSeverity"
      FROM test_queue_entries q JOIN students st ON st.id=q.student_id JOIN grades g ON g.id=st.grade_id JOIN classes c ON c.id=st.class_id LEFT JOIN test_stations station ON station.id=q.station_id
      LEFT JOIN LATERAL (SELECT session.id,session.started_at,
        (SELECT COUNT(*)::int FROM session_action_events event WHERE event.session_id=session.id) AS event_count,
        (SELECT MAX(event.happened_at) FROM session_action_events event WHERE event.session_id=session.id) AS last_event_at
        FROM test_sessions session WHERE session.queue_entry_id=q.id AND session.status IN ('created','checked_in','testing')
        ORDER BY session.attempt_no DESC,session.created_at DESC LIMIT 1) active_session ON TRUE
      LEFT JOIN LATERAL (SELECT event.event_type,event.payload_json,event.happened_at FROM session_action_events event
        WHERE event.session_id=active_session.id ORDER BY event.sequence_no DESC,event.happened_at DESC LIMIT 1) latest_event ON TRUE
      WHERE q.task_id=$1 AND ($2::text IS NULL OR q.station_id=$2) AND ($3::text[] IS NULL OR st.class_id=ANY($3)) ORDER BY q.priority DESC,q.queue_order`, [taskId, queryValue(url, 'stationId') || null, scopedClasses]);
    return ok(res, queues.rows);
  }
  if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-queues' && parts[3] && parts[4] === 'history') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看学生现场记录');
    const queue = await query(`SELECT q.id,q.task_id AS "taskId",q.student_id AS "studentId",q.station_id AS "stationId",q.status,q.priority,q.queue_order AS "queueOrder",q.retest_count AS "retestCount",q.state_version AS "stateVersion",q.note,q.last_called_at AS "lastCalledAt",q.completed_at AS "completedAt",q.created_at AS "createdAt",q.updated_at AS "updatedAt",
      t.school_id AS "schoolId",t.title AS "taskTitle",t.test_date::text AS "testDate",st.class_id AS "classId",st.name AS "studentName",st.student_no AS "studentNo",st.gender,st.birth_date::text AS "birthDate",c.name AS "className",g.name AS "gradeName",station.station_code AS "stationCode",station.name AS "stationName"
      FROM test_queue_entries q JOIN assessment_tasks t ON t.id=q.task_id JOIN students st ON st.id=q.student_id JOIN classes c ON c.id=st.class_id JOIN grades g ON g.id=st.grade_id
      LEFT JOIN test_stations station ON station.id=q.station_id WHERE q.id=$1`, [parts[3]]);
    const row = queue.rows[0];
    if (!row || !schoolAllowed(user, row.schoolId)) return fail(res, 404, 'FIELD_QUEUE_NOT_FOUND', '队列记录不存在或无权访问');
    if (teacherOnly(user) && !teacherClassIds(user, row.schoolId).includes(row.classId)) return fail(res, 403, 'NO_PERMISSION', '教师只能查看所负责班级');
    const [events, sessions] = await Promise.all([
      query(`SELECT event.id,event.old_status AS "oldStatus",event.new_status AS "newStatus",event.reason,event.actor_type AS "actorType",event.actor_id AS "actorId",event.happened_at AS "happenedAt",event.created_at AS "createdAt",
        COALESCE(actor.name,device.name,CASE event.actor_type WHEN 'system' THEN '中央系统' WHEN 'admin' THEN '管理员' WHEN 'teacher' THEN '教师' ELSE '场地设备' END) AS "actorName",
        station.station_code AS "stationCode",station.name AS "stationName"
        FROM queue_events event LEFT JOIN users actor ON actor.id=event.actor_id AND event.actor_type IN ('admin','teacher')
        LEFT JOIN test_devices device ON device.id=event.actor_id AND event.actor_type='device' LEFT JOIN test_stations station ON station.id=event.station_id
        WHERE event.queue_entry_id=$1 ORDER BY event.happened_at DESC,event.created_at DESC LIMIT 100`, [row.id]),
      query(`SELECT session.id,session.status,session.attempt_no AS "attemptNo",session.started_at AS "startedAt",session.ended_at AS "endedAt",session.algorithm_version AS "algorithmVersion",session.calibration_version AS "calibrationVersion",session.summary_json AS summary,
        station.station_code AS "stationCode",device.name AS "deviceName",
        (SELECT COUNT(*)::int FROM session_evidence evidence WHERE evidence.session_id=session.id AND evidence.purged_at IS NULL) AS "evidenceCount",
        (SELECT COUNT(*)::int FROM assessment_scores score WHERE score.session_id=session.id) AS "scoreCount"
        FROM test_sessions session LEFT JOIN test_stations station ON station.id=session.station_id LEFT JOIN test_devices device ON device.id=session.edge_device_id
        WHERE session.task_id=$1 AND session.student_id=$2 ORDER BY session.attempt_no DESC,session.created_at DESC LIMIT 50`, [row.taskId, row.studentId])
    ]);
    return ok(res, { queue: row, events: events.rows, sessions: sessions.rows });
  }
  if (req.method === 'POST' && url.pathname === '/v1/admin/test-queues/rebalance') {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以重新分流场地队列');
    const input = await body(req);
    const taskId = fieldInputString(input.taskId, '任务 ID');
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ action: 'field.queue.rebalance', taskId }));
    if (idempotency === false) return;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const task = await client.query(`SELECT * FROM assessment_tasks WHERE id=$1 FOR UPDATE`, [taskId]);
      const row = task.rows[0];
      if (!row || !schoolAllowed(user, row.school_id)) throw Object.assign(new Error('测评任务不存在或无权操作'), { status: 404, code: 'FIELD_TASK_NOT_FOUND' });
      if (row.status !== 'published') throw Object.assign(new Error('只有已发布的任务可以分流'), { status: 409, code: 'FIELD_TASK_INACTIVE' });
      await ensureFieldQueue(client, { school_id: row.school_id }, taskId);
      const dispatch = await rebalanceFieldQueue(client, row);
      await client.query('COMMIT');
      await audit(user, req, 'field.queue.rebalance', 'assessment_task', row.id, null, dispatch, row.school_id);
      void publishFieldUpdate(row.school_id, 'queue.rebalanced', { taskId: row.id, ...dispatch });
      return okIdempotently(res, user, idempotency, dispatch);
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-queues' && parts[3] && parts[4] === 'assign') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权调整学生测试点');
    const input = await body(req);
    const stationId = fieldInputString(input.stationId, '目标测试点 ID');
    const expectedVersion = Number(input.expectedVersion);
    const reason = fieldInputString(input.reason, '换点原因', 500);
    if (!Number.isInteger(expectedVersion) || expectedVersion < 1) return fail(res, 400, 'FIELD_QUEUE_VERSION_INVALID', '队列版本不合法');
    const client = await pool.connect();
    let before;
    let reassigned;
    try {
      await client.query('BEGIN');
      const current = await client.query(`SELECT q.*,t.school_id,t.status AS task_status,t.items AS task_items,st.class_id,st.name AS student_name,source.station_code AS source_station_code,source.name AS source_station_name
        FROM test_queue_entries q JOIN assessment_tasks t ON t.id=q.task_id JOIN students st ON st.id=q.student_id
        LEFT JOIN test_stations source ON source.id=q.station_id WHERE q.id=$1 FOR UPDATE OF q`, [parts[3]]);
      const row = current.rows[0];
      if (!row || !schoolAllowed(user, row.school_id)) throw Object.assign(new Error('队列记录不存在或无权访问'), { status: 404, code: 'FIELD_QUEUE_NOT_FOUND' });
      if (teacherOnly(user) && !teacherClassIds(user, row.school_id).includes(row.class_id)) throw Object.assign(new Error('教师只能调整所负责班级'), { status: 403, code: 'NO_PERMISSION' });
      if (row.task_status !== 'published') throw Object.assign(new Error('只有已发布任务的候测学生可以调整测试点'), { status: 409, code: 'FIELD_TASK_INACTIVE' });
      if (!['waiting', 'retest'].includes(row.status)) throw Object.assign(new Error('学生已进入叫号或测试流程，不能再更换测试点'), { status: 409, code: 'FIELD_QUEUE_ASSIGNMENT_LOCKED' });
      if (Number(row.state_version) !== expectedVersion) throw Object.assign(new Error('队列已被其他终端更新，请刷新后重试'), { status: 409, code: 'FIELD_QUEUE_VERSION_CONFLICT' });
      if (row.station_id === stationId) throw Object.assign(new Error('学生已在该测试点，无需重复调整'), { status: 409, code: 'FIELD_QUEUE_ALREADY_ASSIGNED' });

      const stationResult = await client.query(`SELECT s.*,cal.version AS calibration_version,cal.checksum_sha256 AS calibration_checksum_sha256
        FROM test_stations s LEFT JOIN LATERAL (
          SELECT version,checksum_sha256 FROM station_calibrations WHERE station_id=s.id AND status='active' ORDER BY effective_at DESC LIMIT 1
        ) cal ON TRUE WHERE s.id=$1 FOR UPDATE OF s`, [stationId]);
      const station = stationResult.rows[0];
      if (!station || station.school_id !== row.school_id) throw Object.assign(new Error('目标测试点不存在或不属于当前学校'), { status: 404, code: 'FIELD_STATION_NOT_FOUND' });
      const compatibility = stationTaskCompatibility(station.item_code, row.task_items);
      if (!compatibility.compatible) throw Object.assign(new Error(`目标测试点不能承接当前任务：${compatibility.reason}`), { status: 409, code: 'FIELD_STATION_TASK_MISMATCH' });
      const devices = await client.query(`SELECT * FROM test_devices WHERE station_id=$1 AND device_type='edge_host' AND status='online' ORDER BY last_heartbeat_at DESC NULLS LAST,id`, [station.id]);
      const calibration = station.calibration_version ? { version: station.calibration_version, checksumSha256: station.calibration_checksum_sha256 } : null;
      const readyDevice = devices.rows.find((device) => fieldReadiness(device, station, calibration).ready);
      if (!readyDevice) throw Object.assign(new Error('目标测试点尚未通过开测检查，请先处理设备、自检和标定'), { status: 409, code: 'FIELD_STATION_NOT_READY' });

      const activeStatuses = ['waiting', 'called', 'checked_in', 'testing', 'retest', 'paused'];
      const loadResult = await client.query(`SELECT COUNT(*)::int AS count,COALESCE(MAX(queue_order),0)::int AS max_order
        FROM test_queue_entries WHERE task_id=$1 AND station_id=$2 AND id<>$3 AND status=ANY($4::text[])`, [row.task_id, station.id, row.id, activeStatuses]);
      const destinationLoad = Number(loadResult.rows[0]?.count || 0);
      if (destinationLoad >= Number(station.queue_capacity)) throw Object.assign(new Error(`目标测试点队列已满（${destinationLoad}/${station.queue_capacity}）`), { status: 409, code: 'FIELD_STATION_QUEUE_FULL' });
      const queueOrder = Number(loadResult.rows[0]?.max_order || 0) + 1;
      const updated = await client.query(`UPDATE test_queue_entries SET station_id=$1,queue_order=$2,state_version=state_version+1,updated_at=now()
        WHERE id=$3 RETURNING id,task_id AS "taskId",student_id AS "studentId",station_id AS "stationId",status,priority,queue_order AS "queueOrder",retest_count AS "retestCount",state_version AS "stateVersion",note,updated_at AS "updatedAt"`,
      [station.id, queueOrder, row.id]);
      before = { id: row.id, schoolId: row.school_id, taskId: row.task_id, studentId: row.student_id, studentName: row.student_name, stationId: row.station_id, stationCode: row.source_station_code, stationName: row.source_station_name, status: row.status, queueOrder: row.queue_order, stateVersion: row.state_version };
      reassigned = { ...updated.rows[0], studentName: row.student_name, stationCode: station.station_code, stationName: station.name, previousStationId: row.station_id, previousStationCode: row.source_station_code, reason, destinationLoad: destinationLoad + 1, queueCapacity: Number(station.queue_capacity) };
      const eventReason = `换点：${row.source_station_code || '待分配'} → ${station.station_code}；${reason}`.slice(0, 500);
      await client.query(`INSERT INTO queue_events(queue_entry_id,old_status,new_status,reason,actor_type,actor_id,station_id,happened_at)
        VALUES($1,$2,$2,$3,$4,$5,$6,now())`, [row.id, row.status, eventReason, hasRole(user, 'admin', 'principal') ? 'admin' : 'teacher', user.id, station.id]);
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    await audit(user, req, 'field.queue.assign', 'test_queue_entry', reassigned.id, before, reassigned, before.schoolId);
    void publishFieldUpdate(before.schoolId, 'queue.assigned', { queueEntryId: reassigned.id, taskId: reassigned.taskId, studentId: reassigned.studentId, previousStationId: reassigned.previousStationId, stationId: reassigned.stationId, stationCode: reassigned.stationCode, status: reassigned.status, stateVersion: Number(reassigned.stateVersion) });
    return ok(res, reassigned);
  }
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-queues' && parts[3] && parts[4] === 'transition') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权调度场地队列');
    const input = await body(req);
    const queueSchool = await query(`SELECT t.school_id,st.class_id FROM test_queue_entries q JOIN assessment_tasks t ON t.id=q.task_id JOIN students st ON st.id=q.student_id WHERE q.id=$1`, [parts[3]]);
    if (!queueSchool.rows[0] || !schoolAllowed(user, queueSchool.rows[0].school_id)) return fail(res, 404, 'FIELD_QUEUE_NOT_FOUND', '队列记录不存在或无权访问');
    if (teacherOnly(user) && !teacherClassIds(user, queueSchool.rows[0].school_id).includes(queueSchool.rows[0].class_id)) return fail(res, 403, 'NO_PERMISSION', '教师只能调度所负责班级');
    return ok(res, await transitionFieldQueue({ school_id: queueSchool.rows[0].school_id, station_id: input.stationId || null }, { ...input, queueEntryId: parts[3] }, { type: hasRole(user, 'admin', 'principal') ? 'admin' : 'teacher', id: user.id }));
  }
  if (req.method === 'POST' && url.pathname === '/v1/admin/device-commands') {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以下发设备级指令');
    const input = await body(req);
    const deviceId = fieldInputString(input.deviceId, '设备 ID');
    const commandType = fieldInputString(input.commandType, '指令类型', 32);
    if (!['pause', 'resume', 'stop', 'call_next', 'recall', 'skip', 'retest', 'refresh_config'].includes(commandType)) return fail(res, 400, 'FIELD_COMMAND_INVALID', '场地指令不合法');
    const payload = fieldObject(input.payload);
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ deviceId, commandType, payload, expiresAt: input.expiresAt || null }));
    if (idempotency === false) return;
    const client = await pool.connect();
    let device;
    let command;
    try {
      await client.query('BEGIN');
      const deviceResult = await client.query('SELECT * FROM test_devices WHERE id=$1 FOR UPDATE', [deviceId]);
      device = deviceResult.rows[0];
      if (!device || !schoolAllowed(user, device.school_id)) throw Object.assign(new Error('场地设备不存在或无权访问'), { status: 404, code: 'FIELD_DEVICE_NOT_FOUND' });
      if (device.status === 'disabled') throw Object.assign(new Error('已停用设备不能接收控制指令'), { status: 409, code: 'FIELD_DEVICE_DISABLED' });
      if (commandType === 'recall') {
        const queueEntryId = fieldInputString(payload.queueEntryId, '队列记录 ID');
        const queueResult = await client.query(`SELECT q.id,q.status,q.station_id,t.school_id
          FROM test_queue_entries q JOIN assessment_tasks t ON t.id=q.task_id WHERE q.id=$1 FOR UPDATE`, [queueEntryId]);
        const queueEntry = queueResult.rows[0];
        if (!queueEntry || queueEntry.school_id !== device.school_id || queueEntry.station_id !== device.station_id)
          throw Object.assign(new Error('只能提醒分配到该设备测试点的学生'), { status: 409, code: 'FIELD_RECALL_STATION_MISMATCH' });
        if (queueEntry.status !== 'called')
          throw Object.assign(new Error('只有已叫号、尚未签到的学生可以再次提醒'), { status: 409, code: 'FIELD_RECALL_STATUS_INVALID' });
      }
      const nextControlState = { pause: 'paused', stop: 'stopped', resume: 'running' }[commandType] || null;
      if (nextControlState) {
        await client.query(`UPDATE device_commands SET status='cancelled' WHERE device_id=$1 AND command_type IN ('pause','stop','resume') AND status='pending'`, [device.id]);
        await client.query('UPDATE test_devices SET control_state=$1,control_state_updated_at=now(),updated_at=now() WHERE id=$2', [nextControlState, device.id]);
      }
      const inserted = await client.query(`INSERT INTO device_commands(school_id,station_id,device_id,command_type,payload_json,issued_by,expires_at)
        VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id,command_type AS "commandType",payload_json AS payload,status,created_at AS "createdAt",expires_at AS "expiresAt"`,
      [device.school_id, device.station_id, device.id, commandType, payload, user.id, input.expiresAt ? fieldIsoDate(input.expiresAt) : null]);
      command = { ...inserted.rows[0], controlState: nextControlState || device.control_state || 'running' };
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    await audit(user, req, 'field.command.create', 'device_command', command.id, null, command, device.school_id);
    void publishFieldUpdate(device.school_id, 'command.issued', { commandId: command.id, deviceId: device.id, stationId: device.station_id, commandType, controlState: command.controlState });
    return createdIdempotently(res, user, idempotency, command);
  }
  return false;
}
