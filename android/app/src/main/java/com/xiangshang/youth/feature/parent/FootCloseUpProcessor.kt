package com.xiangshang.youth.feature.parent

import android.os.SystemClock
import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseLandmark
import com.xiangshang.youth.core.model.BodyCaptureQualityGate
import com.xiangshang.youth.core.model.BodyCaptureTask
import com.xiangshang.youth.core.model.PostureMetricCalculator
import com.xiangshang.youth.core.model.PostureMetricSnapshot
import com.xiangshang.youth.core.model.staticProgress
import java.util.ArrayDeque

/** Isolated lower-leg capture state; it deliberately does not require head or torso landmarks. */
internal class FootCloseUpProcessor(
    private val front: Boolean,
    private val childAgeMonths: Int?,
    private val onPrompt: (String) -> Unit,
    private val onProgress: (Float) -> Unit,
    private val onAlignment: (CaptureBodyAlignment) -> Unit,
    private val onComplete: (CaptureAnalysis) -> Unit,
    private val isCaptureArmed: () -> Boolean
) {
    private var stableFrames = 0
    private var stableSince = 0L
    private var firstHipX: Double? = null
    private var firstHipY: Double? = null
    private var finished = false
    private var segmentPhaseIndex = 0
    private val metricSamples = mutableListOf<PoseMetricSample>()
    private val completedPhaseSamples = mutableListOf<PoseMetricSample>()
    private val displacementWindow = ArrayDeque<Double>()

    private fun profile() = BodyCaptureQualityGate.profileForAge(childAgeMonths)
    private fun publishProgress(value: Float) = onProgress((segmentPhaseIndex + value.coerceIn(0f, 1f)) / 2f)
    private fun <T> ArrayDeque<T>.pushLimited(value: T, maxSize: Int) {
        addLast(value)
        while (size > maxSize) removeFirst()
    }
    private fun resetCaptureState(clearHint: Boolean = true) {
        stableFrames = 0
        stableSince = 0L
        firstHipX = null
        firstHipY = null
        metricSamples.clear()
        displacementWindow.clear()
        if (clearHint) publishProgress(0f)
    }
    private fun median(values: List<Double>) = PostureMetricCalculator.median(values)
    private fun mad(values: List<Double>): Double = PostureMetricCalculator.medianAbsoluteDeviation(values) ?: 0.0
    private fun makeSnapshot(): PostureMetricSnapshot = makePostureSnapshot(
        BodyCaptureTask.FootArch, metricSamples, 0, front, true
    )

    fun process(pose: Pose, imageWidth: Int, imageHeight: Int): Boolean {
        val leftKnee = pose.getPoseLandmark(PoseLandmark.LEFT_KNEE)
        val rightKnee = pose.getPoseLandmark(PoseLandmark.RIGHT_KNEE)
        val leftAnkle = pose.getPoseLandmark(PoseLandmark.LEFT_ANKLE)
        val rightAnkle = pose.getPoseLandmark(PoseLandmark.RIGHT_ANKLE)
        val leftHeel = pose.getPoseLandmark(PoseLandmark.LEFT_HEEL)
        val rightHeel = pose.getPoseLandmark(PoseLandmark.RIGHT_HEEL)
        val leftFoot = pose.getPoseLandmark(PoseLandmark.LEFT_FOOT_INDEX)
        val rightFoot = pose.getPoseLandmark(PoseLandmark.RIGHT_FOOT_INDEX)
        val required = listOf(leftKnee, rightKnee, leftAnkle, rightAnkle, leftHeel, rightHeel)
        val confidences = required.map { it?.inFrameLikelihood ?: 0f }
        if (!BodyCaptureQualityGate.hasReliableLandmarks(confidences, childAgeMonths) || required.any { it == null }) {
            resetCaptureState(false)
            onAlignment(CaptureBodyAlignment())
            onPrompt("请只拍摄膝部以下，让双膝、双踝、足跟和双脚完整进入近景框。")
            return true
        }
        val lk = leftKnee ?: return true
        val rk = rightKnee ?: return true
        val lh = leftHeel ?: return true
        val rh = rightHeel ?: return true
        val frameWidth = imageWidth.coerceAtLeast(1).toDouble()
        val frameHeight = imageHeight.coerceAtLeast(1).toDouble()
        val kneeCenterX = (lk.position.x + rk.position.x) / 2.0
        val kneeCenterY = (lk.position.y + rk.position.y) / 2.0
        val footPoints = listOfNotNull(leftFoot, rightFoot, lh, rh)
        val footCenterX = footPoints.map { it.position.x.toDouble() }.average()
        val footCenterY = footPoints.map { it.position.y.toDouble() }.average()
        val lowerLegCoverage = kotlin.math.abs(kneeCenterY - footCenterY) / frameHeight
        val scaleState = BodyCaptureQualityGate.footScaleState(lowerLegCoverage)
        val lowerBodyCenterX = ((kneeCenterX + footCenterX) / 2.0) / frameWidth
        val centered = lowerBodyCenterX in .34..0.66
        val jointsReady = centered && scaleState == BodyCaptureQualityGate.BodyScaleState.Ready
        onAlignment(CaptureBodyAlignment(true, scaleState, centered, true, true, true, jointsReady, jointsReady))
        when (scaleState) {
            BodyCaptureQualityGate.BodyScaleState.TooFar -> {
                resetCaptureState(); onPrompt("足部画面太小，请把手机移近半步，保持膝部以下完整入镜。")
                return true
            }
            BodyCaptureQualityGate.BodyScaleState.TooClose -> {
                resetCaptureState(); onPrompt("足部画面过近，请把手机后移半步，让双膝到双脚都在近景框内。")
                return true
            }
            BodyCaptureQualityGate.BodyScaleState.Invalid -> {
                resetCaptureState(); onPrompt("暂时无法判断足部取景距离，请保持手机竖直并重新对准双脚。")
                return true
            }
            BodyCaptureQualityGate.BodyScaleState.Ready -> Unit
        }
        if (!centered) {
            resetCaptureState(); onPrompt("请将双膝和双脚整体移到近景框中央。")
            return true
        }
        if (!isCaptureArmed()) {
            resetCaptureState(); onPrompt("足部近景已就绪，请确认赤足站稳后点击开始记录。")
            return true
        }

        val centerX = (kneeCenterX + footCenterX) / 2.0 / frameWidth
        val centerY = (kneeCenterY + footCenterY) / 2.0 / frameHeight
        if (firstHipX == null) { firstHipX = centerX; firstHipY = centerY }
        val displacement = kotlin.math.hypot(centerX - (firstHipX ?: centerX), centerY - (firstHipY ?: centerY))
        val leftHeelLine = kotlin.math.atan2(kotlin.math.abs(lk.position.x - lh.position.x).toDouble(), kotlin.math.abs(lk.position.y - lh.position.y).toDouble().coerceAtLeast(.001)) * 180 / Math.PI
        val rightHeelLine = kotlin.math.atan2(kotlin.math.abs(rk.position.x - rh.position.x).toDouble(), kotlin.math.abs(rk.position.y - rh.position.y).toDouble().coerceAtLeast(.001)) * 180 / Math.PI
        val visibleFootConfidence = listOfNotNull(leftFoot?.inFrameLikelihood, rightFoot?.inFrameLikelihood, lh.inFrameLikelihood, rh.inFrameLikelihood).average()
        metricSamples += PoseMetricSample(
            confidence = confidences.average(),
            shoulderHeightDifferenceCm = 0.0,
            pelvicHeightDifferenceCm = 0.0,
            headTiltDegrees = 0.0,
            spinalMidlineDeviationCm = 0.0,
            thoracicRoundingDegrees = 0.0,
            forwardHeadAngleDegrees = 0.0,
            forwardBendCompletionScore = 0.0,
            kneeAlignmentProxyRatio = 0.0,
            lowerLimbAxisAsymmetryDegrees = kotlin.math.abs(leftHeelLine - rightHeelLine),
            leftKneeValgusProxyDegrees = 0.0,
            rightKneeValgusProxyDegrees = 0.0,
            squatDepthRatio = 0.0,
            footArchVisibilityScore = visibleFootConfidence,
            heelAlignmentProxyDegrees = (leftHeelLine + rightHeelLine) / 2.0
        )
        val gate = profile()
        displacementWindow.pushLimited(displacement, gate.stabilityWindowFrames)
        val stableDisplacement = median(displacementWindow.toList()) ?: displacement
        val jitter = mad(displacementWindow.toList())
        if (stableDisplacement >= gate.staticMaximumDisplacementRatio || jitter > gate.staticDisplacementJitterRatio) {
            resetCaptureState(); firstHipX = centerX; firstHipY = centerY
            onPrompt("请让孩子双脚平行站稳，并固定手机等待画面稳定。")
            return true
        }
        stableFrames++
        if (stableSince == 0L) stableSince = SystemClock.elapsedRealtime()
        val elapsed = SystemClock.elapsedRealtime() - stableSince
        val remaining = kotlin.math.max(0, kotlin.math.ceil(gate.staticHoldMilliseconds / 1000.0 - elapsed / 1000.0).toInt())
        onPrompt(if (remaining > 0) "足部近景稳定，请保持${remaining}秒。" else "本侧足部记录完成，请保持不动。")
        publishProgress(BodyCaptureQualityGate.staticProgress(elapsed, childAgeMonths))
        val enough = BodyCaptureQualityGate.staticReady(elapsed, stableFrames, stableDisplacement, jitter, childAgeMonths) && metricSamples.size >= gate.minimumRawSamplesForCompletion
        if (!enough || finished) return true
        if (segmentPhaseIndex == 0) {
            completedPhaseSamples.clear(); completedPhaseSamples.addAll(metricSamples)
            segmentPhaseIndex = 1; resetCaptureState()
            onPrompt("左足近景完成。请调整站位，让右足内侧和足跟对准近景框后再次记录。")
            return true
        }
        if (completedPhaseSamples.isNotEmpty()) metricSamples.addAll(0, completedPhaseSamples)
        finished = true
        onProgress(1f)
        onComplete(CaptureAnalysis(true, "双侧足部近景记录完成。", "当前仅形成足部画面质量和足跟投影记录，不输出足弓诊断。", makeSnapshot()))
        return true
    }
}
