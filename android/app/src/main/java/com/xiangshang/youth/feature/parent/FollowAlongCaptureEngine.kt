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
import kotlin.math.min
import kotlin.math.roundToInt
import org.json.JSONObject

/**
 * Child follow-along calibration and on-device pose capture.
 * Kept separate from Compose screens so visual changes cannot alter movement
 * thresholds, camera binding, or the privacy-preserving frame pipeline.
 */
data class FollowAlongAgeProfile(
    val label: String,
    val minLandmarkConfidence: Float,
    val minAverageConfidence: Float,
    val calibrationFrames: Int,
    val stablePeakFrames: Int,
    val stableReturnFrames: Int,
    val minRepIntervalMs: Long,
    val amplitudeScale: Float,
    val activeGateRatio: Float = 0.55f,
    val lowGateRatio: Float = 0.33f,
    val qualityAmplitudeWeight: Float = 0.55f,
    val signalToleranceScale: Float = 1f,
    val intervalScale: Float = 1f,
    val smoothScale: Float = 1f,
    val outlierTrimRatio: Float = 0.14f,
    val stabilityGateScale: Float = 1f,
    val dynamicGateFloor: Float = 0.72f,
    val dynamicGateCeiling: Float = 1.26f,
    val confidenceWindowFrames: Int = 18
)

data class FollowAlongActionProfile(
    val minSignalRange: Float,
    val minRepIntervalMs: Long,
    val highGateRatio: Float = 0.18f,
    val lowGateRatio: Float = 0.18f,
    val historyLen: Int = 40,
    val minHistory: Int = 6,
    val smoothAlpha: Float = 0.35f,
    val stablePeakFrames: Int = 2,
    val stableReturnFrames: Int = 2,
    val minConfidencePenalty: Float = 0f,
    val derivativeMin: Float = 0.008f,
    val derivativeScale: Float = 1f,
    val qualityStabilityWeight: Float = 0.28f,
    val activeGateRatio: Float = 1f,
    val rangeNoiseMultiplier: Float = 3.4f,
    val settlingFrames: Int = 2,
    val requiredSignalHistoryFrames: Int = 22,
    val confidenceTrim: Float = 0.22f,
    val topHoldFrames: Int = 2,
    val returnHoldFrames: Int = 2,
    val maxRepIntervalMs: Long = 0L,
    val minDropRatio: Float = 0.26f,
    val minDropAbsolute: Float = 0f,
    val returnSlopeMinRatio: Float = 0.82f,
    val returnConfidenceFloor: Float = 0.78f
)

/**
 * 训练来源说明：
 * 1) 先对齐体育跟跳项目中的儿童回放阈值（repCounter.js）；
 * 2) 结合公开姿态计次实践（基于关节点角度/速度门限）修正“回放补偿”；
 * 3) 加入“先稳定再计次 + 动态门限 + 噪声抑制”，并对 6–8 岁增加更强抗抖与更长定点时长。
 * 4) 计次逻辑采用“先确认峰值有效，再确认回位完成”的双向稳定条件，减少儿童场景漏检与抖动误计。
 */
object ChildFollowAlongTuning {
    const val algorithmVersion = "UY-FOLLOW-CV-1.0"
    const val calibrationVersion = "UY-CAL-BASELINE-1.0"
    const val canonicalAssetVersion = "android-child-precision-2026-09-16-child-motion-research-v4.1"
    private data class AgeProfileOverride(val minAgeMonths: Int, val maxAgeMonths: Int, val profile: FollowAlongAgeProfile)
    private data class ActionProfileOverride(val category: String, val minAgeMonths: Int, val maxAgeMonths: Int, val profile: FollowAlongActionProfile)

