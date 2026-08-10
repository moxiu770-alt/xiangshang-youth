package com.xiangshang.youth.core.model

enum class BodyAttentionLevel(val label: String) { Green("正常关注"), Yellow("建议关注"), Red("建议进一步评估") }
enum class BodyCaptureTask(val title: String, val guide: String) { StandingBack("自然站姿", "背对镜头自然站立，双脚与肩同宽"), ForwardBend("前屈观察", "成人陪同下缓慢前屈，不适立即停止"), Seated("坐姿观察", "坐在无靠背椅上，双手自然放在膝盖"), GaitVideo("步态视频", "沿直线自然行走 3–5 秒，从后方拍摄") }
data class BodyAssessmentRecord(val heightCm: Double, val weightKg: Double, val measuredAt: String, val captures: Set<BodyCaptureTask>, val asymmetric: Boolean, val gaitConcern: Boolean, val nextFollowUp: String, val planDays: Set<String> = emptySet()) {
    val bmi: Double get() = if (heightCm <= 0) 0.0 else weightKg / ((heightCm / 100) * (heightCm / 100))
    fun bmiLevel(age: Int, gender: String): BodyAttentionLevel { val pair = if (gender.contains("男")) mapOf(7 to (17.8 to 20.2), 8 to (18.1 to 20.8), 9 to (18.5 to 21.9), 10 to (19.2 to 23.0), 11 to (19.9 to 24.1))[age] else mapOf(7 to (17.6 to 20.0), 8 to (18.1 to 20.8), 9 to (18.5 to 21.5), 10 to (19.5 to 22.7), 11 to (20.5 to 23.9))[age]; val t = pair ?: (19.0 to 22.0); return if (bmi >= t.second) BodyAttentionLevel.Red else if (bmi >= t.first) BodyAttentionLevel.Yellow else BodyAttentionLevel.Green }
    fun level(age: Int, gender: String): BodyAttentionLevel = if (bmiLevel(age, gender) == BodyAttentionLevel.Red || asymmetric && gaitConcern) BodyAttentionLevel.Red else if (bmiLevel(age, gender) == BodyAttentionLevel.Yellow || asymmetric || gaitConcern || captures.size < 4) BodyAttentionLevel.Yellow else BodyAttentionLevel.Green
}
val Student.bodyAssessmentAge: Int get() = when { grade.contains("一") -> 7; grade.contains("二") -> 8; grade.contains("三") -> 9; grade.contains("四") -> 10; grade.contains("五") -> 11; else -> 12 }
