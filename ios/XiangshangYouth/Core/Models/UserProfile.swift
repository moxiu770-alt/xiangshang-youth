import Foundation

struct UserProfile: Identifiable, Codable, Equatable { let id: String; let name: String; let phone: String; let role: UserRole; let schoolName: String; let avatarInitials: String }
