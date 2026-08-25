import Foundation

struct UserProfile: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let phone: String
    let role: UserRole
    let schoolName: String
    let avatarInitials: String
    /// Authorization claims returned by the backend. They are optional so
    /// existing local fixtures remain source-compatible during migration.
    let roleCode: String?
    let schoolID: String?
    let availableRoles: [UserRole]
    /// Stable authorization claims. Display names are presentation-only and
    /// must never be used to decide which classes a teacher can access.
    let authorizedClassIDs: [String]
    let capabilities: [String]

    init(id: String, name: String, phone: String, role: UserRole, schoolName: String, avatarInitials: String, roleCode: String? = nil, schoolID: String? = nil, availableRoles: [UserRole] = [], authorizedClassIDs: [String] = [], capabilities: [String] = []) {
        self.id = id
        self.name = name
        self.phone = phone
        self.role = role
        self.schoolName = schoolName
        self.avatarInitials = avatarInitials
        self.roleCode = roleCode
        self.schoolID = schoolID
        self.availableRoles = availableRoles.isEmpty ? [role] : availableRoles
        self.authorizedClassIDs = authorizedClassIDs
        self.capabilities = capabilities
    }
}
