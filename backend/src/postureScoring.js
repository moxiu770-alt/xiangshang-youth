/**
 * Canonical posture-screening scorer used by the API.
 *
 * This is intentionally a screening/quality model, not a scoliosis
 * diagnosis. Native clients can preview the same report, but the server is
 * the authority for the persisted level and score so a forged client level
 * cannot be published.
 */
import { MODEL_CALIBRATION_VERSION } from './modelCalibration.js';

export const POSTURE_ALGORITHM_VERSION = 'UY-IMCA-CV-1.3';
export const POSTURE_RULES_SOURCE_VERSION = 'UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20';
export const POSTURE_CAPTURE_TASKS = Object.freeze(['standingBack', 'forwardBend', 'seatedPosture', 'gaitVideo']);
export const POSTURE_SCREENING_RULES = Object.freeze({
  minimumSamples: 10,
  minimumConfidence: 0.56,
  scoringWeightTotal: 1.10
});

const profiles = Object.freeze([
  {
    minMonths: 72, maxMonths: 96,
    shoulderAttention: 1.05, shoulderReferral: 1.70,
    pelvisAttention: 0.55, pelvisReferral: 1.05,
    headTiltAttention: 3, headTiltReferral: 6,
    seatedMidlineAttention: 1.35, seatedRoundingAttention: 25,
    forwardHeadAttention: 12.5, forwardHeadReferral: 16.5,
    gaitAttention: 1.05, proxyAtrAttention: 5.2, proxyAtrReferral: 7.2,
    ribProminenceEquivocalCentimeters: .85, ribProminencePositiveCentimeters: 1.25,
    weightedShoulder: .20, weightedPelvis: .14, weightedSpinalMidline: .11,
    weightedThoracicRounding: .11, weightedForwardHead: .13,
    weightedAdams: .17, weightedGait: .24, yellowScore: 42, redScore: 63
  },
  {
    minMonths: 97, maxMonths: 132,
    shoulderAttention: 1.0, shoulderReferral: 1.6,
    pelvisAttention: .5, pelvisReferral: 1.0,
    headTiltAttention: 3, headTiltReferral: 6,
    seatedMidlineAttention: 1.3, seatedRoundingAttention: 24,
    forwardHeadAttention: 12, forwardHeadReferral: 16,
    gaitAttention: 1.0, proxyAtrAttention: 5, proxyAtrReferral: 7,
    ribProminenceEquivocalCentimeters: .8, ribProminencePositiveCentimeters: 1.2,
    weightedShoulder: .20, weightedPelvis: .13, weightedSpinalMidline: .12,
    weightedThoracicRounding: .10, weightedForwardHead: .14,
    weightedAdams: .18, weightedGait: .23, yellowScore: 40, redScore: 61
  },
  {
    minMonths: 133, maxMonths: 180,
    shoulderAttention: .95, shoulderReferral: 1.55,
    pelvisAttention: .5, pelvisReferral: .98,
    headTiltAttention: 3, headTiltReferral: 6,
    seatedMidlineAttention: 1.25, seatedRoundingAttention: 23,
    forwardHeadAttention: 11.5, forwardHeadReferral: 15.5,
    gaitAttention: .95, proxyAtrAttention: 4.8, proxyAtrReferral: 6.8,
    ribProminenceEquivocalCentimeters: .78, ribProminencePositiveCentimeters: 1.15,
    weightedShoulder: .18, weightedPelvis: .13, weightedSpinalMidline: .12,
    weightedThoracicRounding: .10, weightedForwardHead: .15,
    weightedAdams: .19, weightedGait: .23, yellowScore: 38, redScore: 59
  },
  {
    minMonths: 181, maxMonths: 216,
    shoulderAttention: .92, shoulderReferral: 1.52,
    pelvisAttention: .48, pelvisReferral: .95,
    headTiltAttention: 3, headTiltReferral: 6,
    seatedMidlineAttention: 1.2, seatedRoundingAttention: 23,
    forwardHeadAttention: 11.2, forwardHeadReferral: 15,
    gaitAttention: .92, proxyAtrAttention: 4.7, proxyAtrReferral: 6.6,
    ribProminenceEquivocalCentimeters: .76, ribProminencePositiveCentimeters: 1.12,
    weightedShoulder: .17, weightedPelvis: .12, weightedSpinalMidline: .12,
    weightedThoracicRounding: .10, weightedForwardHead: .15,
    weightedAdams: .20, weightedGait: .24, yellowScore: 37, redScore: 57
  }
]);

