package com.xiangshang.youth.core.model

import com.squareup.moshi.Json

enum class ScoreReviewStatus(val label: String) {
    @Json(name = "passed") Passed("已核验"),
    @Json(name = "pendingReview") PendingReview("待复核")
}

data class ScoreResult(
    val item: TestItem,
    val score: Double,
    val note: String,
    /** 场地端评分引擎可信度，低于阈值时进入教师复核流。 */
    val confidence: Double = 0.0,
    val reviewStatus: ScoreReviewStatus,
    /** Explicit teacher review can approve low-confidence evidence after inspection. */
    val humanReviewed: Boolean = false
) {
    val normalizedScore: Double get() = AssessmentScoreRules.score(score)
    val normalizedConfidence: Double get() = AssessmentScoreRules.confidence(confidence)
    /** Low-confidence evidence always remains in the review queue. */
    val normalizedReviewStatus: ScoreReviewStatus
        get() = if (!humanReviewed && normalizedConfidence < AssessmentScoreRules.reviewConfidenceThreshold) ScoreReviewStatus.PendingReview else reviewStatus
}
