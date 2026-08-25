/**
 * Expert catalogue, slot availability, and appointment lifecycle.
 *
 * Transaction locks, optimistic versions, scope validation, audit logging and
 * idempotency are injected by the HTTP composition root to preserve a single
 * service-wide policy implementation.
 */
export async function handleExpertAppointmentRoutes(context) {
  const {
    req, res, user, parts,
    query, pool, hasRole, schoolAllowed, studentForUser, fail,
    body, requiredString, beginIdempotentRequest, requestBodyHash,
    failIdempotently, audit, okIdempotently, createdIdempotently, ok
  } = context;

if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'experts' && !parts[2]) {
  const schoolIds = user.roles.map((role) => role.school_id).filter(Boolean);
  const result = await query(`SELECT id AS "expertId",school_id AS "schoolId",name,title,bio,status FROM experts WHERE status='active' AND (school_id IS NULL OR school_id=ANY($1::text[])) ORDER BY name LIMIT 100`, [schoolIds]);
  return ok(res, result.rows);
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'experts' && parts[2] && !parts[3]) {
  const result = await query(`SELECT id AS "expertId",school_id AS "schoolId",name,title,bio,status FROM experts WHERE id=$1 AND status='active'`, [parts[2]]);
  const row = result.rows[0];
  if (!row || (row.schoolId && !schoolAllowed(user, row.schoolId))) return fail(res, 404, 'EXPERT_NOT_FOUND', '专家不存在或无权访问');
  return ok(res, row);
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'experts' && parts[3] === 'available-slots') {
  const expert = await query(`SELECT id,school_id FROM experts WHERE id=$1 AND status='active'`, [parts[2]]);
  if (!expert.rowCount || (expert.rows[0].school_id && !schoolAllowed(user, expert.rows[0].school_id))) return fail(res, 404, 'EXPERT_NOT_FOUND', '专家不存在或无权访问');
  const result = await query(`SELECT s.id AS "slotId",s.expert_id AS "expertId",s.service_id AS "serviceId",s.scheduled_start_at AS "scheduledStartAt",s.scheduled_end_at AS "scheduledEndAt",
      s.capacity,s.version,(s.capacity-COUNT(a.id)::int)::int AS "remainingCapacity"
    FROM expert_slots s LEFT JOIN expert_appointments a ON a.slot_id=s.id AND a.status NOT IN ('cancelled','rejected')
    WHERE s.expert_id=$1 AND s.status='available' AND s.scheduled_start_at>now()
    GROUP BY s.id ORDER BY s.scheduled_start_at LIMIT 60`, [parts[2]]);
  return ok(res, result.rows.filter((row) => row.remainingCapacity > 0));
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'expert-appointments' && parts[2] === 'history') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以查看预约历史');
  const result = await query(`SELECT id AS "appointmentId",expert_id AS "expertId",service_id AS "serviceId",slot_id AS "slotId",child_id AS "childId",
      expert_name AS "expertName",preferred_date AS "preferredDate",scheduled_start_at AS "scheduledStartAt",scheduled_end_at AS "scheduledEndAt",
      status,version,note,created_at AS "createdAt",updated_at AS "updatedAt",cancelled_at AS "cancelledAt"
    FROM expert_appointments WHERE user_id=$1 ORDER BY created_at DESC LIMIT 100`, [user.id]);
  return ok(res, result.rows);
}
if (req.method === 'PUT' && parts[0] === 'v1' && parts[1] === 'expert-appointments' && parts[3] === 'reschedule') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以改期预约');
  const input = await body(req);
  const appointment = await query('SELECT * FROM expert_appointments WHERE id=$1 AND user_id=$2', [parts[2], user.id]);
  const current = appointment.rows[0];
  if (!current) return fail(res, 404, 'APPOINTMENT_NOT_FOUND', '预约不存在');
  if (!['pending','confirmed','reschedule_requested'].includes(current.status)) return fail(res, 409, 'APPOINTMENT_LOCKED', '当前预约状态不可改期');
  const expectedVersion = input.expectedVersion == null ? null : Number(input.expectedVersion);
  if (expectedVersion != null && current.version !== expectedVersion) return fail(res, 409, 'VERSION_CONFLICT', '预约已更新，请刷新后重试');
  const slotId = requiredString(input.slotId, '预约时段', { max: 120 });
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ appointmentId: parts[2], slotId, expectedVersion }));
  if (idempotency === false) return;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const slot = await client.query(`SELECT s.*,e.name AS expert_name FROM expert_slots s JOIN experts e ON e.id=s.expert_id WHERE s.id=$1 AND s.status='available' AND s.scheduled_start_at>now() FOR UPDATE`, [slotId]);
    const slotRow = slot.rows[0];
    if (!slotRow || (slotRow.school_id && !schoolAllowed(user, slotRow.school_id))) {
      await client.query('ROLLBACK');
      return failIdempotently(req, res, 404, 'SLOT_NOT_FOUND', '预约时段不存在或无权访问');
    }
    const count = await client.query(`SELECT COUNT(*)::int AS count FROM expert_appointments WHERE slot_id=$1 AND status NOT IN ('cancelled','rejected') AND id<>$2`, [slotId, parts[2]]);
    if (count.rows[0].count >= Number(slotRow.capacity)) {
      await client.query('ROLLBACK');
      return failIdempotently(req, res, 409, 'SLOT_FULL', '该时段已约满');
    }
    const updated = await client.query(`UPDATE expert_appointments SET expert_id=$1,slot_id=$2,service_id=$3,expert_name=$4,preferred_date=to_char($5::timestamptz,'YYYY-MM-DD HH24:MI'),scheduled_start_at=$5,scheduled_end_at=$6,status='reschedule_requested',version=version+1,updated_at=now()
      WHERE id=$7 AND user_id=$8 AND ($9::int IS NULL OR version=$9) RETURNING id AS "appointmentId",expert_id AS "expertId",service_id AS "serviceId",slot_id AS "slotId",child_id AS "childId",status,version,scheduled_start_at AS "scheduledStartAt",scheduled_end_at AS "scheduledEndAt"`,
      [slotRow.expert_id, slotId, slotRow.service_id, slotRow.expert_name, slotRow.scheduled_start_at, slotRow.scheduled_end_at, parts[2], user.id, expectedVersion]);
    if (!updated.rowCount) {
      await client.query('ROLLBACK');
      return failIdempotently(req, res, 409, 'VERSION_CONFLICT', '预约已更新，请刷新后重试');
    }
    await client.query('COMMIT');
    await audit(user, req, 'expert.appointment.reschedule', 'expert_appointment', parts[2], current, updated.rows[0], slotRow.school_id);
    return okIdempotently(res, user, idempotency, updated.rows[0]);
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); throw error; } finally { client.release(); }
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'expert-appointments' && parts[3] === 'cancel') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以取消预约');
  const input = await body(req);
  const appointment = await query('SELECT * FROM expert_appointments WHERE id=$1 AND user_id=$2', [parts[2], user.id]);
  const row = appointment.rows[0];
  if (!row) return fail(res, 404, 'APPOINTMENT_NOT_FOUND', '预约不存在');
  if (row.status === 'completed') return fail(res, 409, 'APPOINTMENT_LOCKED', '已完成预约不可取消');
  const expectedVersion = input.expectedVersion == null ? null : Number(input.expectedVersion);
  if (expectedVersion != null && (!Number.isInteger(expectedVersion) || expectedVersion < 0)) return fail(res, 400, 'VERSION_INVALID', '预约版本不合法');
  if (expectedVersion != null && row.version !== expectedVersion) return fail(res, 409, 'VERSION_CONFLICT', '预约已更新，请刷新后重试');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ appointmentId: parts[2], action: 'cancel', expectedVersion }));
  if (idempotency === false) return;
  const updated = await query(`UPDATE expert_appointments SET status='cancelled',cancelled_at=now(),version=version+1,updated_at=now()
    WHERE id=$1 AND user_id=$2 AND ($3::int IS NULL OR version=$3) RETURNING id AS "appointmentId",status,version,cancelled_at AS "cancelledAt"`, [parts[2], user.id, expectedVersion]);
  if (!updated.rowCount) return failIdempotently(req, res, 409, 'VERSION_CONFLICT', '预约已更新，请刷新后重试');
  await audit(user, req, 'expert.appointment.cancel', 'expert_appointment', parts[2], row, updated.rows[0], row.school_id);
  return okIdempotently(res, user, idempotency, updated.rows[0]);
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'expert-appointments') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以预约专家');
  const input = await body(req);
  const note = String(input.note || '').trim();
  if (note.length > 1000) return fail(res, 400, 'INVALID_ARGUMENT', '咨询说明长度不能超过1000个字符');
  let childId = input.childId ? requiredString(input.childId, '孩子', { max: 120 }) : null;
  if (childId && !await studentForUser(user, childId)) return fail(res, 403, 'NO_PERMISSION', '无权为该孩子预约专家');
  const slotId = input.slotId ? requiredString(input.slotId, '预约时段', { max: 120 }) : null;
  const expertId = input.expertId ? requiredString(input.expertId, '专家', { max: 120 }) : null;
  const serviceId = input.serviceId ? String(input.serviceId).trim().slice(0, 120) : null;
  const expertName = input.expertName ? requiredString(input.expertName, '专家', { max: 80 }) : '';
  const preferredDate = input.preferredDate ? requiredString(input.preferredDate, '预约时间', { max: 120 }) : '';
  if (!slotId && (!expertName || !preferredDate)) return fail(res, 400, 'INVALID_ARGUMENT', '请选择预约时段或填写专家和期望时间');
  const schoolId = input.schoolId || user.roles.find((role) => role.school_id)?.school_id || null;
  if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权为该学校预约专家');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ expertId, serviceId, slotId, childId, expertName, preferredDate, note, schoolId }));
  if (idempotency === false) return;
  if (!slotId) {
    const result = await query(`INSERT INTO expert_appointments(user_id,school_id,child_id,expert_name,preferred_date,note) VALUES($1,$2,$3,$4,$5,$6) RETURNING id AS "appointmentId",status,version`, [user.id, schoolId, childId, expertName, preferredDate, note]);
    return createdIdempotently(res, user, idempotency, result.rows[0]);
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const slot = await client.query(`SELECT s.*,e.name AS expert_name FROM expert_slots s JOIN experts e ON e.id=s.expert_id WHERE s.id=$1 AND s.status='available' AND s.scheduled_start_at>now() FOR UPDATE`, [slotId]);
    const slotRow = slot.rows[0];
    if (!slotRow || (slotRow.school_id && !schoolAllowed(user, slotRow.school_id))) {
      await client.query('ROLLBACK');
      return failIdempotently(req, res, 404, 'SLOT_NOT_FOUND', '预约时段不存在或无权访问');
    }
    const count = await client.query(`SELECT COUNT(*)::int AS count FROM expert_appointments WHERE slot_id=$1 AND status NOT IN ('cancelled','rejected')`, [slotId]);
    if (count.rows[0].count >= Number(slotRow.capacity)) {
      await client.query('ROLLBACK');
      return failIdempotently(req, res, 409, 'SLOT_FULL', '该时段已约满');
    }
    const result = await client.query(`INSERT INTO expert_appointments(user_id,school_id,expert_id,service_id,slot_id,child_id,expert_name,preferred_date,scheduled_start_at,scheduled_end_at,note,status)
      VALUES($1,$2,$3,$4,$5,$6,$7,to_char($8::timestamptz,'YYYY-MM-DD HH24:MI'),$8,$9,$10,'pending')
      RETURNING id AS "appointmentId",expert_id AS "expertId",service_id AS "serviceId",slot_id AS "slotId",child_id AS "childId",status,version,scheduled_start_at AS "scheduledStartAt",scheduled_end_at AS "scheduledEndAt"`,
      [user.id, slotRow.school_id || schoolId, slotRow.expert_id, slotRow.service_id || serviceId, slotId, childId, slotRow.expert_name, slotRow.scheduled_start_at, slotRow.scheduled_end_at, note]);
    await client.query('COMMIT');
    await audit(user, req, 'expert.appointment.create', 'expert_appointment', result.rows[0].appointmentId, null, result.rows[0], slotRow.school_id || schoolId);
    return createdIdempotently(res, user, idempotency, result.rows[0]);
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); throw error; } finally { client.release(); }
}

  return false;
}