const finite = (value) => {
  // Do not let JSON arrays/objects/functions coerce to numeric zero. Those
  // values are malformed landmark evidence and must fail closed.
  if (value == null || typeof value === 'boolean' || typeof value === 'object' || typeof value === 'function' || (typeof value === 'string' && value.trim() === '')) return null;
  return Number.isFinite(Number(value)) ? Number(value) : null;
};
const POSTURE_METRIC_LIMITS = Object.freeze({
  shoulderHeightDifferenceCm: 20,
  pelvicHeightDifferenceCm: 20,
  headTiltDegrees: 180,
  spinalMidlineDeviationCm: 20,
  thoracicRoundingDegrees: 180,
  forwardHeadAngleDegrees: 180,
  instrumentAtrDegrees: 180,
  thoracicAtrDegrees: 180,
  lumbarAtrDegrees: 180,
  cameraProxyAtrDegrees: 180,
  cameraProxyRibProminenceCm: 20,
  occiputWallDistanceCm: 50,
  gaitShoulderSwingDifferenceCm: 20,
  gaitPelvicSwingDifferenceCm: 20,
  gaitTrunkSwayCm: 20
});
function metricIsValid(value, limit) {
  const number = finite(value);
  return value == null || (number != null && Math.abs(number) <= limit);
}
const TASK_EVIDENCE_KEYS = Object.freeze({
  standingBack: Object.freeze(['shoulderHeightDifferenceCm', 'pelvicHeightDifferenceCm', 'headTiltDegrees']),
  forwardBend: Object.freeze(['spinalMidlineDeviationCm', 'thoracicRoundingDegrees', 'forwardHeadAngleDegrees', 'cameraProxyAtrDegrees', 'cameraProxyRibProminenceCm', 'instrumentAtrDegrees', 'thoracicAtrDegrees', 'lumbarAtrDegrees']),
  seatedPosture: Object.freeze(['shoulderHeightDifferenceCm', 'spinalMidlineDeviationCm', 'thoracicRoundingDegrees', 'forwardHeadAngleDegrees', 'occiputWallDistanceCm']),
  gaitVideo: Object.freeze(['gaitShoulderSwingDifferenceCm', 'gaitPelvicSwingDifferenceCm', 'gaitTrunkSwayCm'])
});
function snapshotHasMetricEvidence(snapshot) {
  const metrics = snapshot?.metrics;
  if (!metrics || typeof metrics !== 'object' || Array.isArray(metrics)) return false;
  const keys = TASK_EVIDENCE_KEYS[snapshot?.captureTask] || Object.keys(POSTURE_METRIC_LIMITS);
  const numericEvidence = keys.some((key) => finite(metrics[key]) != null);
  const adamsEvidence = ['adamsResult', 'adams'].some((key) => {
    const value = String(metrics[key] ?? '').trim().toLowerCase();
    return ['positive', 'equivocal', 'negative', '阳性', '可疑', '阴性', '阳', '临界'].some((token) => value.includes(token));
  });
  return numericEvidence || adamsEvidence;
}
function snapshotMetricsAreValid(snapshot) {
  if (!snapshot || !Number.isInteger(snapshot.sampleCount) || snapshot.sampleCount < 0) return false;
  const metrics = metricsFor(snapshot);
  return Object.entries(POSTURE_METRIC_LIMITS).every(([key, limit]) => metricIsValid(metrics[key], limit));
}
const magnitude = (value) => {
  const number = finite(value);
  return number == null ? 0 : Math.abs(number);
};
const clamp01 = (value) => Math.min(1, Math.max(0, value));
const norm = (value, attention, referral) => {
  if (!Number.isFinite(value) || !Number.isFinite(attention) || !Number.isFinite(referral) || referral <= attention) return 0;
  if (value <= attention) return 0;
  if (value >= referral) return 1;
  return clamp01((value - attention) / (referral - attention));
};

export function postureProfileForAge(ageMonths) {
  const age = Number.isInteger(ageMonths) ? ageMonths : null;
  if (age != null) {
    const match = profiles.find((profile) => age >= profile.minMonths && age <= profile.maxMonths);
    if (match) return match;
    // Native clients clamp out-of-scope ages to the nearest published
    // profile. Keep this deterministic rather than silently falling back to
    // the middle age band on the server.
    if (age < profiles[0].minMonths) return profiles[0];
    if (age > profiles[profiles.length - 1].maxMonths) return profiles[profiles.length - 1];
  }
  return profiles[1];
}

function evidence(snapshot) {
  if (!snapshot || snapshot.sampleCount < POSTURE_SCREENING_RULES.minimumSamples) return 0;
  if (!Number.isFinite(snapshot.confidence) || snapshot.confidence < POSTURE_SCREENING_RULES.minimumConfidence || snapshot.confidence > 1) return 0;
  const sampleFactor = clamp01((snapshot.sampleCount - POSTURE_SCREENING_RULES.minimumSamples) / POSTURE_SCREENING_RULES.minimumSamples);
  const confidenceFactor = clamp01((snapshot.confidence - POSTURE_SCREENING_RULES.minimumConfidence) / .44);
  return .55 * confidenceFactor + .45 * sampleFactor;
}

