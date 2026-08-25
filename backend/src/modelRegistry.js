/**
 * Single audit manifest for every deterministic model family shipped in the
 * first release. These identifiers describe executable policy, not a claim
 * of clinical or real-world accuracy.
 */
export const MODEL_REGISTRY_VERSION = 'UY-MODELS-1.0';
export const MODEL_REGISTRY = Object.freeze({
  movement: Object.freeze({ algorithmVersion: 'UY-IMCA-SCORE-1.3', calibrationVersion: 'UY-CAL-BASELINE-1.0', status: 'pending-human-validation' }),
  posture: Object.freeze({ algorithmVersion: 'UY-IMCA-CV-1.3', sourceVersion: 'android-v1-search-calibrated-2026-09-15', rulesSourceVersion: 'UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20', calibrationVersion: 'UY-CAL-BASELINE-1.0', status: 'pending-human-validation' }),
  bmi: Object.freeze({ algorithmVersion: 'UY-IMCA-BMI-1.2', ruleVersion: 'WS/T 586—2018 年龄别 BMI 参考 v1.1', calibrationVersion: 'UY-CAL-BASELINE-1.0', status: 'pending-human-validation' }),
  height: Object.freeze({ algorithmVersion: 'UY-IMCA-HEIGHT-1.0', ruleVersion: 'WS/T 612—2018', calibrationVersion: 'UY-CAL-BASELINE-1.0', status: 'pending-human-validation' }),
  followAlong: Object.freeze({ algorithmVersion: 'UY-FOLLOW-CV-1.0', sourceVersion: 'android-child-precision-2026-09-16-child-motion-research-v4.1', calibrationVersion: 'UY-CAL-BASELINE-1.0', status: 'pending-human-validation' }),
  growth: Object.freeze({ algorithmVersion: 'UY-GROWTH-RULE-1.1', calibrationVersion: 'UY-CAL-BASELINE-1.0', status: 'pending-human-validation' })
});

export function modelManifest() {
  return { version: MODEL_REGISTRY_VERSION, models: MODEL_REGISTRY };
}
