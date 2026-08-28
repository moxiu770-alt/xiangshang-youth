package com.xiangshang.youth.feature.parent

internal data class PoseMetricSample(
    val confidence: Double,
    val shoulderHeightDifferenceCm: Double,
    val pelvicHeightDifferenceCm: Double,
    val headTiltDegrees: Double,
    val spinalMidlineDeviationCm: Double,
    val thoracicRoundingDegrees: Double,
    val forwardHeadAngleDegrees: Double,
    val forwardBendCompletionScore: Double,
    val kneeAlignmentProxyRatio: Double,
    val lowerLimbAxisAsymmetryDegrees: Double,
    val leftKneeValgusProxyDegrees: Double,
    val rightKneeValgusProxyDegrees: Double,
    val squatDepthRatio: Double,
    val footArchVisibilityScore: Double,
    val heelAlignmentProxyDegrees: Double
)
