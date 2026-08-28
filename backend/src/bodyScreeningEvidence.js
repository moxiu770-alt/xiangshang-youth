/**
 * Trust boundary for parent-submitted body-screening evidence.
 *
 * The household flow may submit camera-derived proxies, guardian observations
 * and capture-quality provenance. It must never be able to promote a value to
 * an instrument measurement merely by naming a JSON property accordingly.
 */

const CAPTURE_TASKS = new Set([
  'standingFront', 'standingBack', 'standingSide', 'forwardBend',
  'dynamicKneeControl', 'gaitVideo', 'seatedPosture', 'footArch'
]);
const QUALITY_CHECKS = new Set([
  'device-level', 'full-body', 'single-person', 'landmark-confidence',
  'multi-frame-robust', 'two-take-repeatability', 'three-repetition-cycle'
]);

const finiteInRange = (value, minimum, maximum) => {
  const numeric = Number(value);
  return Number.isFinite(numeric) && numeric >= minimum && numeric <= maximum ? numeric : undefined;
};
const shortText = (value, maximum = 120) => {
  const text = typeof value === 'string' ? value.trim() : '';
  return text ? text.slice(0, maximum) : undefined;
};
const enumText = (value, allowed) => {
  const text = shortText(value);
  return text && allowed.has(text) ? text : undefined;
};
const put = (target, key, value) => { if (value !== undefined) target[key] = value; };

const NUMERIC_FIELDS = Object.freeze({
  standingFront: [
    ['shoulderHeightDifferenceCm', 0, 50], ['pelvicHeightDifferenceCm', 0, 50],
    ['headTiltDegrees', 0, 90], ['kneeAlignmentProxyRatio', -2, 2],
    ['lowerLimbAxisAsymmetryDegrees', 0, 90]
  ],
  standingBack: [
    ['shoulderHeightDifferenceCm', 0, 50], ['pelvicHeightDifferenceCm', 0, 50],
    ['headTiltDegrees', 0, 90], ['spinalMidlineDeviationCm', 0, 50]
  ],
  forwardBend: [
    ['cameraProxyAtrDegrees', 0, 90], ['cameraProxyRibProminenceCm', 0, 50]
  ],
  standingSide: [
    ['forwardHeadAngleDegrees', 0, 180], ['thoracicRoundingDegrees', 0, 180],
    ['shoulderProtractionProxyDegrees', 0, 180], ['pelvicTiltProxyDegrees', -90, 90]
  ],
  dynamicKneeControl: [
    ['leftKneeValgusProxyDegrees', -90, 90], ['rightKneeValgusProxyDegrees', -90, 90],
    ['kneeTrackingAsymmetryRatio', 0, 3], ['squatDepthRatio', 0, 2], ['movementRepetitionCount', 0, 20]
  ],
  seatedPosture: [
    ['shoulderHeightDifferenceCm', 0, 50], ['spinalMidlineDeviationCm', 0, 50],
    ['thoracicRoundingDegrees', 0, 180], ['forwardHeadAngleDegrees', 0, 180]
  ],
  gaitVideo: [
    ['gaitShoulderSwingDifferenceCm', 0, 50], ['gaitPelvicSwingDifferenceCm', 0, 50],
    ['gaitTrunkSwayCm', 0, 50]
  ],
  footArch: [
    ['footArchVisibilityScore', 0, 1], ['leftArchProxyIndex', 0, 1],
    ['rightArchProxyIndex', 0, 1], ['heelAlignmentProxyDegrees', -90, 90]
  ]
});

function safeCalibration(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const mode = enumText(value.mode, new Set(['guided', 'marker-pnp']));
  if (!mode) return undefined;
  const result = { mode, boardDetected: value.boardDetected === true };
  for (const key of ['boardId', 'intrinsicsId', 'lensId', 'resolution', 'profileId']) put(result, key, shortText(value[key], 160));
  put(result, 'reprojectionErrorPx', finiteInRange(value.reprojectionErrorPx, 0, 20));
  return result;
}

