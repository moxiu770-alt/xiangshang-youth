package com.xiangshang.youth.core.model

enum class BodyScreeningRoute(val apiValue: String, val label: String, val detail: String) {
    AutoArchive("auto_archive", "已形成成长记录", "本次采集与模型发布门均已通过，结果已安全归档。"),
    RecaptureRequired("recapture_required", "需要重新采集", "部分动作、画面质量或两次记录一致性未达要求，请按提示重新采集。"),
    ProfessionalReview("professional_review", "等待专业复核", "采集记录已提交给有权限的学校专业人员；复核完成前不发布姿态风险结论。")
}

enum class BodyScreeningOutcomeLevel(val apiValue: String, val label: String) {
    CaptureInvalid("capture_invalid", "采集无效"),
    NoObviousAbnormality("no_obvious_abnormality", "未见明显异常"),
    TrainingObservation("training_observation", "训练并观察"),
    SchoolRetest("school_retest", "建议学校复测"),
    ProfessionalEvaluation("professional_evaluation", "建议专业评估")
}

data class BodyScreeningDecision(
    val sessionId: String? = null,
    val decisionId: String? = null,
    val route: BodyScreeningRoute,
    val reasonCodes: List<String> = emptyList(),
    val qualityScore: Int? = null,
    val reviewRequired: Boolean = false,
    val decisionPolicyVersion: String,
    val version: Int? = null,
    val decidedAt: String? = null,
    val reviewStatus: String? = null,
    val reviewDecision: BodyScreeningReviewDecision? = null,
    val reviewComment: String? = null,
    val requestedRecaptureTasks: List<String>? = null,
    val reviewVersion: Int? = null,
    val reviewedAt: String? = null,
    val outcomeLevel: BodyScreeningOutcomeLevel? = null
)

enum class BodyScreeningReviewDecision(val apiValue: String, val label: String) {
    Archive("archive", "归入成长档案"),
    ContinueObservation("continue_observation", "继续家庭观察"),
    ReferForProfessionalAssessment("refer_for_professional_assessment", "建议专业评估"),
    Recapture("recapture", "要求重新采集")
}

data class BodyScreeningReviewAttempt(
    val captureTask: String,
    val attemptCount: Int,
    val sampleCount: Int,
    val confidence: Double,
    val qualityScore: Int? = null,
    val qualityEvents: List<String> = emptyList(),
    val repeatabilityDifference: Double? = null,
    val capturedAt: String? = null,
    val evidenceMetrics: List<BodyScreeningEvidenceMetric> = emptyList()
)

data class BodyScreeningEvidenceMetric(
    val code: String,
    val label: String,
    val numericValue: Double? = null,
    val textValue: String? = null,
    val unit: String? = null,
    val source: String
) {
    val displayedValue: String get() = textValue?.takeIf(String::isNotBlank)
        ?: numericValue?.let { value -> "${"%.2f".format(value).trimEnd('0').trimEnd('.')}${unit?.let { " $it" }.orEmpty()}" }
        ?: "未提供"
    val sourceTitle: String get() = when (source) {
        "camera_proxy" -> "摄像头投影参考"
        "guardian_observation" -> "家长结构化观察"
        "instrument" -> "专业仪器测量"
        else -> "结构化采集记录"
    }
}

data class BodyScreeningReviewItem(
    val reviewId: String,
    val sessionId: String,
    val status: String,
    val version: Int,
    val createdAt: String? = null,
    val studentId: String,
    val classId: String? = null,
    val studentDisplayName: String,
    val route: String,
    val reasonCodes: List<String> = emptyList(),
    val qualityScore: Int? = null,
    val modelConfidence: Double? = null,
    val modelUncertainty: Double? = null,
    val decidedAt: String? = null,
    val protocolVersion: String? = null,
    val modelVersion: String? = null,
    val thresholdVersion: String? = null,
    val measuredAt: String? = null,
    val attempts: List<BodyScreeningReviewAttempt> = emptyList()
)

data class BodyScreeningReviewAck(
    val reviewId: String,
    val sessionId: String,
    val status: String,
    val decision: String? = null,
    val comment: String? = null,
    val requestedRecaptureTasks: List<String> = emptyList(),
    val version: Int,
    val reviewedAt: String? = null
)