    private val defaultProfile = FollowAlongAgeProfile(
        label = "8–12岁",
        minLandmarkConfidence = 0.30f,
        minAverageConfidence = 0.42f,
        calibrationFrames = 24,
        stablePeakFrames = 4,
        stableReturnFrames = 4,
        minRepIntervalMs = 680L,
        amplitudeScale = 0.96f,
        activeGateRatio = 0.53f,
        lowGateRatio = 0.34f,
        qualityAmplitudeWeight = 0.58f,
        signalToleranceScale = 0.98f,
        intervalScale = 0.98f,
        smoothScale = 1.02f,
        outlierTrimRatio = 0.14f,
        stabilityGateScale = 1f,
        dynamicGateFloor = 0.72f,
        dynamicGateCeiling = 1.28f,
        confidenceWindowFrames = 20
    )
    private val actionDefaults = mapOf(
        "front_raise" to FollowAlongActionProfile(
            minSignalRange = 0.095f,
            minRepIntervalMs = 620L,
            derivativeMin = 0.0068f,
            derivativeScale = 1.04f,
            highGateRatio = 0.25f,
            lowGateRatio = 0.18f,
            qualityStabilityWeight = 0.24f,
            activeGateRatio = 0.56f,
            rangeNoiseMultiplier = 3.8f,
            requiredSignalHistoryFrames = 24,
            stablePeakFrames = 2,
            stableReturnFrames = 2
        ),
        "lateral_raise" to FollowAlongActionProfile(
            minSignalRange = 0.095f,
            minRepIntervalMs = 620L,
            derivativeMin = 0.0068f,
            derivativeScale = 1.04f,
            highGateRatio = 0.25f,
            lowGateRatio = 0.18f,
            qualityStabilityWeight = 0.24f,
            activeGateRatio = 0.56f,
            rangeNoiseMultiplier = 3.8f,
            requiredSignalHistoryFrames = 24,
            stablePeakFrames = 2,
            stableReturnFrames = 2
        ),
        "squat" to FollowAlongActionProfile(
            minSignalRange = 0.052f,
            minRepIntervalMs = 820L,
            highGateRatio = 0.20f,
            lowGateRatio = 0.17f,
            derivativeMin = 0.0076f,
            derivativeScale = 0.97f,
            activeGateRatio = 0.40f,
            rangeNoiseMultiplier = 3.0f,
            requiredSignalHistoryFrames = 25,
            stablePeakFrames = 2,
            stableReturnFrames = 2
        ),
        "squat_challenge" to FollowAlongActionProfile(
            minSignalRange = 0.057f,
            minRepIntervalMs = 1020L,
            highGateRatio = 0.21f,
            lowGateRatio = 0.17f,
            derivativeMin = 0.0088f,
            derivativeScale = 0.98f,
            activeGateRatio = 0.41f,
            rangeNoiseMultiplier = 3.25f,
            requiredSignalHistoryFrames = 25,
            stablePeakFrames = 2,
            stableReturnFrames = 3
        ),
        "lunge" to FollowAlongActionProfile(
            minSignalRange = 0.056f,
            minRepIntervalMs = 980L,
            highGateRatio = 0.20f,
            lowGateRatio = 0.17f,
            derivativeMin = 0.0082f,
            derivativeScale = 0.99f,
            activeGateRatio = 0.40f,
            rangeNoiseMultiplier = 3.25f,
            requiredSignalHistoryFrames = 25,
            stablePeakFrames = 2,
            stableReturnFrames = 2
        ),
        "jumping_jack" to FollowAlongActionProfile(
            minSignalRange = 0.040f,
            minRepIntervalMs = 560L,
            derivativeMin = 0.0062f,
            derivativeScale = 1.08f,
            highGateRatio = 0.15f,
            activeGateRatio = 0.33f,
            rangeNoiseMultiplier = 2.6f,
            requiredSignalHistoryFrames = 36,
            historyLen = 52,
            stablePeakFrames = 6,
            stableReturnFrames = 6,
            topHoldFrames = 6,
            returnHoldFrames = 7,
            maxRepIntervalMs = 1980L,
            minDropRatio = 0.52f,
            minDropAbsolute = 0.0118f,
            returnSlopeMinRatio = 1.2f,
            returnConfidenceFloor = 0.9f
        ),
        "high_knee" to FollowAlongActionProfile(
            minSignalRange = 0.102f,
            minRepIntervalMs = 560L,
            highGateRatio = 0.11f,
            lowGateRatio = 0.11f,
            derivativeMin = 0.0054f,
            derivativeScale = 1.04f,
            activeGateRatio = 0.34f,
            rangeNoiseMultiplier = 2.9f,
            requiredSignalHistoryFrames = 35,
            historyLen = 52,
            stablePeakFrames = 6,
            stableReturnFrames = 6,
            topHoldFrames = 6,
            returnHoldFrames = 7,
            maxRepIntervalMs = 1760L,
            minDropRatio = 0.48f,
            minDropAbsolute = 0.0135f,
            returnSlopeMinRatio = 1.18f,
            returnConfidenceFloor = 0.89f
        ),
        "sit_up" to FollowAlongActionProfile(
            minSignalRange = 0.088f,
            minRepIntervalMs = 670L,
            highGateRatio = 0.18f,
            derivativeMin = 0.0078f,
            derivativeScale = 1.01f,
            activeGateRatio = 0.37f,
            rangeNoiseMultiplier = 3.2f,
            requiredSignalHistoryFrames = 26,
            stablePeakFrames = 2,
            stableReturnFrames = 2
        ),
        "plank" to FollowAlongActionProfile(
            minSignalRange = 0.034f,
            minRepIntervalMs = 2050L,
            derivativeMin = 0.0036f,
            derivativeScale = 0.96f,
            qualityStabilityWeight = 0.35f,
            activeGateRatio = 0.25f,
            rangeNoiseMultiplier = 2.4f,
            requiredSignalHistoryFrames = 26,
            stablePeakFrames = 3,
            stableReturnFrames = 3
        ),
        "burpee" to FollowAlongActionProfile(
            minSignalRange = 0.138f,
            minRepIntervalMs = 1180L,
            highGateRatio = 0.22f,
            lowGateRatio = 0.17f,
            derivativeMin = 0.0096f,
            derivativeScale = 1.02f,
            activeGateRatio = 0.42f,
            rangeNoiseMultiplier = 3.4f,
            requiredSignalHistoryFrames = 24,
            stablePeakFrames = 2,
            stableReturnFrames = 2
        ),
        "jump_rope" to FollowAlongActionProfile(
            minSignalRange = 0.06f,
            minRepIntervalMs = 760L,
            highGateRatio = 0.16f,
            derivativeMin = 0.0072f,
            derivativeScale = 1.06f,
            activeGateRatio = 0.36f,
            rangeNoiseMultiplier = 2.8f,
            requiredSignalHistoryFrames = 37,
            historyLen = 52,
            stablePeakFrames = 6,
            stableReturnFrames = 6,
            topHoldFrames = 8,
            returnHoldFrames = 9,
            maxRepIntervalMs = 2040L,
            minDropRatio = 0.56f,
            minDropAbsolute = 0.0158f,
            returnSlopeMinRatio = 1.32f,
            returnConfidenceFloor = 0.90f
        ),
    )
    private val actionFallback = FollowAlongActionProfile(
        minSignalRange = 0.05f,
        minRepIntervalMs = 480L,
        historyLen = 40,
        minHistory = 6,
        smoothAlpha = 0.35f,
        rangeNoiseMultiplier = 3.2f,
        requiredSignalHistoryFrames = 20,
        activeGateRatio = 0.36f
    )

