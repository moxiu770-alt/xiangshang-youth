package com.xiangshang.youth.core.model

import java.text.SimpleDateFormat
import java.util.Date
import java.util.TimeZone
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

enum class BodyAttentionLevel(val label: String) {
    /** A data-completeness state, not a health-risk classification. */
    Pending("待完成拍摄记录"),
    Green("本次观察已完成"),
    Yellow("建议关注"),
    Red("建议进一步评估"),
    Unavailable("待完善生日")
}
enum class AdamsScreeningResult(val label: String) {
    Negative("阴性（未见明显不对称）"),
    Equivocal("可疑阳性（建议复测）"),
    Positive("阳性代理信号（建议专科复核）")
}

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
    /** Optional validated ATR from a calibrated instrument/depth adapter. */
    val instrumentAtrDegrees: Double? = null,
    /** Optional calibrated chest/waist ATR readings. */
    val thoracicAtrDegrees: Double? = null,
    val lumbarAtrDegrees: Double? = null,
    /** Optional supervised occiput-to-wall distance measurement. */
    val occiputWallDistanceCm: Double? = null,
    val gaitShoulderSwingDifferenceCm: Double? = null,
    val gaitPelvicSwingDifferenceCm: Double? = null,
    val gaitTrunkSwayCm: Double? = null
) {
    val adamsResult: AdamsScreeningResult?
        get() = cameraProxyRibProminenceCm?.takeIf { it.isFinite() && it >= 0.0 }?.let { when { it >= PostureScreeningRules.ribProminencePositiveCentimeters -> AdamsScreeningResult.Positive; it >= PostureScreeningRules.ribProminenceEquivocalCentimeters -> AdamsScreeningResult.Equivocal; else -> AdamsScreeningResult.Negative } }
}

/** Product screening thresholds for the on-device posture proxy. */
object PostureScreeningRules {
    const val rulesSourceVersion = "UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20"
    const val minimumSamples = 10
    const val minimumConfidence = .56
    const val headTiltAttentionDegrees = 3.0
    const val headTiltReferralDegrees = 6.0

    /** 6–18 岁场景下，1.0 cm 为关注起点，1.6 cm 为偏高风险。 */
    const val shoulderAttentionCentimeters = 1.0
    const val shoulderReferralCentimeters = 1.6
    /** 骨盆高度差 >0.5 cm 关注，>1.0 cm 建议复测。 */
    const val pelvisAttentionCentimeters = 0.5
    const val pelvisReferralCentimeters = 1.0
    /** 坐姿躯干中线偏移 >1.3 cm 在儿童样本中开始异常。 */
    const val seatedMidlineAttentionCentimeters = 1.3
    /** 2D 估算下的胸椎前凸/圆背警戒线。 */
    const val seatedRoundingAttentionDegrees = 24.0
    /** 前伸角度映射自 CVA 研究的非专业阈值近似值。 */
    const val forwardHeadAttentionDegrees = 12.0
    const val forwardHeadReferralDegrees = 16.0
    const val gaitAttentionCentimeters = 1.0
    /** 5° 提示复核，7° 建议专科转诊为常见儿童脊柱筛查边界。 */
    const val proxyAtrAttentionDegrees = 5.0
    const val proxyAtrReferralDegrees = 7.0
    /** 前屈骨骼后凸代理值偏宽容：避免儿童单次拍摄抖动过度触发红黄灯。 */
    const val ribProminenceEquivocalCentimeters = 0.8
    const val ribProminencePositiveCentimeters = 1.2

    data class PostureScoringProfile(
        val tag: String,
        val minMonths: Int,
        val maxMonths: Int,
        val shoulderAttentionCentimeters: Double,
        val shoulderReferralCentimeters: Double,
        val pelvisAttentionCentimeters: Double,
        val pelvisReferralCentimeters: Double,
        val seatedMidlineAttentionCentimeters: Double,
        val seatedRoundingAttentionDegrees: Double,
        val forwardHeadAttentionDegrees: Double,
        val forwardHeadReferralDegrees: Double,
        val proxyAtrAttentionDegrees: Double,
        val proxyAtrReferralDegrees: Double,
        val ribProminenceEquivocalCentimeters: Double,
        val ribProminencePositiveCentimeters: Double,
        val gaitAttentionCentimeters: Double,
        val weightedShoulder: Double,
        val weightedPelvis: Double,
        val weightedSpinalMidline: Double,
        val weightedThoracicRounding: Double,
        val weightedForwardHead: Double,
        val weightedAdams: Double,
        val weightedGait: Double,
        val yellowScore: Double,
        val redScore: Double
    )

    private val scoringProfiles = listOf(
        PostureScoringProfile(
            tag = "6-8岁",
            minMonths = 72,
            maxMonths = 96,
            shoulderAttentionCentimeters = 1.05,
            shoulderReferralCentimeters = 1.7,
            pelvisAttentionCentimeters = 0.55,
            pelvisReferralCentimeters = 1.05,
            seatedMidlineAttentionCentimeters = 1.35,
            seatedRoundingAttentionDegrees = 25.0,
            forwardHeadAttentionDegrees = 12.5,
            forwardHeadReferralDegrees = 16.5,
            proxyAtrAttentionDegrees = 5.2,
            proxyAtrReferralDegrees = 7.2,
            ribProminenceEquivocalCentimeters = 0.85,
            ribProminencePositiveCentimeters = 1.25,
            gaitAttentionCentimeters = 1.05,
            weightedShoulder = .20,
            weightedPelvis = .14,
            weightedSpinalMidline = .11,
            weightedThoracicRounding = .11,
            weightedForwardHead = .13,
            weightedAdams = .17,
            weightedGait = .24,
            yellowScore = 42.0,
            redScore = 63.0
        ),
        PostureScoringProfile(
            tag = "9-11岁",
            minMonths = 97,
            maxMonths = 132,
            shoulderAttentionCentimeters = 1.0,
            shoulderReferralCentimeters = 1.6,
            pelvisAttentionCentimeters = 0.5,
            pelvisReferralCentimeters = 1.0,
            seatedMidlineAttentionCentimeters = 1.3,
            seatedRoundingAttentionDegrees = 24.0,
            forwardHeadAttentionDegrees = 12.0,
            forwardHeadReferralDegrees = 16.0,
            proxyAtrAttentionDegrees = 5.0,
            proxyAtrReferralDegrees = 7.0,
            ribProminenceEquivocalCentimeters = 0.8,
            ribProminencePositiveCentimeters = 1.2,
            gaitAttentionCentimeters = 1.0,
            weightedShoulder = .20,
            weightedPelvis = .13,
            weightedSpinalMidline = .12,
            weightedThoracicRounding = .10,
            weightedForwardHead = .14,
            weightedAdams = .18,
            weightedGait = .23,
            yellowScore = 40.0,
            redScore = 61.0
        ),
        PostureScoringProfile(
            tag = "12-15岁",
            minMonths = 133,
            maxMonths = 180,
            shoulderAttentionCentimeters = 0.95,
            shoulderReferralCentimeters = 1.55,
            pelvisAttentionCentimeters = 0.5,
            pelvisReferralCentimeters = 0.98,
            seatedMidlineAttentionCentimeters = 1.25,
            seatedRoundingAttentionDegrees = 23.0,
            forwardHeadAttentionDegrees = 11.5,
            forwardHeadReferralDegrees = 15.5,
            proxyAtrAttentionDegrees = 4.8,
            proxyAtrReferralDegrees = 6.8,
            ribProminenceEquivocalCentimeters = 0.78,
            ribProminencePositiveCentimeters = 1.15,
            gaitAttentionCentimeters = 0.95,
            weightedShoulder = .18,
            weightedPelvis = .13,
            weightedSpinalMidline = .12,
            weightedThoracicRounding = .10,
            weightedForwardHead = .15,
            weightedAdams = .19,
            weightedGait = .23,
            yellowScore = 38.0,
            redScore = 59.0
        ),
        PostureScoringProfile(
            tag = "16-18岁",
            minMonths = 181,
            maxMonths = 216,
            shoulderAttentionCentimeters = 0.92,
            shoulderReferralCentimeters = 1.52,
            pelvisAttentionCentimeters = 0.48,
            pelvisReferralCentimeters = 0.95,
            seatedMidlineAttentionCentimeters = 1.2,
            seatedRoundingAttentionDegrees = 23.0,
            forwardHeadAttentionDegrees = 11.2,
            forwardHeadReferralDegrees = 15.0,
            proxyAtrAttentionDegrees = 4.7,
            proxyAtrReferralDegrees = 6.6,
            ribProminenceEquivocalCentimeters = 0.76,
            ribProminencePositiveCentimeters = 1.12,
            gaitAttentionCentimeters = 0.92,
            weightedShoulder = .17,
            weightedPelvis = .12,
            weightedSpinalMidline = .12,
            weightedThoracicRounding = .10,
            weightedForwardHead = .15,
            weightedAdams = .20,
            weightedGait = .24,
            yellowScore = 37.0,
            redScore = 57.0
        )
    )

