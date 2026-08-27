package com.xiangshang.youth.core.model

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
