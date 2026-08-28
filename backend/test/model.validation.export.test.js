import assert from 'node:assert/strict';
import { test } from 'node:test';
import { prepareBlindedValidationExport, SOURCE_MANIFEST_VERSION } from '../../scripts/prepare_blinded_validation_export.mjs';

const secret = '0123456789abcdef0123456789abcdef';
const sample = (index) => ({
  sourceReference: `internal-record-${index}`,
  subjectReference: `internal-child-${index % 3}`,
  artifactSha256: index.toString(16).padStart(64, '0'),
  domain: index % 2 ? 'body' : 'followAlong',
  taskCode: index % 2 ? 'forwardBend' : 'squat',
  ageMonths: 108,
  sexAtMeasurement: 'female',
  deviceModel: 'test-device-a',
  cameraFacing: 'rear-1x',
  lightingBucket: 'indoor-even',
  captureProtocolVersion: 'UY-CAPTURE-GUIDED-2.0',
  modelVersion: 'frozen-model-1',
  thresholdVersion: 'frozen-threshold-1'
});
const manifest = () => ({
  manifestVersion: SOURCE_MANIFEST_VERSION,
  studyId: 'study-2026-01',
  datasetId: 'dataset-independent-01',
  annotatorProtocolVersion: 'UY-ANNOTATION-1.0',
  frozenAt: '2026-08-28T00:00:00.000Z',
  doubleReviewFraction: 0.10,
  samples: Array.from({ length: 20 }, (_, index) => sample(index + 1))
});

test('blinded export is deterministic, pseudonymous and assigns at least ten percent double review', () => {
  const first = prepareBlindedValidationExport(manifest(), secret);
  const second = prepareBlindedValidationExport(manifest(), secret);
  assert.deepEqual(first, second);
  assert.equal(first.samples.filter((entry) => entry.requiredReviewCount === 2).length, 2);
  const serialized = JSON.stringify(first);
  assert.doesNotMatch(serialized, /internal-child|internal-record/);
  assert.doesNotMatch(serialized, /predicted|modelOutput/);
});

test('blinded export rejects identity and raw-media locator fields', () => {
  const value = manifest();
  value.samples[0].studentName = '测试儿童';
  assert.throws(() => prepareBlindedValidationExport(value, secret), /禁止进入盲审导出/);
  delete value.samples[0].studentName;
  value.samples[0].videoPath = '/private/sample.mov';
  assert.throws(() => prepareBlindedValidationExport(value, secret), /禁止进入盲审导出/);
});

test('blinded export never accepts a short pseudonym key', () => {
  assert.throws(() => prepareBlindedValidationExport(manifest(), 'short'), /至少需要 32 字节/);
});
