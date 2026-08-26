import { POSTURE_ALGORITHM_VERSION, scorePostureSnapshots } from './postureScoring.js';
import { MODEL_CALIBRATION_VERSION } from './modelCalibration.js';
import { MODEL_REGISTRY, MODEL_REGISTRY_VERSION } from './modelRegistry.js';

export const BODY_ALGORITHM_VERSION = POSTURE_ALGORITHM_VERSION;
export const BMI_RULE_VERSION = 'WS/T 586—2018 年龄别 BMI 参考 v1.1';
export const BMI_ALGORITHM_VERSION = MODEL_REGISTRY.bmi.algorithmVersion;
export const BMI_SUPPORTED_AGE_MONTHS = Object.freeze({ min: 72, max: 216 });
export const HEIGHT_RULE_VERSION = 'WS/T 612—2018';
export const HEIGHT_ALGORITHM_VERSION = MODEL_REGISTRY.height.algorithmVersion;
export const HEIGHT_SUPPORTED_AGE_MONTHS = Object.freeze({ min: 84, max: 227 });

// Scores and BMI comparisons are non-negative. Use one explicit half-up
// rule so JavaScript, Swift and Kotlin do not disagree on .05 boundaries.
const roundHalfUp = (value, decimals) => {
  const factor = 10 ** decimals;
  return Math.floor(value * factor + 0.5) / factor;
};