        const val scoringWeightTotal = 1.10
    fun scoringProfileForAge(ageMonths: Int?): PostureScoringProfile = when {
        ageMonths == null -> scoringProfiles[1]
        ageMonths in scoringProfiles[0].minMonths..scoringProfiles[0].maxMonths -> scoringProfiles[0]
        ageMonths in scoringProfiles[1].minMonths..scoringProfiles[1].maxMonths -> scoringProfiles[1]
        ageMonths in scoringProfiles[2].minMonths..scoringProfiles[2].maxMonths -> scoringProfiles[2]
        ageMonths in scoringProfiles[3].minMonths..scoringProfiles[3].maxMonths -> scoringProfiles[3]
        ageMonths < scoringProfiles[0].minMonths -> scoringProfiles[0]
        else -> scoringProfiles.last()
    }
}

/** UY-IMCA V1.1 screening rules from the supplied 7.20 framework. */
data class PostureAssessmentReport(
    val generatedAt: String,
    val algorithm: String,
    val snapshots: Map<BodyCaptureTask, PostureMetricSnapshot>,
    val overallLevel: BodyAttentionLevel,
    val reasons: List<String>,
    val disclaimer: String,
    val riskScore: Int = 0,
    val qualityScore: Int = 0,
    val calibrationVersion: String = CALIBRATION_VERSION,
    val rulesSourceVersion: String = PostureScreeningRules.rulesSourceVersion
) {
    companion object {
        const val algorithmVersion = "UY-IMCA-CV-1.3"
        const val calibrationVersion = "UY-CAL-BASELINE-1.0"
        private const val CALIBRATION_VERSION = calibrationVersion
        private const val qualityFactorMin = .55
        private const val confidenceGainFactor = .45

        private fun clamp01(v: Double) = v.coerceIn(0.0, 1.0)
        private fun norm(value: Double, attention: Double, referral: Double): Double {
            return when {
                !value.isFinite() -> 0.0
                value <= attention -> 0.0
                value >= referral -> 1.0
                !attention.isFinite() || !referral.isFinite() || referral <= attention -> 0.0
                else -> clamp01((value - attention) / (referral - attention))
            }
        }

        private fun snapshotEvidence(snapshot: PostureMetricSnapshot?): Double {
            if (snapshot == null) return 0.0
            if (snapshot.sampleCount < PostureScreeningRules.minimumSamples || !snapshot.confidence.isFinite() || snapshot.confidence < PostureScreeningRules.minimumConfidence || snapshot.confidence > 1.0) return 0.0

            val min = PostureScreeningRules.minimumSamples.toDouble()
            val sampleFactor = ((snapshot.sampleCount - min) / min).coerceIn(0.0, 1.0)
            val confidenceFactor = ((snapshot.confidence - PostureScreeningRules.minimumConfidence) / .44).coerceIn(0.0, 1.0)
            return 0.55 * confidenceFactor + 0.45 * sampleFactor
        }

        private fun weightedEvidence(vararg values: Double): Double {
            if (values.isEmpty()) return 0.0
            val sum = values.sumOf { it }
            return if (sum <= 0.0) 0.0 else sum / values.size
        }

        fun make(snapshots: Map<BodyCaptureTask, PostureMetricSnapshot>, generatedAt: String, ageMonths: Int? = null): PostureAssessmentReport {
            val profile = PostureScreeningRules.scoringProfileForAge(ageMonths)
            val standing = snapshots[BodyCaptureTask.StandingBack]
            val forward = snapshots[BodyCaptureTask.ForwardBend]
            val seated = snapshots[BodyCaptureTask.Seated]
            val gait = snapshots[BodyCaptureTask.GaitVideo]
            fun valid(value: Double?, limit: Double): Boolean = value == null || (value.isFinite() && kotlin.math.abs(value) <= limit)
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
                    valid(snapshot.instrumentAtrDegrees, 180.0) &&
                    valid(snapshot.thoracicAtrDegrees, 180.0) &&
                    valid(snapshot.lumbarAtrDegrees, 180.0) &&
                    valid(snapshot.occiputWallDistanceCm, 50.0) &&
                    valid(snapshot.gaitShoulderSwingDifferenceCm, 20.0) &&
                    valid(snapshot.gaitPelvicSwingDifferenceCm, 20.0) &&
                    valid(snapshot.gaitTrunkSwayCm, 20.0)
            }
            fun hasMetricEvidence(snapshot: PostureMetricSnapshot?): Boolean {
                val value = snapshot ?: return false
                val numeric = when (value.task) {
                    BodyCaptureTask.StandingBack -> listOf(value.shoulderHeightDifferenceCm, value.pelvicHeightDifferenceCm, value.headTiltDegrees)
                    BodyCaptureTask.ForwardBend -> listOf(value.spinalMidlineDeviationCm, value.thoracicRoundingDegrees, value.forwardHeadAngleDegrees, value.cameraProxyAtrDegrees, value.cameraProxyRibProminenceCm, value.instrumentAtrDegrees, value.thoracicAtrDegrees, value.lumbarAtrDegrees)
                    BodyCaptureTask.Seated -> listOf(value.shoulderHeightDifferenceCm, value.spinalMidlineDeviationCm, value.thoracicRoundingDegrees, value.forwardHeadAngleDegrees, value.occiputWallDistanceCm)
                    BodyCaptureTask.GaitVideo -> listOf(value.gaitShoulderSwingDifferenceCm, value.gaitPelvicSwingDifferenceCm, value.gaitTrunkSwayCm)
                }
                return numeric.any { it?.isFinite() == true } || value.adamsResult != null
            }
            val metricsValid = listOf(standing, forward, seated, gait).all(::validMetrics)

            // Local/remote records are untrusted. Non-finite or negative
            // geometry is missing evidence, never a threshold bypass.
            fun magnitude(value: Double?): Double = value?.takeIf { it.isFinite() }?.let { kotlin.math.abs(it) } ?: 0.0
            val shoulder = maxOf(magnitude(standing?.shoulderHeightDifferenceCm), magnitude(seated?.shoulderHeightDifferenceCm))
            val pelvis = magnitude(standing?.pelvicHeightDifferenceCm)
            val trunk = magnitude(seated?.spinalMidlineDeviationCm)
            val round = magnitude(seated?.thoracicRoundingDegrees)
            val seatedForwardHead = magnitude(seated?.forwardHeadAngleDegrees)
            val headTilt = magnitude(standing?.headTiltDegrees)
            val headTiltYellow = headTilt > PostureScreeningRules.headTiltAttentionDegrees
            // Numeric rib-prominence proxies use the age-specific profile so
            // local preview and server scoring share the same boundary.
            val adams = forward?.cameraProxyRibProminenceCm
                ?.takeIf { it.isFinite() }
                ?.let { prominence ->
                    when {
                        kotlin.math.abs(prominence) >= profile.ribProminencePositiveCentimeters -> AdamsScreeningResult.Positive
                        kotlin.math.abs(prominence) >= profile.ribProminenceEquivocalCentimeters -> AdamsScreeningResult.Equivocal
                        else -> AdamsScreeningResult.Negative
                    }
                }
                ?: forward?.adamsResult
            val instrumentATR = listOf(forward?.instrumentAtrDegrees, forward?.thoracicAtrDegrees, forward?.lumbarAtrDegrees)
                .mapNotNull { it?.takeIf { value -> value.isFinite() }?.coerceAtLeast(0.0) }
                .maxOrNull() ?: 0.0
            val atrRed = instrumentATR >= profile.proxyAtrReferralDegrees
            val atrYellow = instrumentATR >= profile.proxyAtrAttentionDegrees
            val occiputWallAbnormal = seated?.occiputWallDistanceCm?.takeIf { it.isFinite() }?.coerceAtLeast(0.0)?.let { it > 2.0 } ?: false
            val adamsValue = when (adams) {
                AdamsScreeningResult.Positive -> 1.0
                AdamsScreeningResult.Equivocal -> 0.48
                else -> 0.0
            }
            val gaitValue = maxOf(magnitude(gait?.gaitShoulderSwingDifferenceCm), magnitude(gait?.gaitPelvicSwingDifferenceCm), magnitude(gait?.gaitTrunkSwayCm))

            val shoulderRed = shoulder > profile.shoulderReferralCentimeters
            val shoulderYellow = shoulder > profile.shoulderAttentionCentimeters
            val pelvisRed = pelvis > profile.pelvisReferralCentimeters
            val pelvisYellow = pelvis > profile.pelvisAttentionCentimeters
            val seatedForwardHeadRed = seatedForwardHead >= profile.forwardHeadReferralDegrees
            val seatedAbnormal = trunk > profile.seatedMidlineAttentionCentimeters || round >= profile.seatedRoundingAttentionDegrees || seatedForwardHeadRed
            val seatedAbnormalYellow = trunk > profile.seatedMidlineAttentionCentimeters || round >= profile.seatedRoundingAttentionDegrees || seatedForwardHead >= profile.forwardHeadAttentionDegrees
            val gaitAbnormal = gaitValue >= profile.gaitAttentionCentimeters

            val complete = BodyCaptureTask.values().all { task ->
                val snapshot = snapshots[task]
                snapshot?.let { hasMetricEvidence(it) && it.sampleCount >= PostureScreeningRules.minimumSamples && it.confidence.isFinite() && it.confidence >= PostureScreeningRules.minimumConfidence && it.confidence <= 1.0 } == true
            }

            val quality = weightedEvidence(
                snapshotEvidence(standing),
                snapshotEvidence(forward),
                snapshotEvidence(seated),
                snapshotEvidence(gait)
            )
            val weightedScoreRaw = (
                norm(shoulder, profile.shoulderAttentionCentimeters, profile.shoulderReferralCentimeters) * profile.weightedShoulder +
                    norm(pelvis, profile.pelvisAttentionCentimeters, profile.pelvisReferralCentimeters) * profile.weightedPelvis +
                    norm(trunk, profile.seatedMidlineAttentionCentimeters, profile.seatedMidlineAttentionCentimeters + 1.2) * profile.weightedSpinalMidline +
                    norm(round, profile.seatedRoundingAttentionDegrees, profile.seatedRoundingAttentionDegrees + 14.0) * profile.weightedThoracicRounding +
                    norm(seatedForwardHead, profile.forwardHeadAttentionDegrees, profile.forwardHeadReferralDegrees) * profile.weightedForwardHead +
                    adamsValue * profile.weightedAdams +
                    norm(gaitValue, profile.gaitAttentionCentimeters, profile.gaitAttentionCentimeters + 1.1) * profile.weightedGait
                ) / PostureScreeningRules.scoringWeightTotal
            val evidenceAdjustedScore = weightedScoreRaw * (qualityFactorMin + confidenceGainFactor * clamp01(quality))

            // A single shoulder/pelvis/head proxy is a yellow follow-up signal,
            // not a scoliosis referral by itself. The supplied screening
            // framework reserves red for ATR/Adams evidence combined with a
            // second dynamic or seated asymmetry. ATR/Adams remains optional
            // for validated depth/instrument adapters; the on-device 2D RGB
            // flow intentionally leaves those fields unavailable.
            val hardRed = adams == AdamsScreeningResult.Positive && (gaitAbnormal || seatedAbnormal)
            val hardYellow = shoulderRed || pelvisRed || adams == AdamsScreeningResult.Positive || gaitAbnormal || seatedAbnormal || headTiltYellow
            val level = when {
                !complete || !metricsValid -> BodyAttentionLevel.Pending
                atrRed || hardRed || evidenceAdjustedScore >= profile.redScore / 100.0 -> BodyAttentionLevel.Red
                atrYellow || occiputWallAbnormal || hardYellow || evidenceAdjustedScore >= profile.yellowScore / 100.0 || shoulderYellow || pelvisYellow || adams == AdamsScreeningResult.Equivocal || seatedAbnormalYellow -> BodyAttentionLevel.Yellow
                else -> BodyAttentionLevel.Green
            }

            val reasons = buildList {
                var hasMetricReason = false
                fun addMetric(message: String) {
                    add(message)
                    hasMetricReason = true
                }

                standing?.shoulderHeightDifferenceCm?.takeIf { it.isFinite() }?.let { addMetric("站姿双肩高度差 %.1f cm".format(kotlin.math.abs(it))) }
                standing?.pelvicHeightDifferenceCm?.takeIf { it.isFinite() }?.let { addMetric("站姿骨盆高度差 %.1f cm".format(kotlin.math.abs(it))) }
                forward?.cameraProxyAtrDegrees?.takeIf { it.isFinite() }?.let { addMetric("前屈姿态代偿角 %.1f°（用于观察提示）".format(kotlin.math.abs(it))) }
                listOf(forward?.instrumentAtrDegrees, forward?.thoracicAtrDegrees, forward?.lumbarAtrDegrees).mapNotNull { it?.takeIf { value -> value.isFinite() && value >= 0 } }.maxOrNull()?.let { addMetric("校准设备/深度 ATR 最大值 %.1f°（设备筛查证据）".format(it)) }
                standing?.headTiltDegrees?.takeIf { it.isFinite() }?.let { addMetric("头部侧倾角 %.1f°".format(kotlin.math.abs(it))) }
                if (!metricsValid) add("检测到异常测量值，请重新拍摄并保持设备稳定。")
                adams?.let { addMetric("前屈背部不对称：${it.label}") }
                seated?.spinalMidlineDeviationCm?.takeIf { it.isFinite() }?.let { addMetric("坐姿躯干中线偏移 %.1f cm".format(kotlin.math.abs(it))) }
                seated?.thoracicRoundingDegrees?.takeIf { it.isFinite() }?.let { addMetric("坐姿胸椎圆背观察角度 %.1f°".format(kotlin.math.abs(it))) }
                seated?.forwardHeadAngleDegrees?.takeIf { it.isFinite() }?.let { addMetric("坐姿头前伸观察角度 %.1f°".format(kotlin.math.abs(it))) }
                gait?.gaitTrunkSwayCm?.takeIf { it.isFinite() }?.let { addMetric("步态躯干侧向摆动 %.1f cm".format(kotlin.math.abs(it))) }
                seated?.occiputWallDistanceCm?.takeIf { it.isFinite() && it >= 0 }?.let { addMetric("枕墙距 %.1f cm".format(it)) }

                if (hasMetricReason) {
                    add("姿态综合关注度 %.0f分（记录稳定度 %.0f%%）".format(evidenceAdjustedScore * 100, quality * 100))
                }

                    if (isEmpty()) {
                    if (complete) {
                        add("记录不足，暂未形成完整指标。")
                    } else {
                        add("记录不足，请完成 4 项拍摄记录，并保持每项画面稳定、全身入镜。")
                    }
                }
            }

            return PostureAssessmentReport(
                generatedAt,
                algorithmVersion,
                snapshots,
                level,
                reasons,
                "本报告用于家庭健康观察与风险提示。二维相机不输出肋峰/ATR或Cobb角度，结果不替代脊柱侧弯筛查、体检或影像检查。出现持续疼痛或异常体征请及时就医。",
                riskScore = (evidenceAdjustedScore * 100).toInt(),
                qualityScore = (quality * 100).toInt()
            )
        }

    }
}

