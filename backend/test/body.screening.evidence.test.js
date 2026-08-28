import assert from 'node:assert/strict';
import { test } from 'node:test';
import { bodyScreeningEvidenceMetrics, sanitizeHouseholdBodyMetrics } from '../src/bodyScreeningEvidence.js';

test('household evidence strips instrument claims, raw paths and unknown values', () => {
  const result = sanitizeHouseholdBodyMetrics({
    cameraProxyAtrDegrees: 4.2,
    instrumentAtrDegrees: 19,
    thoracicAtrDegrees: 17,
    rawVideoPath: '/private/child.mov',
    mysteryRiskScore: 99,
    captureProtocolVersion: 'UY-CAPTURE-GUIDED-2.0',
    cameraFacing: 'rear-1x',
    qualityChecks: ['device-level', 'two-take-repeatability', 'forged-check']
  }, 'forwardBend');
  assert.equal(result.cameraProxyAtrDegrees, 4.2);
  assert.equal('instrumentAtrDegrees' in result, false);
  assert.equal('thoracicAtrDegrees' in result, false);
  assert.equal('rawVideoPath' in result, false);
  assert.equal('mysteryRiskScore' in result, false);
  assert.deepEqual(result.qualityChecks, ['device-level', 'two-take-repeatability']);
});

test('review projection labels camera geometry as proxy rather than physical measurement', () => {
  const evidence = bodyScreeningEvidenceMetrics({ cameraProxyAtrDegrees: 3.25, cameraProxyRibProminenceCm: 0.34 }, 'forwardBend');
  assert.deepEqual(evidence.map((item) => item.source), ['camera_proxy', 'camera_proxy']);
  assert.match(evidence[0].unit, /非 ATR/);
  assert.match(evidence[1].unit, /投影/);
});

test('task-specific allowlist prevents cross-task evidence pollution', () => {
  const result = sanitizeHouseholdBodyMetrics({ shoulderHeightDifferenceCm: 1.2, gaitTrunkSwayCm: 4.1 }, 'standingBack');
  assert.equal(result.shoulderHeightDifferenceCm, 1.2);
  assert.equal('gaitTrunkSwayCm' in result, false);
});

test('guardian observations remain distinct from camera proxies', () => {
  const evidence = bodyScreeningEvidenceMetrics({ adamsObservedResult: 'equivocal', adamsProminenceSide: '右' }, 'forwardBend');
  assert.equal(evidence[0].source, 'guardian_observation');
  assert.equal(evidence[0].textValue, '观察不确定');
  assert.equal(evidence[1].textValue, '右侧');
});
