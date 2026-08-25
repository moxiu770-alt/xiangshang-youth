#!/usr/bin/env node
/**
 * Offline model gate.
 *
 * The checked-in corpus is synthetic boundary regression, not a claim of
 * real-world accuracy. Pass --corpus <file> (or MODEL_CORPUS_PATH) to run the
 * exact same evaluator against a human-labelled corpus. The evaluator never
 * tunes thresholds or trains on the input; it only scores a frozen model and
 * reports confusion/precision/recall so the validation set remains auditable.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { MOVEMENT_ALGORITHM_VERSION, MOVEMENT_ITEM_CODES, evaluateMovementScores } from '../backend/src/scoring.js';
import { MODEL_CALIBRATION_STATUS, MODEL_CALIBRATION_VERSION } from '../backend/src/modelCalibration.js';
import { scoreBodyAssessment } from '../backend/src/bodyScoring.js';
import { scoreGrowth } from '../backend/src/growthScoring.js';
import { MODEL_REGISTRY, MODEL_REGISTRY_VERSION } from '../backend/src/modelRegistry.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const corpusArgIndex = args.indexOf('--corpus');
const outputArgIndex = args.indexOf('--output');
const corpusPath = corpusArgIndex >= 0 && args[corpusArgIndex + 1]
  ? args[corpusArgIndex + 1]
  : process.env.MODEL_CORPUS_PATH || path.join(root, 'qa/model_golden_corpus.json');
const requireLabeled = args.includes('--require-labeled') || process.env.REQUIRE_LABELED_MODEL_CORPUS === '1';
const releaseGate = args.includes('--release-gate') || process.env.RELEASE_GATE_MODEL_CORPUS === '1';
const outputPath = outputArgIndex >= 0 && args[outputArgIndex + 1]
  ? path.resolve(args[outputArgIndex + 1])
  : null;
const corpus = JSON.parse(fs.readFileSync(path.resolve(corpusPath), 'utf8'));
const followAssetPath = path.join(root, 'android/app/src/main/assets/follow_along_action_profiles.json');
const followAsset = JSON.parse(fs.readFileSync(followAssetPath, 'utf8'));
const bodyCaptureAssetPath = path.join(root, 'android/app/src/main/assets/body_pose_capture_profiles.json');
const bodyCaptureAsset = JSON.parse(fs.readFileSync(bodyCaptureAssetPath, 'utf8'));
const cleanMetrics = {
  shoulderHeightDifferenceCm: 0.2,
  pelvicHeightDifferenceCm: 0.2,
  headTiltDegrees: 1,
  spinalMidlineDeviationCm: 0.2,
  thoracicRoundingDegrees: 10,
  forwardHeadAngleDegrees: 5,
  gaitShoulderSwingDifferenceCm: 0.2,
  gaitPelvicSwingDifferenceCm: 0.2,
  gaitTrunkSwayCm: 0.2
};
const snapshotsFor = (kind) => {
  const tasks = ['standingBack', 'forwardBend', 'seatedPosture', 'gaitVideo'];
  const snapshots = tasks.map((captureTask) => ({ captureTask, sampleCount: 18, confidence: 0.82, metrics: { ...cleanMetrics } }));
  if (kind === 'shoulder') snapshots[0].metrics.shoulderHeightDifferenceCm = 2.0;
  if (kind === 'atr') snapshots[1].metrics.instrumentAtrDegrees = 7.0;
  if (kind === 'incomplete') snapshots.pop();
  return snapshots;
};

const finite = (value) => {
  // Keep the evaluator's corpus semantics identical to runtime scorers:
  // JSON arrays/objects/booleans/blank strings are malformed, not numeric 0.
  if (value == null || typeof value === 'boolean' || typeof value === 'object' || typeof value === 'function' || (typeof value === 'string' && value.trim() === '')) return false;
  return Number.isFinite(Number(value));
};
const movementLabels = new Set(['low', 'attention', 'high', 'unavailable']);
const bodyLabels = new Set(['green', 'yellow', 'red', 'pending', 'unavailable']);
const bmiLabels = new Set(['green', 'yellow', 'red', 'unavailable']);
const heightLabels = new Set(['low', 'lower', 'middle', 'upper', 'high']);

function validateCorpus(input) {
  if (!input || typeof input !== 'object') throw new Error('模型语料必须是 JSON 对象');
  if (!/^UY-IMCA-CV-\d+\.\d+$/.test(String(input.version || ''))) throw new Error('模型语料缺少合法 version');
  if (!Array.isArray(input.movement) || !Array.isArray(input.body)) throw new Error('模型语料必须包含 movement 与 body 数组');
  const ids = new Set();
  const clipHashes = new Set();
  const labeled = input.evidenceLevel === 'human-labeled' || input.kind === 'human-labeled-independent-validation';
  for (const sample of [...input.movement, ...input.body, ...(Array.isArray(input.growth) ? input.growth : []), ...(Array.isArray(input.followAlong) ? input.followAlong : [])]) {
    if (!sample || typeof sample !== 'object' || !sample.id || ids.has(sample.id)) throw new Error(`模型样本 id 缺失或重复: ${sample?.id || ''}`);
    ids.add(sample.id);
    if (!sample.expected && !sample.expectedPlanTitle && sample.expectedRepCount == null) throw new Error(`模型样本缺少 expected: ${sample.id}`);
    if (labeled) {
      const groupId = String(sample.groupId || sample.metadata?.groupId || '').trim();
      const clipHash = String(sample.clipHash || sample.metadata?.clipHash || '').trim();
      if (requireLabeled && (!groupId || !/^[a-f0-9]{64}$/i.test(clipHash))) throw new Error(`独立标注样本必须提供匿名 groupId 与 64 位 SHA-256 clipHash: ${sample.id}`);
      if (clipHash) {
        if (clipHashes.has(clipHash)) throw new Error(`验证集存在重复 clipHash，可能发生数据泄漏: ${sample.id}`);
        clipHashes.add(clipHash);
      }
      if (requireLabeled && sample.split !== 'validation') throw new Error(`独立验证门禁要求 split=validation: ${sample.id}`);
    }
  }
  for (const sample of input.movement) {
    if (!movementLabels.has(sample.expected)) throw new Error(`movement 标签非法: ${sample.id}`);
    const rows = Array.isArray(sample.rows) ? sample.rows : null;
    if (rows) {
      if (!rows.length) throw new Error(`movement rows 为空: ${sample.id}`);
      for (const row of rows) {
        if (!MOVEMENT_ITEM_CODES.includes(row?.item) || !finite(row?.score) || !finite(row?.confidence)) throw new Error(`movement row 非法: ${sample.id}`);
        if (Number(row.confidence) < 0 || Number(row.confidence) > 1) throw new Error(`movement confidence 越界: ${sample.id}`);
      }
    } else {
      if (!Array.isArray(sample.scores) || sample.scores.length !== MOVEMENT_ITEM_CODES.length) throw new Error(`movement scores 必须是 7 项: ${sample.id}`);
      if (!sample.scores.every((score) => finite(score) && Number(score) >= 0 && Number(score) <= 5)) throw new Error(`movement score 越界: ${sample.id}`);
      if (!finite(sample.confidence) || Number(sample.confidence) < 0 || Number(sample.confidence) > 1) throw new Error(`movement confidence 非法: ${sample.id}`);
    }
  }
  for (const sample of input.body) {
    if (!bodyLabels.has(sample.expected)) throw new Error(`body 标签非法: ${sample.id}`);
    if (!finite(sample.heightCm) || Number(sample.heightCm) < 90 || Number(sample.heightCm) > 190 || !finite(sample.weightKg) || Number(sample.weightKg) < 15 || Number(sample.weightKg) > 90 || !Number.isInteger(sample.ageMonths) || sample.ageMonths < 72 || sample.ageMonths > 216) throw new Error(`body 基础测量字段非法: ${sample.id}`);
    if (!sample.gender) throw new Error(`body gender 缺失: ${sample.id}`);
    if (sample.snapshots != null && !Array.isArray(sample.snapshots)) throw new Error(`body snapshots 必须是数组: ${sample.id}`);
    if (sample.expectedBmi != null && !bmiLabels.has(sample.expectedBmi)) throw new Error(`body BMI 标签非法: ${sample.id}`);
    if (sample.expectedHeight != null && !heightLabels.has(sample.expectedHeight)) throw new Error(`body 身高标签非法: ${sample.id}`);
    if (sample.expectedPosture != null && !bodyLabels.has(sample.expectedPosture)) throw new Error(`body 姿态标签非法: ${sample.id}`);
  }
  if (input.growth != null && !Array.isArray(input.growth)) throw new Error('growth 必须是数组');
  for (const sample of input.growth || []) {
    if (!['week', 'month'].includes(sample.period)) throw new Error(`growth 周期非法: ${sample.id}`);
    if (!Array.isArray(sample.checkInDates) || !Array.isArray(sample.planDates)) throw new Error(`growth 日期数组缺失: ${sample.id}`);
    for (const date of [...sample.checkInDates, ...sample.planDates]) if (!/^\d{4}-\d{2}-\d{2}$/.test(String(date))) throw new Error(`growth 日期格式非法: ${sample.id}`);
    if (sample.expectedPlanTitle == null || !Number.isInteger(sample.expectedActiveDays) || !Number.isInteger(sample.expectedConsistencyPercent)) throw new Error(`growth 期望结果缺失: ${sample.id}`);
    if (sample.expectedConsistencyPercent < 0 || sample.expectedConsistencyPercent > 100 || sample.expectedActiveDays < 0) throw new Error(`growth 期望结果越界: ${sample.id}`);
  }
  if (input.followAlong != null && !Array.isArray(input.followAlong)) throw new Error('followAlong 必须是数组');
  for (const sample of input.followAlong || []) {
    if (!Number.isInteger(sample.ageMonths) || sample.ageMonths < 72 || sample.ageMonths > 216) throw new Error(`followAlong ageMonths 非法: ${sample.id}`);
    if (typeof sample.category !== 'string' || !sample.category.trim()) throw new Error(`followAlong category 缺失: ${sample.id}`);
    if (!Number.isInteger(sample.expectedRepCount) || sample.expectedRepCount < 0) throw new Error(`followAlong expectedRepCount 非法: ${sample.id}`);
    if (!Number.isInteger(sample.predictedRepCount) || sample.predictedRepCount < 0) throw new Error(`followAlong predictedRepCount 非法: ${sample.id}`);
    if (sample.qualityScore != null && (!Number.isInteger(sample.qualityScore) || sample.qualityScore < 0 || sample.qualityScore > 100)) throw new Error(`followAlong qualityScore 非法: ${sample.id}`);
    if (labeled && sample.algorithmVersion !== MODEL_REGISTRY.followAlong.algorithmVersion) throw new Error(`followAlong 样本算法版本不匹配: ${sample.id}`);
  }
  return { sampleCount: ids.size, evidenceLevel: input.kind === 'synthetic-boundary-regression' ? 'synthetic' : (input.evidenceLevel || 'human-labeled') };
}

function validateReleaseCorpus(input) {
  if (input.kind !== 'human-labeled-independent-validation' || input.evidenceLevel !== 'human-labeled') {
    throw new Error('发布门禁必须使用 human-labeled-independent-validation 独立标注集');
  }
  if (!String(input.datasetId || '').trim() || !String(input.annotatorProtocolVersion || '').trim()) {
    throw new Error('发布门禁要求 datasetId 与 annotatorProtocolVersion');
  }
  if (!Array.isArray(input.growth) || input.growth.length === 0) throw new Error('发布门禁要求 growth 独立验证样本');
  if (!Array.isArray(input.followAlong) || input.followAlong.length === 0) throw new Error('发布门禁要求 followAlong 独立验证样本');
  for (const sample of input.growth) if (sample.split !== 'validation') throw new Error(`发布门禁只接受 validation 样本: ${sample.id}`);
  if (input.growth.length < 20) throw new Error('发布门禁要求至少 20 条 growth 独立验证样本');
  for (const sample of input.followAlong) if (sample.split !== 'validation') throw new Error(`发布门禁只接受 validation 样本: ${sample.id}`);
  for (const sample of input.followAlong) if (sample.algorithmVersion !== MODEL_REGISTRY.followAlong.algorithmVersion) throw new Error(`followAlong 样本算法版本不匹配: ${sample.id}`);
  if (input.followAlong.length < 20) throw new Error('发布门禁要求至少 20 条 followAlong 独立验证样本');
  for (const sample of input.body) {
    for (const field of ['expectedBmi', 'expectedHeight', 'expectedPosture']) {
      if (sample[field] == null) throw new Error(`发布门禁要求 body 样本提供 ${field}: ${sample.id}`);
    }
  }
  const samples = [...input.movement, ...input.body, ...input.followAlong];
  const requiredBands = new Set(['72-96m', '97-132m', '133-180m', '181-216m']);
  const requiredFollowBands = new Set(['72-96m', '97-132m', '133-168m', '169-216m']);
  const requiredFollowCategories = new Set(['front_raise', 'lateral_raise', 'squat', 'lunge', 'jumping_jack', 'high_knee', 'sit_up', 'plank', 'burpee', 'squat_challenge', 'jump_rope']);
  const coveredBands = new Set();
  const bandCounts = { movement: new Map(), body: new Map(), followAlong: new Map() };
  const followCategoryCounts = new Map();
  const dimensionValues = { deviceModel: new Set(), cameraPosition: new Set(), lighting: new Set() };
  for (const sample of samples) {
    const metadata = sample.metadata && typeof sample.metadata === 'object' ? sample.metadata : {};
    if (sample.split !== 'validation') throw new Error(`发布门禁只接受 validation 样本: ${sample.id}`);
    const age = ageBand(sample.ageMonths ?? metadata.ageMonths);
    if (!requiredBands.has(age)) throw new Error(`发布门禁要求每条样本带 72–216 月龄: ${sample.id}`);
    coveredBands.add(age);
    const task = input.movement.includes(sample) ? 'movement' : input.body.includes(sample) ? 'body' : 'followAlong';
    const taskCounts = bandCounts[task];
    if (task !== 'followAlong') taskCounts.set(age, (taskCounts.get(age) || 0) + 1);
    if (task === 'followAlong') {
      const followBand = followAgeBand(sample.ageMonths ?? metadata.ageMonths);
      if (!requiredFollowBands.has(followBand)) throw new Error(`发布门禁要求跟做样本落在运行时年龄档位: ${sample.id}`);
      taskCounts.set(followBand, (taskCounts.get(followBand) || 0) + 1);
      followCategoryCounts.set(sample.category, (followCategoryCounts.get(sample.category) || 0) + 1);
    }
    for (const field of ['deviceModel', 'cameraPosition', 'lighting']) {
      const value = String(sample[field] ?? metadata[field] ?? '').trim();
      if (!value) throw new Error(`发布门禁缺少 ${field}: ${sample.id}`);
      dimensionValues[field].add(value);
    }
  }
  for (const band of requiredBands) if (!coveredBands.has(band)) throw new Error(`发布门禁缺少年龄分层: ${band}`);
  for (const task of ['movement', 'body']) {
    for (const band of requiredBands) if ((bandCounts[task].get(band) || 0) < 20) throw new Error(`发布门禁要求 ${task} 每个月龄层至少 20 条样本: ${band}`);
  }
  for (const band of requiredFollowBands) if ((bandCounts.followAlong.get(band) || 0) < 20) throw new Error(`发布门禁要求 followAlong 每个运行时年龄层至少 20 条样本: ${band}`);
  for (const category of requiredFollowCategories) if ((followCategoryCounts.get(category) || 0) < 2) throw new Error(`发布门禁要求跟做动作至少 2 条独立样本: ${category}`);
  for (const [field, values] of Object.entries(dimensionValues)) if (values.size < 2) throw new Error(`发布门禁要求至少两种 ${field} 条件`);
}

function ageBand(ageMonths) {
  const age = Number(ageMonths);
  if (!Number.isInteger(age)) return 'unknown';
  if (age >= 72 && age <= 96) return '72-96m';
  if (age >= 97 && age <= 132) return '97-132m';
  if (age >= 133 && age <= 180) return '133-180m';
  if (age >= 181 && age <= 216) return '181-216m';
  return 'out-of-scope';
}

function followAgeBand(ageMonths) {
  const age = Number(ageMonths);
  if (!Number.isInteger(age)) return 'unknown';
  if (age >= 72 && age <= 96) return '72-96m';
  if (age >= 97 && age <= 132) return '97-132m';
  if (age >= 133 && age <= 168) return '133-168m';
  if (age >= 169 && age <= 216) return '169-216m';
  return 'out-of-scope';
}

function stratumFor(sample, task = null) {
  const metadata = sample.metadata && typeof sample.metadata === 'object' ? sample.metadata : {};
  const age = task === 'followAlong'
    ? followAgeBand(sample.ageMonths ?? metadata.ageMonths)
    : ageBand(sample.ageMonths ?? metadata.ageMonths);
  const fields = [
    age,
    String(sample.gender ?? metadata.gender ?? 'unknown'),
    String(metadata.deviceModel ?? sample.deviceModel ?? 'unknown'),
    String(metadata.cameraPosition ?? sample.cameraPosition ?? 'unknown'),
    String(metadata.lighting ?? sample.lighting ?? 'unknown')
  ];
  return fields.join('|');
}

function confusionMetrics(rows) {
  const labels = [...new Set(rows.flatMap((row) => [row.expected, row.actual]))].sort();
  const confusion = {};
  for (const row of rows) {
    confusion[row.expected] ||= {};
    confusion[row.expected][row.actual] = (confusion[row.expected][row.actual] || 0) + 1;
  }
  const perLabel = Object.fromEntries(labels.map((label) => {
    const tp = rows.filter((row) => row.expected === label && row.actual === label).length;
    const fp = rows.filter((row) => row.expected !== label && row.actual === label).length;
    const fn = rows.filter((row) => row.expected === label && row.actual !== label).length;
    const support = tp + fn;
    const precision = tp + fp ? tp / (tp + fp) : 0;
    const recall = support ? tp / support : 0;
    const f1 = precision + recall ? (2 * precision * recall) / (precision + recall) : 0;
    return [label, { support, precision, recall, f1 }];
  }));
  const recalls = labels.map((label) => perLabel[label].recall);
  const f1s = labels.map((label) => perLabel[label].f1);
  return {
    confusion,
    perLabel,
    balancedAccuracy: recalls.length ? recalls.reduce((sum, value) => sum + value, 0) / recalls.length : 0,
    macroF1: f1s.length ? f1s.reduce((sum, value) => sum + value, 0) / f1s.length : 0
  };
}

function metricsByTask(rows) {
  return Object.fromEntries([...new Set(rows.map((row) => row.task))].sort().map((task) => {
    const subset = rows.filter((row) => row.task === task);
    const metrics = confusionMetrics(subset);
    return [task, {
      samples: subset.length,
      accuracy: subset.filter((row) => row.expected === row.actual).length / subset.length,
      balancedAccuracy: metrics.balancedAccuracy,
      macroF1: metrics.macroF1,
      perLabel: metrics.perLabel
    }];
  }));
}

function stratifiedMetrics(rows) {
  return Object.fromEntries([...new Set(rows.map((row) => row.stratum))].sort().map((stratum) => {
    const subset = rows.filter((row) => row.stratum === stratum);
    const subsetMetrics = confusionMetrics(subset);
    return [stratum, {
      samples: subset.length,
      accuracy: subset.filter((row) => row.expected === row.actual).length / subset.length,
      balancedAccuracy: subsetMetrics.balancedAccuracy,
      macroF1: subsetMetrics.macroF1,
      perLabel: subsetMetrics.perLabel
    }];
  }));
}

function validateFollowAlongAsset(input) {
  const ageBands = (input?.ageProfiles || []).map((profile) => [Number(profile.minAgeMonths), Number(profile.maxAgeMonths)]);
  const expectedBands = [[72, 96], [97, 132], [133, 168], [169, 216]];
  if (JSON.stringify(ageBands) !== JSON.stringify(expectedBands)) throw new Error(`跟做年龄段漂移: ${JSON.stringify(ageBands)}`);
  const ageProfiles = Array.isArray(input?.ageProfiles) ? input.ageProfiles : [];
  if (ageProfiles.length !== expectedBands.length) throw new Error('跟做年龄配置数量不完整');
  ageProfiles.forEach((profile, index) => {
    for (const key of ['minAgeMonths', 'maxAgeMonths', 'calibrationFrames', 'minRepIntervalMs', 'dynamicGateFloor', 'dynamicGateCeiling', 'confidenceWindowFrames']) {
      if (!Number.isFinite(Number(profile[key]))) throw new Error(`跟做年龄阈值非法: ageProfiles[${index}].${key}`);
    }
    if (Number(profile.minAgeMonths) > Number(profile.maxAgeMonths) || Number(profile.dynamicGateFloor) <= 0 || Number(profile.dynamicGateFloor) >= Number(profile.dynamicGateCeiling)) {
      throw new Error(`跟做年龄动态门限非法: ageProfiles[${index}]`);
    }
  });
  const categories = ['front_raise', 'lateral_raise', 'squat', 'lunge', 'jumping_jack', 'high_knee', 'sit_up', 'plank', 'burpee', 'squat_challenge', 'jump_rope'];
  const profiles = Array.isArray(input?.actionProfiles) ? input.actionProfiles : [];
  const keys = new Set();
  for (const category of categories) {
    const rows = profiles.filter((profile) => profile.category === category);
    if (rows.length !== expectedBands.length) throw new Error(`跟做动作配置不完整: ${category}`);
    for (const row of rows) {
      const key = `${row.category}:${row.minAgeMonths}:${row.maxAgeMonths}`;
      if (keys.has(key)) throw new Error(`跟做动作配置重复: ${key}`);
      keys.add(key);
      for (const key of ['minSignalRange', 'minRepIntervalMs', 'highGateRatio', 'lowGateRatio', 'topHoldFrames', 'returnHoldFrames', 'maxRepIntervalMs', 'minDropRatio', 'minDropAbsolute', 'returnSlopeMinRatio', 'returnConfidenceFloor', 'requiredSignalHistoryFrames', 'historyLen']) {
        if (!finite(row[key]) || Number(row[key]) < 0) throw new Error(`跟做阈值非法: ${category}.${key}`);
      }
      if (Number(row.requiredSignalHistoryFrames) > Number(row.historyLen) || Number(row.maxRepIntervalMs) < Number(row.minRepIntervalMs) || Number(row.lowGateRatio) > Number(row.highGateRatio) || Number(row.highGateRatio) > 0.5 || Number(row.returnConfidenceFloor) > 1 || Number(row.returnSlopeMinRatio) <= 0 || Number(row.minDropRatio) > 1.2) {
        throw new Error(`跟做动态门限关系非法: ${category}`);
      }
    }
  }
  if (keys.size !== expectedBands.length * categories.length) throw new Error('跟做动作配置存在未知或缺失年龄段');
  return { ageBands: ageBands.length, actionProfiles: profiles.length, categories: categories.length, sourceVersion: input?.meta?.version || null };
}
function validateBodyCaptureAsset(input) {
  const bands = Array.isArray(input?.ageProfiles) ? input.ageProfiles : [];
  const expectedBands = [[72, 96], [97, 132], [133, 180], [181, 216]];
  const actualBands = bands.map((row) => [Number(row.minAgeMonths), Number(row.maxAgeMonths)]);
  if (JSON.stringify(actualBands) !== JSON.stringify(expectedBands)) throw new Error(`姿态采集年龄段漂移: ${JSON.stringify(actualBands)}`);
  if (bands.length !== expectedBands.length || typeof input?.version !== 'string' || !input.version.trim()) throw new Error('姿态采集配置版本或年龄配置不完整');
  const required = ['staticHoldMilliseconds', 'staticMinimumFrames', 'staticMaximumDisplacementRatio', 'gaitMinimumMilliseconds', 'gaitMinimumDisplacementRatio', 'minimumIndividualLandmarkConfidence', 'minimumMeanLandmarkConfidence'];
  for (const row of bands) for (const key of required) if (!finite(row[key]) || Number(row[key]) < 0) throw new Error(`姿态采集阈值非法: ${row.tag}.${key}`);
  return { ageBands: bands.length, sourceVersion: input.version };
}
const followAlongValidation = validateFollowAlongAsset(followAsset);
if (followAlongValidation.sourceVersion !== MODEL_REGISTRY.followAlong.sourceVersion) throw new Error('跟做模型注册表 sourceVersion 与运行时资产不一致');
const bodyCaptureValidation = validateBodyCaptureAsset(bodyCaptureAsset);
if (bodyCaptureValidation.sourceVersion !== MODEL_REGISTRY.posture.sourceVersion) throw new Error('姿态采集模型注册表 sourceVersion 与运行时资产不一致');

const validated = validateCorpus(corpus);
if (releaseGate) {
  if (!requireLabeled) throw new Error('发布门禁必须同时启用 --require-labeled');
  validateReleaseCorpus(corpus);
}
if (requireLabeled && validated.evidenceLevel !== 'human-labeled') {
  console.error('模型评估被阻止：当前语料不是 human-labeled 独立验证集。');
  process.exit(2);
}

const results = [];
for (const sample of corpus.movement) {
  const rows = Array.isArray(sample.rows)
    ? sample.rows
    : MOVEMENT_ITEM_CODES.map((item, index) => ({ item, score: sample.scores[index], confidence: sample.confidence, reviewStatus: 'passed' }));
  const evaluation = evaluateMovementScores(rows);
  results.push({ id: sample.id, task: 'movement', expected: sample.expected, actual: evaluation.riskLevel, score: evaluation.totalScore, confidence: evaluation.meanConfidence, stratum: stratumFor(sample) });
}
for (const sample of corpus.body) {
  const report = scoreBodyAssessment({ ...sample, snapshots: sample.snapshots || snapshotsFor(sample.posture) });
  results.push({ id: sample.id, task: 'body', expected: sample.expected, actual: report.overallLevel, score: report.postureReport.riskScore, confidence: report.postureReport.qualityScore / 100, stratum: stratumFor(sample) });
  if (sample.expectedBmi != null) results.push({ id: `${sample.id}:bmi`, task: 'bmi', expected: sample.expectedBmi, actual: report.bmiLevel, score: report.bmi, confidence: 1, stratum: stratumFor(sample) });
  if (sample.expectedHeight != null) results.push({ id: `${sample.id}:height`, task: 'height', expected: sample.expectedHeight, actual: report.heightReport?.level ?? 'unavailable', score: report.heightReport?.heightCm ?? 0, confidence: report.heightReport ? 1 : 0, stratum: stratumFor(sample) });
  if (sample.expectedPosture != null) results.push({ id: `${sample.id}:posture`, task: 'posture', expected: sample.expectedPosture, actual: report.postureReport.overallLevel, score: report.postureReport.riskScore, confidence: report.postureReport.qualityScore / 100, stratum: stratumFor(sample) });
}
for (const sample of corpus.growth || []) {
  const report = scoreGrowth({ period: sample.period, checkInDates: sample.checkInDates, planDates: sample.planDates, assessmentCount: sample.assessmentCount, bodyAttention: sample.bodyAttention, totalScore: sample.totalScore, now: sample.now ? new Date(sample.now) : new Date() });
  results.push({ id: `${sample.id}:plan`, task: 'growth', expected: sample.expectedPlanTitle, actual: report.planTitle, score: report.consistencyPercent, confidence: 1, stratum: stratumFor(sample) });
  if (report.activeDays !== sample.expectedActiveDays || report.consistencyPercent !== sample.expectedConsistencyPercent) {
    results.push({ id: `${sample.id}:metrics`, task: 'growth-metrics', expected: `${sample.expectedActiveDays}/${sample.expectedConsistencyPercent}`, actual: `${report.activeDays}/${report.consistencyPercent}`, score: report.consistencyPercent, confidence: 1, stratum: stratumFor(sample) });
  }
}
for (const sample of corpus.followAlong || []) {
  const absoluteError = Math.abs(sample.predictedRepCount - sample.expectedRepCount);
  results.push({
    id: sample.id,
    task: 'followAlong',
    expected: sample.expectedRepCount,
    actual: sample.predictedRepCount,
    score: sample.qualityScore ?? 0,
    confidence: (sample.qualityScore ?? 0) / 100,
    absoluteError,
    stratum: stratumFor(sample, 'followAlong')
  });
}
const correct = results.filter((row) => row.expected === row.actual).length;
const accuracy = results.length ? correct / results.length : 0;
const metrics = confusionMetrics(results);
const taskMetrics = metricsByTask(results);
const stratified = stratifiedMetrics(results);
const taskStrata = Object.fromEntries(Object.keys(taskMetrics).sort().map((task) => [task, stratifiedMetrics(results.filter((row) => row.task === task))]));
const followAlongRows = results.filter((row) => row.task === 'followAlong');
const followAlongMae = followAlongRows.length
  ? followAlongRows.reduce((sum, row) => sum + row.absoluteError, 0) / followAlongRows.length
  : null;
const report = {
  corpus: corpus.kind,
  evidenceLevel: validated.evidenceLevel,
  version: corpus.version,
  movementAlgorithmVersion: MOVEMENT_ALGORITHM_VERSION,
  calibrationVersion: MODEL_CALIBRATION_VERSION,
  calibrationStatus: MODEL_CALIBRATION_STATUS,
  modelRegistryVersion: MODEL_REGISTRY_VERSION,
  followAlong: { ...followAlongValidation, algorithmVersion: MODEL_REGISTRY.followAlong.algorithmVersion, sourceVersion: MODEL_REGISTRY.followAlong.sourceVersion, calibrationVersion: MODEL_REGISTRY.followAlong.calibrationVersion },
  followAlongMetrics: { samples: followAlongRows.length, exactAccuracy: followAlongRows.length ? followAlongRows.filter((row) => row.absoluteError === 0).length / followAlongRows.length : null, meanAbsoluteError: followAlongMae },
  bodyCapture: { ...bodyCaptureValidation, algorithmVersion: MODEL_REGISTRY.posture.algorithmVersion, sourceVersion: MODEL_REGISTRY.posture.sourceVersion, calibrationVersion: MODEL_REGISTRY.posture.calibrationVersion },
  samples: results.length,
  correct,
  accuracy,
  balancedAccuracy: metrics.balancedAccuracy,
  macroF1: metrics.macroF1,
  taskMetrics,
  confusion: metrics.confusion,
  perLabel: metrics.perLabel,
  strata: stratified,
  taskStrata
};
const serializedReport = JSON.stringify(report, null, 2) + '\n';
if (outputPath) fs.writeFileSync(outputPath, serializedReport, 'utf8');
console.log(serializedReport.trimEnd());
if (releaseGate) {
  const minimumMetric = 0.95;
  const requiredTasks = ['movement', 'body', 'bmi', 'height', 'posture', 'growth', 'followAlong'];
  const missingTasks = requiredTasks.filter((task) => !taskMetrics[task]);
  const followAlongErrors = results.filter((row) => row.task === 'followAlong').map((row) => row.absoluteError);
  const followAlongMae = followAlongErrors.length ? followAlongErrors.reduce((sum, value) => sum + value, 0) / followAlongErrors.length : Infinity;
  const weakTasks = Object.entries(taskMetrics).filter(([, value]) => value.samples < 20 || value.accuracy < minimumMetric || value.balancedAccuracy < minimumMetric || value.macroF1 < minimumMetric);
  if (followAlongMae > 0.5) weakTasks.push(['followAlong', { samples: followAlongErrors.length, meanAbsoluteError: followAlongMae }]);
  const weakStrata = Object.entries(taskStrata).flatMap(([task, strata]) => Object.entries(strata).filter(([, value]) => value.samples > 0 && (value.accuracy < minimumMetric || value.balancedAccuracy < minimumMetric || value.macroF1 < minimumMetric)).map(([stratum, value]) => ({ task, stratum, ...value })));
  if (missingTasks.length || weakTasks.length || weakStrata.length || accuracy < minimumMetric || metrics.balancedAccuracy < minimumMetric || metrics.macroF1 < minimumMetric) {
    console.error(JSON.stringify({ releaseGate: 'failed', minimumMetric, followAlongMae, accuracy, balancedAccuracy: metrics.balancedAccuracy, macroF1: metrics.macroF1, missingTasks, weakTasks, weakStrata }, null, 2));
    process.exitCode = 1;
  } else {
    console.error(JSON.stringify({ releaseGate: 'passed', minimumMetric, followAlongMae }, null, 2));
  }
}
if (correct !== results.length) {
  console.error(results.filter((row) => row.expected !== row.actual));
  process.exitCode = 1;
}
