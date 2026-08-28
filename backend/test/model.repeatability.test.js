import assert from 'node:assert/strict';
import { test } from 'node:test';
import { evaluateRepeatability, REPEATABILITY_POLICY_VERSION } from '../../scripts/evaluate_capture_repeatability.mjs';

function corpus({ unstable = false } = {}) {
  const postureRuns = Array.from({ length: 10 }, (_, index) => ({
    runId: `p-${index}`,
    setupId: `re-enter-calibration-zone-${index}`,
    capturedAt: `2026-08-28T10:${String(index).padStart(2, '0')}:00.000Z`,
    captureProtocolVersion: 'UY-CAPTURE-GUIDED-1.0',
    cameraFacing: 'rear-1x',
    qualityChecks: ['device-level', 'full-body', 'single-person', 'landmark-confidence', 'multi-frame-robust'],
    complete: true,
    metrics: { shoulderHeightDifferenceCm: unstable && index === 9 ? 2.0 : 0.4 + index * 0.01, headTiltDegrees: 1 + index * 0.05 }
  }));
  const countRuns = Array.from({ length: 10 }, (_, index) => ({ runId: `f-${index}`, predictedRepCount: unstable && index > 5 ? 7 : 10 }));
  return {
    policyVersion: REPEATABILITY_POLICY_VERSION,
    postureGroups: [{ subjectId: 'anonymous-child-1', algorithmVersion: 'UY-IMCA-CV-1.3', deviceModel: 'device-a', cameraPosition: 'rear', captureProtocolVersion: 'UY-CAPTURE-GUIDED-1.0', calibrationMode: 'guided', cameraLensId: 'rear-wide-1x', resolution: '1920x1080', runs: postureRuns }],
    followAlongGroups: [{ subjectId: 'anonymous-child-1', algorithmVersion: 'UY-FOLLOW-CV-1.0', deviceModel: 'device-a', cameraPosition: 'front', category: 'squat', expectedRepCount: 10, runs: countRuns }]
  };
}

test('repeatability gate passes ten stable runs without claiming clinical validity', () => {
  const report = evaluateRepeatability(corpus());
  assert.equal(report.status, 'passed');
  assert.match(report.disclaimer, /不代表健康结论正确/);
});

test('repeatability gate rejects unstable posture and follow-along output', () => {
  const report = evaluateRepeatability(corpus({ unstable: true }));
  assert.equal(report.status, 'failed');
  assert.ok(report.failures.some((message) => message.includes('shoulderHeightDifferenceCm')));
  assert.ok(report.failures.some((message) => message.includes('计数重复性未达标')));
});

test('guided capture can prove screening repeatability but never physical measurement eligibility', () => {
  const report = evaluateRepeatability(corpus(), { releaseGate: true });
  assert.equal(report.status, 'failed');
  assert.equal(report.posture[0].screeningRepeatabilityEligible, true);
  assert.equal(report.posture[0].formalMeasurementEligible, false);
  assert.equal(report.failures.some((message) => message.includes('marker-pnp 标定')), false);
  assert.match(report.disclaimer, /不得声称物理厘米/);
});

test('repeatability gate requires each posture run to be an independent re-entry', () => {
  const value = corpus();
  value.postureGroups[0].runs[1].setupId = value.postureGroups[0].runs[0].setupId;
  assert.throws(() => evaluateRepeatability(value), /唯一 setupId/);
});
