import crypto from 'node:crypto';
import { config } from './config.js';
import { pool, query } from './db.js';
import { logger, recordMetric } from './observability.js';
import { MOVEMENT_ITEM_CODES, MOVEMENT_SCORE_RULES, normalizeConfidence, normalizeReviewStatus, normalizeScore } from './scoring.js';
import { normalizeStationItemCode, scoreScopeDifference, stationTaskCompatibility } from './fieldTaskScope.js';
import { protocolSnapshotFromTask, resolveAssessmentProtocol } from './assessmentProtocols.js';
import { fieldReadiness } from './fieldReadiness.js';
import { resolveAssessmentStandard } from './assessmentStandards.js';
import { dateOnlyText } from './dateOnly.js';

const { fieldDeviceOfflineAfterSeconds, fieldEvidenceVideoRetentionDays, fieldEvidenceDerivedRetentionDays } = config;
const evaluateFieldReadiness = (device, station, calibration, options = {}) => fieldReadiness(device, station, calibration, { ...options, heartbeatMaxAgeSeconds: fieldDeviceOfflineAfterSeconds });
const canonicalize = (value) => Array.isArray(value)
  ? `[${value.map(canonicalize).join(',')}]`
  : value && typeof value === 'object'
    ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalize(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const requestBodyHash = (value) => crypto.createHash('sha256').update(canonicalize(value)).digest('hex');
let publishUpdate = async () => {};
let writeAudit = async () => {};
export function configureFieldSessionService({ publishFieldUpdate, audit }) {
  publishUpdate = publishFieldUpdate;
  writeAudit = audit;
}
const publishFieldUpdate = (...args) => publishUpdate(...args);
const audit = (...args) => writeAudit(...args);

export const fieldQueueStatusMap = Object.freeze({
  waiting: '未签到',
  // Calling a student is not a check-in. Keep the roster status unchanged
  // until staff confirms identity at the station.
  called: '未签到',
  checked_in: '已签到',
  testing: '测试中',
  completed: '已完成',
  retest: '待补测',
  absent: '缺席',
  skipped: '缺席',
  cancelled: '缺席',
  paused: null
});

const queueStatusTransitions = Object.freeze({
  waiting: ['called', 'absent', 'cancelled', 'paused'],
  called: ['waiting', 'checked_in', 'absent', 'skipped', 'paused'],
  checked_in: ['called', 'retest', 'absent', 'paused'],
  // Only completeFieldSession may create a completed queue entry. A generic
  // queue transition has no scores, evidence or algorithm trace to prove that
  // the formal assessment actually finished.
  testing: ['retest', 'paused', 'cancelled'],
  completed: ['retest'],
  retest: ['waiting', 'called', 'cancelled'],
  absent: ['waiting'],
  skipped: ['waiting'],
  paused: ['waiting', 'retest', 'cancelled'],
  cancelled: []
});

const fieldQueueTransitionAllowed = (from, to) => from === to || Boolean(queueStatusTransitions[from]?.includes(to));
export const operationalTaskOrder = (alias = '') => {
  const prefix = alias ? `${alias}.` : '';
  return `CASE WHEN ${prefix}test_date=current_date THEN 0 WHEN ${prefix}test_date<current_date THEN 1 ELSE 2 END,
    CASE WHEN ${prefix}test_date<=current_date THEN ${prefix}test_date END DESC,
    CASE WHEN ${prefix}test_date>current_date THEN ${prefix}test_date END ASC`;
};
export const validTaskCompletionPredicate = (taskStudentAlias = 'ts', taskAlias = 't') => {
  const safeItems = `CASE WHEN jsonb_typeof(${taskAlias}.items)='array' THEN ${taskAlias}.items ELSE '[]'::jsonb END`;
  return `(${taskStudentAlias}.status='已完成'
    AND jsonb_array_length(${safeItems})>0
    AND (SELECT COUNT(DISTINCT completion_score.item_code) FROM assessment_scores completion_score
      WHERE completion_score.task_id=${taskStudentAlias}.task_id AND completion_score.student_id=${taskStudentAlias}.student_id
        AND completion_score.review_status='passed'
        AND completion_score.item_code IN (SELECT jsonb_array_elements_text(${safeItems})))=jsonb_array_length(${safeItems}))`;
};
export const fieldIsoDate = (value, fallback = new Date()) => {
  if (!value) return fallback;
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) ? parsed : fallback;
};

export const fieldInputString = (value, name, max = 160) => {
  const result = String(value || '').trim();
  if (!result || result.length > max) throw Object.assign(new Error(`${name}不合法`), { status: 400, code: 'FIELD_INPUT_INVALID' });
  return result;
};

export const fieldObject = (value) => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const fieldEventItemCode = (payload) => ['item', 'itemCode', 'itemName', 'movement', 'exercise']
  .map((key) => payload?.[key]).find((value) => typeof value === 'string' && value.trim())?.trim() || null;
const fieldEventItemStatus = (eventType) => {
  const type = String(eventType || '').trim().toLowerCase();
  if (['item.started', 'movement.started', 'exercise.started'].includes(type)) return 'running';
  if (['item.completed', 'movement.completed', 'exercise.completed'].includes(type)) return 'completed';
  if (['item.review_required', 'movement.review_required', 'quality.review_required'].includes(type)) return 'needs_review';
  if (['item.retest', 'movement.retest', 'exercise.retest'].includes(type)) return 'retest';
  return null;
};

async function updateFieldSessionItemFromEvent(client, sessionId, eventType, happenedAt, payload) {
  const nextStatus = fieldEventItemStatus(eventType);
  if (!nextStatus) return;
  const itemCode = fieldEventItemCode(payload);
  if (!itemCode) throw Object.assign(new Error('逐项采集事件必须包含 item 或 itemCode'), { status: 400, code: 'FIELD_EVENT_ITEM_REQUIRED' });
  const confidenceValue = Number(payload?.confidence);
  const confidence = Number.isFinite(confidenceValue) && confidenceValue >= 0 && confidenceValue <= 1 ? confidenceValue : null;
  const result = await client.query(`UPDATE test_session_items SET status=$1,
      started_at=CASE WHEN $1='running' THEN COALESCE(started_at,$2) ELSE started_at END,
      completed_at=CASE WHEN $1 IN ('completed','needs_review') THEN COALESCE(completed_at,$2) WHEN $1='retest' THEN NULL ELSE completed_at END,
      confidence=COALESCE($3,confidence),capture_summary_json=capture_summary_json || $4::jsonb,updated_at=now()
    WHERE session_id=$5 AND (item_code=$6 OR item_name=$6) RETURNING id`,
  [nextStatus, happenedAt, confidence, payload, sessionId, itemCode]);
  if (!result.rows[0]) throw Object.assign(new Error(`采集事件项目“${itemCode}”不在当前测试方案中`), { status: 409, code: 'FIELD_EVENT_ITEM_SCOPE_MISMATCH' });
}
const fieldEvidenceRetentionDaysFor = (evidenceType) => ['video', 'image'].includes(evidenceType) ? fieldEvidenceVideoRetentionDays : fieldEvidenceDerivedRetentionDays;

const assessmentStandardContext = (student, task) => ({
  schoolId: student.school_id,
  gradeId: student.grade_id || task.grade_id || null,
  region: student.region || '',
  povertyArea: Boolean(student.is_poverty_area),
  testDate: task.test_date,
  fallbackVersion: task.rule_version
});

