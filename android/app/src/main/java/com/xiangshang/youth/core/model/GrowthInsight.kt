package com.xiangshang.youth.core.model

import java.text.SimpleDateFormat
import java.text.ParsePosition
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

enum class GrowthReportPeriod(val label: String, val dayCount: Int, val targetActiveDays: Int) {
    Week("本周", 7, 4), Month("本月", 30, 16)
}

data class GrowthInsight(
    val period: GrowthReportPeriod,
    val activeDays: Int,
    val targetActiveDays: Int,
    val planDays: Int,
    val assessmentCount: Int,
    val consistencyPercent: Int,
    val planTitle: String,
    val planReason: String,
    val sessionsPerWeek: Int,
    val minutesPerSession: Int,
    val actions: List<String>
) {
    companion object {
        const val algorithmVersion = "UY-GROWTH-RULE-1.1"
        const val calibrationVersion = "UY-CAL-BASELINE-1.0"
        fun make(
            period: GrowthReportPeriod,
            checkInDates: Set<String>,
            planDates: Set<String>,
            assessmentCount: Int,
            bodyAttention: BodyAttentionLevel?,
            /** Null means the school has not published a report. Never use
             * zero as a placeholder for an unknown score. */
            totalScore: Double?,
            now: Date = Date()
        ): GrowthInsight {
            val calendar = Calendar.getInstance(businessTimeZone).apply { time = now; add(Calendar.DAY_OF_YEAR, -(period.dayCount - 1)); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
            val start = calendar.time
            fun recent(values: Set<String>) = values.filterTo(mutableSetOf()) { value ->
                parseBusinessDate(value)?.let { !it.before(start) && !it.after(now) } ?: false
            }
            val recentCheckIns = recent(checkInDates)
            val recentPlanDates = recent(planDates)
            val activeDates = recentCheckIns + recentPlanDates
            val consistency = kotlin.math.round((activeDates.size.toDouble() / period.targetActiveDays.coerceAtLeast(1)) * 100).toInt().coerceIn(0, 100)

            val safeAssessmentCount = assessmentCount.coerceAtLeast(0)
            val safeTotalScore = totalScore?.takeIf { it.isFinite() }?.coerceIn(0.0, AssessmentScoreRules.totalMaximum)
            val plan = when {
                bodyAttention == BodyAttentionLevel.Red -> Plan("低冲击观察计划", "身体测评出现需进一步关注的信号，本周优先轻量活动与复测，不增加动作强度。", 3, 10, listOf("完成一次家长陪同复测", "选择低冲击姿态课程", "出现疼痛或活动受限时停止并咨询专业人员"))
                bodyAttention == BodyAttentionLevel.Yellow -> Plan("姿态巩固计划", "根据近期记录，已缩短单次时长并增加姿态练习。", 4, 12, listOf("完成 2 次肩背与站姿练习", "完成 1 次自然步态观察", "按提醒日期复测并记录变化"))
                bodyAttention == BodyAttentionLevel.Pending -> Plan("完成家庭观察计划", "拍摄任务尚未完成；先完成剩余引导，不将未完成记录当作健康风险。", 2, 8, listOf("完成剩余拍摄记录", "由家长确认观察结果", "完成后再查看训练建议"))
                bodyAttention == BodyAttentionLevel.Unavailable -> Plan("完善成长资料计划", "尚缺少年龄别 BMI 筛查所需的生日信息；先补全资料，再生成对应参考。", 2, 8, listOf("核对孩子生日", "保留本次真实身高体重", "资料完整后查看年龄别 BMI 参考"))
                consistency < 50 -> Plan("轻量习惯计划", "近期完成率低于目标，先降低开始门槛，建立稳定运动习惯。", 3, 10, listOf("任选 3 天完成 10 分钟运动", "每次训练后完成打卡", "周末回顾一次身体感受"))
                safeTotalScore != null && safeTotalScore < AssessmentScoreRules.attentionTotalThreshold -> Plan("基础能力提升计划", "综合运动能力仍有提升空间，计划保持中等频率并优先练习薄弱项。", 4, 15, listOf("完成 2 次薄弱能力课程", "完成 1 次平衡或协调练习", "训练后记录难度与完成感受"))
                else -> Plan("均衡成长计划", "近期完成率和测评状态稳定，维持当前节奏并逐步增加动作质量。", 4, 15, listOf("完成 2 次综合能力课程", "完成 1 次户外运动", "保留 1 天亲子轻松活动"))
            }
            return GrowthInsight(period, activeDates.size, period.targetActiveDays, recentPlanDates.size, safeAssessmentCount, consistency, plan.title, plan.reason, plan.sessions, plan.minutes, plan.actions)
        }

        private val businessTimeZone = TimeZone.getTimeZone("Asia/Shanghai")
        private fun parseBusinessDate(raw: String): Date? {
            val value = raw.trim()
            if (!Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(value)) return null
            // SimpleDateFormat is mutable and not thread-safe. Growth reports
            // can be recomputed concurrently by StateFlow collectors and
            // background refreshes, so never share one parser instance.
            val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
                isLenient = false
                timeZone = businessTimeZone
            }
            val position = ParsePosition(0)
            val parsed = formatter.parse(value, position)
            return parsed?.takeIf { position.index == value.length }
        }
    }

    private data class Plan(val title: String, val reason: String, val sessions: Int, val minutes: Int, val actions: List<String>)
}