    private val overrideLock = Any()
    private var ageProfileOverrides: List<AgeProfileOverride> = emptyList()
    private var actionProfileOverrides: Map<String, List<ActionProfileOverride>> = emptyMap()

    private fun builtInProfileForAge(ageMonths: Int?): FollowAlongAgeProfile = when {
        ageMonths == null -> defaultProfile
        ageMonths <= 96 -> FollowAlongAgeProfile(
            label = "6-8岁",
            minLandmarkConfidence = 0.34f,
            minAverageConfidence = 0.47f,
            calibrationFrames = 30,
            stablePeakFrames = 5,
            stableReturnFrames = 5,
            minRepIntervalMs = 800L,
            amplitudeScale = 0.70f,
            activeGateRatio = 0.58f,
            lowGateRatio = 0.34f,
            qualityAmplitudeWeight = 0.61f,
            signalToleranceScale = 0.86f,
            intervalScale = 1.12f,
            smoothScale = 0.98f,
            outlierTrimRatio = 0.17f,
            stabilityGateScale = 1.14f,
            dynamicGateFloor = 0.66f,
            dynamicGateCeiling = 1.34f,
            confidenceWindowFrames = 22
        )
        ageMonths in 97..132 -> FollowAlongAgeProfile(
            label = "9-11岁",
            minLandmarkConfidence = 0.33f,
            minAverageConfidence = 0.46f,
            calibrationFrames = 26,
            stablePeakFrames = 5,
            stableReturnFrames = 5,
            minRepIntervalMs = 790L,
            amplitudeScale = 0.82f,
            activeGateRatio = 0.57f,
            lowGateRatio = 0.33f,
            qualityAmplitudeWeight = 0.59f,
            signalToleranceScale = 0.92f,
            intervalScale = 1.03f,
            smoothScale = 0.98f,
            outlierTrimRatio = 0.14f,
            stabilityGateScale = 1.02f,
            dynamicGateFloor = 0.68f,
            dynamicGateCeiling = 1.31f,
            confidenceWindowFrames = 20
        )
        ageMonths in 133..168 -> FollowAlongAgeProfile(
            label = "11-14岁",
            minLandmarkConfidence = 0.325f,
            minAverageConfidence = 0.445f,
            calibrationFrames = 24,
            stablePeakFrames = 4,
            stableReturnFrames = 4,
            minRepIntervalMs = 650L,
            amplitudeScale = 0.86f,
            activeGateRatio = 0.55f,
            lowGateRatio = 0.32f,
            qualityAmplitudeWeight = 0.56f,
            signalToleranceScale = 1f,
            intervalScale = 1f,
            smoothScale = 1f,
            outlierTrimRatio = 0.12f,
            stabilityGateScale = 1f,
            dynamicGateFloor = 0.72f,
            dynamicGateCeiling = 1.25f,
            confidenceWindowFrames = 18
        )
        ageMonths in 169..216 -> FollowAlongAgeProfile(
            label = "14-18岁",
            minLandmarkConfidence = 0.31f,
            minAverageConfidence = 0.43f,
            calibrationFrames = 24,
            stablePeakFrames = 4,
            stableReturnFrames = 4,
            minRepIntervalMs = 620L,
            amplitudeScale = 0.9f,
            activeGateRatio = 0.55f,
            lowGateRatio = 0.32f,
            qualityAmplitudeWeight = 0.55f,
            signalToleranceScale = 1.02f,
            intervalScale = 0.98f,
            smoothScale = 1.01f,
            outlierTrimRatio = 0.11f,
            stabilityGateScale = 1f,
            dynamicGateFloor = 0.74f,
            dynamicGateCeiling = 1.24f,
            confidenceWindowFrames = 17
        )
        else -> defaultProfile.copy(
            label = "14-18岁",
            minAverageConfidence = 0.425f,
            minRepIntervalMs = 600L,
            amplitudeScale = 1.00f,
            qualityAmplitudeWeight = 0.54f,
            signalToleranceScale = 1.02f,
            intervalScale = 0.95f,
            smoothScale = 1.03f,
            outlierTrimRatio = 0.10f,
            stabilityGateScale = 0.98f,
            dynamicGateFloor = 0.76f,
            dynamicGateCeiling = 1.2f,
            confidenceWindowFrames = 16
        )
    }

