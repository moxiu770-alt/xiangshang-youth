package com.xiangshang.youth.feature.parent

import com.xiangshang.youth.core.model.BodyCaptureTask
import com.xiangshang.youth.core.model.CaptureCalibrationEvidence
import com.xiangshang.youth.core.model.PostureMetricCalculator
import com.xiangshang.youth.core.model.PostureMetricSnapshot
import com.xiangshang.youth.core.model.robustRange

internal fun makePostureSnapshot(
    task: BodyCaptureTask,
    metricSamples: List<PoseMetricSample>,
    dynamicRepetitionCount: Int,
    front: Boolean,
    requiresBilateralPhases: Boolean
): PostureMetricSnapshot {
    val gaitShoulder = PostureMetricCalculator.robustRange(metricSamples.map { it.shoulderHeightDifferenceCm })
    val gaitPelvic = PostureMetricCalculator.robustRange(metricSamples.map { it.pelvicHeightDifferenceCm })
    val gaitSway = PostureMetricCalculator.robustRange(metricSamples.map { it.spinalMidlineDeviationCm })

    return PostureMetricSnapshot(
        id = "${task.name}-${System.currentTimeMillis()}",
        task = task,
        sampleCount = metricSamples.size,
        confidence = PostureMetricCalculator.robustMedian(metricSamples.map { it.confidence }) ?: 0.0,
        shoulderHeightDifferenceCm = PostureMetricCalculator.robustMedian(metricSamples.map { it.shoulderHeightDifferenceCm }),
        pelvicHeightDifferenceCm = PostureMetricCalculator.robustMedian(metricSamples.map { it.pelvicHeightDifferenceCm }),
        headTiltDegrees = PostureMetricCalculator.robustMedian(metricSamples.map { it.headTiltDegrees }),
        spinalMidlineDeviationCm = PostureMetricCalculator.robustMedian(metricSamples.map { it.spinalMidlineDeviationCm }),
        thoracicRoundingDegrees = PostureMetricCalculator.robustMedian(metricSamples.map { it.thoracicRoundingDegrees }),
        forwardHeadAngleDegrees = PostureMetricCalculator.robustMedian(metricSamples.map { it.forwardHeadAngleDegrees }),
        // ATR/rib prominence is intentionally unavailable from this
        // 2D RGB stream; do not synthesize a number from landmarks.
        cameraProxyAtrDegrees = null,
        cameraProxyRibProminenceCm = null,
        shoulderProtractionProxyDegrees = if (task == BodyCaptureTask.StandingSide) PostureMetricCalculator.robustMedian(metricSamples.map { it.forwardHeadAngleDegrees }) else null,
        pelvicTiltProxyDegrees = if (task == BodyCaptureTask.StandingSide) PostureMetricCalculator.robustMedian(metricSamples.map { it.thoracicRoundingDegrees }) else null,
        kneeAlignmentProxyRatio = if (task == BodyCaptureTask.StandingFront) PostureMetricCalculator.robustMedian(metricSamples.map { it.kneeAlignmentProxyRatio }) else null,
        lowerLimbAxisAsymmetryDegrees = if (task == BodyCaptureTask.StandingFront) PostureMetricCalculator.robustMedian(metricSamples.map { it.lowerLimbAxisAsymmetryDegrees }) else null,
        leftKneeValgusProxyDegrees = if (task == BodyCaptureTask.DynamicKneeControl) PostureMetricCalculator.robustMedian(metricSamples.map { it.leftKneeValgusProxyDegrees }) else null,
        rightKneeValgusProxyDegrees = if (task == BodyCaptureTask.DynamicKneeControl) PostureMetricCalculator.robustMedian(metricSamples.map { it.rightKneeValgusProxyDegrees }) else null,
        kneeTrackingAsymmetryRatio = if (task == BodyCaptureTask.DynamicKneeControl) PostureMetricCalculator.robustMedian(metricSamples.map { kotlin.math.abs(it.kneeAlignmentProxyRatio) }) else null,
        squatDepthRatio = if (task == BodyCaptureTask.DynamicKneeControl) PostureMetricCalculator.robustMedian(metricSamples.map { it.squatDepthRatio }) else null,
        movementRepetitionCount = if (task == BodyCaptureTask.DynamicKneeControl) dynamicRepetitionCount.toDouble() else null,
        footArchVisibilityScore = if (task == BodyCaptureTask.FootArch) PostureMetricCalculator.robustMedian(metricSamples.map { it.footArchVisibilityScore }) else null,
        leftArchProxyIndex = null,
        rightArchProxyIndex = null,
        heelAlignmentProxyDegrees = if (task == BodyCaptureTask.FootArch) PostureMetricCalculator.robustMedian(metricSamples.map { it.heelAlignmentProxyDegrees }) else null,
        gaitShoulderSwingDifferenceCm = if (task == BodyCaptureTask.GaitVideo) gaitShoulder else null,
        gaitPelvicSwingDifferenceCm = if (task == BodyCaptureTask.GaitVideo) gaitPelvic else null,
        gaitTrunkSwayCm = if (task == BodyCaptureTask.GaitVideo) gaitSway else null,
        captureProtocolVersion = "UY-CAPTURE-GUIDED-3.0",
        cameraFacing = if (front) "front-preview" else "rear-1x",
        measurementMode = "rgb-pose-2d",
        deviceCapabilityTier = "standard-2d",
        depthAvailable = false,
        segmentPhaseCount = if (requiresBilateralPhases) 2 else 1,
        qualityChecks = (if (task == BodyCaptureTask.FootArch) {
            listOf("device-level", "foot-close-up", "lower-limb-landmarks", "single-person", "landmark-confidence", "multi-frame-robust")
        } else {
            listOf("device-level", "full-body", "single-person", "landmark-confidence", "multi-frame-robust")
        }) + if (task == BodyCaptureTask.DynamicKneeControl) listOf("three-repetition-cycle") else emptyList(),
        captureCalibration = CaptureCalibrationEvidence(),
        captureAttemptCount = 1,
        repeatabilityStatus = "awaiting-second-take"
    )
}
