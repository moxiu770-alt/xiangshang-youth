/**
 * Activity discovery and registration lifecycle.
 *
 * The main server supplies its established auth, audit, response, and
 * idempotency helpers. This keeps the route contract unchanged while keeping
 * activity concurrency rules out of the monolithic HTTP entrypoint.
 */
export async function handleActivityRoutes(context) {
  const {
    req, res, user, url, parts,
    query, pool, hasRole, queryValue, studentForUser, fail,
    requiredString, schoolAllowed, assertPhone, beginIdempotentRequest,
    requestBodyHash, failIdempotently, audit, createdIdempotently,
    okIdempotently, ok
  } = context;

if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'activities' && parts[2] === 'registrations' && parts[3] === 'history') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以查看报名历史');
  const result = await query(`SELECT ar.id AS "registrationId",ar.activity_id AS "activityId",ar.child_id AS "childId",ar.contact_name AS "contactName",ar.phone,ar.status,ar.version,
      ar.created_at AS "createdAt",ar.updated_at AS "updatedAt",ar.cancelled_at AS "cancelledAt",a.title AS "activityTitle",a.starts_at AS "startsAt",a.ends_at AS "endsAt"
    FROM activity_registrations ar JOIN activities a ON a.id=ar.activity_id
    WHERE ar.user_id=$1 ORDER BY ar.created_at DESC LIMIT 100`, [user.id]);
  return ok(res, result.rows);
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'activities' && !parts[2]) {
  const schoolIds = user.roles.map((role) => role.school_id).filter(Boolean);
  const requestedChildId = queryValue(url, 'childId');
  if (requestedChildId) {
    const child = await studentForUser(user, requestedChildId);
    if (!child) return fail(res, 403, 'NO_PERMISSION', '无权查看该孩子的活动报名状态');
  }
  const result = await query(`SELECT a.id AS "activityId",a.school_id AS "schoolId",a.title,a.description,a.starts_at AS "startsAt",a.ends_at AS "endsAt",
      a.capacity,a.registration_start_at AS "registrationStartAt",a.registration_end_at AS "registrationEndAt",a.status,a.version,
      COUNT(ar.id)::int AS "registeredCount",
      GREATEST(COALESCE(a.capacity, 0)-COUNT(ar.id)::int, 0)::int AS "remainingCapacity",
      mine.id AS "registrationId",mine.status AS "registrationStatus",mine.child_id AS "childId"
    FROM activities a
    LEFT JOIN activity_registrations ar ON ar.activity_id=a.id AND ar.status NOT IN ('cancelled','rejected')
    LEFT JOIN activity_registrations mine ON mine.activity_id=a.id AND mine.user_id=$1 AND mine.child_id IS NOT DISTINCT FROM $3
    WHERE a.status IN ('published','active','cancelled') AND (a.school_id IS NULL OR a.school_id=ANY($2::text[]))
    GROUP BY a.id,mine.id,mine.status,mine.child_id
    ORDER BY COALESCE(a.starts_at,a.created_at) DESC LIMIT 100`, [user.id, schoolIds, requestedChildId || null]);
  return ok(res, result.rows.map((row) => ({ ...row, remainingCapacity: row.capacity == null ? null : row.remainingCapacity })));
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'activities' && parts[2]) {
  const activityId = requiredString(parts[2], '活动', { max: 120 });
  const requestedChildId = queryValue(url, 'childId');
  if (requestedChildId) {
    const child = await studentForUser(user, requestedChildId);
    if (!child) return fail(res, 403, 'NO_PERMISSION', '无权查看该孩子的活动报名状态');
  }
  const result = await query(`SELECT a.id AS "activityId",a.school_id AS "schoolId",a.title,a.description,a.starts_at AS "startsAt",a.ends_at AS "endsAt",
      a.capacity,a.registration_start_at AS "registrationStartAt",a.registration_end_at AS "registrationEndAt",a.status,a.version,
      COUNT(ar.id)::int AS "registeredCount",
      GREATEST(COALESCE(a.capacity, 0)-COUNT(ar.id)::int, 0)::int AS "remainingCapacity",
      mine.id AS "registrationId",mine.status AS "registrationStatus",mine.child_id AS "childId"
    FROM activities a
    LEFT JOIN activity_registrations ar ON ar.activity_id=a.id AND ar.status NOT IN ('cancelled','rejected')
    LEFT JOIN activity_registrations mine ON mine.activity_id=a.id AND mine.user_id=$2 AND mine.child_id IS NOT DISTINCT FROM $3
    WHERE a.id=$1
    GROUP BY a.id,mine.id,mine.status,mine.child_id`, [activityId, user.id, requestedChildId || null]);
  const row = result.rows[0];
  if (!row || (row.schoolId && !schoolAllowed(user, row.schoolId))) return fail(res, 404, 'ACTIVITY_NOT_FOUND', '活动不存在或无权访问');
  return ok(res, { ...row, remainingCapacity: row.capacity == null ? null : row.remainingCapacity });
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'activities' && parts[3] === 'registrations') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以报名活动');
  const input = await body(req);
  const activityId = requiredString(parts[2], '活动', { max: 120 });
  const activity = await query('SELECT id,school_id,status,capacity,registration_start_at,registration_end_at FROM activities WHERE id=$1', [activityId]);
  if (!activity.rowCount) return fail(res, 404, 'ACTIVITY_NOT_FOUND', '活动不存在或已下线');
  const activityRow = activity.rows[0];
  if (!['published', 'active'].includes(activityRow.status)) return fail(res, 409, 'ACTIVITY_NOT_AVAILABLE', '活动当前不可报名');
  if (activityRow.school_id && !schoolAllowed(user, activityRow.school_id)) return fail(res, 403, 'NO_PERMISSION', '无权报名该学校活动');
  const now = Date.now();
  if (activityRow.registration_start_at && new Date(activityRow.registration_start_at).getTime() > now) return fail(res, 409, 'ACTIVITY_REGISTRATION_NOT_STARTED', '报名尚未开始');
  if (activityRow.registration_end_at && new Date(activityRow.registration_end_at).getTime() < now) return fail(res, 409, 'ACTIVITY_REGISTRATION_CLOSED', '报名已截止');
  let childId = input.childId ? requiredString(input.childId, '孩子', { max: 120 }) : null;
  if (childId) {
    const child = await studentForUser(user, childId);
    if (!child || (activityRow.school_id && child.school_id !== activityRow.school_id)) return fail(res, 403, 'NO_PERMISSION', '无权为该孩子报名活动');
  }
  const contactName = requiredString(input.contactName, '联系人姓名', { max: 80 });
  const phone = assertPhone(input.phone);
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ activityId, childId, contactName, phone }));
  if (idempotency === false) return;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT id FROM activities WHERE id=$1 FOR UPDATE', [activityId]);
    const existing = await client.query(`SELECT id,status,version FROM activity_registrations
      WHERE activity_id=$1 AND user_id=$2 AND child_id IS NOT DISTINCT FROM $3 FOR UPDATE`, [activityId, user.id, childId]);
    const existingId = existing.rows[0]?.id || null;
    const count = await client.query(`SELECT COUNT(*)::int AS count FROM activity_registrations
      WHERE activity_id=$1 AND status NOT IN ('cancelled','rejected') AND ($2::text IS NULL OR id<>$2)`, [activityId, existingId]);
    if (activityRow.capacity != null && count.rows[0].count >= Number(activityRow.capacity)) {
      await client.query('ROLLBACK');
      return failIdempotently(req, res, 409, 'ACTIVITY_FULL', '活动名额已满');
    }
    const result = existingId
      ? await client.query(`UPDATE activity_registrations SET contact_name=$1,phone=$2,status='pending',version=version+1,updated_at=now(),cancelled_at=NULL
          WHERE id=$3 RETURNING id AS "registrationId",activity_id AS "activityId",child_id AS "childId",status,version,updated_at AS "updatedAt"`, [contactName, phone, existingId])
      : await client.query(`INSERT INTO activity_registrations(activity_id,user_id,child_id,contact_name,phone,status) VALUES($1,$2,$3,$4,$5,'pending')
          RETURNING id AS "registrationId",activity_id AS "activityId",child_id AS "childId",status,version,updated_at AS "updatedAt"`, [activityId, user.id, childId, contactName, phone]);
    await client.query('COMMIT');
    await audit(user, req, 'activity.register', 'activity_registration', result.rows[0].registrationId, null, { activityId, childId, contactName, phone }, activityRow.school_id);
    return createdIdempotently(res, user, idempotency, result.rows[0]);
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); throw error; } finally { client.release(); }
}
if (req.method === 'PUT' && parts[0] === 'v1' && parts[1] === 'activities' && parts[3] === 'registrations' && parts[4]) {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以修改报名');
  const input = await body(req);
  const registration = await query(`SELECT ar.*,a.school_id FROM activity_registrations ar JOIN activities a ON a.id=ar.activity_id WHERE ar.id=$1 AND ar.activity_id=$2 AND ar.user_id=$3`, [parts[4], parts[2], user.id]);
  const row = registration.rows[0];
  if (!row) return fail(res, 404, 'REGISTRATION_NOT_FOUND', '报名记录不存在');
  if (['cancelled','confirmed'].includes(row.status)) return fail(res, 409, 'REGISTRATION_LOCKED', '当前报名状态不可修改');
  const expectedVersion = input.expectedVersion == null ? null : Number(input.expectedVersion);
  if (expectedVersion != null && row.version !== expectedVersion) return fail(res, 409, 'VERSION_CONFLICT', '报名信息已更新，请刷新后重试');
  const contactName = requiredString(input.contactName, '联系人姓名', { max: 80 });
  const phone = assertPhone(input.phone);
  const childId = input.childId ? requiredString(input.childId, '孩子', { max: 120 }) : row.child_id;
  if (childId) {
    const child = await studentForUser(user, childId);
    if (!child || (row.school_id && child.school_id !== row.school_id)) return fail(res, 403, 'NO_PERMISSION', '无权为该孩子修改报名');
  }
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ registrationId: parts[4], childId, contactName, phone, expectedVersion }));
  if (idempotency === false) return;
  const updated = await query(`UPDATE activity_registrations SET child_id=$1,contact_name=$2,phone=$3,version=version+1,updated_at=now()
    WHERE id=$4 AND user_id=$5 AND ($6::int IS NULL OR version=$6)
    RETURNING id AS "registrationId",activity_id AS "activityId",child_id AS "childId",status,version,updated_at AS "updatedAt"`, [childId, contactName, phone, parts[4], user.id, expectedVersion]);
  if (!updated.rowCount) return failIdempotently(req, res, 409, 'VERSION_CONFLICT', '报名信息已更新，请刷新后重试');
  await audit(user, req, 'activity.registration.update', 'activity_registration', parts[4], row, updated.rows[0], row.school_id);
  return okIdempotently(res, user, idempotency, updated.rows[0]);
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'activities' && parts[3] === 'registrations' && parts[5] === 'cancel') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以取消报名');
  const input = await body(req);
  const registration = await query(`SELECT ar.*,a.school_id FROM activity_registrations ar JOIN activities a ON a.id=ar.activity_id WHERE ar.id=$1 AND ar.activity_id=$2 AND ar.user_id=$3`, [parts[4], parts[2], user.id]);
  const row = registration.rows[0];
  if (!row) return fail(res, 404, 'REGISTRATION_NOT_FOUND', '报名记录不存在');
  if (row.status === 'confirmed') return fail(res, 409, 'REGISTRATION_LOCKED', '学校已确认，取消请联系学校');
  const expectedVersion = input.expectedVersion == null ? null : Number(input.expectedVersion);
  if (expectedVersion != null && (!Number.isInteger(expectedVersion) || expectedVersion < 0)) return fail(res, 400, 'VERSION_INVALID', '报名版本不合法');
  if (expectedVersion != null && row.version !== expectedVersion) return fail(res, 409, 'VERSION_CONFLICT', '报名信息已更新，请刷新后重试');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ registrationId: parts[4], action: 'cancel', expectedVersion }));
  if (idempotency === false) return;
  const updated = await query(`UPDATE activity_registrations SET status='cancelled',cancelled_at=now(),version=version+1,updated_at=now()
    WHERE id=$1 AND user_id=$2 AND ($3::int IS NULL OR version=$3) RETURNING id AS "registrationId",activity_id AS "activityId",status,version,cancelled_at AS "cancelledAt"`, [parts[4], user.id, expectedVersion]);
  if (!updated.rowCount) return failIdempotently(req, res, 409, 'VERSION_CONFLICT', '报名信息已更新，请刷新后重试');
  await audit(user, req, 'activity.registration.cancel', 'activity_registration', parts[4], row, updated.rows[0], row.school_id);
  return okIdempotently(res, user, idempotency, updated.rows[0]);
}

  return false;
}
