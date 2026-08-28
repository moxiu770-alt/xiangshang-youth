/** Teacher analytics, roster, task status, score and family binding routes. */
export async function handleTeacherTaskRoutes(context) {
  const {
    req, res, user, url, parts, query, pool, teacherOnly,
    userHasCapability, fail, schoolAllowed, teacherClassIds, queryValue,
    movementItemCodes: MOVEMENT_ITEM_CODES, ok, dashboard, pagination,
    parentOnly, hasRole, listResult, studentRow, beginIdempotentRequest,
    requestBodyHash, randomToken, sha256, audit, createdIdempotently,
    failIdempotently, body, requiredString, isProduction,
    taskStatusAllowed, okIdempotently, taskStudentForUser, studentForUser,
    movementScoreRules: MOVEMENT_SCORE_RULES, normalizeScoreRows,
    normalizeScore, normalizeConfidence, normalizeReviewStatus
  } = context;
  const operationalTaskOrder = (alias = '') => {
    const prefix = alias ? `${alias}.` : '';
    return `CASE WHEN ${prefix}test_date=current_date THEN 0 WHEN ${prefix}test_date<current_date THEN 1 ELSE 2 END,
      CASE WHEN ${prefix}test_date<=current_date THEN ${prefix}test_date END DESC,
      CASE WHEN ${prefix}test_date>current_date THEN ${prefix}test_date END ASC`;
  };
  const validTaskCompletionPredicate = (taskStudentAlias = 'ts', taskAlias = 't') => {
    const safeItems = `CASE WHEN jsonb_typeof(${taskAlias}.items)='array' THEN ${taskAlias}.items ELSE '[]'::jsonb END`;
    return `(${taskStudentAlias}.status='已完成'
      AND jsonb_array_length(${safeItems})>0
      AND (SELECT COUNT(DISTINCT completion_score.item_code) FROM assessment_scores completion_score
        WHERE completion_score.task_id=${taskStudentAlias}.task_id AND completion_score.student_id=${taskStudentAlias}.student_id
          AND completion_score.review_status='passed'
          AND completion_score.item_code IN (SELECT jsonb_array_elements_text(${safeItems})))=jsonb_array_length(${safeItems}))`;
  };
  const runQuery = (executor, sql, params) => typeof executor === 'function' ? executor(sql, params) : executor.query(sql, params);
  const taskCompletionState = async (executor, taskId, studentId, taskItems = null) => {
    let expected = Array.isArray(taskItems) ? taskItems.map((item) => String(item || '').trim()).filter(Boolean) : null;
    if (expected === null) {
      const task = await runQuery(executor, 'SELECT items FROM assessment_tasks WHERE id=$1', [taskId]);
      expected = task.rows[0]?.items;
    }
    if (!Array.isArray(expected) || expected.length < 1 || expected.length > MOVEMENT_ITEM_CODES.length || new Set(expected).size !== expected.length || expected.some((item) => !MOVEMENT_ITEM_CODES.includes(item))) {
      throw Object.assign(new Error('任务项目配置不完整，不能确认学生已完成'), { status: 409, code: 'TASK_ITEMS_INVALID' });
    }
    const scores = await runQuery(executor, `SELECT item_code AS item,review_status AS "reviewStatus" FROM assessment_scores
      WHERE task_id=$1 AND student_id=$2 AND item_code=ANY($3::text[])`, [taskId, studentId, expected]);
    const present = new Set(scores.rows.map((item) => item.item));
    const missingItems = expected.filter((item) => !present.has(item));
    const pendingReviewItems = scores.rows.filter((item) => item.reviewStatus === 'pendingReview').map((item) => item.item);
    return { requiredItemCount: expected.length, measuredItemCount: present.size, missingItems, pendingReviewItems, canComplete: missingItems.length === 0 && pendingReviewItems.length === 0 };
  };
  const requireTaskCompletion = async (executor, taskId, studentId, taskItems = null) => {
    const state = await taskCompletionState(executor, taskId, studentId, taskItems);
    if (state.missingItems.length) throw Object.assign(new Error(`成绩尚未完整，缺少：${state.missingItems.join('、')}`), { status: 409, code: 'TASK_COMPLETION_SCORES_INCOMPLETE', data: state });
    if (state.pendingReviewItems.length) throw Object.assign(new Error(`以下成绩仍待复核：${state.pendingReviewItems.join('、')}`), { status: 409, code: 'TASK_COMPLETION_REVIEW_PENDING', data: state });
    return state;
  };

if (req.method === 'GET' && url.pathname === '/v1/teacher/analytics/overview') {
  if (!teacherOnly(user) || !await userHasCapability(user, 'VIEW_CLASS_DASHBOARD')) return fail(res, 403, 'CAPABILITY_DENIED', '当前账号无查看班级看板权限');
  const schoolId = queryValue(url, 'schoolId');
  const classId = queryValue(url, 'classId');
  const taskId = queryValue(url, 'taskId');
  if (!schoolId || !classId || !taskId) return fail(res, 400, 'ANALYTICS_FILTER_REQUIRED', '请选择学校、班级和测评任务');
  if (!schoolAllowed(user, schoolId) || !teacherClassIds(user, schoolId).includes(classId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该班级看板');
  const task = await query('SELECT id,rule_version FROM assessment_tasks WHERE id=$1 AND school_id=$2', [taskId, schoolId]);
  if (!task.rows[0]) return fail(res, 404, 'TASK_NOT_FOUND', '测评任务不存在或不属于该学校');
  const standardVersion = queryValue(url, 'standardVersion');
  if (standardVersion && standardVersion !== task.rows[0].rule_version) return fail(res, 409, 'STANDARD_VERSION_MISMATCH', '评分标准已更新，请刷新看板');
  const summary = await query(`SELECT COUNT(ts.id)::int AS "totalCount",
    COUNT(ts.id) FILTER(WHERE ${validTaskCompletionPredicate('ts', 'completion_task')})::int AS "completedCount",
    COUNT(ts.id) FILTER(WHERE ts.status='未签到')::int AS "notCheckedInCount",
    COUNT(ts.id) FILTER(WHERE ts.status='已签到')::int AS "checkedInCount",
    COUNT(ts.id) FILTER(WHERE ts.status='候测')::int AS "waitingCount",
    COUNT(ts.id) FILTER(WHERE ts.status='测试中')::int AS "testingCount",
    COUNT(ts.id) FILTER(WHERE ts.status='待复核')::int AS "reviewCount",
    COUNT(ts.id) FILTER(WHERE ts.status='待补测')::int AS "retestCount",
    COUNT(ts.id) FILTER(WHERE ts.status='缺席')::int AS "absentCount",
    COUNT(ts.id) FILTER(WHERE ts.status='未完成')::int AS "incompleteCount",
    COUNT(DISTINCT ts.student_id) FILTER(WHERE ts.status IN ('待复核','待补测') OR EXISTS (
      SELECT 1 FROM assessment_scores risk_score WHERE risk_score.task_id=ts.task_id AND risk_score.student_id=ts.student_id
        AND (risk_score.score < 3 OR risk_score.review_status='pendingReview')
    ))::int AS "riskCount",
    COUNT(DISTINCT ts.student_id) FILTER(WHERE EXISTS (
      SELECT 1 FROM assessment_scores low_score WHERE low_score.task_id=ts.task_id AND low_score.student_id=ts.student_id AND low_score.score < 3
    ))::int AS "lowScoreCount"
    FROM task_students ts JOIN assessment_tasks completion_task ON completion_task.id=ts.task_id JOIN students st ON st.id=ts.student_id WHERE ts.task_id=$1 AND st.class_id=$2`, [taskId, classId]);
  // Cross join the canonical seven-item catalogue with this class's task
  // roster. This deliberately returns zero-measurement rows instead of
  // removing an item that has not started yet; clients can distinguish
  // absence of data from a missing component of the standard.
  const items = await query(`WITH item_codes(item_code) AS (SELECT unnest($3::text[]))
    SELECT code.item_code AS "itemCode",COUNT(DISTINCT ts.student_id)::int AS "totalCount",
      COUNT(DISTINCT ts.student_id) FILTER(WHERE score.id IS NOT NULL)::int AS "measuredCount",
      COALESCE(ROUND(AVG(score.score)::numeric,2),0)::float AS "averageScore",
      COUNT(DISTINCT ts.student_id) FILTER(WHERE score.review_status IN ('risk','retest','review','pendingReview'))::int AS "riskCount"
    FROM item_codes code
    LEFT JOIN task_students ts ON ts.task_id=$1
    LEFT JOIN students st ON st.id=ts.student_id AND st.class_id=$2
    LEFT JOIN assessment_scores score ON score.task_id=ts.task_id AND score.student_id=ts.student_id AND score.item_code=code.item_code
    WHERE st.id IS NOT NULL
    GROUP BY code.item_code ORDER BY code.item_code`, [taskId, classId, MOVEMENT_ITEM_CODES]);
  const byItem = new Map(items.rows.map((item) => [item.itemCode, item]));
  const normalizedItems = MOVEMENT_ITEM_CODES.map((itemCode) => {
    const item = byItem.get(itemCode) || { itemCode, totalCount: Number(summary.rows[0].totalCount || 0), measuredCount: 0, averageScore: 0, riskCount: 0 };
    return { ...item, completionRate: item.totalCount ? Math.round(item.measuredCount * 100 / item.totalCount) : 0 };
  });
  return ok(res, { ...summary.rows[0], schoolId, classId, taskId, standardVersion: task.rows[0].rule_version, itemStats: normalizedItems, dataAvailable: summary.rows[0].totalCount > 0, history: [] });
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'schools' && parts[3] === 'dashboard') {
  return ok(res, await dashboard(user, parts[2], { studentPage: queryValue(url, 'studentPage'), studentPageSize: queryValue(url, 'studentPageSize') }));
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'schools' && parts[3] === 'students') {
  const schoolId = parts[2];
  if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
  const requestedClass = queryValue(url, 'classId') || null;
  const search = queryValue(url, 'search') || null;
  const page = pagination(url);
  const params = [schoolId];
  let classFilter = '';
  let searchFilter = '';
  if (parentOnly(user)) { params.push(user.id); classFilter = ` AND EXISTS (SELECT 1 FROM parent_student_bindings pb WHERE pb.parent_user_id=$2 AND pb.student_id=st.id AND pb.status='active')`; }
  else if (hasRole(user, 'teacher') && !hasRole(user, 'principal', 'admin')) {
    const allowedClassIds = teacherClassIds(user, schoolId);
    params.push(requestedClass ? (allowedClassIds.includes(requestedClass) ? requestedClass : '__none__') : (allowedClassIds.length ? allowedClassIds : ['__none__']));
    classFilter = requestedClass ? ' AND st.class_id=$2' : ' AND st.class_id=ANY($2)';
  } else if (requestedClass) { params.push(requestedClass); classFilter = ' AND st.class_id=$2'; }
  if (search) { params.push(`%${search}%`); searchFilter = ` AND (st.name ILIKE $${params.length} OR COALESCE(st.student_no,'') ILIKE $${params.length})`; }
  const count = await query(`SELECT COUNT(*)::int AS total FROM students st WHERE st.school_id=$1 AND st.status='active'${classFilter}${searchFilter}`, params);
  params.push(page.pageSize, page.offset);
  const result = await query(`SELECT st.*,g.name AS grade_name,c.name AS class_name FROM students st JOIN grades g ON g.id=st.grade_id JOIN classes c ON c.id=st.class_id
    WHERE st.school_id=$1 AND st.status='active'${classFilter}${searchFilter} ORDER BY st.name LIMIT $${params.length - 1} OFFSET $${params.length}`, params);
  return ok(res, listResult(url, result.rows.map(studentRow), count.rows[0].total));
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'students' && parts[4] === 'binding-code') {
  if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有管理员或校长可以生成绑定码');
  const student = await query('SELECT id,school_id,name FROM students WHERE id=$1 AND status=\'active\'', [parts[3]]);
  if (!student.rows[0] || !schoolAllowed(user, student.rows[0].school_id)) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentId: parts[3], action: 'binding-code' }));
  if (idempotency === false) return;
  const bindingCode = randomToken().slice(0, 12).toUpperCase();
  const expiresAt = new Date(Date.now() + 30 * 60_000);
  await query('UPDATE student_binding_codes SET used_at=COALESCE(used_at,now()) WHERE student_id=$1 AND used_at IS NULL', [parts[3]]);
  const result = await query(`INSERT INTO student_binding_codes(student_id,code_hash,expires_at,created_by)
    VALUES($1,$2,$3,$4) RETURNING id,student_id AS "studentId",expires_at AS "expiresAt"`, [parts[3], sha256(bindingCode), expiresAt, user.id]);
  await audit(user, req, 'student.binding_code.create', 'student', parts[3], null, { ...result.rows[0], codeIssued: true }, student.rows[0].school_id);
  return createdIdempotently(res, user, idempotency, { ...result.rows[0], bindingCode, studentName: student.rows[0].name });
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'bind') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家长可以绑定孩子');
  const student = await query('SELECT * FROM students WHERE id=$1 AND status=\'active\'', [parts[2]]);
  const code = queryValue(url, 'code');
  if (!student.rows[0] || !code) return fail(res, 400, 'BINDING_CODE_INVALID', '绑定码无效');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentId: parts[2], code: String(code).trim().toUpperCase() }));
  if (idempotency === false) return;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const issued = await client.query(`SELECT id FROM student_binding_codes WHERE student_id=$1 AND code_hash=$2 AND used_at IS NULL AND expires_at>now() FOR UPDATE`, [parts[2], sha256(String(code).trim().toUpperCase())]);
    if (!issued.rows[0] && !( !isProduction && code === student.rows[0].student_no)) {
      await client.query('ROLLBACK');
      return fail(res, 400, 'BINDING_CODE_INVALID', '绑定码无效或已过期');
    }
    const result = await client.query(`INSERT INTO parent_student_bindings(parent_user_id,student_id,relation,binding_code) VALUES($1,$2,$3,NULL)
      ON CONFLICT(parent_user_id,student_id) DO UPDATE SET status='active',expires_at=NULL RETURNING id,parent_user_id AS "parentId",student_id,relation`, [user.id, parts[2], '监护人']);
    if (issued.rows[0]) await client.query('UPDATE student_binding_codes SET used_at=now(),used_by=$1 WHERE id=$2', [user.id, issued.rows[0].id]);
    await client.query('COMMIT');
    await audit(user, req, 'student.bind', 'student', parts[2], null, result.rows[0], student.rows[0].school_id);
    const detail = await studentForUser(user, parts[2]);
    return createdIdempotently(res, user, idempotency, { ...result.rows[0], student: studentRow(detail) });
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}
if (req.method === 'POST' && url.pathname === '/v1/students/bind') {
  if (!hasRole(user, 'parent')) return fail(res, 403, 'NO_PERMISSION', '只有家长可以绑定孩子');
  const input = await body(req);
  const studentName = requiredString(input.studentName, '学生姓名', { max: 80 });
  const code = requiredString(input.code, '绑定码', { max: 128 }).toUpperCase();
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentName, code }));
  if (idempotency === false) return;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const studentResult = await client.query(`SELECT st.*, g.name AS grade_name, c.name AS class_name
      FROM students st JOIN grades g ON g.id=st.grade_id JOIN classes c ON c.id=st.class_id
      WHERE st.name=$1 AND st.status='active' ORDER BY st.created_at DESC LIMIT 10 FOR UPDATE OF st`, [studentName]);
    let matched = null;
    for (const candidate of studentResult.rows) {
      const issued = await client.query(`SELECT id FROM student_binding_codes WHERE student_id=$1 AND code_hash=$2 AND used_at IS NULL AND expires_at>now() FOR UPDATE`, [candidate.id, sha256(code)]);
      if (issued.rows[0] || (!isProduction && candidate.student_no === code)) { matched = { student: candidate, issued: issued.rows[0] || null }; break; }
    }
    if (!matched) { await client.query('ROLLBACK'); return failIdempotently(req, res, 400, 'BINDING_CODE_INVALID', '姓名或绑定码无效或已过期'); }
    const result = await client.query(`INSERT INTO parent_student_bindings(parent_user_id,student_id,relation,binding_code)
      VALUES($1,$2,$3,NULL) ON CONFLICT(parent_user_id,student_id) DO UPDATE SET status='active',expires_at=NULL
      RETURNING id,parent_user_id AS "parentId",student_id`, [user.id, matched.student.id, '监护人']);
    if (matched.issued) await client.query('UPDATE student_binding_codes SET used_at=now(),used_by=$1 WHERE id=$2', [user.id, matched.issued.id]);
    await client.query('COMMIT');
    await audit(user, req, 'student.bind', 'student', matched.student.id, null, result.rows[0], matched.student.school_id);
    const detail = await studentForUser(user, matched.student.id);
    return createdIdempotently(res, user, idempotency, { ...result.rows[0], student: studentRow(detail) });
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'schools' && parts[3] === 'tasks') {
  const schoolId = parts[2];
  if (!schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校');
  const page = pagination(url);
  const gradeId = queryValue(url, 'gradeId') || null;
  const classId = queryValue(url, 'classId') || null;
  const parentScope = parentOnly(user);
  const scopeJoin = parentScope ? ` JOIN task_students visible_ts ON visible_ts.task_id=t.id
    JOIN parent_student_bindings visible_pb ON visible_pb.student_id=visible_ts.student_id AND visible_pb.parent_user_id=$4 AND visible_pb.status='active'` : '';
  const countParams = parentScope ? [schoolId, gradeId, classId, user.id] : [schoolId, gradeId, classId];
  const count = await query(`SELECT COUNT(DISTINCT t.id)::int AS total FROM assessment_tasks t${scopeJoin}
    WHERE t.school_id=$1 AND ($2::text IS NULL OR t.grade_id=$2) AND ($3::text IS NULL OR t.class_id=$3)`, countParams);
  const taskParams = parentScope ? [schoolId, gradeId, classId, user.id, page.pageSize, page.offset] : [schoolId, gradeId, classId, page.pageSize, page.offset];
  const parentGroup = parentScope ? ',visible_pb.parent_user_id' : '';
  const limitIndex = parentScope ? 5 : 4;
  const offsetIndex = parentScope ? 6 : 5;
  const visibleTaskAlias = parentScope ? 'visible_ts' : 'ts';
  const visibleTaskId = `${visibleTaskAlias}.id`;
  const result = await query(`SELECT t.id,t.title,t.test_date::text AS date,t.location,COALESCE(g.name,'全校') AS "gradeName",COALESCE(c.name,'全校') AS "className",t.items,t.rule_version AS "ruleVersion",t.protocol_snapshot_json AS "protocolSnapshot",t.status,
    CASE WHEN t.class_id IS NULL THEN ARRAY[]::text[] ELSE ARRAY[t.class_id] END AS "classIds",COALESCE(ARRAY_AGG(DISTINCT ${visibleTaskAlias}.student_id) FILTER(WHERE ${visibleTaskAlias}.student_id IS NOT NULL), ARRAY[]::text[]) AS "studentIds",COUNT(DISTINCT ${visibleTaskId})::int AS "totalCount",COUNT(DISTINCT ${visibleTaskId}) FILTER(WHERE ${validTaskCompletionPredicate(visibleTaskAlias, 't')})::int AS "completedCount" FROM assessment_tasks t LEFT JOIN grades g ON g.id=t.grade_id LEFT JOIN classes c ON c.id=t.class_id LEFT JOIN task_students ts ON ts.task_id=t.id${scopeJoin}
    WHERE t.school_id=$1 AND ($2::text IS NULL OR t.grade_id=$2) AND ($3::text IS NULL OR t.class_id=$3) GROUP BY t.id,g.name,c.name,t.class_id${parentGroup} ORDER BY ${operationalTaskOrder('t')},t.created_at DESC LIMIT $${limitIndex} OFFSET $${offsetIndex}`, taskParams);
  return ok(res, listResult(url, result.rows.map((row) => {
    const progressStatus = row.completedCount === row.totalCount && row.totalCount > 0
      ? '已完成'
      : row.status === 'published' ? '未签到'
        : row.status === 'closed' ? '已关闭' : row.status;
    return { ...row, items: row.items || [], lifecycleStatus: row.status, progressStatus, status: progressStatus };
  }), count.rows[0].total));
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'tasks' && parts[2] && parts[3] === 'students' && parts.length === 4) {
  const taskResult = await query('SELECT id,school_id FROM assessment_tasks WHERE id=$1', [parts[2]]);
  const task = taskResult.rows[0];
  if (!task || !schoolAllowed(user, task.school_id)) return fail(res, 404, 'TASK_NOT_FOUND', '任务不存在或无权访问');
  if (teacherOnly(user) && !await userHasCapability(user, 'VIEW_TEST_TASKS', task.school_id)) return fail(res, 403, 'CAPABILITY_DENIED', '当前账号无查看测评任务权限');
  const params = [parts[2]];
  const page = pagination(url, 200);
  const statusFilter = queryValue(url, 'status');
  const keyword = queryValue(url, 'keyword');
  let scope = '';
  if (hasRole(user, 'teacher') && !hasRole(user, 'principal', 'admin')) {
    const classIds = teacherClassIds(user, task.school_id);
    params.push(classIds.length ? classIds : ['__none__']);
    scope = ` AND st.class_id=ANY($2)`;
  }
  if (parentOnly(user)) {
    params.push(user.id);
    scope = ` AND EXISTS (SELECT 1 FROM parent_student_bindings visible_pb WHERE visible_pb.parent_user_id=$${params.length} AND visible_pb.student_id=st.id AND visible_pb.status='active')`;
  }
  if (statusFilter) { params.push(statusFilter); scope += ` AND ts.status=$${params.length}`; }
  if (keyword) { params.push(`%${keyword}%`); scope += ` AND (st.name ILIKE $${params.length} OR c.name ILIKE $${params.length})`; }
  const limitIndex = params.length + 1;
  const offsetIndex = params.length + 2;
  const result = await query(`SELECT ts.id,ts.task_id AS "taskId",ts.student_id AS "studentId",ts.status,ts.version,st.name AS "studentName",st.gender AS "studentGender",st.grade_id AS "gradeId",g.name AS "gradeName",st.class_id AS "classId",c.name AS "className",
      jsonb_array_length(t.items)::int AS "requiredItemCount",completion.measured_count AS "measuredItemCount",completion.pending_review_count AS "pendingReviewCount",
      (jsonb_array_length(t.items)>0 AND completion.measured_count=jsonb_array_length(t.items) AND completion.pending_review_count=0) AS "completionReady"
    FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id JOIN students st ON st.id=ts.student_id JOIN classes c ON c.id=st.class_id LEFT JOIN grades g ON g.id=st.grade_id
    LEFT JOIN LATERAL (SELECT COUNT(DISTINCT score.item_code) FILTER(WHERE score.item_code IN (SELECT jsonb_array_elements_text(t.items)))::int AS measured_count,
      COUNT(*) FILTER(WHERE score.item_code IN (SELECT jsonb_array_elements_text(t.items)) AND score.review_status='pendingReview')::int AS pending_review_count
      FROM assessment_scores score WHERE score.task_id=ts.task_id AND score.student_id=ts.student_id) completion ON TRUE
    WHERE ts.task_id=$1${scope} ORDER BY c.name,st.name LIMIT $${limitIndex} OFFSET $${offsetIndex}`, [...params, page.pageSize, page.offset]);
  if (!page.paged) return ok(res, result.rows);
  const count = await query(`SELECT COUNT(*)::int AS total FROM task_students ts JOIN students st ON st.id=ts.student_id JOIN classes c ON c.id=st.class_id WHERE ts.task_id=$1${scope}`, params);
  return ok(res, { items: result.rows, page: page.page, pageSize: page.pageSize, total: count.rows[0]?.total || 0 });
}
if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'tasks' && parts[3] === 'students' && parts[5] === 'status') {
  if (!hasRole(user, 'teacher', 'principal', 'admin')) return fail(res, 403, 'NO_PERMISSION', '无权修改测评状态');
  const input = await body(req);
  const result = await query(`SELECT ts.*,t.school_id,t.items,st.class_id FROM task_students ts JOIN assessment_tasks t ON t.id=ts.task_id JOIN students st ON st.id=ts.student_id WHERE ts.task_id=$1 AND ts.student_id=$2`, [parts[2], parts[4]]);
  const row = result.rows[0];
  if (!row || !schoolAllowed(user, row.school_id)) return fail(res, 404, 'TASK_STUDENT_NOT_FOUND', '任务学生不存在');
  if (hasRole(user, 'teacher') && !hasRole(user, 'principal', 'admin') && !teacherClassIds(user, row.school_id).includes(row.class_id)) return fail(res, 403, 'NO_PERMISSION', '无权修改该班级测评状态');
  if (teacherOnly(user) && !await userHasCapability(user, 'UPDATE_TEST_STATUS', row.school_id, row.class_id)) return fail(res, 403, 'CAPABILITY_DENIED', '当前账号无更新测评状态权限');
  if (!taskStatusAllowed(row.status, input.status)) return fail(res, 409, 'TASK_STATUS_INVALID', `不能从${row.status}变更为${input.status}`);
  if (input.status === '已完成') await requireTaskCompletion(query, parts[2], parts[4], row.items);
  const expectedVersion = input.expectedVersion == null ? null : Number(input.expectedVersion);
  if (expectedVersion != null && (!Number.isInteger(expectedVersion) || expectedVersion < 1)) return fail(res, 400, 'VERSION_INVALID', '版本号不合法');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ taskId: parts[2], studentId: parts[4], ...input }));
  if (idempotency === false) return;
  const updated = await query(`UPDATE task_students SET status=$1,note=$2,check_in_at=CASE WHEN $1='已签到' THEN COALESCE(check_in_at,now()) ELSE check_in_at END,
    completed_at=CASE WHEN $1='已完成' THEN COALESCE(completed_at,now()) ELSE completed_at END,version=version+1 WHERE task_id=$3 AND student_id=$4 AND ($5::int IS NULL OR version=$5) RETURNING *`, [input.status, input.note || null, parts[2], parts[4], expectedVersion]);
  if (!updated.rowCount) return failIdempotently(req, res, 409, 'VERSION_CONFLICT', '记录已被其他人更新，请刷新后重试');
  await query(`INSERT INTO task_student_status_events(task_id,student_id,from_status,to_status,note,reason_code,operator_teacher_id,expected_version,resulting_version,client_operation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, [parts[2], parts[4], row.status, input.status, input.note || null, input.reasonCode || null, user.id, expectedVersion, updated.rows[0].version, input.clientOperationId || null]);
  await audit(user, req, 'task.status.update', 'task_student', row.id, row, updated.rows[0], row.school_id);
  return okIdempotently(res, user, idempotency, updated.rows[0]);
}
if (req.method === 'POST' && (url.pathname === '/v1/admin/tasks/batch-status' || (parts[0] === 'v1' && parts[1] === 'tasks' && parts[2] && parts[3] === 'students' && parts[4] === 'batch-status'))) {
  if (!hasRole(user, 'teacher', 'principal', 'admin')) return fail(res, 403, 'NO_PERMISSION', '无权批量修改测评状态');
  const input = await body(req);
  if (!Array.isArray(input.updates) || input.updates.length < 1 || input.updates.length > 100) return fail(res, 400, 'BATCH_INVALID', '批量更新数量必须在 1 到 100 条之间');
  const scopedTaskId = parts[0] === 'v1' && parts[1] === 'tasks' ? parts[2] : null;
  if (scopedTaskId && input.updates.some((item) => item.taskId && item.taskId !== scopedTaskId)) return fail(res, 400, 'BATCH_TASK_MISMATCH', '批量操作只能包含当前任务的学生');
  if (scopedTaskId) input.updates = input.updates.map((item) => ({ ...item, taskId: scopedTaskId }));
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
  if (idempotency === false) return;
  const client = await pool.connect();
  const saved = [];
  try {
    await client.query('BEGIN');
    for (const item of input.updates) {
      const rowResult = await client.query(`SELECT ts.*,t.school_id,t.items,st.class_id FROM task_students ts
        JOIN assessment_tasks t ON t.id=ts.task_id JOIN students st ON st.id=ts.student_id
        WHERE ts.task_id=$1 AND ts.student_id=$2 FOR UPDATE`, [item.taskId, item.studentId]);
      const row = rowResult.rows[0];
      if (!row || !schoolAllowed(user, row.school_id)) throw Object.assign(new Error('任务学生不存在或无权访问'), { status: 404, code: 'TASK_STUDENT_NOT_FOUND' });
      if (hasRole(user, 'teacher') && !hasRole(user, 'principal', 'admin') && !teacherClassIds(user, row.school_id).includes(row.class_id)) throw Object.assign(new Error('无权修改该班级测评状态'), { status: 403, code: 'NO_PERMISSION' });
      if (teacherOnly(user) && !await userHasCapability(user, 'UPDATE_TEST_STATUS', row.school_id, row.class_id)) throw Object.assign(new Error('当前账号无更新测评状态权限'), { status: 403, code: 'CAPABILITY_DENIED' });
      if (!taskStatusAllowed(row.status, item.status)) throw Object.assign(new Error(`不能从${row.status}变更为${item.status}`), { status: 409, code: 'TASK_STATUS_INVALID' });
      if (item.status === '已完成') await requireTaskCompletion(client, item.taskId, item.studentId, row.items);
      const expectedVersion = item.expectedVersion == null ? null : Number(item.expectedVersion);
      const updated = await client.query(`UPDATE task_students SET status=$1,note=$2,version=version+1,
        check_in_at=CASE WHEN $1='已签到' THEN COALESCE(check_in_at,now()) ELSE check_in_at END,
        completed_at=CASE WHEN $1='已完成' THEN COALESCE(completed_at,now()) ELSE completed_at END
        WHERE task_id=$3 AND student_id=$4 AND ($5::int IS NULL OR version=$5) RETURNING *`, [item.status, item.note || null, item.taskId, item.studentId, expectedVersion]);
      if (!updated.rowCount) throw Object.assign(new Error('记录已被其他人更新，请刷新后重试'), { status: 409, code: 'VERSION_CONFLICT' });
      await client.query(`INSERT INTO task_student_status_events(task_id,student_id,from_status,to_status,note,reason_code,operator_teacher_id,expected_version,resulting_version,client_operation_id)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, [item.taskId, item.studentId, row.status, item.status, item.note || null, item.reasonCode || null, user.id, expectedVersion, updated.rows[0].version, item.clientOperationId || null]);
      saved.push({ ...updated.rows[0], schoolId: row.school_id });
    }
    await client.query('COMMIT');
    for (const item of saved) await audit(user, req, 'task.status.batch_update', 'task_student', item.id, null, item, item.schoolId);
    return createdIdempotently(res, user, idempotency, { updated: saved.length, items: saved });
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'tasks' && parts[3] === 'students' && parts[5] === 'status-history') {
  const taskStudent = await taskStudentForUser(user, parts[2], parts[4]);
  if (!taskStudent) return fail(res, 404, 'TASK_STUDENT_NOT_FOUND', '任务学生不存在或无权访问');
  if (teacherOnly(user) && !await userHasCapability(user, 'VIEW_TEST_TASKS', taskStudent.school_id, taskStudent.class_id)) return fail(res, 403, 'CAPABILITY_DENIED', '当前账号无查看测评任务权限');
  const history = await query(`SELECT id,task_id AS "taskId",student_id AS "studentId",from_status AS "fromStatus",to_status AS "toStatus",note,
      reason_code AS "reasonCode",operator_teacher_id AS "operatorTeacherId",expected_version AS "expectedVersion",resulting_version AS "resultingVersion",
      client_operation_id AS "clientOperationId",created_at AS "createdAt"
    FROM task_student_status_events WHERE task_id=$1 AND student_id=$2 ORDER BY created_at DESC,id DESC LIMIT 100`, [parts[2], parts[4]]);
  return ok(res, history.rows);
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'tasks' && parts[3] === 'students' && parts[5] === 'scores') {
  const taskStudent = await taskStudentForUser(user, parts[2], parts[4]);
  if (!taskStudent) return fail(res, 404, 'TASK_STUDENT_NOT_FOUND', '任务学生不存在或无权访问');
  const result = await query(`SELECT id,item_code AS item,score,note,confidence,review_status AS "reviewStatus",manual_reviewed AS "humanReviewed",source,created_at AS "createdAt",updated_at AS "updatedAt"
    FROM assessment_scores WHERE task_id=$1 AND student_id=$2 ORDER BY item_code`, [parts[2], parts[4]]);
  return ok(res, normalizeScoreRows(result.rows));
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'tasks' && parts[3] === 'students' && parts[5] === 'scores') {
  if (!hasRole(user, 'teacher', 'principal', 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有学校工作人员可以录入成绩');
  const taskStudent = await taskStudentForUser(user, parts[2], parts[4]);
  if (!taskStudent) return fail(res, 404, 'TASK_STUDENT_NOT_FOUND', '任务学生不存在或无权访问');
  const input = await body(req);
  if (!Array.isArray(input.scores) || input.scores.length === 0) return fail(res, 400, 'SCORES_REQUIRED', '至少需要提交一项成绩');
  if (input.scores.length > MOVEMENT_SCORE_RULES.itemCount) return fail(res, 400, 'SCORES_TOO_MANY', `最多提交${MOVEMENT_SCORE_RULES.itemCount}项成绩`);
  const itemCodes = new Set();
  const taskItems = Array.isArray(taskStudent.items) ? taskStudent.items : [];
  for (const item of input.scores) {
    if (!MOVEMENT_ITEM_CODES.includes(String(item?.item || '').trim())) throw Object.assign(new Error('体测项目不合法'), { status: 400, code: 'SCORE_ITEM_INVALID' });
    const itemCode = String(item.item).trim();
    if (!taskItems.includes(itemCode)) throw Object.assign(new Error(`“${itemCode}”不在当前任务项目范围内`), { status: 409, code: 'SCORE_ITEM_OUTSIDE_TASK' });
    if (itemCodes.has(itemCode)) throw Object.assign(new Error('同一请求不能重复提交体测项目'), { status: 400, code: 'SCORE_ITEM_DUPLICATE' });
    itemCodes.add(itemCode);
  }
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
  if (idempotency === false) return;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const saved = [];
    for (const item of input.scores) {
      const score = normalizeScore(item.score);
      const confidence = normalizeConfidence(item.confidence == null ? 0 : item.confidence);
      if (score == null || confidence == null) {
        throw Object.assign(new Error('成绩或置信度不合法'), { status: 400, code: 'SCORE_INVALID' });
      }
      const reviewStatus = normalizeReviewStatus(item.reviewStatus, confidence);
      const result = await client.query(`INSERT INTO assessment_scores(task_id,student_id,item_code,score,confidence,note,source,review_status,manual_reviewed,created_by)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,FALSE,$9)
        ON CONFLICT(task_id,student_id,item_code) DO UPDATE SET score=EXCLUDED.score,confidence=EXCLUDED.confidence,note=EXCLUDED.note,source=EXCLUDED.source,review_status=EXCLUDED.review_status,manual_reviewed=FALSE,updated_at=now()
        RETURNING id,item_code AS item,score,note,confidence,review_status AS "reviewStatus"`, [parts[2], parts[4], item.item, score, confidence, item.note || '', item.source || 'teacher', reviewStatus, user.id]);
      saved.push({ ...result.rows[0], score: Number(result.rows[0].score), confidence: Number(result.rows[0].confidence) });
    }
    if (input.markCompleted === true) {
      if (!taskStatusAllowed(taskStudent.status, '已完成')) throw Object.assign(new Error(`不能从${taskStudent.status}直接确认已完成`), { status: 409, code: 'TASK_STATUS_INVALID' });
      await requireTaskCompletion(client, parts[2], parts[4], taskItems);
      await client.query(`UPDATE task_students SET status='已完成',completed_at=COALESCE(completed_at,now()),version=version+1 WHERE task_id=$1 AND student_id=$2`, [parts[2], parts[4]]);
    }
    await client.query('COMMIT');
    await audit(user, req, 'scores.upsert', 'task_student', `${parts[2]}:${parts[4]}`, null, saved, taskStudent.school_id);
    // Preserve the established array response used by the mobile clients. The
    // roster endpoint exposes completion readiness after this write.
    return createdIdempotently(res, user, idempotency, saved);
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'scores' && parts[3] === 'review') {
  if (!hasRole(user, 'teacher', 'principal', 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有学校工作人员可以复核成绩');
  const scoreResult = await query(`SELECT s.*,t.school_id,st.class_id FROM assessment_scores s JOIN assessment_tasks t ON t.id=s.task_id JOIN students st ON st.id=s.student_id WHERE s.id=$1`, [parts[2]]);
  const scoreRow = scoreResult.rows[0];
  if (!scoreRow || !schoolAllowed(user, scoreRow.school_id)) return fail(res, 404, 'SCORE_NOT_FOUND', '成绩不存在或无权访问');
  if (hasRole(user, 'teacher') && !hasRole(user, 'principal', 'admin') && !teacherClassIds(user, scoreRow.school_id).includes(scoreRow.class_id)) return fail(res, 403, 'NO_PERMISSION', '无权复核该班级成绩');
  const input = await body(req);
  const newScore = input.score == null ? normalizeScore(scoreRow.score) : normalizeScore(input.score);
  if (newScore == null) return fail(res, 400, 'SCORE_INVALID', '成绩必须在 0 到 5 之间');
  if (input.action != null && !['approve', 'reject'].includes(String(input.action))) return fail(res, 400, 'REVIEW_ACTION_INVALID', '复核动作不合法');
  const reviewStatus = input.action === 'reject' ? 'pendingReview' : 'passed';
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ scoreId: parts[2], ...input }));
  if (idempotency === false) return;
  const humanReviewed = input.action !== 'reject';
  const updated = await query(`UPDATE assessment_scores SET score=$1,review_status=$2,manual_reviewed=$3,note=$4,updated_at=now() WHERE id=$5 RETURNING id,item_code AS item,score,note,confidence,review_status AS "reviewStatus",manual_reviewed AS "humanReviewed"`, [newScore, reviewStatus, humanReviewed, input.reason || scoreRow.note || '', parts[2]]);
  await query(`INSERT INTO score_reviews(score_id,reviewer_id,action,old_score,new_score,reason) VALUES($1,$2,$3,$4,$5,$6)`, [parts[2], user.id, input.action || 'approve', scoreRow.score, newScore, input.reason || '']);
  await audit(user, req, 'score.review', 'assessment_score', parts[2], scoreRow, updated.rows[0], scoreRow.school_id);
  return okIdempotently(res, user, idempotency, { ...updated.rows[0], score: Number(updated.rows[0].score), confidence: Number(updated.rows[0].confidence) });
}
  return false;
}
