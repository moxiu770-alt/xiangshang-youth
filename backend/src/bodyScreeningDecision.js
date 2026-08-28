export const BODY_SCREENING_DECISION_POLICY_VERSION = 'UY-BODY-TRIAGE-2.0';

export const BodyScreeningRoute = Object.freeze({
  AUTO_ARCHIVE: 'auto_archive',
  RECAPTURE: 'recapture_required',
  PROFESSIONAL_REVIEW: 'professional_review'
});

export const BodyScreeningOutcomeLevel = Object.freeze({
  CAPTURE_INVALID: 'capture_invalid',
  NO_OBVIOUS_ABNORMALITY: 'no_obvious_abnormality',
  TRAINING_OBSERVATION: 'training_observation',
  SCHOOL_RETEST: 'school_retest',
  PROFESSIONAL_EVALUATION: 'professional_evaluation'
});

export const REQUIRED_VALIDATION_DOMAINS = Object.freeze([
  'spinal_alignment', 'shoulder_pelvis', 'head_upper_posture', 'trunk_rotation',
  'dynamic_knee', 'gait', 'seated_posture', 'foot_arch'
]);

export const REQUIRED_HOUSEHOLD_TASKS = Object.freeze([
  'standingFront', 'standingBack', 'standingSide', 'forwardBend',
  'dynamicKneeControl', 'gaitVideo', 'seatedPosture', 'footArch'
]);
const REQUIRED_GUIDED_CHECKS = Object.freeze([
  'device-level', 'full-body', 'single-person', 'landmark-confidence',
  'multi-frame-robust', 'two-take-repeatability'
]);
const REQUIRED_FOOT_CHECKS = Object.freeze([
  'device-level', 'foot-close-up', 'lower-limb-landmarks', 'single-person',
  'landmark-confidence', 'multi-frame-robust', 'two-take-repeatability'
]);

const metadata = (snapshot) => {
  const metrics = snapshot?.metrics && typeof snapshot.metrics === 'object' ? snapshot.metrics : {};
  const nested = metrics.captureMetadata && typeof metrics.captureMetadata === 'object' ? metrics.captureMetadata : {};
  return {
    protocolVersion: String(metrics.captureProtocolVersion || nested.captureProtocolVersion || ''),
    cameraFacing: String(metrics.cameraFacing || nested.cameraFacing || ''),
    qualityChecks: Array.isArray(metrics.qualityChecks)
      ? metrics.qualityChecks.map(String)
      : Array.isArray(nested.qualityChecks) ? nested.qualityChecks.map(String) : [],
    attemptCount: Number(metrics.captureAttemptCount || nested.captureAttemptCount || 0),
    repeatabilityStatus: String(metrics.repeatabilityStatus || nested.repeatabilityStatus || '')
  };
};

const rawMediaKey = (path) => /(raw(frame|frames|image|images|photo|photos|video)|image(path|url|data)|video(path|url|data)|base64|pixelbuffer|samplebuffer)/i.test(path);

/** Fail closed if a structured-only payload accidentally contains child media. */
export function containsRawMedia(value, path = '') {
  if (Array.isArray(value)) return value.some((entry, index) => containsRawMedia(entry, `${path}[${index}]`));
  if (!value || typeof value !== 'object') return false;
  return Object.entries(value).some(([key, entry]) => {
    const nextPath = path ? `${path}.${key}` : key;
    return rawMediaKey(nextPath) || containsRawMedia(entry, nextPath);
  });
}