object PostureMetricCalculator {
    /** Remove global camera roll before comparing left/right heights. */
    fun rollCorrectedX(x: Double, y: Double, axisDx: Double, axisDy: Double): Double {
        val angle = rollAngle(axisDx, axisDy)
        return x * kotlin.math.cos(angle) + y * kotlin.math.sin(angle)
    }
    fun rollCorrectedY(x: Double, y: Double, axisDx: Double, axisDy: Double): Double {
        val angle = rollAngle(axisDx, axisDy)
        return -x * kotlin.math.sin(angle) + y * kotlin.math.cos(angle)
    }
    private fun rollAngle(axisDx: Double, axisDy: Double): Double =
        if (axisDx.isFinite() && axisDy.isFinite() && kotlin.math.hypot(axisDx, axisDy) > 0.0001) kotlin.math.atan2(axisDy, axisDx) else 0.0
    fun rollCorrectedVerticalDifference(firstX: Double, firstY: Double, secondX: Double, secondY: Double, axisDx: Double, axisDy: Double): Double =
        kotlin.math.abs(rollCorrectedY(firstX, firstY, axisDx, axisDy) - rollCorrectedY(secondX, secondY, axisDx, axisDy))

    fun centimeters(normalizedDifference: Double, bodyHeightNormalized: Double, measuredHeightCm: Double): Double? = if (normalizedDifference.isFinite() && bodyHeightNormalized.isFinite() && measuredHeightCm.isFinite() && bodyHeightNormalized > .05 && measuredHeightCm > 0) (normalizedDifference / bodyHeightNormalized * measuredHeightCm).coerceAtLeast(0.0) else null
    fun degrees(radians: Double): Double? = radians.takeIf { it.isFinite() }?.let { kotlin.math.abs(it * 180.0 / Math.PI) }
    /** Use motion range rather than maximum baseline offset for gait sway. */
    fun range(values: List<Double>): Double? {
        val finite = values.filter { it.isFinite() }
        val minimum = finite.minOrNull() ?: return null
        val maximum = finite.maxOrNull() ?: return null
        return (maximum - minimum).coerceAtLeast(0.0)
    }
}
enum class BodyCaptureTask(val title: String, val guide: String, val apiCode: String) {
    StandingBack("自然站姿", "背对镜头自然站立，双脚与肩同宽", "standingBack"),
    ForwardBend("前屈观察", "建议从侧后方拍摄；成人陪同下缓慢前屈，不适立即停止", "forwardBend"),
    Seated("坐姿观察", "坐在无靠背椅上，双手自然放在膝盖", "seatedPosture"),
    GaitVideo("步态视频", "沿直线自然行走 3–5 秒，从后方拍摄", "gaitVideo")
}
/** Capture usability rules only. They never create a medical conclusion. */
object BodyCaptureQualityGate {
    const val canonicalAssetVersion = "android-v1-search-calibrated-2026-09-15"
    data class PostureCaptureProfile(
        val tag: String,
        val staticHoldMilliseconds: Long,
        val staticMinimumFrames: Int,
        val staticMaximumDisplacementRatio: Double,
        val staticDisplacementJitterRatio: Double,
        val gaitMinimumMilliseconds: Long,
        val gaitMinimumDisplacementRatio: Double,
        val stabilityWindowFrames: Int,
        val gaitMovementWindowFrames: Int,
        val minimumRawSamplesForCompletion: Int,
        val fullBodyMinimumFrameCoverageRatio: Double,
        val seatedMinimumFrameCoverageRatio: Double,
        val minimumIndividualLandmarkConfidence: Float,
        val minimumMeanLandmarkConfidence: Float,
        val forwardBendMinimumTorsoTiltRatio: Double
    )