function adamsValue(snapshot, profile) {
  const ribProminence = finite(snapshot?.metrics?.cameraProxyRibProminenceCm);
  if (ribProminence != null && profile) {
    const value = Math.abs(ribProminence);
    if (value >= profile.ribProminencePositiveCentimeters) return 1;
    if (value >= profile.ribProminenceEquivocalCentimeters) return .48;
    return 0;
  }
  const value = String(snapshot?.metrics?.adamsResult ?? snapshot?.metrics?.adams ?? '').toLowerCase();
  if (value.includes('positive') || value.includes('阳性') || value.includes('阳')) return 1;
  if (value.includes('equivocal') || value.includes('可疑') || value.includes('临界')) return .48;
  return 0;
}

function metricsFor(snapshot) {
  return snapshot?.metrics && typeof snapshot.metrics === 'object' ? snapshot.metrics : {};
}

/**
 * Score the four normalized snapshots. The return object is safe to persist
 * and contains only finite, bounded values.
 */
export function scorePostureSnapshots(rawSnapshots, ageMonths = null) {
  const byTask = new Map();
  for (const raw of Array.isArray(rawSnapshots) ? rawSnapshots : []) {
    if (!POSTURE_CAPTURE_TASKS.includes(raw?.captureTask)) continue;
    const metrics = metricsFor(raw);
    byTask.set(raw.captureTask, {
      captureTask: raw.captureTask,
      sampleCount: Number.isInteger(raw.sampleCount) ? raw.sampleCount : 0,
      confidence: finite(raw.confidence) ?? 0,
      metrics
    });
  }
  const standing = byTask.get('standingBack');
  const forward = byTask.get('forwardBend');
  const seated = byTask.get('seatedPosture');
  const gait = byTask.get('gaitVideo');
  const profile = postureProfileForAge(ageMonths);
  const standingMetrics = metricsFor(standing);
  const forwardMetrics = metricsFor(forward);
  const seatedMetrics = metricsFor(seated);
  const gaitMetrics = metricsFor(gait);
  const metricsValid = [standing, forward, seated, gait].every(snapshotMetricsAreValid);

  const shoulder = Math.max(magnitude(standingMetrics.shoulderHeightDifferenceCm), magnitude(seatedMetrics.shoulderHeightDifferenceCm));
  const pelvis = magnitude(standingMetrics.pelvicHeightDifferenceCm);
  const trunk = magnitude(seatedMetrics.spinalMidlineDeviationCm);
  const rounding = magnitude(seatedMetrics.thoracicRoundingDegrees);
  const forwardHead = magnitude(seatedMetrics.forwardHeadAngleDegrees);
  const instrumentAtr = Math.max(
    0,
    finite(forwardMetrics.instrumentAtrDegrees) ?? 0,
    finite(forwardMetrics.thoracicAtrDegrees) ?? 0,
    finite(forwardMetrics.lumbarAtrDegrees) ?? 0
  );
  const headTilt = magnitude(standingMetrics.headTiltDegrees);
  const occiputWall = Math.max(0, finite(seatedMetrics.occiputWallDistanceCm) ?? 0);
  const gaitValue = Math.max(
    magnitude(gaitMetrics.gaitShoulderSwingDifferenceCm),
    magnitude(gaitMetrics.gaitPelvicSwingDifferenceCm),
    magnitude(gaitMetrics.gaitTrunkSwayCm)
  );
  const adams = adamsValue(forward, profile);
  const complete = metricsValid && POSTURE_CAPTURE_TASKS.every((task) => {
    const snapshot = byTask.get(task);
    return snapshot && snapshotHasMetricEvidence(snapshot) && snapshot.sampleCount >= POSTURE_SCREENING_RULES.minimumSamples && snapshot.confidence >= POSTURE_SCREENING_RULES.minimumConfidence && snapshot.confidence <= 1;
  });
  const quality = POSTURE_CAPTURE_TASKS.reduce((sum, task) => sum + evidence(byTask.get(task)), 0) / POSTURE_CAPTURE_TASKS.length;
  const seatedAbnormal = trunk > profile.seatedMidlineAttention || rounding >= profile.seatedRoundingAttention || forwardHead >= profile.forwardHeadReferral;
  const seatedAbnormalYellow = trunk > profile.seatedMidlineAttention || rounding >= profile.seatedRoundingAttention || forwardHead >= profile.forwardHeadAttention;
  const gaitAbnormal = gaitValue >= profile.gaitAttention;
  const weightedScoreRaw = (
    norm(shoulder, profile.shoulderAttention, profile.shoulderReferral) * profile.weightedShoulder +
    norm(pelvis, profile.pelvisAttention, profile.pelvisReferral) * profile.weightedPelvis +
    norm(trunk, profile.seatedMidlineAttention, profile.seatedMidlineAttention + 1.2) * profile.weightedSpinalMidline +
    norm(rounding, profile.seatedRoundingAttention, profile.seatedRoundingAttention + 14) * profile.weightedThoracicRounding +
    norm(forwardHead, profile.forwardHeadAttention, profile.forwardHeadReferral) * profile.weightedForwardHead +
    adams * profile.weightedAdams +
    norm(gaitValue, profile.gaitAttention, profile.gaitAttention + 1.1) * profile.weightedGait
  ) / POSTURE_SCREENING_RULES.scoringWeightTotal;
  const evidenceAdjustedScore = clamp01(weightedScoreRaw * (.55 + .45 * clamp01(quality)));
  const shoulderRed = shoulder > profile.shoulderReferral;
  const pelvisRed = pelvis > profile.pelvisReferral;
  // A camera ATR proxy is kept as an explanatory observation only. It is not
  // a validated 2D measurement and must not become a referral decision.
  const atrRed = instrumentAtr >= profile.proxyAtrReferral;
  const atrYellow = instrumentAtr >= profile.proxyAtrAttention;
  const hardRed = adams >= 1 && (gaitAbnormal || seatedAbnormal);
  const headTiltYellow = headTilt > profile.headTiltAttention;
  const hardYellow = shoulderRed || pelvisRed || adams >= 1 || gaitAbnormal || seatedAbnormal || headTiltYellow;
  let overallLevel = 'green';
  if (!complete) overallLevel = 'pending';
  else if (atrRed || hardRed || evidenceAdjustedScore >= profile.redScore / 100) overallLevel = 'red';
  else if (atrYellow || occiputWall > 2 || hardYellow || evidenceAdjustedScore >= profile.yellowScore / 100 || shoulder > profile.shoulderAttention || pelvis > profile.pelvisAttention || adams > 0 || seatedAbnormalYellow) overallLevel = 'yellow';

  const reasons = [];
  const append = (label, value, unit = '') => {
    if (Number.isFinite(value)) reasons.push(`${label} ${Math.abs(value).toFixed(1)}${unit}`);
  };
  append('站姿双肩高度差', finite(standingMetrics.shoulderHeightDifferenceCm), ' cm');
  append('站姿骨盆高度差', finite(standingMetrics.pelvicHeightDifferenceCm), ' cm');
  append('头部侧倾角', finite(standingMetrics.headTiltDegrees), '°');
  append('坐姿躯干中线偏移', finite(seatedMetrics.spinalMidlineDeviationCm), ' cm');
  append('坐姿胸椎圆背观察角度', finite(seatedMetrics.thoracicRoundingDegrees), '°');
  append('坐姿头前伸观察角度', finite(seatedMetrics.forwardHeadAngleDegrees), '°');
  append('步态躯干侧向摆动', finite(gaitMetrics.gaitTrunkSwayCm), ' cm');
  if ([forwardMetrics.instrumentAtrDegrees, forwardMetrics.thoracicAtrDegrees, forwardMetrics.lumbarAtrDegrees].some((value) => finite(value) != null)) append('校准设备/深度 ATR 最大值', instrumentAtr, '°');
  if (!metricsValid) reasons.push('检测到异常测量值，请重新拍摄并保持设备稳定。');
  if (!reasons.length) reasons.push(complete ? '记录完整，暂未发现需要进一步关注的指标。' : '请完成 4 项拍摄记录，并保持每项画面稳定、全身入镜。');
  if (complete) reasons.push(`姿态综合关注度 ${Math.floor(evidenceAdjustedScore * 100)} 分 · 记录稳定度 ${Math.floor(quality * 100)}%`);

  return {
    algorithm: POSTURE_ALGORITHM_VERSION,
    rulesSourceVersion: POSTURE_RULES_SOURCE_VERSION,
    calibrationVersion: MODEL_CALIBRATION_VERSION,
    overallLevel,
    riskScore: Math.min(100, Math.max(0, Math.floor(evidenceAdjustedScore * 100))),
    qualityScore: Math.min(100, Math.max(0, Math.floor(clamp01(quality) * 100))),
    complete,
    reasons,
    disclaimer: '本报告用于家庭健康观察与风险提示，不替代脊柱筛查、体检或影像检查。',
    ageMonths: Number.isInteger(ageMonths) ? ageMonths : null
  };
}
