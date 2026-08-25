import Foundation

enum GrowthReportPeriod: String, CaseIterable, Identifiable {
    case week = "本周"
    case month = "本月"

    var id: String { rawValue }
    var dayCount: Int { self == .week ? 7 : 30 }
    var targetActiveDays: Int { self == .week ? 4 : 16 }
}

/// A deterministic client-side summary built only from persisted family data.
/// It remains useful in Mock/offline mode and can later be replaced by a
/// server-authored report without changing the presentation contract.
struct GrowthInsight: Equatable {
    static let algorithmVersion = "UY-GROWTH-RULE-1.1"
    static let calibrationVersion = "UY-CAL-BASELINE-1.0"
    let period: GrowthReportPeriod
    let activeDays: Int
    let targetActiveDays: Int
    let planDays: Int
    let assessmentCount: Int
    let consistencyPercent: Int
    let planTitle: String
    let planReason: String
    let sessionsPerWeek: Int
    let minutesPerSession: Int
    let actions: [String]

    static func make(
        period: GrowthReportPeriod,
        checkInDates: Set<String>,
        planDates: Set<String>,
        assessmentCount: Int,
        bodyAttention: BodyAssessmentRecord.AttentionLevel?,
        /// `nil` means the school report has not been published yet. It must
        /// never be treated as a score of zero, otherwise a family receives a
        /// fabricated “weak ability” recommendation.
        totalScore: Double?,
        now: Date = .now
    ) -> GrowthInsight {
        // Growth windows are a business rule, not a device-local rule. Use
        // the same China calendar as the server and Android so a midnight
        // boundary cannot move an activity between weeks on different phones.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = businessTimeZone
        let start = calendar.date(byAdding: .day, value: -(period.dayCount - 1), to: calendar.startOfDay(for: now)) ?? now
        let recentCheckIns = Set(checkInDates.filter { date($0).map { $0 >= start && $0 <= now } ?? false })
        let recentPlanDates = Set(planDates.filter { date($0).map { $0 >= start && $0 <= now } ?? false })
        let activeDates = recentCheckIns.union(recentPlanDates)
        let percent = min(100, Int((Double(activeDates.count) / Double(max(period.targetActiveDays, 1)) * 100).rounded()))

        let safeAssessmentCount = max(0, assessmentCount)
        let safeTotalScore: Double? = {
            guard let value = totalScore, value.isFinite else { return nil }
            return min(AssessmentScoreRules.totalMaximum, max(0, value))
        }()
        let plan: (String, String, Int, Int, [String])
        switch bodyAttention {
        case .red:
            plan = ("低冲击观察计划", "身体测评出现需进一步关注的信号，本周优先轻量活动与复测，不增加动作强度。", 3, 10, ["完成一次家长陪同复测", "选择低冲击姿态课程", "出现疼痛或活动受限时停止并咨询专业人员"])
        case .yellow:
            plan = ("姿态巩固计划", "根据近期记录，已缩短单次时长并增加姿态练习。", 4, 12, ["完成 2 次肩背与站姿练习", "完成 1 次自然步态观察", "按提醒日期复测并记录变化"])
        case .pending:
            plan = ("完成家庭观察计划", "拍摄任务尚未完成；先完成剩余引导，不将未完成记录当作健康风险。", 2, 8, ["完成剩余拍摄记录", "由家长确认观察结果", "完成后再查看训练建议"])
        case .unavailable:
            plan = ("完善成长资料计划", "尚缺少年龄别 BMI 筛查所需的生日信息；先补全资料，再生成对应参考。", 2, 8, ["核对孩子生日", "保留本次真实身高体重", "资料完整后查看年龄别 BMI 参考"])
        case _ where percent < 50:
            plan = ("轻量习惯计划", "近期完成率低于目标，先降低开始门槛，建立稳定运动习惯。", 3, 10, ["任选 3 天完成 10 分钟运动", "每次训练后完成打卡", "周末回顾一次身体感受"])
        case _ where (safeTotalScore ?? .infinity) < AssessmentScoreRules.attentionTotalThreshold:
            plan = ("基础能力提升计划", "综合运动能力仍有提升空间，计划保持中等频率并优先练习薄弱项。", 4, 15, ["完成 2 次薄弱能力课程", "完成 1 次平衡或协调练习", "训练后记录难度与完成感受"])
        case _:
            plan = ("均衡成长计划", "近期完成率和测评状态稳定，维持当前节奏并逐步增加动作质量。", 4, 15, ["完成 2 次综合能力课程", "完成 1 次户外运动", "保留 1 天亲子轻松活动"])
        }

        return GrowthInsight(period: period, activeDays: activeDates.count, targetActiveDays: period.targetActiveDays, planDays: recentPlanDates.count, assessmentCount: safeAssessmentCount, consistencyPercent: percent, planTitle: plan.0, planReason: plan.1, sessionsPerWeek: plan.2, minutesPerSession: plan.3, actions: plan.4)
    }

    private static func date(_ value: String) -> Date? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        // DateFormatter is mutable. Build a short-lived parser per call so
        // concurrent StateObject refreshes cannot race on shared formatter
        // state and change which activity dates are accepted.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = businessTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let parsed = formatter.date(from: normalized), formatter.string(from: parsed) == normalized else { return nil }
        return parsed
    }
    private static let businessTimeZone = TimeZone(identifier: "Asia/Shanghai")!
}
