import Foundation

enum BodyScreeningRoute: String, Codable {
    case autoArchive = "auto_archive"
    case recaptureRequired = "recapture_required"
    case professionalReview = "professional_review"

    var label: String {
        switch self {
        case .autoArchive: "已形成成长记录"
        case .recaptureRequired: "需要重新采集"
        case .professionalReview: "等待专业复核"
        }
    }

    var detail: String {
        switch self {
        case .autoArchive: "本次采集与模型发布门均已通过，结果已安全归档。"
        case .recaptureRequired: "部分动作、画面质量或两次记录一致性未达要求，请按提示重新采集。"
        case .professionalReview: "采集记录已提交给有权限的学校专业人员；复核完成前不发布姿态风险结论。"
        }
    }
}

enum BodyScreeningOutcomeLevel: String, Codable {
    case captureInvalid = "capture_invalid"
    case noObviousAbnormality = "no_obvious_abnormality"
    case trainingObservation = "training_observation"
    case schoolRetest = "school_retest"
    case professionalEvaluation = "professional_evaluation"

    var label: String {
        switch self {
        case .captureInvalid: "采集无效"
        case .noObviousAbnormality: "未见明显异常"
        case .trainingObservation: "训练并观察"
        case .schoolRetest: "建议学校复测"
        case .professionalEvaluation: "建议专业评估"
        }
    }
}

struct BodyScreeningDecision: Codable, Equatable {
    let sessionId: String?
    let decisionId: String?
    let route: BodyScreeningRoute
    let outcomeLevel: BodyScreeningOutcomeLevel?
    let reasonCodes: [String]
    let qualityScore: Int?
    let reviewRequired: Bool
    let decisionPolicyVersion: String
    let version: Int?
    let decidedAt: Date?
    let reviewStatus: String?
    let reviewDecision: BodyScreeningReviewDecision?
    let reviewComment: String?
    let requestedRecaptureTasks: [String]?
    let reviewVersion: Int?
    let reviewedAt: Date?

    init(sessionId: String?, decisionId: String?, route: BodyScreeningRoute, outcomeLevel: BodyScreeningOutcomeLevel? = nil, reasonCodes: [String], qualityScore: Int?, reviewRequired: Bool, decisionPolicyVersion: String, version: Int?, decidedAt: Date?, reviewStatus: String? = nil, reviewDecision: BodyScreeningReviewDecision? = nil, reviewComment: String? = nil, requestedRecaptureTasks: [String]? = nil, reviewVersion: Int? = nil, reviewedAt: Date? = nil) {
        self.sessionId = sessionId
        self.decisionId = decisionId
        self.route = route
        self.outcomeLevel = outcomeLevel
        self.reasonCodes = reasonCodes
        self.qualityScore = qualityScore
        self.reviewRequired = reviewRequired
        self.decisionPolicyVersion = decisionPolicyVersion
        self.version = version
        self.decidedAt = decidedAt
        self.reviewStatus = reviewStatus
        self.reviewDecision = reviewDecision
        self.reviewComment = reviewComment
        self.requestedRecaptureTasks = requestedRecaptureTasks
        self.reviewVersion = reviewVersion
        self.reviewedAt = reviewedAt
    }
}

enum BodyScreeningReviewDecision: String, Codable, CaseIterable, Identifiable {
    case archive
    case continueObservation = "continue_observation"
    case referForProfessionalAssessment = "refer_for_professional_assessment"
    case recapture

    var id: String { rawValue }
    var title: String {
        switch self {
        case .archive: "归入成长档案"
        case .continueObservation: "继续家庭观察"
        case .referForProfessionalAssessment: "建议专业评估"
        case .recapture: "要求重新采集"
        }
    }
}

struct BodyScreeningReviewAttempt: Codable, Equatable, Identifiable {
    let captureTask: String
    let attemptCount: Int
    let sampleCount: Int
    let confidence: Double
    let qualityScore: Int?
    let qualityEvents: [String]
    let repeatabilityDifference: Double?
    let capturedAt: Date?
    let evidenceMetrics: [BodyScreeningEvidenceMetric]?
    var id: String { captureTask }
}

struct BodyScreeningEvidenceMetric: Codable, Equatable, Identifiable {
    let code: String
    let label: String
    let numericValue: Double?
    let textValue: String?
    let unit: String?
    let source: String
    var id: String { code }

    var displayedValue: String {
        if let textValue, !textValue.isEmpty { return textValue }
        guard let numericValue else { return "未提供" }
        let formatted = numericValue.formatted(.number.precision(.fractionLength(0...2)))
        return unit.map { "\(formatted) \($0)" } ?? formatted
    }

    var sourceTitle: String {
        switch source {
        case "camera_proxy": "摄像头投影参考"
        case "guardian_observation": "家长结构化观察"
        case "instrument": "专业仪器测量"
        default: "结构化采集记录"
        }
    }
}

struct BodyScreeningReviewItem: Codable, Equatable, Identifiable {
    let reviewId: String
    let sessionId: String
    let status: String
    let version: Int
    let createdAt: Date?
    let studentId: String
    let classId: String?
    let studentDisplayName: String
    let route: String
    let reasonCodes: [String]
    let qualityScore: Int?
    let modelConfidence: Double?
    let modelUncertainty: Double?
    let decidedAt: Date?
    let protocolVersion: String?
    let modelVersion: String?
    let thresholdVersion: String?
    let measuredAt: Date?
    let attempts: [BodyScreeningReviewAttempt]
    var id: String { reviewId }
}

struct BodyScreeningReviewAck: Codable, Equatable {
    let reviewId: String
    let sessionId: String
    let status: String
    let decision: String?
    let comment: String?
    let requestedRecaptureTasks: [String]
    let version: Int
    let reviewedAt: Date?
}