    data class AgeLimitedProfile(
        val minMonths: Int,
        val maxMonths: Int,
        val profile: PostureCaptureProfile
    )

    private data class ProfileOverrideToken(
        val minMonths: Int,
        val maxMonths: Int,
        val profile: PostureCaptureProfile
    )

    private val builtInProfiles = listOf(
        AgeLimitedProfile(
            72,
            96,
            PostureCaptureProfile(
                tag = "6-8岁",
                staticHoldMilliseconds = 1800L,
                staticMinimumFrames = 12,
                staticMaximumDisplacementRatio = .032,
                staticDisplacementJitterRatio = .0088,
                gaitMinimumMilliseconds = 2550L,
                gaitMinimumDisplacementRatio = .0365,
                stabilityWindowFrames = 11,
                gaitMovementWindowFrames = 7,
                minimumRawSamplesForCompletion = 6,
                fullBodyMinimumFrameCoverageRatio = .38,
                seatedMinimumFrameCoverageRatio = .145,
                minimumIndividualLandmarkConfidence = .47f,
                minimumMeanLandmarkConfidence = .515f,
                forwardBendMinimumTorsoTiltRatio = .34
            )
        ),
        AgeLimitedProfile(
            97,
            132,
            PostureCaptureProfile(
                tag = "9-11岁",
                staticHoldMilliseconds = 1700L,
                staticMinimumFrames = 13,
                staticMaximumDisplacementRatio = .031,
                staticDisplacementJitterRatio = .0078,
                gaitMinimumMilliseconds = 2500L,
                gaitMinimumDisplacementRatio = .0355,
                stabilityWindowFrames = 10,
                gaitMovementWindowFrames = 7,
                minimumRawSamplesForCompletion = 6,
                fullBodyMinimumFrameCoverageRatio = .40,
                seatedMinimumFrameCoverageRatio = .155,
                minimumIndividualLandmarkConfidence = .50f,
                minimumMeanLandmarkConfidence = .54f,
                forwardBendMinimumTorsoTiltRatio = .35
            )
        ),
        AgeLimitedProfile(
            133,
            180,
            PostureCaptureProfile(
                tag = "12-15岁",
                staticHoldMilliseconds = 1650L,
                staticMinimumFrames = 14,
                staticMaximumDisplacementRatio = .03,
                staticDisplacementJitterRatio = .0072,
                gaitMinimumMilliseconds = 2450L,
                gaitMinimumDisplacementRatio = .0368,
                stabilityWindowFrames = 10,
                gaitMovementWindowFrames = 6,
                minimumRawSamplesForCompletion = 6,
                fullBodyMinimumFrameCoverageRatio = .42,
                seatedMinimumFrameCoverageRatio = .16,
                minimumIndividualLandmarkConfidence = .52f,
                minimumMeanLandmarkConfidence = .56f,
                forwardBendMinimumTorsoTiltRatio = .35
            )
        ),
        AgeLimitedProfile(
            181,
            216,
            PostureCaptureProfile(
                tag = "16-18岁",
                staticHoldMilliseconds = 1600L,
                staticMinimumFrames = 14,
                staticMaximumDisplacementRatio = .029,
                staticDisplacementJitterRatio = .0068,
                gaitMinimumMilliseconds = 2400L,
                gaitMinimumDisplacementRatio = .038,
                stabilityWindowFrames = 10,
                gaitMovementWindowFrames = 6,
                minimumRawSamplesForCompletion = 6,
                fullBodyMinimumFrameCoverageRatio = .43,
                seatedMinimumFrameCoverageRatio = .16,
                minimumIndividualLandmarkConfidence = .53f,
                minimumMeanLandmarkConfidence = .57f,
                forwardBendMinimumTorsoTiltRatio = .35
            )
        )
    )

