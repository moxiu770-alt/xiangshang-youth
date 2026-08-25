#!/usr/bin/env node
import assert from 'node:assert/strict';
import { fitMovementCalibration } from './fit_movement_calibration.mjs';

const items = ['连续双脚障碍跳', '侧向滑步', '倒退平衡', '接球-上手掷准', '手运球绕杆', '脚运球变向', '定点踢准'];
const rows = (score) => items.map((item) => ({ item, score, confidence: 0.95, reviewStatus: 'passed', humanReviewed: true }));
const movement = Array.from({ length: 20 }, (_, index) => ({
  id: `fixture-${index}`,
  split: index < 10 ? 'train' : 'validation',
  groupId: `fixture-group-${index}`,
  clipHash: String(index + 1).padStart(2, '0').repeat(32),
  expected: index % 2 ? 'high' : 'low',
  rows: rows(index % 2 ? 2 : 5)
}));
const result = fitMovementCalibration({ kind: 'human-labeled-calibration', evidenceLevel: 'human-labeled', datasetId: 'fixture', movement });
assert.equal(result.status, 'candidate-review-required');
assert.equal(result.train.candidate.accuracy, 1);
assert.equal(result.validation.candidate.accuracy, 1);
assert.match(result.candidateCalibrationVersion, /^UY-CAL-CANDIDATE-[a-f0-9]{12}$/);
console.log(JSON.stringify({ status: 'passed', candidate: result.candidateCalibrationVersion }));
