/**
 * Child-safe class-circle routes: cursor pagination, attachment ownership,
 * moderation, reporting, comments and teacher pinning.
 */
export async function handleClassPostRoutes(context) {
  const {
    req, res, user, url, parts,
    query, hasRole, parentOnly, teacherOnly, teacherClassIds, schoolAllowed,
    userHasCapability, classPostVisibleToUser, body, requiredString,
    fail, beginIdempotentRequest, requestBodyHash, failIdempotently,
    audit, createdIdempotently, okIdempotently, created, ok
  } = context;

if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'class-posts' && !parts[2]) {
  const schoolId = url.searchParams.get('schoolId') || user.roles.find((role) => role.school_id)?.school_id || null;
  const classId = url.searchParams.get('classId') || null;
  const pageSize = Math.min(Number(url.searchParams.get('pageSize') || 20), 50);
  const cursor = url.searchParams.get('cursor');
  if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校班级圈');
  if (classId && hasRole(user, 'teacher') && !teacherClassIds(user, schoolId).includes(classId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该班级动态');
  // Ownership is a server projection, never inferred by the client from a
  // display name.  It controls whether the UI offers delete/edit or report.
  const params = [schoolId, classId, cursor, pageSize, user.id];
  let scopeSql = '';
  if (parentOnly(user)) {
    params.push(user.id);
    scopeSql = ` AND p.class_id IS NOT NULL
      AND p.visibility_scope='class'
      AND EXISTS (SELECT 1 FROM parent_student_bindings pb JOIN students st ON st.id=pb.student_id
                  WHERE pb.parent_user_id=$6 AND pb.status='active' AND st.class_id=p.class_id AND st.status='active')
      AND (p.moderation_status IN ('approved','published') OR p.user_id=$6)`;
  } else if (teacherOnly(user)) {
    params.push(teacherClassIds(user, schoolId));
    scopeSql = ` AND (p.class_id=ANY($6::text[]) OR p.class_id IS NULL)`;
  }
  const result = await query(`SELECT p.id AS "postId",p.school_id AS "schoolId",p.class_id AS "classId",p.display_name AS "displayName",p.content,p.status,p.visibility_scope AS "visibilityScope",p.moderation_status AS "moderationStatus",p.pinned,p.report_status AS "reportStatus",p.attachments,p.created_at AS "createdAt",(p.user_id=$5) AS "ownedByCurrentUser",
      COALESCE((SELECT r.code FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=p.user_id ORDER BY CASE WHEN r.code='teacher' THEN 0 WHEN r.code='parent' THEN 1 ELSE 2 END LIMIT 1),'parent') AS "authorRole",
      COALESCE(c.count,0)::int AS "commentCount"
    FROM class_posts p
    LEFT JOIN LATERAL (SELECT COUNT(*) FROM class_post_comments WHERE post_id=p.id AND deleted_at IS NULL) c ON true
    WHERE p.deleted_at IS NULL AND ($1::text IS NULL OR p.school_id=$1) AND ($2::text IS NULL OR p.class_id=$2) AND ($3::timestamptz IS NULL OR p.created_at<$3)
      ${scopeSql}
    ORDER BY p.pinned DESC,p.created_at DESC LIMIT $4`, params);
  return ok(res, { items: result.rows, nextCursor: result.rows.length === pageSize ? result.rows[result.rows.length - 1].createdAt : null });
}
if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'class-posts' && parts[2] && parts[3] === 'comments' && !parts[4]) {
  const post = await query('SELECT * FROM class_posts WHERE id=$1 AND deleted_at IS NULL', [parts[2]]);
  if (!post.rowCount || !await classPostVisibleToUser(user, post.rows[0])) return fail(res, 404, 'POST_NOT_FOUND', '动态不存在或无权访问');
  const pageSize = Math.min(Number(url.searchParams.get('pageSize') || 20), 50);
  const cursor = url.searchParams.get('cursor');
  const comments = await query(`SELECT id AS "commentId",post_id AS "postId",display_name AS "displayName",content,status,created_at AS "createdAt",
      (user_id=$2) AS "ownedByCurrentUser"
    FROM class_post_comments
    WHERE post_id=$1 AND deleted_at IS NULL AND ($3::timestamptz IS NULL OR created_at<$3)
    ORDER BY created_at DESC LIMIT $4`, [parts[2], user.id, cursor, pageSize]);
  return ok(res, { items: comments.rows, nextCursor: comments.rows.length === pageSize ? comments.rows[comments.rows.length - 1].createdAt : null });
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'class-posts') {
  const input = await body(req);
  const content = requiredString(input.content, '动态内容', { max: 2000 });
  const schoolId = input.schoolId || user.roles.find((role) => role.school_id)?.school_id || null;
  if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权向该学校发布动态');
  const classId = input.classId ? requiredString(input.classId, '班级', { max: 120 }) : null;
  if (parentOnly(user) && !classId) return fail(res, 400, 'CLASS_REQUIRED', '家长发布班级动态需要指定已绑定孩子所在班级');
  if (parentOnly(user) && classId) {
    const binding = await query(`SELECT 1
      FROM parent_student_bindings pb JOIN students st ON st.id=pb.student_id
      WHERE pb.parent_user_id=$1 AND pb.status='active' AND st.status='active'
        AND st.class_id=$2 AND ($3::text IS NULL OR st.school_id=$3)
      LIMIT 1`, [user.id, classId, schoolId]);
    if (!binding.rowCount) return fail(res, 403, 'NO_PERMISSION', '只能向已绑定孩子所在班级发布动态');
  }
  if (classId && hasRole(user, 'teacher') && !teacherClassIds(user, schoolId).includes(classId)) return fail(res, 403, 'NO_PERMISSION', '无权向该班级发布动态');
  const attachments = Array.isArray(input.attachments) ? input.attachments.slice(0, 9).map((item) => ({
    id: requiredString(item.id || item.objectId || 'attachment', '附件', { max: 120 }),
    type: requiredString(item.type || 'image', '附件类型', { max: 30 }),
    objectId: requiredString(item.objectId, '附件文件', { max: 120 }),
    thumbnailObjectId: item.thumbnailObjectId || null
  })) : [];
  if (JSON.stringify(attachments).length > 5000) return fail(res, 400, 'INVALID_ARGUMENT', '附件信息过长');
  const fileIds = [...new Set(attachments.flatMap((item) => [item.objectId, item.thumbnailObjectId].filter(Boolean)))];
  if (fileIds.length) {
    const files = await query(`SELECT id,status,owner_id,purpose FROM files WHERE id=ANY($1::text[])`, [fileIds]);
    const byId = new Map(files.rows.map((file) => [file.id, file]));
    for (const fileId of fileIds) {
      const file = byId.get(fileId);
      if (!file || file.status !== 'uploaded' || file.owner_id !== user.id || file.purpose !== 'class_post_attachment') {
        return fail(res, 400, 'FILE_NOT_READY', '班级圈附件尚未上传完成或用途不匹配');
      }
    }
  }
  const displayName = input.displayName ? requiredString(input.displayName, '展示名', { max: 80 }) : `${String(user.name || '本班').slice(0, 1)}同学家长`;
  const visibilityScope = ['class', 'school_staff', 'teacher_only'].includes(input.visibilityScope) ? input.visibilityScope : 'class';
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ ...input, content }));
  if (idempotency === false) return;
  const result = await query(`INSERT INTO class_posts(user_id,school_id,class_id,author,display_name,content,visibility_scope,moderation_status,attachments) VALUES($1,$2,$3,$4,$5,$6,$7,'pending_review',$8::jsonb) RETURNING id AS "postId",status,moderation_status AS "moderationStatus",created_at AS "createdAt"`, [user.id, schoolId, classId, requiredString(input.author || user.name, '发布人', { max: 80 }), displayName, content, visibilityScope, JSON.stringify(attachments)]);
  await audit(user, req, 'class_post.create', 'class_post', result.rows[0].postId, null, result.rows[0], schoolId);
  return createdIdempotently(res, user, idempotency, result.rows[0]);
}
if (req.method === 'DELETE' && parts[0] === 'v1' && parts[1] === 'class-posts' && parts[2]) {
  const current = await query('SELECT * FROM class_posts WHERE id=$1 AND deleted_at IS NULL', [parts[2]]);
  const row = current.rows[0];
  if (!row) return fail(res, 404, 'POST_NOT_FOUND', '动态不存在');
  if (row.user_id !== user.id && !hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '只能删除本人发布的内容');
  const updated = await query('UPDATE class_posts SET deleted_at=now(),updated_at=now() WHERE id=$1 RETURNING id AS "postId"', [parts[2]]);
  await audit(user, req, 'class_post.delete', 'class_post', parts[2], row, updated.rows[0], row.school_id);
  return ok(res, updated.rows[0]);
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'class-posts' && parts[3] === 'comments') {
  const input = await body(req);
  const content = requiredString(input.content, '评论内容', { max: 500 });
  const post = await query('SELECT * FROM class_posts WHERE id=$1 AND deleted_at IS NULL', [parts[2]]);
  if (!post.rowCount || !await classPostVisibleToUser(user, post.rows[0])) return fail(res, 404, 'POST_NOT_FOUND', '动态不存在或无权访问');
  const displayName = input.displayName ? requiredString(input.displayName, '展示名', { max: 80 }) : `${String(user.name || '本班').slice(0, 1)}同学家长`;
  const result = await query(`INSERT INTO class_post_comments(post_id,user_id,display_name,content) VALUES($1,$2,$3,$4) RETURNING id AS "commentId",post_id AS "postId",display_name AS "displayName",content,created_at AS "createdAt",true AS "ownedByCurrentUser"`, [parts[2], user.id, displayName, content]);
  await audit(user, req, 'class_post.comment.create', 'class_post_comment', result.rows[0].commentId, null, result.rows[0], post.rows[0].school_id);
  return created(res, result.rows[0]);
}
if (req.method === 'DELETE' && parts[0] === 'v1' && parts[1] === 'class-posts' && parts[3] === 'comments' && parts[4]) {
  // Keep the complete post authorization projection here.  Passing only
  // school_id/class_id made classPostVisibleToUser treat a parent's own
  // pending post as an incomplete row and could incorrectly hide/delete
  // comments depending on visibility and moderation state.
  const comment = await query(`SELECT c.*,p.id AS post_id,p.school_id,p.class_id,p.user_id AS post_user_id,
      p.visibility_scope,p.moderation_status,p.deleted_at AS post_deleted_at
    FROM class_post_comments c JOIN class_posts p ON p.id=c.post_id
    WHERE c.id=$1 AND c.post_id=$2 AND c.deleted_at IS NULL AND p.deleted_at IS NULL`, [parts[4], parts[2]]);
  const row = comment.rows[0];
  const post = row ? {
    id: row.post_id,
    school_id: row.school_id,
    class_id: row.class_id,
    user_id: row.post_user_id,
    visibility_scope: row.visibility_scope,
    moderation_status: row.moderation_status,
    deleted_at: row.post_deleted_at
  } : null;
  if (!row || !await classPostVisibleToUser(user, post)) return fail(res, 404, 'COMMENT_NOT_FOUND', '评论不存在或无权访问');
  if (row.user_id !== user.id && !hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只能删除本人评论');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ postId: parts[2], commentId: parts[4], action: 'delete' }));
  if (idempotency === false) return;
  const updated = await query(`UPDATE class_post_comments SET deleted_at=now(),status='deleted' WHERE id=$1 RETURNING id AS "commentId",post_id AS "postId",status`, [parts[4]]);
  await audit(user, req, 'class_post.comment.delete', 'class_post_comment', parts[4], row, updated.rows[0], row.school_id);
  return okIdempotently(res, user, idempotency, updated.rows[0]);
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'class-posts' && parts[3] === 'report') {
  const input = await body(req);
  const reason = requiredString(input.reason, '举报原因', { max: 300 });
  const post = await query('SELECT * FROM class_posts WHERE id=$1 AND deleted_at IS NULL', [parts[2]]);
  if (!post.rowCount || !await classPostVisibleToUser(user, post.rows[0])) return fail(res, 404, 'POST_NOT_FOUND', '动态不存在或无权访问');
  const result = await query(`INSERT INTO class_post_reports(post_id,user_id,reason) VALUES($1,$2,$3) ON CONFLICT(post_id,user_id) DO UPDATE SET reason=EXCLUDED.reason,status='pending',created_at=now() RETURNING id,status`, [parts[2], user.id, reason]);
  await query(`UPDATE class_posts SET report_status='reported',updated_at=now() WHERE id=$1`, [parts[2]]);
  await audit(user, req, 'class_post.report', 'class_post', parts[2], null, { reason }, post.rows[0].school_id);
  return ok(res, result.rows[0]);
}
if (req.method === 'PATCH' && parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'class-posts' && parts[3] && parts[4] === 'moderation') {
  if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有学校管理员可以审核班级动态');
  const input = await body(req);
  if (!['approved', 'rejected'].includes(input.status)) return fail(res, 400, 'MODERATION_STATUS_INVALID', '审核状态不合法');
  const current = await query('SELECT * FROM class_posts WHERE id=$1 AND deleted_at IS NULL', [parts[3]]);
  const row = current.rows[0];
  if (!row || !schoolAllowed(user, row.school_id)) return fail(res, 404, 'POST_NOT_FOUND', '动态不存在或无权访问');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ postId: parts[3], status: input.status, reason: input.reason || '' }));
  if (idempotency === false) return;
  const updated = await query(`UPDATE class_posts SET moderation_status=$1,status=CASE WHEN $1='rejected' THEN 'rejected' ELSE 'published' END,updated_at=now()
    WHERE id=$2 RETURNING id AS "postId",status,moderation_status AS "moderationStatus",updated_at AS "updatedAt"`, [input.status, parts[3]]);
  await audit(user, req, 'class_post.moderation', 'class_post', parts[3], row, { ...updated.rows[0], reason: input.reason || null }, row.school_id);
  return okIdempotently(res, user, idempotency, updated.rows[0]);
}
if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'class-posts' && parts[3] === 'pin') {
  const input = await body(req);
  const pinned = input.pinned !== false;
  const post = await query('SELECT * FROM class_posts WHERE id=$1 AND deleted_at IS NULL', [parts[2]]);
  const row = post.rows[0];
  if (!row) return fail(res, 404, 'POST_NOT_FOUND', '动态不存在');
  if (!await userHasCapability(user, 'PUBLISH_CLASS_NOTICE', row.school_id, row.class_id)) return fail(res, 403, 'NO_PERMISSION', '无权置顶班级动态');
  if (row.class_id && hasRole(user, 'teacher') && !teacherClassIds(user, row.school_id).includes(row.class_id)) return fail(res, 403, 'NO_PERMISSION', '无权管理该班级动态');
  const updated = await query(`UPDATE class_posts SET pinned=$1,updated_at=now() WHERE id=$2 RETURNING id AS "postId",pinned`, [pinned, parts[2]]);
  await audit(user, req, pinned ? 'class_post.pin' : 'class_post.unpin', 'class_post', parts[2], row, updated.rows[0], row.school_id);
  return ok(res, updated.rows[0]);
}

  return false;
}