    private fun resolveActionBase(category: String, ageMonths: Int): FollowAlongActionProfile {
        val rules = synchronized(overrideLock) { actionProfileOverrides[category] } ?: return actionDefaults[category] ?: actionFallback
        return rules.firstOrNull { ageMonths in it.minAgeMonths..it.maxAgeMonths }?.profile
            ?: rules.firstOrNull { it.minAgeMonths == Int.MIN_VALUE && it.maxAgeMonths == Int.MAX_VALUE }?.profile
            ?: actionDefaults[category]
            ?: actionFallback
    }

    private fun resolveActionBase(category: String, ageProfile: FollowAlongAgeProfile): FollowAlongActionProfile {
        val representativeAgeMonths = ageMonthsForLabel(ageProfile.label)
        return if (representativeAgeMonths != null) resolveActionBase(category, representativeAgeMonths) else actionDefaults[category] ?: actionFallback
    }

    private fun ageMonthsForLabel(label: String): Int? {
        val normalized = label.trim().replace("–", "-")
        val range = Regex("(\\d{1,2})-(\\d{1,2})").find(normalized) ?: return null
        val a = range.groupValues[1].toIntOrNull() ?: return null
        val b = range.groupValues[2].toIntOrNull() ?: return null
        return ((a + b) * 6)
    }

    fun setProfileOverridesFromJson(raw: String): Boolean {
        return runCatching {
            val root = JSONObject(raw)
            val assetVersion = root.optJSONObject("meta")?.optString("version").orEmpty()
            if (assetVersion.isNotBlank() && assetVersion != canonicalAssetVersion) throw IllegalArgumentException("unsupported follow-along asset version")
            val ageOverrides = parseAgeProfileOverrides(root)
            val actionOverrides = parseActionProfileOverrides(root)

            // Versioned assets are release artifacts, not partial hot overrides.
            // Require the complete canonical matrix so iOS and Android cannot
            // silently run different age bands or action categories in production.
            if (assetVersion.isNotBlank() && !isCanonicalManifest(ageOverrides, actionOverrides)) {
                throw IllegalArgumentException("incomplete follow-along canonical asset")
            }

            if (ageOverrides.isEmpty() && actionOverrides.isEmpty()) {
                throw IllegalArgumentException("no valid override data")
            }

            synchronized(overrideLock) {
                ageProfileOverrides = ageOverrides.sortedWith(compareBy({ it.minAgeMonths }, { it.maxAgeMonths }))
                actionProfileOverrides = actionOverrides
                    .groupBy { it.category }
                    .mapValues { entry -> entry.value.sortedBy { it.minAgeMonths } }
            }
        }.isSuccess
    }

    private fun isCanonicalManifest(
        ageOverrides: List<AgeProfileOverride>,
        actionOverrides: List<ActionProfileOverride>
    ): Boolean {
        val expectedBands = listOf(72 to 96, 97 to 132, 133 to 168, 169 to 216)
        val actualBands = ageOverrides.map { it.minAgeMonths to it.maxAgeMonths }
        if (actualBands != expectedBands) return false

        val expectedCategories = setOf(
            "burpee", "front_raise", "high_knee", "jump_rope", "jumping_jack",
            "lateral_raise", "lunge", "plank", "sit_up", "squat", "squat_challenge"
        )
        if (actionOverrides.size != 44 || actionOverrides.map { it.category }.toSet() != expectedCategories) return false
        val keys = actionOverrides.map { "${it.category}|${it.minAgeMonths}|${it.maxAgeMonths}" }
        if (keys.toSet().size != keys.size) return false
        return actionOverrides.all { it.minAgeMonths to it.maxAgeMonths in expectedBands }
    }

    fun clearProfileOverrides() {
        synchronized(overrideLock) {
            ageProfileOverrides = emptyList()
            actionProfileOverrides = emptyMap()
        }
    }

    fun profileForAge(ageMonths: Int?): FollowAlongAgeProfile {
        val overrideProfile = ageMonths?.let { months ->
            synchronized(overrideLock) {
                ageProfileOverrides.firstOrNull { months in it.minAgeMonths..it.maxAgeMonths }?.profile
            }
        }
        return overrideProfile ?: builtInProfileForAge(ageMonths)
    }

    enum class FollowAgeBand {
        AGE_6_8,
        AGE_9_11,
        AGE_11_14,
        AGE_14_18,
        AGE_UNKNOWN
    }

