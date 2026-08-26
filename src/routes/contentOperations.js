const contentTables = {
  course: { table: 'courses', label: '课程', order: 'created_at' },
  activity: { table: 'activities', label: '活动', order: 'updated_at' },
  expert: { table: 'experts', label: '专家', order: 'updated_at' },
  notification_template: { table: 'notification_templates', label: '通知模板', order: 'updated_at' }
};

const allowedChannels = new Set(['mobile', 'teacher', 'family']);
const allowedContentTypes = new Set([...Object.keys(contentTables), 'scoring_rule']);

/** Versioned content catalogue and publication workflow. */
export async function handleContentOperationRoutes(context) {
  const {
    req, res, user, url, parts, query, pool, hasRole, schoolAllowed,
    body, fail, requiredString, beginIdempotentRequest, requestBodyHash,
    failIdempotently, audit, createdIdempotently, okIdempotently, ok
  } = context;

  if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'mobile' && parts[2] === 'content-manifest') {
    const schoolId = url.searchParams.get('schoolId') || user.roles.map((role) => role.school_id).find(Boolean) || null;
    const channel = url.searchParams.get('channel') || (hasRole(user, 'teacher') ? 'teacher' : 'family');
    if (!allowedChannels.has(channel)) return fail(res, 400, 'CONTENT_CHANNEL_INVALID', '内容渠道不合法');
    if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权访问该学校内容');
    const knownVersion = Math.max(0, Number.parseInt(url.searchParams.get('knownVersion') || '0', 10) || 0);
    const release = await query(`SELECT id AS "releaseId",school_id AS "schoolId",channel,version,effective_at AS "effectiveAt",published_at AS "publishedAt"
      FROM content_releases WHERE status='published' AND channel=$1 AND (school_id IS NULL OR school_id=$2)
      AND (effective_at IS NULL OR effective_at<=now()) ORDER BY (school_id IS NOT NULL) DESC,version DESC LIMIT 1`, [channel, schoolId]);
    if (!release.rowCount) return ok(res, { dataAvailable: false, changed: false, version: 0, items: [] });
    const selected = release.rows[0];
    if (selected.version <= knownVersion) return ok(res, { ...selected, dataAvailable: true, changed: false, items: [] });
    const items = await query(`SELECT content_type AS "contentType",content_id AS "contentId",content_version AS "contentVersion",sort_order AS "sortOrder",metadata
      FROM content_release_items WHERE release_id=$1 ORDER BY sort_order,content_type,content_id`, [selected.releaseId]);
    return ok(res, { ...selected, dataAvailable: true, changed: true, items: items.rows });
  }

  if (!(parts[0] === 'v1' && parts[1] === 'admin' && parts[2] === 'content')) return false;
  if (!hasRole(user, 'admin', 'principal')) return fail(res, 403, 'NO_PERMISSION', '只有内容管理员可以管理发布内容');

  if (req.method === 'GET' && parts[3] === 'catalog') {
    const type = url.searchParams.get('type') || 'course';
    const config = contentTables[type];
    if (!config) return fail(res, 400, 'CONTENT_TYPE_INVALID', '内容类型不合法');
    const schoolId = url.searchParams.get('schoolId') || user.roles.map((role) => role.school_id).find(Boolean) || null;
    if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校内容');
    const result = await query(`SELECT * FROM ${config.table} WHERE (school_id IS NULL OR school_id=$1) ORDER BY ${config.order} DESC LIMIT 200`, [schoolId]);
    return ok(res, result.rows);
  }

  if (req.method === 'GET' && parts[3] === 'releases' && !parts[4]) {
    const schoolId = url.searchParams.get('schoolId') || user.roles.map((role) => role.school_id).find(Boolean) || null;
    if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权查看该学校内容版本');
    const releases = await query(`SELECT r.id AS "releaseId",r.school_id AS "schoolId",r.channel,r.version,r.status,r.notes,r.effective_at AS "effectiveAt",r.published_at AS "publishedAt",r.withdrawn_at AS "withdrawnAt",COUNT(i.content_id)::int AS "itemCount"
      FROM content_releases r LEFT JOIN content_release_items i ON i.release_id=r.id
      WHERE r.school_id IS NOT DISTINCT FROM $1 GROUP BY r.id ORDER BY r.version DESC LIMIT 100`, [schoolId]);
    return ok(res, releases.rows);
  }

  if (req.method === 'GET' && parts[3] === 'releases' && parts[4] && !parts[5]) {
    const release = await query(`SELECT id AS "releaseId",school_id AS "schoolId",channel,version,status,notes,
      effective_at AS "effectiveAt",published_at AS "publishedAt",withdrawn_at AS "withdrawnAt",created_at AS "createdAt",updated_at AS "updatedAt"
      FROM content_releases WHERE id=$1`, [parts[4]]);
    const row = release.rows[0];
    if (!row || (row.schoolId && !schoolAllowed(user, row.schoolId))) return fail(res, 404, 'CONTENT_RELEASE_NOT_FOUND', '内容版本不存在');
    const items = await query(`SELECT content_type AS "contentType",content_id AS "contentId",content_version AS "contentVersion",
      sort_order AS "sortOrder",metadata FROM content_release_items WHERE release_id=$1 ORDER BY sort_order,content_type,content_id`, [parts[4]]);
    return ok(res, { ...row, items: items.rows });
  }

  if (req.method === 'POST' && parts[3] === 'releases' && !parts[4]) {
    const input = await body(req);
    const schoolId = input.schoolId || user.roles.map((role) => role.school_id).find(Boolean) || null;
    if (schoolId && !schoolAllowed(user, schoolId)) return fail(res, 403, 'NO_PERMISSION', '无权创建该学校内容版本');
    const channel = String(input.channel || 'mobile');
    if (!allowedChannels.has(channel)) return fail(res, 400, 'CONTENT_CHANNEL_INVALID', '内容渠道不合法');
    const notes = String(input.notes || '').trim().slice(0, 2000);
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ schoolId, channel, notes, effectiveAt: input.effectiveAt || null }));
    if (idempotency === false) return;
    const result = await query(`INSERT INTO content_releases(school_id,channel,version,notes,effective_at,created_by)
      SELECT $1,$2,COALESCE(MAX(version),0)+1,$3,$4,$5 FROM content_releases WHERE school_id IS NOT DISTINCT FROM $1 AND channel=$2
      RETURNING id AS "releaseId",school_id AS "schoolId",channel,version,status,notes,effective_at AS "effectiveAt"`, [schoolId, channel, notes, input.effectiveAt || null, user.id]);
    await audit(user, req, 'content.release.create', 'content_release', result.rows[0].releaseId, null, result.rows[0], schoolId);
    return createdIdempotently(res, user, idempotency, result.rows[0]);
  }

  if (req.method === 'PUT' && parts[3] === 'releases' && parts[4] && parts[5] === 'items') {
    const input = await body(req);
    if (!Array.isArray(input.items)) return fail(res, 400, 'CONTENT_ITEMS_INVALID', '内容列表不能为空');
    const release = await query('SELECT * FROM content_releases WHERE id=$1', [parts[4]]);
    const row = release.rows[0];
    if (!row || (row.school_id && !schoolAllowed(user, row.school_id))) return fail(res, 404, 'CONTENT_RELEASE_NOT_FOUND', '内容版本不存在');
    if (row.status !== 'draft') return fail(res, 409, 'CONTENT_RELEASE_LOCKED', '已发布版本不可编辑');
    const normalized = input.items.map((item, index) => ({
      contentType: requiredString(item.contentType, '内容类型', { max: 40 }),
      contentId: requiredString(item.contentId, '内容编号', { max: 160 }),
      contentVersion: Math.max(1, Number(item.contentVersion) || 1),
      sortOrder: Number.isInteger(item.sortOrder) ? item.sortOrder : index,
      metadata: item.metadata && typeof item.metadata === 'object' ? item.metadata : {}
    }));
    if (normalized.some((item) => !allowedContentTypes.has(item.contentType))) return fail(res, 400, 'CONTENT_TYPE_INVALID', '内容类型不合法');
    const seen = new Set();
    if (normalized.some((item) => { const key = `${item.contentType}:${item.contentId}`; if (seen.has(key)) return true; seen.add(key); return false; })) return fail(res, 400, 'CONTENT_ITEM_DUPLICATED', '内容列表存在重复项目');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('DELETE FROM content_release_items WHERE release_id=$1', [parts[4]]);
      for (const item of normalized) await client.query(`INSERT INTO content_release_items(release_id,content_type,content_id,content_version,sort_order,metadata) VALUES($1,$2,$3,$4,$5,$6)`, [parts[4], item.contentType, item.contentId, item.contentVersion, item.sortOrder, item.metadata]);
      await client.query('UPDATE content_releases SET updated_at=now() WHERE id=$1', [parts[4]]);
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK').catch(() => {}); throw error; } finally { client.release(); }
    await audit(user, req, 'content.release.items.replace', 'content_release', parts[4], null, { itemCount: normalized.length }, row.school_id);
    return ok(res, { releaseId: parts[4], itemCount: normalized.length });
  }

  if (req.method === 'POST' && parts[3] === 'releases' && parts[4] && ['publish', 'withdraw'].includes(parts[5])) {
    const action = parts[5];
    const release = await query('SELECT * FROM content_releases WHERE id=$1', [parts[4]]);
    const row = release.rows[0];
    if (!row || (row.school_id && !schoolAllowed(user, row.school_id))) return fail(res, 404, 'CONTENT_RELEASE_NOT_FOUND', '内容版本不存在');
    if (action === 'publish' && row.status !== 'draft') return fail(res, 409, 'CONTENT_RELEASE_LOCKED', '只有草稿版本可以发布');
    if (action === 'withdraw' && row.status !== 'published') return fail(res, 409, 'CONTENT_RELEASE_LOCKED', '只有已发布版本可以撤回');
    const itemCount = await query('SELECT COUNT(*)::int AS count FROM content_release_items WHERE release_id=$1', [parts[4]]);
    if (action === 'publish' && itemCount.rows[0].count < 1) return fail(res, 409, 'CONTENT_RELEASE_EMPTY', '内容版本为空，不能发布');
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash({ releaseId: parts[4], action }));
    if (idempotency === false) return;
    const updated = action === 'publish'
      ? await query(`UPDATE content_releases SET status='published',published_by=$1,published_at=now(),withdrawn_at=NULL,updated_at=now() WHERE id=$2 RETURNING id AS "releaseId",status,version,published_at AS "publishedAt"`, [user.id, parts[4]])
      : await query(`UPDATE content_releases SET status='withdrawn',withdrawn_at=now(),updated_at=now() WHERE id=$1 RETURNING id AS "releaseId",status,version,withdrawn_at AS "withdrawnAt"`, [parts[4]]);
    await audit(user, req, `content.release.${action}`, 'content_release', parts[4], row, updated.rows[0], row.school_id);
    return okIdempotently(res, user, idempotency, updated.rows[0]);
  }

  return false;
}
