package com.xiangshang.youth.feature.parent

import android.content.Context
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

/** On-device camera and pose analysis. Threshold configuration lives in FollowAlongTuning.kt. */
class FollowAlongPoseAnalyzer(context: Context) {
    val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainExecutor = ContextCompat.getMainExecutor(context)
    private val detector: PoseDetector = PoseDetection.getClient(
        AccuratePoseDetectorOptions.Builder().setDetectorMode(AccuratePoseDetectorOptions.STREAM_MODE).build()
    )
    private val faceDetector: FaceDetector = FaceDetection.getClient(
        FaceDetectorOptions.Builder().setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST).build()
    )
    private var category = "unknown"
    private var actionProfile: FollowAlongActionProfile = ChildFollowAlongTuning.actionProfileFor("unknown", ChildFollowAlongTuning.profileForAge(null))
    private var callback: ((FollowAlongPoseFeedback) -> Unit)? = null
    private val signalHistory = ArrayDeque<Float>()
    private val signalDerivativeHistory = ArrayDeque<Float>()
    private val confidenceHistory = ArrayDeque<Float>()
    private var smoothedSignal: Float? = null
    private var previousSignal: Float? = null
    private var stateReady = true
    private var lowConfidenceStreak = 0
    private var droppedSignalFrames = 0
    private var stableFrames = 0
    private var returnDropValidated = false
    private var returnSlopeValidated = false
    private var topSignalValue = 0f
    private var reps = 0
    private var comboCount = 0
    private var lastRepAt = 0L
    private var lastTempoScore = 0
    private var topReachedAt = 0L
    private var returnTimeoutHintAt = 0L
    private var activeWindowStart = 0L
    private var activeAccumMs = 0L
    private var wasActive = false
    private var lastPublishedAt = 0L
    private var profile: FollowAlongAgeProfile = ChildFollowAlongTuning.profileForAge(null)
    private var ageBand: ChildFollowAlongTuning.FollowAgeBand = ChildFollowAlongTuning.FollowAgeBand.AGE_UNKNOWN

    fun update(category: String, ageMonths: Int?, callback: (FollowAlongPoseFeedback) -> Unit) {
        val targetProfile = ChildFollowAlongTuning.profileForAge(ageMonths)
        val targetActionProfile = ChildFollowAlongTuning.actionProfileFor(category, targetProfile, ageMonths)
        val needsReset = this.category != category || this.profile.label != targetProfile.label
        this.category = category
        this.profile = targetProfile
        this.actionProfile = targetActionProfile
        this.ageBand = ChildFollowAlongTuning.resolveAgeBand(ageMonths, targetProfile)
        if (needsReset) {
            reset()
        }
        this.callback = callback
    }

    @ExperimentalGetImage
    fun analyze(image: ImageProxy) {
        val mediaImage = image.image
        if (mediaImage == null) {
            image.close()
            return
        }
        val input = InputImage.fromMediaImage(mediaImage, image.imageInfo.rotationDegrees)
        val poseTask = detector.process(input)
        val faceTask = faceDetector.process(input)
        Tasks.whenAllSuccess<Any>(poseTask, faceTask)
            .addOnSuccessListener { results ->
                val pose = results.getOrNull(0) as? Pose ?: return@addOnSuccessListener
                val faceCount = (results.getOrNull(1) as? List<*>)?.size ?: 0
                if (faceCount > 1) {
                    resetSignal()
                    publish(FollowAlongPoseFeedback(false, false, "检测到多人，请只保留一名孩子在镜头内", 0f, reps, 0, 0, captureState = FollowAlongCaptureState.MultiplePeople), true)
                } else {
                    handle(pose)
                }
            }
            .addOnFailureListener {
                publish(FollowAlongPoseFeedback(false, false, "动作记录暂不可用，可继续手动记录", 0f, reps, activeSeconds(System.currentTimeMillis()), 0, captureState = FollowAlongCaptureState.Error), true)
            }
            .addOnCompleteListener { image.close() }
    }

    private fun handle(pose: Pose) {
        val required = requiredLandmarks(category)
        val confidenceValues = required.map { pose.getPoseLandmark(it)?.inFrameLikelihood ?: 0f }
        val confidence = confidenceValues.filter { it.isFinite() }.average().toFloat()
        if (!confidence.isFinite() || confidence !in 0f..1f || confidence < profile.minAverageConfidence || required.any { val value = pose.getPoseLandmark(it)?.inFrameLikelihood ?: 0f; !value.isFinite() || value !in 0f..1f || value < profile.minLandmarkConfidence }) {
            if (confidence < profile.minAverageConfidence * 0.85f || required.any { (pose.getPoseLandmark(it)?.inFrameLikelihood ?: 0f) < profile.minLandmarkConfidence * 0.85f }) {
                if (lowConfidenceStreak < 9) lowConfidenceStreak += 1 else droppedSignalFrames += 1
            } else {
                lowConfidenceStreak = 0
            }
            resetSignal()
            val message = if (droppedSignalFrames >= 4 || lowConfidenceStreak >= 6) {
                "姿态点波动较大，建议把身材离后移到正中位，拉直肩膀后重试"
            } else {
                "请让头、肩、髋和双脚完整入镜，站稳后开始确认动作"
            }
            publish(FollowAlongPoseFeedback(false, false, message, confidence, reps, 0, 0, captureState = if (confidence > 0.1f) FollowAlongCaptureState.Occluded else FollowAlongCaptureState.OutOfFrame))
            return
        }
        lowConfidenceStreak = 0
        confidenceHistory.addLast(confidence)
        while (confidenceHistory.size > profile.confidenceWindowFrames) confidenceHistory.removeFirst()
        // Include the current frame in the robust confidence window. The old
        // ordering made the first valid frame report 0 confidence, delaying
        // return validation and making short camera sessions feel unresponsive.
        val trimmedConfidence = trimAverage(confidenceHistory, actionProfile.confidenceTrim).coerceAtLeast(0f)

        val rawSignal = signal(pose) ?: run {
            publish(FollowAlongPoseFeedback(false, false, "画面边界不完整，请调整位置后重试", confidence, reps, 0, 0, captureState = FollowAlongCaptureState.OutOfFrame))
            return
        }
        val signal = smoothedSignal?.let { it * (1f - actionProfile.smoothAlpha) + rawSignal * actionProfile.smoothAlpha } ?: rawSignal
        val delta = (previousSignal?.let { signal - it } ?: 0f) * actionProfile.derivativeScale
        smoothedSignal = signal
        previousSignal = signal
        val now = System.currentTimeMillis()

        signalHistory.addLast(signal)
        while (signalHistory.size > actionProfile.historyLen) signalHistory.removeFirst()
        signalDerivativeHistory.addLast(abs(delta))
        while (signalDerivativeHistory.size > actionProfile.historyLen) signalDerivativeHistory.removeFirst()

        if (signalHistory.size < actionProfile.requiredSignalHistoryFrames || signalHistory.size < actionProfile.minHistory) {
            updateActiveWindow(now = now, active = false)
            publish(FollowAlongPoseFeedback(true, false, "正在确认动作范围（请先保持站姿）", confidence, reps, 0, 0))
            return
        }

        val (min, max) = robustRange(signalHistory, profile.outlierTrimRatio)
        val rawRange = max - min
        val rangeNoise = robustDerivative(noiseWindow = signalDerivativeHistory, trim = actionProfile.confidenceTrim)
        val rangeNoisePenalty = (rangeNoise * actionProfile.rangeNoiseMultiplier).coerceIn(0f, rawRange.coerceAtLeast(0.05f) * 0.35f)
        val noiseFloorRange = actionProfile.rangeNoiseMultiplier * rangeNoise
        val minRange = (actionProfile.minSignalRange * profile.dynamicGateFloor).coerceAtLeast(actionProfile.minSignalRange) + noiseFloorRange
        // High-noise frames can push minRange above the configured ceiling.
        // Clamp the lower bound first; Kotlin's coerceIn throws when its
        // minimum exceeds its maximum, which would otherwise terminate the
        // camera analyzer instead of returning a safe guidance state.
        val rangeCeiling = actionProfile.minSignalRange * profile.dynamicGateCeiling
        val dynamicRange = rawRange.coerceIn(minRange.coerceAtMost(rangeCeiling), rangeCeiling)
        val noiseRatio = if (rawRange > 0f) rangeNoise / rawRange else 0f
        val jitterGate = 1f + noiseRatio.coerceIn(0f, 0.55f) * 0.55f

        // Noise-adaptive hysteresis: when jitter rises, slightly widen the state gates
        // and active threshold so a single jitter spike won't be treated as a completed rep.
        val jitterPadding = rangeNoisePenalty.coerceAtMost(dynamicRange * 0.28f)

        if (rawRange < minRange) {
            stateReady = true
            stableFrames = 0
            updateActiveWindow(now = now, active = false)
            val needText = if (category == "plank") {
                "请保持标准支撑位，避免身体晃动"
            } else {
                "动作幅度不够，请抬得更高/下蹲更稳"
            }
            publish(FollowAlongPoseFeedback(true, false, if (rawRange < minRange * 0.7f) "先稳住站姿再做动作幅度，确认动作到位后开始下一次" else needText, confidence, reps, activeSeconds(now), 0))
            return
        }

        val mean = signalHistory.average().toFloat()
        val highGate = mean + dynamicRange * actionProfile.highGateRatio * jitterGate + jitterPadding
        val lowGate = mean - dynamicRange * actionProfile.lowGateRatio * jitterGate - jitterPadding
        val amplitude = abs(signal - mean)
        val activeThreshold = dynamicRange * actionProfile.activeGateRatio * jitterGate + jitterPadding
        val active = amplitude >= activeThreshold
        val quality = qualityScore(trimmedConfidence, amplitude, dynamicRange, lowGate, highGate, signal)
        updateActiveWindow(now = now, active = active)

        if (!stateReady && topReachedAt > 0L) {
            val maxReturnWaitMs = (actionProfile.minRepIntervalMs * 2.5f).toLong().coerceAtLeast(900L)
            val elapsedSinceTop = now - topReachedAt
            if (elapsedSinceTop > maxReturnWaitMs) {
                stateReady = true
                stableFrames = 0
                topReachedAt = 0L
                if (now - returnTimeoutHintAt > 1_800L) {
                    returnTimeoutHintAt = now
                    val hint = guidanceText(category = category, active = false, ageBand = ageBand, forcedTimeout = true)
                    publish(FollowAlongPoseFeedback(true, true, hint, confidence, reps, activeSeconds(now), quality), true)
                }
                // Recalibrate range and keep listening for a fresh up/down cycle.
            }
        }

        if (advanceGate(signal, highGate, lowGate, now, delta, trimmedConfidence)) {
            if (lastRepAt > 0L) {
                val interval = (now - lastRepAt).toFloat() / 1000f
                val expected = (actionProfile.minRepIntervalMs / 1000f).coerceAtLeast(.45f)
                lastTempoScore = ((1f - abs(interval - expected) / expected).coerceIn(0f, 1f) * 100f).roundToInt()
                comboCount = if (interval <= expected * 1.8f) comboCount + 1 else 1
            } else {
                comboCount = 1
            }
            lastRepAt = now
            reps += 1
            publish(FollowAlongPoseFeedback(true, true, "动作完成 ${reps} 次 · 连击 $comboCount", confidence, reps, activeSeconds(now), quality, FollowAlongStage.Return, FollowAlongCaptureState.Ready, dominantSide(pose), (amplitude / dynamicRange.coerceAtLeast(.001f) * 100f).roundToInt().coerceIn(0, 100), lastTempoScore, comboCount), true)
        }
        publish(
                FollowAlongPoseFeedback(
                    true,
                    active,
                    correctionHint(pose) ?: guidanceText(category = category, active = active, ageBand = ageBand),
                    confidence,
                    reps,
                    activeSeconds(now),
                    quality,
                    if (stateReady) (if (active) FollowAlongStage.Exertion else FollowAlongStage.Setup) else FollowAlongStage.Return,
                    FollowAlongCaptureState.Ready,
                    dominantSide(pose),
                    (amplitude / dynamicRange.coerceAtLeast(.001f) * 100f).roundToInt().coerceIn(0, 100),
                    lastTempoScore,
                    comboCount
                )
            )
    }

    private fun dominantSide(pose: Pose): FollowAlongSide {
        if (category != "high_knee" && category != "front_raise" && category != "lateral_raise") return FollowAlongSide.Both
        val left = pose.getPoseLandmark(if (category == "high_knee") PoseLandmark.LEFT_KNEE else PoseLandmark.LEFT_WRIST)?.position?.y ?: 0f
        val right = pose.getPoseLandmark(if (category == "high_knee") PoseLandmark.RIGHT_KNEE else PoseLandmark.RIGHT_WRIST)?.position?.y ?: 0f
        if (abs(left - right) < 30f) return FollowAlongSide.Both
        return if (left < right) FollowAlongSide.Left else FollowAlongSide.Right
    }

    private fun correctionHint(pose: Pose): String? {
        fun point(id: Int) = pose.getPoseLandmark(id)?.position
        return when (category) {
            "squat", "lunge", "squat_challenge" -> {
                val leftKnee = point(PoseLandmark.LEFT_KNEE); val rightKnee = point(PoseLandmark.RIGHT_KNEE)
                val leftAnkle = point(PoseLandmark.LEFT_ANKLE); val rightAnkle = point(PoseLandmark.RIGHT_ANKLE)
                if ((leftKnee != null && leftAnkle != null && abs(leftKnee.x - leftAnkle.x) > 35f) || (rightKnee != null && rightAnkle != null && abs(rightKnee.x - rightAnkle.x) > 35f)) "膝盖请对准脚尖，先稳住再下蹲" else null
            }
            "front_raise", "lateral_raise" -> {
                val left = point(PoseLandmark.LEFT_SHOULDER); val right = point(PoseLandmark.RIGHT_SHOULDER)
                if (left != null && right != null && abs(left.y - right.y) > 35f) "肩膀保持同高，避免一侧耸肩" else null
            }
            "plank" -> {
                val shoulder = point(PoseLandmark.LEFT_SHOULDER); val hip = point(PoseLandmark.LEFT_HIP)
                if (shoulder != null && hip != null && abs(shoulder.y - hip.y) > 90f) "收紧核心，肩髋尽量保持一条线" else null
            }
            else -> null
        }
    }

    private fun guidanceText(
        category: String,
        active: Boolean,
        ageBand: ChildFollowAlongTuning.FollowAgeBand,
        forcedTimeout: Boolean = false
    ): String {
        val paceTag = when (ageBand) {
            ChildFollowAlongTuning.FollowAgeBand.AGE_6_8 -> "慢一半速度"
            ChildFollowAlongTuning.FollowAgeBand.AGE_9_11 -> "稳住节奏"
            else -> "保持节奏"
        }
        if (forcedTimeout) {
            return when (category) {
                "jump_rope", "jumping_jack" -> "先停住1-2秒，回到起始位后再发起下一次。"
                "plank" -> "先回到标准支撑位并稳定，保持1秒后再继续。"
                else -> "先回到起始位并停1秒后再发起下一次。"
            } + paceTag
        }
        if (!active) {
            return when (category) {
                "plank" -> "先定支撑位，腹部收紧，准备后再开始下一次。"
                "high_knee" -> "先抬腿到舒适高度，停1秒后回到起始位。"
                "jumping_jack" -> "先完整张开再合拢，保持手脚同步。"
                else -> "先看标准幅度，吸气时准备，下沉时收紧核心。"
            } + paceTag
        }
        return when (category) {
            "plank" -> "支撑位已就位，保持一字线，不要塌腰。"
            "high_knee", "jumping_jack", "jump_rope" -> "到顶停1秒再回位，不要上下乱抖。"
            "squat", "lunge", "squat_challenge", "burpee" -> "到位后停1秒再回到起始位。"
            "sit_up", "front_raise", "lateral_raise" -> "到达最大幅度后停一拍再落回。"
            else -> "动作进行中，保持动作到底再回位。"
        } + paceTag
    }

    private fun updateActiveWindow(now: Long, active: Boolean) {
        if (active) {
            if (!wasActive) activeWindowStart = now
            wasActive = true
            return
        }
        if (wasActive && activeWindowStart > 0L) {
            activeAccumMs += (now - activeWindowStart)
            activeWindowStart = 0L
        }
        wasActive = false
    }

    private fun signal(pose: Pose): Float? {
        fun y(id: Int) = pose.getPoseLandmark(id)?.position?.y ?: 0f
        fun x(id: Int) = pose.getPoseLandmark(id)?.position?.x ?: 0f
        fun point(id: Int) = pose.getPoseLandmark(id)?.position
        fun angle(a: android.graphics.PointF?, b: android.graphics.PointF?, c: android.graphics.PointF?): Float {
            if (a == null || b == null || c == null) return 180f
            val abx = a.x - b.x; val aby = a.y - b.y
            val cbx = c.x - b.x; val cby = c.y - b.y
            val denominator = hypot(abx.toDouble(), aby.toDouble()) * hypot(cbx.toDouble(), cby.toDouble())
            if (denominator < .001) return 180f
            val cosine = ((abx * cbx + aby * cby) / denominator).coerceIn(-1.0, 1.0)
            return Math.toDegrees(acos(cosine)).toFloat()
        }
        val leftShoulder = point(PoseLandmark.LEFT_SHOULDER)
        val rightShoulder = point(PoseLandmark.RIGHT_SHOULDER)
        val leftHip = point(PoseLandmark.LEFT_HIP)
        val rightHip = point(PoseLandmark.RIGHT_HIP)
        if (leftShoulder == null || rightShoulder == null || leftHip == null || rightHip == null) return null
        val torsoScale = hypot((((leftShoulder.x + rightShoulder.x) - (leftHip.x + rightHip.x)) / 2f).toDouble(), (((leftShoulder.y + rightShoulder.y) - (leftHip.y + rightHip.y)) / 2f).toDouble()).toFloat().coerceAtLeast(1f)
        val shouldersY = (y(PoseLandmark.LEFT_SHOULDER) + y(PoseLandmark.RIGHT_SHOULDER)) / 2f
        val wristsY = (y(PoseLandmark.LEFT_WRIST) + y(PoseLandmark.RIGHT_WRIST)) / 2f
        val hipsY = (y(PoseLandmark.LEFT_HIP) + y(PoseLandmark.RIGHT_HIP)) / 2f
        val leftKneeY = y(PoseLandmark.LEFT_KNEE)
        val rightKneeY = y(PoseLandmark.RIGHT_KNEE)
        val leftKneeLift = kotlin.math.abs(leftKneeY - hipsY) / torsoScale
        val rightKneeLift = kotlin.math.abs(rightKneeY - hipsY) / torsoScale
        val value = when (category) {
            "squat", "lunge", "squat_challenge" -> (180f - (angle(point(PoseLandmark.LEFT_HIP), point(PoseLandmark.LEFT_KNEE), point(PoseLandmark.LEFT_ANKLE)) + angle(point(PoseLandmark.RIGHT_HIP), point(PoseLandmark.RIGHT_KNEE), point(PoseLandmark.RIGHT_ANKLE))) / 2f) / 180f
            "front_raise", "lateral_raise" -> (shouldersY - wristsY) / torsoScale
            "high_knee" -> kotlin.math.max(leftKneeLift, rightKneeLift)
            "sit_up", "plank" -> abs(shouldersY - hipsY) / torsoScale
            // Feet opening is horizontal; ankle Y is almost unchanged during a
            // jumping jack and would under-count the movement.
            "jumping_jack", "burpee" -> abs(wristsY - hipsY) / torsoScale + abs(x(PoseLandmark.LEFT_ANKLE) - x(PoseLandmark.RIGHT_ANKLE)) / torsoScale * .5f
            else -> (shouldersY - wristsY) / torsoScale
        }
        return value.takeIf { it.isFinite() }
    }

    private fun activeSeconds(now: Long): Int {
        val runningMs = activeAccumMs + if (activeWindowStart > 0L) (now - activeWindowStart) else 0L
        return (runningMs / 1000L).toInt()
    }

    private fun requiredLandmarks(category: String): List<Int> = when (category) {
        "front_raise", "lateral_raise" -> listOf(
            PoseLandmark.NOSE, PoseLandmark.LEFT_SHOULDER, PoseLandmark.RIGHT_SHOULDER,
            PoseLandmark.LEFT_ELBOW, PoseLandmark.RIGHT_ELBOW,
            PoseLandmark.LEFT_WRIST, PoseLandmark.RIGHT_WRIST
        )
        "jumping_jack" -> listOf(
            PoseLandmark.NOSE, PoseLandmark.LEFT_SHOULDER, PoseLandmark.RIGHT_SHOULDER,
            PoseLandmark.LEFT_HIP, PoseLandmark.RIGHT_HIP,
            PoseLandmark.LEFT_ANKLE, PoseLandmark.RIGHT_ANKLE,
            PoseLandmark.LEFT_WRIST, PoseLandmark.RIGHT_WRIST
        )
        "high_knee" -> listOf(
            PoseLandmark.NOSE, PoseLandmark.LEFT_SHOULDER, PoseLandmark.RIGHT_SHOULDER,
            PoseLandmark.LEFT_HIP, PoseLandmark.RIGHT_HIP,
            PoseLandmark.LEFT_KNEE, PoseLandmark.RIGHT_KNEE,
            PoseLandmark.LEFT_ANKLE, PoseLandmark.RIGHT_ANKLE
        )
        "sit_up" -> listOf(
            PoseLandmark.NOSE, PoseLandmark.LEFT_SHOULDER, PoseLandmark.RIGHT_SHOULDER,
            PoseLandmark.LEFT_HIP, PoseLandmark.RIGHT_HIP, PoseLandmark.LEFT_KNEE, PoseLandmark.RIGHT_KNEE,
            PoseLandmark.LEFT_WRIST, PoseLandmark.RIGHT_WRIST
        )
        "plank" -> listOf(
            PoseLandmark.NOSE, PoseLandmark.LEFT_SHOULDER, PoseLandmark.RIGHT_SHOULDER,
            PoseLandmark.LEFT_HIP, PoseLandmark.RIGHT_HIP, PoseLandmark.LEFT_KNEE, PoseLandmark.RIGHT_KNEE,
            PoseLandmark.LEFT_ANKLE, PoseLandmark.RIGHT_ANKLE
        )
        "squat", "lunge", "squat_challenge", "burpee" -> listOf(
            PoseLandmark.NOSE, PoseLandmark.LEFT_SHOULDER, PoseLandmark.RIGHT_SHOULDER,
            PoseLandmark.LEFT_HIP, PoseLandmark.RIGHT_HIP,
            PoseLandmark.LEFT_KNEE, PoseLandmark.RIGHT_KNEE,
            PoseLandmark.LEFT_ANKLE, PoseLandmark.RIGHT_ANKLE
        )
        else -> listOf(
            PoseLandmark.NOSE, PoseLandmark.LEFT_SHOULDER, PoseLandmark.RIGHT_SHOULDER,
            PoseLandmark.LEFT_HIP, PoseLandmark.RIGHT_HIP, PoseLandmark.LEFT_KNEE,
            PoseLandmark.RIGHT_KNEE, PoseLandmark.LEFT_ANKLE, PoseLandmark.RIGHT_ANKLE
        )
    }

    private fun robustRange(samples: ArrayDeque<Float>, trimScale: Float): Pair<Float, Float> {
        val sorted = samples.filter { it.isFinite() }.sorted()
        if (sorted.isEmpty()) return 0f to 1f
        val scale = trimScale.coerceIn(0.03f, 0.5f)
        val trim = ((sorted.size * 0.08f * scale).toInt()).coerceAtMost(sorted.size / 3).coerceAtLeast(0)
        val min = sorted.getOrElse(trim) { sorted.first() }
        val max = sorted.getOrElse(sorted.lastIndex - trim) { sorted.last() }
        return if (max > min) min to max else min to (min + 0.0001f)
    }

    private fun trimAverage(values: ArrayDeque<Float>, trimPercent: Float): Float {
        val sorted = values.filter { it.isFinite() }.sorted()
        if (sorted.isEmpty()) return 0f
        val trim = ((sorted.size * trimPercent.coerceIn(0f, 0.48f)).toInt()).coerceAtMost(sorted.size / 2).coerceAtLeast(0)
        if (sorted.size <= trim * 2) return sorted.average().toFloat()
        val range = sorted.subList(trim, sorted.size - trim)
        return if (range.isEmpty()) sorted.average().toFloat() else range.average().toFloat()
    }

    private fun robustDerivative(noiseWindow: ArrayDeque<Float>, trim: Float): Float {
        val sorted = noiseWindow.filter { it.isFinite() }.map { kotlin.math.abs(it) }.sorted()
        if (sorted.size < 6) return 0f
        val trimCount = (sorted.size * trim.coerceIn(0f, 0.48f)).toInt().coerceAtMost(sorted.size / 2).coerceAtLeast(0)
        if (trimCount * 2 >= sorted.size) return sorted.average().toFloat()
        val trimmed = sorted.subList(trimCount, sorted.size - trimCount)
        val median = trimmed.sorted()[trimmed.size / 2]
        val mad = trimmed.map { kotlin.math.abs(it - median) }.sorted().let { diffs ->
            diffs[diffs.size / 2]
        }
        return (mad * 1.4826f).toFloat()
    }

    private fun resetSignal() {
        signalHistory.clear()
        signalDerivativeHistory.clear()
        confidenceHistory.clear()
        smoothedSignal = null
        previousSignal = null
        stateReady = true
        returnDropValidated = false
        returnSlopeValidated = false
        topSignalValue = 0f
        stableFrames = 0
        wasActive = false
        activeWindowStart = 0L
        activeAccumMs = 0L
        topReachedAt = 0L
        returnTimeoutHintAt = 0L
    }

    private fun advanceGate(current: Float, highGate: Float, lowGate: Float, now: Long, delta: Float, trimmedConfidence: Float): Boolean {
        val settleFrames = actionProfile.settlingFrames
        val topHold = actionProfile.topHoldFrames
        val returnHold = actionProfile.returnHoldFrames
        val maxReturnWindowMs = if (actionProfile.maxRepIntervalMs > 0L) actionProfile.maxRepIntervalMs else (actionProfile.minRepIntervalMs * 2.7f).toLong()
        if (stateReady) {
            if (current >= highGate && delta >= actionProfile.derivativeMin) {
                stableFrames += 1
                if (stableFrames >= topHold + settleFrames + actionProfile.stablePeakFrames - 2) {
                    stateReady = false
                    stableFrames = 0
                    topReachedAt = now
                    topSignalValue = current
                    returnDropValidated = false
                    returnSlopeValidated = false
                }
            } else if (stableFrames > 0) {
                stableFrames = 0
            }
            return false
        }
        if (topReachedAt > 0L && now - topReachedAt > maxReturnWindowMs) {
            if (now - returnTimeoutHintAt > 1_200L) {
                returnTimeoutHintAt = now
                val hint = guidanceText(category = category, active = false, ageBand = ageBand, forcedTimeout = true)
                publish(FollowAlongPoseFeedback(true, true, hint, trimmedConfidence, reps, activeSeconds(now), 0), true)
            }
            stateReady = true
            stableFrames = 0
            topReachedAt = 0L
            returnDropValidated = false
            returnSlopeValidated = false
            return false
        }
        if (current <= lowGate) {
            val dropRatio = actionProfile.minDropRatio.coerceIn(0.12f, 1.12f)
            val requiredDrop = maxOf(
                actionProfile.minDropAbsolute,
                (topSignalValue - highGate).coerceAtLeast(actionProfile.minSignalRange * 1.1f) * dropRatio
            )
            if (topSignalValue - current >= requiredDrop) {
                returnDropValidated = true
            }

            if (trimmedConfidence >= actionProfile.returnConfidenceFloor && delta <= -actionProfile.derivativeMin * actionProfile.returnSlopeMinRatio) {
                returnSlopeValidated = true
            }

            if (returnDropValidated && returnSlopeValidated) {
                stableFrames += 1
            } else {
                stableFrames = 0
            }
            if (
                stableFrames >= returnHold + settleFrames + actionProfile.stableReturnFrames - 2 &&
                now - lastRepAt >= actionProfile.minRepIntervalMs &&
                now - topReachedAt <= maxReturnWindowMs &&
                trimmedConfidence >= actionProfile.returnConfidenceFloor
            ) {
                stateReady = true
                stableFrames = 0
                topReachedAt = 0L
                returnDropValidated = false
                returnSlopeValidated = false
                return true
            }
        } else if (stableFrames > 0) {
            stableFrames = 0
        }
        return false
    }


