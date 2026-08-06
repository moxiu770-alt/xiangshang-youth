import Foundation

/// Typed remote authentication contract. MockRepository remains the default;
/// this type only defines the seam used when the identity service is enabled.
struct AuthApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }

    func login(phone: String, verificationCode: String? = nil, password: String? = nil) async throws -> UserProfile {
        try await client.request(
            path: "v1/auth/login",
            method: "POST",
            body: LoginRequest(account: phone, verificationCode: verificationCode, password: password),
            type: UserProfile.self
        )
    }

    func logout() async throws {
        client.token = nil
    }
}

private struct LoginRequest: Encodable {
    let account: String
    let verificationCode: String?
    let password: String?
}
