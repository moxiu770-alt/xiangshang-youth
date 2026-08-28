import Foundation

enum BodyMeasurementInput {
    static func normalized(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
        guard range.lowerBound.isFinite, range.upperBound.isFinite, range.lowerBound <= range.upperBound, step.isFinite, step > 0 else { return range.lowerBound }
        guard value.isFinite else { return range.lowerBound }
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        let snapped = (clamped / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }
}

/// Current-height classification from WS/T 612—2018. This is a growth
/// reference for ages 7–18, not an adult-height prediction or diagnosis.
enum HeightDevelopmentLevel: String, Codable, CaseIterable {
    case low, lower, middle, upper, high

    var label: String {
        switch self {
        case .low: "下等"
        case .lower: "中下等"
        case .middle: "中等"
        case .upper: "中上等"
        case .high: "上等"
        }
    }
}

struct HeightDevelopmentAssessment: Codable, Equatable {
    let ageYears: Int
    let heightCentimeters: Double
    let level: HeightDevelopmentLevel
    let lowerTwoSD: Double
    let lowerOneSD: Double
    let median: Double
    let upperOneSD: Double
    let upperTwoSD: Double
    let ruleVersion: String
}

/// Family-side body assessment.  This is deliberately a health-management
/// record, not a medical diagnosis or a replacement for a school screening.
struct BodyAssessmentRecord: Codable, Equatable {
    enum AttentionLevel: String, Codable, CaseIterable {
        /// The family has not yet completed every camera-guided task. This is
        /// a data-completeness state, never a health-risk classification.
        case pending
        case green, yellow, red, unavailable

        var label: String {
            switch self {
            case .pending: "待完成拍摄记录"
            case .green: "本次观察已完成"
            case .yellow: "建议关注"
            case .red: "建议进一步评估"
            case .unavailable: "待完善生日"
            }
        }
    }

    enum CaptureTask: String, Codable, CaseIterable, Identifiable {
        case standingFront, standingBack, standingSide, forwardBend
        case dynamicKneeControl, gaitVideo, seatedPosture, footArch

        var id: String { rawValue }
        var title: String {
            switch self {
            case .standingFront: "正面自然站立观察"
            case .standingBack: "静态站姿对称观察"
            case .standingSide: "左右侧位姿态观察"
            case .forwardBend: "亚当斯前屈试验"
            case .dynamicKneeControl: "动态下肢力线观察"
            case .seatedPosture: "无靠背坐姿脊柱直立测试"
            case .gaitVideo: "动态步态姿态观察"
            case .footArch: "足弓与足跟对齐观察"
            }
        }
        var instruction: String { SpineScreeningStandard.instruction(for: self) }
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
    /// A non-diagnostic, on-device framing/alignment prompt. This is kept only
    /// after the parent has chosen to save the observation; raw media is never
    /// stored by the app.
    var visualObservationHint: String? = nil
    /// Task-scoped, non-diagnostic prompts. Keeping the task with each prompt
    /// makes resumed drafts and remote sync auditable without retaining media.
    var captureObservationHints: [CaptureTask: String] = [:]
    /// Parent-reported values used only for the family-height reference. They
    /// are optional so existing local records remain readable.
    var fatherHeightCentimeters: Double? = nil
    var motherHeightCentimeters: Double? = nil
    var savedAt: Date
    var nextFollowUpDate: Date
    var completedPlanDays: Set<String>
    var postureReport: PostureAssessmentReport? = nil
    /// Frozen at measurement time so historical BMI/height bands do not drift
    /// when a child crosses a half-year age boundary later.
    var ageMonthsAtMeasurement: Int? = nil

    static let ruleVersion = "WS/T 586—2018 年龄别 BMI 参考 v1.1"
    static let bmiAlgorithmVersion = "UY-IMCA-BMI-1.2"
    static let heightAlgorithmVersion = "UY-IMCA-HEIGHT-1.0"
    static let geneticHeightRangeHalfWidthCentimeters = 5.0
    // WS/T 586 child BMI tables end at the 18-year (216-month) row. Do not
    // silently reuse the adult cutoff for older ages.
    static let bmiSupportedAgeMonths = 72...216
    static let heightSupportedAgeMonths = 84...227