    fun resolveAgeBand(ageMonths: Int?, ageProfile: FollowAlongAgeProfile): FollowAgeBand = when {
        ageMonths != null && ageMonths <= 96 -> FollowAgeBand.AGE_6_8
        ageMonths != null && ageMonths in 97..132 -> FollowAgeBand.AGE_9_11
        ageMonths != null && ageMonths in 133..168 -> FollowAgeBand.AGE_11_14
        ageMonths != null && ageMonths in 169..216 -> FollowAgeBand.AGE_14_18
        ageProfile.label.replace("–", "-").startsWith("6-8") -> FollowAgeBand.AGE_6_8
        ageProfile.label.replace("–", "-").startsWith("9-11") -> FollowAgeBand.AGE_9_11
        ageProfile.label.replace("–", "-").startsWith("11-14") -> FollowAgeBand.AGE_11_14
        ageProfile.label.replace("–", "-").startsWith("14-18") -> FollowAgeBand.AGE_14_18
        else -> FollowAgeBand.AGE_UNKNOWN
    }

    private fun childBandBias(ageBand: FollowAgeBand): Float = when (ageBand) {
        FollowAgeBand.AGE_6_8 -> 1.00f
        FollowAgeBand.AGE_9_11 -> 0.88f
        FollowAgeBand.AGE_11_14 -> 0.78f
        FollowAgeBand.AGE_14_18 -> 0.72f
        FollowAgeBand.AGE_UNKNOWN -> 0.80f
    }

    private fun jitterProtectionBonus(ageBand: FollowAgeBand): Float = when (ageBand) {
        FollowAgeBand.AGE_6_8 -> 1.20f
        FollowAgeBand.AGE_9_11 -> 1.12f
        FollowAgeBand.AGE_11_14 -> 1.06f
        FollowAgeBand.AGE_14_18 -> 1.00f
        FollowAgeBand.AGE_UNKNOWN -> 1.12f
    }

    private fun repeatBoostFrames(ageBand: FollowAgeBand): Int = when (ageBand) {
        FollowAgeBand.AGE_6_8 -> 4
        FollowAgeBand.AGE_9_11 -> 2
        FollowAgeBand.AGE_11_14 -> 1
        FollowAgeBand.AGE_14_18 -> 0
        FollowAgeBand.AGE_UNKNOWN -> 2
    }

    private fun repeatBoostHold(ageBand: FollowAgeBand): Int = when (ageBand) {
        FollowAgeBand.AGE_6_8 -> 2
        FollowAgeBand.AGE_9_11 -> 1
        else -> 0
    }

    private fun dropRatioBoost(ageBand: FollowAgeBand): Float = when (ageBand) {
        FollowAgeBand.AGE_6_8 -> 1.22f
        FollowAgeBand.AGE_9_11 -> 1.10f
        FollowAgeBand.AGE_11_14 -> 0.96f
        FollowAgeBand.AGE_14_18 -> 0.90f
        FollowAgeBand.AGE_UNKNOWN -> 1.00f
    }

    private fun returnSlopeBoost(ageBand: FollowAgeBand): Float = when (ageBand) {
        FollowAgeBand.AGE_6_8 -> 1.24f
        FollowAgeBand.AGE_9_11 -> 1.08f
        FollowAgeBand.AGE_11_14 -> 0.96f
        FollowAgeBand.AGE_14_18 -> 0.92f
        FollowAgeBand.AGE_UNKNOWN -> 1.00f
    }

    private fun confidenceFloorBoost(ageBand: FollowAgeBand): Float = when (ageBand) {
        FollowAgeBand.AGE_6_8 -> 1.12f
        FollowAgeBand.AGE_9_11 -> 1.05f
        FollowAgeBand.AGE_11_14 -> 1.00f
        FollowAgeBand.AGE_14_18 -> 0.96f
        FollowAgeBand.AGE_UNKNOWN -> 1.00f
    }

    private fun actionPrecisionHoldBoost(ageBand: FollowAgeBand, category: String): Int = when (ageBand) {
        FollowAgeBand.AGE_6_8 -> when (category) {
            "jump_rope", "jumping_jack", "high_knee" -> 2
            "squat", "lunge", "squat_challenge", "burpee", "front_raise", "lateral_raise", "sit_up", "plank" -> 1
            else -> 0
        }
        FollowAgeBand.AGE_9_11 -> when (category) {
            "jump_rope", "jumping_jack", "high_knee" -> 1
            "squat", "lunge", "squat_challenge", "burpee" -> 1
            else -> 0
        }
        FollowAgeBand.AGE_11_14, FollowAgeBand.AGE_14_18 -> 0
        FollowAgeBand.AGE_UNKNOWN -> 0
    }

    private fun actionPrecisionRepScale(ageBand: FollowAgeBand, category: String): Float = when (ageBand) {
        FollowAgeBand.AGE_6_8 -> when (category) {
            "jump_rope", "jumping_jack", "high_knee" -> 1.10f
            "squat", "lunge", "squat_challenge", "burpee", "front_raise", "lateral_raise", "sit_up", "plank" -> 1.06f
            else -> 1.00f
        }
        FollowAgeBand.AGE_9_11 -> when (category) {
            "jump_rope", "jumping_jack", "high_knee" -> 1.04f
            "squat", "lunge", "squat_challenge", "burpee" -> 1.02f
            else -> 1.00f
        }
        else -> 1.00f
    }

