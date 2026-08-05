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
}
