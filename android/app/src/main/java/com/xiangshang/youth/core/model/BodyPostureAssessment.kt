package com.xiangshang.youth.core.model

/** Aggregated normalized pose geometry. Raw camera frames are never stored. */
data class PostureMetricSnapshot(
    val id: String,
    val task: BodyCaptureTask,
    val sampleCount: Int,
    val confidence: Double,
    val shoulderHeightDifferenceCm: Double? = null,
    val pelvicHeightDifferenceCm: Double? = null,
    val headTiltDegrees: Double? = null,
    val spinalMidlineDeviationCm: Double? = null,
    val thoracicRoundingDegrees: Double? = null,
    val forwardHeadAngleDegrees: Double? = null,
    val cameraProxyAtrDegrees: Double? = null,
    val cameraProxyRibProminenceCm: Double? = null,
    val shoulderProtractionProxyDegrees: Double? = null,
    val pelvicTiltProxyDegrees: Double? = null,
    val kneeAlignmentProxyRatio: Double? = null,
    val lowerLimbAxisAsymmetryDegrees: Double? = null,
    val leftKneeValgusProxyDegrees: Double? = null,
    val rightKneeValgusProxyDegrees: Double? = null,
    val kneeTrackingAsymmetryRatio: Double? = null,
    val squatDepthRatio: Double? = null,
    val movementRepetitionCount: Double? = null,
    /** Quality-only until a dedicated paediatric foot model is validated. */
    val footArchVisibilityScore: Double? = null,
    val leftArchProxyIndex: Double? = null,
    val rightArchProxyIndex: Double? = null,
    val heelAlignmentProxyDegrees: Double? = null,
    val adamsObservedResult: String? = null,
    val adamsProminenceSide: String? = null,
    /** Optional validated ATR from a calibrated instrument/depth adapter. */
    val instrumentAtrDegrees: Double? = null,
    /** Optional calibrated chest/waist ATR readings. */
    val thoracicAtrDegrees: Double? = null,
    val lumbarAtrDegrees: Double? = null,
    val thoracicAtrSide: String? = null,
    val lumbarAtrSide: String? = null,
    val thoracicAtrFirstDegrees: Double? = null,
    val thoracicAtrSecondDegrees: Double? = null,
    val lumbarAtrFirstDegrees: Double? = null,
    val lumbarAtrSecondDegrees: Double? = null,
    val seatedForwardBendAtrDegrees: Double? = null,
    /** Optional supervised occiput-to-wall distance measurement. */
    val occiputWallDistanceCm: Double? = null,
    val gaitShoulderSwingDifferenceCm: Double? = null,
    val gaitPelvicSwingDifferenceCm: Double? = null,
    val gaitTrunkSwayCm: Double? = null,
    val gaitObservedAbnormal: Boolean? = null,
    val gaitObservationNote: String? = null,
    val seatedThoracicKyphosisObserved: Boolean? = null,
    /** Actual camera-gate provenance, not an assertion that a physical
     * marker board has already been detected. */
    val captureProtocolVersion: String? = null,
    val cameraFacing: String? = null,
    /** This describes evidence actually consumed, not hardware marketing. */
    val measurementMode: String? = null,
    val deviceCapabilityTier: String? = null,
    val depthAvailable: Boolean? = null,
    val segmentPhaseCount: Int? = null,
    val qualityChecks: List<String>? = null,
    val captureCalibration: CaptureCalibrationEvidence? = null,
    /** 1 means a usable first take exists and an independent second take is still required. */
    val captureAttemptCount: Int? = null,
    val repeatabilityStatus: String? = null,
    val repeatabilityMaximumDifference: Double? = null
) {
    val adamsResult: AdamsScreeningResult?
        get() = when (adamsObservedResult) {
            "negative" -> AdamsScreeningResult.Negative
            "equivocal" -> AdamsScreeningResult.Equivocal
            "positive" -> AdamsScreeningResult.Positive
            else -> cameraProxyRibProminenceCm?.takeIf { it.isFinite() && it >= 0.0 }?.let { when { it >= PostureScreeningRules.ribProminencePositiveCentimeters -> AdamsScreeningResult.Positive; it >= PostureScreeningRules.ribProminenceEquivocalCentimeters -> AdamsScreeningResult.Equivocal; else -> AdamsScreeningResult.Negative } }
        }
}
