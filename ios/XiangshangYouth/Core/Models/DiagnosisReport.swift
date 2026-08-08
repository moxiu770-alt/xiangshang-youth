import Foundation

struct DiagnosisReport: Identifiable, Codable {
    let id: String; let student: Student; let assessmentDate: String; let scores: [ScoreResult]
    let abilityTags: [String]; let riskAlerts: [String]; let trainingAdvice: [String]; let courseSuggestions: [CourseSuggestion]; let ruleVersion: String
    /// A report must carry the regional policy snapshot that was used when it
    /// was produced.  The backend will supply the authoritative record later;
    /// Mock keeps the same immutable contract for UI and audit testing.
    let regionPolicy: RegionPolicy
    var totalScore: Double { scores.reduce(0) { $0 + $1.score } }
}