    private val legacy6To8Profile = builtInProfiles[0].profile
    private val legacy9To11Profile = builtInProfiles[1].profile
    private val legacy12To15Profile = builtInProfiles[2].profile
    private val legacy16PlusProfile = builtInProfiles[3].profile

    private val profileLock = Any()
    private var overrides: List<ProfileOverrideToken> = emptyList()

    /** Load sampling-informed values without a build/release cycle. */
    fun setProfileOverridesFromJson(raw: String): Boolean = runCatching {
        val root = JSONObject(raw)
        val assetVersion = root.optString("version").orEmpty()
        if (assetVersion.isNotBlank() && assetVersion != canonicalAssetVersion) {
            throw IllegalArgumentException("unsupported posture capture asset version")
        }
        val nodes = root.optJSONArray("ageProfiles") ?: throw IllegalArgumentException("missing ageProfiles")
        val parsed = mutableListOf<ProfileOverrideToken>()

        for (i in 0 until nodes.length()) {
            val profile = nodes.getJSONObject(i)
            val minMonths = profile.optInt("minAgeMonths", Int.MIN_VALUE)
            val maxMonths = profile.optInt("maxAgeMonths", Int.MAX_VALUE)
            val captureProfile = PostureCaptureProfile(
                tag = profile.optString("tag", "${'$'}{minMonths}-${'$'}{maxMonths}月"),
                staticHoldMilliseconds = profile.optLong("staticHoldMilliseconds", builtInProfiles[2].profile.staticHoldMilliseconds),
                staticMinimumFrames = profile.optInt("staticMinimumFrames", builtInProfiles[2].profile.staticMinimumFrames),
                staticMaximumDisplacementRatio = profile.optDouble("staticMaximumDisplacementRatio", builtInProfiles[2].profile.staticMaximumDisplacementRatio),
                staticDisplacementJitterRatio = profile.optDouble("staticDisplacementJitterRatio", builtInProfiles[2].profile.staticDisplacementJitterRatio),
                gaitMinimumMilliseconds = profile.optLong("gaitMinimumMilliseconds", builtInProfiles[2].profile.gaitMinimumMilliseconds),
                gaitMinimumDisplacementRatio = profile.optDouble("gaitMinimumDisplacementRatio", builtInProfiles[2].profile.gaitMinimumDisplacementRatio),
                stabilityWindowFrames = profile.optInt("stabilityWindowFrames", builtInProfiles[2].profile.stabilityWindowFrames),
                gaitMovementWindowFrames = profile.optInt("gaitMovementWindowFrames", builtInProfiles[2].profile.gaitMovementWindowFrames),
                minimumRawSamplesForCompletion = profile.optInt("minimumRawSamplesForCompletion", builtInProfiles[2].profile.minimumRawSamplesForCompletion),
                fullBodyMinimumFrameCoverageRatio = profile.optDouble("fullBodyMinimumFrameCoverageRatio", builtInProfiles[2].profile.fullBodyMinimumFrameCoverageRatio),
                seatedMinimumFrameCoverageRatio = profile.optDouble("seatedMinimumFrameCoverageRatio", builtInProfiles[2].profile.seatedMinimumFrameCoverageRatio),
                minimumIndividualLandmarkConfidence = profile.optDouble("minimumIndividualLandmarkConfidence", builtInProfiles[2].profile.minimumIndividualLandmarkConfidence.toDouble()).toFloat(),
                minimumMeanLandmarkConfidence = profile.optDouble("minimumMeanLandmarkConfidence", builtInProfiles[2].profile.minimumMeanLandmarkConfidence.toDouble()).toFloat(),
                forwardBendMinimumTorsoTiltRatio = profile.optDouble("forwardBendMinimumTorsoTiltRatio", builtInProfiles[2].profile.forwardBendMinimumTorsoTiltRatio)
            )

            if (minMonths == Int.MIN_VALUE || maxMonths == Int.MAX_VALUE || minMonths < 0 || maxMonths < minMonths || maxMonths > 240 || !captureProfile.isValid()) {
                throw IllegalArgumentException("invalid age profile")
            }
            parsed += ProfileOverrideToken(minMonths, maxMonths, captureProfile)
        }

        if (parsed.isEmpty()) throw IllegalArgumentException("invalid ageProfiles")
        if (assetVersion.isNotBlank()) {
            val expectedBands = listOf(72 to 96, 97 to 132, 133 to 180, 181 to 216)
            val actualBands = parsed.map { it.minMonths to it.maxMonths }
            if (actualBands != expectedBands) throw IllegalArgumentException("incomplete posture capture canonical asset")
        }
        parsed.sortWith(compareBy({ it.minMonths }, { it.maxMonths }))
        synchronized(profileLock) { overrides = parsed }
        true
    }.getOrNull() == true

    private fun PostureCaptureProfile.isValid(): Boolean {
        fun ratio(value: Double, upper: Double = 1.0) = value.isFinite() && value in 0.0..upper
        fun positive(value: Long) = value in 100L..30_000L
        return positive(staticHoldMilliseconds) && staticMinimumFrames in 3..240 &&
            ratio(staticMaximumDisplacementRatio) && ratio(staticDisplacementJitterRatio) &&
            positive(gaitMinimumMilliseconds) && ratio(gaitMinimumDisplacementRatio) &&
            stabilityWindowFrames in 3..240 && gaitMovementWindowFrames in 2..120 &&
            minimumRawSamplesForCompletion in 1..10_000 && ratio(fullBodyMinimumFrameCoverageRatio) &&
            ratio(seatedMinimumFrameCoverageRatio) && minimumIndividualLandmarkConfidence.isFinite() && minimumIndividualLandmarkConfidence in 0f..1f &&
            minimumMeanLandmarkConfidence.isFinite() && minimumMeanLandmarkConfidence in 0f..1f &&
            ratio(forwardBendMinimumTorsoTiltRatio)
    }

    /** Reset to the built-in age profiles. */
    fun clearProfileOverrides() = synchronized(profileLock) { overrides = emptyList() }

    private fun fallbackProfile(ageMonths: Int): PostureCaptureProfile {
        val source = builtInProfiles
        return source.firstOrNull { ageMonths in it.minMonths..it.maxMonths }?.profile
            ?: source.last { ageMonths >= it.minMonths }.profile
    }

    private fun overrideProfile(ageMonths: Int): PostureCaptureProfile {
        val currentOverrides = synchronized(profileLock) { overrides }
        val matched = currentOverrides.firstOrNull { ageMonths in it.minMonths..it.maxMonths }
        if (matched != null) return matched.profile
        return fallbackProfile(ageMonths)
    }

