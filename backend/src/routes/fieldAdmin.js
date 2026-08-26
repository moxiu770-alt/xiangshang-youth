/** User-authenticated field administration routes. */
export async function handleFieldAdminRoutes(context) {
  const {
    req, res, user, url, parts, hasRole, fail, fieldInputString, queryValue,
    schoolAllowed, corsOrigin, fieldStreamSubscribers, writeFieldStream, query,
    ok, body, beginIdempotentRequest, requestBodyHash, fieldObject, audit,
    createdIdempotently, fieldReadiness, randomToken, sha256,
    encryptFieldDeviceSigningSecret, fieldDeviceSigningEncryptionKey,
    fieldDeviceKeyExpiresAt, created, pool, teacherOnly, teacherClassIds,
    pagination, normalizeScoreRows, rebalanceFieldQueue, okIdempotently,
    publishFieldUpdate, transitionFieldQueue, fieldIsoDate
  } = context;
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
  if (req.method === 'GET' && url.pathname === '/v1/admin/test-stations') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地测试点');
    const schoolId = queryValue(url, 'schoolId');
    if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校场地测试点');
    const stations = await query(`SELECT s.id,s.school_id AS "schoolId",s.station_code AS "stationCode",s.name,s.item_code AS "itemCode",s.queue_capacity AS "queueCapacity",s.status,
      s.metadata_json AS metadata,s.last_seen_at AS "lastSeenAt",s.updated_at AS "updatedAt",cal.version AS "activeCalibrationVersion",cal.effective_at AS "calibrationEffectiveAt",COUNT(d.id)::int AS "deviceCount",
      COUNT(d.id) FILTER(WHERE d.status='online')::int AS "onlineDeviceCount"
      FROM test_stations s LEFT JOIN test_devices d ON d.station_id=s.id
      LEFT JOIN LATERAL (SELECT version,effective_at FROM station_calibrations WHERE station_id=s.id AND status='active' ORDER BY effective_at DESC LIMIT 1) cal ON TRUE
      WHERE s.school_id=$1 GROUP BY s.id,cal.version,cal.effective_at ORDER BY s.station_code`, [schoolId]);
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
    if (!['online', 'offline', 'maintenance', 'paused', 'disabled'].includes(status)) return fail(res, 400, 'FIELD_STATION_INVALID', '测试点状态不合法');
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
    if (idempotency === false) return;
    const station = await query(`INSERT INTO test_stations(school_id,station_code,name,item_code,queue_capacity,status,metadata_json)
      VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id,school_id AS "schoolId",station_code AS "stationCode",name,item_code AS "itemCode",queue_capacity AS "queueCapacity",status,metadata_json AS metadata`,
    [schoolId, stationCode, name, String(input.itemCode || '').slice(0, 64) || null, queueCapacity, status, fieldObject(input.metadata)]);
    await audit(user, req, 'field.station.create', 'test_station', station.rows[0].id, null, station.rows[0], schoolId);
    return createdIdempotently(res, user, idempotency, station.rows[0]);
  }
  if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-stations' && parts[3]) {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权修改场地测试点');
    const input = await body(req);
    const existing = await query('SELECT * FROM test_stations WHERE id=$1', [parts[3]]);
    const row = existing.rows[0];
    if (!row || !schoolAllowed(user, row.school_id)) return fail(res, 404, 'FIELD_STATION_NOT_FOUND', '场地测试点不存在或无权访问');
    const status = input.status == null ? row.status : String(input.status);
    if (!['online', 'offline', 'maintenance', 'paused', 'disabled'].includes(status)) return fail(res, 400, 'FIELD_STATION_INVALID', '测试点状态不合法');
    const queueCapacity = input.queueCapacity == null ? Number(row.queue_capacity) : Number(input.queueCapacity);
    if (!Number.isInteger(queueCapacity) || queueCapacity < 1 || queueCapacity > 500) return fail(res, 400, 'FIELD_STATION_INVALID', '队列容量必须在 1 到 500 之间');
    const updated = await query(`UPDATE test_stations SET name=$1,item_code=$2,queue_capacity=$3,status=$4,metadata_json=$5,updated_at=now() WHERE id=$6
      RETURNING id,school_id AS "schoolId",station_code AS "stationCode",name,item_code AS "itemCode",queue_capacity AS "queueCapacity",status,metadata_json AS metadata,updated_at AS "updatedAt"`,
    [input.name == null ? row.name : fieldInputString(input.name, '测试点名称', 120), input.itemCode == null ? row.item_code : (String(input.itemCode).slice(0, 64) || null), queueCapacity, status, input.metadata == null ? row.metadata_json : fieldObject(input.metadata), row.id]);
    await audit(user, req, 'field.station.update', 'test_station', row.id, row, updated.rows[0], row.school_id);
    return ok(res, updated.rows[0]);
  }
  if (req.method === 'GET' && url.pathname === '/v1/admin/test-devices') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地设备');
    const schoolId = queryValue(url, 'schoolId');
    if (!schoolId || !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校场地设备');
    const devices = await query(`SELECT d.id,d.school_id AS "schoolId",d.station_id AS "stationId",s.station_code AS "stationCode",s.status AS "stationStatus",d.device_code AS "deviceCode",d.name,d.device_type AS "deviceType",
      d.serial_number AS "serialNumber",d.software_version AS "softwareVersion",d.status,d.capabilities_json AS capabilities,d.health_json AS health,
      d.last_heartbeat_at AS "lastHeartbeatAt",d.api_key_expires_at AS "apiKeyExpiresAt",(d.signing_secret_encrypted IS NOT NULL) AS "signedRequestReady",
      cal.version AS "activeCalibrationVersion",cal."checksumSha256" AS "activeCalibrationChecksumSha256",
      CASE WHEN d.signing_secret_encrypted IS NULL THEN 'rotation_required' WHEN d.api_key_expires_at IS NULL THEN 'legacy_unbounded' WHEN d.api_key_expires_at<=now() THEN 'expired'
        WHEN d.api_key_expires_at<=now()+interval '14 days' THEN 'expiring' ELSE 'valid' END AS "apiKeyStatus",d.updated_at AS "updatedAt"
      FROM test_devices d LEFT JOIN test_stations s ON s.id=d.station_id
      LEFT JOIN LATERAL (SELECT version,checksum_sha256 AS "checksumSha256" FROM station_calibrations WHERE station_id=s.id AND status='active' ORDER BY effective_at DESC LIMIT 1) cal ON TRUE
      WHERE d.school_id=$1 ORDER BY d.device_code`, [schoolId]);
    return ok(res, devices.rows.map((device) => ({
      ...device,
      readiness: fieldReadiness({ ...device, health_json: device.health }, device.stationId ? { id: device.stationId, status: device.stationStatus } : null, device.activeCalibrationVersion ? { version: device.activeCalibrationVersion, checksumSha256: device.activeCalibrationChecksumSha256 } : null)
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
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-devices' && parts[3] && parts[4] === 'rotate-key') {
    if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '无权轮换设备密钥');
    const input = await body(req);
    const row = await query('SELECT * FROM test_devices WHERE id=$1', [parts[3]]);
    if (!row.rows[0] || !schoolAllowed(user, row.rows[0].school_id)) return fail(res, 404, 'FIELD_DEVICE_NOT_FOUND', '场地设备不存在或无权访问');
    const deviceKey = randomToken();
    const result = await query(`UPDATE test_devices SET api_key_hash=$1,signing_secret_encrypted=$2,api_key_expires_at=$3,status='offline',updated_at=now() WHERE id=$4
      RETURNING id,device_code AS "deviceCode",status,api_key_expires_at AS "apiKeyExpiresAt"`, [sha256(deviceKey), encryptFieldDeviceSigningSecret(deviceKey, fieldDeviceSigningEncryptionKey), fieldDeviceKeyExpiresAt(input.apiKeyExpiresAt), parts[3]]);
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
    const sessions = await query(`SELECT s.id,s.client_session_id AS "clientSessionId",s.task_id AS "taskId",t.title AS "taskTitle",s.student_id AS "studentId",st.name AS "studentName",
      s.station_id AS "stationId",station.station_code AS "stationCode",s.edge_device_id AS "deviceId",device.device_code AS "deviceCode",s.attempt_no AS "attemptNo",s.status,
      s.rule_version AS "ruleVersion",s.standard_id AS "standardId",s.standard_version AS "standardVersion",s.calibration_version AS "calibrationVersion",s.algorithm_version AS "algorithmVersion",s.started_at AS "startedAt",s.ended_at AS "endedAt",s.summary_json AS summary
      FROM test_sessions s JOIN assessment_tasks t ON t.id=s.task_id JOIN students st ON st.id=s.student_id LEFT JOIN test_stations station ON station.id=s.station_id
      LEFT JOIN test_devices device ON device.id=s.edge_device_id WHERE s.school_id=$1 AND ($2::text IS NULL OR s.task_id=$2) AND ($3::text IS NULL OR s.station_id=$3) AND ($4::text IS NULL OR s.status=$4)
      AND ($5::text[] IS NULL OR st.class_id=ANY($5)) ORDER BY s.created_at DESC LIMIT $6 OFFSET $7`, [schoolId, queryValue(url, 'taskId') || null, queryValue(url, 'stationId') || null, queryValue(url, 'status') || null, scopedClasses, page.pageSize, page.offset]);
    return ok(res, sessions.rows);
  }
  if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'test-sessions' && parts[3]) {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地测试会话');
    const session = await query(`SELECT s.*,s.standard_id AS "standardId",s.standard_version AS "standardVersion",s.standard_snapshot_json AS "standardSnapshot",st.name AS "studentName",st.class_id,t.title AS "taskTitle",station.station_code AS "stationCode",device.device_code AS "deviceCode"
      FROM test_sessions s JOIN students st ON st.id=s.student_id JOIN assessment_tasks t ON t.id=s.task_id LEFT JOIN test_stations station ON station.id=s.station_id
      LEFT JOIN test_devices device ON device.id=s.edge_device_id WHERE s.id=$1`, [parts[3]]);
    if (!session.rows[0] || !schoolAllowed(user, session.rows[0].school_id)) return fail(res, 404, 'FIELD_SESSION_NOT_FOUND', '测试会话不存在或无权访问');
    if (teacherOnly(user) && !teacherClassIds(user, session.rows[0].school_id).includes(session.rows[0].class_id)) return fail(res, 404, 'FIELD_SESSION_NOT_FOUND', '测试会话不存在或无权访问');
    const [events, evidence, scores] = await Promise.all([
      query(`SELECT client_event_id AS "clientEventId",sequence_no AS "sequenceNo",event_type AS "eventType",happened_at AS "happenedAt",payload_json AS payload FROM session_action_events WHERE session_id=$1 ORDER BY sequence_no`, [parts[3]]),
      query(`SELECT e.id,e.evidence_type AS "evidenceType",e.ordinal,e.checksum_sha256 AS "checksumSha256",e.metadata_json AS metadata,e.file_id AS "fileId",e.retention_until AS "retentionUntil",e.purged_at AS "purgedAt",e.purge_reason AS "purgeReason",f.content_type AS "contentType",f.file_size AS "fileSize" FROM session_evidence e LEFT JOIN files f ON f.id=e.file_id WHERE e.session_id=$1 ORDER BY e.evidence_type,e.ordinal`, [parts[3]]),
      query(`SELECT id,item_code AS item,score,confidence,review_status AS "reviewStatus",note,source,algorithm_version AS "algorithmVersion" FROM assessment_scores WHERE session_id=$1 ORDER BY item_code`, [parts[3]])
    ]);
    return ok(res, { ...session.rows[0], events: events.rows, evidence: evidence.rows, scores: normalizeScoreRows(scores.rows) });
  }
  if (req.method === 'GET' && url.pathname === '/v1/admin/test-queues') {
    if (!hasRole(user, 'admin', 'principal', 'teacher')) return fail(res, 403, 'NO_PERMISSION', '无权查看场地排队');
    const taskId = fieldInputString(queryValue(url, 'taskId'), '任务 ID');
    const task = await query('SELECT school_id FROM assessment_tasks WHERE id=$1', [taskId]);
    if (!task.rows[0] || !schoolAllowed(user, task.rows[0].school_id)) return fail(res, 404, 'FIELD_TASK_NOT_FOUND', '测评任务不存在或无权访问');
    const scopedClasses = teacherOnly(user) ? teacherClassIds(user, task.rows[0].school_id) : null;
    const queues = await query(`SELECT q.id,q.student_id AS "studentId",st.name AS "studentName",c.name AS "className",q.station_id AS "stationId",station.station_code AS "stationCode",q.status,q.priority,q.queue_order AS "queueOrder",q.retest_count AS "retestCount",q.state_version AS "stateVersion",q.note,q.updated_at AS "updatedAt"
      FROM test_queue_entries q JOIN students st ON st.id=q.student_id JOIN classes c ON c.id=st.class_id LEFT JOIN test_stations station ON station.id=q.station_id
      WHERE q.task_id=$1 AND ($2::text IS NULL OR q.station_id=$2) AND ($3::text[] IS NULL OR st.class_id=ANY($3)) ORDER BY q.priority DESC,q.queue_order`, [taskId, queryValue(url, 'stationId') || null, scopedClasses]);
    return ok(res, queues.rows);
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
      const dispatch = await rebalanceFieldQueue(client, row);
      await client.query('COMMIT');
      await audit(user, req, 'field.queue.rebalance', 'assessment_task', row.id, null, dispatch, row.school_id);
      void publishFieldUpdate(row.school_id, 'queue.rebalanced', { taskId: row.id, ...dispatch });
      return okIdempotently(res, user, idempotency, dispatch);
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
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
    const device = await query('SELECT * FROM test_devices WHERE id=$1', [deviceId]);
    if (!device.rows[0] || !schoolAllowed(user, device.rows[0].school_id)) return fail(res, 404, 'FIELD_DEVICE_NOT_FOUND', '场地设备不存在或无权访问');
    const commandType = fieldInputString(input.commandType, '指令类型', 32);
    if (!['pause', 'resume', 'stop', 'call_next', 'recall', 'skip', 'retest', 'refresh_config'].includes(commandType)) return fail(res, 400, 'FIELD_COMMAND_INVALID', '场地指令不合法');
    const command = await query(`INSERT INTO device_commands(school_id,station_id,device_id,command_type,payload_json,issued_by,expires_at)
      VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id,command_type AS "commandType",payload_json AS payload,status,created_at AS "createdAt",expires_at AS "expiresAt"`,
    [device.rows[0].school_id, device.rows[0].station_id, device.rows[0].id, commandType, fieldObject(input.payload), user.id, input.expiresAt ? fieldIsoDate(input.expiresAt) : null]);
    await audit(user, req, 'field.command.create', 'device_command', command.rows[0].id, null, command.rows[0], device.rows[0].school_id);
    void publishFieldUpdate(device.rows[0].school_id, 'command.issued', { commandId: command.rows[0].id, deviceId: device.rows[0].id, stationId: device.rows[0].station_id, commandType });
    return created(res, command.rows[0]);
  }
  return false;
}