/** Returns the only structure accepted from the household camera workflow. */
export function sanitizeHouseholdBodyMetrics(value, captureTask) {
  if (!CAPTURE_TASKS.has(captureTask)) throw new TypeError('unsupported capture task');
  const source = value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  const nested = source.captureMetadata && typeof source.captureMetadata === 'object' && !Array.isArray(source.captureMetadata)
    ? source.captureMetadata : {};
  const result = {};
  for (const [key, minimum, maximum] of NUMERIC_FIELDS[captureTask]) put(result, key, finiteInRange(source[key], minimum, maximum));

  if (captureTask === 'forwardBend') {
    put(result, 'adamsObservedResult', enumText(source.adamsObservedResult, new Set(['negative', 'equivocal', 'positive'])));
    put(result, 'adamsProminenceSide', enumText(source.adamsProminenceSide, new Set(['左', '右', 'left', 'right'])));
  }
  if (captureTask === 'seatedPosture' && typeof source.seatedThoracicKyphosisObserved === 'boolean') {
    result.seatedThoracicKyphosisObserved = source.seatedThoracicKyphosisObserved;
  }
  if (captureTask === 'gaitVideo') {
    if (typeof source.gaitObservedAbnormal === 'boolean') result.gaitObservedAbnormal = source.gaitObservedAbnormal;
    put(result, 'gaitObservationNote', shortText(source.gaitObservationNote, 240));
  }

  put(result, 'captureProtocolVersion', shortText(source.captureProtocolVersion ?? nested.captureProtocolVersion, 120));
  put(result, 'cameraFacing', enumText(source.cameraFacing ?? nested.cameraFacing, new Set(['rear-1x'])));
  put(result, 'measurementMode', enumText(source.measurementMode ?? nested.measurementMode, new Set(['rgb-pose-2d', 'depth-assisted-3d'])));
  put(result, 'deviceCapabilityTier', enumText(source.deviceCapabilityTier ?? nested.deviceCapabilityTier, new Set(['standard-2d', 'enhanced-depth'])));
  const depthAvailable = source.depthAvailable ?? nested.depthAvailable;
  if (typeof depthAvailable === 'boolean') result.depthAvailable = depthAvailable;
  const segmentPhaseCount = finiteInRange(source.segmentPhaseCount ?? nested.segmentPhaseCount, 1, 4);
  if (segmentPhaseCount !== undefined) result.segmentPhaseCount = Math.trunc(segmentPhaseCount);
  const checks = Array.isArray(source.qualityChecks) ? source.qualityChecks : Array.isArray(nested.qualityChecks) ? nested.qualityChecks : [];
  const safeChecks = [...new Set(checks.filter((item) => typeof item === 'string').map((item) => item.trim()).filter((item) => QUALITY_CHECKS.has(item)))];
  if (safeChecks.length) result.qualityChecks = safeChecks;
  const calibration = safeCalibration(source.captureCalibration ?? nested.calibration);
  if (calibration) result.captureCalibration = calibration;
  const attemptCount = finiteInRange(source.captureAttemptCount, 1, 10);
  if (attemptCount !== undefined) result.captureAttemptCount = Math.trunc(attemptCount);
  put(result, 'repeatabilityStatus', enumText(source.repeatabilityStatus, new Set(['awaiting-second-take', 'passed', 'inconsistent'])));
  put(result, 'repeatabilityMaximumDifference', finiteInRange(source.repeatabilityMaximumDifference, 0, 100));
  return result;
}

