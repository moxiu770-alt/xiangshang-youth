/**
 * Canonical posture-screening scorer used by the API.
 *
 * This is intentionally a screening/quality model, not a scoliosis
 * diagnosis. Native clients can preview the same report, but the server is
 * the authority for the persisted level and score so a forged client level
 * cannot be published.
 */
import { MODEL_CALIBRATION_VERSION } from './modelCalibration.js';
import { MODEL_REGISTRY, postureClassificationIsPublished } from './modelRegistry.js';

export const POSTURE_ALGORITHM_VERSION = 'UY-IMCA-CV-1.3';
export const POSTURE_RULES_SOURCE_VERSION = 'UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20';
export const POSTURE_CAPTURE_TASKS = Object.freeze(['standingFront', 'standingBack', 'standingSide', 'forwardBend', 'dynamicKneeControl', 'gaitVideo', 'seatedPosture', 'footArch']);
// The mobile clients can currently prove a guided capture only: rear 1×
// camera, level device, one full body and a robust multi-frame window.  A
// physical board / PnP result is intentionally a separate, stricter tier.
// Do not call guided evidence "calibrated" in an API response or a report.
export const GUIDED_CAPTURE_PROTOCOL_PREFIX = 'UY-CAPTURE-GUIDED-';
export const MARKER_PNP_CAPTURE_PROTOCOL_PREFIX = 'UY-CAPTURE-MARKER-PNP-';
export const GUIDED_CAPTURE_CHECKS = Object.freeze([
  'device-level', 'full-body', 'single-person', 'landmark-confidence', 'multi-frame-robust'
]);
export const GUIDED_FOOT_CAPTURE_CHECKS = Object.freeze([
  'device-level', 'foot-close-up', 'lower-limb-landmarks', 'single-person', 'landmark-confidence', 'multi-frame-robust'
]);
export const MAXIMUM_MARKER_REPROJECTION_ERROR_PX = 2;
export const POSTURE_SCREENING_RULES = Object.freeze({
  minimumAgeMonths: 72,
  maximumAgeMonths: 155,
  minimumSamples: 10,
  minimumConfidence: 0.56,
  scoringWeightTotal: 1.10,
  shoulderNormalCentimeters: .5,
  shoulderMarkedCentimeters: 1.5,
  pelvisNormalCentimeters: .5,
  pelvisMarkedCentimeters: 1.0,
  headTiltNormalDegrees: 3,
  seatedMidlineNormalCentimeters: 1.0,
  gaitShoulderDifferenceCentimeters: 1.0,
  atrAttentionDegrees: 5,
  atrReferralDegrees: 7,
  occiputWallDistanceAbnormalCentimeters: 2
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
const stringValue = (value) => typeof value === 'string' && value.trim() ? value.trim() : null;
const stringList = (value) => Array.isArray(value)
  ? [...new Set(value.map(stringValue).filter(Boolean))]
  : [];

/**
 * New native clients serialise this trace inside `metrics` for backward
 * compatibility with the existing posture_snapshots table.  Accept a future
 * top-level field as well, but never infer a calibration board from a label.
 */
function captureMetadataFor(snapshot) {
  const metrics = metricsFor(snapshot);
  const nested = metrics.captureMetadata && typeof metrics.captureMetadata === 'object'
    ? metrics.captureMetadata
    : {};
  const calibration = snapshot?.calibration && typeof snapshot.calibration === 'object'
    ? snapshot.calibration
    : metrics.captureCalibration && typeof metrics.captureCalibration === 'object'
      ? metrics.captureCalibration
    : nested.calibration && typeof nested.calibration === 'object'
      ? nested.calibration
      : {};
  return {
    protocolVersion: stringValue(snapshot?.captureProtocolVersion)
      ?? stringValue(nested.captureProtocolVersion)
      ?? stringValue(metrics.captureProtocolVersion),
    cameraFacing: stringValue(snapshot?.cameraFacing)
      ?? stringValue(nested.cameraFacing)
      ?? stringValue(metrics.cameraFacing),
    qualityChecks: stringList(snapshot?.qualityChecks).length
      ? stringList(snapshot.qualityChecks)
      : stringList(nested.qualityChecks).length
        ? stringList(nested.qualityChecks)
        : stringList(metrics.qualityChecks),
    calibration: {
      mode: stringValue(calibration.mode),
      boardDetected: calibration.boardDetected === true,
      boardId: stringValue(calibration.boardId),
      intrinsicsId: stringValue(calibration.intrinsicsId),
      lensId: stringValue(calibration.lensId),
      resolution: stringValue(calibration.resolution),
      profileId: stringValue(calibration.profileId),
      reprojectionErrorPx: finite(calibration.reprojectionErrorPx)
    }
  };
}

function captureQualityFor(snapshots) {
  const traces = snapshots.map((snapshot) => ({ task: snapshot?.captureTask, ...captureMetadataFor(snapshot) }));
  const hasTrace = traces.some((trace) => trace.protocolVersion || trace.cameraFacing || trace.qualityChecks.length);
  if (!hasTrace) {
    return {
      level: 'legacy-untraced',
      formalMeasurementEligible: false,
      message: '该历史记录未包含采集协议追溯信息；仅保留为家庭观察记录，不能作为高精度对比依据。'
    };
  }
  const allRearOneX = traces.every((trace) => trace.cameraFacing === 'rear-1x');
  const allGuidedChecks = traces.every((trace) => {
    const required = trace.task === 'footArch' ? GUIDED_FOOT_CAPTURE_CHECKS : GUIDED_CAPTURE_CHECKS;
    return required.every((check) => trace.qualityChecks.includes(check));
  });
  const allV2Repeatable = traces.every((trace) => !/^UY-CAPTURE-GUIDED-(2|3)\./.test(trace.protocolVersion || '') || trace.qualityChecks.includes('two-take-repeatability'));
  const markerPnp = traces.length === POSTURE_CAPTURE_TASKS.length && traces.every((trace) =>
    trace.protocolVersion?.startsWith(MARKER_PNP_CAPTURE_PROTOCOL_PREFIX)
      && trace.cameraFacing === 'rear-1x'
      && trace.calibration.mode === 'marker-pnp'
      && trace.calibration.boardDetected
      && trace.calibration.boardId
      && trace.calibration.intrinsicsId
      && trace.calibration.lensId
      && trace.calibration.resolution
      && trace.calibration.profileId
      && trace.calibration.reprojectionErrorPx != null
      && trace.calibration.reprojectionErrorPx <= MAXIMUM_MARKER_REPROJECTION_ERROR_PX
  );
  if (markerPnp) {
    return {
      level: 'marker-pnp-calibrated',
      formalMeasurementEligible: true,
      message: '已记录标定板、镜头内参与 PnP 重投影误差；仍须通过独立儿童人工标注验证后才可发布算法分类。'
    };
  }
  const guided = traces.every((trace) => trace.protocolVersion?.startsWith(GUIDED_CAPTURE_PROTOCOL_PREFIX))
    && allRearOneX && allGuidedChecks && allV2Repeatable;
  if (guided) {
    return {
      level: 'guided-quality-gate',
      formalMeasurementEligible: false,
      message: '已通过后置 1× 引导质量门，但尚未检测物理标定板与 PnP 位姿；不能标注为高精度标定测量。'
    };
  }
  return {
    level: 'trace-incomplete',
    formalMeasurementEligible: false,
    message: '采集追溯信息不完整，请使用后置 1×镜头、完整入镜并重新完成质量检查。'
  };
}
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
  thoracicAtrFirstDegrees: 180,
  thoracicAtrSecondDegrees: 180,
  lumbarAtrFirstDegrees: 180,
  lumbarAtrSecondDegrees: 180,
  seatedForwardBendAtrDegrees: 180,
  cameraProxyAtrDegrees: 180,
  cameraProxyRibProminenceCm: 20,
  shoulderProtractionProxyDegrees: 180,
  pelvicTiltProxyDegrees: 90,
  kneeAlignmentProxyRatio: 2,
  lowerLimbAxisAsymmetryDegrees: 90,
  leftKneeValgusProxyDegrees: 90,
  rightKneeValgusProxyDegrees: 90,
  kneeTrackingAsymmetryRatio: 3,
  squatDepthRatio: 2,
  movementRepetitionCount: 20,
  footArchVisibilityScore: 1,
  leftArchProxyIndex: 1,
  rightArchProxyIndex: 1,
  heelAlignmentProxyDegrees: 90,
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
  standingFront: Object.freeze(['shoulderHeightDifferenceCm', 'pelvicHeightDifferenceCm', 'headTiltDegrees', 'kneeAlignmentProxyRatio', 'lowerLimbAxisAsymmetryDegrees']),
  standingBack: Object.freeze(['shoulderHeightDifferenceCm', 'pelvicHeightDifferenceCm', 'headTiltDegrees']),
  standingSide: Object.freeze(['forwardHeadAngleDegrees', 'thoracicRoundingDegrees', 'shoulderProtractionProxyDegrees', 'pelvicTiltProxyDegrees']),
  forwardBend: Object.freeze(['spinalMidlineDeviationCm', 'thoracicRoundingDegrees', 'forwardHeadAngleDegrees', 'cameraProxyAtrDegrees', 'cameraProxyRibProminenceCm', 'instrumentAtrDegrees', 'thoracicAtrDegrees', 'lumbarAtrDegrees', 'thoracicAtrFirstDegrees', 'thoracicAtrSecondDegrees', 'lumbarAtrFirstDegrees', 'lumbarAtrSecondDegrees', 'seatedForwardBendAtrDegrees']),
  dynamicKneeControl: Object.freeze(['leftKneeValgusProxyDegrees', 'rightKneeValgusProxyDegrees', 'kneeTrackingAsymmetryRatio', 'squatDepthRatio', 'movementRepetitionCount']),
  seatedPosture: Object.freeze(['shoulderHeightDifferenceCm', 'spinalMidlineDeviationCm', 'thoracicRoundingDegrees', 'forwardHeadAngleDegrees', 'occiputWallDistanceCm']),
  gaitVideo: Object.freeze(['gaitShoulderSwingDifferenceCm', 'gaitPelvicSwingDifferenceCm', 'gaitTrunkSwayCm']),
  footArch: Object.freeze(['footArchVisibilityScore', 'leftArchProxyIndex', 'rightArchProxyIndex', 'heelAlignmentProxyDegrees'])
});
function snapshotHasMetricEvidence(snapshot) {
  const metrics = snapshot?.metrics;
  if (!metrics || typeof metrics !== 'object' || Array.isArray(metrics)) return false;
  const keys = TASK_EVIDENCE_KEYS[snapshot?.captureTask] || Object.keys(POSTURE_METRIC_LIMITS);
  const numericEvidence = keys.some((key) => finite(metrics[key]) != null);
  const adamsEvidence = ['adamsObservedResult', 'adamsResult', 'adams'].some((key) => {
    const value = String(metrics[key] ?? '').trim().toLowerCase();
    return ['positive', 'equivocal', 'negative', '阳性', '可疑', '阴性', '阳', '临界'].some((token) => value.includes(token));
  });
  const structuredEvidence = ['gaitObservedAbnormal', 'seatedThoracicKyphosisObserved'].some((key) => typeof metrics[key] === 'boolean');
  return numericEvidence || adamsEvidence || structuredEvidence;
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
const averagedReading = (primaryValue, firstValue, secondValue) => {
  const first = finite(firstValue);
  const second = finite(secondValue);
  if (first != null && second != null) return Math.abs((first + second) / 2);
  const primary = finite(primaryValue);
  if (primary != null) return Math.abs(primary);
  if (first != null) return Math.abs(first);
  return 0;
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
  const observed = String(snapshot?.metrics?.adamsObservedResult ?? '').trim().toLowerCase();
  if (observed === 'positive' || observed.includes('阳性')) return 1;
  if (observed === 'equivocal' || observed.includes('可疑')) return .48;
  if (observed === 'negative' || observed.includes('阴性')) return 0;
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

  const standingShoulder = magnitude(standingMetrics.shoulderHeightDifferenceCm);
  const seatedShoulder = magnitude(seatedMetrics.shoulderHeightDifferenceCm);
  const shoulder = Math.max(standingShoulder, seatedShoulder);
  const pelvis = magnitude(standingMetrics.pelvicHeightDifferenceCm);
  const trunk = magnitude(seatedMetrics.spinalMidlineDeviationCm);
  const rounding = magnitude(seatedMetrics.thoracicRoundingDegrees);
  const forwardHead = magnitude(seatedMetrics.forwardHeadAngleDegrees);
  // The framework requires a second reading when ATR fluctuates and uses the
  // arithmetic mean. Recompute this on the server from the retained raw
  // readings so a client-supplied final value cannot change the level.
  const thoracicAtr = averagedReading(
    forwardMetrics.thoracicAtrDegrees,
    forwardMetrics.thoracicAtrFirstDegrees,
    forwardMetrics.thoracicAtrSecondDegrees
  );
  const lumbarAtr = averagedReading(
    forwardMetrics.lumbarAtrDegrees,
    forwardMetrics.lumbarAtrFirstDegrees,
    forwardMetrics.lumbarAtrSecondDegrees
  );
  const hasSegmentAtr = [
    forwardMetrics.thoracicAtrDegrees,
    forwardMetrics.lumbarAtrDegrees,
    forwardMetrics.thoracicAtrFirstDegrees,
    forwardMetrics.thoracicAtrSecondDegrees,
    forwardMetrics.lumbarAtrFirstDegrees,
    forwardMetrics.lumbarAtrSecondDegrees
  ].some((value) => finite(value) != null);
  const captureQuality = captureQualityFor([...byTask.values()]);
  const instrumentAtr = Math.max(
    0,
    hasSegmentAtr ? 0 : magnitude(forwardMetrics.instrumentAtrDegrees),
    thoracicAtr,
    lumbarAtr
  );
  const seatedReviewAtr = finite(forwardMetrics.seatedForwardBendAtrDegrees);
  const atrDrop = seatedReviewAtr == null ? null : instrumentAtr - Math.max(0, seatedReviewAtr);
  const headTilt = magnitude(standingMetrics.headTiltDegrees);
  const occiputWall = Math.max(0, finite(seatedMetrics.occiputWallDistanceCm) ?? 0);
  const gaitValue = Math.max(
    magnitude(gaitMetrics.gaitShoulderSwingDifferenceCm),
    magnitude(gaitMetrics.gaitPelvicSwingDifferenceCm),
    magnitude(gaitMetrics.gaitTrunkSwayCm)
  );
  const adams = adamsValue(forward, profile);
  const ageApplicable = Number.isInteger(ageMonths) && ageMonths >= POSTURE_SCREENING_RULES.minimumAgeMonths && ageMonths <= POSTURE_SCREENING_RULES.maximumAgeMonths;
  const complete = ageApplicable && metricsValid && POSTURE_CAPTURE_TASKS.every((task) => {
    const snapshot = byTask.get(task);
    return snapshot && snapshotHasMetricEvidence(snapshot) && snapshot.sampleCount >= POSTURE_SCREENING_RULES.minimumSamples && snapshot.confidence >= POSTURE_SCREENING_RULES.minimumConfidence && snapshot.confidence <= 1;
  });
  const quality = POSTURE_CAPTURE_TASKS.reduce((sum, task) => sum + evidence(byTask.get(task)), 0) / POSTURE_CAPTURE_TASKS.length;
  const seatedAbnormal = trunk > POSTURE_SCREENING_RULES.seatedMidlineNormalCentimeters || seatedShoulder > POSTURE_SCREENING_RULES.shoulderNormalCentimeters || seatedMetrics.seatedThoracicKyphosisObserved === true || occiputWall > POSTURE_SCREENING_RULES.occiputWallDistanceAbnormalCentimeters;
  const seatedAbnormalYellow = seatedAbnormal;
  const gaitAbnormal = gaitMetrics.gaitObservedAbnormal === true || gaitValue >= POSTURE_SCREENING_RULES.gaitShoulderDifferenceCentimeters;
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
  const shoulderRed = standingShoulder > POSTURE_SCREENING_RULES.shoulderMarkedCentimeters;
  const shoulderYellow = standingShoulder > POSTURE_SCREENING_RULES.shoulderNormalCentimeters;
  const pelvisRed = pelvis > POSTURE_SCREENING_RULES.pelvisMarkedCentimeters;
  const pelvisYellow = pelvis > POSTURE_SCREENING_RULES.pelvisNormalCentimeters;
  // A camera ATR proxy is kept as an explanatory observation only. It is not
  // a validated 2D measurement and must not become a referral decision.
  const fixedAtrConcern = instrumentAtr >= POSTURE_SCREENING_RULES.atrAttentionDegrees && atrDrop != null && atrDrop < 3;
  const atrRed = instrumentAtr >= POSTURE_SCREENING_RULES.atrReferralDegrees || fixedAtrConcern;
  const atrYellow = instrumentAtr >= POSTURE_SCREENING_RULES.atrAttentionDegrees && !atrRed;
  const hardRed = adams >= 1 && (gaitAbnormal || seatedAbnormal);
  const headTiltYellow = headTilt > POSTURE_SCREENING_RULES.headTiltNormalDegrees;
  const hardYellow = shoulderRed || pelvisRed || adams >= 1 || gaitAbnormal || seatedAbnormal || headTiltYellow;
  let overallLevel = 'green';
  if (!complete) overallLevel = 'pending';
  else if (atrRed || hardRed) overallLevel = 'red';
  else if (atrYellow || occiputWall > POSTURE_SCREENING_RULES.occiputWallDistanceAbnormalCentimeters || hardYellow || shoulderYellow || pelvisYellow || adams > 0 || seatedAbnormalYellow) overallLevel = 'yellow';

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
  if ([
    forwardMetrics.instrumentAtrDegrees,
    forwardMetrics.thoracicAtrDegrees,
    forwardMetrics.lumbarAtrDegrees,
    forwardMetrics.thoracicAtrFirstDegrees,
    forwardMetrics.thoracicAtrSecondDegrees,
    forwardMetrics.lumbarAtrFirstDegrees,
    forwardMetrics.lumbarAtrSecondDegrees
  ].some((value) => finite(value) != null)) append('Bunnell 脊柱侧弯计 ATR 最大值', instrumentAtr, '°');
  if ([forwardMetrics.thoracicAtrFirstDegrees, forwardMetrics.thoracicAtrSecondDegrees].every((value) => finite(value) != null)) {
    reasons.push(`胸段 ATR 原始读数 ${Math.abs(Number(forwardMetrics.thoracicAtrFirstDegrees)).toFixed(1)}° / ${Math.abs(Number(forwardMetrics.thoracicAtrSecondDegrees)).toFixed(1)}°，算术平均 ${thoracicAtr.toFixed(1)}°`);
  }
  if ([forwardMetrics.lumbarAtrFirstDegrees, forwardMetrics.lumbarAtrSecondDegrees].every((value) => finite(value) != null)) {
    reasons.push(`腰段 ATR 原始读数 ${Math.abs(Number(forwardMetrics.lumbarAtrFirstDegrees)).toFixed(1)}° / ${Math.abs(Number(forwardMetrics.lumbarAtrSecondDegrees)).toFixed(1)}°，算术平均 ${lumbarAtr.toFixed(1)}°`);
  }
  if (seatedReviewAtr != null && atrDrop != null) reasons.push(`坐位前屈 ATR ${Math.max(0, seatedReviewAtr).toFixed(1)}°，较站位变化 ${atrDrop.toFixed(1)}°（${atrDrop >= 3 ? '功能性偏斜可能' : '结构异常复核提示'}）`);
  if (['左', '右'].includes(forwardMetrics.adamsProminenceSide)) reasons.push(`前屈隆起侧：${forwardMetrics.adamsProminenceSide}侧`);
  if (typeof gaitMetrics.gaitObservedAbnormal === 'boolean') reasons.push(gaitMetrics.gaitObservedAbnormal ? '步态人工观察：存在异常' : '步态人工观察：未见异常');
  if (typeof gaitMetrics.gaitObservationNote === 'string' && gaitMetrics.gaitObservationNote.trim()) reasons.push(`步态备注：${gaitMetrics.gaitObservationNote.trim().slice(0, 200)}`);
  if (typeof seatedMetrics.seatedThoracicKyphosisObserved === 'boolean') reasons.push(seatedMetrics.seatedThoracicKyphosisObserved ? '坐姿观察：存在圆肩驼背表现' : '坐姿观察：未见明显圆肩驼背');
  if (!metricsValid) reasons.push('检测到异常测量值，请重新拍摄并保持设备稳定。');
  if (!ageApplicable) reasons.push('本五项脊柱筛查手册仅适用于 6–12 岁，请核对孩子出生日期和测量日期。');
  if (captureQuality.level !== 'marker-pnp-calibrated') reasons.push(captureQuality.message);
  if (!reasons.length) reasons.push(complete ? '记录已完成，可供后续人工复核与算法验证使用。' : '请完成 4 项拍摄记录，并保持每项画面稳定、全身入镜。');
  const classificationPublished = postureClassificationIsPublished();
  if (complete && classificationPublished) reasons.push(`姿态综合关注度 ${Math.floor(evidenceAdjustedScore * 100)} 分 · 记录稳定度 ${Math.floor(quality * 100)}%`);

  return {
    algorithm: POSTURE_ALGORITHM_VERSION,
    rulesSourceVersion: POSTURE_RULES_SOURCE_VERSION,
    calibrationVersion: MODEL_CALIBRATION_VERSION,
    validationStatus: MODEL_REGISTRY.posture.status,
    domainValidation: MODEL_REGISTRY.posture.domainValidation,
    classificationPublished,
    overallLevel,
    riskScore: Math.min(100, Math.max(0, Math.floor(evidenceAdjustedScore * 100))),
    qualityScore: Math.min(100, Math.max(0, Math.floor(clamp01(quality) * 100))),
    captureQuality,
    complete,
    ageApplicable,
    reasons,
    disclaimer: classificationPublished
      ? '本报告用于家庭健康观察与风险提示，不替代脊柱筛查、体检或影像检查。'
      : '手机姿态算法尚未完成人工标注验证；当前结果仅供内部评估与采集质量检查，不得面向家庭发布风险等级。',
    ageMonths: Number.isInteger(ageMonths) ? ageMonths : null
  };
}
