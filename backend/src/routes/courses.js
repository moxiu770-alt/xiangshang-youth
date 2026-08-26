/** Course catalogue, playback and progress routes. */
export async function handleCourseRoutes(context) {
  const { req, res, user, parts, query, hasRole, schoolAllowed, guardianStudentForUser, body, fail, requiredString, beginIdempotentRequest, requestBodyHash, failIdempotently, createdIdempotently, okIdempotently, ok } = context;
  if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'courses') {
    const student = await guardianStudentForUser(user, parts[2]);
    if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
    const result = await query(`SELECT c.id AS "courseId",c.title,c.cover,l.module_id AS "moduleId",l.id AS "lessonId",l.title AS "lessonTitle",l.duration_ms AS "durationMs",l.video_source AS "videoSource",l.captions,COALESCE(p.last_position_ms,0)::int AS "lastPositionMs",COALESCE(p.completed,false) AS completed,COALESCE(p.version,0)::int AS version FROM courses c JOIN course_lessons l ON l.course_id=c.id AND l.status='active' LEFT JOIN lesson_progress p ON p.lesson_id=l.id AND p.student_id=$2 WHERE c.status='active' AND (c.school_id IS NULL OR c.school_id=$1) ORDER BY c.created_at DESC,l.sort_order`, [student.school_id, parts[2]]);
    return ok(res, result.rows);
  }
  if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'courses' && parts.length === 3) {
    const course = await query(`SELECT c.id AS "courseId",c.school_id AS "schoolId",c.title,c.cover,c.status,COALESCE(json_agg(json_build_object('lessonId',l.id,'moduleId',l.module_id,'title',l.title,'durationMs',l.duration_ms,'locked',l.status<>'active') ORDER BY l.sort_order) FILTER(WHERE l.id IS NOT NULL),'[]') AS lessons FROM courses c LEFT JOIN course_lessons l ON l.course_id=c.id WHERE c.id=$1 GROUP BY c.id`, [parts[2]]);
    if (!course.rowCount || course.rows[0].status !== 'active' || (course.rows[0].schoolId && !schoolAllowed(user, course.rows[0].schoolId))) return fail(res, 404, 'COURSE_NOT_FOUND', '课程不存在或无权访问');
    return ok(res, course.rows[0]);
  }
  if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'lessons' && parts[3] === 'playback') {
    const lesson = await query(`SELECT l.id AS "lessonId",l.course_id AS "courseId",c.school_id AS "schoolId",l.video_source AS "videoSource",l.captions,l.duration_ms AS "durationMs" FROM course_lessons l JOIN courses c ON c.id=l.course_id WHERE l.id=$1 AND l.status='active' AND c.status='active'`, [parts[2]]);
    if (!lesson.rowCount || (lesson.rows[0].schoolId && !schoolAllowed(user, lesson.rows[0].schoolId))) return fail(res, 404, 'LESSON_NOT_FOUND', '课节不存在或无权访问');
    if (!lesson.rows[0].videoSource) return fail(res, 404, 'VIDEO_NOT_AVAILABLE', '课程视频暂不可用');
    return ok(res, lesson.rows[0]);
  }
  if (req.method === 'PUT' && parts[0] === 'v1' && parts[1] === 'students' && parts[3] === 'lessons' && parts[5] === 'progress') {
    const student = await guardianStudentForUser(user, parts[2]);
    if (!student) return fail(res, 404, 'STUDENT_NOT_FOUND', '学生不存在或无权访问');
    const input = await body(req); const position = Number(input.lastPositionMs); const expectedVersion = input.expectedVersion == null ? null : Number(input.expectedVersion);
    if (!Number.isInteger(position) || position < 0) return fail(res, 400, 'PROGRESS_INVALID', '播放位置不合法');
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ studentId: parts[2], lessonId: parts[4], ...input })); if (idempotency === false) return;
    const lesson = await query(`SELECT l.id,l.duration_ms AS "durationMs",c.school_id AS "schoolId" FROM course_lessons l JOIN courses c ON c.id=l.course_id WHERE l.id=$1 AND l.status='active' AND c.status='active'`, [parts[4]]);
    if (!lesson.rowCount || (lesson.rows[0].schoolId && lesson.rows[0].schoolId !== student.school_id)) return failIdempotently(req, res, 404, 'LESSON_NOT_FOUND', '课节不存在或无权访问');
    if (position > Number(lesson.rows[0].durationMs || 0)) return failIdempotently(req, res, 400, 'PROGRESS_INVALID', '播放位置不能超过课时长度');
    const existing = await query('SELECT version FROM lesson_progress WHERE student_id=$1 AND lesson_id=$2', [parts[2], parts[4]]);
    if (expectedVersion != null && existing.rowCount && existing.rows[0].version !== expectedVersion) return failIdempotently(req, res, 409, 'VERSION_CONFLICT', '学习进度已在其他设备更新，请刷新后重试');
    const saved = await query(`INSERT INTO lesson_progress(student_id,lesson_id,last_position_ms,completed,version) VALUES($1,$2,$3,$4,1) ON CONFLICT(student_id,lesson_id) DO UPDATE SET last_position_ms=EXCLUDED.last_position_ms,completed=lesson_progress.completed OR EXCLUDED.completed,version=lesson_progress.version+1,updated_at=now() RETURNING student_id AS "studentId",lesson_id AS "lessonId",last_position_ms AS "lastPositionMs",completed,version,updated_at AS "updatedAt"`, [parts[2], parts[4], position, input.completed === true]);
    return okIdempotently(res, user, idempotency, saved.rows[0]);
  }
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'courses' && parts[2] === 'uploads') {
    if (!hasRole(user, 'teacher', 'principal', 'admin')) return fail(res, 403, 'NO_PERMISSION', '只有学校工作人员可以上传课程');
    const input = await body(req);
    if (input.attachmentFileId) {
      const file = await query('SELECT id,status,owner_id FROM files WHERE id=$1', [input.attachmentFileId]);
      if (!file.rows[0] || file.rows[0].status !== 'uploaded' || (file.rows[0].owner_id !== user.id && !hasRole(user, 'admin'))) return fail(res, 400, 'FILE_NOT_READY', '附件尚未上传完成');
    }
    const attendanceCount = Number(input.attendanceCount);
    if (!Number.isInteger(attendanceCount) || attendanceCount < 0 || attendanceCount > 10000) return fail(res, 400, 'INVALID_ARGUMENT', '出勤人数必须是0到10000之间的整数');
    const notes = String(input.notes || '').trim(); const attachmentName = requiredString(input.attachmentName, '附件名称', { max: 180 });
    if (notes.length > 2000) return fail(res, 400, 'INVALID_ARGUMENT', '课堂记录长度不能超过2000个字符');
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input)); if (idempotency === false) return;
    const taskSchool = input.taskId ? await query('SELECT school_id FROM assessment_tasks WHERE id=$1', [input.taskId]) : { rows: [] };
    const schoolId = input.schoolId || taskSchool.rows[0]?.school_id || user.roles.find((role) => role.school_id)?.school_id || null;
    if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权向该学校上传课程');
    const result = await query('INSERT INTO course_uploads(user_id,school_id,task_id,attachment_file_id,attendance_count,notes,attachment_name) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id,status', [user.id, schoolId, input.taskId || null, input.attachmentFileId || null, attendanceCount, notes, attachmentName]);
    return createdIdempotently(res, user, idempotency, result.rows[0]);
  }
}