    // Backward-compatible legacy constants used by UI labels and existing tests.
    const val staticHoldMilliseconds = 1600L
    const val staticMinimumFrames = 14
    /** 单次单帧位移上限（相对身高归一化后）。 */
    const val staticMaximumDisplacementRatio = .029
    /** 动作完成抖动门限：当短窗内抖动上升超过该值则重置。 */
    const val staticDisplacementJitterRatio = .0072
    const val gaitMinimumMilliseconds = 2450L
    /** 步态必须有持续位移，不是一次抖动。 */
    const val gaitMinimumDisplacementRatio = .0368
    /** 过滤单次抖动的滑窗长度。 */
    const val stabilityWindowFrames = 10
    /** 步态需要连续几帧维持移动迹象。 */
    const val gaitMovementWindowFrames = 6
    /** 快速拒绝噪声前最少可用原始样本。 */
    const val minimumRawSamplesForCompletion = 6
    /** Pose confidence alone is insufficient when the child is too far away. */
    const val fullBodyMinimumFrameCoverageRatio = .42
    const val seatedMinimumFrameCoverageRatio = .16
    /** Requires every key joint to be reliable, not merely one detected frame.
     * This is a framing-quality gate and must not be interpreted as a body or
     * medical score. */
    const val minimumIndividualLandmarkConfidence = .50f
    const val minimumMeanLandmarkConfidence = .56f
    /** Visual completion only, never a flexibility/medical score. */
    const val forwardBendMinimumTorsoTiltRatio = .35

    fun profileForAge(ageMonths: Int?): PostureCaptureProfile = when {
        ageMonths == null -> fallbackProfile(108)
        ageMonths < builtInProfiles.first().minMonths -> fallbackProfile(builtInProfiles.first().minMonths)
        ageMonths > builtInProfiles.last().maxMonths -> fallbackProfile(builtInProfiles.last().maxMonths)
        builtInProfiles.any { ageMonths in it.minMonths..it.maxMonths } -> overrideProfile(ageMonths)
        else -> overrideProfile(ageMonths)
    }

    fun staticReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double, ageMonths: Int?): Boolean =
        staticReady(elapsedMs, stableFrames, displacementRatio, 0.0, ageMonths)

    fun staticReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double, displacementJitterRatio: Double, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return elapsedMs >= 0 && displacementRatio.isFinite() && displacementJitterRatio.isFinite() && displacementRatio >= 0 && displacementJitterRatio >= 0 && elapsedMs >= profile.staticHoldMilliseconds && stableFrames >= profile.staticMinimumFrames && displacementRatio < profile.staticMaximumDisplacementRatio && displacementJitterRatio <= profile.staticDisplacementJitterRatio
    }

    fun staticReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double): Boolean = staticReady(elapsedMs, stableFrames, displacementRatio, 0.0, null)

    fun staticReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double, displacementJitterRatio: Double): Boolean = staticReady(elapsedMs, stableFrames, displacementRatio, displacementJitterRatio, null)

    fun gaitReady(elapsedMs: Long, displacementRatio: Double, movementSamples: Int, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return elapsedMs >= 0 && displacementRatio.isFinite() && displacementRatio >= profile.gaitMinimumDisplacementRatio && elapsedMs >= profile.gaitMinimumMilliseconds && movementSamples >= profile.gaitMovementWindowFrames
    }

    fun gaitReady(elapsedMs: Long, displacementRatio: Double, movementSamples: Int): Boolean = gaitReady(elapsedMs, displacementRatio, movementSamples, null)

    fun gaitReady(elapsedMs: Long, displacementRatio: Double, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return gaitReady(elapsedMs, displacementRatio, profile.gaitMovementWindowFrames, ageMonths)
    }

    fun gaitReady(elapsedMs: Long, displacementRatio: Double): Boolean = gaitReady(elapsedMs, displacementRatio, null)

    fun forwardBendReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double, torsoTiltRatio: Double, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return staticReady(elapsedMs, stableFrames, displacementRatio, 0.0, ageMonths) && torsoTiltRatio.isFinite() && torsoTiltRatio in 0.0..10.0 && torsoTiltRatio >= profile.forwardBendMinimumTorsoTiltRatio
    }

    fun forwardBendReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double, torsoTiltRatio: Double): Boolean = forwardBendReady(elapsedMs, stableFrames, displacementRatio, torsoTiltRatio, null)

    fun hasUsableBodyScale(verticalCoverageRatio: Double, seated: Boolean, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return verticalCoverageRatio.isFinite() && verticalCoverageRatio in 0.0..1.0 && verticalCoverageRatio >= if (seated) profile.seatedMinimumFrameCoverageRatio else profile.fullBodyMinimumFrameCoverageRatio
    }

    fun hasUsableBodyScale(verticalCoverageRatio: Double, seated: Boolean): Boolean = hasUsableBodyScale(verticalCoverageRatio, seated, null)

    /** Camera image coordinates grow downward; shoulders must remain above hips. */
    fun hasUsableSeatedGeometry(shoulderCenterY: Double, hipCenterY: Double, verticalCoverageRatio: Double, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return shoulderCenterY.isFinite() && hipCenterY.isFinite() && verticalCoverageRatio.isFinite() && verticalCoverageRatio in 0.0..1.0 && shoulderCenterY < hipCenterY && verticalCoverageRatio >= profile.seatedMinimumFrameCoverageRatio
    }

    fun hasUsableSeatedGeometry(shoulderCenterY: Double, hipCenterY: Double, verticalCoverageRatio: Double): Boolean = hasUsableSeatedGeometry(shoulderCenterY, hipCenterY, verticalCoverageRatio, null)

    fun hasReliableLandmarks(confidences: List<Float>, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return confidences.isNotEmpty() && confidences.all { it.isFinite() && it in 0f..1f && it >= profile.minimumIndividualLandmarkConfidence } && confidences.average() >= profile.minimumMeanLandmarkConfidence.toDouble()
    }

    fun hasReliableLandmarks(confidences: List<Float>): Boolean = hasReliableLandmarks(confidences, null)

    fun staticProgress(elapsedMs: Long, ageMonths: Int?): Float {
        val profile = profileForAge(ageMonths)
        return (elapsedMs.toFloat() / profile.staticHoldMilliseconds).coerceIn(0f, .96f)
    }

    fun staticProgress(elapsedMs: Long): Float = staticProgress(elapsedMs, null)

    fun gaitProgress(elapsedMs: Long, hasMoved: Boolean, ageMonths: Int?): Float {
        val profile = profileForAge(ageMonths)
        return if (hasMoved) (.2f + elapsedMs.toFloat() / profile.gaitMinimumMilliseconds * .8f).coerceAtMost(.96f) else .12f
    }

    fun gaitProgress(elapsedMs: Long, hasMoved: Boolean): Float = gaitProgress(elapsedMs, hasMoved, null)
}

/** One normalization rule for ruler dragging, step buttons and text input. */
object BodyMeasurementInput {
    fun normalized(value: Double, range: ClosedFloatingPointRange<Double>, step: Double): Double {
        if (!range.start.isFinite() || !range.endInclusive.isFinite() || range.start > range.endInclusive || !step.isFinite() || step <= 0) return range.start
        if (!value.isFinite()) return range.start
        val clamped = value.coerceIn(range.start, range.endInclusive)
        return (kotlin.math.round(clamped / step) * step).coerceIn(range.start, range.endInclusive)
    }
}

/** Current-height classification from WS/T 612—2018. This is a growth
 * reference for ages 7–18, not an adult-height prediction or diagnosis. */