    /// Accept the API's Chinese labels as well as common import/remote codes.
    /// Keeping this normalization local prevents an English `male`/`female`
    /// payload from silently becoming an unavailable BMI result on iOS.
    private static func genderIsBoy(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "男", "男性", "boy", "male", "m", "1": return true
        case "女", "女性", "girl", "female", "f", "2": return false
        default: return nil
        }
    }

    var bmi: Double {
        guard heightCentimeters.isFinite, weightKilograms.isFinite,
              heightCentimeters >= 90, heightCentimeters <= 190,
              weightKilograms >= 15, weightKilograms <= 90 else { return 0 }
        let value = weightKilograms / pow(heightCentimeters / 100, 2)
        return value.isFinite ? value : 0
    }

    /// WS/T 586—2018 requires BMI to be retained to one decimal place before
    /// comparing it with the age/sex screening cut-offs.
    var bmiForScreening: Double {
        guard bmi > 0 else { return 0 }
        return floor(bmi * 10 + 0.5) / 10
    }

    /// A commonly used family-height reference, not a diagnosis or a promise
    /// of adult height.  Male: (father + mother + 13cm) / 2; female:
    /// (father + mother - 13cm) / 2.
    func geneticHeightReference(gender: String) -> Double? {
        guard let fatherHeightCentimeters, let motherHeightCentimeters,
              fatherHeightCentimeters.isFinite, motherHeightCentimeters.isFinite,
              (120...230).contains(fatherHeightCentimeters),
              (120...230).contains(motherHeightCentimeters),
              let isBoy = Self.genderIsBoy(gender) else { return nil }
        let adjustment = isBoy ? 13.0 : -13.0
        return (fatherHeightCentimeters + motherHeightCentimeters + adjustment) / 2
    }

    /// Mid-parental target height with a transparent ±5 cm family range.
    /// This is a health-management estimate, not a medical guarantee.
    func geneticHeightRange(gender: String) -> ClosedRange<Double>? {
        guard let reference = geneticHeightReference(gender: gender) else { return nil }
        return (reference - Self.geneticHeightRangeHalfWidthCentimeters)...(reference + Self.geneticHeightRangeHalfWidthCentimeters)
    }

    func geneticHeightFormula(gender: String) -> String {
        if Self.genderIsBoy(gender) == true { return "（父亲身高 + 母亲身高 + 13 cm）÷ 2" }
        if Self.genderIsBoy(gender) == false { return "（父亲身高 + 母亲身高 − 13 cm）÷ 2" }
        return "待完善孩子性别后计算"
    }

    /// Classifies the measured height against the national 7–18 year
    /// age/sex reference. The completed age in years is used, matching the
    /// standard's annual reference rows.
    func heightDevelopmentAssessment(ageMonths: Int?, gender: String) -> HeightDevelopmentAssessment? {
        let effectiveAgeMonths = ageMonthsAtMeasurement ?? ageMonths
        guard heightCentimeters.isFinite, heightCentimeters >= 90, heightCentimeters <= 190, let effectiveAgeMonths,
              Self.heightSupportedAgeMonths.contains(effectiveAgeMonths),
              let isBoy = Self.genderIsBoy(gender) else { return nil }
        let ageYears = min(18, max(7, effectiveAgeMonths / 12))
        let row = HeightReference.row(ageYears: ageYears, isBoy: isBoy)
        let level: HeightDevelopmentLevel
        if heightCentimeters < row.minusTwoSD { level = .low }
        else if heightCentimeters < row.minusOneSD { level = .lower }
        else if heightCentimeters <= row.plusOneSD { level = .middle }
        else if heightCentimeters <= row.plusTwoSD { level = .upper }
        else { level = .high }
        return HeightDevelopmentAssessment(ageYears: ageYears, heightCentimeters: heightCentimeters, level: level, lowerTwoSD: row.minusTwoSD, lowerOneSD: row.minusOneSD, median: row.median, upperOneSD: row.plusOneSD, upperTwoSD: row.plusTwoSD, ruleVersion: "WS/T 612—2018")
    }

