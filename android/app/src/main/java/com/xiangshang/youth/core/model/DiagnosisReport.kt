package com.xiangshang.youth.core.model
data class DiagnosisReport(
    val id: String,
    val student: Student,
    val date: String,
    val scores: List<ScoreResult>,
    val abilityTags: List<String>,
    val riskAlerts: List<String>,
    val trainingAdvice: List<String>,
    val courseSuggestions: List<CourseSuggestion>,
    val ruleVersion: String,
    /** Regional policy snapshot used for this report's scoring explanation. */
    val regionPolicy: RegionPolicy
) {
    val totalScore: Double get() = scores.sumOf { it.score }
}
