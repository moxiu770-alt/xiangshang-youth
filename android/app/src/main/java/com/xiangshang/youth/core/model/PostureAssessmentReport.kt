package com.xiangshang.youth.core.model

/** Candidate rules retained for offline validation; product output fails closed. */
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
    val rulesSourceVersion: String = PostureScreeningRules.rulesSourceVersion,
    val validationStatus: AlgorithmValidationStatus = AlgorithmReleaseGate.posture,
    val screeningDecision: BodyScreeningDecision? = null
) {
    val canPublishClassification: Boolean get() = validationStatus.allowsClassification

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

        fun make(
            snapshots: Map<BodyCaptureTask, PostureMetricSnapshot>,
            generatedAt: String,
            ageMonths: Int? = null,
            validationStatus: AlgorithmValidationStatus = AlgorithmReleaseGate.posture
        ): PostureAssessmentReport {
            val profile = PostureScreeningRules.scoringProfileForAge(ageMonths)
            val standingFront = snapshots[BodyCaptureTask.StandingFront]
            val standing = snapshots[BodyCaptureTask.StandingBack]
            val standingSide = snapshots[BodyCaptureTask.StandingSide]
            val forward = snapshots[BodyCaptureTask.ForwardBend]
            val dynamicKnee = snapshots[BodyCaptureTask.DynamicKneeControl]
            val seated = snapshots[BodyCaptureTask.Seated]
            val gait = snapshots[BodyCaptureTask.GaitVideo]
            val footArch = snapshots[BodyCaptureTask.FootArch]
            fun hasMetricEvidence(snapshot: PostureMetricSnapshot?): Boolean {
                val value = snapshot ?: return false
                val numeric = when (value.task) {
                    BodyCaptureTask.StandingFront -> listOf(value.shoulderHeightDifferenceCm, value.pelvicHeightDifferenceCm, value.headTiltDegrees, value.kneeAlignmentProxyRatio, value.lowerLimbAxisAsymmetryDegrees)
                    BodyCaptureTask.StandingBack -> listOf(value.shoulderHeightDifferenceCm, value.pelvicHeightDifferenceCm, value.headTiltDegrees)
                    BodyCaptureTask.StandingSide -> listOf(value.forwardHeadAngleDegrees, value.thoracicRoundingDegrees, value.shoulderProtractionProxyDegrees, value.pelvicTiltProxyDegrees)
                    BodyCaptureTask.ForwardBend -> listOf(value.spinalMidlineDeviationCm, value.thoracicRoundingDegrees, value.forwardHeadAngleDegrees, value.cameraProxyAtrDegrees, value.cameraProxyRibProminenceCm, value.instrumentAtrDegrees, value.thoracicAtrDegrees, value.lumbarAtrDegrees)
                    BodyCaptureTask.DynamicKneeControl -> listOf(value.leftKneeValgusProxyDegrees, value.rightKneeValgusProxyDegrees, value.kneeTrackingAsymmetryRatio, value.squatDepthRatio, value.movementRepetitionCount)
                    BodyCaptureTask.Seated -> listOf(value.shoulderHeightDifferenceCm, value.spinalMidlineDeviationCm, value.thoracicRoundingDegrees, value.forwardHeadAngleDegrees, value.occiputWallDistanceCm)
                    BodyCaptureTask.GaitVideo -> listOf(value.gaitShoulderSwingDifferenceCm, value.gaitPelvicSwingDifferenceCm, value.gaitTrunkSwayCm)
                    BodyCaptureTask.FootArch -> listOf(value.footArchVisibilityScore, value.leftArchProxyIndex, value.rightArchProxyIndex, value.heelAlignmentProxyDegrees)
                }
                return numeric.any { it?.isFinite() == true } || value.adamsResult != null || value.gaitObservedAbnormal != null || value.seatedThoracicKyphosisObserved != null
            }
            val metricsValid = snapshots.values.all(PostureEvidenceValidation::validMetrics)

            // Local/remote records are untrusted. Non-finite or negative
            // geometry is missing evidence, never a threshold bypass.
            fun magnitude(value: Double?): Double = value?.takeIf { it.isFinite() }?.let { kotlin.math.abs(it) } ?: 0.0
            val standingShoulder = magnitude(standing?.shoulderHeightDifferenceCm)
            val seatedShoulder = magnitude(seated?.shoulderHeightDifferenceCm)
            val shoulder = maxOf(magnitude(standingFront?.shoulderHeightDifferenceCm), standingShoulder, seatedShoulder)
            val pelvis = maxOf(magnitude(standingFront?.pelvicHeightDifferenceCm), magnitude(standing?.pelvicHeightDifferenceCm))
            val trunk = magnitude(seated?.spinalMidlineDeviationCm)
            val round = maxOf(magnitude(seated?.thoracicRoundingDegrees), magnitude(standingSide?.thoracicRoundingDegrees))
            val seatedForwardHead = maxOf(magnitude(seated?.forwardHeadAngleDegrees), magnitude(standingSide?.forwardHeadAngleDegrees))
            val headTilt = magnitude(standing?.headTiltDegrees)
            val headTiltYellow = headTilt > SpineScreeningStandard.headTiltNormalDegrees
            // Numeric rib-prominence proxies use the age-specific profile so
            // local preview and server scoring share the same boundary.
            val adams = forward?.adamsResult?.takeIf { forward.adamsObservedResult != null } ?: forward?.cameraProxyRibProminenceCm
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
            val seatedReviewAtr = forward?.seatedForwardBendAtrDegrees?.takeIf { it.isFinite() }?.coerceAtLeast(0.0)
            val atrDrop = seatedReviewAtr?.let { instrumentATR - it }
            val fixedAtrConcern = instrumentATR >= SpineScreeningStandard.atrAttentionDegrees && atrDrop?.let { it < 3.0 } == true
            val atrRed = instrumentATR >= SpineScreeningStandard.atrReferralDegrees || fixedAtrConcern
            val atrYellow = instrumentATR >= SpineScreeningStandard.atrAttentionDegrees && !atrRed
            val occiputWallAbnormal = seated?.occiputWallDistanceCm?.takeIf { it.isFinite() }?.coerceAtLeast(0.0)?.let { it > SpineScreeningStandard.occiputWallDistanceAbnormalCentimeters } ?: false
            val adamsValue = when (adams) {
                AdamsScreeningResult.Positive -> 1.0
                AdamsScreeningResult.Equivocal -> 0.48
                else -> 0.0
            }
            val gaitValue = maxOf(magnitude(gait?.gaitShoulderSwingDifferenceCm), magnitude(gait?.gaitPelvicSwingDifferenceCm), magnitude(gait?.gaitTrunkSwayCm))

            val shoulderRed = standingShoulder > SpineScreeningStandard.shoulderMarkedCentimeters
            val shoulderYellow = standingShoulder > SpineScreeningStandard.shoulderNormalCentimeters
            val pelvisRed = pelvis > SpineScreeningStandard.pelvisMarkedCentimeters
            val pelvisYellow = pelvis > SpineScreeningStandard.pelvisNormalCentimeters
            val seatedAbnormal = trunk > SpineScreeningStandard.seatedMidlineNormalCentimeters || seatedShoulder > SpineScreeningStandard.shoulderNormalCentimeters || seated?.seatedThoracicKyphosisObserved == true || occiputWallAbnormal
            val seatedAbnormalYellow = seatedAbnormal
            val gaitAbnormal = gait?.gaitObservedAbnormal == true || gaitValue >= SpineScreeningStandard.gaitShoulderDifferenceCentimeters

            val ageApplicable = SpineScreeningStandard.isApplicable(ageMonths)
            val complete = ageApplicable && BodyCaptureTask.values().all { task ->
                val snapshot = snapshots[task]
                snapshot?.let { hasMetricEvidence(it) && it.sampleCount >= PostureScreeningRules.minimumSamples && it.confidence.isFinite() && it.confidence >= PostureScreeningRules.minimumConfidence && it.confidence <= 1.0 } == true
            }

            val quality = weightedEvidence(
                snapshotEvidence(standingFront),
                snapshotEvidence(standing),
                snapshotEvidence(standingSide),
                snapshotEvidence(forward),
                snapshotEvidence(dynamicKnee),
                snapshotEvidence(gait),
                snapshotEvidence(seated),
                snapshotEvidence(footArch)
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
                atrRed || hardRed -> BodyAttentionLevel.Red
                atrYellow || occiputWallAbnormal || hardYellow || shoulderYellow || pelvisYellow || adams == AdamsScreeningResult.Equivocal || seatedAbnormalYellow -> BodyAttentionLevel.Yellow
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
                listOf(forward?.instrumentAtrDegrees, forward?.thoracicAtrDegrees, forward?.lumbarAtrDegrees).mapNotNull { it?.takeIf { value -> value.isFinite() && value >= 0 } }.maxOrNull()?.let { addMetric("Bunnell 脊柱侧弯计 ATR 最大值 %.1f°".format(it)) }
                if (seatedReviewAtr != null && atrDrop != null) addMetric("坐位前屈 ATR %.1f°，较站位变化 %.1f°（%s）".format(seatedReviewAtr, atrDrop, if (atrDrop >= 3.0) "功能性偏斜可能" else "结构异常复核提示"))
                standing?.headTiltDegrees?.takeIf { it.isFinite() }?.let { addMetric("头部侧倾角 %.1f°".format(kotlin.math.abs(it))) }
                if (!metricsValid) add("检测到异常测量值，请重新拍摄并保持设备稳定。")
                adams?.let { addMetric("前屈背部不对称：${it.label}") }
                forward?.adamsProminenceSide?.takeIf { it == "左" || it == "右" }?.let { addMetric("前屈隆起侧：${it}侧") }
                seated?.spinalMidlineDeviationCm?.takeIf { it.isFinite() }?.let { addMetric("坐姿躯干中线偏移 %.1f cm".format(kotlin.math.abs(it))) }
                seated?.thoracicRoundingDegrees?.takeIf { it.isFinite() }?.let { addMetric("坐姿胸椎圆背观察角度 %.1f°".format(kotlin.math.abs(it))) }
                seated?.forwardHeadAngleDegrees?.takeIf { it.isFinite() }?.let { addMetric("坐姿头前伸观察角度 %.1f°".format(kotlin.math.abs(it))) }
                gait?.gaitTrunkSwayCm?.takeIf { it.isFinite() }?.let { addMetric("步态躯干侧向摆动 %.1f cm".format(kotlin.math.abs(it))) }
                gait?.gaitObservedAbnormal?.let { addMetric(if (it) "步态人工观察：存在异常" else "步态人工观察：未见异常") }
                gait?.gaitObservationNote?.trim()?.takeIf { it.isNotEmpty() }?.let { addMetric("步态备注：$it") }
                seated?.seatedThoracicKyphosisObserved?.let { addMetric(if (it) "坐姿观察：存在圆肩驼背表现" else "坐姿观察：未见明显圆肩驼背") }
                seated?.occiputWallDistanceCm?.takeIf { it.isFinite() && it >= 0 }?.let { addMetric("枕墙距 %.1f cm".format(it)) }
                if (!ageApplicable) add("本五项脊柱筛查手册仅适用于 6–12 岁，请核对孩子出生日期和测量日期。")

                if (hasMetricReason && validationStatus.allowsClassification) {
                    add("姿态综合关注度 %.0f分（记录稳定度 %.0f%%）".format(evidenceAdjustedScore * 100, quality * 100))
                }

                    if (isEmpty()) {
                    if (complete) {
                        add("记录不足，暂未形成完整指标。")
                    } else {
                        add("记录不足，请完成 8 段相机采集，并按每段提示通过画面质量检查。")
                    }
                }
            }

            val publishedReasons = if (validationStatus.allowsClassification) reasons else listOf(AlgorithmReleaseGate.pendingPostureNotice) + reasons
            return PostureAssessmentReport(
                generatedAt,
                algorithmVersion,
                snapshots,
                if (validationStatus.allowsClassification) level else BodyAttentionLevel.Pending,
                publishedReasons,
                "当前手机二维视觉仅用于家庭姿态观察和采集质量检查，不输出肋峰、ATR或Cobb角，也不替代学校筛查、体检或影像检查。出现持续疼痛、活动受限或明显异常体征，请停止测试并咨询专业人员。",
                riskScore = if (validationStatus.allowsClassification) (evidenceAdjustedScore * 100).toInt() else 0,
                qualityScore = (quality * 100).toInt(),
                validationStatus = validationStatus
            )
        }

        /** Test/evaluation only; product code must use the fail-closed default. */
        fun makeValidatedFixture(snapshots: Map<BodyCaptureTask, PostureMetricSnapshot>, generatedAt: String, ageMonths: Int? = null): PostureAssessmentReport =
            make(snapshots, generatedAt, ageMonths ?: 108, AlgorithmValidationStatus.HumanValidated)

    }
}
