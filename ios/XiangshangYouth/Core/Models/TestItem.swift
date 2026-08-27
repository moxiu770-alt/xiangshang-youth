import Foundation

enum TestItem: String, CaseIterable, Identifiable, Codable {
    case obstacleJump = "连续双脚障碍跳", lateralSlide = "侧向滑步", backwardBalance = "倒退平衡"
    case catchThrow = "接球-上手掷准", handDribble = "手运球绕杆", footDribble = "脚运球变向", spotKick = "定点踢准"
    var id: String { rawValue }
    var shortName: String { switch self { case .obstacleJump: "障碍跳"; case .lateralSlide: "侧滑步"; case .backwardBalance: "倒退平衡"; case .catchThrow: "接掷准"; case .handDribble: "手运球"; case .footDribble: "脚运球"; case .spotKick: "踢准" } }
    var icon: String { switch self { case .obstacleJump: "figure.jumprope"; case .lateralSlide: "arrow.left.and.right"; case .backwardBalance: "figure.walk"; case .catchThrow: "target"; case .handDribble: "basketball"; case .footDribble: "soccerball"; case .spotKick: "scope" } }
}
