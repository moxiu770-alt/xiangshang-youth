package com.xiangshang.youth.core.model

enum class ScoreReviewStatus(val label: String) { Passed("已核验"), PendingReview("待复核") }

data class ScoreResult(
    val item: TestItem,
    val score: Double,
    val note: String,
    /** 场地端评分引擎可信度，低于阈值时进入教师复核流。 */
    val confidence: Double,
    val reviewStatus: ScoreReviewStatus
)
