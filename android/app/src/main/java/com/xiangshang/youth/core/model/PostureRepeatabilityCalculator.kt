package com.xiangshang.youth.core.model

/** Engineering ten-run gate; real child/device runs must supply values. */
fun PostureMetricCalculator.repeatability(values: List<Double>, minimumRuns: Int = 10, maximumRange: Double, maximumStandardDeviation: Double): PostureMetricCalculator.RepeatabilityResult {
    val finite = values.filter { it.isFinite() }
    val measuredRange = range(finite)
    val deviation = standardDeviation(finite)
    return PostureMetricCalculator.RepeatabilityResult(
        finite.size,
        measuredRange,
        deviation,
        finite.size >= minimumRuns && (measuredRange ?: Double.POSITIVE_INFINITY) <= maximumRange && (deviation ?: Double.POSITIVE_INFINITY) <= maximumStandardDeviation
    )
}
/** Use motion range rather than maximum baseline offset for gait sway. */
fun PostureMetricCalculator.range(values: List<Double>): Double? {
    val finite = values.filter { it.isFinite() }
    val minimum = finite.minOrNull() ?: return null
    val maximum = finite.maxOrNull() ?: return null
    return (maximum - minimum).coerceAtLeast(0.0)
}
/** Trim both tails so one isolated gait landmark jump cannot set amplitude. */
fun PostureMetricCalculator.robustRange(values: List<Double>, trimFraction: Double = 0.10): Double? {
    val sorted = values.filter { it.isFinite() }.sorted()
    if (sorted.size < 3 || !trimFraction.isFinite() || trimFraction < 0.0 || trimFraction >= 0.5) return null
    val trimCount = minOf((sorted.size - 2) / 2, kotlin.math.floor(sorted.size * trimFraction).toInt())
    return range(sorted.subList(trimCount, sorted.size - trimCount))
}