    private fun actionPrecisionDropScale(ageBand: FollowAgeBand, category: String): Float = when (ageBand) {
        FollowAgeBand.AGE_6_8 -> when (category) {
            "jump_rope", "jumping_jack", "high_knee" -> 1.10f
            "squat", "lunge", "squat_challenge", "burpee" -> 1.08f
            else -> 1.00f
        }
        FollowAgeBand.AGE_9_11 -> when (category) {
            "squat", "lunge", "squat_challenge", "burpee" -> 1.04f
            else -> 1.00f
        }
        else -> 1.00f
    }

    fun actionProfileFor(category: String, ageProfile: FollowAlongAgeProfile, ageMonths: Int? = null): FollowAlongActionProfile {
        val ageBand = resolveAgeBand(ageMonths, ageProfile)
        val childBandBoost = repeatBoostFrames(ageBand)
        val holdFramesBoost = repeatBoostHold(ageBand)
        val childDropBoost = dropRatioBoost(ageBand)
        val childReturnSlopeBoost = returnSlopeBoost(ageBand)
        val childConfidenceBoost = confidenceFloorBoost(ageBand)
        val jitterBonus = jitterProtectionBonus(ageBand)
        val base = ageMonths?.let { resolveActionBase(category, it) } ?: resolveActionBase(category, ageProfile)
        val resolvedMaxRepMs = if (base.maxRepIntervalMs > 0L) base.maxRepIntervalMs else (base.minRepIntervalMs * 2.45f).toLong()
        return base.copy(
            minSignalRange = base.minSignalRange * ageProfile.amplitudeScale * ageProfile.signalToleranceScale,
            minRepIntervalMs = (base.minRepIntervalMs * ageProfile.intervalScale * childBandBias(ageBand)).toLong()
                .coerceAtLeast(320L + if (ageBand == FollowAgeBand.AGE_6_8) 40 else if (ageBand == FollowAgeBand.AGE_9_11) 25 else 0)
                .let { (it * actionPrecisionRepScale(ageBand, category)).toLong() }
                .coerceAtLeast(base.minRepIntervalMs),
            maxRepIntervalMs = (resolvedMaxRepMs * (1f + (childDropBoost - 1f) * 0.45f)).toLong()
                .coerceAtLeast((base.minRepIntervalMs * 1.6f).toLong()),
            smoothAlpha = (base.smoothAlpha * ageProfile.smoothScale).coerceIn(0.18f, 0.52f),
            highGateRatio = (base.highGateRatio * ageProfile.smoothScale * 0.98f).coerceIn(0.10f, 0.34f),
            lowGateRatio = (base.lowGateRatio * ageProfile.smoothScale * 0.98f).coerceIn(0.10f, 0.34f),
            stablePeakFrames = ((base.stablePeakFrames * (ageProfile.outlierTrimRatio + 0.8f) * ageProfile.stabilityGateScale))
                .toInt().coerceAtLeast(base.stablePeakFrames.coerceAtLeast(2)),
            stableReturnFrames = ((base.stableReturnFrames * (ageProfile.outlierTrimRatio + 0.8f) * ageProfile.stabilityGateScale))
                .toInt().coerceAtLeast(base.stableReturnFrames.coerceAtLeast(2)),
            derivativeMin = (base.derivativeMin * ageProfile.smoothScale * base.derivativeScale * (1f + childBandBoost * 0.035f)).coerceIn(0.002f, 0.035f),
            activeGateRatio = (base.activeGateRatio * ageProfile.activeGateRatio * ageProfile.smoothScale * jitterBonus).coerceIn(0.18f, 1.10f),
            requiredSignalHistoryFrames = maxOf(
                base.requiredSignalHistoryFrames + childBandBoost,
                (ageProfile.calibrationFrames * 0.55f).toInt()
            ),
            minDropRatio = (base.minDropRatio * childDropBoost * actionPrecisionDropScale(ageBand, category)).coerceIn(0.16f, 1.05f),
            minDropAbsolute = base.minDropAbsolute + if (ageBand == FollowAgeBand.AGE_6_8) 0.008f else if (ageBand == FollowAgeBand.AGE_9_11) 0.006f else 0f,
            returnSlopeMinRatio = (base.returnSlopeMinRatio * childReturnSlopeBoost).coerceIn(0.70f, 1.28f),
            returnConfidenceFloor = (base.returnConfidenceFloor * childConfidenceBoost)
                .coerceIn(ageProfile.minAverageConfidence * 0.80f, 0.92f),
            settlingFrames = when (ageBand) {
                FollowAgeBand.AGE_6_8 -> 6
                FollowAgeBand.AGE_9_11 -> 4
                FollowAgeBand.AGE_11_14 -> 3
                FollowAgeBand.AGE_14_18 -> 2
                FollowAgeBand.AGE_UNKNOWN -> 4
            },
            rangeNoiseMultiplier = (base.rangeNoiseMultiplier * (0.92f + ageProfile.stabilityGateScale * 0.06f) * jitterBonus).coerceIn(2.2f, 4.55f),
            confidenceTrim = (base.confidenceTrim * ageProfile.smoothScale).coerceIn(0.10f, 0.35f),
            topHoldFrames = (base.topHoldFrames + holdFramesBoost + actionPrecisionHoldBoost(ageBand, category))
                .coerceAtLeast(base.topHoldFrames),
            returnHoldFrames = (base.returnHoldFrames + holdFramesBoost + actionPrecisionHoldBoost(ageBand, category))
                .coerceAtLeast(base.returnHoldFrames)
        )
    }

