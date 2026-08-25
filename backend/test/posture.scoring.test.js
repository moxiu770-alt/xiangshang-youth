import assert from 'node:assert/strict';
import { test } from 'node:test';
import { POSTURE_ALGORITHM_VERSION, POSTURE_RULES_SOURCE_VERSION, postureProfileForAge, scorePostureSnapshots } from '../src/postureScoring.js';

const tasks = ['standingBack', 'forwardBend', 'seatedPosture', 'gaitVideo'];

function snapshots(overrides = {}) {
  return tasks.map((captureTask) => ({
    captureTask,
    sampleCount: 18,
    confidence: 0.82,
    metrics: {
      shoulderHeightDifferenceCm: 0.2,
      pelvicHeightDifferenceCm: 0.2,
      spinalMidlineDeviationCm: 0.2,
      thoracicRoundingDegrees: 10,
      forwardHeadAngleDegrees: 5,
      gaitShoulderSwingDifferenceCm: 0.2,
      gaitPelvicSwingDifferenceCm: 0.2,
      gaitTrunkSwayCm: 0.2,
      ...overrides[captureTask]
    }
  }));
}

test('server posture scorer is complete, bounded, and green for clean evidence', () => {
  const report = scorePostureSnapshots(snapshots(), 108);
  assert.equal(report.algorithm, POSTURE_ALGORITHM_VERSION);
  assert.equal(report.rulesSourceVersion, POSTURE_RULES_SOURCE_VERSION);
  assert.equal(report.complete, true);
  assert.equal(report.overallLevel, 'green');
  assert.ok(report.riskScore >= 0 && report.riskScore <= 100);
  assert.ok(report.qualityScore >= 0 && report.qualityScore <= 100);
});

test('server posture scorer ignores a forged client level and applies objective thresholds', () => {
  const shoulder = scorePostureSnapshots(snapshots({ standingBack: { shoulderHeightDifferenceCm: 2.0 } }), 108);
  assert.equal(shoulder.overallLevel, 'yellow');

  const atr = scorePostureSnapshots(snapshots({ forwardBend: { instrumentAtrDegrees: 7.0 } }), 108);
  assert.equal(atr.overallLevel, 'red');
});

test('server posture scorer never publishes incomplete or malformed evidence', () => {
  const incomplete = scorePostureSnapshots(snapshots().slice(0, 3), 108);
  assert.equal(incomplete.complete, false);
  assert.equal(incomplete.overallLevel, 'pending');
  assert.equal(incomplete.riskScore, 0);

  const malformed = scorePostureSnapshots(snapshots({ seatedPosture: { spinalMidlineDeviationCm: Number.NaN } }), 108);
  assert.equal(malformed.overallLevel, 'pending');
  assert.equal(malformed.complete, false);
  assert.ok(malformed.reasons.every((reason) => !reason.includes('NaN')));

  const absurd = scorePostureSnapshots(snapshots({ standingBack: { shoulderHeightDifferenceCm: 999 } }), 108);
  assert.equal(absurd.overallLevel, 'pending');
  assert.equal(absurd.complete, false);

  const noMetrics = scorePostureSnapshots(snapshots().map((snapshot) => ({ ...snapshot, metrics: {} })), 108);
  assert.equal(noMetrics.overallLevel, 'pending');
  assert.equal(noMetrics.complete, false);
  const arrayMetrics = scorePostureSnapshots(snapshots().map((snapshot) => ({ ...snapshot, metrics: [] })), 108);
  assert.equal(arrayMetrics.overallLevel, 'pending');

  const emptyStringEvidence = scorePostureSnapshots(snapshots({ standingBack: { shoulderHeightDifferenceCm: '' } }), 108);
  assert.equal(emptyStringEvidence.complete, false);
  assert.equal(emptyStringEvidence.overallLevel, 'pending');

  const missingSnapshot = scorePostureSnapshots(snapshots().map((snapshot) => ({ ...snapshot })).slice(0, 3), 108);
  assert.equal(missingSnapshot.complete, false);
});

test('server posture scorer requires evidence that belongs to each capture task', () => {
  const mismatched = snapshots().map((snapshot) => ({
    ...snapshot,
    metrics: { shoulderHeightDifferenceCm: 0.2 }
  }));
  const rejected = scorePostureSnapshots(mismatched, 108);
  assert.equal(rejected.complete, false);
  assert.equal(rejected.overallLevel, 'pending');

  const taskSpecific = [
    { captureTask: 'standingBack', metrics: { shoulderHeightDifferenceCm: 0.2 } },
    { captureTask: 'forwardBend', metrics: { thoracicRoundingDegrees: 10 } },
    { captureTask: 'seatedPosture', metrics: { spinalMidlineDeviationCm: 0.2 } },
    { captureTask: 'gaitVideo', metrics: { gaitTrunkSwayCm: 0.2 } }
  ].map((snapshot) => ({ ...snapshot, sampleCount: 18, confidence: 0.82 }));
  const accepted = scorePostureSnapshots(taskSpecific, 108);
  assert.equal(accepted.complete, true);
  assert.equal(accepted.overallLevel, 'green');
});

test('server posture scorer selects the age-specific profile at both boundaries', () => {
  const younger = scorePostureSnapshots(snapshots({ standingBack: { shoulderHeightDifferenceCm: 1.06 } }), 96);
  const older = scorePostureSnapshots(snapshots({ standingBack: { shoulderHeightDifferenceCm: 1.06 } }), 97);
  assert.equal(younger.overallLevel, 'yellow');
  assert.equal(older.overallLevel, 'yellow');
  assert.notEqual(younger.riskScore, older.riskScore);
});

test('server posture scorer clamps out-of-scope ages like native clients', () => {
  assert.equal(postureProfileForAge(71).minMonths, 72);
  assert.equal(postureProfileForAge(217).minMonths, 181);
  assert.equal(postureProfileForAge(null).minMonths, 97);
});

test('server posture scorer consumes numeric rib-prominence and camera ATR evidence', () => {
  const rib = snapshots({ forwardBend: { cameraProxyRibProminenceCm: 1.3 } });
  assert.equal(scorePostureSnapshots(rib, 108).overallLevel, 'yellow');
  const ribWithGait = snapshots({ forwardBend: { cameraProxyRibProminenceCm: 1.3 }, gaitVideo: { gaitTrunkSwayCm: 1.4 } });
  assert.equal(scorePostureSnapshots(ribWithGait, 108).overallLevel, 'red');

  const atr = snapshots({ forwardBend: { cameraProxyAtrDegrees: 7.2 } });
  assert.equal(scorePostureSnapshots(atr, 108).overallLevel, 'green');
});

test('server posture scorer applies head tilt and calibrated thoracic/lumbar ATR', () => {
  const headTilt = scorePostureSnapshots(snapshots({ standingBack: { headTiltDegrees: 6.5 } }), 108);
  assert.equal(headTilt.overallLevel, 'yellow');

  const thoracicAtr = scorePostureSnapshots(snapshots({ forwardBend: { thoracicAtrDegrees: 7.0 } }), 108);
  assert.equal(thoracicAtr.overallLevel, 'red');

  const lumbarAtr = scorePostureSnapshots(snapshots({ forwardBend: { lumbarAtrDegrees: 5.0 } }), 108);
  assert.equal(lumbarAtr.overallLevel, 'yellow');
});
