package com.xiangshang.youth.core.model

enum class AssessmentRiskLevel(val label: String) { Low("正常关注"), Attention("建议关注"), High("重点跟进"), Unavailable("待完成/待复核") }

/** Central scoring policy for the seven school movement items. */
object AssessmentScoreRules {
    const val modelRegistryVersion = "UY-MODELS-1.0"
    const val algorithmVersion = "UY-IMCA-SCORE-1.3"
    const val calibrationVersion = "UY-CAL-BASELINE-1.0"
    const val itemCount = 7
    const val itemMaximum = 5.0
    const val totalMaximum = itemCount * itemMaximum
    const val lowItemThreshold = 3.0
    const val attentionTotalThreshold = 25.0
    const val highTotalThreshold = 21.0
    const val reviewConfidenceThreshold = .80
    const val duplicateConflictThreshold = 1.5

    fun score(value: Double): Double = if (!value.isFinite()) 0.0 else (kotlin.math.floor(value.coerceIn(0.0, itemMaximum) * 10.0 + 0.5) / 10.0)
    fun confidence(value: Double): Double = if (!value.isFinite()) 0.0 else value.coerceIn(0.0, 1.0)
    /** Match the backend's final aggregate half-up normalization. */
    fun total(value: Double): Double = if (!value.isFinite()) 0.0 else (kotlin.math.floor(value.coerceIn(0.0, totalMaximum) * 10.0 + 0.5) / 10.0)
}
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
    val regionPolicy: RegionPolicy,
    /** New reports carry audit metadata; old payloads decode via defaults. */
    val algorithmVersion: String = AssessmentScoreRules.algorithmVersion,
    val calibrationVersion: String = AssessmentScoreRules.calibrationVersion,
    val modelRegistryVersion: String = AssessmentScoreRules.modelRegistryVersion
) {
    companion object {
        /** Never show a bundled Mock report while the school service is loading. */
        fun unavailable(student: Student): DiagnosisReport = DiagnosisReport(
            id = "pending-${student.id}", student = student, date = "待学校服务返回", scores = emptyList(),
            abilityTags = emptyList(), riskAlerts = listOf("报告尚未从学校服务返回"),
            trainingAdvice = listOf("完成测评并等待学校发布报告"), courseSuggestions = emptyList(),
            ruleVersion = "pending", regionPolicy = RegionPolicy("pending", student.region, if (student.isPovertyArea) "重点帮扶地区" else null, "待返回", ""),
            algorithmVersion = "", calibrationVersion = "", modelRegistryVersion = ""
        )
    }
    /** Keep the strongest-evidence row when a malformed payload duplicates an item. */
    val normalizedScores: List<ScoreResult> get() = TestItem.entries.mapNotNull { item ->
        scores.filter { it.item == item }
            .maxWithOrNull(compareBy<ScoreResult> { AssessmentScoreRules.confidence(it.confidence) }
                .thenBy { if (it.reviewStatus == ScoreReviewStatus.Passed) 1 else 0 })
            ?.let { score ->
                val normalizedConfidence = AssessmentScoreRules.confidence(score.confidence)
                score.copy(
                    score = AssessmentScoreRules.score(score.score),
                    confidence = normalizedConfidence,
                    reviewStatus = if (!score.humanReviewed && normalizedConfidence < AssessmentScoreRules.reviewConfidenceThreshold) ScoreReviewStatus.PendingReview else score.reviewStatus
                )
            }
    }
    val scoredItemCount: Int get() = normalizedScores.map { it.item }.toSet().size
    val scoreCompletionRatio: Double get() = scoredItemCount.toDouble() / AssessmentScoreRules.itemCount
    val isComplete: Boolean get() = TestItem.entries.all { item -> normalizedScores.any { it.item == item } }
    val totalScore: Double get() = AssessmentScoreRules.total(normalizedScores.sumOf { it.score })
    val averageScore: Double get() = if (scoredItemCount == 0) 0.0 else totalScore / scoredItemCount
    val meanConfidence: Double get() = if (normalizedScores.isEmpty()) 0.0 else normalizedScores.map { it.confidence }.average()
    val lowScoreItems: List<ScoreResult> get() = normalizedScores.filter { it.score < AssessmentScoreRules.lowItemThreshold }
    val conflictingItems: List<TestItem> get() = TestItem.entries.filter { item ->
        val values = scores.filter { it.item == item }.map { AssessmentScoreRules.score(it.score) }
        val maximum = values.maxOrNull()
        val minimum = values.minOrNull()
        values.size > 1 && maximum != null && minimum != null &&
            (maximum - minimum) >= AssessmentScoreRules.duplicateConflictThreshold
    }
    val reviewItems: List<ScoreResult> get() = normalizedScores.filter { conflictingItems.contains(it.item) || it.reviewStatus == ScoreReviewStatus.PendingReview || (!it.humanReviewed && it.confidence < AssessmentScoreRules.reviewConfidenceThreshold) }
    val requiresReview: Boolean get() = !isComplete || reviewItems.isNotEmpty()
    val riskLevel: AssessmentRiskLevel get() = when {
        !isComplete || reviewItems.isNotEmpty() -> AssessmentRiskLevel.Unavailable
        totalScore < AssessmentScoreRules.highTotalThreshold || lowScoreItems.size >= 2 -> AssessmentRiskLevel.High
        totalScore < AssessmentScoreRules.attentionTotalThreshold || lowScoreItems.isNotEmpty() -> AssessmentRiskLevel.Attention
        else -> AssessmentRiskLevel.Low
    }
    val requiresFollowUp: Boolean get() = riskLevel == AssessmentRiskLevel.Attention || riskLevel == AssessmentRiskLevel.High || requiresReview
}
