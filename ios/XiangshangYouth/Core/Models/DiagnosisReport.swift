import Foundation

enum AssessmentRiskLevel: String, Codable {
    case low, attention, high, unavailable

    var label: String {
        switch self {
        case .low: "正常关注"
        case .attention: "建议关注"
        case .high: "重点跟进"
        case .unavailable: "待完成/待复核"
        }
    }
}

/// Central scoring policy for the seven school movement items. Scores coming
/// from the field device are still authoritative, but the app clamps and
/// explains malformed or incomplete data consistently on both platforms.
enum AssessmentScoreRules {
    static let modelRegistryVersion = "UY-MODELS-1.0"
    static let algorithmVersion = "UY-IMCA-SCORE-1.3"
    static let calibrationVersion = "UY-CAL-BASELINE-1.0"
    static let itemCount = TestItem.allCases.count
    static let itemMaximum = 5.0
    static let totalMaximum = Double(itemCount) * itemMaximum
    static let lowItemThreshold = 3.0
    static let attentionTotalThreshold = 25.0
    static let highTotalThreshold = 21.0
    static let reviewConfidenceThreshold = 0.80
    static let duplicateConflictThreshold = 1.5

    static func score(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(itemMaximum, max(0, floor(value * 10 + 0.5) / 10))
    }

    /// The API rounds the aggregate with the same non-bankers half-up rule as
    /// each item. Without this final normalization, binary floating-point
    /// sums such as 20.999999999 can cross the 21-point risk boundary on one
    /// client but not another.
    static func total(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(totalMaximum, max(0, floor(value * 10 + 0.5) / 10))
    }

    static func confidence(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

struct DiagnosisReport: Identifiable, Codable {
    let id: String; let student: Student; let assessmentDate: String; let scores: [ScoreResult]
    let abilityTags: [String]; let riskAlerts: [String]; let trainingAdvice: [String]; let courseSuggestions: [CourseSuggestion]; let ruleVersion: String
    /// A report must carry the regional policy snapshot that was used when it
    /// was produced.  The backend will supply the authoritative record later;
    /// Mock keeps the same immutable contract for UI and audit testing.
    let regionPolicy: RegionPolicy
    /// Version metadata is optional for reports generated before the audit
    /// contract was introduced; newly generated reports always carry it.
    var algorithmVersion: String? = AssessmentScoreRules.algorithmVersion
    var calibrationVersion: String? = AssessmentScoreRules.calibrationVersion
    var modelRegistryVersion: String? = AssessmentScoreRules.modelRegistryVersion

    /// Remote repositories must never render a bundled Mock report while an
    /// authoritative school report is still loading. This typed unavailable
    /// value keeps cards/layouts renderable without inventing scores.
    static func unavailable(for student: Student) -> DiagnosisReport {
        DiagnosisReport(id: "pending-\(student.id)", student: student, assessmentDate: "待学校服务返回", scores: [], abilityTags: [], riskAlerts: ["报告尚未从学校服务返回"], trainingAdvice: ["完成测评并等待学校发布报告"], courseSuggestions: [], ruleVersion: "pending", regionPolicy: RegionPolicy(id: "pending", region: student.region, povertyAreaLabel: student.isPovertyArea ? "重点帮扶地区" : nil, standardVersion: "待返回", effectiveDate: ""), algorithmVersion: nil, calibrationVersion: nil, modelRegistryVersion: nil)
    }
    var normalizedScores: [ScoreResult] {
        // A malformed sync payload can contain the same item twice. Keep the
        // strongest-evidence row so duplicates cannot inflate the total.
        TestItem.allCases.compactMap { item in
            scores.filter { $0.item == item }.max { lhs, rhs in
                let lhsConfidence = AssessmentScoreRules.confidence(lhs.confidence)
                let rhsConfidence = AssessmentScoreRules.confidence(rhs.confidence)
                if lhsConfidence != rhsConfidence { return lhsConfidence < rhsConfidence }
                // When evidence is tied, prefer the explicitly passed row;
                // it is the least surprising deterministic tie-breaker.
                return (lhs.reviewStatus == .passed ? 1 : 0) < (rhs.reviewStatus == .passed ? 1 : 0)
            }
        }.map { score in
            let normalizedConfidence = AssessmentScoreRules.confidence(score.confidence)
            let normalizedStatus: ScoreReviewStatus = !score.humanReviewed && normalizedConfidence < AssessmentScoreRules.reviewConfidenceThreshold ? .pendingReview : score.reviewStatus
            return ScoreResult(id: score.id, item: score.item, score: AssessmentScoreRules.score(score.score), note: score.note, confidence: normalizedConfidence, reviewStatus: normalizedStatus, humanReviewed: score.humanReviewed)
        }
    }

    var scoredItemCount: Int { Set(normalizedScores.map(\.item)).count }
    var scoreCompletionRatio: Double { Double(scoredItemCount) / Double(AssessmentScoreRules.itemCount) }
    var isComplete: Bool { TestItem.allCases.allSatisfy { item in normalizedScores.contains { $0.item == item } } }
    var totalScore: Double { AssessmentScoreRules.total(normalizedScores.reduce(0) { $0 + $1.score }) }
    var averageScore: Double { normalizedScores.isEmpty ? 0 : totalScore / Double(scoredItemCount) }
    var meanConfidence: Double { normalizedScores.isEmpty ? 0 : normalizedScores.map(\.confidence).reduce(0, +) / Double(normalizedScores.count) }
    var lowScoreItems: [ScoreResult] { normalizedScores.filter { $0.score < AssessmentScoreRules.lowItemThreshold } }
    var conflictingItems: [TestItem] {
        TestItem.allCases.filter { item in
            let values = scores.filter { $0.item == item }.map { AssessmentScoreRules.score($0.score) }
            guard values.count > 1, let minValue = values.min(), let maxValue = values.max() else { return false }
            return maxValue - minValue >= AssessmentScoreRules.duplicateConflictThreshold
        }
    }
    var reviewItems: [ScoreResult] { normalizedScores.filter { conflictingItems.contains($0.item) || $0.reviewStatus == .pendingReview || (!$0.humanReviewed && $0.confidence < AssessmentScoreRules.reviewConfidenceThreshold) } }
    var requiresReview: Bool { !isComplete || !reviewItems.isEmpty }
    var riskLevel: AssessmentRiskLevel {
        // A complete set of rows is not enough for a family-facing risk
        // label. Any low-confidence/pending row must be reviewed first;
        // otherwise a “low” label would look like a verified conclusion.
        guard isComplete, reviewItems.isEmpty else { return .unavailable }
        if totalScore < AssessmentScoreRules.highTotalThreshold || lowScoreItems.count >= 2 { return .high }
        if totalScore < AssessmentScoreRules.attentionTotalThreshold || !lowScoreItems.isEmpty { return .attention }
        return .low
    }
    var requiresFollowUp: Bool { riskLevel == .attention || riskLevel == .high || requiresReview }
}
