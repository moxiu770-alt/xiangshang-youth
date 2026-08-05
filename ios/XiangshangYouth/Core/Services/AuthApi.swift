import Foundation

/// Typed remote authentication contract. MockRepository remains the default;
/// this type only defines the seam used when the identity service is enabled.
struct AuthApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }

    func login(phone: String, verificationCode: String? = nil, password: String? = nil) async throws -> UserProfile {
        throw ApiError.notConfigured
    }

    func logout() async throws {
        client.token = nil
    }
}
