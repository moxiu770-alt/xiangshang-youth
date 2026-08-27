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
import com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions
import com.xiangshang.youth.core.model.BodyCaptureQualityGate
import com.xiangshang.youth.core.model.BodyCaptureTask
import com.xiangshang.youth.core.model.PostureMetricCalculator
import com.xiangshang.youth.core.model.PostureMetricSnapshot
import java.util.ArrayDeque
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

internal fun bindLiveCamera(
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

        val metricSamples = mutableListOf<PoseMetricSample>()
        val displacementWindow = ArrayDeque<Double>()
        val gaitMotionWindow = ArrayDeque<Boolean>()

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
            if (clearHint) onProgress(0f)
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

        fun makeSnapshot(): PostureMetricSnapshot {
            val gaitShoulder = metricSamples.takeIf { it.isNotEmpty() }?.let {
                it.maxOf { s -> s.shoulderHeightDifferenceCm } - it.minOf { s -> s.shoulderHeightDifferenceCm }
            }
            val gaitPelvic = metricSamples.takeIf { it.isNotEmpty() }?.let {
                it.maxOf { s -> s.pelvicHeightDifferenceCm } - it.minOf { s -> s.pelvicHeightDifferenceCm }
            }
            val gaitSway = PostureMetricCalculator.range(metricSamples.map { it.spinalMidlineDeviationCm })

            return PostureMetricSnapshot(
                id = "${task.name}-${System.currentTimeMillis()}",
                task = task,
                sampleCount = metricSamples.size,
                confidence = metricSamples.map { it.confidence }.average().takeIf { it.isFinite() } ?: 0.0,
                shoulderHeightDifferenceCm = median(metricSamples.map { it.shoulderHeightDifferenceCm }),
                pelvicHeightDifferenceCm = median(metricSamples.map { it.pelvicHeightDifferenceCm }),
                headTiltDegrees = median(metricSamples.map { it.headTiltDegrees }),
                spinalMidlineDeviationCm = median(metricSamples.map { it.spinalMidlineDeviationCm }),
                thoracicRoundingDegrees = median(metricSamples.map { it.thoracicRoundingDegrees }),
                forwardHeadAngleDegrees = median(metricSamples.map { it.forwardHeadAngleDegrees }),
                // ATR/rib prominence is intentionally unavailable from this
                // 2D RGB stream; do not synthesize a number from landmarks.
                cameraProxyAtrDegrees = null,
                cameraProxyRibProminenceCm = null,
                gaitShoulderSwingDifferenceCm = if (task == BodyCaptureTask.GaitVideo) gaitShoulder else null,
                gaitPelvicSwingDifferenceCm = if (task == BodyCaptureTask.GaitVideo) gaitPelvic else null,
                gaitTrunkSwayCm = if (task == BodyCaptureTask.GaitVideo) gaitSway else null
            )
        }

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

                            val ids = if (task == BodyCaptureTask.Seated) {
                                listOf(
                                    PoseLandmark.NOSE,
                                    PoseLandmark.LEFT_EAR,
                                    PoseLandmark.RIGHT_EAR,
                                    PoseLandmark.LEFT_SHOULDER,
                                    PoseLandmark.RIGHT_SHOULDER,
                                    PoseLandmark.LEFT_HIP,
                                    PoseLandmark.RIGHT_HIP
                                )
                            } else {
                                listOf(
                                    PoseLandmark.NOSE,
                                    PoseLandmark.LEFT_SHOULDER,
                                    PoseLandmark.RIGHT_SHOULDER,
                                    PoseLandmark.LEFT_HIP,
                                    PoseLandmark.RIGHT_HIP,
                                    PoseLandmark.LEFT_ANKLE,
                                    PoseLandmark.RIGHT_ANKLE
                                )
                            }

                            val confidences = ids.map { pose.getPoseLandmark(it)?.inFrameLikelihood ?: 0f }
                            if (!BodyCaptureQualityGate.hasReliableLandmarks(confidences, childAgeMonths)) {
                                resetCaptureState(false)
                                onPrompt(if (task == BodyCaptureTask.Seated) {
                                    "请让肩部和髋部清晰入镜，保持光线充足。"
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
                            val nose = pose.getPoseLandmark(PoseLandmark.NOSE)
                            val leftAnkle = pose.getPoseLandmark(PoseLandmark.LEFT_ANKLE)
                            val rightAnkle = pose.getPoseLandmark(PoseLandmark.RIGHT_ANKLE)
                            if (leftShoulder == null || rightShoulder == null || leftHip == null || rightHip == null) {
                                resetCaptureState(false)
                                onPrompt("暂未看清关键点，请保持光线充足并重新取景。")
                                return@addOnSuccessListener
                            }
                            if (task == BodyCaptureTask.Seated && (nose == null || pose.getPoseLandmark(PoseLandmark.LEFT_EAR) == null || pose.getPoseLandmark(PoseLandmark.RIGHT_EAR) == null)) {
                                resetCaptureState(false)
                                onPrompt("暂未看清头部或耳部，请保持光线充足并重新取景。")
                                return@addOnSuccessListener
                            }
                            if (task != BodyCaptureTask.Seated && (nose == null || leftAnkle == null || rightAnkle == null)) {
                                resetCaptureState(false)
                                onPrompt("暂未看清头部或双脚，请退后一步并确保全身入镜。")
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
                                val leftAnkleY = leftAnkle?.position?.y ?: run {
                                    resetCaptureState(false)
                                    onPrompt("暂未看清左脚，请退后一步并确保全身入镜。")
                                    return@addOnSuccessListener
                                }
                                val rightAnkleY = rightAnkle?.position?.y ?: run {
                                    resetCaptureState(false)
                                    onPrompt("暂未看清右脚，请退后一步并确保全身入镜。")
                                    return@addOnSuccessListener
                                }
                                kotlin.math.abs(noseY - ((leftAnkleY + rightAnkleY) / 2f)).toDouble() / image.height.coerceAtLeast(1)
                            }

                            if (!BodyCaptureQualityGate.hasUsableBodyScale(verticalCoverage, task == BodyCaptureTask.Seated, childAgeMonths)) {
                                resetCaptureState()
                                onProgress(0f)
                                onPrompt(if (task == BodyCaptureTask.Seated) {
                                    "请把手机靠近一些，让上半身占满引导框的大部分区域。"
                                } else {
                                    "请让孩子靠近一些，让身体在引导框内更清晰。"
                                })
                                return@addOnSuccessListener
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

                            val torsoTilt = kotlin.math.abs(shoulderX - hipX) / kotlin.math.abs(shoulderY - hipY).coerceAtLeast(.001)
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
                            val trunkOffsetCm = PostureMetricCalculator.centimeters(trunkOffsetNormalized.toDouble(), bodyHeightNormalized, measuredHeightCm) ?: 0.0
                            // A single RGB/2D camera cannot measure rib
                            // prominence or ATR. The former midpoint-distance
                            // formula was mathematically zero by construction;
                            // leave these fields unavailable until validated
                            // depth/3D or scoliometer-backed measurement exists.
                            metricSamples += PoseMetricSample(
                                confidence = confidences.average().toDouble(),
                                shoulderHeightDifferenceCm = shoulderGap.toDouble(),
                                pelvicHeightDifferenceCm = pelvicGap.toDouble(),
                                headTiltDegrees = headTilt,
                                spinalMidlineDeviationCm = trunkOffsetCm,
                                thoracicRoundingDegrees = kotlin.math.abs(torsoTilt * 180 / Math.PI),
                                forwardHeadAngleDegrees = forwardHead
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

                            if (task != BodyCaptureTask.GaitVideo) {
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
                                onPrompt("请保持自然不动，画面稳定后开始计时。")
                                return@addOnSuccessListener
                            }

                            stableFrames++
                            if (stableSince == 0L) stableSince = SystemClock.elapsedRealtime()
                            val elapsed = SystemClock.elapsedRealtime() - stableSince

                            val enough = if (task == BodyCaptureTask.GaitVideo) {
                                val movedFrames = gaitMotionWindow.count { it }
                                val moved = movedFrames >= gate.gaitMovementWindowFrames / 2
                                onPrompt(if (moved) "节奏已确认，请继续自然走完三步。" else "请固定手机，沿直线自然走三步。")
                                onProgress(BodyCaptureQualityGate.gaitProgress(elapsed, moved, childAgeMonths))
                                BodyCaptureQualityGate.gaitReady(elapsed, displacementRatio, movedFrames, childAgeMonths)
                            } else {
                                if (task == BodyCaptureTask.ForwardBend && torsoTilt < gate.forwardBendMinimumTorsoTiltRatio) {
                                    stableFrames = 0
                                    stableSince = 0
                                    firstHipX = hipX
                                    firstHipY = hipY
                                    metricSamples.clear()
                                    onProgress(0f)
                                    onPrompt("请从侧后方拍摄，缓慢前屈到舒适位置后停住；感到不适请立即停止。")
                                    return@addOnSuccessListener
                                }

                                val stableDisplacement = median(displacementWindow.toList()) ?: displacementRatio
                                val jitter = mad(displacementWindow.toList())
                                val stableHold = gate.staticHoldMilliseconds.toDouble() / 1000.0
                                val remaining = kotlin.math.max(0, kotlin.math.ceil(stableHold - elapsed / 1000.0).toInt())
                                onPrompt(if (remaining > 0) "画面稳定，请保持自然姿势${remaining}秒。" else "记录完成，请保持不动。")
                                onProgress(BodyCaptureQualityGate.staticProgress(elapsed, childAgeMonths))

                                if (task == BodyCaptureTask.ForwardBend) {
                                    BodyCaptureQualityGate.forwardBendReady(elapsed, stableFrames, stableDisplacement, torsoTilt, childAgeMonths)
                                } else {
                                    BodyCaptureQualityGate.staticReady(elapsed, stableFrames, stableDisplacement, jitter, childAgeMonths)
                                }
                            }

                            if (enough && !finished) {
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
                        .addOnFailureListener { if (isCurrent()) onPrompt("正在重新确认画面，请保持全身入镜。") }
                        .addOnCompleteListener { imageProxy.close() }
                }
            }

        runCatching {
            if (!isCurrent()) return@addListener
            onReady(false)
            provider.unbindAll()
            if (!isCurrent()) return@addListener

            provider.bindToLifecycle(
                lifecycleOwner,
                if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                analysis
            )

            if (isCurrent()) onReady(true)
        }.onFailure {
            if (isCurrent()) {
                onProgress(0f)
                onReady(false)
                onFailure("相机启动失败，请检查权限或切换摄像头后重试。")
            }
        }
    }, ContextCompat.getMainExecutor(context))
}

private data class PoseMetricSample(
    val confidence: Double,
    val shoulderHeightDifferenceCm: Double,
    val pelvicHeightDifferenceCm: Double,
    val headTiltDegrees: Double,
    val spinalMidlineDeviationCm: Double,
    val thoracicRoundingDegrees: Double,
    val forwardHeadAngleDegrees: Double
)

