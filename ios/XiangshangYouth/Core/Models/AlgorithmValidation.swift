import Foundation

/// A model may only publish user-facing classifications after an independent,
/// human-labelled evaluation has been approved for the exact frozen version.
/// The production default is deliberately fail-closed.
enum AlgorithmValidationStatus: String, Codable, Equatable {
    case pendingHumanValidation = "pending-human-validation"
    case humanValidated = "human-validated"

    var allowsClassification: Bool { self == .humanValidated }

    var userFacingLabel: String {
        switch self {
        case .pendingHumanValidation: "研发验证中"
        case .humanValidated: "已完成人工验证"
        }
    }
}

enum AlgorithmReleaseGate {
    static let posture: AlgorithmValidationStatus = .pendingHumanValidation
    static let followAlong: AlgorithmValidationStatus = .pendingHumanValidation

    static let pendingPostureNotice = "手机姿态算法尚未完成人工标注验证。本次仅保存取景与姿态观察记录，不生成风险等级或健康结论。"
    static let pendingFollowAlongNotice = "动作识别仍在人工标注验证阶段，辅助计次和动作提示可能有误差。训练是否完成以家长确认为准。"
}