export const finiteScalar = (value) => {
  if (value == null || typeof value === 'boolean' || typeof value === 'object' || typeof value === 'function' || (typeof value === 'string' && value.trim() === '')) return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

const boys = Object.freeze([[72, 16.4, 17.7], [78, 16.7, 18.1], [84, 17.0, 18.7], [90, 17.4, 19.2], [96, 17.8, 19.7], [102, 18.1, 20.3], [108, 18.5, 20.8], [114, 18.9, 21.4], [120, 19.2, 21.9], [126, 19.6, 22.5], [132, 19.9, 23.0], [138, 20.3, 23.6], [144, 20.7, 24.1], [150, 21.0, 24.7], [156, 21.4, 25.2], [162, 21.9, 25.7], [168, 22.3, 26.1], [174, 22.6, 26.4], [180, 22.9, 26.6], [186, 23.1, 26.9], [192, 23.3, 27.1], [198, 23.5, 27.4], [204, 23.7, 27.6], [210, 23.8, 27.8], [216, 24.0, 28.0]]);
const girls = Object.freeze([[72, 16.2, 17.5], [78, 16.5, 18.0], [84, 16.8, 18.5], [90, 17.2, 19.0], [96, 17.6, 19.4], [102, 18.1, 19.9], [108, 18.5, 20.4], [114, 19.0, 21.0], [120, 19.5, 21.5], [126, 20.0, 22.1], [132, 20.5, 22.7], [138, 21.1, 23.3], [144, 21.5, 23.9], [150, 21.9, 24.5], [156, 22.2, 25.0], [162, 22.6, 25.6], [168, 22.8, 25.9], [174, 23.0, 26.3], [180, 23.2, 26.6], [186, 23.4, 26.9], [192, 23.6, 27.1], [198, 23.7, 27.4], [204, 23.8, 27.6], [210, 23.9, 27.8], [216, 24.0, 28.0]]);

const heightBoys = Object.freeze({
  7: [113.51, 119.49, 125.48, 131.47, 137.46], 8: [118.35, 124.53, 130.72, 136.90, 143.08],
  9: [122.74, 129.27, 135.81, 142.35, 148.88], 10: [126.79, 133.77, 140.76, 147.75, 154.74],
  11: [130.39, 138.20, 146.01, 153.82, 161.64], 12: [134.48, 143.33, 152.18, 161.03, 169.89],
  13: [143.01, 151.60, 160.19, 168.78, 177.38], 14: [150.22, 157.93, 165.63, 173.34, 181.05],
  15: [155.25, 162.14, 169.02, 175.91, 182.79], 16: [157.72, 164.15, 170.58, 177.01, 183.44],
  17: [158.76, 165.07, 171.39, 177.70, 184.01], 18: [158.81, 165.12, 171.42, 177.73, 184.03]
});
const heightGirls = Object.freeze({
  7: [112.29, 118.21, 124.13, 130.05, 135.97], 8: [116.83, 123.09, 129.34, 135.59, 141.84],
  9: [121.31, 128.11, 134.91, 141.71, 148.51], 10: [126.38, 133.78, 141.18, 148.57, 155.97],
  11: [132.09, 139.72, 147.36, 154.99, 162.63], 12: [138.11, 145.26, 152.41, 159.56, 166.71],
  13: [143.75, 149.91, 156.07, 162.23, 168.39], 14: [146.18, 151.98, 157.78, 163.58, 169.38],
  15: [147.02, 152.74, 158.47, 164.19, 169.91], 16: [147.59, 153.26, 158.93, 164.60, 170.27],
  17: [147.82, 153.50, 159.18, 164.86, 170.54], 18: [148.54, 154.28, 160.01, 165.74, 171.48]
});

export function normalizeGender(value) {
  const gender = String(value || '').trim().toLowerCase();
  if (['男', '男性', 'boy', 'male', 'm', '1'].includes(gender)) return 'boy';
  if (['女', '女性', 'girl', 'female', 'f', '2'].includes(gender)) return 'girl';
  return null;
}

/** WS/T 586—2018 uses completed half-year age rows; no monthly interpolation. */
export function bmiAgeBucketMonths(ageMonths) {
  if (!Number.isInteger(ageMonths) || ageMonths < BMI_SUPPORTED_AGE_MONTHS.min || ageMonths > BMI_SUPPORTED_AGE_MONTHS.max) return null;
  return Math.floor(ageMonths / 6) * 6;
}

function bmiReference(ageMonths, gender) {
  if (!Number.isInteger(ageMonths) || ageMonths < BMI_SUPPORTED_AGE_MONTHS.min || ageMonths > BMI_SUPPORTED_AGE_MONTHS.max) return null;
  const table = gender === 'boy' ? boys : gender === 'girl' ? girls : null;
  if (!table) return null;
  const bucket = bmiAgeBucketMonths(ageMonths);
  const row = table.find((candidate) => candidate[0] === bucket);
  return row ? { attention: row[1], red: row[2] } : null;
}

export function bmiAttention({ bmi, ageMonths, gender }) {
  const rawValue = finiteScalar(bmi);
  // WS/T 586 comparison uses BMI rounded to one decimal. Keep the stored
  // value at two decimals for reporting, but never compare an unrounded value
  // or the native clients will disagree at a threshold boundary.
  const value = rawValue != null && rawValue > 0 ? roundHalfUp(rawValue, 1) : 0;
  const normalizedGender = normalizeGender(gender);
  const row = bmiReference(ageMonths, normalizedGender);
  if (!Number.isFinite(value) || value <= 0 || !row) return 'unavailable';
  if (value >= row.red) return 'red';
  if (value >= row.attention) return 'yellow';
  return 'green';
}

export function heightDevelopment({ heightCm, ageMonths, gender }) {
  const height = finiteScalar(heightCm);
  const normalizedGender = normalizeGender(gender);
  if (height == null || height < 90 || height > 190 || !Number.isInteger(ageMonths) || ageMonths < HEIGHT_SUPPORTED_AGE_MONTHS.min || ageMonths > HEIGHT_SUPPORTED_AGE_MONTHS.max || !normalizedGender) return null;
  const ageYears = Math.min(18, Math.max(7, Math.floor(ageMonths / 12)));
  const row = (normalizedGender === 'boy' ? heightBoys : heightGirls)[ageYears];
  if (!row) return null;
  const [minusTwoSD, minusOneSD, median, plusOneSD, plusTwoSD] = row;
  const level = height < minusTwoSD ? 'low' : height < minusOneSD ? 'lower' : height <= plusOneSD ? 'middle' : height <= plusTwoSD ? 'upper' : 'high';
  return { ageYears, heightCm: height, level, lowerTwoSD: minusTwoSD, lowerOneSD: minusOneSD, median, upperOneSD: plusOneSD, upperTwoSD: plusTwoSD, ruleVersion: HEIGHT_RULE_VERSION };
}

export function combineBodyLevel(postureLevel, bmiLevel) {
  const validLevels = new Set(['green', 'yellow', 'red', 'pending', 'unavailable']);
  if (!validLevels.has(postureLevel) || !validLevels.has(bmiLevel)) return 'unavailable';
  if (postureLevel === 'red' || bmiLevel === 'red') return 'red';
  if (postureLevel === 'yellow' || bmiLevel === 'yellow') return 'yellow';
  if (postureLevel === 'pending') return 'pending';
  if (postureLevel === 'unavailable' || bmiLevel === 'unavailable') return 'unavailable';
  return 'green';
}

export function scoreBodyAssessment({ heightCm, weightKg, ageMonths, gender, snapshots }) {
  const height = finiteScalar(heightCm);
  const weight = finiteScalar(weightKg);
  // Keep the server's physical input gate aligned with both native clients.
  // A malformed height/weight pair must become unavailable, never an extreme
  // BMI that accidentally publishes a red result.
  const validMeasurements = height != null && height >= 90 && height <= 190
    && weight != null && weight >= 15 && weight <= 90;
  const rawBmi = validMeasurements ? weight / ((height / 100) ** 2) : 0;
  const bmi = Number.isFinite(rawBmi) ? roundHalfUp(rawBmi, 2) : 0;
  const postureReport = scorePostureSnapshots(snapshots, ageMonths);
  // Compare the unrounded mathematical BMI after the canonical one-decimal
  // screening rule. The two-decimal `bmi` field is display/storage only.
  const bmiLevel = bmiAttention({ bmi: rawBmi, ageMonths, gender });
  const bmiAgeBucket = bmiAgeBucketMonths(ageMonths);
  const heightReport = heightDevelopment({ heightCm: height, ageMonths, gender });
  return {
    algorithm: BODY_ALGORITHM_VERSION,
    calibrationVersion: MODEL_CALIBRATION_VERSION,
    ageMonths: Number.isInteger(ageMonths) ? ageMonths : null,
    bmi,
    bmiAlgorithmVersion: BMI_ALGORITHM_VERSION,
    bmiAgeBucketMonths: bmiAgeBucket,
    bmiLevel,
    bmiRuleVersion: BMI_RULE_VERSION,
    heightReport,
    heightAlgorithmVersion: HEIGHT_ALGORITHM_VERSION,
    modelRegistryVersion: MODEL_REGISTRY_VERSION,
    overallLevel: combineBodyLevel(postureReport.overallLevel, bmiLevel),
    postureReport
  };
}
