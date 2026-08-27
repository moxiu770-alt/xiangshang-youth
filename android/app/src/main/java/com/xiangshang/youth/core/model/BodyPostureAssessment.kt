package com.xiangshang.youth.core.model

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
