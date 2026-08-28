package com.xiangshang.youth.core.model

/**
 * Geometry provenance only. It never contains camera frames, photos, video
 * or raw landmarks. The current app emits Guided; MarkerPnp is reserved for
 * the physical board detector and needs a server-approved profile.
 */
enum class CaptureCalibrationMode(val wireValue: String) {
    Guided("guided"),
    MarkerPnp("marker-pnp")
}

data class CaptureCalibrationEvidence(
    val mode: CaptureCalibrationMode = CaptureCalibrationMode.Guided,
    val boardDetected: Boolean = false,
    val boardId: String? = null,
    val intrinsicsId: String? = null,
    val lensId: String? = null,
    val resolution: String? = null,
    val reprojectionErrorPx: Double? = null,
    /** Backend-approved camera/lens/resolution calibration profile. */
    val profileId: String? = null
) {
    val hasMarkerPnPEvidence: Boolean
        get() = mode == CaptureCalibrationMode.MarkerPnp && boardDetected
            && !boardId.isNullOrBlank() && !intrinsicsId.isNullOrBlank()
            && !lensId.isNullOrBlank() && !resolution.isNullOrBlank() && !profileId.isNullOrBlank()
            && (reprojectionErrorPx ?: Double.POSITIVE_INFINITY) <= 2.0
}

/** Engineering consistency gate, not a health or diagnostic conclusion. */
object PostureCaptureRepeatability {
    data class Result(val passed: Boolean, val maximumDifference: Double, val comparedMetricCount: Int)

    fun verify(first: PostureMetricSnapshot, second: PostureMetricSnapshot): Result {
        if (first.task != second.task) return Result(false, Double.POSITIVE_INFINITY, 0)
        val pairs = listOf(
            Triple(first.shoulderHeightDifferenceCm, second.shoulderHeightDifferenceCm, .8),
            Triple(first.pelvicHeightDifferenceCm, second.pelvicHeightDifferenceCm, .8),
            Triple(first.spinalMidlineDeviationCm, second.spinalMidlineDeviationCm, .8),
            Triple(first.gaitShoulderSwingDifferenceCm, second.gaitShoulderSwingDifferenceCm, .8),
            Triple(first.gaitPelvicSwingDifferenceCm, second.gaitPelvicSwingDifferenceCm, .8),
            Triple(first.gaitTrunkSwayCm, second.gaitTrunkSwayCm, .8),
            Triple(first.headTiltDegrees, second.headTiltDegrees, 3.0),
            Triple(first.thoracicRoundingDegrees, second.thoracicRoundingDegrees, 3.0),
            Triple(first.forwardHeadAngleDegrees, second.forwardHeadAngleDegrees, 3.0)
            ,Triple(first.kneeAlignmentProxyRatio, second.kneeAlignmentProxyRatio, .12)
            ,Triple(first.leftKneeValgusProxyDegrees, second.leftKneeValgusProxyDegrees, 4.0)
            ,Triple(first.rightKneeValgusProxyDegrees, second.rightKneeValgusProxyDegrees, 4.0)
            ,Triple(first.footArchVisibilityScore, second.footArchVisibilityScore, .15)
        ).mapNotNull { (a, b, limit) ->
            if (a != null && b != null && a.isFinite() && b.isFinite()) kotlin.math.abs(a - b) to limit else null
        }
        val maximum = pairs.maxOfOrNull { it.first } ?: Double.POSITIVE_INFINITY
        return Result(pairs.size >= 3 && pairs.all { it.first <= it.second }, maximum, pairs.size)
    }

