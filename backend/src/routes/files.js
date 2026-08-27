import crypto from 'node:crypto';
import path from 'node:path';

/** Owner-scoped upload metadata and object content lifecycle. */
export async function handleFileRoutes(context) {
  const {
    req, res, user, parts, storage, query, body, rawBody, fail, ok,
    beginIdempotentRequest, requestBodyHash, createdIdempotently,
    classPostFileVisibleToUser, hasRole, corsOrigin, allowedContentTypes,
    fileSignatureMatches, maxUploadBytes, safeFileName
  } = context;
  const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');

  if (req.method === 'POST' && parts[0] === 'v1' && parts[1] === 'files' && parts[2] === 'presign') {
    const input = await body(req);
    const name = safeFileName(input.fileName || input.name || 'upload.bin');
    const contentType = String(input.contentType || 'application/octet-stream');
    const fileSize = Number(input.fileSize || 0);
    if (!allowedContentTypes.has(contentType)) return fail(res, 400, 'FILE_TYPE_NOT_ALLOWED', '文件类型不受支持');
    if (!Number.isInteger(fileSize) || fileSize < 0 || fileSize > maxUploadBytes) return fail(res, 400, 'FILE_SIZE_INVALID', '文件大小不合法或超过 20MB');
    const idempotency = await beginIdempotentRequest(req, user, res, requestBodyHash(input));
    if (idempotency === false) return;
    const fileId = crypto.randomUUID();
    const objectKey = `${user.id}/${fileId}-${name}`;
    const expiresAt = new Date(Date.now() + 30 * 60_000);
    const result = await query(`INSERT INTO files(id,owner_id,object_key,file_type,purpose,content_type,file_size,expires_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id,object_key AS "objectKey",content_type AS "contentType",status,expires_at AS "expiresAt"`, [fileId, user.id, objectKey, path.extname(name).slice(1) || 'bin', input.purpose || 'general', contentType, fileSize, expiresAt]);
    return createdIdempotently(res, user, idempotency, { ...result.rows[0], uploadUrl: `/v1/files/${fileId}/content` });
  }
  if (req.method === 'PUT' && parts[0] === 'v1' && parts[1] === 'files' && parts[3] === 'content') {
    const fileResult = await query('SELECT * FROM files WHERE id=$1', [parts[2]]);
    const file = fileResult.rows[0];
    if (!file || (file.owner_id !== user.id && !hasRole(user, 'admin'))) return fail(res, 404, 'FILE_NOT_FOUND', '文件不存在');
    if (file.expires_at && new Date(file.expires_at) < new Date()) return fail(res, 410, 'FILE_UPLOAD_EXPIRED', '上传凭证已过期');
    const bytes = await rawBody(req);
    if (bytes.length > maxUploadBytes || (Number(file.file_size) > 0 && bytes.length > Number(file.file_size))) return fail(res, 413, 'FILE_SIZE_INVALID', '实际文件大小超过限制');
    if (!fileSignatureMatches(bytes, file.content_type)) return fail(res, 400, 'FILE_SIGNATURE_INVALID', '文件内容与声明类型不匹配');
    await storage.put(file.object_key, bytes, file.content_type);
    const result = await query(`UPDATE files SET file_size=$1,checksum_sha256=$2,status='uploaded',uploaded_at=now() WHERE id=$3 RETURNING id,file_size AS "fileSize",checksum_sha256 AS "checksumSha256",status,uploaded_at AS "uploadedAt"`, [bytes.length, sha256(bytes), file.id]);
    return ok(res, result.rows[0]);
  }
  if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'files' && parts[3] === 'content') {
    const fileResult = await query('SELECT * FROM files WHERE id=$1 AND status=\'uploaded\'', [parts[2]]);
    const file = fileResult.rows[0];
    if (!file || (file.owner_id !== user.id && !(await classPostFileVisibleToUser(user, parts[2])))) return fail(res, 404, 'FILE_NOT_FOUND', '文件不存在');
    let bytes;
    try { bytes = await storage.get(file.object_key); } catch { return fail(res, 404, 'FILE_NOT_FOUND', '文件内容不存在'); }
    res.writeHead(200, { 'Content-Type': file.content_type, 'Content-Length': bytes.length, 'Content-Disposition': `inline; filename="${safeFileName(file.object_key.split('/').pop())}"`, 'Cache-Control': 'private, no-store', ...(corsOrigin ? { 'Access-Control-Allow-Origin': corsOrigin } : {}) });
    return res.end(bytes);
  }
  if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'files' && parts.length === 3) {
    const result = await query('SELECT id,owner_id AS "ownerId",object_key AS "objectKey",file_type AS "fileType",purpose,content_type AS "contentType",file_size AS "fileSize",status,expires_at AS "expiresAt",uploaded_at AS "uploadedAt" FROM files WHERE id=$1', [parts[2]]);
    const file = result.rows[0];
    if (!file || (file.ownerId !== user.id && !(await classPostFileVisibleToUser(user, parts[2])))) return fail(res, 404, 'FILE_NOT_FOUND', '文件不存在');
    return ok(res, file);
  }
  return false;
}
