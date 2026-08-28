#!/usr/bin/env node
/**
 * Offline repeatability gate for app posture capture and follow-along counts.
 *
 * Input contains structured measurements only, never child images or video.
 * Every subject/action group must contain at least ten runs made with the same
 * frozen algorithm, device and camera position. These are engineering release
 * limits, not clinical diagnostic cut-offs.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const REPEATABILITY_POLICY_VERSION = 'UY-REPEATABILITY-GATE-1.1';
export const MINIMUM_RUNS = 10;
export const MINIMUM_CAPTURE_SUCCESS_RATE = 0.90;
export const POSTURE_RANGE_LIMITS = Object.freeze({
  shoulderHeightDifferenceCm: 0.8,
  pelvicHeightDifferenceCm: 0.8,
  spinalMidlineDeviationCm: 0.8,
  cameraProxyRibProminenceCm: 0.8,
  gaitShoulderSwingDifferenceCm: 0.8,
  gaitPelvicSwingDifferenceCm: 0.8,
  gaitTrunkSwayCm: 0.8,
  headTiltDegrees: 3.0,
  thoracicRoundingDegrees: 3.0,
  forwardHeadAngleDegrees: 3.0,
  cameraProxyAtrDegrees: 3.0
});
export const FOLLOW_ALONG_MAX_MAE = 0.5;
export const FOLLOW_ALONG_MINIMUM_EXACT_RATE = 0.90;
export const FOLLOW_ALONG_MAX_SINGLE_ERROR = 2;
export const GUIDED_CAPTURE_PROTOCOL_PREFIX = 'UY-CAPTURE-GUIDED-';
export const MARKER_PNP_CAPTURE_PROTOCOL_PREFIX = 'UY-CAPTURE-MARKER-PNP-';
export const REQUIRED_GUIDED_QUALITY_CHECKS = Object.freeze([
  'device-level', 'full-body', 'single-person', 'landmark-confidence', 'multi-frame-robust'
]);
export const MAXIMUM_MARKER_REPROJECTION_ERROR_PX = 2;

const finite = (value) => Number.isFinite(Number(value));
const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  if (!sorted.length) return null;
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
};
const stats = (values) => {
  const numeric = values.map(Number).filter(Number.isFinite);
  if (!numeric.length) return { count: 0, min: null, max: null, range: null, median: null, mad: null };
  const center = median(numeric);
  return {
    count: numeric.length,
    min: Math.min(...numeric),
    max: Math.max(...numeric),
    range: Math.max(...numeric) - Math.min(...numeric),
    median: center,
    mad: median(numeric.map((value) => Math.abs(value - center)))
  };
};

function validateGroupIdentity(group, label) {
  for (const field of ['subjectId', 'algorithmVersion', 'deviceModel', 'cameraPosition']) {
    if (!String(group?.[field] ?? '').trim()) throw new Error(`${label} 缺少 ${field}`);
  }
  if (!Array.isArray(group.runs) || group.runs.length < MINIMUM_RUNS) throw new Error(`${label} 至少需要同条件连续 ${MINIMUM_RUNS} 次记录`);
  const ids = new Set();
  for (const run of group.runs) {
    if (!String(run?.runId ?? '').trim() || ids.has(run.runId)) throw new Error(`${label} runId 缺失或重复`);
    ids.add(run.runId);
  }
}

function nonEmpty(value) { return String(value ?? '').trim(); }

function validatePostureCaptureTrace(group, label, { releaseGate, failures }) {
  if (group.cameraPosition !== 'rear') throw new Error(`${label} 姿态重复性验证必须使用后置镜头`);
  if (!nonEmpty(group.captureProtocolVersion)) throw new Error(`${label} 缺少 captureProtocolVersion`);
  if (!nonEmpty(group.cameraLensId) || !nonEmpty(group.resolution)) throw new Error(`${label} 缺少 cameraLensId 或 resolution`);
  if (!['guided', 'marker-pnp'].includes(group.calibrationMode)) throw new Error(`${label} calibrationMode 必须为 guided 或 marker-pnp`);
  const setupIds = new Set();
  for (const run of group.runs) {
    if (!nonEmpty(run.setupId) || setupIds.has(run.setupId)) throw new Error(`${label} 每次记录必须有唯一 setupId（每次离开标定区后重新入镜）`);
    setupIds.add(run.setupId);
    if (!Number.isFinite(Date.parse(run.capturedAt))) throw new Error(`${label} 每次记录必须有合法 capturedAt`);
    if (run.cameraFacing !== 'rear-1x') throw new Error(`${label} 必须使用 rear-1x，不接受前摄、超广角或变焦`);
    if (run.captureProtocolVersion !== group.captureProtocolVersion) throw new Error(`${label} run.captureProtocolVersion 与分组版本不一致`);
    if (run.complete === true) {
      const checks = Array.isArray(run.qualityChecks) ? run.qualityChecks : [];
      if (!REQUIRED_GUIDED_QUALITY_CHECKS.every((check) => checks.includes(check))) {
        failures.push(`${label}.${run.runId} 未通过完整引导质量门`);
      }
    }
  }
  const usesMarkerPnp = group.captureProtocolVersion.startsWith(MARKER_PNP_CAPTURE_PROTOCOL_PREFIX);
  const usesGuided = group.captureProtocolVersion.startsWith(GUIDED_CAPTURE_PROTOCOL_PREFIX);
  if (!usesMarkerPnp && !usesGuided) throw new Error(`${label} 不支持的 captureProtocolVersion`);
  if (group.calibrationMode === 'marker-pnp' && !usesMarkerPnp) throw new Error(`${label} marker-pnp 必须使用 UY-CAPTURE-MARKER-PNP 协议`);
  if (group.calibrationMode === 'guided' && !usesGuided) throw new Error(`${label} guided 必须使用 UY-CAPTURE-GUIDED 协议`);
  if (group.calibrationMode === 'marker-pnp') {
    for (const run of group.runs.filter((candidate) => candidate.complete === true)) {
      const calibration = run.calibration;
      if (!calibration?.boardDetected || !nonEmpty(calibration.boardId) || !nonEmpty(calibration.intrinsicsId)
        || !Number.isFinite(Number(calibration.reprojectionErrorPx)) || Number(calibration.reprojectionErrorPx) > MAXIMUM_MARKER_REPROJECTION_ERROR_PX) {
        failures.push(`${label}.${run.runId} 标定板/PnP 证据不完整或重投影误差超过 ${MAXIMUM_MARKER_REPROJECTION_ERROR_PX}px`);
      }
    }
  }
}

export function evaluateRepeatability(input, { releaseGate = false } = {}) {
  if (!input || typeof input !== 'object') throw new Error('重复性数据必须是 JSON 对象');
  if (input.policyVersion !== REPEATABILITY_POLICY_VERSION) throw new Error(`policyVersion 必须为 ${REPEATABILITY_POLICY_VERSION}`);
  const postureGroups = Array.isArray(input.postureGroups) ? input.postureGroups : [];
  const followAlongGroups = Array.isArray(input.followAlongGroups) ? input.followAlongGroups : [];
  if (!postureGroups.length || !followAlongGroups.length) throw new Error('必须同时提供姿态采集和跟练重复性分组');

  const failures = [];
  const posture = postureGroups.map((group, index) => {
    const label = `postureGroups[${index}]`;
    validateGroupIdentity(group, label);
    validatePostureCaptureTrace(group, label, { releaseGate, failures });
    const completed = group.runs.filter((run) => run.complete === true);
    const successRate = completed.length / group.runs.length;
    if (successRate < MINIMUM_CAPTURE_SUCCESS_RATE) failures.push(`${label} 采集成功率 ${(successRate * 100).toFixed(1)}% < 90%`);
    const metrics = {};
    for (const [metric, limit] of Object.entries(POSTURE_RANGE_LIMITS)) {
      const values = completed.map((run) => run.metrics?.[metric]).filter(finite);
      if (!values.length) continue;
      const summary = stats(values);
      metrics[metric] = { ...summary, limit, passed: summary.count >= MINIMUM_RUNS * MINIMUM_CAPTURE_SUCCESS_RATE && summary.range <= limit };
      if (!metrics[metric].passed) failures.push(`${label}.${metric} 有效次数或极差未达标（${summary.count} 次，极差 ${summary.range?.toFixed(3)}，上限 ${limit}）`);
    }
    if (!Object.keys(metrics).length) failures.push(`${label} 没有可评估的结构化姿态指标`);
    const stable = successRate >= MINIMUM_CAPTURE_SUCCESS_RATE
      && Object.values(metrics).length > 0
      && Object.values(metrics).every((metric) => metric.passed);
    return {
      subjectId: group.subjectId,
      runs: group.runs.length,
      successRate,
      captureProtocolVersion: group.captureProtocolVersion,
      calibrationMode: group.calibrationMode,
      formalMeasurementEligible: group.calibrationMode === 'marker-pnp',
      screeningRepeatabilityEligible: stable,
      metrics
    };
  });

  const followAlong = followAlongGroups.map((group, index) => {
    const label = `followAlongGroups[${index}]`;
    validateGroupIdentity(group, label);
    if (!String(group.category ?? '').trim() || !Number.isInteger(group.expectedRepCount) || group.expectedRepCount < 0) throw new Error(`${label} 缺少动作类型或人工标注次数`);
    const errors = group.runs.map((run) => {
      if (!Number.isInteger(run.predictedRepCount) || run.predictedRepCount < 0) throw new Error(`${label} predictedRepCount 非法`);
      return Math.abs(run.predictedRepCount - group.expectedRepCount);
    });
    const meanAbsoluteError = errors.reduce((sum, value) => sum + value, 0) / errors.length;
    const exactRate = errors.filter((value) => value === 0).length / errors.length;
    const maximumError = Math.max(...errors);
    const passed = meanAbsoluteError <= FOLLOW_ALONG_MAX_MAE && exactRate >= FOLLOW_ALONG_MINIMUM_EXACT_RATE && maximumError <= FOLLOW_ALONG_MAX_SINGLE_ERROR;
    if (!passed) failures.push(`${label} 计数重复性未达标（MAE ${meanAbsoluteError.toFixed(3)}，完全一致率 ${(exactRate * 100).toFixed(1)}%，最大误差 ${maximumError}）`);
    return { subjectId: group.subjectId, category: group.category, runs: errors.length, meanAbsoluteError, exactRate, maximumError, passed };
  });

  if (releaseGate) {
    const subjects = new Set([...postureGroups, ...followAlongGroups].map((group) => group.subjectId));
    const devices = new Set([...postureGroups, ...followAlongGroups].map((group) => group.deviceModel));
    if (subjects.size < 20) failures.push(`正式发布门禁至少需要 20 名独立儿童完成 10 次重复测试，当前 ${subjects.size} 名`);
    if (devices.size < 2) failures.push(`正式发布门禁至少需要 2 种设备，当前 ${devices.size} 种`);
  }

  return {
    policyVersion: REPEATABILITY_POLICY_VERSION,
    status: failures.length ? 'failed' : 'passed',
    disclaimer: '重复性通过只说明同条件输出稳定，不代表健康结论正确，也不能替代独立儿童人工标注和专业复核。引导式家庭采集可用于经验证的筛查分类，但不得声称物理厘米、ATR 或 Cobb 角；只有物理几何测量资格需要标定板、镜头内参与 PnP 证据。',
    posture,
    followAlong,
    failures
  };
}

function main() {
  const args = process.argv.slice(2);
  const inputIndex = args.indexOf('--input');
  const outputIndex = args.indexOf('--output');
  const inputPath = inputIndex >= 0 ? args[inputIndex + 1] : process.env.REPEATABILITY_CORPUS_PATH;
  if (!inputPath) throw new Error('请通过 --input 或 REPEATABILITY_CORPUS_PATH 提供重复性 JSON');
  const report = evaluateRepeatability(JSON.parse(fs.readFileSync(path.resolve(inputPath), 'utf8')), { releaseGate: args.includes('--release-gate') });
  const serialized = JSON.stringify(report, null, 2) + '\n';
  if (outputIndex >= 0 && args[outputIndex + 1]) fs.writeFileSync(path.resolve(args[outputIndex + 1]), serialized, 'utf8');
  process.stdout.write(serialized);
  if (report.status !== 'passed') process.exitCode = 1;
}

if (import.meta.url === pathToFileURL(process.argv[1] || fileURLToPath(import.meta.url)).href) main();
