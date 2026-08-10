import Foundation

/// Family-side body assessment.  This is deliberately a health-management
/// record, not a medical diagnosis or a replacement for a school screening.
struct BodyAssessmentRecord: Codable, Equatable {
    enum AttentionLevel: String, Codable, CaseIterable {
        case green, yellow, red

        var label: String {
            switch self {
            case .green: "正常关注"
            case .yellow: "建议关注"
            case .red: "建议进一步评估"
            }
        }
    }

    enum CaptureTask: String, Codable, CaseIterable, Identifiable {
        case standingBack, forwardBend, seatedPosture, gaitVideo

        var id: String { rawValue }
        var title: String {
            switch self {
            case .standingBack: "自然站姿"
            case .forwardBend: "前屈观察"
            case .seatedPosture: "坐姿观察"
            case .gaitVideo: "步态视频"
            }
        }
        var instruction: String {
            switch self {
            case .standingBack: "背对镜头自然站立，双脚与肩同宽。"
            case .forwardBend: "家长陪同下缓慢前屈，感到不适立即停止。"
            case .seatedPosture: "坐在无靠背椅上，双手自然放在膝盖。"
            case .gaitVideo: "沿直线自然行走 3–5 秒，镜头从后方拍摄。"
            }
        }
    }

    struct Observation: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let detail: String
        let level: AttentionLevel
    }

    var heightCentimeters: Double
    var weightKilograms: Double
    var measuredAt: Date
    var ruleVersion: String
    var completedCaptures: Set<CaptureTask>
    var parentMarkedAsymmetric: Bool
    var parentMarkedGaitConcern: Bool
    var savedAt: Date
    var nextFollowUpDate: Date
    var completedPlanDays: Set<String>

    static let ruleVersion = "WS/T 586—2018 年龄别 BMI 参考 v1.0"

    var bmi: Double {
        guard heightCentimeters > 0 else { return 0 }
        return weightKilograms / pow(heightCentimeters / 100, 2)
    }

    /// This screen serves grade-school children.  The thresholds intentionally
    /// use age/sex rules instead of adult BMI cut-offs.  The remote rule engine
    /// can replace this bundled reference without changing the UI.
    func bmiAttention(age: Int, gender: String) -> AttentionLevel {
        let isBoy = gender.contains("男")
        let table: [Int: (Double, Double)] = isBoy
            ? [6: (17.4, 19.6), 7: (17.8, 20.2), 8: (18.1, 20.8), 9: (18.5, 21.9), 10: (19.2, 23.0), 11: (19.9, 24.1), 12: (20.7, 25.2)]
            : [6: (17.2, 19.3), 7: (17.6, 20.0), 8: (18.1, 20.8), 9: (18.5, 21.5), 10: (19.5, 22.7), 11: (20.5, 23.9), 12: (21.5, 25.0)]
        let threshold = table[min(max(age, 6), 12)] ?? (19.0, 22.0)
        if bmi >= threshold.1 { return .red }
        if bmi >= threshold.0 { return .yellow }
        return .green
    }

    func postureAttention() -> AttentionLevel {
        if parentMarkedAsymmetric && parentMarkedGaitConcern { return .red }
        if parentMarkedAsymmetric || parentMarkedGaitConcern { return .yellow }
        return completedCaptures.count == CaptureTask.allCases.count ? .green : .yellow
    }

    func attention(age: Int, gender: String) -> AttentionLevel {
        let levels = [bmiAttention(age: age, gender: gender), postureAttention()]
        if levels.contains(.red) { return .red }
        if levels.contains(.yellow) { return .yellow }
        return .green
    }

    func observations(age: Int, gender: String) -> [Observation] {
        let posture = postureAttention()
        return [
            Observation(id: "bmi", title: "BMI 年龄别参考", detail: String(format: "BMI %.1f · %@", bmi, ruleVersion), level: bmiAttention(age: age, gender: gender)),
            Observation(id: "shoulder", title: "肩部与骨盆对称", detail: parentMarkedAsymmetric ? "家长观察到明显不对称，建议按提示复测。" : "本次家长观察未标记明显不对称。", level: parentMarkedAsymmetric ? posture : .green),
            Observation(id: "gait", title: "步态动态观察", detail: parentMarkedGaitConcern ? "家长观察到行走中持续偏移或不对称。" : "本次家长观察未标记持续步态偏移。", level: parentMarkedGaitConcern ? posture : .green),
            Observation(id: "capture", title: "视觉捕捉完整度", detail: "已完成 \(completedCaptures.count) / \(CaptureTask.allCases.count) 个引导任务。", level: completedCaptures.count == CaptureTask.allCases.count ? .green : .yellow)
        ]
    }
}

extension Student {
    /// Mock student profiles do not expose a birth date yet.  Grade is used
    /// only as a local placeholder until the real profile API supplies age in
    /// months, which then becomes the authoritative BMI rule input.
    var bodyAssessmentAge: Int {
        if grade.contains("一年级") { return 7 }
        if grade.contains("二年级") { return 8 }
        if grade.contains("三年级") { return 9 }
        if grade.contains("四年级") { return 10 }
        if grade.contains("五年级") { return 11 }
        return 12
    }
}
