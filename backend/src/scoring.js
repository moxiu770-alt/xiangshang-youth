/**
 * Canonical movement-score policy shared by report refresh and score writes.
 *
 * The field terminal remains the authority for the measurement itself.  The
 * API only validates, normalizes and aggregates the seven published items so
 * malformed/duplicate payloads cannot inflate a report or silently bypass
 * manual review.
 */
import { MODEL_CALIBRATION_VERSION } from './modelCalibration.js';
import { MODEL_REGISTRY_VERSION } from './modelRegistry.js';

export const MOVEMENT_ITEM_CODES = Object.freeze([
  '连续双脚障碍跳',
  '侧向滑步',
  '倒退平衡',
  '接球-上手掷准',
  '手运球绕杆',
  '脚运球变向',
  '定点踢准'
]);

export const MOVEMENT_ALGORITHM_VERSION = 'UY-IMCA-SCORE-1.3';

export const MOVEMENT_SCORE_RULES = Object.freeze({
  itemCount: MOVEMENT_ITEM_CODES.length,
  itemMaximum: 5,
  lowItemThreshold: 3,
  attentionTotalThreshold: 25,
  highTotalThreshold: 21,
  reviewConfidenceThreshold: 0.8,
  duplicateConflictThreshold: 1.5
});

const itemOrder = new Map(MOVEMENT_ITEM_CODES.map((item, index) => [item, index]));
const roundHalfUp = (value, decimals = 1) => {
  const factor = 10 ** decimals;
  return Math.floor(value * factor + 0.5) / factor;
};

