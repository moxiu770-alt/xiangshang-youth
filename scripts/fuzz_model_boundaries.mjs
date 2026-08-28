#!/usr/bin/env node
/**
 * Deterministic property checks for the frozen rule models.
 * This is not an accuracy benchmark; it catches numeric instability,
 * non-monotonic thresholds and malformed-input paths before release.
 */
import assert from 'node:assert/strict';
import { MOVEMENT_ITEM_CODES, evaluateMovementScores } from '../backend/src/scoring.js';
import { bmiAttention, heightDevelopment, scoreBodyAssessment } from '../backend/src/bodyScoring.js';
import { scoreGrowth } from '../backend/src/growthScoring.js';

let state = 0x9e3779b9;
function random() {
  state |= 0;
  state = (state + 0x6d2b79f5) | 0;
  let t = Math.imul(state ^ (state >>> 15), 1 | state);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const between = (min, max) => min + (max - min) * random();
const levels = new Set(['green', 'yellow', 'red', 'pending', 'unavailable']);
const movementRank = { unavailable: 0, high: 1, attention: 2, low: 3 };
const bodyRank = { unavailable: 0, pending: 0, green: 1, yellow: 2, red: 3 };
const bmiRank = { unavailable: -1, green: 0, yellow: 1, red: 2 };
const heightRank = { low: 0, lower: 1, middle: 2, upper: 3, high: 4 };
const postureRank = { pending: 0, green: 1, yellow: 2, red: 3 };
let fuzzCases = 0;

const cleanMetrics = () => ({
  shoulderHeightDifferenceCm: between(-2, 2),
  pelvicHeightDifferenceCm: between(-2, 2),
  spinalMidlineDeviationCm: between(-2, 2),
  thoracicRoundingDegrees: between(0, 40),
  forwardHeadAngleDegrees: between(0, 24),
  cameraProxyRibProminenceCm: between(0, 2),
  gaitShoulderSwingDifferenceCm: between(-2, 2),
  gaitPelvicSwingDifferenceCm: between(-2, 2),
  gaitTrunkSwayCm: between(-2, 2)
});
const snapshots = (complete = true) => {
  const tasks = ['standingFront', 'standingBack', 'standingSide', 'forwardBend', 'dynamicKneeControl', 'gaitVideo', 'seatedPosture', 'footArch'];
  return tasks.slice(0, complete ? 4 : Math.floor(between(0, 4))).map((captureTask) => ({
    captureTask,
    sampleCount: Math.floor(between(0, 30)),
    confidence: between(-0.2, 1.2),
    metrics: cleanMetrics()
  }));
};

for (let i = 0; i < 10000; i += 1) {
  const report = scoreBodyAssessment({
    heightCm: between(60, 230),
    weightKg: between(-10, 130),
    ageMonths: Math.floor(between(0, 250)),
    gender: random() > 0.5 ? '男' : '女',
    snapshots: snapshots(random() > 0.15)
  });
  assert.ok(Number.isFinite(report.bmi) && report.bmi >= 0);
  assert.ok(levels.has(report.overallLevel));
  assert.ok(levels.has(report.postureReport.overallLevel));
  assert.ok(Number.isFinite(report.postureReport.riskScore) && report.postureReport.riskScore >= 0 && report.postureReport.riskScore <= 100);
  assert.ok(Number.isFinite(report.postureReport.qualityScore) && report.postureReport.qualityScore >= 0 && report.postureReport.qualityScore <= 100);
  fuzzCases += 1;
}

for (const gender of ['男', '女']) {
  for (const ageMonths of [72, 73, 77, 78, 96, 97, 108, 132, 133, 180, 181, 216]) {
    let previous = -1;
    for (let index = 0; index <= 400; index += 1) {
      const rank = bmiRank[bmiAttention({ bmi: index / 10, ageMonths, gender })];
      assert.ok(rank >= previous, `BMI threshold regressed: ${gender}/${ageMonths}/${index / 10}`);
      previous = rank;
      fuzzCases += 1;
    }
  }
}

for (const gender of ['男', '女']) {
  for (const ageMonths of [84, 95, 96, 97, 108, 119, 120, 132, 133, 180, 181, 216]) {
    let previous = -1;
    for (let heightCm = 90; heightCm <= 190; heightCm += 0.25) {
      const result = heightDevelopment({ heightCm, ageMonths, gender });
      const rank = result ? heightRank[result.level] : -1;
      assert.ok(rank >= previous, `height threshold regressed: ${gender}/${ageMonths}/${heightCm}`);
      previous = rank;
      fuzzCases += 1;
    }
  }
}

for (let i = 0; i < 5000; i += 1) {
  const base = MOVEMENT_ITEM_CODES.map((item) => ({ item, score: between(0, 5), confidence: 0.95, reviewStatus: 'passed' }));
  const increased = base.map((row) => ({ ...row, score: Math.min(5, row.score + between(0, 5 - row.score)) }));
  const before = evaluateMovementScores(base);
  const after = evaluateMovementScores(increased);
  assert.ok(movementRank[after.riskLevel] >= movementRank[before.riskLevel], `movement risk worsened after scores increased: ${before.riskLevel} -> ${after.riskLevel}`);
  fuzzCases += 1;
}

for (let i = 0; i < 1000; i += 1) {
  const report = scoreBodyAssessment({ heightCm: 140, weightKg: 35, ageMonths: 120, gender: '男', snapshots: snapshots(true).map((row) => ({ ...row, confidence: Number.NaN })) });
  assert.equal(report.postureReport.overallLevel, 'pending');
  assert.ok(bodyRank[report.overallLevel] >= 0);
  fuzzCases += 1;
}

// Growth is a deterministic habit model, so malformed dates/counts must never
// crash it and adding one valid in-window activity may not reduce consistency.
const growthNow = new Date('2026-08-22T16:00:00.000Z'); // 2026-08-23 00:00 Asia/Shanghai
const growthDate = (offset) => {
  const value = new Date(growthNow.getTime() - offset * 24 * 60 * 60 * 1000);
  return value.toISOString().slice(0, 10);
};
for (let i = 0; i < 3000; i += 1) {
  const period = random() > 0.5 ? 'week' : 'month';
  const dates = Array.from({ length: Math.floor(between(0, 40)) }, () => growthDate(Math.floor(between(0, 45))));
  const plans = Array.from({ length: Math.floor(between(0, 40)) }, () => growthDate(Math.floor(between(0, 45))));
  const malformed = random() > 0.7 ? ['', '2026-02-30', null, [], false] : [];
  const report = scoreGrowth({
    period,
    checkInDates: [...dates, ...malformed],
    planDates: [...plans, ...malformed],
    assessmentCount: random() > 0.5 ? between(-20, 40) : { invalid: true },
    bodyAttention: ['red', 'yellow', 'pending', 'unavailable', null][Math.floor(between(0, 5))],
    totalScore: random() > 0.5 ? between(-20, 60) : [],
    now: growthNow
  });
  assert.ok(Number.isInteger(report.activeDays) && report.activeDays >= 0);
  assert.ok(Number.isInteger(report.planDays) && report.planDays >= 0);
  assert.ok(Number.isInteger(report.consistencyPercent) && report.consistencyPercent >= 0 && report.consistencyPercent <= 100);
  assert.ok(Number.isInteger(report.assessmentCount) && report.assessmentCount >= 0);
  fuzzCases += 1;
}

for (const period of ['week', 'month']) {
  for (let i = 0; i < 500; i += 1) {
    const existing = new Set(Array.from({ length: Math.floor(between(0, 8)) }, () => growthDate(Math.floor(between(0, period === 'week' ? 7 : 30)))));
    const candidate = growthDate(Math.floor(between(0, period === 'week' ? 7 : 30)));
    const before = scoreGrowth({ period, checkInDates: [...existing], planDates: [], now: growthNow });
    const after = scoreGrowth({ period, checkInDates: [...existing, candidate], planDates: [], now: growthNow });
    assert.ok(after.activeDays >= before.activeDays, `growth active days regressed: ${before.activeDays} -> ${after.activeDays}`);
    assert.ok(after.consistencyPercent >= before.consistencyPercent, `growth consistency regressed: ${before.consistencyPercent} -> ${after.consistencyPercent}`);
    fuzzCases += 1;
  }
}

// A larger observed shoulder asymmetry must never lower a complete posture
// report's risk. This catches accidental sign/normalization inversions.
for (const ageMonths of [72, 108, 156, 192]) {
  let previous = -1;
  for (let shoulder = 0; shoulder <= 4; shoulder += 0.05) {
    const report = scoreBodyAssessment({
      heightCm: 140, weightKg: 35, ageMonths, gender: '男',
      snapshots: ['standingFront', 'standingBack', 'standingSide', 'forwardBend', 'dynamicKneeControl', 'gaitVideo', 'seatedPosture', 'footArch'].map((captureTask) => ({
        captureTask, sampleCount: 18, confidence: 0.90,
        metrics: {
          shoulderHeightDifferenceCm: captureTask === 'standingBack' ? shoulder : 0.2,
          pelvicHeightDifferenceCm: 0.2,
          spinalMidlineDeviationCm: 0.2,
          thoracicRoundingDegrees: 10,
          forwardHeadAngleDegrees: 5,
          gaitShoulderSwingDifferenceCm: 0.2,
          gaitPelvicSwingDifferenceCm: 0.2,
          gaitTrunkSwayCm: 0.2
        }
      }))
    });
    const rank = postureRank[report.postureReport.overallLevel];
    assert.ok(rank >= previous, `posture risk regressed: age=${ageMonths}, shoulder=${shoulder}`);
    previous = rank;
    fuzzCases += 1;
  }
}

console.log(JSON.stringify({ seed: '0x9e3779b9', fuzzCases, status: 'passed' }));
