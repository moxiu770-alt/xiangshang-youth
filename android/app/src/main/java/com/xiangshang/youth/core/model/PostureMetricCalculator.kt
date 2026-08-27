package com.xiangshang.youth.core.model

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
