/** Family support inquiries are separate from inbox messages and notices. */
export async function handleSupportRoutes(context) {
  const { req, res, user, parts, query, body, requiredString, schoolAllowed, fail, beginIdempotentRequest, requestBodyHash, createdIdempotently, audit } = context;
  if (!(req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'support' && parts[2] === 'messages')) return;
  const input = await body(req);
  const content = requiredString(input.content, '咨询内容', { max: 2000 });
  const schoolId = input.schoolId || user.roles.find((role) => role.school_id)?.school_id || null;
  if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权向该学校提交咨询');
  const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ ...input, content }));
  if (idempotency === false) return;
  const result = await query('INSERT INTO support_messages(user_id,school_id,content) VALUES($1,$2,$3) RETURNING id,status,created_at', [user.id, schoolId, content]);
  await audit(user, req, 'support.message.create', 'support_message', result.rows[0].id, null, result.rows[0], schoolId);
  return createdIdempotently(res, user, idempotency, result.rows[0]);
}
