package com.xiangshang.youth.core.model

/** Engineering candidates for offline validation; not published health cut-offs. */
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
    /** 待验证工程候选值，不代表已由儿童标注样本证实。 */
    const val seatedMidlineAttentionCentimeters = 1.3
    /** 2D 估算下的胸椎前凸/圆背警戒线。 */
    const val seatedRoundingAttentionDegrees = 24.0
    /** 待验证的二维视觉代理值，不作为专业CVA或健康结论。 */
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
