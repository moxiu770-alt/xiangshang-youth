package com.xiangshang.youth.core.model

import java.text.SimpleDateFormat
import java.util.Date
import java.util.TimeZone
import java.util.Locale

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
    val postureSnapshots: Map<BodyCaptureTask, PostureMetricSnapshot> = emptyMap(),
    val standingShoulderDifferenceCm: Double? = null,
    val standingPelvisDifferenceCm: Double? = null,
    val standingHeadTiltDegrees: Double? = null,
    val adamsObservedResult: String? = null,
    val adamsProminenceSide: String? = null,
    val gaitObservedAbnormal: Boolean? = null,
    val gaitObservationNote: String? = null,
    val seatedMidlineDifferenceCm: Double? = null,
    val seatedShoulderDifferenceCm: Double? = null,
    val seatedThoracicKyphosisObserved: Boolean? = null,
    val thoracicAtrDegrees: Double? = null,
    val lumbarAtrDegrees: Double? = null,
    val thoracicAtrSide: String? = null,
    val lumbarAtrSide: String? = null,
    val atrRetestEnabled: Boolean = false,
    val thoracicAtrRepeatDegrees: Double? = null,
    val lumbarAtrRepeatDegrees: Double? = null,
    val seatedForwardBendAtrDegrees: Double? = null,
    val occiputWallDistanceFirstCm: Double? = null,
    val occiputWallDistanceSecondCm: Double? = null,
    val occiputWallDistanceCm: Double? = null
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
