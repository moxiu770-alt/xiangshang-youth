/** Message inbox and read receipts. Business-route authorization remains in
 * the target resource handlers; this boundary prevents one user from listing
 * or marking another user's inbox records. */
export async function handleMessageRoutes(context) {
  const { req, res, user, parts, hasRole, query, fail, ok } = context;
  if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'users' && parts[3] === 'messages') {
    if (parts[2] !== user.id && !hasRole(user, 'admin')) return fail(res, 403, 'NO_PERMISSION', '无权查看该用户消息');
    const result = await query(`SELECT id,title,content,to_char(created_at,'YYYY-MM-DD HH24:MI') AS time,is_read AS "isRead",category,
      message_type AS "messageType",business_id AS "businessId",business_route AS "businessRoute",child_id AS "childId",task_id AS "taskId",course_id AS "courseId",lesson_id AS "lessonId",action_label AS "actionLabel",read_at AS "readAt",expires_at AS "expiresAt"
      FROM messages WHERE receiver_user_id=$1 ORDER BY created_at DESC LIMIT 100`, [parts[2]]);
    return ok(res, result.rows);
  }
  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'messages' && parts[3] === 'read') {
    const result = await query('UPDATE messages SET is_read=true,read_at=COALESCE(read_at,now()) WHERE id=$1 AND receiver_user_id=$2 RETURNING id,read_at AS "readAt"', [parts[2], user.id]);
    if (!result.rowCount) return fail(res, 404, 'MESSAGE_NOT_FOUND', '消息不存在');
    return ok(res, null);
  }
}