const EVIDENCE_DEFINITIONS = Object.freeze({
  shoulderHeightDifferenceCm: ['shoulder_projection_difference', '双肩高度投影差', '相对投影值'],
  pelvicHeightDifferenceCm: ['pelvis_projection_difference', '骨盆高度投影差', '相对投影值'],
  headTiltDegrees: ['head_tilt_camera_estimate', '头部倾斜画面估计', '°（摄像头估计）'],
  spinalMidlineDeviationCm: ['trunk_midline_projection', '躯干中线投影偏移', '相对投影值'],
  thoracicRoundingDegrees: ['thoracic_rounding_camera_estimate', '胸椎后凸画面估计', '°（摄像头估计）'],
  forwardHeadAngleDegrees: ['forward_head_camera_estimate', '头前伸画面估计', '°（摄像头估计）'],
  shoulderProtractionProxyDegrees: ['shoulder_protraction_proxy', '圆肩画面代理角', '°（摄像头估计）'],
  pelvicTiltProxyDegrees: ['pelvic_tilt_proxy', '骨盆侧位倾斜代理角', '°（摄像头估计）'],
  kneeAlignmentProxyRatio: ['knee_alignment_proxy', '静态膝踝力线比例', '归一化比值'],
  lowerLimbAxisAsymmetryDegrees: ['lower_limb_axis_asymmetry', '左右下肢力线差', '°（摄像头估计）'],
  leftKneeValgusProxyDegrees: ['left_knee_valgus_proxy', '左膝动态内扣代理角', '°（摄像头估计）'],
  rightKneeValgusProxyDegrees: ['right_knee_valgus_proxy', '右膝动态内扣代理角', '°（摄像头估计）'],
  kneeTrackingAsymmetryRatio: ['knee_tracking_asymmetry', '双膝轨迹不对称', '归一化比值'],
  squatDepthRatio: ['squat_depth_ratio', '下蹲深度', '归一化比值'],
  movementRepetitionCount: ['movement_repetition_count', '有效下蹲次数', '次'],
  footArchVisibilityScore: ['foot_arch_visibility_quality', '足弓可见质量', '质量分'],
  leftArchProxyIndex: ['left_arch_proxy', '左足弓外观指数', '归一化代理值'],
  rightArchProxyIndex: ['right_arch_proxy', '右足弓外观指数', '归一化代理值'],
  heelAlignmentProxyDegrees: ['heel_alignment_proxy', '足跟对齐代理角', '°（摄像头估计）'],
  cameraProxyAtrDegrees: ['forward_bend_rotation_proxy', '前屈旋转投影参考', '°（二维代理，非 ATR）'],
  cameraProxyRibProminenceCm: ['forward_bend_prominence_proxy', '前屈隆起投影参考', '相对投影值'],
  gaitShoulderSwingDifferenceCm: ['gait_shoulder_swing_proxy', '步态双肩摆动投影差', '相对投影值'],
  gaitPelvicSwingDifferenceCm: ['gait_pelvis_swing_proxy', '步态骨盆摆动投影差', '相对投影值'],
  gaitTrunkSwayCm: ['gait_trunk_sway_proxy', '步态躯干摆动投影值', '相对投影值']
});

const OBSERVATION_DEFINITIONS = Object.freeze({
  adamsObservedResult: ['adams_guardian_observation', '家长前屈观察', { negative: '未见明显不对称', equivocal: '观察不确定', positive: '观察到明显不对称' }],
  adamsProminenceSide: ['adams_guardian_side', '家长观察隆起侧', { left: '左侧', right: '右侧', 左: '左侧', 右: '右侧' }],
  seatedThoracicKyphosisObserved: ['seated_guardian_observation', '家长坐姿观察', { true: '观察到明显弓背', false: '未观察到明显弓背' }],
  gaitObservedAbnormal: ['gait_guardian_observation', '家长步态观察', { true: '观察到明显异常', false: '未观察到明显异常' }],
  gaitObservationNote: ['gait_guardian_note', '家长步态补充', null]
});

/** Produces a display-safe, typed evidence list; the original JSON is never returned. */
export function bodyScreeningEvidenceMetrics(value, captureTask) {
  const metrics = sanitizeHouseholdBodyMetrics(value, captureTask);
  const evidence = [];
  for (const [field, definition] of Object.entries(EVIDENCE_DEFINITIONS)) {
    if (metrics[field] === undefined) continue;
    evidence.push({ code: definition[0], label: definition[1], numericValue: metrics[field], unit: definition[2], source: 'camera_proxy' });
  }
  for (const [field, definition] of Object.entries(OBSERVATION_DEFINITIONS)) {
    if (metrics[field] === undefined) continue;
    const mapped = definition[2] ? definition[2][String(metrics[field])] : String(metrics[field]);
    if (mapped) evidence.push({ code: definition[0], label: definition[1], textValue: mapped, source: 'guardian_observation' });
  }
  return evidence;
}
