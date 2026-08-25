#!/usr/bin/env node
/**
 * Leak-safe calibration candidate search for the seven-item movement model.
 *
 * This script never edits production code or modelCalibration.js. It fits a
 * candidate on `split=train`, reports it once on `split=validation`, and
 * prints a reviewable candidate manifest. A candidate is not deployable until
 * a human approves the validation metrics and updates the versioned manifest.
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { MOVEMENT_ITEM_CODES, MOVEMENT_SCORE_RULES, normalizeScoreRows } from '../backend/src/scoring.js';
import { MODEL_CALIBRATION_VERSION } from '../backend/src/modelCalibration.js';

export const MOVEMENT_CALIBRATION_SEARCH_VERSION = 'UY-CAL-SEARCH-1.0';
const labels = ['low', 'attention', 'high', 'unavailable'];

export function rowsFor(sample) {
  if (Array.isArray(sample?.rows)) return sample.rows;
  return MOVEMENT_ITEM_CODES.map((item, index) => ({
    item,
    score: sample?.scores?.[index],
    confidence: sample?.confidence,
    reviewStatus: 'passed',
    humanReviewed: true
  }));
}

export function classifyMovement(rows, rules) {
  const scores = normalizeScoreRows(rows);
  const reviewItems = scores.filter((item) => item.reviewStatus === 'pendingReview' || (!item.humanReviewed && item.confidence < rules.reviewConfidenceThreshold));
  const complete = scores.length === MOVEMENT_ITEM_CODES.length;
  const total = scores.reduce((sum, item) => sum + item.score, 0);
  if (!complete || reviewItems.length) return 'unavailable';
  if (total < rules.highTotalThreshold || scores.filter((item) => item.score < rules.lowItemThreshold).length >= 2) return 'high';
  if (total < rules.attentionTotalThreshold || scores.some((item) => item.score < rules.lowItemThreshold)) return 'attention';
  return 'low';
}

export function confusionMetrics(rows) {
  const perLabel = Object.fromEntries(labels.map((label) => {
    const tp = rows.filter((row) => row.expected === label && row.actual === label).length;
    const fp = rows.filter((row) => row.expected !== label && row.actual === label).length;
    const fn = rows.filter((row) => row.expected === label && row.actual !== label).length;
    const precision = tp + fp ? tp / (tp + fp) : 0;
    const recall = tp + fn ? tp / (tp + fn) : 0;
    const f1 = precision + recall ? (2 * precision * recall) / (precision + recall) : 0;
    return [label, { support: tp + fn, precision, recall, f1 }];
  }));
  const covered = labels.filter((label) => perLabel[label].support > 0);
  const balancedAccuracy = covered.length ? covered.reduce((sum, label) => sum + perLabel[label].recall, 0) / covered.length : 0;
  const macroF1 = covered.length ? covered.reduce((sum, label) => sum + perLabel[label].f1, 0) / covered.length : 0;
  return {
    samples: rows.length,
    accuracy: rows.length ? rows.filter((row) => row.expected === row.actual).length / rows.length : 0,
    balancedAccuracy,
    macroF1,
    perLabel
  };
}

function requireHumanCalibrationCorpus(corpus) {
  if (!corpus || typeof corpus !== 'object' || corpus.kind !== 'human-labeled-calibration' || corpus.evidenceLevel !== 'human-labeled') {
    throw new Error('校准集必须声明 kind=human-labeled-calibration 与 evidenceLevel=human-labeled');
  }
  if (!Array.isArray(corpus.movement) || corpus.movement.length < 20) throw new Error('校准集至少需要 20 条 movement 样本');
  const ids = new Set();
  const groups = new Map();
  const clips = new Map();
  for (const sample of corpus.movement) {
    if (!sample?.id || ids.has(sample.id)) throw new Error(`movement id 缺失或重复: ${sample?.id || ''}`);
    ids.add(sample.id);
    if (!['train', 'validation'].includes(sample.split)) throw new Error(`样本 split 必须是 train/validation: ${sample.id}`);
    if (!labels.includes(sample.expected)) throw new Error(`movement 标签非法: ${sample.id}`);
    const groupId = String(sample.groupId || '').trim();
    const clipHash = String(sample.clipHash || '').trim().toLowerCase();
    if (!groupId || !/^[a-f0-9]{64}$/.test(clipHash)) throw new Error(`样本必须有匿名 groupId 与 SHA-256 clipHash: ${sample.id}`);
    const previousGroup = groups.get(groupId);
    if (previousGroup && previousGroup !== sample.split) throw new Error(`groupId 跨 train/validation 泄漏: ${sample.id}`);
    groups.set(groupId, sample.split);
    const previousClip = clips.get(clipHash);
    if (previousClip && previousClip !== sample.split) throw new Error(`clipHash 跨 train/validation 泄漏: ${sample.id}`);
    clips.set(clipHash, sample.split);
    const rows = rowsFor(sample);
    if (!Array.isArray(rows) || !rows.length) throw new Error(`movement rows 为空: ${sample.id}`);
    if (rows.some((row) => !MOVEMENT_ITEM_CODES.includes(row?.item))) throw new Error(`movement item 非法: ${sample.id}`);
  }
  const train = corpus.movement.filter((sample) => sample.split === 'train');
  const validation = corpus.movement.filter((sample) => sample.split === 'validation');
  if (train.length < 10 || validation.length < 10) throw new Error('train 与 validation 各至少需要 10 条样本');
  return { train, validation };
}

function evaluate(samples, rules) {
  return confusionMetrics(samples.map((sample) => ({ id: sample.id, expected: sample.expected, actual: classifyMovement(rowsFor(sample), rules) })));
}

function candidateDistance(rules) {
  return Math.abs(rules.highTotalThreshold - MOVEMENT_SCORE_RULES.highTotalThreshold) +
    Math.abs(rules.attentionTotalThreshold - MOVEMENT_SCORE_RULES.attentionTotalThreshold) +
    Math.abs(rules.lowItemThreshold - MOVEMENT_SCORE_RULES.lowItemThreshold);
}

export function fitMovementCalibration(corpus) {
  const { train, validation } = requireHumanCalibrationCorpus(corpus);
  const baselineTrain = evaluate(train, MOVEMENT_SCORE_RULES);
  const baselineValidation = evaluate(validation, MOVEMENT_SCORE_RULES);
  let best = null;
  for (let high = 18; high <= 24.0001; high += 0.1) {
    for (let attention = Math.max(high + 0.1, 22); attention <= 30.0001; attention += 0.1) {
      for (let low = 2.5; low <= 3.5001; low += 0.1) {
        const rules = { ...MOVEMENT_SCORE_RULES, highTotalThreshold: Number(high.toFixed(1)), attentionTotalThreshold: Number(attention.toFixed(1)), lowItemThreshold: Number(low.toFixed(1)) };
        const metrics = evaluate(train, rules);
        const candidate = { rules, metrics, distance: candidateDistance(rules) };
        if (!best || candidate.metrics.macroF1 > best.metrics.macroF1 ||
          (candidate.metrics.macroF1 === best.metrics.macroF1 && candidate.metrics.balancedAccuracy > best.metrics.balancedAccuracy) ||
          (candidate.metrics.macroF1 === best.metrics.macroF1 && candidate.metrics.balancedAccuracy === best.metrics.balancedAccuracy && candidate.distance < best.distance)) best = candidate;
      }
    }
  }
  const candidateValidation = evaluate(validation, best.rules);
  const sourceHash = crypto.createHash('sha256').update(JSON.stringify(corpus)).digest('hex');
  return {
    searchVersion: MOVEMENT_CALIBRATION_SEARCH_VERSION,
    baseCalibrationVersion: MODEL_CALIBRATION_VERSION,
    candidateCalibrationVersion: `UY-CAL-CANDIDATE-${sourceHash.slice(0, 12)}`,
    status: 'candidate-review-required',
    sourceDatasetId: corpus.datasetId || null,
    sourceHash,
    rules: best.rules,
    train: { baseline: baselineTrain, candidate: best.metrics },
    validation: { baseline: baselineValidation, candidate: candidateValidation }
  };
}

function main() {
  const corpusPath = process.argv[2];
  if (!corpusPath || process.argv.includes('--help')) {
    console.error('用法: node scripts/fit_movement_calibration.mjs /path/to/calibration.json');
    process.exit(corpusPath ? 0 : 2);
  }
  const corpus = JSON.parse(fs.readFileSync(path.resolve(corpusPath), 'utf8'));
  console.log(JSON.stringify(fitMovementCalibration(corpus), null, 2));
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) main();