    /// Uses WS/T 586—2018's sex/age (half-year) screening threshold table.
    /// This is a screening result for overweight/obesity only, not a judgement
    /// of overall nutrition status or a clinical diagnosis.
    func bmiAttention(ageMonths: Int?, gender: String) -> AttentionLevel {
        let effectiveAgeMonths = ageMonthsAtMeasurement ?? ageMonths
        guard bmiForScreening > 0, let effectiveAgeMonths, Self.bmiSupportedAgeMonths.contains(effectiveAgeMonths), let isBoy = Self.genderIsBoy(gender) else { return .unavailable }
        let threshold = BMIReference.threshold(ageMonths: effectiveAgeMonths, isBoy: isBoy)
        if bmiForScreening >= threshold.1 { return .red }
        if bmiForScreening >= threshold.0 { return .yellow }
        return .green
    }

    func bmiScreeningLabel(ageMonths: Int?, gender: String) -> String {
        guard bmi > 0 else { return "待填写身高体重" }
        let effectiveAgeMonths = ageMonthsAtMeasurement ?? ageMonths
        guard let effectiveAgeMonths else { return "待完善出生日期" }
        guard Self.genderIsBoy(gender) != nil else { return "待完善性别" }
        guard Self.bmiSupportedAgeMonths.contains(effectiveAgeMonths) else { return "适用年龄为 6–18 岁" }
        switch bmiAttention(ageMonths: effectiveAgeMonths, gender: gender) {
        case .pending: return "待完成拍摄记录"
        case .green: return "未达到超重筛查界值"
        case .yellow: return "超重筛查关注"
        case .red: return "肥胖筛查关注"
        case .unavailable: return "待完善生日"
        }
    }

    func postureAttention() -> AttentionLevel {
        if parentMarkedAsymmetric && parentMarkedGaitConcern { return .red }
        if parentMarkedAsymmetric || parentMarkedGaitConcern { return .yellow }
        return completedCaptures.count == CaptureTask.allCases.count ? .green : .pending
    }

    func attention(ageMonths: Int?, gender: String) -> AttentionLevel {
        // Once the camera report exists, its objective aggregate is the source
        // of posture risk. Parent checkboxes remain safety context only and
        // must not overwrite an algorithmically generated report.
        let posture = postureReport?.overallLevel ?? postureAttention()
        let levels = [bmiAttention(ageMonths: ageMonths, gender: gender), posture]
        if levels.contains(.red) { return .red }
        if levels.contains(.yellow) { return .yellow }
        if levels.contains(.pending) { return .pending }
        if levels.contains(.unavailable) { return .unavailable }
        return .green
    }

    func observations(ageMonths: Int?, gender: String) -> [Observation] {
        let posture = postureReport?.overallLevel ?? postureAttention()
        let postureDetail: String = {
            guard let postureReport else { return "尚未形成完整姿态观察。" }
            return postureReport.canPublishClassification
                ? "本次观察已整理为结果：\(postureReport.overallLevel.label)。"
                : "姿态观察记录已保存；算法仍在人工标注验证中，暂不生成风险等级。"
        }()
        let captureQualityLevel: AttentionLevel = postureReport.map { $0.isComplete ? .green : .pending } ?? .pending
        return [
            Observation(id: "bmi", title: "BMI 年龄别筛查", detail: String(format: "BMI %.1f · %@ · %@", bmi, bmiScreeningLabel(ageMonths: ageMonths, gender: gender), ruleVersion), level: bmiAttention(ageMonths: ageMonths, gender: gender)),
            Observation(id: "shoulder", title: "姿态观察", detail: postureDetail, level: posture),
            Observation(id: "gait", title: "家长安全信息", detail: parentMarkedGaitConcern ? "家长补充：近期有行走困难或活动受限，请关注安全并咨询专业人员。" : "未补充行走困难或活动受限。", level: .green),
            Observation(id: "visual", title: "画面质量", detail: visualObservationSummary ?? "画面已完成质量检查。", level: captureQualityLevel),
            Observation(id: "capture", title: "记录完整度", detail: postureReport.map { _ in "本次记录已保存，可查看采集值和质量说明。" } ?? "已完成 \(completedCaptures.count) / \(CaptureTask.allCases.count) 个拍摄任务，仍需完成稳定度确认。", level: postureReport == nil ? .yellow : captureQualityLevel)
        ]
    }

