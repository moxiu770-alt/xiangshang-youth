package com.xiangshang.youth.core.model

object PostureMetricCalculator {
    data class RepeatabilityResult(
        val runCount: Int,
        val range: Double?,
        val standardDeviation: Double?,
        val passed: Boolean
    )
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
    fun median(values: List<Double>): Double? {
        val sorted = values.filter { it.isFinite() }.sorted()
        if (sorted.isEmpty()) return null
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[middle - 1] + sorted[middle]) / 2.0 else sorted[middle]
    }
    /** MAD-filtered median prevents one landmark jump from moving a result. */
    fun robustMedian(values: List<Double>, madMultiplier: Double = 3.5): Double? {
        val finite = values.filter { it.isFinite() }
        val center = median(finite) ?: return null
        val mad = median(finite.map { kotlin.math.abs(it - center) }) ?: return center
        if (mad <= .000_001) return center
        val fence = mad * maxOf(2.5, madMultiplier)
        return median(finite.filter { kotlin.math.abs(it - center) <= fence }) ?: center
    }
    fun medianAbsoluteDeviation(values: List<Double>): Double? {
        val finite = values.filter { it.isFinite() }
        if (finite.size < 2) return null
        val center = median(finite) ?: return null
        return median(finite.map { kotlin.math.abs(it - center) })
    }
    fun standardDeviation(values: List<Double>): Double? {
        val finite = values.filter { it.isFinite() }
        if (finite.size < 2) return null
        val mean = finite.average()
        return kotlin.math.sqrt(finite.sumOf { (it - mean) * (it - mean) } / (finite.size - 1))
    }
    /** Capture-quality stability only; this is not a health threshold. */
    fun isStableSeries(values: List<Double>, minimumSamples: Int, maximumMedianAbsoluteDeviation: Double): Boolean {
        val finite = values.filter { it.isFinite() }
        val mad = medianAbsoluteDeviation(finite) ?: return false
        return finite.size >= minimumSamples && maximumMedianAbsoluteDeviation.isFinite() &&
            maximumMedianAbsoluteDeviation >= 0.0 && mad <= maximumMedianAbsoluteDeviation
    }
}
