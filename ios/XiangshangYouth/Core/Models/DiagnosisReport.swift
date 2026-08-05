import Foundation

struct DiagnosisReport: Identifiable, Codable {
    let id: String; let student: Student; let assessmentDate: String; let scores: [ScoreResult]
    let abilityTags: [String]; let riskAlerts: [String]; let trainingAdvice: [String]; let courseSuggestions: [CourseSuggestion]; let ruleVersion: String
    var totalScore: Double { scores.reduce(0) { $0 + $1.score } }
}