private fun qualityScore(confidence: Float, amplitudeValue: Float, range: Float, lowGate: Float, highGate: Float, signal: Float): Int {
        val amplitude = if (range <= 0f) 0f else (amplitudeValue / range).coerceIn(0f, 1f) * 100f
        val gateCenter = (lowGate + highGate) / 2f
        val gateWidth = (highGate - lowGate).coerceAtLeast(0.001f)
        val gateBalance = (1f - abs(signal - gateCenter) / (gateWidth * 0.5f)).coerceIn(0f, 1f)
        val stability = ((actionProfile.qualityStabilityWeight) * gateBalance * 100f) + ((1f - actionProfile.qualityStabilityWeight) * confidence * 100f * (1f - actionProfile.minConfidencePenalty))
        return (amplitude * (1f - actionProfile.qualityStabilityWeight) + stability).roundToInt().coerceIn(0, 100)
    }

    private fun reset() {
        resetSignal()
        lowConfidenceStreak = 0
        droppedSignalFrames = 0
        previousSignal = null
        reps = 0
        comboCount = 0
        lastTempoScore = 0
        lastRepAt = 0L
        activeWindowStart = 0L
        activeAccumMs = 0L
        wasActive = false
        publish(FollowAlongPoseFeedback(false, false, "准备开始动作记录…", 0f, 0, 0, 0), true)
    }

    private fun publish(feedback: FollowAlongPoseFeedback, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastPublishedAt < 120L) return
        lastPublishedAt = now
        mainExecutor.execute { callback?.invoke(feedback) }
    }

    fun close() { detector.close(); faceDetector.close(); executor.shutdownNow() }
}

@ExperimentalGetImage
fun bindFollowAlongCamera(context: Context, lifecycleOwner: androidx.lifecycle.LifecycleOwner, previewView: PreviewView, front: Boolean, analyzer: FollowAlongPoseAnalyzer) {
    val future = ProcessCameraProvider.getInstance(context)
    future.addListener({
        val provider = runCatching { future.get() }.getOrNull() ?: return@addListener
        provider.unbindAll()
        val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
            .also { it.setAnalyzer(analyzer.executor) { image -> analyzer.analyze(image) } }
        val selector = if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
        runCatching { provider.bindToLifecycle(lifecycleOwner, selector, preview, analysis) }
    }, ContextCompat.getMainExecutor(context))
}

fun unbindFollowAlongCamera(context: Context) {
    val future = ProcessCameraProvider.getInstance(context)
    future.addListener({ runCatching { future.get().unbindAll() } }, ContextCompat.getMainExecutor(context))
}
