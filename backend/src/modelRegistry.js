/**
 * Single audit manifest for every deterministic model family shipped in the
 * first release. These identifiers describe executable policy, not a claim
 * of clinical or real-world accuracy.
 */
export const MODEL_REGISTRY_VERSION = 'UY-MODELS-1.1';
export const POSTURE_VALIDATION_DOMAINS = Object.freeze([
  'spinal_alignment',
  'shoulder_pelvis',
  'head_upper_posture',
  'trunk_rotation',
  'dynamic_knee',
  'gait',
  'seated_posture',
  'foot_arch'
]);

const pendingPostureDomains = Object.freeze(Object.fromEntries(
  POSTURE_VALIDATION_DOMAINS.map((domain) => [domain, 'pending-human-validation'])
));
export const MODEL_REGISTRY = Object.freeze({
  movement: Object.freeze({ algorithmVersion: 'UY-IMCA-SCORE-1.3', calibrationVersion: 'UY-CAL-BASELINE-1.0', status: 'pending-human-validation' }),
  posture: Object.freeze({
    algorithmVersion: 'UY-IMCA-CV-1.3',
    sourceVersion: 'android-v3-adams-repeatability-2026-08-27',
    rulesSourceVersion: 'UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20',
    calibrationVersion: 'UY-CAL-BASELINE-1.0',
    status: 'pending-human-validation',
    domainValidation: pendingPostureDomains
  }),
  bmi: Object.freeze({ algorithmVersion: 'UY-IMCA-BMI-1.2', ruleVersion: 'WS/T 586—2018 年龄别 BMI 参考 v1.1', calibrationVersion: 'UY-CAL-BASELINE-1.0', status: 'pending-human-validation' }),
  height: Object.freeze({ algorithmVersion: 'UY-IMCA-HEIGHT-1.0', ruleVersion: 'WS/T 612—2018', calibrationVersion: 'UY-CAL-BASELINE-1.0', status: 'pending-human-validation' }),
  followAlong: Object.freeze({ algorithmVersion: 'UY-FOLLOW-CV-1.0', sourceVersion: 'android-child-precision-2026-09-16-child-motion-research-v4.1', calibrationVersion: 'UY-CAL-BASELINE-1.0', status: 'pending-human-validation' }),
  growth: Object.freeze({ algorithmVersion: 'UY-GROWTH-RULE-1.1', calibrationVersion: 'UY-CAL-BASELINE-1.0', status: 'pending-human-validation' })
});

export function postureClassificationIsPublished() {
  return MODEL_REGISTRY.posture.status === 'human-validated'
    && POSTURE_VALIDATION_DOMAINS.every(
      (domain) => MODEL_REGISTRY.posture.domainValidation?.[domain] === 'human-validated'
    );
}

export function modelManifest() {
  return { version: MODEL_REGISTRY_VERSION, models: MODEL_REGISTRY };
}
