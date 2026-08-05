import Foundation

enum UserRole: String, CaseIterable, Identifiable, Codable, Equatable {
    case parent = "家长"
    case teacher = "教师"
    case principal = "校长"

    var id: String { rawValue }
    var icon: String {
        switch self { case .parent: "figure.2.and.child.holdinghands"; case .teacher: "person.text.rectangle"; case .principal: "building.2" }
    }
    var description: String {
        switch self { case .parent: "查看孩子测评与训练建议"; case .teacher: "组织测评、跟进班级进度"; case .principal: "掌握学校测评与风险情况" }
    }
}