    private fun parseAgeProfileOverrides(root: JSONObject): List<AgeProfileOverride> {
        val nodes = root.optJSONArray("ageProfiles") ?: return emptyList()
        val parsed = mutableListOf<AgeProfileOverride>()

        for (i in 0 until nodes.length()) {
            val node = nodes.getJSONObject(i)
            val minAgeMonths = node.optInt("minAgeMonths", Int.MIN_VALUE)
            val maxAgeMonths = node.optInt("maxAgeMonths", Int.MAX_VALUE)
            if (minAgeMonths == Int.MIN_VALUE || maxAgeMonths == Int.MAX_VALUE) {
                throw IllegalArgumentException("ageProfiles[$i] missing minAgeMonths/maxAgeMonths")
            }

            val ageProfile = FollowAlongAgeProfile(
                label = node.optString("tag", "${minAgeMonths}–${maxAgeMonths}月"),
                minLandmarkConfidence = optFloat(node, "minLandmarkConfidence", defaultProfile.minLandmarkConfidence),
                minAverageConfidence = optFloat(node, "minAverageConfidence", defaultProfile.minAverageConfidence),
                calibrationFrames = node.optInt("calibrationFrames", defaultProfile.calibrationFrames),
                stablePeakFrames = node.optInt("stablePeakFrames", defaultProfile.stablePeakFrames),
                stableReturnFrames = node.optInt("stableReturnFrames", defaultProfile.stableReturnFrames),
                minRepIntervalMs = node.optLong("minRepIntervalMs", defaultProfile.minRepIntervalMs),
                amplitudeScale = optFloat(node, "amplitudeScale", defaultProfile.amplitudeScale),
                activeGateRatio = optFloat(node, "activeGateRatio", defaultProfile.activeGateRatio),
                lowGateRatio = optFloat(node, "lowGateRatio", defaultProfile.lowGateRatio),
                qualityAmplitudeWeight = optFloat(node, "qualityAmplitudeWeight", defaultProfile.qualityAmplitudeWeight),
                signalToleranceScale = optFloat(node, "signalToleranceScale", defaultProfile.signalToleranceScale),
                intervalScale = optFloat(node, "intervalScale", defaultProfile.intervalScale),
                smoothScale = optFloat(node, "smoothScale", defaultProfile.smoothScale),
                outlierTrimRatio = optFloat(node, "outlierTrimRatio", defaultProfile.outlierTrimRatio),
                stabilityGateScale = optFloat(node, "stabilityGateScale", defaultProfile.stabilityGateScale),
                dynamicGateFloor = optFloat(node, "dynamicGateFloor", defaultProfile.dynamicGateFloor),
                dynamicGateCeiling = optFloat(node, "dynamicGateCeiling", defaultProfile.dynamicGateCeiling),
                confidenceWindowFrames = node.optInt("confidenceWindowFrames", defaultProfile.confidenceWindowFrames)
            )
            if (minAgeMonths < 0 || maxAgeMonths < minAgeMonths || maxAgeMonths > 240 || !ageProfile.isValid()) throw IllegalArgumentException("invalid follow-along age profile")
            parsed += AgeProfileOverride(
                minAgeMonths = minAgeMonths,
                maxAgeMonths = maxAgeMonths,
                profile = ageProfile
            )
        }

        return parsed
    }