    var visualObservationSummary: String? {
        let structured = captureObservationHints.keys.sorted { $0.rawValue < $1.rawValue }
            .compactMap { task in captureObservationHints[task].map { "\(task.title)：\($0)" } }
            .joined(separator: "\n")
        return structured.isEmpty ? visualObservationHint : structured
    }
}

extension Student {
    var bodyAssessmentAgeMonths: Int? {
        guard let birthDate else { return nil }
        return Self.ageMonths(from: birthDate)
    }
    /// Internal deterministic seam used by tests and import validation. The
    /// production property above always supplies the current instant.
    static func ageMonths(from rawBirthDate: String, now: Date = .now) -> Int? {
        let normalized = rawBirthDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let date = Self.birthDateFormatter.date(from: normalized),
              Self.birthDateFormatter.string(from: date) == normalized else { return nil }
        let calendar = Self.ageCalendar
        guard let months = calendar.dateComponents([.month], from: date, to: now).month,
              months >= 0, months <= 240 else { return nil }
        return months
    }
    var bodyAssessmentAgeLabel: String { bodyAssessmentAgeMonths.map { "\($0 / 12)岁\($0 % 12)个月" } ?? "待完善" }
    /// Date-only birthday semantics must be identical on device and server.
    /// Do not use the user's current timezone: a midnight boundary could move
    /// a child between two BMI reference months on different clients.
    private static let ageCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()
    private static let birthDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = ageCalendar
        f.timeZone = ageCalendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        return f
    }()
}

private enum BMIReference {
    /// (age months at interval start, overweight, obesity), WS/T 586—2018.
    static let boys: [(Int, Double, Double)] = [(72,16.4,17.7),(78,16.7,18.1),(84,17.0,18.7),(90,17.4,19.2),(96,17.8,19.7),(102,18.1,20.3),(108,18.5,20.8),(114,18.9,21.4),(120,19.2,21.9),(126,19.6,22.5),(132,19.9,23.0),(138,20.3,23.6),(144,20.7,24.1),(150,21.0,24.7),(156,21.4,25.2),(162,21.9,25.7),(168,22.3,26.1),(174,22.6,26.4),(180,22.9,26.6),(186,23.1,26.9),(192,23.3,27.1),(198,23.5,27.4),(204,23.7,27.6),(210,23.8,27.8),(216,24.0,28.0)]
    static let girls: [(Int, Double, Double)] = [(72,16.2,17.5),(78,16.5,18.0),(84,16.8,18.5),(90,17.2,19.0),(96,17.6,19.4),(102,18.1,19.9),(108,18.5,20.4),(114,19.0,21.0),(120,19.5,21.5),(126,20.0,22.1),(132,20.5,22.7),(138,21.1,23.3),(144,21.5,23.9),(150,21.9,24.5),(156,22.2,25.0),(162,22.6,25.6),(168,22.8,25.9),(174,23.0,26.3),(180,23.2,26.6),(186,23.4,26.9),(192,23.6,27.1),(198,23.7,27.4),(204,23.8,27.6),(210,23.9,27.8),(216,24.0,28.0)]
    static func threshold(ageMonths: Int, isBoy: Bool) -> (Double, Double) {
        let table = isBoy ? boys : girls
        // Use the completed lower half-year row from the published table.
        let bucket = (ageMonths / 6) * 6
        let row = table.first(where: { $0.0 == bucket }) ?? table.first!
        return (row.1, row.2)
    }
}