enum class HeightDevelopmentLevel(val label: String) { Low("下等"), Lower("中下等"), Middle("中等"), Upper("中上等"), High("上等") }
data class HeightDevelopmentAssessment(
    val ageYears: Int,
    val heightCentimeters: Double,
    val level: HeightDevelopmentLevel,
    val lowerTwoSD: Double,
    val lowerOneSD: Double,
    val median: Double,
    val upperOneSD: Double,
    val upperTwoSD: Double,
    val ruleVersion: String
)
private fun normalizedGenderIsBoy(raw: String): Boolean? = when (raw.trim().lowercase()) {
    "男", "男性", "boy", "male", "m", "1" -> true
    "女", "女性", "girl", "female", "f", "2" -> false
    else -> null
}

data class BodyAssessmentRecord(val heightCm: Double, val weightKg: Double, val measuredAt: String, val captures: Set<BodyCaptureTask>, val asymmetric: Boolean, val gaitConcern: Boolean, val nextFollowUp: String, val planDays: Set<String> = emptySet(), val visualObservationHint: String? = null, val fatherHeightCm: Double? = null, val motherHeightCm: Double? = null, val captureObservationHints: Map<String, String> = emptyMap(), val postureReport: PostureAssessmentReport? = null, val ageMonthsAtMeasurement: Int? = null) {
    companion object {
        const val ruleVersion = "WS/T 586—2018 年龄别 BMI 参考 v1.1"
        const val bmiAlgorithmVersion = "UY-IMCA-BMI-1.2"
        const val heightAlgorithmVersion = "UY-IMCA-HEIGHT-1.0"
        const val geneticHeightRangeHalfWidthCentimeters = 5.0
        // WS/T 586 child BMI tables end at the 18-year (216-month) row.
        // Ages beyond that must not silently fall back to adult cut-offs.
    val bmiSupportedAgeMonths = 72..216
    val heightSupportedAgeMonths = 84..227

    }
    val bmi: Double get() {
        if (!heightCm.isFinite() || !weightKg.isFinite() || heightCm !in 90.0..190.0 || weightKg !in 15.0..90.0) return 0.0
        val value = weightKg / ((heightCm / 100) * (heightCm / 100))
        return value.takeIf { it.isFinite() } ?: 0.0
    }
    /** WS/T 586—2018 compares the BMI rounded to one decimal place. */
    val bmiForScreening: Double get() = if (bmi <= 0) 0.0 else kotlin.math.floor(bmi * 10.0 + 0.5) / 10.0
    /** A task-labelled, non-diagnostic summary. Legacy unsorted text remains
     * readable for records saved before task-level hints were introduced. */
    val visualObservationSummary: String?
        get() = captureObservationHints.toSortedMap().mapNotNull { (task, hint) ->
            runCatching { "${BodyCaptureTask.valueOf(task).title}：$hint" }.getOrNull()
        }.joinToString("\n").ifBlank { visualObservationHint }
    /** Male: (father + mother + 13cm) / 2; female: (father + mother - 13cm) / 2. */
    fun geneticHeightReference(gender: String): Double? {
        val father = fatherHeightCm ?: return null
        val mother = motherHeightCm ?: return null
        val isBoy = normalizedGenderIsBoy(gender) ?: return null
        if (!father.isFinite() || !mother.isFinite() || father !in 120.0..230.0 || mother !in 120.0..230.0) return null
        return (father + mother + if (isBoy) 13.0 else -13.0) / 2
    }
    /** Mid-parental target height with a transparent ±5 cm family range. */
    fun geneticHeightRange(gender: String): ClosedFloatingPointRange<Double>? = geneticHeightReference(gender)?.let { (it - geneticHeightRangeHalfWidthCentimeters)..(it + geneticHeightRangeHalfWidthCentimeters) }
    fun geneticHeightFormula(gender: String): String = when {
        normalizedGenderIsBoy(gender) == true -> "（父亲身高 + 母亲身高 + 13 cm）÷ 2"
        normalizedGenderIsBoy(gender) == false -> "（父亲身高 + 母亲身高 − 13 cm）÷ 2"
        else -> "待完善孩子性别后计算"
    }
    /** Classifies current height against the national 7–18 year age/sex reference. */
    fun heightDevelopmentAssessment(ageMonths: Int?, gender: String): HeightDevelopmentAssessment? {
        val isBoy = normalizedGenderIsBoy(gender) ?: return null
        val effectiveAgeMonths = ageMonthsAtMeasurement ?: ageMonths
        if (!heightCm.isFinite() || heightCm !in 90.0..190.0 || effectiveAgeMonths == null || effectiveAgeMonths !in heightSupportedAgeMonths) return null
        val ageYears = (effectiveAgeMonths / 12).coerceIn(7, 18)
        val row = HeightReference.row(ageYears, isBoy)
        val level = when {
            heightCm < row.minusTwoSD -> HeightDevelopmentLevel.Low
            heightCm < row.minusOneSD -> HeightDevelopmentLevel.Lower
            heightCm <= row.plusOneSD -> HeightDevelopmentLevel.Middle
            heightCm <= row.plusTwoSD -> HeightDevelopmentLevel.Upper
            else -> HeightDevelopmentLevel.High
        }
        return HeightDevelopmentAssessment(ageYears, heightCm, level, row.minusTwoSD, row.minusOneSD, row.median, row.plusOneSD, row.plusTwoSD, "WS/T 612—2018")
    }
    fun bmiLevel(ageMonths: Int?, gender: String): BodyAttentionLevel {
        val effectiveAgeMonths = ageMonthsAtMeasurement ?: ageMonths
        if (bmiForScreening <= 0 || effectiveAgeMonths == null || effectiveAgeMonths !in bmiSupportedAgeMonths || normalizedGenderIsBoy(gender) == null) return BodyAttentionLevel.Unavailable
        val row = bmiReferenceRow(effectiveAgeMonths, gender)
            ?: return BodyAttentionLevel.Unavailable
        return if (bmiForScreening >= row.obesity) BodyAttentionLevel.Red else if (bmiForScreening >= row.overweight) BodyAttentionLevel.Yellow else BodyAttentionLevel.Green
    }

    private fun bmiReferenceRow(ageMonths: Int, gender: String): BmiRow? {
        val rows = if (normalizedGenderIsBoy(gender) == true) BmiReference.boys else BmiReference.girls
        if (rows.isEmpty() || ageMonths < rows.first().month || ageMonths > rows.last().month) return null

        // Use the completed lower half-year row from WS/T 586—2018. The
        // standard does not define synthetic monthly thresholds.
        val bucket = (ageMonths / 6) * 6
        return rows.firstOrNull { it.month == bucket }
    }
    fun bmiScreeningLabel(ageMonths: Int?, gender: String): String {
        if (bmi <= 0) return "待填写身高体重"
        val effectiveAgeMonths = ageMonthsAtMeasurement ?: ageMonths
        if (effectiveAgeMonths == null) return "待完善出生日期"
        if (normalizedGenderIsBoy(gender) == null) return "待完善性别"
        if (effectiveAgeMonths !in bmiSupportedAgeMonths) return "适用年龄为 6–18 岁"
        return when (bmiLevel(effectiveAgeMonths, gender)) {
        BodyAttentionLevel.Green -> "未达到超重筛查界值"
        BodyAttentionLevel.Yellow -> "超重筛查关注"
        BodyAttentionLevel.Red -> "肥胖筛查关注"
        BodyAttentionLevel.Unavailable -> "待完善生日"
        BodyAttentionLevel.Pending -> "待完成拍摄记录"
        }
    }
    fun postureLevel(): BodyAttentionLevel = when {
        asymmetric && gaitConcern -> BodyAttentionLevel.Red
        asymmetric || gaitConcern -> BodyAttentionLevel.Yellow
        captures.size < BodyCaptureTask.values().size -> BodyAttentionLevel.Pending
        else -> BodyAttentionLevel.Green
    }

