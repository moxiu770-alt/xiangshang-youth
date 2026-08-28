#!/usr/bin/env node
/**
 * Build a deterministic, de-identified annotation worklist.
 *
 * The source manifest contains references and SHA-256 digests only. Raw media
 * stays in a separately consented, access-controlled validation environment;
 * the production App/API must never be used as research-media storage.
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export const BLINDED_EXPORT_VERSION = 'UY-BLINDED-VALIDATION-1.0';
export const SOURCE_MANIFEST_VERSION = 'UY-VALIDATION-SOURCE-1.0';
const DOMAINS = new Set(['body', 'followAlong', 'movement']);
const CAMERA_FACING = new Set(['rear-1x', 'front-1x']);
const SHA256 = /^[a-f0-9]{64}$/i;
const FORBIDDEN_KEYS = /(?:name|phone|mobile|email|address|idcard|identity|studentid|guardian|parent|url|path|filename|raw(?:image|video|frame)|landmarks|skeleton)/i;

const requiredText = (value, label, maximum = 160) => {
  const text = typeof value === 'string' ? value.trim() : '';
  if (!text || text.length > maximum) throw new Error(`${label} 缺失或过长`);
  return text;
};

function assertNoForbiddenKeys(value, location = 'manifest') {
  if (!value || typeof value !== 'object') return;
  if (Array.isArray(value)) return value.forEach((item, index) => assertNoForbiddenKeys(item, `${location}[${index}]`));
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_KEYS.test(key)) throw new Error(`${location}.${key} 禁止进入盲审导出；请仅提供摘要和受控引用`);
    assertNoForbiddenKeys(child, `${location}.${key}`);
  }
}

const hmacCode = (secret, namespace, value, length = 20) => crypto
  .createHmac('sha256', secret)
  .update(`${namespace}\u0000${value}`)
  .digest('hex')
  .slice(0, length);

function annotationTemplate(domain) {
  if (domain === 'body') return {
    captureUsable: null,
    expectedPosture: null,
    professionalAction: null,
    observedRegions: [],
    notes: ''
  };
  if (domain === 'followAlong') return {
    captureUsable: null,
    expectedRepCount: null,
    leftRightCorrect: null,
    phaseQuality: null,
    correctionTags: [],
    notes: ''
  };
  return {
    captureUsable: null,
    itemScores: [],
    notes: ''
  };
}

export function prepareBlindedValidationExport(input, secret) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('验证源清单必须是 JSON 对象');
  if (typeof secret !== 'string' || Buffer.byteLength(secret, 'utf8') < 32) throw new Error('VALIDATION_PSEUDONYM_KEY 至少需要 32 字节随机密钥');
  assertNoForbiddenKeys(input);
  if (input.manifestVersion !== SOURCE_MANIFEST_VERSION) throw new Error(`manifestVersion 必须为 ${SOURCE_MANIFEST_VERSION}`);
  const studyId = requiredText(input.studyId, 'studyId');
  const datasetId = requiredText(input.datasetId, 'datasetId');
  const annotatorProtocolVersion = requiredText(input.annotatorProtocolVersion, 'annotatorProtocolVersion');
  if (!Number.isFinite(Date.parse(input.frozenAt))) throw new Error('frozenAt 必须是固定的 ISO-8601 时间');
  const fraction = Number(input.doubleReviewFraction ?? 0.10);
  if (!Number.isFinite(fraction) || fraction < 0.10 || fraction > 1) throw new Error('doubleReviewFraction 必须在 0.10–1.00');
  if (!Array.isArray(input.samples) || !input.samples.length) throw new Error('samples 不能为空');

  const sourceIds = new Set();
  const artifactHashes = new Set();
  const candidates = input.samples.map((sample, index) => {
    const sourceReference = requiredText(sample?.sourceReference, `samples[${index}].sourceReference`);
    const subjectReference = requiredText(sample?.subjectReference, `samples[${index}].subjectReference`);
    const artifactSha256 = requiredText(sample?.artifactSha256, `samples[${index}].artifactSha256`, 64).toLowerCase();
    const domain = requiredText(sample?.domain, `samples[${index}].domain`);
    if (sourceIds.has(sourceReference)) throw new Error(`sourceReference 重复: ${sourceReference}`);
    if (!SHA256.test(artifactSha256) || artifactHashes.has(artifactSha256)) throw new Error(`artifactSha256 非法或重复: samples[${index}]`);
    if (!DOMAINS.has(domain)) throw new Error(`samples[${index}].domain 不支持`);
    const ageMonths = Number(sample.ageMonths);
    if (!Number.isInteger(ageMonths) || ageMonths < 72 || ageMonths > 216) throw new Error(`samples[${index}].ageMonths 超出 6–18 岁范围`);
    const cameraFacing = requiredText(sample.cameraFacing, `samples[${index}].cameraFacing`);
    if (!CAMERA_FACING.has(cameraFacing)) throw new Error(`samples[${index}].cameraFacing 不支持`);
    sourceIds.add(sourceReference);
    artifactHashes.add(artifactSha256);
    const sampleCode = `S-${hmacCode(secret, `${studyId}:sample`, sourceReference)}`;
    return {
      sampleCode,
      groupCode: `G-${hmacCode(secret, `${studyId}:subject`, subjectReference)}`,
      artifactSha256,
      domain,
      taskCode: requiredText(sample.taskCode, `samples[${index}].taskCode`),
      metadata: {
        ageMonths,
        sexAtMeasurement: requiredText(sample.sexAtMeasurement, `samples[${index}].sexAtMeasurement`, 32),
        deviceModel: requiredText(sample.deviceModel, `samples[${index}].deviceModel`),
        cameraFacing,
        lightingBucket: requiredText(sample.lightingBucket, `samples[${index}].lightingBucket`, 32),
        captureProtocolVersion: requiredText(sample.captureProtocolVersion, `samples[${index}].captureProtocolVersion`),
        modelVersion: requiredText(sample.modelVersion, `samples[${index}].modelVersion`),
        thresholdVersion: requiredText(sample.thresholdVersion, `samples[${index}].thresholdVersion`)
      },
      annotation: annotationTemplate(domain),
      rank: hmacCode(secret, `${studyId}:double-review`, sourceReference, 64)
    };
  });

  const doubleReviewCount = Math.max(1, Math.ceil(candidates.length * fraction));
  const doubleReviewCodes = new Set([...candidates].sort((a, b) => a.rank.localeCompare(b.rank)).slice(0, doubleReviewCount).map((sample) => sample.sampleCode));
  const samples = candidates
    .map(({ rank: _rank, ...sample }) => ({ ...sample, requiredReviewCount: doubleReviewCodes.has(sample.sampleCode) ? 2 : 1 }))
    .sort((a, b) => a.sampleCode.localeCompare(b.sampleCode));
  return {
    exportVersion: BLINDED_EXPORT_VERSION,
    studyId,
    datasetId,
    frozenAt: new Date(input.frozenAt).toISOString(),
    annotatorProtocolVersion,
    doubleReviewFraction: fraction,
    sourcePolicy: 'separately-consented-secure-validation-storage',
    blinding: 'model-output-and-identity-hidden',
    samples
  };
}

function main() {
  const args = process.argv.slice(2);
  const inputIndex = args.indexOf('--input');
  const outputIndex = args.indexOf('--output');
  const inputPath = inputIndex >= 0 ? args[inputIndex + 1] : null;
  const outputPath = outputIndex >= 0 ? args[outputIndex + 1] : null;
  if (!inputPath || !outputPath) throw new Error('用法：--input <结构化源清单.json> --output <盲审工作单.json>');
  const result = prepareBlindedValidationExport(
    JSON.parse(fs.readFileSync(path.resolve(inputPath), 'utf8')),
    process.env.VALIDATION_PSEUDONYM_KEY
  );
  fs.writeFileSync(path.resolve(outputPath), `${JSON.stringify(result, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
  process.stdout.write(`已生成 ${result.samples.length} 条盲审工作单；${result.samples.filter((sample) => sample.requiredReviewCount === 2).length} 条双人独立复核。\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) main();
