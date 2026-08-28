package com.xiangshang.youth.core.model

internal object PostureEvidenceValidation {
    private fun valid(value: Double?, limit: Double): Boolean = value == null || (value.isFinite() && kotlin.math.abs(value) <= limit)
    fun validMetrics(snapshot: PostureMetricSnapshot?): Boolean {
        if (snapshot == null) return true
        return valid(snapshot.shoulderHeightDifferenceCm, 20.0) &&
            valid(snapshot.pelvicHeightDifferenceCm, 20.0) &&
            valid(snapshot.headTiltDegrees, 180.0) &&
            valid(snapshot.spinalMidlineDeviationCm, 20.0) &&
            valid(snapshot.thoracicRoundingDegrees, 180.0) &&
            valid(snapshot.forwardHeadAngleDegrees, 180.0) &&
            valid(snapshot.cameraProxyAtrDegrees, 180.0) &&
            valid(snapshot.cameraProxyRibProminenceCm, 20.0) &&
            valid(snapshot.shoulderProtractionProxyDegrees, 180.0) &&
            valid(snapshot.pelvicTiltProxyDegrees, 90.0) &&
            valid(snapshot.kneeAlignmentProxyRatio, 2.0) &&
            valid(snapshot.lowerLimbAxisAsymmetryDegrees, 90.0) &&
            valid(snapshot.leftKneeValgusProxyDegrees, 90.0) &&
            valid(snapshot.rightKneeValgusProxyDegrees, 90.0) &&
            valid(snapshot.kneeTrackingAsymmetryRatio, 3.0) &&
            valid(snapshot.squatDepthRatio, 2.0) &&
            valid(snapshot.movementRepetitionCount, 20.0) &&
            valid(snapshot.footArchVisibilityScore, 1.0) &&
            valid(snapshot.leftArchProxyIndex, 1.0) &&
            valid(snapshot.rightArchProxyIndex, 1.0) &&
            valid(snapshot.heelAlignmentProxyDegrees, 90.0) &&
            valid(snapshot.instrumentAtrDegrees, 180.0) &&
            valid(snapshot.thoracicAtrDegrees, 180.0) &&
            valid(snapshot.lumbarAtrDegrees, 180.0) &&
            valid(snapshot.thoracicAtrFirstDegrees, 180.0) &&
            valid(snapshot.thoracicAtrSecondDegrees, 180.0) &&
            valid(snapshot.lumbarAtrFirstDegrees, 180.0) &&
            valid(snapshot.lumbarAtrSecondDegrees, 180.0) &&
            valid(snapshot.seatedForwardBendAtrDegrees, 180.0) &&
            valid(snapshot.occiputWallDistanceCm, 50.0) &&
            valid(snapshot.gaitShoulderSwingDifferenceCm, 20.0) &&
            valid(snapshot.gaitPelvicSwingDifferenceCm, 20.0) &&
            valid(snapshot.gaitTrunkSwayCm, 20.0)
    }
}