    fun level(ageMonths: Int?, gender: String): BodyAttentionLevel {
        val bmi = bmiLevel(ageMonths, gender)
        // Parent checkboxes are safety context. A generated camera report is
        // the source of posture risk and cannot be overwritten by a checkbox.
        val posture = postureReport?.overallLevel ?: postureLevel()
        return when {
            bmi == BodyAttentionLevel.Red || posture == BodyAttentionLevel.Red -> BodyAttentionLevel.Red
            bmi == BodyAttentionLevel.Yellow || posture == BodyAttentionLevel.Yellow -> BodyAttentionLevel.Yellow
            posture == BodyAttentionLevel.Pending -> BodyAttentionLevel.Pending
            posture == BodyAttentionLevel.Unavailable || bmi == BodyAttentionLevel.Unavailable -> BodyAttentionLevel.Unavailable
            else -> BodyAttentionLevel.Green
        }
    }
}
data class BodyAssessmentDraft(
    val stage: Int = 0,
    val guardianReady: Boolean = false,
    val consentAcknowledged: Boolean = false,
    val environmentReady: Boolean = false,
    val heightCm: Double = 0.0,
    val weightKg: Double = 0.0,
    val captures: Set<BodyCaptureTask> = emptySet(),
    val asymmetric: Boolean = false,
    val gaitConcern: Boolean = false,
    val visualObservationHint: String? = null,
    val fatherHeightCm: Double? = null,
    val motherHeightCm: Double? = null,
    val captureObservationHints: Map<String, String> = emptyMap(),
    val postureSnapshots: Map<BodyCaptureTask, PostureMetricSnapshot> = emptyMap()
)
private data class BmiRow(val month: Int, val overweight: Double, val obesity: Double)
private object BmiReference {
    val boys = listOf(72 to 16.4 to 17.7,78 to 16.7 to 18.1,84 to 17.0 to 18.7,90 to 17.4 to 19.2,96 to 17.8 to 19.7,102 to 18.1 to 20.3,108 to 18.5 to 20.8,114 to 18.9 to 21.4,120 to 19.2 to 21.9,126 to 19.6 to 22.5,132 to 19.9 to 23.0,138 to 20.3 to 23.6,144 to 20.7 to 24.1,150 to 21.0 to 24.7,156 to 21.4 to 25.2,162 to 21.9 to 25.7,168 to 22.3 to 26.1,174 to 22.6 to 26.4,180 to 22.9 to 26.6,186 to 23.1 to 26.9,192 to 23.3 to 27.1,198 to 23.5 to 27.4,204 to 23.7 to 27.6,210 to 23.8 to 27.8,216 to 24.0 to 28.0).map { BmiRow(it.first.first, it.first.second, it.second) }
    val girls = listOf(72 to 16.2 to 17.5,78 to 16.5 to 18.0,84 to 16.8 to 18.5,90 to 17.2 to 19.0,96 to 17.6 to 19.4,102 to 18.1 to 19.9,108 to 18.5 to 20.4,114 to 19.0 to 21.0,120 to 19.5 to 21.5,126 to 20.0 to 22.1,132 to 20.5 to 22.7,138 to 21.1 to 23.3,144 to 21.5 to 23.9,150 to 21.9 to 24.5,156 to 22.2 to 25.0,162 to 22.6 to 25.6,168 to 22.8 to 25.9,174 to 23.0 to 26.3,180 to 23.2 to 26.6,186 to 23.4 to 26.9,192 to 23.6 to 27.1,198 to 23.7 to 27.4,204 to 23.8 to 27.6,210 to 23.9 to 27.8,216 to 24.0 to 28.0).map { BmiRow(it.first.first, it.first.second, it.second) }
}
private object HeightReference {
    data class Row(val minusTwoSD: Double, val minusOneSD: Double, val median: Double, val plusOneSD: Double, val plusTwoSD: Double)
    val boys = mapOf(
        7 to Row(113.51,119.49,125.48,131.47,137.46), 8 to Row(118.35,124.53,130.72,136.90,143.08),
        9 to Row(122.74,129.27,135.81,142.35,148.88), 10 to Row(126.79,133.77,140.76,147.75,154.74),
        11 to Row(130.39,138.20,146.01,153.82,161.64), 12 to Row(134.48,143.33,152.18,161.03,169.89),
        13 to Row(143.01,151.60,160.19,168.78,177.38), 14 to Row(150.22,157.93,165.63,173.34,181.05),
        15 to Row(155.25,162.14,169.02,175.91,182.79), 16 to Row(157.72,164.15,170.58,177.01,183.44),
        17 to Row(158.76,165.07,171.39,177.70,184.01), 18 to Row(158.81,165.12,171.42,177.73,184.03)
    )
    val girls = mapOf(
        7 to Row(112.29,118.21,124.13,130.05,135.97), 8 to Row(116.83,123.09,129.34,135.59,141.84),
        9 to Row(121.31,128.11,134.91,141.71,148.51), 10 to Row(126.38,133.78,141.18,148.57,155.97),
        11 to Row(132.09,139.72,147.36,154.99,162.63), 12 to Row(138.11,145.26,152.41,159.56,166.71),
        13 to Row(143.75,149.91,156.07,162.23,168.39), 14 to Row(146.18,151.98,157.78,163.58,169.38),
        15 to Row(147.02,152.74,158.47,164.19,169.91), 16 to Row(147.59,153.26,158.93,164.60,170.27),
        17 to Row(147.82,153.50,159.18,164.86,170.54), 18 to Row(148.54,154.28,160.01,165.74,171.48)
    )
    private val safeBoyFallback = Row(158.81, 165.12, 171.42, 177.73, 184.03)
    private val safeGirlFallback = Row(148.54, 154.28, 160.01, 165.74, 171.48)
    fun row(ageYears: Int, isBoy: Boolean): Row {
        val table = if (isBoy) boys else girls
        val safeFallback = if (isBoy) safeBoyFallback else safeGirlFallback
        return table[ageYears] ?: table[18] ?: table.values.lastOrNull() ?: safeFallback
    }
}
fun ageMonthsFromBirthDate(rawBirthDate: String, nowInstant: Date = Date()): Int? = runCatching {
    // Birthday is a calendar date. Keep it on the same China business
    // calendar as the API and iOS, rather than the device timezone.
    val businessZone = TimeZone.getTimeZone("Asia/Shanghai")
    val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false; timeZone = businessZone }
    val raw = rawBirthDate.trim()
    if (!Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(raw)) return@runCatching null
    val parsed = formatter.parse(raw) ?: return@runCatching null
    if (formatter.format(parsed) != raw) return@runCatching null
    val born = java.util.Calendar.getInstance(businessZone).apply { time = parsed }
    val now = java.util.Calendar.getInstance(businessZone).apply { time = nowInstant }
    val months = (now.get(java.util.Calendar.YEAR) - born.get(java.util.Calendar.YEAR)) * 12 +
        now.get(java.util.Calendar.MONTH) - born.get(java.util.Calendar.MONTH) -
        if (now.get(java.util.Calendar.DAY_OF_MONTH) < born.get(java.util.Calendar.DAY_OF_MONTH)) 1 else 0
    months.takeIf { it in 0..240 }
}.getOrNull()

val Student.bodyAssessmentAgeMonths: Int?
    get() = birthDate?.let(::ageMonthsFromBirthDate)
val Student.bodyAssessmentAgeLabel: String get() = bodyAssessmentAgeMonths?.let { "${it / 12}岁${it % 12}个月" } ?: "待完善"