private enum HeightReference {
    struct Row { let minusTwoSD: Double; let minusOneSD: Double; let median: Double; let plusOneSD: Double; let plusTwoSD: Double }
    static let boys: [Int: Row] = [
        7: Row(minusTwoSD: 113.51, minusOneSD: 119.49, median: 125.48, plusOneSD: 131.47, plusTwoSD: 137.46),
        8: Row(minusTwoSD: 118.35, minusOneSD: 124.53, median: 130.72, plusOneSD: 136.90, plusTwoSD: 143.08),
        9: Row(minusTwoSD: 122.74, minusOneSD: 129.27, median: 135.81, plusOneSD: 142.35, plusTwoSD: 148.88),
        10: Row(minusTwoSD: 126.79, minusOneSD: 133.77, median: 140.76, plusOneSD: 147.75, plusTwoSD: 154.74),
        11: Row(minusTwoSD: 130.39, minusOneSD: 138.20, median: 146.01, plusOneSD: 153.82, plusTwoSD: 161.64),
        12: Row(minusTwoSD: 134.48, minusOneSD: 143.33, median: 152.18, plusOneSD: 161.03, plusTwoSD: 169.89),
        13: Row(minusTwoSD: 143.01, minusOneSD: 151.60, median: 160.19, plusOneSD: 168.78, plusTwoSD: 177.38),
        14: Row(minusTwoSD: 150.22, minusOneSD: 157.93, median: 165.63, plusOneSD: 173.34, plusTwoSD: 181.05),
        15: Row(minusTwoSD: 155.25, minusOneSD: 162.14, median: 169.02, plusOneSD: 175.91, plusTwoSD: 182.79),
        16: Row(minusTwoSD: 157.72, minusOneSD: 164.15, median: 170.58, plusOneSD: 177.01, plusTwoSD: 183.44),
        17: Row(minusTwoSD: 158.76, minusOneSD: 165.07, median: 171.39, plusOneSD: 177.70, plusTwoSD: 184.01),
        18: Row(minusTwoSD: 158.81, minusOneSD: 165.12, median: 171.42, plusOneSD: 177.73, plusTwoSD: 184.03)
    ]
    static let girls: [Int: Row] = [
        7: Row(minusTwoSD: 112.29, minusOneSD: 118.21, median: 124.13, plusOneSD: 130.05, plusTwoSD: 135.97),
        8: Row(minusTwoSD: 116.83, minusOneSD: 123.09, median: 129.34, plusOneSD: 135.59, plusTwoSD: 141.84),
        9: Row(minusTwoSD: 121.31, minusOneSD: 128.11, median: 134.91, plusOneSD: 141.71, plusTwoSD: 148.51),
        10: Row(minusTwoSD: 126.38, minusOneSD: 133.78, median: 141.18, plusOneSD: 148.57, plusTwoSD: 155.97),
        11: Row(minusTwoSD: 132.09, minusOneSD: 139.72, median: 147.36, plusOneSD: 154.99, plusTwoSD: 162.63),
        12: Row(minusTwoSD: 138.11, minusOneSD: 145.26, median: 152.41, plusOneSD: 159.56, plusTwoSD: 166.71),
        13: Row(minusTwoSD: 143.75, minusOneSD: 149.91, median: 156.07, plusOneSD: 162.23, plusTwoSD: 168.39),
        14: Row(minusTwoSD: 146.18, minusOneSD: 151.98, median: 157.78, plusOneSD: 163.58, plusTwoSD: 169.38),
        15: Row(minusTwoSD: 147.02, minusOneSD: 152.74, median: 158.47, plusOneSD: 164.19, plusTwoSD: 169.91),
        16: Row(minusTwoSD: 147.59, minusOneSD: 153.26, median: 158.93, plusOneSD: 164.60, plusTwoSD: 170.27),
        17: Row(minusTwoSD: 147.82, minusOneSD: 153.50, median: 159.18, plusOneSD: 164.86, plusTwoSD: 170.54),
        18: Row(minusTwoSD: 148.54, minusOneSD: 154.28, median: 160.01, plusOneSD: 165.74, plusTwoSD: 171.48)
    ]
    private static let safeBoyFallback = Row(minusTwoSD: 158.81, minusOneSD: 165.12, median: 171.42, plusOneSD: 177.73, plusTwoSD: 184.03)
    private static let safeGirlFallback = Row(minusTwoSD: 148.54, minusOneSD: 154.28, median: 160.01, plusOneSD: 165.74, plusTwoSD: 171.48)
    static func row(ageYears: Int, isBoy: Bool) -> Row {
        let table = isBoy ? boys : girls
        let safeFallback = isBoy ? safeBoyFallback : safeGirlFallback
        return table[ageYears] ?? table[18] ?? Array(table.values).last ?? safeFallback
    }
}
