/**
 * Versioned calibration manifest for the frozen rule models.
 *
 * This baseline is intentionally marked pending-human-validation. It records
 * which parameters are in production code and prevents a future threshold
 * edit from being mistaken for a validated recalibration. A release may only
 * move the status to validated after an independent labelled-set report has
 * been reviewed and the dataset id/checksum is recorded.
 */
export const MODEL_CALIBRATION_VERSION = 'UY-CAL-BASELINE-1.0';
export const MODEL_CALIBRATION_STATUS = 'pending-human-validation';
export const MODEL_CALIBRATION_DATASET_ID = null;

export const MODEL_CALIBRATION = Object.freeze({
  version: MODEL_CALIBRATION_VERSION,
  status: MODEL_CALIBRATION_STATUS,
  datasetId: MODEL_CALIBRATION_DATASET_ID,
  parameters: Object.freeze({
    movementReviewConfidence: 0.80,
    movementDuplicateConflictThreshold: 1.5,
    postureMinimumConfidence: 0.56,
    bmiComparisonDecimals: 1,
    ageCalendar: 'Asia/Shanghai'
  })
});
