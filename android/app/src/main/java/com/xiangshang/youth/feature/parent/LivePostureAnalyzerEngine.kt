package com.xiangshang.youth.feature.parent

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.SystemClock
import android.provider.Settings
import android.speech.tts.TextToSpeech
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions
import com.xiangshang.youth.core.model.BodyCaptureQualityGate
import com.xiangshang.youth.core.model.BodyCaptureTask
import com.xiangshang.youth.core.model.PostureMetricCalculator
import com.xiangshang.youth.core.model.PostureMetricSnapshot
import com.xiangshang.youth.core.model.CaptureCalibrationEvidence
import com.xiangshang.youth.core.model.adamsForwardBendCompletionScore
import com.xiangshang.youth.core.model.gaitProgress
import com.xiangshang.youth.core.model.hasAdamsLowerBodyPosition
import com.xiangshang.youth.core.model.jointAngle
import com.xiangshang.youth.core.model.robustRange
import com.xiangshang.youth.core.model.staticProgress
import java.util.ArrayDeque
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

internal fun bindLiveCameraEngine(
    context: Context,
    lifecycleOwner: androidx.lifecycle.LifecycleOwner,
    previewView: PreviewView,
    front: Boolean,
    task: BodyCaptureTask,
    measuredHeightCm: Double,
    detector: PoseDetector,
    onPrompt: (String) -> Unit,
    onProgress: (Float) -> Unit,
    onReady: (Boolean) -> Unit,
    onAlignment: (CaptureBodyAlignment) -> Unit,
    onFailure: (String) -> Unit,
    onComplete: (CaptureAnalysis) -> Unit,
    analysisExecutor: ExecutorService,
    childAgeMonths: Int?,
    isCurrent: () -> Boolean,
    isCaptureArmed: () -> Boolean
) {
    val future = ProcessCameraProvider.getInstance(context)
    future.addListener({
        if (!isCurrent()) return@addListener

        val provider = runCatching { future.get() }.getOrElse {
            if (isCurrent()) {
                onProgress(0f)
                onReady(false)
                onAlignment(CaptureBodyAlignment())
                onFailure("相机服务暂不可用，请稍后重试。")
            }
            return@addListener
        }

        if (!isCurrent()) return@addListener
        val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
        var stableFrames = 0
        var stableSince = 0L
        // Keep the stability anchor in the same normalized Double precision
        // as the roll-corrected landmarks. Mixing Float and Double here
        // silently loses precision on small movements and made the two
        // native implementations disagree near the stability threshold.
        var firstHipX: Double? = null
        var firstHipY: Double? = null
        var finished = false
        var dynamicRepetitionCount = 0
        var dynamicWasDown = false
        var segmentPhaseIndex = 0

        val metricSamples = mutableListOf<PoseMetricSample>()
        val completedPhaseSamples = mutableListOf<PoseMetricSample>()
        val displacementWindow = ArrayDeque<Double>()
        val gaitMotionWindow = ArrayDeque<Boolean>()
        val requiresBilateralPhases = task == BodyCaptureTask.StandingSide || task == BodyCaptureTask.FootArch

        fun publishProgress(rawValue: Float) {
            val clamped = rawValue.coerceIn(0f, 1f)
            onProgress(if (requiresBilateralPhases) (segmentPhaseIndex + clamped) / 2f else clamped)
        }

        fun <T> ArrayDeque<T>.pushLimited(value: T, maxSize: Int) {
            addLast(value)
            while (size > maxSize) removeFirst()
        }

        fun profile() = BodyCaptureQualityGate.profileForAge(childAgeMonths)

        fun resetCaptureState(clearHint: Boolean = true) {
            stableFrames = 0
            stableSince = 0L
            firstHipX = null
            firstHipY = null
            metricSamples.clear()
            displacementWindow.clear()
            gaitMotionWindow.clear()
            dynamicRepetitionCount = 0
            dynamicWasDown = false
            if (clearHint) publishProgress(0f)
        }

        fun median(values: List<Double>): Double? {
            val sorted = values.filter { it.isFinite() }.sorted()
            if (sorted.isEmpty()) return null
            val middle = sorted.size / 2
            return if (sorted.size % 2 == 0) (sorted[middle - 1] + sorted[middle]) / 2.0 else sorted[middle]
        }

        fun mad(values: List<Double>): Double {
            if (values.size < 2) return 0.0
            val center = median(values) ?: return 0.0
            return median(values.map { kotlin.math.abs(it - center) }) ?: 0.0
        }

        fun makeSnapshot(): PostureMetricSnapshot = makePostureSnapshot(
            task, metricSamples, dynamicRepetitionCount, front, requiresBilateralPhases
        )

        fun staticMetricsAreStable(minimumSamples: Int): Boolean {
            fun stableCm(values: List<Double>) = PostureMetricCalculator.isStableSeries(values, minimumSamples, .55)
            if (!stableCm(metricSamples.map { it.shoulderHeightDifferenceCm }) ||
                !stableCm(metricSamples.map { it.pelvicHeightDifferenceCm }) ||
                !stableCm(metricSamples.map { it.spinalMidlineDeviationCm })) return false
            return when (task) {
                BodyCaptureTask.StandingFront, BodyCaptureTask.StandingBack -> PostureMetricCalculator.isStableSeries(metricSamples.map { it.headTiltDegrees }, minimumSamples, 2.5)
                BodyCaptureTask.StandingSide, BodyCaptureTask.Seated -> PostureMetricCalculator.isStableSeries(metricSamples.map { it.thoracicRoundingDegrees }, minimumSamples, 3.5) &&
                    PostureMetricCalculator.isStableSeries(metricSamples.map { it.forwardHeadAngleDegrees }, minimumSamples, 3.5)
                BodyCaptureTask.ForwardBend -> PostureMetricCalculator.isStableSeries(metricSamples.map { it.forwardBendCompletionScore }, minimumSamples, .05)
                BodyCaptureTask.DynamicKneeControl -> PostureMetricCalculator.isStableSeries(metricSamples.map { it.kneeAlignmentProxyRatio }, minimumSamples, .08)
                BodyCaptureTask.GaitVideo, BodyCaptureTask.FootArch -> true
            }
        }

        val footProcessor = FootCloseUpProcessor(
            front = front,
            childAgeMonths = childAgeMonths,
            onPrompt = onPrompt,
            onProgress = onProgress,
            onAlignment = onAlignment,
            onComplete = onComplete,
            isCaptureArmed = isCaptureArmed
        )

        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build().also { useCase ->
                useCase.setAnalyzer(analysisExecutor) { imageProxy ->
                    val image = imageProxy.image
                    if (image == null || finished || !isCurrent()) {
                        imageProxy.close()
                        return@setAnalyzer
                    }

                    detector.process(InputImage.fromMediaImage(image, imageProxy.imageInfo.rotationDegrees))
                        .addOnSuccessListener { pose ->
                            if (!isCurrent()) return@addOnSuccessListener
                            if (task == BodyCaptureTask.FootArch && footProcessor.process(pose, image.width, image.height)) return@addOnSuccessListener

                            val ids = when (task) {
                                BodyCaptureTask.Seated -> listOf(
                                    PoseLandmark.NOSE,
                                    PoseLandmark.LEFT_EAR,
                                    PoseLandmark.RIGHT_EAR,
                                    PoseLandmark.LEFT_SHOULDER,
                                    PoseLandmark.RIGHT_SHOULDER,
                                    PoseLandmark.LEFT_HIP,
                                    PoseLandmark.RIGHT_HIP
                                )
                                BodyCaptureTask.StandingFront, BodyCaptureTask.StandingBack -> listOf(
                                    PoseLandmark.NOSE,
                                    PoseLandmark.LEFT_EAR,
                                    PoseLandmark.RIGHT_EAR,
                                    PoseLandmark.LEFT_SHOULDER,
                                    PoseLandmark.RIGHT_SHOULDER,
                                    PoseLandmark.LEFT_HIP,
                                    PoseLandmark.RIGHT_HIP,
                                    PoseLandmark.LEFT_KNEE,
                                    PoseLandmark.RIGHT_KNEE,
                                    PoseLandmark.LEFT_ANKLE,
                                    PoseLandmark.RIGHT_ANKLE
                                )
                                else -> listOf(
                                    PoseLandmark.NOSE,
                                    PoseLandmark.LEFT_SHOULDER,
                                    PoseLandmark.RIGHT_SHOULDER,
                                    PoseLandmark.LEFT_HIP,
                                    PoseLandmark.RIGHT_HIP,
                                    PoseLandmark.LEFT_KNEE,
                                    PoseLandmark.RIGHT_KNEE,
                                    PoseLandmark.LEFT_ANKLE,
                                    PoseLandmark.RIGHT_ANKLE
                                )
                            }

                            val confidences = ids.map { pose.getPoseLandmark(it)?.inFrameLikelihood ?: 0f }
                            val forwardBendCoreConfidences = listOf(
                                PoseLandmark.NOSE,
                                PoseLandmark.LEFT_SHOULDER,
                                PoseLandmark.RIGHT_SHOULDER,
                                PoseLandmark.LEFT_HIP,
                                PoseLandmark.RIGHT_HIP,
                                PoseLandmark.LEFT_KNEE,
                                PoseLandmark.RIGHT_KNEE
                            ).map { pose.getPoseLandmark(it)?.inFrameLikelihood ?: 0f }
                            val forwardBendAnkleConfidences = listOf(
                                PoseLandmark.LEFT_ANKLE,
                                PoseLandmark.RIGHT_ANKLE
                            ).map { pose.getPoseLandmark(it)?.inFrameLikelihood ?: 0f }
                            val hasReliablePose = if (task == BodyCaptureTask.ForwardBend) {
                                if (isCaptureArmed()) {
                                    BodyCaptureQualityGate.hasReliableForwardBendLandmarks(
                                        forwardBendCoreConfidences,
                                        forwardBendAnkleConfidences,
                                        childAgeMonths
                                    )
                                } else {
                                    BodyCaptureQualityGate.hasReliableLandmarks(confidences, childAgeMonths)
                                }
                            } else {
                                BodyCaptureQualityGate.hasReliableLandmarks(confidences, childAgeMonths)
                            }
                            if (!hasReliablePose) {
                                resetCaptureState(false)
                                onAlignment(CaptureBodyAlignment())
                                onPrompt(if (task == BodyCaptureTask.Seated) {
                                    "请让肩部和髋部清晰入镜，保持光线充足。"
                                } else if (task == BodyCaptureTask.ForwardBend) {
                                    "请背对镜头，让头、双肩、双髋、双膝和双脚清晰入镜。"
                                } else {
                                    "请让头、肩、髋和双脚完整入镜，保持光线充足。"
                                })
                                return@addOnSuccessListener
                            }

                            // The detector result is read more than once below. A
                            // result can be invalidated between those reads on
                            // low-end devices or during a lens/permission
                            // transition, so never force unwrap a landmark even
                            // after the confidence gate has passed.
                            val leftShoulder = pose.getPoseLandmark(PoseLandmark.LEFT_SHOULDER)
                            val rightShoulder = pose.getPoseLandmark(PoseLandmark.RIGHT_SHOULDER)
                            val leftHip = pose.getPoseLandmark(PoseLandmark.LEFT_HIP)
                            val rightHip = pose.getPoseLandmark(PoseLandmark.RIGHT_HIP)
                            val leftKnee = pose.getPoseLandmark(PoseLandmark.LEFT_KNEE)
                            val rightKnee = pose.getPoseLandmark(PoseLandmark.RIGHT_KNEE)
                            val nose = pose.getPoseLandmark(PoseLandmark.NOSE)
                            val leftAnkle = pose.getPoseLandmark(PoseLandmark.LEFT_ANKLE)
                            val rightAnkle = pose.getPoseLandmark(PoseLandmark.RIGHT_ANKLE)
                            if (leftShoulder == null || rightShoulder == null || leftHip == null || rightHip == null) {
                                resetCaptureState(false)
                                onAlignment(CaptureBodyAlignment())
                                onPrompt("暂未看清关键点，请保持光线充足并重新取景。")
                                return@addOnSuccessListener
                            }
                            if (task != BodyCaptureTask.Seated && (leftKnee == null || rightKnee == null)) {
                                resetCaptureState(false)
                                onAlignment(CaptureBodyAlignment())
                                onPrompt("请让双膝清晰入镜，保持全身无遮挡。")
                                return@addOnSuccessListener
                            }
                            if (task == BodyCaptureTask.Seated && (nose == null || pose.getPoseLandmark(PoseLandmark.LEFT_EAR) == null || pose.getPoseLandmark(PoseLandmark.RIGHT_EAR) == null)) {
                                resetCaptureState(false)
                                onPrompt("暂未看清头部或耳部，请保持光线充足并重新取景。")
                                return@addOnSuccessListener
                            }
                            if (task != BodyCaptureTask.Seated && task != BodyCaptureTask.ForwardBend && (nose == null || leftAnkle == null || rightAnkle == null)) {
                                resetCaptureState(false)
                                onPrompt("暂未看清头部或双脚，请退后一步并确保全身入镜。")
                                return@addOnSuccessListener
                            }
                            if (task == BodyCaptureTask.ForwardBend && nose == null) {
                                resetCaptureState(false)
                                onPrompt("暂未看清头部，请保持背对镜头并重新取景。")
                                return@addOnSuccessListener
                            }
                            // Each value has been checked in a separate branch
                            // above, allowing Kotlin to smart-cast it without a
                            // force unwrap and keeping the analyzer fail-closed.
                            val ls = leftShoulder
                            val rs = rightShoulder
                            val lh = leftHip
                            val rh = rightHip
                            val n = nose
                            val noseY = n?.position?.y ?: run {
                                resetCaptureState(false)
                                onPrompt("暂未看清头部，请保持光线充足并重新取景。")
                                return@addOnSuccessListener
                            }
                            val verticalCoverage = if (task == BodyCaptureTask.Seated) {
                                kotlin.math.abs(((ls.position.y + rs.position.y) / 2f) - ((lh.position.y + rh.position.y) / 2f)).toDouble() / image.height.coerceAtLeast(1)
                            } else {
                                val ankleConfidenceFloor = BodyCaptureQualityGate.profileForAge(childAgeMonths).minimumIndividualLandmarkConfidence
                                val visibleAnkles = listOfNotNull(leftAnkle, rightAnkle)
                                    .filter { it.inFrameLikelihood >= ankleConfidenceFloor }
                                val requiredVisibleAnkles = if (task == BodyCaptureTask.ForwardBend && isCaptureArmed()) 1 else 2
                                if (visibleAnkles.size < requiredVisibleAnkles) {
                                    resetCaptureState(false)
                                    onAlignment(CaptureBodyAlignment())
                                    onPrompt(if (task == BodyCaptureTask.ForwardBend) {
                                        "请让双脚完整入镜并保持并拢。"
                                    } else {
                                        "暂未看清双脚，请退后一步并确保全身入镜。"
                                    })
                                    return@addOnSuccessListener
                                }
                                val ankleY = visibleAnkles.map { it.position.y }.average().toFloat()
                                kotlin.math.abs(noseY - ankleY).toDouble() / image.height.coerceAtLeast(1)
                            }

                            val scaleState = BodyCaptureQualityGate.bodyScaleState(verticalCoverage, task == BodyCaptureTask.Seated, childAgeMonths)
                            val frameWidth = image.width.coerceAtLeast(1).toDouble()
                            val frameHeight = image.height.coerceAtLeast(1).toDouble()
                            val shoulderCenterXRatio = ((ls.position.x + rs.position.x) / 2.0) / frameWidth
                            val hipCenterXRatio = ((lh.position.x + rh.position.x) / 2.0) / frameWidth
                            val bodyCenterXRatio = (shoulderCenterXRatio + hipCenterXRatio) / 2.0
                            val visibleFeet = listOfNotNull(leftAnkle, rightAnkle)
                                .filter { it.inFrameLikelihood >= BodyCaptureQualityGate.profileForAge(childAgeMonths).minimumIndividualLandmarkConfidence }
                            val ankleCenterXRatio = if (visibleFeet.isEmpty()) bodyCenterXRatio else visibleFeet.map { it.position.x.toDouble() / frameWidth }.average()
                            val confidenceFloor = BodyCaptureQualityGate.profileForAge(childAgeMonths).minimumIndividualLandmarkConfidence
                            val kneesVisible = (leftKnee?.inFrameLikelihood ?: 0f) >= confidenceFloor && (rightKnee?.inFrameLikelihood ?: 0f) >= confidenceFloor
                            val kneeAngles = listOfNotNull(
                                if (leftKnee != null && leftAnkle != null && leftKnee.inFrameLikelihood >= confidenceFloor && leftAnkle.inFrameLikelihood >= confidenceFloor) {
                                    BodyCaptureQualityGate.jointAngle(
                                        lh.position.x.toDouble(), lh.position.y.toDouble(),
                                        leftKnee.position.x.toDouble(), leftKnee.position.y.toDouble(),
                                        leftAnkle.position.x.toDouble(), leftAnkle.position.y.toDouble()
                                    )
                                } else null,
                                if (rightKnee != null && rightAnkle != null && rightKnee.inFrameLikelihood >= confidenceFloor && rightAnkle.inFrameLikelihood >= confidenceFloor) {
                                    BodyCaptureQualityGate.jointAngle(
                                        rh.position.x.toDouble(), rh.position.y.toDouble(),
                                        rightKnee.position.x.toDouble(), rightKnee.position.y.toDouble(),
                                        rightAnkle.position.x.toDouble(), rightAnkle.position.y.toDouble()
                                    )
                                } else null
                            )
                            val shoulderWidthRatio = kotlin.math.abs(ls.position.x - rs.position.x).toDouble() / frameWidth
                            val ankleGapRatio = if (leftAnkle != null && rightAnkle != null && leftAnkle.inFrameLikelihood >= confidenceFloor && rightAnkle.inFrameLikelihood >= confidenceFloor) {
                                kotlin.math.abs(leftAnkle.position.x - rightAnkle.position.x).toDouble() / frameWidth
                            } else null
                            val adamsLowerBodyReady = task != BodyCaptureTask.ForwardBend || BodyCaptureQualityGate.hasAdamsLowerBodyPosition(
                                kneeAngles,
                                ankleGapRatio,
                                shoulderWidthRatio,
                                requiresBothFeet = !isCaptureArmed()
                            )
                            onAlignment(
                                CaptureBodyAlignment(
                                    bodyDetected = true,
                                    distanceState = scaleState,
                                    centered = bodyCenterXRatio in 0.39..0.61,
                                    headReady = n.position.x.toDouble() / frameWidth in 0.27..0.73 && n.position.y.toDouble() / frameHeight in 0.08..0.94,
                                    shouldersReady = shoulderCenterXRatio in 0.31..0.69,
                                    hipsReady = hipCenterXRatio in 0.33..0.67,
                                    kneesReady = task == BodyCaptureTask.Seated || (kneesVisible && adamsLowerBodyReady),
                                    feetReady = task == BodyCaptureTask.Seated || (visibleFeet.isNotEmpty() && ankleCenterXRatio in 0.27..0.73 && adamsLowerBodyReady)
                                )
                            )
                            when (scaleState) {
                                BodyCaptureQualityGate.BodyScaleState.Ready -> Unit
                                BodyCaptureQualityGate.BodyScaleState.TooClose -> {
                                    resetCaptureState()
                                    onProgress(0f)
                                    onPrompt(if (task == BodyCaptureTask.Seated) {
                                        "镜头太近，请把手机向后移，让肩部到髋部约占画面三分之一。"
                                    } else {
                                        "人物离镜头太近，请后退两步，让全身约占画面一半到三分之二。"
                                    })
                                    return@addOnSuccessListener
                                }
                                BodyCaptureQualityGate.BodyScaleState.TooFar -> {
                                    resetCaptureState()
                                    onProgress(0f)
                                    onPrompt(if (task == BodyCaptureTask.Seated) {
                                        "距离稍远，请向前半步，仍保持头部、肩部和髋部完整入镜。"
                                    } else {
                                        "距离稍远，请向前半步，保持头顶和双脚完整入镜。"
                                    })
                                    return@addOnSuccessListener
                                }
                                BodyCaptureQualityGate.BodyScaleState.Invalid -> {
                                    resetCaptureState()
                                    onProgress(0f)
                                    onPrompt("暂时无法判断取景距离，请保持手机竖直并重新站位。")
                                    return@addOnSuccessListener
                                }
                            }

                            if (!isCaptureArmed()) {
                                resetCaptureState()
                                onProgress(0f)
                                onPrompt("取景已就绪，请确认动作后点击开始记录。")
                                return@addOnSuccessListener
                            }

                            // Estimate global camera roll from both shoulder
                            // and hip axes before deriving any left/right
                            // height or trunk metrics.
                            val rollAxisDx = ((ls.position.x - rs.position.x) + (lh.position.x - rh.position.x)) / 2f
                            val rollAxisDy = ((ls.position.y - rs.position.y) + (lh.position.y - rh.position.y)) / 2f
                            val leftHipCorrectedX = PostureMetricCalculator.rollCorrectedX(lh.position.x.toDouble(), lh.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())
                            val leftHipCorrectedY = PostureMetricCalculator.rollCorrectedY(lh.position.x.toDouble(), lh.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())
                            val rightHipCorrectedX = PostureMetricCalculator.rollCorrectedX(rh.position.x.toDouble(), rh.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())
                            val rightHipCorrectedY = PostureMetricCalculator.rollCorrectedY(rh.position.x.toDouble(), rh.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())
                            val leftShoulderCorrectedX = PostureMetricCalculator.rollCorrectedX(ls.position.x.toDouble(), ls.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())
                            val leftShoulderCorrectedY = PostureMetricCalculator.rollCorrectedY(ls.position.x.toDouble(), ls.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())
                            val rightShoulderCorrectedX = PostureMetricCalculator.rollCorrectedX(rs.position.x.toDouble(), rs.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())
                            val rightShoulderCorrectedY = PostureMetricCalculator.rollCorrectedY(rs.position.x.toDouble(), rs.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())
                            val hipX = (leftHipCorrectedX + rightHipCorrectedX) / 2.0
                            val hipY = (leftHipCorrectedY + rightHipCorrectedY) / 2.0
                            val shoulderX = (leftShoulderCorrectedX + rightShoulderCorrectedX) / 2.0
                            val shoulderY = (leftShoulderCorrectedY + rightShoulderCorrectedY) / 2.0

                            if (task == BodyCaptureTask.Seated) {
                                if (!BodyCaptureQualityGate.hasUsableSeatedGeometry(shoulderY, hipY, verticalCoverage, childAgeMonths)) {
                                    resetCaptureState()
                                    onPrompt("请坐直、双脚落地，让肩部保持在髋部上方；不要斜靠椅背。")
                                    return@addOnSuccessListener
                                }
                            }
                            if (task == BodyCaptureTask.ForwardBend && !adamsLowerBodyReady) {
                                resetCaptureState()
                                onProgress(0f)
                                onPrompt("请保持双脚并拢、膝关节完全伸直；不要屈膝或做弓步。")
                                return@addOnSuccessListener
                            }

                            val rawHipY = (lh.position.y + rh.position.y) / 2.0
                            val torsoTilt = kotlin.math.abs(shoulderX - hipX) / kotlin.math.abs(shoulderY - hipY).coerceAtLeast(.001)
                            val forwardBendCompletionScore = BodyCaptureQualityGate.adamsForwardBendCompletionScore(
                                ls.position.x.toDouble(),
                                ls.position.y.toDouble(),
                                rs.position.x.toDouble(),
                                rs.position.y.toDouble(),
                                rawHipY
                            ) ?: 0.0
                            val bodyHeightNormalized = verticalCoverage

                            val shoulderGap = PostureMetricCalculator.rollCorrectedVerticalDifference(ls.position.x.toDouble(), ls.position.y.toDouble(), rs.position.x.toDouble(), rs.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble()) / image.height.coerceAtLeast(1)
                            val pelvicGap = PostureMetricCalculator.rollCorrectedVerticalDifference(lh.position.x.toDouble(), lh.position.y.toDouble(), rh.position.x.toDouble(), rh.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble()) / image.height.coerceAtLeast(1)

                            val leftEar = pose.getPoseLandmark(PoseLandmark.LEFT_EAR)
                            val rightEar = pose.getPoseLandmark(PoseLandmark.RIGHT_EAR)
                            val headTilt = if (leftEar != null && rightEar != null) {
                                val earDy = PostureMetricCalculator.rollCorrectedVerticalDifference(leftEar.position.x.toDouble(), leftEar.position.y.toDouble(), rightEar.position.x.toDouble(), rightEar.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())
                                val earLeftX = PostureMetricCalculator.rollCorrectedX(leftEar.position.x.toDouble(), leftEar.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())
                                val earRightX = PostureMetricCalculator.rollCorrectedX(rightEar.position.x.toDouble(), rightEar.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())
                                kotlin.math.abs(
                                    kotlin.math.atan2(earDy, kotlin.math.abs(earLeftX - earRightX).coerceAtLeast(.001)) * 180 / Math.PI
                                )
                            } else 0.0

                            val forwardHead = if (leftEar != null && rightEar != null) {
                                val earX = (PostureMetricCalculator.rollCorrectedX(leftEar.position.x.toDouble(), leftEar.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble()) + PostureMetricCalculator.rollCorrectedX(rightEar.position.x.toDouble(), rightEar.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())) / 2.0
                                val earY = (PostureMetricCalculator.rollCorrectedY(leftEar.position.x.toDouble(), leftEar.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble()) + PostureMetricCalculator.rollCorrectedY(rightEar.position.x.toDouble(), rightEar.position.y.toDouble(), rollAxisDx.toDouble(), rollAxisDy.toDouble())) / 2.0
                                kotlin.math.abs(kotlin.math.atan2(kotlin.math.abs(earX - shoulderX), kotlin.math.abs(earY - shoulderY).coerceAtLeast(.001)) * 180 / Math.PI)
                            } else 0.0

                            val trunkOffsetNormalized = kotlin.math.abs(shoulderX - hipX) / image.height.coerceAtLeast(1)
                            val shoulderGapCm = PostureMetricCalculator.centimeters(shoulderGap, bodyHeightNormalized, measuredHeightCm) ?: 0.0
                            val pelvicGapCm = PostureMetricCalculator.centimeters(pelvicGap, bodyHeightNormalized, measuredHeightCm) ?: 0.0
                            val trunkOffsetCm = PostureMetricCalculator.centimeters(trunkOffsetNormalized.toDouble(), bodyHeightNormalized, measuredHeightCm) ?: 0.0
                            val hipWidth = kotlin.math.abs(lh.position.x - rh.position.x).toDouble().coerceAtLeast(.001)
                            val kneeGap = if (leftKnee != null && rightKnee != null) kotlin.math.abs(leftKnee.position.x - rightKnee.position.x).toDouble() else 0.0
                            val ankleGap = if (leftAnkle != null && rightAnkle != null) kotlin.math.abs(leftAnkle.position.x - rightAnkle.position.x).toDouble() else 0.0
                            val kneeAlignmentProxy = (kneeGap - ankleGap) / hipWidth
                            val leftKneeValgus = if (leftKnee != null && leftAnkle != null) BodyCaptureQualityGate.jointAngle(lh.position.x.toDouble(), lh.position.y.toDouble(), leftKnee.position.x.toDouble(), leftKnee.position.y.toDouble(), leftAnkle.position.x.toDouble(), leftAnkle.position.y.toDouble())?.let { 180.0 - it } ?: 0.0 else 0.0
                            val rightKneeValgus = if (rightKnee != null && rightAnkle != null) BodyCaptureQualityGate.jointAngle(rh.position.x.toDouble(), rh.position.y.toDouble(), rightKnee.position.x.toDouble(), rightKnee.position.y.toDouble(), rightAnkle.position.x.toDouble(), rightAnkle.position.y.toDouble())?.let { 180.0 - it } ?: 0.0 else 0.0
                            val lowerLimbAxisAsymmetry = kotlin.math.abs(leftKneeValgus - rightKneeValgus)
                            val kneeCenterY = if (leftKnee != null && rightKnee != null) (leftKnee.position.y + rightKnee.position.y) / 2.0 else rawHipY
                            val squatDepthRatio = kotlin.math.abs(rawHipY - kneeCenterY) / image.height.coerceAtLeast(1) / bodyHeightNormalized.coerceAtLeast(.001)
                            val heelAlignmentProxy = if (leftKnee != null && leftAnkle != null && rightKnee != null && rightAnkle != null) {
                                val leftAngle = kotlin.math.atan2(kotlin.math.abs(leftKnee.position.x - leftAnkle.position.x).toDouble(), kotlin.math.abs(leftKnee.position.y - leftAnkle.position.y).toDouble().coerceAtLeast(.001)) * 180 / Math.PI
                                val rightAngle = kotlin.math.atan2(kotlin.math.abs(rightKnee.position.x - rightAnkle.position.x).toDouble(), kotlin.math.abs(rightKnee.position.y - rightAnkle.position.y).toDouble().coerceAtLeast(.001)) * 180 / Math.PI
                                (leftAngle + rightAngle) / 2
                            } else 0.0
                            val footVisibility = listOfNotNull(leftAnkle?.inFrameLikelihood, rightAnkle?.inFrameLikelihood).average().takeIf { !it.isNaN() } ?: 0.0
                            // A single RGB/2D camera cannot measure rib
                            // prominence or ATR. The former midpoint-distance
                            // formula was mathematically zero by construction;
                            // leave these fields unavailable until validated
                            // depth/3D or scoliometer-backed measurement exists.
                            metricSamples += PoseMetricSample(
                                confidence = confidences.average().toDouble(),
                                shoulderHeightDifferenceCm = shoulderGapCm,
                                pelvicHeightDifferenceCm = pelvicGapCm,
                                headTiltDegrees = headTilt,
                                spinalMidlineDeviationCm = trunkOffsetCm,
                                thoracicRoundingDegrees = kotlin.math.abs(torsoTilt * 180 / Math.PI),
                                forwardHeadAngleDegrees = forwardHead,
                                forwardBendCompletionScore = forwardBendCompletionScore,
                                kneeAlignmentProxyRatio = kneeAlignmentProxy,
                                lowerLimbAxisAsymmetryDegrees = lowerLimbAxisAsymmetry,
                                leftKneeValgusProxyDegrees = leftKneeValgus,
                                rightKneeValgusProxyDegrees = rightKneeValgus,
                                squatDepthRatio = squatDepthRatio,
                                footArchVisibilityScore = footVisibility,
                                heelAlignmentProxyDegrees = heelAlignmentProxy
                            )

                            if (firstHipX == null) {
                                firstHipX = hipX
                                firstHipY = hipY
                            }

                            val displacement = kotlin.math.hypot((hipX - (firstHipX ?: hipX)).toDouble(), (hipY - (firstHipY ?: hipY)).toDouble())
                            val displacementRatio = displacement / image.height.coerceAtLeast(1)
                            val gate = profile()

                            displacementWindow.pushLimited(displacementRatio, gate.stabilityWindowFrames)
                            gaitMotionWindow.pushLimited(displacementRatio >= gate.gaitMinimumDisplacementRatio, gate.gaitMovementWindowFrames)

                            if (task != BodyCaptureTask.GaitVideo && task != BodyCaptureTask.DynamicKneeControl) {
                                val windowDisplacement = median(displacementWindow.toList()) ?: 0.0
                                val windowJitter = mad(displacementWindow.toList())
                                if (windowDisplacement >= gate.staticMaximumDisplacementRatio || windowJitter > gate.staticDisplacementJitterRatio) {
                                    firstHipX = hipX
                                    firstHipY = hipY
                                    metricSamples.clear()
                                    displacementWindow.clear()
                                    onProgress(0f)
                                    onPrompt("请保持自然不动，画面稳定后开始计时。")
                                    return@addOnSuccessListener
                                }
                            }

                            if (task == BodyCaptureTask.GaitVideo && metricSamples.size < gate.minimumRawSamplesForCompletion) {
                                onProgress(0f)
                                onPrompt("请继续自然走动，正在采集足够的稳定样本。")
                                return@addOnSuccessListener
                            }

                            stableFrames++
                            if (stableSince == 0L) stableSince = SystemClock.elapsedRealtime()
                            val elapsed = SystemClock.elapsedRealtime() - stableSince

                            val enough = if (task == BodyCaptureTask.DynamicKneeControl) {
                                val kneeFlexion = (leftKneeValgus + rightKneeValgus) / 2.0
                                if (kneeFlexion >= 30.0) {
                                    dynamicWasDown = true
                                    onPrompt("已识别下蹲位，请保持双膝朝向脚尖并自然站起。")
                                } else if (dynamicWasDown && kneeFlexion <= 18.0) {
                                    dynamicWasDown = false
                                    dynamicRepetitionCount++
                                    onPrompt(if (dynamicRepetitionCount >= 3) "三次动作已完成，请保持站立。" else "已完成${dynamicRepetitionCount}次，请继续下一次下蹲。")
                                } else {
                                    onPrompt(if (dynamicRepetitionCount == 0) "请正对镜头，缓慢下蹲后回到站立，共完成三次。" else "已完成${dynamicRepetitionCount}次，请继续完成下蹲和回位。")
                                }
                                publishProgress(((dynamicRepetitionCount + if (dynamicWasDown) 0.5 else 0.0) / 3.0).coerceAtMost(0.98).toFloat())
                                dynamicRepetitionCount >= 3
                            } else if (task == BodyCaptureTask.GaitVideo) {
                                val movedFrames = gaitMotionWindow.count { it }
                                val moved = movedFrames >= gate.gaitMovementWindowFrames / 2
                                onPrompt(if (moved) "节奏已确认，请继续自然走完三步。" else "请固定手机，沿直线自然走三步。")
                                publishProgress(BodyCaptureQualityGate.gaitProgress(elapsed, moved, childAgeMonths))
                                BodyCaptureQualityGate.gaitReady(elapsed, displacementRatio, movedFrames, childAgeMonths)
                            } else {
                                if (task == BodyCaptureTask.ForwardBend && forwardBendCompletionScore < gate.forwardBendMinimumTorsoTiltRatio) {
                                    stableFrames = 0
                                    stableSince = 0
                                    firstHipX = hipX
                                    firstHipY = hipY
                                    metricSamples.clear()
                                    onProgress(0f)
                                    onPrompt("请背对镜头，双脚并拢、膝盖完全伸直、双手合十下垂，继续缓慢前屈至躯干接近水平。")
                                    return@addOnSuccessListener
                                }

                                val stableDisplacement = median(displacementWindow.toList()) ?: displacementRatio
                                val jitter = mad(displacementWindow.toList())
                                val stableHold = gate.staticHoldMilliseconds.toDouble() / 1000.0
                                val remaining = kotlin.math.max(0, kotlin.math.ceil(stableHold - elapsed / 1000.0).toInt())
                                onPrompt(if (task == BodyCaptureTask.ForwardBend) {
                                    if (remaining > 0) "前屈动作已识别，请保持${remaining}秒。" else "前屈记录完成，请保持不动。"
                                } else {
                                    if (remaining > 0) "画面稳定，请保持自然姿势${remaining}秒。" else "记录完成，请保持不动。"
                                })
                                publishProgress(BodyCaptureQualityGate.staticProgress(elapsed, childAgeMonths))

                                if (task == BodyCaptureTask.ForwardBend) {
                                    BodyCaptureQualityGate.forwardBendReady(elapsed, stableFrames, stableDisplacement, forwardBendCompletionScore, childAgeMonths)
                                } else {
                                    BodyCaptureQualityGate.staticReady(elapsed, stableFrames, stableDisplacement, jitter, childAgeMonths)
                                }
                            }

                            if (enough && !finished) {
                                if (metricSamples.size < gate.minimumRawSamplesForCompletion) {
                                    onPrompt("请继续保持，正在采集更多稳定样本。")
                                    return@addOnSuccessListener
                                }
                                if (task != BodyCaptureTask.GaitVideo && task != BodyCaptureTask.DynamicKneeControl && !staticMetricsAreStable(gate.minimumRawSamplesForCompletion)) {
                                    resetCaptureState()
                                    firstHipX = hipX
                                    firstHipY = hipY
                                    onPrompt("本次关键点波动较大，请固定手机并重新保持动作。")
                                    return@addOnSuccessListener
                                }
                                if (requiresBilateralPhases && segmentPhaseIndex == 0) {
                                    completedPhaseSamples.clear()
                                    completedPhaseSamples.addAll(metricSamples)
                                    segmentPhaseIndex = 1
                                    resetCaptureState()
                                    onPrompt(if (task == BodyCaptureTask.StandingSide) {
                                        "左侧记录完成。请让孩子转身，以右侧对准镜头，重新进入人型框后保持自然站立。"
                                    } else {
                                        "左足记录完成。请按引导调整站位，让右足完整进入近景框。"
                                    })
                                    return@addOnSuccessListener
                                }
                                if (requiresBilateralPhases && completedPhaseSamples.isNotEmpty()) {
                                    metricSamples.addAll(0, completedPhaseSamples)
                                }
                                finished = true
                                onProgress(1f)
                                val gap = maxOf(
                                    kotlin.math.abs(ls.position.y - rs.position.y),
                                    kotlin.math.abs(lh.position.y - rh.position.y)
                                ) / image.height.coerceAtLeast(1)
                                val hint = if (gap >= .07f) {
                                    "画面中左右高度差异较明显，请在下一步由家长结合实际站姿确认；这不是医学诊断。"
                                } else {
                                    null
                                }
                                onComplete(CaptureAnalysis(true, "已完成拍摄记录，可查看本次观察指标。", hint, makeSnapshot()))
                            }
                        }
                        .addOnFailureListener { if (isCurrent()) onPrompt(if (task == BodyCaptureTask.FootArch) "正在重新确认足部近景，请保持膝部以下完整入镜。" else "正在重新确认画面，请保持全身入镜。") }
                        .addOnCompleteListener { imageProxy.close() }
                }
            }

        runCatching {
            if (!isCurrent()) return@addListener
            onReady(false)
            provider.unbindAll()
            if (!isCurrent()) return@addListener

            val camera = provider.bindToLifecycle(
                lifecycleOwner,
                if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                analysis
            )
            camera.cameraControl.setZoomRatio(1f)

            if (isCurrent()) onReady(true)
        }.onFailure {
            if (isCurrent()) {
                onProgress(0f)
                onReady(false)
                onAlignment(CaptureBodyAlignment())
                onFailure("相机启动失败，请检查权限或切换摄像头后重试。")
            }
        }
    }, ContextCompat.getMainExecutor(context))
}
