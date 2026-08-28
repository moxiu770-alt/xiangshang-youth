import assert from 'node:assert/strict';
import { test } from 'node:test';
import { POSTURE_ALGORITHM_VERSION, POSTURE_RULES_SOURCE_VERSION, postureProfileForAge, scorePostureSnapshots } from '../src/postureScoring.js';

const tasks = ['standingFront', 'standingBack', 'standingSide', 'forwardBend', 'dynamicKneeControl', 'gaitVideo', 'seatedPosture', 'footArch'];

const baseTaskMetrics = Object.freeze({
  standingFront: { shoulderHeightDifferenceCm: 0.2, pelvicHeightDifferenceCm: 0.2 },
  standingBack: { shoulderHeightDifferenceCm: 0.2, pelvicHeightDifferenceCm: 0.2 },
  standingSide: { thoracicRoundingDegrees: 10, forwardHeadAngleDegrees: 5 },
  forwardBend: { spinalMidlineDeviationCm: 0.2, cameraProxyAtrDegrees: 2 },
  dynamicKneeControl: {
    leftKneeValgusProxyDegrees: 8,
    rightKneeValgusProxyDegrees: 8,
    kneeTrackingAsymmetryRatio: 0.04,
    squatDepthRatio: 0.4,
    movementRepetitionCount: 3
  },
  gaitVideo: {
    gaitShoulderSwingDifferenceCm: 0.2,
    gaitPelvicSwingDifferenceCm: 0.2,
    gaitTrunkSwayCm: 0.2
  },
  seatedPosture: { spinalMidlineDeviationCm: 0.2, thoracicRoundingDegrees: 10 },
  footArch: {
    footArchVisibilityScore: 0.85,
    leftArchProxyIndex: 0.3,
    rightArchProxyIndex: 0.3,
    heelAlignmentProxyDegrees: 2
  }
});

