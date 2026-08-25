import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BMI_RULE_VERSION, HEIGHT_RULE_VERSION, bmiAgeBucketMonths, bmiAttention, combineBodyLevel, finiteScalar, heightDevelopment, normalizeGender, scoreBodyAssessment } from '../src/bodyScoring.js';

const cleanSnapshots = ['standingBack', 'forwardBend', 'seatedPosture', 'gaitVideo'].map((captureTask) => ({
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
    gaitTrunkSwayCm: 0.2
  }
}));

test('BMI model normalizes supported gender encodings and uses published half-year buckets', () => {
  assert.equal(normalizeGender('男'), 'boy');
  assert.equal(normalizeGender('male'), 'boy');
  assert.equal(normalizeGender('F'), 'girl');
  assert.equal(normalizeGender('unknown'), null);
  assert.equal(bmiAttention({ bmi: 21, ageMonths: 108, gender: 'male' }), 'red');
  assert.equal(bmiAttention({ bmi: 19, ageMonths: 108, gender: '女' }), 'yellow');
  assert.equal(bmiAttention({ bmi: 18, ageMonths: 108, gender: '女' }), 'green');
  assert.equal(bmiAttention({ bmi: 16.96, ageMonths: 84, gender: '男' }), 'yellow');
  assert.equal(bmiAgeBucketMonths(75), 72);
  assert.equal(bmiAttention({ bmi: 16.5, ageMonths: 75, gender: '男' }), 'yellow');
  assert.equal(bmiAttention({ bmi: 21, ageMonths: 71, gender: '男' }), 'unavailable');
  // 16.949 BMI must stay 16.9 for the one-decimal WS/T 586 comparison;
  // rounding to two decimals first would incorrectly cross the 17.0 gate.
  assert.equal(scoreBodyAssessment({ heightCm: 140, weightKg: 33.22, ageMonths: 84, gender: '男', snapshots: cleanSnapshots }).bmiLevel, 'green');
});

test('body model returns the measurement age used for historical re-scoring', () => {
  const report = scoreBodyAssessment({ heightCm: 100, weightKg: 17.2, ageMonths: 84, gender: '男', snapshots: [] });
  assert.equal(report.ageMonths, 84);
});

test('body model combines BMI and posture without allowing unavailable data to look healthy', () => {
  assert.equal(combineBodyLevel('green', 'red'), 'red');
  assert.equal(combineBodyLevel('yellow', 'green'), 'yellow');
  assert.equal(combineBodyLevel('pending', 'unavailable'), 'pending');
  assert.equal(combineBodyLevel('green', 'unavailable'), 'unavailable');
  assert.equal(combineBodyLevel('unavailable', 'green'), 'unavailable');
  assert.equal(combineBodyLevel('unknown', 'green'), 'unavailable');

  const report = scoreBodyAssessment({ heightCm: 135, weightKg: 40, ageMonths: 108, gender: '男', snapshots: cleanSnapshots });
  assert.equal(report.bmiRuleVersion, BMI_RULE_VERSION);
  assert.equal(report.bmiAlgorithmVersion, 'UY-IMCA-BMI-1.2');
  assert.equal(report.bmiAgeBucketMonths, 108);
  assert.equal(report.postureReport.overallLevel, 'green');
  assert.equal(report.bmiLevel, 'red');
  assert.equal(report.overallLevel, 'red');
  assert.equal(report.heightReport.ruleVersion, HEIGHT_RULE_VERSION);
  assert.equal(report.heightAlgorithmVersion, 'UY-IMCA-HEIGHT-1.0');
  assert.equal(report.modelRegistryVersion, 'UY-MODELS-1.0');
  assert.equal(report.heightReport.level, 'middle');

  const malformedMeasurements = scoreBodyAssessment({ heightCm: 40, weightKg: 120, ageMonths: 108, gender: '男', snapshots: cleanSnapshots });
  assert.equal(malformedMeasurements.bmi, 0);
  assert.equal(malformedMeasurements.bmiLevel, 'unavailable');
});

test('height model matches the native age/sex bands and fails closed outside scope', () => {
  assert.equal(heightDevelopment({ heightCm: 125, ageMonths: 84, gender: 'male' }).level, 'middle');
  assert.equal(heightDevelopment({ heightCm: 100, ageMonths: 84, gender: '男' }).level, 'low');
  assert.equal(heightDevelopment({ heightCm: 150, ageMonths: 83, gender: '男' }), null);
  assert.equal(heightDevelopment({ heightCm: 150, ageMonths: 120, gender: 'unknown' }), null);
  assert.equal(heightDevelopment({ heightCm: [], ageMonths: 120, gender: '男' }), null);
  assert.equal(bmiAttention({ bmi: false, ageMonths: 120, gender: '男' }), 'unavailable');
  assert.equal(scoreBodyAssessment({ heightCm: [], weightKg: 35, ageMonths: 120, gender: '男', snapshots: cleanSnapshots }).bmiLevel, 'unavailable');
});

test('body scalar gate rejects coercive JSON values consistently', () => {
  assert.equal(finiteScalar(true), null);
  assert.equal(finiteScalar([]), null);
  assert.equal(finiteScalar(['100']), null);
  assert.equal(finiteScalar('  '), null);
  assert.equal(finiteScalar('100'), 100);
});
