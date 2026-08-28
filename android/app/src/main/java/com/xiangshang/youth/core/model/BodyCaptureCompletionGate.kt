package com.xiangshang.youth.core.model

/** Rear-view Adams completion score. As the trunk approaches horizontal,
 * its projected vertical length becomes shorter relative to shoulder
 * width. This only verifies that the guided action was performed; it is
 * not an ATR, rib-prominence or scoliosis measurement. */
fun BodyCaptureQualityGate.adamsForwardBendCompletionScore(
    leftShoulderX: Double,
    leftShoulderY: Double,
    rightShoulderX: Double,
    rightShoulderY: Double,
    hipCenterY: Double
): Double? {
    val values = listOf(leftShoulderX, leftShoulderY, rightShoulderX, rightShoulderY, hipCenterY)
    if (!values.all(Double::isFinite)) return null
    val shoulderWidth = kotlin.math.hypot(leftShoulderX - rightShoulderX, leftShoulderY - rightShoulderY)
    if (shoulderWidth < .001) return null
    val shoulderCenterY = (leftShoulderY + rightShoulderY) / 2.0
    val verticalTorsoRatio = kotlin.math.abs(shoulderCenterY - hipCenterY) / shoulderWidth
    return (1.0 - verticalTorsoRatio).coerceIn(0.0, 1.0)
}

fun BodyCaptureQualityGate.jointAngle(firstX: Double, firstY: Double, jointX: Double, jointY: Double, thirdX: Double, thirdY: Double): Double? {
    val values = listOf(firstX, firstY, jointX, jointY, thirdX, thirdY)
    if (!values.all(Double::isFinite)) return null
    val a = kotlin.math.hypot(firstX - jointX, firstY - jointY)
    val b = kotlin.math.hypot(thirdX - jointX, thirdY - jointY)
    val c = kotlin.math.hypot(firstX - thirdX, firstY - thirdY)
    if (a <= .001 || b <= .001) return null
    val cosine = ((a * a + b * b - c * c) / (2 * a * b)).coerceIn(-1.0, 1.0)
    return Math.toDegrees(kotlin.math.acos(cosine))
}

fun BodyCaptureQualityGate.hasAdamsLowerBodyPosition(kneeAngles: List<Double>, ankleGap: Double?, shoulderWidth: Double, requiresBothFeet: Boolean): Boolean {
    if (!shoulderWidth.isFinite() || shoulderWidth <= .001 || kneeAngles.size < if (requiresBothFeet) 2 else 1) return false
    if (!kneeAngles.all { it.isFinite() && it >= adamsMinimumKneeExtensionDegrees && it <= 180.5 }) return false
    if (requiresBothFeet && ankleGap == null) return false
    return ankleGap?.let { it.isFinite() && it >= 0 && it <= maxOf(.045, shoulderWidth * .42) } ?: true
}

fun BodyCaptureQualityGate.hasReliableLandmarks(confidences: List<Float>): Boolean = hasReliableLandmarks(confidences, null)

fun BodyCaptureQualityGate.staticProgress(elapsedMs: Long, ageMonths: Int?): Float {
    val profile = profileForAge(ageMonths)
    return (elapsedMs.toFloat() / profile.staticHoldMilliseconds).coerceIn(0f, .96f)
}

fun BodyCaptureQualityGate.staticProgress(elapsedMs: Long): Float = staticProgress(elapsedMs, null)

fun BodyCaptureQualityGate.gaitProgress(elapsedMs: Long, hasMoved: Boolean, ageMonths: Int?): Float {
    val profile = profileForAge(ageMonths)
    return if (hasMoved) (.2f + elapsedMs.toFloat() / profile.gaitMinimumMilliseconds * .8f).coerceAtMost(.96f) else .12f
}

fun BodyCaptureQualityGate.gaitProgress(elapsedMs: Long, hasMoved: Boolean): Float = gaitProgress(elapsedMs, hasMoved, null)