const finiteInput = (value) => {
  // JSON `null`, booleans, empty strings and arrays must not become numeric
  // zero through JavaScript's permissive Number() coercion. They represent
  // missing/malformed field evidence and must remain reviewable.
  if (value == null || typeof value === 'boolean' || typeof value === 'object' || typeof value === 'function') return null;
  if (typeof value === 'string' && value.trim() === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

export function normalizeScore(value) {
  const number = finiteInput(value);
  if (number == null) return null;
  return Math.min(MOVEMENT_SCORE_RULES.itemMaximum, Math.max(0, roundHalfUp(number)));
}

export function normalizeTotalScore(value) {
  const number = finiteInput(value);
  if (number == null) return null;
  return Math.min(MOVEMENT_SCORE_RULES.itemCount * MOVEMENT_SCORE_RULES.itemMaximum, Math.max(0, roundHalfUp(number)));
}

export function normalizeConfidence(value) {
  const number = finiteInput(value);
  if (number == null) return null;
  return Math.min(1, Math.max(0, number));
}

export function normalizeReviewStatus(status, confidence, humanReviewed = false) {
  // A low-confidence sample can never be silently treated as verified. A
  // reviewer may later explicitly approve it through the review endpoint;
  // that explicit human decision is represented separately from machine
  // confidence so it is not immediately downgraded again on mobile.
  if (!humanReviewed && confidence < MOVEMENT_SCORE_RULES.reviewConfidenceThreshold) return 'pendingReview';
  // `humanReviewed` records that a reviewer opened the evidence; it is not
  // itself an approval. Only the explicit `passed` state may leave the
  // review queue, keeping this backend decision identical to iOS/Android and
  // fail-closed for humanReviewed=true + pendingReview payloads.
  if (status === 'passed') return 'passed';
  return 'pendingReview';
}

export function normalizeScoreRow(row) {
  const item = String(row?.item ?? '').trim();
  if (!itemOrder.has(item)) return null;
  const score = normalizeScore(row?.score);
  // Missing confidence means missing evidence, not perfect evidence. Keep it
  // reviewable instead of silently publishing an uncalibrated score.
  const confidence = normalizeConfidence(row?.confidence == null ? 0 : row.confidence);
  if (score == null || confidence == null) return null;
  const humanReviewed = row?.humanReviewed === true || row?.manualReviewed === true;
  const algorithmVersion = typeof row?.algorithmVersion === 'string' ? row.algorithmVersion.trim() : '';
  // A score produced by a different field model cannot be silently mixed
  // into the current seven-item aggregate. Keep legacy rows without a
  // version readable, but force any explicit unsupported version through
  // review so a stale terminal cannot publish a current-model report.
  const unsupportedAlgorithmVersion = algorithmVersion.length > 0 && algorithmVersion !== MOVEMENT_ALGORITHM_VERSION;
  return {
    ...row,
    item,
    score,
    confidence,
    humanReviewed,
    algorithmVersion: algorithmVersion || null,
    unsupportedAlgorithmVersion,
    reviewStatus: unsupportedAlgorithmVersion ? 'pendingReview' : normalizeReviewStatus(row?.reviewStatus, confidence, humanReviewed)
  };
}

/** Keep one row per item, preferring the strongest evidence. */
export function normalizeScoreRows(rows) {
  const selected = new Map();
  for (const raw of Array.isArray(rows) ? rows : []) {
    const row = normalizeScoreRow(raw);
    if (!row) continue;
    const previous = selected.get(row.item);
    if (!previous || row.confidence > previous.confidence || (row.confidence === previous.confidence && row.reviewStatus === 'passed' && previous.reviewStatus !== 'passed')) {
      selected.set(row.item, row);
    }
  }
  return [...selected.values()].sort((a, b) => itemOrder.get(a.item) - itemOrder.get(b.item));
}

export function conflictingMovementItems(rows) {
  const grouped = new Map();
  for (const raw of Array.isArray(rows) ? rows : []) {
    const row = normalizeScoreRow(raw);
    if (!row) continue;
    const list = grouped.get(row.item) || [];
    list.push(row.score);
    grouped.set(row.item, list);
  }
  return [...grouped.entries()]
    .filter(([, scores]) => scores.length > 1 && Math.max(...scores) - Math.min(...scores) >= MOVEMENT_SCORE_RULES.duplicateConflictThreshold)
    .map(([item]) => item);
}

export function evaluateMovementScores(rows) {
  const scores = normalizeScoreRows(rows);
  const conflictSet = new Set(conflictingMovementItems(rows));
  const reviewItems = scores.filter((item) => conflictSet.has(item.item) || item.reviewStatus === 'pendingReview' || (!item.humanReviewed && item.confidence < MOVEMENT_SCORE_RULES.reviewConfidenceThreshold));
  const isComplete = scores.length === MOVEMENT_SCORE_RULES.itemCount;
  const totalScore = scores.reduce((sum, item) => sum + item.score, 0);
  const riskLevel = !isComplete || reviewItems.length > 0
    ? 'unavailable'
    : totalScore < MOVEMENT_SCORE_RULES.highTotalThreshold || scores.filter((item) => item.score < MOVEMENT_SCORE_RULES.lowItemThreshold).length >= 2
      ? 'high'
      : totalScore < MOVEMENT_SCORE_RULES.attentionTotalThreshold || scores.some((item) => item.score < MOVEMENT_SCORE_RULES.lowItemThreshold)
        ? 'attention'
        : 'low';
  return {
    algorithmVersion: MOVEMENT_ALGORITHM_VERSION,
    calibrationVersion: MODEL_CALIBRATION_VERSION,
    modelRegistryVersion: MODEL_REGISTRY_VERSION,
    scores,
    isComplete,
    scoreCompletionRatio: scores.length / MOVEMENT_SCORE_RULES.itemCount,
    totalScore: normalizeTotalScore(totalScore),
    averageScore: scores.length ? totalScore / scores.length : 0,
    meanConfidence: scores.length ? scores.reduce((sum, item) => sum + item.confidence, 0) / scores.length : 0,
    conflictingItems: [...conflictSet],
    reviewItems,
    requiresReview: !isComplete || reviewItems.length > 0,
    riskLevel
  };
}
