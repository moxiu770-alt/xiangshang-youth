import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const hash = (value) => crypto.createHash('sha256').update(value).digest('hex');
const hmac = (key, value) => crypto.createHmac('sha256', key).update(value).digest();
const encodePath = (value) => String(value).split('/').map((part) => encodeURIComponent(part)).join('/');

function localStorage(rootValue) {
  const root = path.resolve(rootValue);
  const objectPath = (objectKey) => {
    const target = path.resolve(root, String(objectKey).replace(/^\/+/, ''));
    if (!target.startsWith(`${root}${path.sep}`)) throw Object.assign(new Error('文件路径非法'), { status: 400, code: 'FILE_PATH_INVALID' });
    return target;
  };
  return {
    driver: 'local',
    async put(objectKey, bytes) {
      const target = objectPath(objectKey);
      await fs.mkdir(path.dirname(target), { recursive: true });
      await fs.writeFile(target, bytes, { flag: 'w' });
    },
    async get(objectKey) { return fs.readFile(objectPath(objectKey)); },
    async remove(objectKey) { await fs.rm(objectPath(objectKey), { force: true }); },
    async health() { await fs.mkdir(root, { recursive: true }); return { driver: 'local', ready: true }; }
  };
}

function s3Storage({ endpoint, bucket, accessKey, secretKey, region = 'auto' }) {
  if (!endpoint || !bucket || !accessKey || !secretKey) throw new Error('S3 存储需要 S3_STORAGE_ENDPOINT、S3_BUCKET、S3_ACCESS_KEY 和 S3_SECRET_KEY');
  const base = new URL(endpoint);

  async function request(method, objectKey, bytes = null, contentType = null) {
    const canonicalUri = `${base.pathname.replace(/\/$/, '')}/${encodeURIComponent(bucket)}/${encodePath(objectKey)}`;
    const target = new URL(`${base.origin}${canonicalUri}`);
    const now = new Date();
    const amzDate = now.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
    const date = amzDate.slice(0, 8);
    const payloadHash = hash(bytes || Buffer.alloc(0));
    const headers = {
      host: target.host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate
    };
    if (contentType) headers['content-type'] = contentType;
    const signedHeaders = Object.keys(headers).sort();
    const canonicalHeaders = signedHeaders.map((key) => `${key}:${String(headers[key]).trim()}\n`).join('');
    const canonicalRequest = [method, target.pathname, '', canonicalHeaders, signedHeaders.join(';'), payloadHash].join('\n');
    const scope = `${date}/${region}/s3/aws4_request`;
    const stringToSign = ['AWS4-HMAC-SHA256', amzDate, scope, hash(canonicalRequest)].join('\n');
    const signingKey = hmac(hmac(hmac(hmac(`AWS4${secretKey}`, date), region), 's3'), 'aws4_request');
    const signature = crypto.createHmac('sha256', signingKey).update(stringToSign).digest('hex');
    headers.authorization = `AWS4-HMAC-SHA256 Credential=${accessKey}/${scope}, SignedHeaders=${signedHeaders.join(';')}, Signature=${signature}`;
    const response = await fetch(target, { method, headers, body: bytes || undefined });
    if (!response.ok) throw Object.assign(new Error(`对象存储请求失败: ${response.status}`), { status: 502, code: 'STORAGE_REQUEST_FAILED' });
    return response;
  }

  return {
    driver: 's3',
    async put(objectKey, bytes, contentType) { await request('PUT', objectKey, bytes, contentType); },
    async get(objectKey) { return Buffer.from(await (await request('GET', objectKey)).arrayBuffer()); },
    async remove(objectKey) { await request('DELETE', objectKey); },
    async health() { return { driver: 's3', ready: true, bucket }; }
  };
}

export function createStorage(config) {
  if (config.storageDriver === 'local') return localStorage(config.storageRoot || fileURLToPath(new URL('../storage/', import.meta.url)));
  if (config.storageDriver === 's3') {
    return s3Storage({
      endpoint: config.storageEndpoint || config.endpoint,
      bucket: config.storageBucket || config.bucket,
      accessKey: config.storageAccessKey || config.accessKey,
      secretKey: config.storageSecretKey || config.secretKey,
      region: config.storageRegion || config.region
    });
  }
  throw new Error(`不支持的文件存储驱动: ${config.storageDriver}`);
}
