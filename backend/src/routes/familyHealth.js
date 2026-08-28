/**
 * Child-scoped family health records. The module stores only structured
 * observations, session metrics and check-ins; it deliberately accepts no
 * camera frames, photos, or raw video.
 */
import { MODEL_REGISTRY } from '../modelRegistry.js';

export async function handleFamilyHealthRoutes(context) {
  const {
    req, res, user, url, parts,
    query, pool, hasRole, guardianStudentForUser, queryValue, fieldObject,
    body, requiredString, fail, beginIdempotentRequest, requestBodyHash,
    failIdempotently, audit, createdIdempotently, okIdempotently, ok
  } = context;

if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'training-sessions') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以查看跟练记录');
  const student = await guardianStudentForUser(user, parts[2]);
  if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
  const from = queryValue(url, 'from') || null;
  const to = queryValue(url, 'to') || null;
  const result = await query(`SELECT id,child_id AS "childId",day_id AS "dayId",completed_at AS "completedAt",duration_seconds AS "durationSeconds",
      completion_ratio AS "completionRatio",quality_score AS "qualityScore",camera_verified AS "cameraVerified",visual_units AS "visualUnits",
      manual_units AS "manualUnits",model_version AS "modelVersion",mode,created_at AS "createdAt",updated_at AS "updatedAt"
    FROM training_sessions WHERE user_id=$1 AND child_id=$2
      AND ($3::timestamptz IS NULL OR completed_at >= $3::timestamptz)
      AND ($4::timestamptz IS NULL OR completed_at < $4::timestamptz)
    ORDER BY completed_at DESC LIMIT 200`, [user.id, parts[2], from, to]);
  return ok(res, result.rows);
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'training-sessions') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以提交跟练记录');
  const student = await guardianStudentForUser(user, parts[2]);
  if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
  const input = await body(req);
  const sessionId = requiredString(input.sessionId, '跟练记录编号', { max: 120 });
  const dayId = Number(input.dayId);
  const completedAt = new Date(input.completedAt || '');
  const durationSeconds = Number(input.durationSeconds);
  const completionRatio = Number(input.completionRatio);
  const qualityScore = Number(input.qualityScore);
  const manualUnits = Number(input.manualUnits || 0);
  if (!Number.isInteger(dayId) || dayId < 0 || dayId >= 90 || !Number.isFinite(completedAt.getTime())) return fail(res, 400, 'TRAINING_SESSION_INVALID', '跟练日期或训练日不合法');
  if (!Number.isInteger(durationSeconds) || durationSeconds < 0 || durationSeconds > 86400) return fail(res, 400, 'TRAINING_SESSION_INVALID', '训练时长不合法');
  if (!Number.isFinite(completionRatio) || completionRatio < 0 || completionRatio > 1) return fail(res, 400, 'TRAINING_SESSION_INVALID', '完成比例不合法');
  if (!Number.isInteger(qualityScore) || qualityScore < 0 || qualityScore > 100) return fail(res, 400, 'TRAINING_SESSION_INVALID', '质量分不合法');
  if (!Number.isInteger(manualUnits) || manualUnits < 0 || manualUnits > 100000) return fail(res, 400, 'TRAINING_SESSION_INVALID', '手动完成次数不合法');
  const modelVersion = requiredString(input.modelVersion, '模型版本', { max: 120 });
  const mode = requiredString(input.mode || 'guidedTraining', '训练模式', { max: 60 });
  if (modelVersion !== MODEL_REGISTRY.followAlong.algorithmVersion) return fail(res, 409, 'MODEL_VERSION_UNSUPPORTED', '跟练模型版本与服务端当前版本不一致');
  if (MODEL_REGISTRY.followAlong.status !== 'human-validated' && (Boolean(input.cameraVerified) || qualityScore > 0)) {
    return fail(res, 409, 'MODEL_VALIDATION_PENDING', '动作识别尚未完成人工标注验证，不能提交摄像头验证或动作质量分');
  }
  const visualUnits = fieldObject(input.visualUnits);
  if (JSON.stringify(visualUnits).length > 4000) return fail(res, 400, 'TRAINING_SESSION_INVALID', '动作统计过长');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ ...input, childId: parts[2], sessionId }));
  if (idempotency === false) return;
  const existing = await query('SELECT user_id FROM training_sessions WHERE id=$1', [sessionId]);
  if (existing.rowCount && existing.rows[0].user_id !== user.id) return failIdempotently(req, res, 409, 'SESSION_ID_CONFLICT', '跟练记录编号已被占用');
  const result = await query(`INSERT INTO training_sessions(id,user_id,child_id,day_id,completed_at,duration_seconds,completion_ratio,quality_score,camera_verified,visual_units,manual_units,model_version,mode)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb,$11,$12,$13)
    ON CONFLICT(id) DO UPDATE SET completed_at=EXCLUDED.completed_at,duration_seconds=EXCLUDED.duration_seconds,completion_ratio=EXCLUDED.completion_ratio,
      quality_score=EXCLUDED.quality_score,camera_verified=EXCLUDED.camera_verified,visual_units=EXCLUDED.visual_units,manual_units=EXCLUDED.manual_units,
      model_version=EXCLUDED.model_version,mode=EXCLUDED.mode,updated_at=now()
    WHERE training_sessions.user_id=$2 AND training_sessions.child_id=$3
    RETURNING id,child_id AS "childId",day_id AS "dayId",completed_at AS "completedAt",duration_seconds AS "durationSeconds",completion_ratio AS "completionRatio",
      quality_score AS "qualityScore",camera_verified AS "cameraVerified",visual_units AS "visualUnits",manual_units AS "manualUnits",model_version AS "modelVersion",mode,created_at AS "createdAt",updated_at AS "updatedAt"`,
    [sessionId, user.id, parts[2], dayId, completedAt, durationSeconds, completionRatio, qualityScore, Boolean(input.cameraVerified), JSON.stringify(visualUnits), manualUnits, modelVersion, mode]);
  if (!result.rowCount) return failIdempotently(req, res, 409, 'SESSION_ID_CONFLICT', '跟练记录与其他孩子不匹配');
  await audit(user, req, 'training_session.upsert', 'training_session', sessionId, null, { ...result.rows[0], childId: parts[2] }, student.school_id);
  return okIdempotently(res, user, idempotency, result.rows[0]);
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'health-observations') {
  // These are private guardian observations. A teacher's class scope grants
  // access to school assessment data, not family health or wellbeing notes.
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有已绑定监护人可以查看家庭观察记录');
  const student = await guardianStudentForUser(user, parts[2]);
  if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
  const result = await query(`SELECT id,child_id AS "childId",category,form_version AS "formVersion",answers,frequency,severity,note,version,submitted_at AS "submittedAt",updated_at AS "updatedAt" FROM family_health_observations WHERE user_id=$1 AND child_id=$2 ORDER BY submitted_at DESC`, [user.id, parts[2]]);
  return ok(res, result.rows);
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'health-observations') {
  // Do not let school staff create guardian observations either.
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有已绑定监护人可以提交家庭观察记录');
  const student = await guardianStudentForUser(user, parts[2]);
  if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
  const input = await body(req);
  const category = requiredString(input.category, '观察类型', { max: 40 });
  if (!['vision', 'oral', 'mental'].includes(category)) return fail(res, 400, 'INVALID_ARGUMENT', '观察类型不支持');
  const formVersion = requiredString(input.formVersion || 'family-observation-v1', '表单版本', { max: 60 });
  const answers = Array.isArray(input.answers) ? input.answers.slice(0, 40) : [];
  if (!answers.length) return fail(res, 400, 'INVALID_ARGUMENT', '请至少填写一项家庭观察');
  if (JSON.stringify(answers).length > 8000) return fail(res, 400, 'INVALID_ARGUMENT', '观察记录过长');
  const allowedQuestionTypes = new Set(['single', 'multiple', 'frequency', 'severity', 'text']);
  for (const answer of answers) {
    if (!answer || typeof answer !== 'object') return fail(res, 400, 'INVALID_ARGUMENT', '观察答案格式不正确');
    const questionId = String(answer.questionId || '').trim();
    const questionType = String(answer.questionType || '').trim();
    const selectedOptionIds = answer.selectedOptionIds == null ? [] : answer.selectedOptionIds;
    if (!questionId || questionId.length > 120 || !allowedQuestionTypes.has(questionType) || !Array.isArray(selectedOptionIds) || selectedOptionIds.length > 20) {
      return fail(res, 400, 'INVALID_ARGUMENT', '观察答案字段不合法');
    }
    if (selectedOptionIds.some((option) => typeof option !== 'string' || option.trim().length === 0 || option.length > 120)) return fail(res, 400, 'INVALID_ARGUMENT', '观察选项不合法');
    if (answer.note != null && String(answer.note).length > 500) return fail(res, 400, 'INVALID_ARGUMENT', '观察补充说明过长');
    if (answer.required != null && typeof answer.required !== 'boolean') return fail(res, 400, 'INVALID_ARGUMENT', '观察必填标记不合法');
  }
  const expectedVersion = input.expectedVersion == null ? null : Number(input.expectedVersion);
  if (expectedVersion != null && (!Number.isInteger(expectedVersion) || expectedVersion < 0)) return fail(res, 400, 'VERSION_INVALID', '版本号不合法');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ childId: parts[2], category, formVersion, answers, expectedVersion }));
  if (idempotency === false) return;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const existing = await client.query(`SELECT id,version FROM family_health_observations
      WHERE user_id=$1 AND child_id=$2 AND category=$3 AND form_version=$4 FOR UPDATE`, [user.id, parts[2], category, formVersion]);
    const currentVersion = existing.rows[0] ? Number(existing.rows[0].version) : 0;
    if (expectedVersion != null && currentVersion !== expectedVersion) {
      await client.query('ROLLBACK');
      return failIdempotently(req, res, 409, 'VERSION_CONFLICT', '家庭观察记录已在其他设备更新，请刷新后重试');
    }
    const result = existing.rows[0]
      ? await client.query(`UPDATE family_health_observations SET answers=$1::jsonb,frequency=$2,severity=$3,note=$4,version=version+1,updated_at=now(),submitted_at=now()
          WHERE id=$5 RETURNING id,child_id AS "childId",category,form_version AS "formVersion",answers,frequency,severity,note,version,submitted_at AS "submittedAt",updated_at AS "updatedAt"`, [JSON.stringify(answers), input.frequency || null, input.severity || null, input.note || null, existing.rows[0].id])
      : await client.query(`INSERT INTO family_health_observations(user_id,child_id,category,form_version,answers,frequency,severity,note) VALUES($1,$2,$3,$4,$5::jsonb,$6,$7,$8)
          RETURNING id,child_id AS "childId",category,form_version AS "formVersion",answers,frequency,severity,note,version,submitted_at AS "submittedAt",updated_at AS "updatedAt"`, [user.id, parts[2], category, formVersion, JSON.stringify(answers), input.frequency || null, input.severity || null, input.note || null]);
    await client.query('COMMIT');
    await audit(user, req, 'family_health_observation.upsert', 'family_health_observation', result.rows[0].id, existing.rows[0] || null, { ...result.rows[0], childId: parts[2], category, formVersion }, student.school_id);
    return okIdempotently(res, user, idempotency, result.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally { client.release(); }
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'health-checkins') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以查看运动打卡');
  const student = await guardianStudentForUser(user, parts[2]);
  if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
  const from = queryValue(url, 'from') || null;
  const to = queryValue(url, 'to') || null;
  const validDate = (value) => {
    if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const [year, month, day] = value.split('-').map(Number);
    const date = new Date(Date.UTC(year, month - 1, day));
    return Number.isFinite(date.getTime()) && date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
  };
  if ((from && !validDate(from)) || (to && !validDate(to)) || (from && to && from > to)) return fail(res, 400, 'CHECKIN_INVALID', '运动记录日期范围不合法');
  const result = await query(`SELECT id,child_id AS "childId",check_in_date AS "checkInDate",activity_type AS "activityType",
      duration_minutes AS "durationMinutes",intensity,feeling,completed_recommended AS "completedRecommended",parent_note AS "parentNote",
      version,created_at AS "createdAt",updated_at AS "updatedAt"
    FROM health_checkins WHERE user_id=$1 AND child_id=$2
      AND ($3::date IS NULL OR check_in_date >= $3::date)
      AND ($4::date IS NULL OR check_in_date <= $4::date)
    ORDER BY check_in_date DESC,updated_at DESC LIMIT 366`, [user.id, parts[2], from, to]);
  return ok(res, result.rows);
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'health-checkins') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家庭账号可以提交运动打卡');
  const student = await guardianStudentForUser(user, parts[2]);
  if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
  const input = await body(req);
  const checkInDate = requiredString(input.checkInDate, '打卡日期', { max: 10 });
  if (!/^\d{4}-\d{2}-\d{2}$/.test(checkInDate)) return fail(res, 400, 'CHECKIN_INVALID', '打卡日期格式不合法');
  const [year, month, day] = checkInDate.split('-').map(Number);
  const parsedDate = new Date(Date.UTC(year, month - 1, day));
  if (!Number.isFinite(parsedDate.getTime()) || parsedDate.getUTCFullYear() !== year || parsedDate.getUTCMonth() !== month - 1 || parsedDate.getUTCDate() !== day) return fail(res, 400, 'CHECKIN_INVALID', '打卡日期不合法');
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai' }).format(new Date());
  if (checkInDate > today) return fail(res, 400, 'CHECKIN_INVALID', '不能记录未来日期');
  const activityType = requiredString(input.activityType, '运动类型', { max: 60 });
  const durationMinutes = Number(input.durationMinutes);
  if (!Number.isInteger(durationMinutes) || durationMinutes <= 0 || durationMinutes > 1440) return fail(res, 400, 'CHECKIN_INVALID', '运动时长不合法');
  const intensity = requiredString(input.intensity, '运动强度', { max: 20 });
  if (!['low', 'moderate', 'high'].includes(intensity)) return fail(res, 400, 'CHECKIN_INVALID', '运动强度不合法');
  const feeling = input.feeling == null ? null : requiredString(input.feeling, '主观感受', { max: 120 });
  const parentNote = input.parentNote == null ? null : requiredString(input.parentNote, '家长备注', { max: 1000 });
  const expectedVersion = input.expectedVersion == null ? null : Number(input.expectedVersion);
  if (expectedVersion != null && (!Number.isInteger(expectedVersion) || expectedVersion < 0)) return fail(res, 400, 'VERSION_INVALID', '版本号不合法');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ ...input, childId: parts[2], checkInDate }));
  if (idempotency === false) return;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const existing = await client.query(`SELECT id,version FROM health_checkins WHERE user_id=$1 AND child_id=$2 AND check_in_date=$3 FOR UPDATE`, [user.id, parts[2], checkInDate]);
    const currentVersion = existing.rows[0] ? Number(existing.rows[0].version) : 0;
    if (expectedVersion != null && currentVersion !== expectedVersion) {
      await client.query('ROLLBACK');
      return failIdempotently(req, res, 409, 'VERSION_CONFLICT', '运动打卡已在其他设备更新，请刷新后重试');
    }
    const result = existing.rows[0]
      ? await client.query(`UPDATE health_checkins SET activity_type=$1,duration_minutes=$2,intensity=$3,feeling=$4,completed_recommended=$5,parent_note=$6,version=version+1,updated_at=now()
          WHERE id=$7 RETURNING id,child_id AS "childId",check_in_date AS "checkInDate",activity_type AS "activityType",duration_minutes AS "durationMinutes",intensity,feeling,completed_recommended AS "completedRecommended",parent_note AS "parentNote",version,created_at AS "createdAt",updated_at AS "updatedAt"`, [activityType, durationMinutes, intensity, feeling, Boolean(input.completedRecommended), parentNote, existing.rows[0].id])
      : await client.query(`INSERT INTO health_checkins(user_id,child_id,check_in_date,activity_type,duration_minutes,intensity,feeling,completed_recommended,parent_note)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id,child_id AS "childId",check_in_date AS "checkInDate",activity_type AS "activityType",duration_minutes AS "durationMinutes",intensity,feeling,completed_recommended AS "completedRecommended",parent_note AS "parentNote",version,created_at AS "createdAt",updated_at AS "updatedAt"`, [user.id, parts[2], checkInDate, activityType, durationMinutes, intensity, feeling, Boolean(input.completedRecommended), parentNote]);
    await client.query('COMMIT');
    await audit(user, req, 'health_checkin.upsert', 'health_checkin', result.rows[0].id, existing.rows[0] || null, { ...result.rows[0], childId: parts[2] }, student.school_id);
    return okIdempotently(res, user, idempotency, result.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally { client.release(); }
}

  return false;
}