function snapshots(overrides = {}) {
  return tasks.map((captureTask) => ({
    captureTask,
    sampleCount: 18,
    confidence: 0.82,
    metrics: {
      ...baseTaskMetrics[captureTask],
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
    { captureTask: 'standingFront', metrics: { shoulderHeightDifferenceCm: 0.2 } },
    { captureTask: 'standingBack', metrics: { shoulderHeightDifferenceCm: 0.2 } },
    { captureTask: 'standingSide', metrics: { forwardHeadAngleDegrees: 5 } },
    { captureTask: 'forwardBend', metrics: { thoracicRoundingDegrees: 10 } },
    { captureTask: 'dynamicKneeControl', metrics: { movementRepetitionCount: 3 } },
    { captureTask: 'seatedPosture', metrics: { spinalMidlineDeviationCm: 0.2 } },
    { captureTask: 'gaitVideo', metrics: { gaitTrunkSwayCm: 0.2 } },
    { captureTask: 'footArch', metrics: { footArchVisibilityScore: 0.8 } }
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
  assert.equal(scorePostureSnapshots(snapshots(), 71).overallLevel, 'pending');
  assert.equal(scorePostureSnapshots(snapshots(), 156).overallLevel, 'pending');
  assert.equal(scorePostureSnapshots(snapshots(), null).overallLevel, 'pending');
  assert.equal(scorePostureSnapshots(snapshots(), 155).ageApplicable, true);
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

test('server posture scorer follows the framework ATR boundary bands exactly', () => {
  assert.equal(scorePostureSnapshots(snapshots({ forwardBend: { thoracicAtrDegrees: 4.9 } }), 108).overallLevel, 'green');
  assert.equal(scorePostureSnapshots(snapshots({ forwardBend: { thoracicAtrDegrees: 5.0 } }), 108).overallLevel, 'yellow');
  assert.equal(scorePostureSnapshots(snapshots({ forwardBend: { thoracicAtrDegrees: 6.9 } }), 108).overallLevel, 'yellow');
  assert.equal(scorePostureSnapshots(snapshots({ forwardBend: { thoracicAtrDegrees: 7.0 } }), 108).overallLevel, 'red');
});

test('server posture scorer recomputes fluctuating ATR readings by arithmetic mean', () => {
  const averaged = scorePostureSnapshots(snapshots({
    forwardBend: {
      thoracicAtrDegrees: 8.0,
      thoracicAtrFirstDegrees: 4.0,
      thoracicAtrSecondDegrees: 6.0
    }
  }), 108);
  assert.equal(averaged.overallLevel, 'yellow');
  assert.ok(averaged.reasons.some((reason) => reason.includes('算术平均 5.0°')));
});

test('server posture scorer applies the seated ATR three-degree review rule', () => {
  const functional = scorePostureSnapshots(snapshots({
    forwardBend: { thoracicAtrDegrees: 5.5, seatedForwardBendAtrDegrees: 2.0 }
  }), 108);
  assert.equal(functional.overallLevel, 'yellow');
  assert.ok(functional.reasons.some((reason) => reason.includes('功能性偏斜可能')));

  const structuralReview = scorePostureSnapshots(snapshots({
    forwardBend: { thoracicAtrDegrees: 5.5, seatedForwardBendAtrDegrees: 3.0 }
  }), 108);
  assert.equal(structuralReview.overallLevel, 'red');
  assert.ok(structuralReview.reasons.some((reason) => reason.includes('结构异常复核提示')));
});

test('server posture scorer follows standing, seated, OTWD and combined red rules', () => {
  assert.equal(scorePostureSnapshots(snapshots({ standingBack: { shoulderHeightDifferenceCm: 0.5 } }), 108).overallLevel, 'green');
  assert.equal(scorePostureSnapshots(snapshots({ standingBack: { shoulderHeightDifferenceCm: 0.51 } }), 108).overallLevel, 'yellow');
  assert.equal(scorePostureSnapshots(snapshots({ seatedPosture: { occiputWallDistanceCm: 2.0 } }), 108).overallLevel, 'green');
  assert.equal(scorePostureSnapshots(snapshots({ seatedPosture: { occiputWallDistanceCm: 2.1 } }), 108).overallLevel, 'yellow');

  const combined = scorePostureSnapshots(snapshots({
    forwardBend: { adamsResult: 'positive' },
    gaitVideo: { gaitTrunkSwayCm: 1.1 }
  }), 108);
  assert.equal(combined.overallLevel, 'red');
});

test('server posture scorer treats supervised manual observations as authoritative evidence', () => {
  const manualRed = scorePostureSnapshots(snapshots({
    forwardBend: { adamsObservedResult: 'positive', adamsProminenceSide: '右' },
    seatedPosture: { seatedThoracicKyphosisObserved: true },
    gaitVideo: { gaitObservedAbnormal: false, gaitObservationNote: '肩骨盆摆动基本对称' }
  }), 108);
  assert.equal(manualRed.overallLevel, 'red');
  assert.ok(manualRed.reasons.some((reason) => reason.includes('右侧')));
  assert.ok(manualRed.reasons.some((reason) => reason.includes('圆肩驼背')));
});

test('server labels guided camera capture honestly and only accepts complete marker PnP evidence as formal geometry', () => {
  const guided = snapshots().map((snapshot) => ({
    ...snapshot,
    metrics: {
      ...snapshot.metrics,
      captureProtocolVersion: 'UY-CAPTURE-GUIDED-1.0',
      cameraFacing: 'rear-1x',
      qualityChecks: snapshot.captureTask === 'footArch'
        ? ['device-level', 'foot-close-up', 'lower-limb-landmarks', 'single-person', 'landmark-confidence', 'multi-frame-robust']
        : ['device-level', 'full-body', 'single-person', 'landmark-confidence', 'multi-frame-robust'],
      captureCalibration: { mode: 'guided', boardDetected: false }
    }
  }));
  const guidedReport = scorePostureSnapshots(guided, 108);
  assert.equal(guidedReport.captureQuality.level, 'guided-quality-gate');
  assert.equal(guidedReport.captureQuality.formalMeasurementEligible, false);
  assert.match(guidedReport.reasons.join(' '), /尚未检测物理标定板/);

  const incompletePnp = guided.map((snapshot) => ({
    ...snapshot,
    metrics: {
      ...snapshot.metrics,
      captureProtocolVersion: 'UY-CAPTURE-MARKER-PNP-1.0',
      captureCalibration: { mode: 'marker-pnp', boardDetected: true, boardId: 'board-a' }
    }
  }));
  assert.equal(scorePostureSnapshots(incompletePnp, 108).captureQuality.level, 'trace-incomplete');

  const unregisteredPnp = guided.map((snapshot) => ({
    ...snapshot,
    metrics: {
      ...snapshot.metrics,
      captureProtocolVersion: 'UY-CAPTURE-MARKER-PNP-1.0',
      captureCalibration: { mode: 'marker-pnp', boardDetected: true, boardId: 'board-a', intrinsicsId: 'i-a', lensId: 'rear-1x', resolution: '1920x1080', reprojectionErrorPx: 1.2 }
    }
  }));
  assert.equal(scorePostureSnapshots(unregisteredPnp, 108).captureQuality.level, 'trace-incomplete');

  const incompleteSecondTake = guided.map((snapshot) => ({
    ...snapshot,
    metrics: { ...snapshot.metrics, captureProtocolVersion: 'UY-CAPTURE-GUIDED-2.0' }
  }));
  assert.equal(scorePostureSnapshots(incompleteSecondTake, 108).captureQuality.level, 'trace-incomplete');
});
