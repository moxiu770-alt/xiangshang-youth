import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BodyScreeningRoute, REQUIRED_VALIDATION_DOMAINS, containsRawMedia, decideBodyScreening } from '../src/bodyScreeningDecision.js';

const validatedDomains = Object.fromEntries(REQUIRED_VALIDATION_DOMAINS.map((domain) => [domain, 'human-validated']));

const snapshots = ['standingFront', 'standingBack', 'standingSide', 'forwardBend', 'dynamicKneeControl', 'gaitVideo', 'seatedPosture', 'footArch'].map((captureTask) => ({
  captureTask, sampleCount: 24, confidence: 0.91,
  metrics: {
    captureProtocolVersion: 'UY-CAPTURE-GUIDED-3.0', cameraFacing: 'rear-1x',
    measurementMode: 'rgb-pose-2d', deviceCapabilityTier: 'standard-2d', depthAvailable: false,
    segmentPhaseCount: ['standingSide', 'footArch'].includes(captureTask) ? 2 : 1,
    qualityChecks: captureTask === 'footArch'
      ? ['device-level', 'foot-close-up', 'lower-limb-landmarks', 'single-person', 'landmark-confidence', 'multi-frame-robust', 'two-take-repeatability']
      : ['device-level', 'full-body', 'single-person', 'landmark-confidence', 'multi-frame-robust', 'two-take-repeatability'],
    captureAttemptCount: 2, repeatabilityStatus: 'passed', repeatabilityMaximumDifference: 1.2,
    ...(captureTask === 'dynamicKneeControl' ? { movementRepetitionCount: 3, qualityChecks: ['device-level', 'full-body', 'single-person', 'landmark-confidence', 'multi-frame-robust', 'two-take-repeatability', 'three-repetition-cycle'] } : {})
  }
}));

test('commercial triage requires recapture when a task or repeatability proof is missing', () => {
  assert.equal(decideBodyScreening({ snapshots: snapshots.slice(0, 3), postureReport: { validationStatus: 'human-validated' } }).route, BodyScreeningRoute.RECAPTURE);
  const inconsistent = structuredClone(snapshots);
  inconsistent[1].metrics.repeatabilityStatus = 'inconsistent';
  assert.equal(decideBodyScreening({ snapshots: inconsistent, postureReport: { validationStatus: 'human-validated' } }).route, BodyScreeningRoute.RECAPTURE);
});

test('dynamic knee task requires three complete squat and return cycles', () => {
  const incomplete = structuredClone(snapshots);
  incomplete.find((item) => item.captureTask === 'dynamicKneeControl').metrics.movementRepetitionCount = 2;
  const result = decideBodyScreening({ snapshots: incomplete, postureReport: { validationStatus: 'human-validated' } });
  assert.equal(result.route, BodyScreeningRoute.RECAPTURE);
  assert.ok(result.reasonCodes.includes('DYNAMIC_REPETITIONS_INCOMPLETE'));
});

test('side and foot segments require both directed phases', () => {
  const incomplete = structuredClone(snapshots);
  incomplete.find((item) => item.captureTask === 'standingSide').metrics.segmentPhaseCount = 1;
  const result = decideBodyScreening({ snapshots: incomplete, postureReport: { validationStatus: 'human-validated' } });
  assert.equal(result.route, BodyScreeningRoute.RECAPTURE);
  assert.ok(result.reasonCodes.includes('BILATERAL_PHASES_INCOMPLETE'));
});

test('unvalidated model is routed to professional review, never auto-published', () => {
  const result = decideBodyScreening({ snapshots, postureReport: { validationStatus: 'pending-human-validation', riskScore: 0 } });
  assert.equal(result.route, BodyScreeningRoute.PROFESSIONAL_REVIEW);
  assert.equal(result.reviewRequired, true);
});

test('only validated low-risk and low-uncertainty evidence is auto archived', () => {
  const result = decideBodyScreening({ snapshots, postureReport: { validationStatus: 'human-validated', domainValidation: validatedDomains, riskScore: 8, overallLevel: 'green' }, modelUncertainty: 0.08 });
  assert.equal(result.route, BodyScreeningRoute.AUTO_ARCHIVE);
});

test('global validation cannot bypass an unvalidated screening domain', () => {
  const domainValidation = { ...validatedDomains, foot_arch: 'pending-human-validation' };
  const result = decideBodyScreening({ snapshots, postureReport: { validationStatus: 'human-validated', domainValidation, riskScore: 8, overallLevel: 'green' }, modelUncertainty: 0.08 });
  assert.equal(result.route, BodyScreeningRoute.PROFESSIONAL_REVIEW);
  assert.ok(result.reasonCodes.includes('DOMAIN_VALIDATION_INCOMPLETE'));
});

test('foot close-up cannot be replaced by generic full-body proof', () => {
  const invalid = structuredClone(snapshots);
  invalid.find((item) => item.captureTask === 'footArch').metrics.qualityChecks = [
    'device-level', 'full-body', 'single-person', 'landmark-confidence',
    'multi-frame-robust', 'two-take-repeatability'
  ];
  const result = decideBodyScreening({ snapshots: invalid, postureReport: { validationStatus: 'human-validated', domainValidation: validatedDomains } });
  assert.equal(result.route, BodyScreeningRoute.RECAPTURE);
  assert.ok(result.reasonCodes.includes('QUALITY_GATE_INCOMPLETE'));
});

test('structured-only contract detects raw child media recursively', () => {
  assert.equal(containsRawMedia({ snapshots }), false);
  assert.equal(containsRawMedia({ metrics: { rawVideoData: 'base64' } }), true);
  assert.equal(containsRawMedia({ evidence: [{ imageUrl: 'https://example.test/child.jpg' }] }), true);
});