    /** Fuses two accepted independent takes; no missing measurement is invented. */
    fun merged(first: PostureMetricSnapshot, second: PostureMetricSnapshot, result: Result): PostureMetricSnapshot {
        fun mean(a: Double?, b: Double?): Double? = when {
            a != null && a.isFinite() && b != null && b.isFinite() -> (a + b) / 2.0
            a != null && a.isFinite() -> a
            b != null && b.isFinite() -> b
            else -> null
        }
        return second.copy(
            sampleCount = first.sampleCount + second.sampleCount,
            confidence = (first.confidence + second.confidence) / 2.0,
            shoulderHeightDifferenceCm = mean(first.shoulderHeightDifferenceCm, second.shoulderHeightDifferenceCm),
            pelvicHeightDifferenceCm = mean(first.pelvicHeightDifferenceCm, second.pelvicHeightDifferenceCm),
            headTiltDegrees = mean(first.headTiltDegrees, second.headTiltDegrees),
            spinalMidlineDeviationCm = mean(first.spinalMidlineDeviationCm, second.spinalMidlineDeviationCm),
            thoracicRoundingDegrees = mean(first.thoracicRoundingDegrees, second.thoracicRoundingDegrees),
            forwardHeadAngleDegrees = mean(first.forwardHeadAngleDegrees, second.forwardHeadAngleDegrees),
            cameraProxyAtrDegrees = mean(first.cameraProxyAtrDegrees, second.cameraProxyAtrDegrees),
            cameraProxyRibProminenceCm = mean(first.cameraProxyRibProminenceCm, second.cameraProxyRibProminenceCm),
            shoulderProtractionProxyDegrees = mean(first.shoulderProtractionProxyDegrees, second.shoulderProtractionProxyDegrees),
            pelvicTiltProxyDegrees = mean(first.pelvicTiltProxyDegrees, second.pelvicTiltProxyDegrees),
            kneeAlignmentProxyRatio = mean(first.kneeAlignmentProxyRatio, second.kneeAlignmentProxyRatio),
            lowerLimbAxisAsymmetryDegrees = mean(first.lowerLimbAxisAsymmetryDegrees, second.lowerLimbAxisAsymmetryDegrees),
            leftKneeValgusProxyDegrees = mean(first.leftKneeValgusProxyDegrees, second.leftKneeValgusProxyDegrees),
            rightKneeValgusProxyDegrees = mean(first.rightKneeValgusProxyDegrees, second.rightKneeValgusProxyDegrees),
            kneeTrackingAsymmetryRatio = mean(first.kneeTrackingAsymmetryRatio, second.kneeTrackingAsymmetryRatio),
            squatDepthRatio = mean(first.squatDepthRatio, second.squatDepthRatio),
            movementRepetitionCount = mean(first.movementRepetitionCount, second.movementRepetitionCount),
            footArchVisibilityScore = mean(first.footArchVisibilityScore, second.footArchVisibilityScore),
            leftArchProxyIndex = mean(first.leftArchProxyIndex, second.leftArchProxyIndex),
            rightArchProxyIndex = mean(first.rightArchProxyIndex, second.rightArchProxyIndex),
            heelAlignmentProxyDegrees = mean(first.heelAlignmentProxyDegrees, second.heelAlignmentProxyDegrees),
            instrumentAtrDegrees = mean(first.instrumentAtrDegrees, second.instrumentAtrDegrees),
            thoracicAtrDegrees = mean(first.thoracicAtrDegrees, second.thoracicAtrDegrees),
            lumbarAtrDegrees = mean(first.lumbarAtrDegrees, second.lumbarAtrDegrees),
            thoracicAtrFirstDegrees = mean(first.thoracicAtrFirstDegrees, second.thoracicAtrFirstDegrees),
            thoracicAtrSecondDegrees = mean(first.thoracicAtrSecondDegrees, second.thoracicAtrSecondDegrees),
            lumbarAtrFirstDegrees = mean(first.lumbarAtrFirstDegrees, second.lumbarAtrFirstDegrees),
            lumbarAtrSecondDegrees = mean(first.lumbarAtrSecondDegrees, second.lumbarAtrSecondDegrees),
            seatedForwardBendAtrDegrees = mean(first.seatedForwardBendAtrDegrees, second.seatedForwardBendAtrDegrees),
            occiputWallDistanceCm = mean(first.occiputWallDistanceCm, second.occiputWallDistanceCm),
            gaitShoulderSwingDifferenceCm = mean(first.gaitShoulderSwingDifferenceCm, second.gaitShoulderSwingDifferenceCm),
            gaitPelvicSwingDifferenceCm = mean(first.gaitPelvicSwingDifferenceCm, second.gaitPelvicSwingDifferenceCm),
            gaitTrunkSwayCm = mean(first.gaitTrunkSwayCm, second.gaitTrunkSwayCm),
            adamsObservedResult = second.adamsObservedResult ?: first.adamsObservedResult,
            adamsProminenceSide = second.adamsProminenceSide ?: first.adamsProminenceSide,
            thoracicAtrSide = second.thoracicAtrSide ?: first.thoracicAtrSide,
            lumbarAtrSide = second.lumbarAtrSide ?: first.lumbarAtrSide,
            gaitObservedAbnormal = second.gaitObservedAbnormal ?: first.gaitObservedAbnormal,
            gaitObservationNote = second.gaitObservationNote ?: first.gaitObservationNote,
            seatedThoracicKyphosisObserved = second.seatedThoracicKyphosisObserved ?: first.seatedThoracicKyphosisObserved,
            captureProtocolVersion = second.captureProtocolVersion ?: first.captureProtocolVersion,
            cameraFacing = second.cameraFacing ?: first.cameraFacing,
            measurementMode = second.measurementMode ?: first.measurementMode,
            deviceCapabilityTier = second.deviceCapabilityTier ?: first.deviceCapabilityTier,
            depthAvailable = second.depthAvailable ?: first.depthAvailable,
            segmentPhaseCount = maxOf(first.segmentPhaseCount ?: 1, second.segmentPhaseCount ?: 1),
            qualityChecks = (first.qualityChecks.orEmpty() + second.qualityChecks.orEmpty() + "two-take-repeatability").distinct().sorted(),
            captureCalibration = second.captureCalibration ?: first.captureCalibration,
            captureAttemptCount = 2,
            repeatabilityStatus = "passed",
            repeatabilityMaximumDifference = result.maximumDifference
        )
    }
}
