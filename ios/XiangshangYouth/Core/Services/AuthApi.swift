import Foundation

/// Typed remote authentication contract shared by login and session restore.
struct AuthApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }

    func login(phone: String, verificationCode: String? = nil, password: String? = nil) async throws -> AuthenticatedSession {
        let payload: BackendAuthPayload = try await client.request(
            path: "v1/auth/login",
            method: "POST",
            body: LoginRequest(account: phone, verificationCode: verificationCode, password: password),
            type: BackendAuthPayload.self
        )
        return try makeSession(from: payload)
    }

    func register(name: String, phone: String, verificationCode: String, password: String, role: UserRole) async throws -> AuthenticatedSession {
        let payload: BackendAuthPayload = try await client.request(
            path: "v1/auth/register",
            method: "POST",
            body: RegisterRequest(name: name, phone: phone, verificationCode: verificationCode, password: password, roleCode: role.backendCode),
            type: BackendAuthPayload.self
        )
        return try makeSession(from: payload)
    }

    func resetPassword(phone: String, verificationCode: String, password: String) async throws {
        try await client.send(path: "v1/auth/reset-password", method: "POST", body: ResetPasswordRequest(phone: phone, verificationCode: verificationCode, newPassword: password))
    }

    func sendVerificationCode(account: String, purpose: String) async throws {
        try await client.send(path: "v1/auth/verification-codes", method: "POST", body: VerificationCodeRequest(account: account, purpose: purpose))
    }

    /// Starts a server-owned WeChat OAuth flow. The returned state is short
    /// lived and single use; the native layer opens authorizeURL and passes the
    /// callback code/state back to exchangeWechat(code:state:).
    func startWechatAuthorization() async throws -> WechatAuthorizationStart {
        try await client.request(path: "v1/auth/oauth/wechat/start", method: "POST", type: WechatAuthorizationStart.self)
    }

    func exchangeWechat(code: String, state: String) async throws -> AuthenticatedSession {
        let payload: BackendAuthPayload = try await client.request(
            path: "v1/auth/oauth/wechat/exchange",
            method: "POST",
            body: WechatExchangeRequest(code: code, state: state),
            type: BackendAuthPayload.self
        )
        return try makeSession(from: payload)
    }

    /// Revalidates persisted credentials and refreshes server-owned claims on
    /// launch. Native clients must never recreate classes or permissions from
    /// bundled fixtures when this request succeeds.
    func currentSession() async throws -> AuthenticatedSession {
        let payload: BackendSessionClaims = try await client.request(path: "v1/auth/session", type: BackendSessionClaims.self)
        return try makeSession(user: payload.user, roles: payload.accountRoles ?? payload.roles)
    }

    private func makeSession(from payload: BackendAuthPayload) throws -> AuthenticatedSession {
        client.setSession(accessToken: payload.accessToken, refreshToken: payload.refreshToken)
        return try makeSession(user: payload.user, roles: payload.accountRoles ?? payload.roles)
    }

    private func makeSession(user: BackendUser, roles backendRoles: [BackendRole]) throws -> AuthenticatedSession {
        let roles = backendRoles.compactMap { UserRole(backendCode: $0.code) }
        guard let role = UserRole(backendCode: user.roleCode) ?? UserRole(backendCode: user.role) else {
            throw ApiError.invalidResponse
        }
        let roleClassIDs = backendRoles.flatMap { $0.classIDs ?? [$0.classID].compactMap { $0 } }
        let authorizedClassIDs = user.authorizedClassIDs ?? roleClassIDs
        let profile = UserProfile(id: user.id, name: user.name, phone: user.phone,
                                  role: role, schoolName: user.schoolName,
                                  avatarInitials: user.avatarInitials ?? String(user.name.prefix(1)),
                                  roleCode: user.roleCode, schoolID: user.schoolID,
                                  availableRoles: roles.isEmpty ? [role] : roles,
                                  authorizedClassIDs: authorizedClassIDs,
                                  capabilities: user.capabilities ?? backendRoles.flatMap { $0.capabilities ?? [] })
        return AuthenticatedSession(profile: profile, roles: roles.isEmpty ? [role] : roles)
    }

    func logout() async throws {
        defer { client.clearSession() }
        guard client.token != nil else { return }
        try await client.send(path: "v1/auth/logout", method: "POST")
    }
}

struct AuthenticatedSession {
    let profile: UserProfile
    let roles: [UserRole]
}

struct WechatAuthorizationStart: Decodable {
    let state: String
    let expiresAt: String
    let authorizeUrl: URL
}

private struct BackendAuthPayload: Decodable {
    let accessToken: String
    let refreshToken: String?
    let user: BackendUser
    let roles: [BackendRole]
    let accountRoles: [BackendRole]?
}

private struct BackendSessionClaims: Decodable {
    let user: BackendUser
    let roles: [BackendRole]
    let accountRoles: [BackendRole]?
}

private struct BackendRole: Decodable {
    let code: String
    let classID: String?
    let classIDs: [String]?
    let capabilities: [String]?

    enum CodingKeys: String, CodingKey {
        case code, capabilities
        case classID = "classId"
        case classIDs = "classIds"
    }
}

private struct BackendUser: Decodable {
    let id: String
    let name: String
    let phone: String
    let role: String
    let roleCode: String?
    let schoolID: String?
    let schoolName: String
    let avatarInitials: String?
    let authorizedClassIDs: [String]?
    let capabilities: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, phone, role, roleCode, schoolName, avatarInitials, capabilities
        case schoolID = "schoolId"
        case authorizedClassIDs = "authorizedClassIds"
    }
}

private struct LoginRequest: Encodable {
    let account: String
    let verificationCode: String?
    let password: String?
}

private struct RegisterRequest: Encodable {
    let name: String
    let phone: String
    let verificationCode: String
    let password: String
    let roleCode: String
}

private struct ResetPasswordRequest: Encodable {
    let phone: String
    let verificationCode: String
    let newPassword: String
}

private struct VerificationCodeRequest: Encodable {
    let account: String
    let purpose: String
}

private struct WechatExchangeRequest: Encodable {
    let code: String
    let state: String
}
