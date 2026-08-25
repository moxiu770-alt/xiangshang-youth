import Foundation

enum ScoreReviewStatus: String, Codable {
    case passed
    case pendingReview

    var label: String { self == .passed ? "已核验" : "待复核" }
}

struct ScoreResult: Identifiable, Codable {
    let id: String
    let item: TestItem
    let score: Double
    let note: String
    /// 场地端评分引擎返回的可信度，用于提示老师是否需要复核证据。
    let confidence: Double
    let reviewStatus: ScoreReviewStatus
    /// Explicit teacher review is separate from machine confidence. A human
    /// can approve a low-confidence sample after inspecting the evidence.
    var humanReviewed: Bool = false

    private enum CodingKeys: String, CodingKey { case id, item, score, note, confidence, reviewStatus, humanReviewed }

    init(id: String, item: TestItem, score: Double, note: String, confidence: Double, reviewStatus: ScoreReviewStatus, humanReviewed: Bool = false) {
        self.id = id
        self.item = item
        self.score = score
        self.note = note
        self.confidence = confidence
        self.reviewStatus = reviewStatus
        self.humanReviewed = humanReviewed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        item = try container.decode(TestItem.self, forKey: .item)
        score = try container.decode(Double.self, forKey: .score)
        note = try container.decode(String.self, forKey: .note)
        // Older payloads may omit confidence. Missing evidence is reviewable,
        // never equivalent to a fully trusted score.
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        // Older/remote payloads may omit or introduce a status value. Keep the
        // row renderable but fail closed into the review queue instead of
        // dropping the whole report during Codable decoding.
        let rawReviewStatus = try container.decodeIfPresent(String.self, forKey: .reviewStatus)
        reviewStatus = rawReviewStatus.flatMap(ScoreReviewStatus.init(rawValue:)) ?? .pendingReview
        humanReviewed = try container.decodeIfPresent(Bool.self, forKey: .humanReviewed) ?? false
    }

    var normalizedScore: Double { AssessmentScoreRules.score(score) }
    var normalizedConfidence: Double { AssessmentScoreRules.confidence(confidence) }
    /// A low-confidence row is never treated as terminal just because an
    /// upstream payload labelled it passed. This keeps mobile rendering and
    /// the backend review queue consistent during endpoint rollout.
    var normalizedReviewStatus: ScoreReviewStatus {
        !humanReviewed && normalizedConfidence < AssessmentScoreRules.reviewConfidenceThreshold ? .pendingReview : reviewStatus
    }
}
