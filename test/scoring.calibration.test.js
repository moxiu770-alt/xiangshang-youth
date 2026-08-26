import assert from 'node:assert/strict';
import { test } from 'node:test';
import { MOVEMENT_ITEM_CODES, MOVEMENT_SCORE_RULES, evaluateMovementScores, normalizeTotalScore } from '../src/scoring.js';

function rows(scores, confidence = 0.95, extra = {}) {
  return MOVEMENT_ITEM_CODES.map((item, index) => ({
    item,
    score: Array.isArray(scores) ? scores[index] : scores,
    confidence,
    reviewStatus: 'passed',
    ...extra
  }));
}

test('scoring calibration keeps the published decision boundaries explicit', () => {
  assert.equal(MOVEMENT_SCORE_RULES.itemCount, 7);
  assert.equal(MOVEMENT_SCORE_RULES.itemMaximum, 5);

  const allFive = evaluateMovementScores(rows(5));
  assert.deepEqual(
    { total: allFive.totalScore, level: allFive.riskLevel, review: allFive.requiresReview },
    { total: 35, level: 'low', review: false }
  );

  // Exactly 25 remains the attention boundary's healthy side; 24.9 is attention.
  assert.equal(evaluateMovementScores(rows(25 / 7)).riskLevel, 'low');
  assert.equal(evaluateMovementScores(rows([3.4, 3.4, 3.4, 3.4, 3.4, 3.4, 3.5])).riskLevel, 'attention');

  // A single weak item is attention; two weak items are high even if the sum is high.
  assert.equal(evaluateMovementScores(rows([2.9, 4, 4, 4, 4, 4, 4])).riskLevel, 'attention');
  assert.equal(evaluateMovementScores(rows([2.9, 2.9, 5, 5, 5, 5, 5])).riskLevel, 'high');
  assert.equal(evaluateMovementScores(rows([0, 0, 5, 5, 5, 5, 5])).riskLevel, 'high');
});

test('total score uses the same non-bankers half-up rule as native clients', () => {
  assert.equal(normalizeTotalScore(24.95), 25.0);
  assert.equal(normalizeTotalScore(34.949), 34.9);
  assert.equal(normalizeTotalScore(40), 35);
});

test('scoring calibration never publishes an incomplete or unverified vector', () => {
  const missing = evaluateMovementScores(rows(5).slice(0, 6));
  assert.equal(missing.isComplete, false);
  assert.equal(missing.scoreCompletionRatio, 6 / 7);
  assert.equal(missing.riskLevel, 'unavailable');

  const lowConfidence = evaluateMovementScores(rows(5, MOVEMENT_SCORE_RULES.reviewConfidenceThreshold - 0.001));
  assert.equal(lowConfidence.requiresReview, true);
  assert.equal(lowConfidence.riskLevel, 'unavailable');

  const approved = evaluateMovementScores(rows(5, 0.3, { humanReviewed: true }));
  assert.equal(approved.requiresReview, false);
  assert.equal(approved.riskLevel, 'low');
});

test('scoring calibration selects one strongest evidence row per item', () => {
  const duplicate = [
    ...rows(5),
    { item: MOVEMENT_ITEM_CODES[0], score: 0, confidence: 1, reviewStatus: 'passed' },
    { item: MOVEMENT_ITEM_CODES[1], score: 5, confidence: 0.99, reviewStatus: 'pendingReview' }
  ];
  const result = evaluateMovementScores(duplicate);
  assert.equal(result.scores.length, 7);
  assert.equal(result.scores[0].score, 0);
  assert.equal(result.scores[1].score, 5);
  assert.equal(result.scores[1].reviewStatus, 'pendingReview');
  assert.equal(result.riskLevel, 'unavailable');
  assert.ok(result.conflictingItems.includes(MOVEMENT_ITEM_CODES[0]));
});

test('scoring calibration sends contradictory duplicate evidence to review', () => {
  const duplicate = [...rows(4), { item: MOVEMENT_ITEM_CODES[3], score: 1.5, confidence: 0.99, reviewStatus: 'passed' }];
  const result = evaluateMovementScores(duplicate);
  assert.deepEqual(result.conflictingItems, [MOVEMENT_ITEM_CODES[3]]);
  assert.equal(result.requiresReview, true);
  assert.equal(result.riskLevel, 'unavailable');
});

test('scoring calibration fails closed for an explicit stale field algorithm', () => {
  const stale = evaluateMovementScores(rows(5).map((row) => ({ ...row, algorithmVersion: 'UY-IMCA-SCORE-1.2' })));
  assert.equal(stale.requiresReview, true);
  assert.equal(stale.riskLevel, 'unavailable');
  assert.ok(stale.reviewItems.every((row) => row.unsupportedAlgorithmVersion === true));

  // Historical rows without a version remain readable during migration; new
  // rows are versioned by the field-session ingest path and are checked above.
  const legacy = evaluateMovementScores(rows(5));
  assert.equal(legacy.requiresReview, false);
  assert.equal(legacy.riskLevel, 'low');
});
