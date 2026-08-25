import Foundation

enum UserRole: String, CaseIterable, Identifiable, Codable, Equatable {
    case parent = "家长"
    case teacher = "教师"
    case principal = "校长"

    /// Mobile workbenches. School management analytics are delivered by the
    /// backend dashboard rather than embedded in the parent/teacher app.
    static var mobileRoles: [UserRole] { [.parent, .teacher] }

    init?(backendCode: String?) {
        switch String(backendCode ?? "").lowercased() {
        case "parent", "家长": self = .parent
        case "teacher", "教师": self = .teacher
        case "principal", "校长": self = .principal
        default: return nil
        }
    }

    var id: String { rawValue }
    var backendCode: String {
        switch self { case .parent: "parent"; case .teacher: "teacher"; case .principal: "principal" }
    }
    var icon: String {
        switch self { case .parent: "figure.2.and.child.holdinghands"; case .teacher: "person.text.rectangle"; case .principal: "building.2" }
    }
    var description: String {
        switch self { case .parent: "查看孩子测评与训练建议"; case .teacher: "组织测评、跟进班级进度"; case .principal: "学校管理数据请在后台看板查看" }
    }
}
