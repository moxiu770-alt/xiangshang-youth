import Foundation
struct AuthApi { func login(phone: String) async throws -> UserProfile { UserProfile(id: "p1", name: "王女士", phone: phone, role: .parent, schoolName: "向上实验小学", avatarInitials: "王") } }