    private fun parseActionProfileOverrides(root: JSONObject): List<ActionProfileOverride> {
        val nodes = root.optJSONArray("actionProfiles") ?: return emptyList()
        val parsed = mutableListOf<ActionProfileOverride>()

        for (i in 0 until nodes.length()) {
            val node = nodes.getJSONObject(i)
            val category = node.optString("category").trim()
            if (category.isBlank()) continue

            val minAgeMonths = node.optInt("minAgeMonths", Int.MIN_VALUE)
            val maxAgeMonths = node.optInt("maxAgeMonths", Int.MAX_VALUE)
            if (minAgeMonths > maxAgeMonths) throw IllegalArgumentException("actionProfiles[$i] invalid age range")
            val fallback = actionDefaults[category] ?: actionFallback

            val actionProfile = FollowAlongActionProfile(
                minSignalRange = optFloat(node, "minSignalRange", fallback.minSignalRange),
                minRepIntervalMs = optLong(node, "minRepIntervalMs", fallback.minRepIntervalMs),
                highGateRatio = optFloat(node, "highGateRatio", fallback.highGateRatio),
                lowGateRatio = optFloat(node, "lowGateRatio", fallback.lowGateRatio),
                historyLen = optInt(node, "historyLen", fallback.historyLen),
                minHistory = optInt(node, "minHistory", fallback.minHistory),
                smoothAlpha = optFloat(node, "smoothAlpha", fallback.smoothAlpha),
                stablePeakFrames = optInt(node, "stablePeakFrames", fallback.stablePeakFrames),
                stableReturnFrames = optInt(node, "stableReturnFrames", fallback.stableReturnFrames),
                minConfidencePenalty = optFloat(node, "minConfidencePenalty", fallback.minConfidencePenalty),
                derivativeMin = optFloat(node, "derivativeMin", fallback.derivativeMin),
                derivativeScale = optFloat(node, "derivativeScale", fallback.derivativeScale),
                qualityStabilityWeight = optFloat(node, "qualityStabilityWeight", fallback.qualityStabilityWeight),
                activeGateRatio = optFloat(node, "activeGateRatio", fallback.activeGateRatio),
                rangeNoiseMultiplier = optFloat(node, "rangeNoiseMultiplier", fallback.rangeNoiseMultiplier),
                settlingFrames = optInt(node, "settlingFrames", fallback.settlingFrames),
                requiredSignalHistoryFrames = optInt(node, "requiredSignalHistoryFrames", fallback.requiredSignalHistoryFrames),
                confidenceTrim = optFloat(node, "confidenceTrim", fallback.confidenceTrim),
                topHoldFrames = optInt(node, "topHoldFrames", fallback.topHoldFrames),
                returnHoldFrames = optInt(node, "returnHoldFrames", fallback.returnHoldFrames),
                maxRepIntervalMs = optLong(node, "maxRepIntervalMs", fallback.maxRepIntervalMs),
                minDropRatio = optFloat(node, "minDropRatio", fallback.minDropRatio),
                minDropAbsolute = optFloat(node, "minDropAbsolute", fallback.minDropAbsolute),
                returnSlopeMinRatio = optFloat(node, "returnSlopeMinRatio", fallback.returnSlopeMinRatio),
                returnConfidenceFloor = optFloat(node, "returnConfidenceFloor", fallback.returnConfidenceFloor)
            )
            if (!actionProfile.isValid()) throw IllegalArgumentException("invalid follow-along action profile")
            parsed += ActionProfileOverride(
                category = category,
                minAgeMonths = minAgeMonths,
                maxAgeMonths = maxAgeMonths,
                profile = actionProfile
            )
        }

        return parsed
    }

    private fun FollowAlongAgeProfile.isValid(): Boolean {
        fun finiteRatio(value: Float, upper: Float = 2f) = value.isFinite() && value in 0f..upper
        return finiteRatio(minLandmarkConfidence, 1f) && finiteRatio(minAverageConfidence, 1f) &&
            calibrationFrames in 4..240 && stablePeakFrames in 1..120 && stableReturnFrames in 1..120 &&
            minRepIntervalMs in 100L..30_000L && finiteRatio(amplitudeScale) && finiteRatio(activeGateRatio) &&
            finiteRatio(lowGateRatio) && finiteRatio(qualityAmplitudeWeight, 1f) && finiteRatio(signalToleranceScale) &&
            finiteRatio(intervalScale) && finiteRatio(smoothScale) && finiteRatio(outlierTrimRatio, .5f) &&
            finiteRatio(stabilityGateScale) && finiteRatio(dynamicGateFloor) && finiteRatio(dynamicGateCeiling) &&
            dynamicGateCeiling >= dynamicGateFloor && confidenceWindowFrames in 4..240
    }

    private fun FollowAlongActionProfile.isValid(): Boolean {
        fun finiteRatio(value: Float, upper: Float = 3f) = value.isFinite() && value in 0f..upper
        return minSignalRange.isFinite() && minSignalRange in .001f..1.5f && minRepIntervalMs in 100L..30_000L &&
            finiteRatio(highGateRatio) && finiteRatio(lowGateRatio) && historyLen in 6..240 && minHistory in 3..historyLen &&
            finiteRatio(smoothAlpha, 1f) && stablePeakFrames in 1..120 && stableReturnFrames in 1..120 &&
            finiteRatio(minConfidencePenalty, 1f) && finiteRatio(derivativeMin) && finiteRatio(derivativeScale) &&
            finiteRatio(qualityStabilityWeight, 1f) && finiteRatio(activeGateRatio) && rangeNoiseMultiplier.isFinite() && rangeNoiseMultiplier in 0f..10f &&
            settlingFrames in 0..120 && requiredSignalHistoryFrames in minHistory..240 && confidenceTrim in 0f..0.5f &&
            topHoldFrames in 1..120 && returnHoldFrames in 1..120 && maxRepIntervalMs in 0L..60_000L &&
            finiteRatio(minDropRatio) && finiteRatio(minDropAbsolute) && finiteRatio(returnSlopeMinRatio) && finiteRatio(returnConfidenceFloor, 1f)
    }

    private fun optFloat(node: JSONObject, key: String, fallback: Float): Float {
        return if (node.has(key) && !node.isNull(key)) node.getDouble(key).toFloat() else fallback
    }

    private fun optLong(node: JSONObject, key: String, fallback: Long): Long {
        return if (node.has(key) && !node.isNull(key)) node.getLong(key) else fallback
    }

    private fun optInt(node: JSONObject, key: String, fallback: Int): Int {
        return if (node.has(key) && !node.isNull(key)) node.getInt(key) else fallback
    }
}

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