export const effectiveDate = (value, name = '生效日期') => {
  const date = String(value || '').trim();
  const parsed = new Date(`${date}T00:00:00.000Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(parsed.valueOf()) || parsed.toISOString().slice(0, 10) !== date) {
    throw Object.assign(new Error(`${name}不合法`), { status: 400, code: 'FIELD_INPUT_INVALID' });
  }
  return date;
};

async function fieldTaskForDevice(device, taskId, client = null) {
  const executor = client || { query };
  const result = await executor.query(`SELECT t.* FROM assessment_tasks t
    WHERE t.id=$1 AND t.school_id=$2`, [taskId, device.school_id]);
  if (!result.rows[0]) throw Object.assign(new Error('测评任务不存在或不属于本设备学校'), { status: 404, code: 'FIELD_TASK_NOT_FOUND' });
  if (result.rows[0].status !== 'published') throw Object.assign(new Error('只有已发布的测评任务可以下发到场地端'), { status: 409, code: 'FIELD_TASK_INACTIVE' });
  return result.rows[0];
}

export async function ensureFieldQueue(client, device, taskId) {
  await fieldTaskForDevice(device, taskId, client);
  await client.query(`INSERT INTO test_queue_entries(school_id,task_id,student_id,station_id,queue_order)
    SELECT $1,$2,ts.student_id,NULL,ROW_NUMBER() OVER (ORDER BY c.name,st.name)::int
      FROM task_students ts JOIN students st ON st.id=ts.student_id JOIN classes c ON c.id=st.class_id
     WHERE ts.task_id=$2
    ON CONFLICT(task_id,student_id) DO NOTHING`, [device.school_id, taskId]);
}

// Only unstarted students may move. Called, checked-in and testing students
// retain their station so identity, evidence and operator context never split
// across two physical points mid-flow.
export async function rebalanceFieldQueue(client, task) {
  const stationRows = await client.query(`SELECT s.id AS "stationId",s.station_code AS "stationCode",s.item_code AS "itemCode",s.queue_capacity AS "queueCapacity",s.status AS "stationStatus",
      d.*,cal.version AS "calibrationVersion",cal.checksum_sha256 AS "calibrationChecksumSha256"
    FROM test_stations s JOIN test_devices d ON d.station_id=s.id
    LEFT JOIN LATERAL (SELECT version,checksum_sha256 FROM station_calibrations WHERE station_id=s.id AND status='active' ORDER BY effective_at DESC LIMIT 1) cal ON TRUE
    WHERE s.school_id=$1 AND s.status NOT IN ('maintenance','paused','disabled') AND d.status<>'disabled' AND d.device_type='edge_host'
    ORDER BY s.station_code,d.id`, [task.school_id]);
  const planningById = new Map();
  for (const row of stationRows.rows) {
    const station = planningById.get(row.stationId) || {
      id: row.stationId,
      stationCode: row.stationCode,
      itemCode: row.itemCode,
      queueCapacity: Number(row.queueCapacity),
      ready: false,
      online: false,
      load: 0
    };
    const calibration = row.calibrationVersion ? { version: row.calibrationVersion, checksumSha256: row.calibrationChecksumSha256 } : null;
    const readiness = evaluateFieldReadiness(row, { id: row.stationId, status: row.stationStatus }, calibration);
    station.ready ||= readiness.ready;
    station.online ||= row.status === 'online';
    planningById.set(row.stationId, station);
  }
  const configuredStations = [...planningById.values()].map((station) => ({ ...station, compatibility: stationTaskCompatibility(station.itemCode, task.items) }));
  const planningStations = configuredStations.filter((station) => station.compatibility.compatible);
  const incompatibleStations = configuredStations.filter((station) => !station.compatibility.compatible);
  const readyStations = planningStations.filter((station) => station.ready);
  // Queue planning and formal capture are separate concerns. Before any station
  // is ready, spread the roster across every configured active station so each
  // field client can download its students during setup. Once formal-ready
  // stations exist, new/unstarted work is limited to that safe pool.
  // openFieldSession remains fail-closed on the full readiness contract.
  const dispatchStations = readyStations.length ? readyStations : planningStations;
  const mode = readyStations.length ? 'formal_ready' : 'pre_dispatch';
  const stationsById = new Map(dispatchStations.map((station) => [station.id, station]));
  const dispatchIds = dispatchStations.map((station) => station.id);
  if (dispatchIds.length) {
    await client.query(`UPDATE test_queue_entries SET station_id=NULL,state_version=state_version+1,updated_at=now()
      WHERE task_id=$1 AND status='waiting' AND station_id IS NOT NULL AND NOT (station_id=ANY($2::text[]))`, [task.id, dispatchIds]);
  } else {
    await client.query(`UPDATE test_queue_entries SET station_id=NULL,state_version=state_version+1,updated_at=now()
      WHERE task_id=$1 AND status='waiting' AND station_id IS NOT NULL`, [task.id]);
  }
  const entries = await client.query(`SELECT id,station_id,status,priority,queue_order AS "queueOrder",created_at AS "createdAt"
    FROM test_queue_entries WHERE task_id=$1 AND status IN ('waiting','called','checked_in','testing','retest','paused')
    ORDER BY priority DESC,queue_order,created_at FOR UPDATE`, [task.id]);
  for (const entry of entries.rows) {
    const station = entry.station_id ? stationsById.get(entry.station_id) : null;
    if (station) station.load += 1;
  }
  const assignments = [];
  for (const entry of entries.rows.filter((item) => item.status === 'waiting' && !item.station_id)) {
    const target = dispatchStations
      .filter((station) => station.load < station.queueCapacity)
      .sort((left, right) => (left.load / left.queueCapacity) - (right.load / right.queueCapacity) || left.stationCode.localeCompare(right.stationCode))[0];
    if (!target) break;
    target.load += 1;
    await client.query(`UPDATE test_queue_entries SET station_id=$1,queue_order=$2,state_version=state_version+1,updated_at=now() WHERE id=$3`, [target.id, target.load, entry.id]);
    assignments.push({ queueEntryId: entry.id, stationId: target.id, stationCode: target.stationCode, queueOrder: target.load });
  }
  const remaining = await client.query(`SELECT COUNT(*)::int AS count FROM test_queue_entries WHERE task_id=$1 AND status='waiting' AND station_id IS NULL`, [task.id]);
  const stationView = ({ load, ...station }) => ({ ...station, assignedCount: load });
  return {
    mode,
    selectionBasis: readyStations.length ? 'ready' : planningStations.length ? 'configured' : 'none',
    readyStationCount: readyStations.length,
    planningStationCount: planningStations.length,
    configuredStationCount: configuredStations.length,
    eligibleStations: readyStations.map(stationView),
    planningStations: planningStations.map(stationView),
    incompatibleStations: incompatibleStations.map(stationView),
    dispatchStations: dispatchStations.map(stationView),
    assignments,
    unassignedCount: Number(remaining.rows[0]?.count || 0)
  };
}

export async function fieldBootstrap(device, taskId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const availableTaskRows = await client.query(`SELECT t.id,t.title,t.test_date::text AS "testDate",t.location,
        COUNT(ts.id)::int AS "totalCount",COUNT(ts.id) FILTER(WHERE ${validTaskCompletionPredicate('ts', 't')})::int AS "completedCount"
      FROM assessment_tasks t LEFT JOIN task_students ts ON ts.task_id=t.id
      WHERE t.school_id=$1 AND t.status='published'
      GROUP BY t.id
      ORDER BY ${operationalTaskOrder('t')},t.created_at DESC LIMIT 50`, [device.school_id]);
    const availableTasks = availableTaskRows.rows;
    let selectedTaskId = taskId ? fieldInputString(taskId, '任务 ID') : null;
    if (!selectedTaskId) selectedTaskId = availableTasks[0]?.id || null;
    let task = null;
    let queue = [];
    let queueSummary = null;
    let dispatch = null;
    if (selectedTaskId) {
      task = await fieldTaskForDevice(device, selectedTaskId, client);
      await ensureFieldQueue(client, device, selectedTaskId);
      dispatch = await rebalanceFieldQueue(client, task);
      const entries = await client.query(`SELECT q.id,q.task_id AS "taskId",q.student_id AS "studentId",q.station_id AS "stationId",q.status,
          q.priority,q.queue_order AS "queueOrder",q.retest_count AS "retestCount",q.state_version AS "stateVersion",q.note,
          q.last_called_at AS "lastCalledAt",q.updated_at AS "updatedAt",
          active_session.id AS "activeSessionId",active_session.started_at AS "captureStartedAt",active_session.event_count AS "captureEventCount",active_session.last_event_at AS "lastCaptureEventAt",
          latest_event.event_type AS "latestCaptureEventType",latest_event.payload_json AS "latestCapturePayload",
          GREATEST(0,FLOOR(EXTRACT(EPOCH FROM (now()-COALESCE(CASE WHEN q.status='called' THEN q.last_called_at END,q.updated_at)))))::int AS "stateAgeSeconds",
          (q.status='called' AND q.last_called_at IS NOT NULL AND q.last_called_at<now()-interval '2 minutes') AS "calledOverdue",
          CASE WHEN q.status='called' AND q.last_called_at IS NOT NULL AND q.last_called_at<now()-interval '2 minutes' THEN 'critical'
            WHEN q.status IN ('waiting','retest') AND q.updated_at<now()-interval '30 minutes' THEN 'critical'
            WHEN q.status IN ('waiting','retest') AND q.updated_at<now()-interval '15 minutes' THEN 'warning'
            ELSE 'normal' END AS "timingSeverity",
          st.name AS "studentName",st.gender,st.birth_date::text AS "birthDate",
          st.student_no AS "studentNo",st.grade_id AS "gradeId",st.region,st.is_poverty_area AS "isPovertyArea",g.name AS "gradeName",c.name AS "className",ts.status AS "taskStatus",ts.version AS "taskVersion"
        FROM test_queue_entries q JOIN students st ON st.id=q.student_id JOIN grades g ON g.id=st.grade_id
          JOIN classes c ON c.id=st.class_id JOIN task_students ts ON ts.task_id=q.task_id AND ts.student_id=q.student_id
          LEFT JOIN LATERAL (SELECT session.id,session.started_at,
            (SELECT COUNT(*)::int FROM session_action_events event WHERE event.session_id=session.id) AS event_count,
            (SELECT MAX(event.happened_at) FROM session_action_events event WHERE event.session_id=session.id) AS last_event_at
            FROM test_sessions session WHERE session.queue_entry_id=q.id AND session.status IN ('created','checked_in','testing')
            ORDER BY session.attempt_no DESC,session.created_at DESC LIMIT 1) active_session ON TRUE
          LEFT JOIN LATERAL (SELECT event.event_type,event.payload_json,event.happened_at FROM session_action_events event
            WHERE event.session_id=active_session.id ORDER BY event.sequence_no DESC,event.happened_at DESC LIMIT 1) latest_event ON TRUE
        WHERE q.task_id=$1 AND q.station_id=$2
        ORDER BY q.priority DESC,q.queue_order,q.created_at`, [selectedTaskId, device.station_id || null]);
      queue = entries.rows;
      const summary = await client.query(`SELECT
          (SELECT COUNT(*)::int FROM task_students WHERE task_id=$1) AS "rosterCount",
          COUNT(q.id)::int AS "queuedCount",
          COUNT(q.id) FILTER(WHERE q.status IN ('waiting','called','checked_in','testing','retest','paused'))::int AS "activeQueueCount",
          COUNT(q.id) FILTER(WHERE q.station_id=$2)::int AS "stationAssignedCount",
          COUNT(q.id) FILTER(WHERE q.station_id=$2 AND q.status IN ('waiting','called','checked_in','testing','retest','paused'))::int AS "stationActiveCount",
          COUNT(q.id) FILTER(WHERE q.station_id IS NULL AND q.status IN ('waiting','called','checked_in','testing','retest','paused'))::int AS "unassignedCount",
          COUNT(q.id) FILTER(WHERE q.station_id IS NOT NULL AND ($2::text IS NULL OR q.station_id<>$2) AND q.status IN ('waiting','called','checked_in','testing','retest','paused'))::int AS "otherStationCount"
        FROM test_queue_entries q WHERE q.task_id=$1`, [selectedTaskId, device.station_id || null]);
      queueSummary = summary.rows[0];
    }
    const [station, calibration, commands] = await Promise.all([
      client.query(`SELECT id,station_code AS "stationCode",name,item_code AS "itemCode",queue_capacity AS "queueCapacity",status,
          status_reason AS "statusReason",status_changed_at AS "statusChangedAt",metadata_json AS metadata,last_seen_at AS "lastSeenAt",updated_at AS "updatedAt" FROM test_stations WHERE id=$1`, [device.station_id || null]),
      client.query(`SELECT version,checksum_sha256 AS "checksumSha256",config_json AS config,effective_at AS "effectiveAt"
        FROM station_calibrations WHERE station_id=$1 AND status='active' ORDER BY effective_at DESC LIMIT 1`, [device.station_id || null]),
      client.query(`SELECT id,command_type AS "commandType",payload_json AS payload,created_at AS "createdAt",expires_at AS "expiresAt"
        FROM device_commands WHERE device_id=$1 AND status IN ('pending','delivered') AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at LIMIT 50`, [device.id])
    ]);
    await client.query('COMMIT');
    const standardContexts = [...new Map(queue.map((entry) => {
      const context = assessmentStandardContext({ school_id: device.school_id, grade_id: entry.gradeId, region: entry.region, is_poverty_area: entry.isPovertyArea }, task);
      return [`${context.gradeId || ''}|${context.region}|${context.povertyArea}`, context];
    })).values()];
    const standards = await Promise.all(standardContexts.map(async (context) => ({
      ...(await resolveAssessmentStandard(client, context)),
      appliesTo: { gradeId: context.gradeId, region: context.region, povertyArea: context.povertyArea }
    })));
    const readiness = evaluateFieldReadiness(device, station.rows[0] || null, calibration.rows[0] || null);
    if (dispatch?.assignments.length) void publishFieldUpdate(device.school_id, 'queue.rebalanced', { taskId: task.id, assignments: dispatch.assignments, unassignedCount: dispatch.unassignedCount });
    return {
      serverTime: new Date().toISOString(),
      device: { id: device.id, code: device.device_code, name: device.name, type: device.device_type, softwareVersion: device.software_version, controlState: device.control_state || 'running' },
      station: station.rows[0] || null,
      calibration: calibration.rows[0] || null,
      readiness,
      task: task ? { id: task.id, title: task.title, testDate: dateOnlyText(task.test_date), location: task.location, items: task.items || [], ruleVersion: task.rule_version, status: task.status } : null,
      protocol: task ? protocolSnapshotFromTask(task) : null,
      availableTasks,
      queue,
      queueSummary,
      dispatch,
      standards,
      commands: commands.rows
    };
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

export async function transitionFieldQueue(device, input, actor = { type: 'device', id: null }) {
  const queueEntryId = fieldInputString(input.queueEntryId || input.id, '队列记录 ID');
  const nextStatus = fieldInputString(input.status, '队列状态', 32);
  if (input.expectedVersion == null) throw Object.assign(new Error('必须提供队列版本，请刷新名单后重试'), { status: 400, code: 'FIELD_QUEUE_VERSION_REQUIRED' });
  const expectedVersion = Number(input.expectedVersion);
  if (!Object.hasOwn(fieldQueueStatusMap, nextStatus)) throw Object.assign(new Error('队列状态不合法'), { status: 400, code: 'FIELD_QUEUE_STATUS_INVALID' });
  if (!Number.isInteger(expectedVersion) || expectedVersion < 1) throw Object.assign(new Error('队列版本不合法'), { status: 400, code: 'FIELD_QUEUE_VERSION_INVALID' });
  const transitionReason = String(input.reason || input.note || '').trim();
  if (['absent', 'skipped', 'cancelled', 'retest'].includes(nextStatus) && !transitionReason) throw Object.assign(new Error('缺席、跳过、取消或补测必须填写处理原因'), { status: 400, code: 'FIELD_QUEUE_REASON_REQUIRED' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(`SELECT q.*,t.school_id,t.status AS task_status,t.items AS task_items,ts.id AS task_student_id,ts.status AS task_student_status
      FROM test_queue_entries q JOIN assessment_tasks t ON t.id=q.task_id
        JOIN task_students ts ON ts.task_id=q.task_id AND ts.student_id=q.student_id
      WHERE q.id=$1 FOR UPDATE`, [queueEntryId]);
    const row = current.rows[0];
    if (!row || row.school_id !== device.school_id || (device.station_id && row.station_id && row.station_id !== device.station_id)) throw Object.assign(new Error('队列记录不存在或不属于本设备'), { status: 404, code: 'FIELD_QUEUE_NOT_FOUND' });
    if (input.taskId && fieldInputString(input.taskId, '任务 ID') !== row.task_id) throw Object.assign(new Error('队列记录与客户端任务不一致，已拒绝跨任务写入'), { status: 409, code: 'FIELD_QUEUE_TASK_MISMATCH' });
    if (nextStatus === 'checked_in' && input.identityVerified !== true) throw Object.assign(new Error('签到前必须当面核对姓名、班级和学籍信息并明确确认本人'), { status: 400, code: 'FIELD_IDENTITY_CONFIRMATION_REQUIRED' });
    if (row.task_status !== 'published') {
      if (!input.syncReceipt || !['closed', 'archived'].includes(row.task_status)) throw Object.assign(new Error('任务未处于可运行状态，不能继续修改现场队列'), { status: 409, code: 'FIELD_TASK_INACTIVE' });
      if (nextStatus === 'completed') throw Object.assign(new Error('完成状态只能由正式采集会话在成绩和证据保存成功后生成'), { status: 409, code: 'FIELD_SESSION_COMPLETION_REQUIRED' });
      if (nextStatus === 'testing') throw Object.assign(new Error('测试中状态只能在正式采集会话创建成功后生成'), { status: 409, code: 'FIELD_SESSION_OPEN_REQUIRED' });
      const happenedAt = fieldIsoDate(input.happenedAt);
      const lateReason = `任务${row.task_status === 'closed' ? '关闭' : '归档'}后收到离线现场事实：设备曾提交 ${nextStatus}${transitionReason ? `；${transitionReason}` : ''}`.slice(0, 500);
      await client.query(`INSERT INTO queue_events(queue_entry_id,client_event_id,old_status,new_status,reason,actor_type,actor_id,station_id,happened_at)
        VALUES($1,$2,$3,$3,$4,$5,$6,$7,$8) ON CONFLICT(client_event_id) DO NOTHING`,
      [row.id, fieldInputString(input.clientEventId, '客户端事件 ID'), row.status, lateReason, actor.type, actor.id, row.station_id || null, happenedAt]);
      await client.query(`INSERT INTO field_sync_events(device_id,client_event_id,event_type,session_id,happened_at,payload_hash)
        VALUES($1,$2,'queue.transition',NULL,$3,$4)`, [input.syncReceipt.deviceId, input.clientEventId, happenedAt, input.syncReceipt.payloadHash]);
      await client.query('COMMIT');
      return {
        id: row.id, taskId: row.task_id, studentId: row.student_id, stationId: row.station_id, status: row.status,
        priority: row.priority, queueOrder: row.queue_order, retestCount: row.retest_count, stateVersion: Number(row.state_version), note: row.note,
        lateAfterTaskClosure: true, submittedStatus: nextStatus, happenedAt
      };
    }
    if (nextStatus === 'completed' && row.status !== 'completed') throw Object.assign(new Error('完成状态只能由正式采集会话在成绩和证据保存成功后生成'), { status: 409, code: 'FIELD_SESSION_COMPLETION_REQUIRED' });
    if (nextStatus === 'testing') throw Object.assign(new Error('测试中状态只能在正式采集会话创建成功后生成'), { status: 409, code: 'FIELD_SESSION_OPEN_REQUIRED' });
    if (row.status === 'testing' && nextStatus !== 'testing') throw Object.assign(new Error('正在采集的学生必须先完成或中止正式会话，不能只修改队列状态'), { status: 409, code: 'FIELD_SESSION_RESOLUTION_REQUIRED' });
    if (!fieldQueueTransitionAllowed(row.status, nextStatus)) throw Object.assign(new Error(`不能从 ${row.status} 变更为 ${nextStatus}`), { status: 409, code: 'FIELD_QUEUE_TRANSITION_INVALID' });
    if (Number(row.state_version) !== expectedVersion) throw Object.assign(new Error('队列已被其他终端更新，请重新同步'), { status: 409, code: 'FIELD_QUEUE_VERSION_CONFLICT' });
    if (['called', 'checked_in', 'testing'].includes(nextStatus) && !row.station_id) throw Object.assign(new Error('学生尚未分配测试点，请先生成或调整候测名单'), { status: 409, code: 'FIELD_QUEUE_UNASSIGNED' });
    if (nextStatus === 'called') {
      const stationResult = await client.query(`SELECT s.*,cal.version AS calibration_version,cal.checksum_sha256 AS calibration_checksum_sha256
        FROM test_stations s LEFT JOIN LATERAL (
          SELECT version,checksum_sha256 FROM station_calibrations WHERE station_id=s.id AND status='active' ORDER BY effective_at DESC LIMIT 1
        ) cal ON TRUE WHERE s.id=$1 FOR UPDATE OF s`, [row.station_id]);
      const station = stationResult.rows[0];
      if (!station || station.school_id !== row.school_id) throw Object.assign(new Error('已分配测试点不存在或不属于当前学校，请重新分流'), { status: 409, code: 'FIELD_QUEUE_STATION_UNAVAILABLE' });
      const compatibility = stationTaskCompatibility(station.item_code, row.task_items);
      if (!compatibility.compatible) throw Object.assign(new Error(`测试点不能承接当前任务：${compatibility.reason}`), { status: 409, code: 'FIELD_STATION_TASK_MISMATCH' });
      const calibration = station.calibration_version ? { version: station.calibration_version, checksumSha256: station.calibration_checksum_sha256 } : null;
      const devices = await client.query(`SELECT * FROM test_devices WHERE station_id=$1 AND device_type='edge_host' AND status='online' ORDER BY last_heartbeat_at DESC NULLS LAST,id`, [station.id]);
      if (!devices.rows.some((fieldDevice) => evaluateFieldReadiness(fieldDevice, station, calibration).ready)) throw Object.assign(new Error('测试点尚未通过开测检查，不能叫号；请先处理设备、自检和标定'), { status: 409, code: 'FIELD_STATION_NOT_READY' });
    }
    const happenedAt = fieldIsoDate(input.happenedAt);
    const updated = await client.query(`UPDATE test_queue_entries SET status=$1,note=$2,state_version=state_version+1,
      last_called_at=CASE WHEN $1='called' THEN $3 ELSE last_called_at END,
      completed_at=CASE WHEN $1='completed' THEN COALESCE(completed_at,$3) ELSE completed_at END,updated_at=now()
      WHERE id=$4 RETURNING id,task_id AS "taskId",student_id AS "studentId",station_id AS "stationId",status,priority,
      queue_order AS "queueOrder",retest_count AS "retestCount",state_version AS "stateVersion",note,last_called_at AS "lastCalledAt",updated_at AS "updatedAt"`,
    [nextStatus, String(input.note || '').slice(0, 500), happenedAt, row.id]);
    const taskStatus = fieldQueueStatusMap[nextStatus] || row.task_student_status;
    await client.query(`UPDATE task_students SET status=$1,note=COALESCE(NULLIF($2,''),note),
      check_in_at=CASE WHEN $1='已签到' THEN COALESCE(check_in_at,$3) ELSE check_in_at END,
      completed_at=CASE WHEN $1='已完成' THEN COALESCE(completed_at,$3) ELSE completed_at END,version=version+1
      WHERE id=$4`, [taskStatus, String(input.note || '').slice(0, 500), happenedAt, row.task_student_id]);
    await client.query(`INSERT INTO queue_events(queue_entry_id,client_event_id,old_status,new_status,reason,actor_type,actor_id,station_id,happened_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(client_event_id) DO NOTHING`,
    [row.id, input.clientEventId ? fieldInputString(input.clientEventId, '客户端事件 ID') : null, row.status, nextStatus, transitionReason.slice(0, 500), actor.type, actor.id, row.station_id || null, happenedAt]);
    if (input.syncReceipt) {
      await client.query(`INSERT INTO field_sync_events(device_id,client_event_id,event_type,session_id,happened_at,payload_hash)
        VALUES($1,$2,'queue.transition',NULL,$3,$4)`, [input.syncReceipt.deviceId, input.clientEventId, happenedAt, input.syncReceipt.payloadHash]);
    }
    await client.query('COMMIT');
    void publishFieldUpdate(row.school_id, 'queue.updated', { queueEntryId: row.id, taskId: row.task_id, studentId: row.student_id, stationId: row.station_id, status: nextStatus, stateVersion: Number(updated.rows[0].stateVersion) });
    return updated.rows[0];
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

export async function openFieldSession(device, input, options = {}) {
  const clientSessionId = fieldInputString(input.clientSessionId, '客户端会话 ID');
  const taskId = fieldInputString(input.taskId, '任务 ID');
  const studentId = fieldInputString(input.studentId, '学生 ID');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1),hashtext($2))', [taskId, studentId]);
    const existing = await client.query(`SELECT id,client_session_id AS "clientSessionId",school_id,edge_device_id,task_id,student_id,status,attempt_no AS "attemptNo",started_at AS "startedAt",sync_version AS "syncVersion"
      FROM test_sessions WHERE client_session_id=$1`, [clientSessionId]);
    if (existing.rows[0]) {
      if (existing.rows[0].school_id !== device.school_id || existing.rows[0].edge_device_id !== device.id || existing.rows[0].task_id !== taskId || existing.rows[0].student_id !== studentId) {
        throw Object.assign(new Error('测试会话不存在或不属于本设备'), { status: 404, code: 'FIELD_SESSION_NOT_FOUND' });
      }
      await client.query('COMMIT');
      return existing.rows[0];
    }
    const algorithmVersion = fieldInputString(input.algorithmVersion || device.software_version || '', '采集算法版本', 120);
    if (/manual(?:-|_)?fallback|人工录入/i.test(algorithmVersion)) throw Object.assign(new Error('人工兜底不能创建正式场地测评会话，请使用认证采集适配器或在后台安排复核'), { status: 409, code: 'FIELD_MANUAL_CAPTURE_FORBIDDEN' });
    const taskResult = await client.query('SELECT * FROM assessment_tasks WHERE id=$1 AND school_id=$2', [taskId, device.school_id]);
    const task = taskResult.rows[0];
    if (!task) throw Object.assign(new Error('测评任务不存在或不属于本设备学校'), { status: 404, code: 'FIELD_TASK_NOT_FOUND' });
    if (task.status !== 'published') {
      if (options.allowInactiveRecovery !== true || !['closed', 'archived'].includes(task.status)) throw Object.assign(new Error('只有已发布的测评任务可以创建场地会话'), { status: 409, code: 'FIELD_TASK_INACTIVE' });
      const roster = await client.query(`SELECT ts.id AS task_student_id FROM task_students ts JOIN students st ON st.id=ts.student_id
        WHERE ts.task_id=$1 AND ts.student_id=$2 AND st.school_id=$3 FOR UPDATE OF ts`, [taskId, studentId, device.school_id]);
      if (!roster.rows[0]) throw Object.assign(new Error('学生不在当前测评名单内'), { status: 404, code: 'FIELD_ROSTER_NOT_FOUND' });
      const queueResult = await client.query('SELECT * FROM test_queue_entries WHERE task_id=$1 AND student_id=$2 FOR UPDATE', [taskId, studentId]);
      const queue = queueResult.rows[0] || null;
      const existingAttempts = await client.query('SELECT COALESCE(MAX(attempt_no),0)::int AS max_attempt FROM test_sessions WHERE task_id=$1 AND student_id=$2', [taskId, studentId]);
      const startedAt = fieldIsoDate(input.startedAt);
      const retiredAt = new Date().toISOString();
      const summary = {
        ...fieldObject(input.summary),
        lateAfterTaskClosure: true,
        taskStatusAtReceipt: task.status,
        retiredAt,
        abortReason: '任务关闭或归档后收到场地端离线开测事实；仅归档中断会话，不重新开启任务'
      };
      const protocol = protocolSnapshotFromTask(task);
      const retired = await client.query(`INSERT INTO test_sessions(client_session_id,school_id,task_id,student_id,station_id,edge_device_id,queue_entry_id,attempt_no,status,rule_version,protocol_id,protocol_version,protocol_snapshot_json,algorithm_version,started_at,ended_at,device_started_at,device_ended_at,summary_json)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,'aborted',$9,$10,$11,$12,$13,$14,$15,$14,$15,$16)
        RETURNING id,client_session_id AS "clientSessionId",task_id AS "taskId",student_id AS "studentId",station_id AS "stationId",attempt_no AS "attemptNo",status,rule_version AS "ruleVersion",algorithm_version AS "algorithmVersion",started_at AS "startedAt",ended_at AS "endedAt",sync_version AS "syncVersion",summary_json AS summary`,
      [clientSessionId, device.school_id, taskId, studentId, queue?.station_id || device.station_id || null, device.id, queue?.id || null, Number(existingAttempts.rows[0].max_attempt) + 1, task.rule_version, protocol.id, protocol.version, protocol, algorithmVersion, startedAt, retiredAt, summary]);
      await client.query(`INSERT INTO test_session_items(session_id,item_code,item_name,sequence_no,required,status,attempt_no)
        SELECT $1,item->>'code',COALESCE(item->>'name',item->>'code'),(item->>'sequenceNo')::int,COALESCE((item->>'required')::boolean,TRUE),'retest',$3
        FROM jsonb_array_elements($2::jsonb->'items') item ON CONFLICT(session_id,item_code) DO NOTHING`, [retired.rows[0].id, protocol, Number(existingAttempts.rows[0].max_attempt) + 1]);
      await client.query('COMMIT');
      void publishFieldUpdate(device.school_id, 'session.retired_after_task_close', { sessionId: retired.rows[0].id, taskId, studentId, stationId: retired.rows[0].stationId, deviceId: device.id, status: 'aborted' });
      return retired.rows[0];
    }
    const [stationResult, calibrationResult] = await Promise.all([
      client.query(`SELECT id,status,item_code FROM test_stations WHERE id=$1`, [device.station_id || null]),
      client.query(`SELECT version,checksum_sha256 AS "checksumSha256" FROM station_calibrations WHERE station_id=$1 AND status='active' ORDER BY effective_at DESC LIMIT 1`, [device.station_id || null])
    ]);
    const readiness = evaluateFieldReadiness(device, stationResult.rows[0] || null, calibrationResult.rows[0] || null);
    if (!readiness.ready) throw Object.assign(new Error(`场地端未就绪：${readiness.blockers.join('；')}`), { status: 409, code: 'FIELD_STATION_NOT_READY' });
    const compatibility = stationTaskCompatibility(stationResult.rows[0]?.item_code, task.items);
    if (!compatibility.compatible) throw Object.assign(new Error(`测试点不能承接当前任务：${compatibility.reason}`), { status: 409, code: 'FIELD_STATION_TASK_MISMATCH' });
    const roster = await client.query(`SELECT ts.id AS task_student_id,ts.status,st.grade_id,st.region,st.is_poverty_area FROM task_students ts
      JOIN students st ON st.id=ts.student_id WHERE ts.task_id=$1 AND ts.student_id=$2 AND st.school_id=$3 FOR UPDATE`, [taskId, studentId, device.school_id]);
    if (!roster.rows[0]) throw Object.assign(new Error('学生不在当前测评名单内'), { status: 404, code: 'FIELD_ROSTER_NOT_FOUND' });
    const standard = await resolveAssessmentStandard(client, assessmentStandardContext({ school_id: device.school_id, ...roster.rows[0] }, task));
    await ensureFieldQueue(client, device, taskId);
    await rebalanceFieldQueue(client, task);
    const queueResult = await client.query(`SELECT * FROM test_queue_entries WHERE task_id=$1 AND student_id=$2 FOR UPDATE`, [taskId, studentId]);
    const queue = queueResult.rows[0];
    if (queue?.station_id && queue.station_id !== device.station_id) throw Object.assign(new Error('学生已由其他测试点接管，请在对应测试点继续'), { status: 409, code: 'FIELD_QUEUE_ASSIGNED_ELSEWHERE' });
    if (!queue || queue.status !== 'checked_in') throw Object.assign(new Error('学生尚未完成现场签到，不能开始正式采集'), { status: 409, code: 'FIELD_STUDENT_NOT_CHECKED_IN' });
    const existingAttempts = await client.query('SELECT COALESCE(MAX(attempt_no),0)::int AS max_attempt FROM test_sessions WHERE task_id=$1 AND student_id=$2', [taskId, studentId]);
    const startedAt = fieldIsoDate(input.startedAt);
    const protocol = protocolSnapshotFromTask(task);
    const session = await client.query(`INSERT INTO test_sessions(client_session_id,school_id,task_id,student_id,station_id,edge_device_id,queue_entry_id,attempt_no,status,rule_version,protocol_id,protocol_version,protocol_snapshot_json,standard_id,standard_version,standard_snapshot_json,calibration_version,algorithm_version,started_at,device_started_at,summary_json)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,'testing',$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$18,$19)
      RETURNING id,client_session_id AS "clientSessionId",task_id AS "taskId",student_id AS "studentId",station_id AS "stationId",attempt_no AS "attemptNo",status,rule_version AS "ruleVersion",standard_id AS "standardId",standard_version AS "standardVersion",calibration_version AS "calibrationVersion",algorithm_version AS "algorithmVersion",started_at AS "startedAt",sync_version AS "syncVersion"`,
    [clientSessionId, device.school_id, taskId, studentId, device.station_id || null, device.id, queue?.id || null, Number(existingAttempts.rows[0].max_attempt) + 1, task.rule_version, protocol.id, protocol.version, protocol, standard.id, standard.standardVersion, standard, calibrationResult.rows[0]?.version || '', algorithmVersion, startedAt, fieldObject(input.summary)]);
    await client.query(`INSERT INTO test_session_items(session_id,item_code,item_name,sequence_no,required,status,attempt_no)
      SELECT $1,item->>'code',COALESCE(item->>'name',item->>'code'),(item->>'sequenceNo')::int,COALESCE((item->>'required')::boolean,TRUE),'pending',$3
      FROM jsonb_array_elements($2::jsonb->'items') item ON CONFLICT(session_id,item_code) DO NOTHING`, [session.rows[0].id, protocol, Number(existingAttempts.rows[0].max_attempt) + 1]);
    if (queue) {
      await client.query(`UPDATE test_queue_entries SET status='testing',state_version=state_version+1,updated_at=now() WHERE id=$1`, [queue.id]);
      await client.query(`INSERT INTO queue_events(queue_entry_id,old_status,new_status,reason,actor_type,actor_id,station_id,happened_at)
        VALUES($1,$2,'testing','场地端开始测试','device',$3,$4,$5)`, [queue.id, queue.status, device.id, device.station_id || null, startedAt]);
    }
    await client.query(`UPDATE task_students SET status='测试中',check_in_at=COALESCE(check_in_at,$1),version=version+1 WHERE id=$2`, [startedAt, roster.rows[0].task_student_id]);
    await client.query('COMMIT');
    void publishFieldUpdate(device.school_id, 'session.opened', { sessionId: session.rows[0].id, taskId, studentId, stationId: device.station_id || null, deviceId: device.id });
    return session.rows[0];
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

export async function appendFieldSessionEvents(device, sessionId, events) {
  if (!Array.isArray(events) || !events.length || events.length > 500) throw Object.assign(new Error('采集事件数量必须在 1 到 500 条之间'), { status: 400, code: 'FIELD_EVENTS_INVALID' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const sessionResult = await client.query(`SELECT id,client_session_id,school_id,edge_device_id,status FROM test_sessions WHERE (id=$1 OR client_session_id=$1) FOR UPDATE`, [sessionId]);
    const session = sessionResult.rows[0];
    if (!session || session.school_id !== device.school_id || session.edge_device_id !== device.id) throw Object.assign(new Error('测试会话不存在或不属于本设备'), { status: 404, code: 'FIELD_SESSION_NOT_FOUND' });
    if (!['created', 'checked_in', 'testing'].includes(session.status)) throw Object.assign(new Error('当前会话不能继续写入采集事件'), { status: 409, code: 'FIELD_SESSION_CLOSED' });
    const saved = [];
    let insertedCount = 0;
    for (const event of events) {
      const clientEventId = fieldInputString(event?.clientEventId, '客户端事件 ID');
      const sequenceNo = Number(event?.sequenceNo);
      if (!Number.isInteger(sequenceNo) || sequenceNo < 0) throw Object.assign(new Error('事件序号不合法'), { status: 400, code: 'FIELD_EVENT_SEQUENCE_INVALID' });
      const eventType = fieldInputString(event?.eventType, '事件类型', 64);
      const happenedAt = fieldIsoDate(event?.happenedAt);
      const payload = fieldObject(event?.payload);
      const sameEvent = (row) => row.session_id === session.id
        && Number(row.sequence_no) === sequenceNo
        && row.event_type === eventType
        && new Date(row.happened_at).getTime() === new Date(happenedAt).getTime()
        && requestBodyHash(row.payload_json) === requestBodyHash(payload);
      const replay = await client.query('SELECT id,session_id,sequence_no,event_type,happened_at,payload_json FROM session_action_events WHERE client_event_id=$1', [clientEventId]);
      if (replay.rows[0]) {
        if (!sameEvent(replay.rows[0])) {
          recordMetric('xiangshang_field_sync_conflicts_total', { reason: 'action_replay_mismatch' });
          logger.warn('field.action_replay_mismatch', { deviceId: device.id, sessionId: session.id, clientEventId });
          throw Object.assign(new Error('采集事件 ID 已被用于不同内容，已拒绝覆盖原始时间线'), { status: 409, code: 'FIELD_ACTION_REPLAY_MISMATCH' });
        }
        saved.push({ id: replay.rows[0].id, clientEventId, sequenceNo, eventType, happenedAt });
        continue;
      }
      const sequence = await client.query('SELECT client_event_id AS "clientEventId" FROM session_action_events WHERE session_id=$1 AND sequence_no=$2', [session.id, sequenceNo]);
      if (sequence.rows[0]) throw Object.assign(new Error('采集事件序号已被其他事件占用，请重新同步会话时间线'), { status: 409, code: 'FIELD_EVENT_SEQUENCE_CONFLICT' });
      const result = await client.query(`INSERT INTO session_action_events(session_id,client_event_id,sequence_no,event_type,happened_at,payload_json)
        VALUES($1,$2,$3,$4,$5,$6)
        RETURNING id,client_event_id AS "clientEventId",sequence_no AS "sequenceNo",event_type AS "eventType",happened_at AS "happenedAt"`,
      [session.id, clientEventId, sequenceNo, eventType, happenedAt, payload]);
      if (result.rows[0]) {
        await updateFieldSessionItemFromEvent(client, session.id, eventType, happenedAt, payload);
        saved.push(result.rows[0]); insertedCount += 1;
      }
    }
    if (insertedCount) await client.query('UPDATE test_sessions SET sync_version=sync_version+1,updated_at=now() WHERE id=$1', [session.id]);
    await client.query('COMMIT');
    return { id: session.id, sessionId: session.id, clientSessionId: session.client_session_id, accepted: saved.length, events: saved };
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

export async function abortFieldSession(device, sessionId, input = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(`SELECT s.*,ts.id AS task_student_id FROM test_sessions s
      JOIN task_students ts ON ts.task_id=s.task_id AND ts.student_id=s.student_id
      WHERE (s.id=$1 OR s.client_session_id=$1) FOR UPDATE OF s`, [sessionId]);
    const session = result.rows[0];
    if (!session || session.school_id !== device.school_id || session.edge_device_id !== device.id) throw Object.assign(new Error('测试会话不存在或不属于本设备'), { status: 404, code: 'FIELD_SESSION_NOT_FOUND' });
    if (session.status === 'aborted') {
      if (session.summary_json?.lateAfterTaskClosure === true && !session.summary_json?.retirementConfirmedAt) {
        const confirmedAt = fieldIsoDate(input.endedAt);
        const reason = String(input.reason || session.summary_json.abortReason || '场地端已确认封存任务关闭后的中断采集').trim().slice(0, 500);
        await client.query(`UPDATE test_sessions SET device_ended_at=$1,summary_json=summary_json || jsonb_build_object('abortReason',$2::text,'retirementConfirmedAt',$1::timestamptz),sync_version=sync_version+1,updated_at=now() WHERE id=$3`, [confirmedAt, reason, session.id]);
      }
      await client.query('COMMIT');
      return { id: session.id, status: 'aborted', queueStatus: 'cancelled', idempotent: true, lateAfterTaskClosure: session.summary_json?.lateAfterTaskClosure === true };
    }
    if (!['created', 'checked_in', 'testing'].includes(session.status)) throw Object.assign(new Error('当前会话不能标记为采集中断'), { status: 409, code: 'FIELD_SESSION_ABORT_INVALID' });
    const endedAt = fieldIsoDate(input.endedAt);
    const reason = String(input.reason || 'Windows 场地端异常退出，无法恢复原硬件采集上下文').trim().slice(0, 500);
    await client.query(`UPDATE test_sessions SET status='aborted',ended_at=$1,device_ended_at=$1,summary_json=summary_json || jsonb_build_object('abortReason',$2::text,'abortedAt',$1::timestamptz),sync_version=sync_version+1,updated_at=now() WHERE id=$3`, [endedAt, reason, session.id]);
    if (session.queue_entry_id) {
      const queue = await client.query('SELECT * FROM test_queue_entries WHERE id=$1 FOR UPDATE', [session.queue_entry_id]);
      const row = queue.rows[0];
      if (row && row.status !== 'retest') {
        await client.query(`UPDATE test_queue_entries SET status='retest',retest_count=retest_count+1,completed_at=NULL,note=$1,state_version=state_version+1,updated_at=now() WHERE id=$2`, [reason, row.id]);
        await client.query(`INSERT INTO queue_events(queue_entry_id,old_status,new_status,reason,actor_type,actor_id,station_id,happened_at) VALUES($1,$2,'retest',$3,'device',$4,$5,$6)`, [row.id, row.status, reason, device.id, row.station_id, endedAt]);
      }
    }
    await client.query(`UPDATE task_students SET status='待补测',completed_at=NULL,note=$1,version=version+1 WHERE id=$2`, [reason, session.task_student_id]);
    await client.query('COMMIT');
    await audit(null, { ...input, socket: { remoteAddress: null }, _requestId: input.requestId || crypto.randomUUID() }, 'field.session.abort', 'test_session', session.id, null, { deviceId: device.id, reason }, session.school_id);
    void publishFieldUpdate(session.school_id, 'session.aborted', { sessionId: session.id, taskId: session.task_id, studentId: session.student_id, stationId: session.station_id, status: 'aborted' });
    return { id: session.id, status: 'aborted', queueStatus: 'retest' };
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

export async function completeFieldSession(device, sessionId, input) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(`SELECT s.*,t.school_id,t.items AS task_items,ts.id AS task_student_id FROM test_sessions s
      JOIN assessment_tasks t ON t.id=s.task_id JOIN task_students ts ON ts.task_id=s.task_id AND ts.student_id=s.student_id
      WHERE (s.id=$1 OR s.client_session_id=$1) FOR UPDATE`, [sessionId]);
    const session = result.rows[0];
    if (!session || session.school_id !== device.school_id || session.edge_device_id !== device.id) throw Object.assign(new Error('测试会话不存在或不属于本设备'), { status: 404, code: 'FIELD_SESSION_NOT_FOUND' });
    if (['completed', 'needs_review', 'retest'].includes(session.status)) { await client.query('COMMIT'); return { id: session.id, status: session.status, idempotent: true }; }
    if (session.status === 'aborted') throw Object.assign(new Error('该会话已由现场端或后台中止并安排补测，迟到成绩不能覆盖中央状态'), { status: 409, code: 'FIELD_SESSION_ABORTED' });
    if (!['created', 'checked_in', 'testing'].includes(session.status)) throw Object.assign(new Error('当前会话已关闭，不能再提交成绩'), { status: 409, code: 'FIELD_SESSION_CLOSED' });
    if (!Array.isArray(input.scores) || !input.scores.length || input.scores.length > MOVEMENT_SCORE_RULES.itemCount) throw Object.assign(new Error('必须提交 1 到 7 项成绩'), { status: 400, code: 'FIELD_SCORES_INVALID' });
    const items = new Set();
    const savedScores = [];
    const evidence = Array.isArray(input.evidence) ? input.evidence : [];
    const endedAt = fieldIsoDate(input.endedAt);
    if (evidence.length > 30) throw Object.assign(new Error('证据文件超过上限'), { status: 400, code: 'FIELD_EVIDENCE_INVALID' });
    const validatedScores = [];
    for (const item of input.scores) {
      const itemCode = fieldInputString(item?.item, '体测项目', 64);
      const score = normalizeScore(item?.score);
      const confidence = normalizeConfidence(item?.confidence == null ? 0 : item.confidence);
      if (!MOVEMENT_ITEM_CODES.includes(itemCode) || score == null || confidence == null || items.has(itemCode)) throw Object.assign(new Error('成绩项目、分数或置信度不合法'), { status: 400, code: 'FIELD_SCORE_INVALID' });
      items.add(itemCode);
      validatedScores.push({ input: item, itemCode, score, confidence });
    }
    const scoreScope = scoreScopeDifference(session.task_items, [...items]);
    if (scoreScope.missing.length || scoreScope.unexpected.length) {
      const detail = [scoreScope.missing.length ? `缺少：${scoreScope.missing.join('、')}` : '', scoreScope.unexpected.length ? `超出任务：${scoreScope.unexpected.join('、')}` : ''].filter(Boolean).join('；');
      throw Object.assign(new Error(`设备成绩必须与任务项目完全一致（${detail}）`), { status: 409, code: 'FIELD_SCORE_SCOPE_MISMATCH' });
    }
    for (const validated of validatedScores) {
      const { input: item, itemCode, score, confidence } = validated;
      const reviewStatus = normalizeReviewStatus(item?.reviewStatus, confidence);
      const saved = await client.query(`INSERT INTO assessment_scores(task_id,student_id,item_code,score,confidence,note,source,review_status,manual_reviewed,created_by,session_id,algorithm_version,evidence_json)
        VALUES($1,$2,$3,$4,$5,$6,'field',$7,FALSE,NULL,$8,$9,$10)
        ON CONFLICT(task_id,student_id,item_code) DO UPDATE SET score=EXCLUDED.score,confidence=EXCLUDED.confidence,note=EXCLUDED.note,source='field',review_status=EXCLUDED.review_status,manual_reviewed=FALSE,created_by=NULL,session_id=EXCLUDED.session_id,algorithm_version=EXCLUDED.algorithm_version,evidence_json=EXCLUDED.evidence_json,updated_at=now()
        RETURNING id,item_code AS item,score,confidence,review_status AS "reviewStatus"`,
      [session.task_id, session.student_id, itemCode, score, confidence, String(item?.note || '').slice(0, 1000), reviewStatus, session.id, String(input.algorithmVersion || session.algorithm_version || '').slice(0, 120), fieldObject(item?.evidence)]);
      savedScores.push({ ...saved.rows[0], score: Number(saved.rows[0].score), confidence: Number(saved.rows[0].confidence) });
      await client.query(`UPDATE test_session_items SET status=$1,score=$2,confidence=$3,started_at=COALESCE(started_at,$4),completed_at=COALESCE(completed_at,$4),capture_summary_json=capture_summary_json || jsonb_build_object('reviewStatus',$5::text),updated_at=now()
        WHERE session_id=$6 AND item_code=$7`, [reviewStatus === 'pendingReview' ? 'needs_review' : 'completed', score, confidence, endedAt, reviewStatus, session.id, itemCode]);
    }
    for (const [ordinal, entry] of evidence.entries()) {
      const fileId = fieldInputString(entry?.fileId, '证据文件 ID');
      const file = await client.query(`SELECT id FROM files WHERE id=$1 AND status='uploaded' AND purpose='field_evidence' AND object_key LIKE $2`, [fileId, `field/${device.id}/%`]);
      if (!file.rows[0]) throw Object.assign(new Error('证据文件不存在、未上传或不属于本设备'), { status: 400, code: 'FIELD_EVIDENCE_NOT_FOUND' });
      const evidenceType = fieldInputString(entry?.evidenceType || 'other', '证据类型', 32);
      if (!['video', 'image', 'skeleton', 'timeline', 'calibration', 'log', 'other'].includes(evidenceType)) throw Object.assign(new Error('证据类型不合法'), { status: 400, code: 'FIELD_EVIDENCE_INVALID' });
      const retentionDays = fieldEvidenceRetentionDaysFor(evidenceType);
      await client.query(`INSERT INTO session_evidence(session_id,file_id,evidence_type,ordinal,checksum_sha256,metadata_json,retention_until,purged_at,purge_reason)
        VALUES($1,$2,$3,$4,$5,$6,$7::timestamptz+($8::int * interval '1 day'),NULL,NULL)
        ON CONFLICT(file_id) DO UPDATE SET session_id=EXCLUDED.session_id,evidence_type=EXCLUDED.evidence_type,ordinal=EXCLUDED.ordinal,metadata_json=EXCLUDED.metadata_json,retention_until=EXCLUDED.retention_until,purged_at=NULL,purge_reason=NULL`,
      [session.id, fileId, evidenceType, ordinal, entry?.checksumSha256 || null, fieldObject(entry?.metadata), endedAt, retentionDays]);
      await client.query(`UPDATE files SET retention_until=$1::timestamptz+($2::int * interval '1 day'),expires_at=NULL WHERE id=$3`, [endedAt, retentionDays, fileId]);
    }
    const needsReview = savedScores.some((score) => score.reviewStatus === 'pendingReview');
    const isRetest = input.outcome === 'retest';
    const sessionStatus = isRetest ? 'retest' : (needsReview ? 'needs_review' : 'completed');
    const queueStatus = isRetest ? 'retest' : 'completed';
    if (isRetest) await client.query(`UPDATE test_session_items SET status='retest',completed_at=NULL,updated_at=now() WHERE session_id=$1`, [session.id]);
    await client.query(`UPDATE test_sessions SET status=$1,ended_at=$2,device_ended_at=$2,algorithm_version=$3,summary_json=$4,sync_version=sync_version+1,updated_at=now() WHERE id=$5`,
    [sessionStatus, endedAt, String(input.algorithmVersion || session.algorithm_version || '').slice(0, 120), fieldObject(input.summary), session.id]);
    if (session.queue_entry_id) {
      const queue = await client.query('SELECT status FROM test_queue_entries WHERE id=$1 FOR UPDATE', [session.queue_entry_id]);
      await client.query(`UPDATE test_queue_entries SET status=$1,retest_count=retest_count+CASE WHEN $1='retest' THEN 1 ELSE 0 END,state_version=state_version+1,
        completed_at=CASE WHEN $1='completed' THEN COALESCE(completed_at,$2) ELSE completed_at END,updated_at=now() WHERE id=$3`, [queueStatus, endedAt, session.queue_entry_id]);
      await client.query(`INSERT INTO queue_events(queue_entry_id,old_status,new_status,reason,actor_type,actor_id,station_id,happened_at)
        VALUES($1,$2,$3,$4,'device',$5,$6,$7)`, [session.queue_entry_id, queue.rows[0]?.status || 'testing', queueStatus, String(input.reason || '').slice(0, 500), device.id, device.station_id || null, endedAt]);
    }
    const taskStatus = isRetest ? '待补测' : (needsReview ? '待复核' : '已完成');
    await client.query(`UPDATE task_students SET status=$1,completed_at=CASE WHEN $1='已完成' THEN COALESCE(completed_at,$2) ELSE completed_at END,version=version+1 WHERE id=$3`, [taskStatus, endedAt, session.task_student_id]);
    if (!isRetest) await client.query(`INSERT INTO job_queue(job_type,payload,available_at) VALUES('report.refresh',$1,now())`, [{ studentId: session.student_id, taskId: session.task_id, sessionId: session.id, schoolId: session.school_id }]);
    await client.query('COMMIT');
    await audit(null, { ...input, socket: { remoteAddress: null }, _requestId: input.requestId || crypto.randomUUID() }, 'field.session.complete', 'test_session', session.id, null, { deviceId: device.id, status: sessionStatus, scoreCount: savedScores.length }, session.school_id);
    void publishFieldUpdate(session.school_id, 'session.completed', { sessionId: session.id, taskId: session.task_id, studentId: session.student_id, stationId: session.station_id, status: sessionStatus, scoreCount: savedScores.length });
    return { id: session.id, status: sessionStatus, scores: savedScores, evidenceCount: evidence.length };
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}