export function decideBodyScreening({ snapshots = [], postureReport = null, modelUncertainty = null } = {}) {
  const reasons = [];
  const byTask = new Map(snapshots.map((snapshot) => [snapshot?.captureTask, snapshot]));
  if (REQUIRED_HOUSEHOLD_TASKS.some((task) => !byTask.has(task))) reasons.push('CAPTURE_TASKS_INCOMPLETE');

  for (const task of REQUIRED_HOUSEHOLD_TASKS) {
    const snapshot = byTask.get(task);
    if (!snapshot) continue;
    const trace = metadata(snapshot);
    if (!trace.protocolVersion.startsWith('UY-CAPTURE-GUIDED-3.') && !trace.protocolVersion.startsWith('UY-CAPTURE-MARKER-PNP-')) reasons.push('CAPTURE_PROTOCOL_UNSUPPORTED');
    if (trace.cameraFacing !== 'rear-1x') reasons.push('FORMAL_CAMERA_NOT_REAR_1X');
    const requiredChecks = task === 'footArch' ? REQUIRED_FOOT_CHECKS : REQUIRED_GUIDED_CHECKS;
    if (requiredChecks.some((check) => !trace.qualityChecks.includes(check))) reasons.push('QUALITY_GATE_INCOMPLETE');
    if (trace.attemptCount < 2 || !['passed', 'stable', 'consistent'].includes(trace.repeatabilityStatus.toLowerCase())) reasons.push('REPEATABILITY_INCOMPLETE');
    if (!Number.isFinite(Number(snapshot.confidence)) || Number(snapshot.confidence) < 0.56) reasons.push('LANDMARK_CONFIDENCE_LOW');
    if (!['rgb-pose-2d', 'depth-assisted-3d'].includes(String(snapshot?.metrics?.measurementMode || ''))) reasons.push('MEASUREMENT_MODE_MISSING');
    if (!['standard-2d', 'enhanced-depth'].includes(String(snapshot?.metrics?.deviceCapabilityTier || ''))) reasons.push('DEVICE_TIER_MISSING');
    if (['standingSide', 'footArch'].includes(task) && Number(snapshot?.metrics?.segmentPhaseCount || 0) < 2) reasons.push('BILATERAL_PHASES_INCOMPLETE');
    if (task === 'dynamicKneeControl' && Number(snapshot?.metrics?.movementRepetitionCount || 0) < 3) reasons.push('DYNAMIC_REPETITIONS_INCOMPLETE');
  }

  const recaptureReasons = [...new Set(reasons)];
  if (recaptureReasons.length) return {
    route: BodyScreeningRoute.RECAPTURE,
    outcomeLevel: BodyScreeningOutcomeLevel.CAPTURE_INVALID,
    reasonCodes: recaptureReasons,
    reviewRequired: false,
    decisionPolicyVersion: BODY_SCREENING_DECISION_POLICY_VERSION
  };

  const validationStatus = String(postureReport?.validationStatus || 'pending-human-validation');
  const uncertainty = Number.isFinite(Number(modelUncertainty)) ? Number(modelUncertainty) : validationStatus === 'human-validated' ? 0 : 1;
  const riskScore = Number(postureReport?.riskScore || 0);
  const candidateLevel = String(postureReport?.candidateLevel || postureReport?.overallLevel || 'pending');
  const reviewReasons = [];
  if (validationStatus !== 'human-validated') reviewReasons.push('MODEL_PENDING_HUMAN_VALIDATION');
  const domainValidation = postureReport?.domainValidation && typeof postureReport.domainValidation === 'object'
    ? postureReport.domainValidation
    : {};
  if (REQUIRED_VALIDATION_DOMAINS.some((domain) => domainValidation[domain] !== 'human-validated')) {
    reviewReasons.push('DOMAIN_VALIDATION_INCOMPLETE');
  }
  if (uncertainty > 0.25) reviewReasons.push('MODEL_UNCERTAINTY_HIGH');
  if (riskScore >= 40 || ['yellow', 'red'].includes(candidateLevel)) reviewReasons.push('POSTURE_FEATURES_REQUIRE_REVIEW');

  if (reviewReasons.length) return {
    route: BodyScreeningRoute.PROFESSIONAL_REVIEW,
    outcomeLevel: riskScore >= 70 || candidateLevel === 'red'
      ? BodyScreeningOutcomeLevel.PROFESSIONAL_EVALUATION
      : BodyScreeningOutcomeLevel.SCHOOL_RETEST,
    reasonCodes: [...new Set(reviewReasons)],
    reviewRequired: true,
    decisionPolicyVersion: BODY_SCREENING_DECISION_POLICY_VERSION
  };

  return {
    route: BodyScreeningRoute.AUTO_ARCHIVE,
    outcomeLevel: riskScore >= 20
      ? BodyScreeningOutcomeLevel.TRAINING_OBSERVATION
      : BodyScreeningOutcomeLevel.NO_OBVIOUS_ABNORMALITY,
    reasonCodes: ['QUALITY_AND_MODEL_GATE_PASSED'],
    reviewRequired: false,
    decisionPolicyVersion: BODY_SCREENING_DECISION_POLICY_VERSION
  };
}
