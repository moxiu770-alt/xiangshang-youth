import Foundation
import Security

enum ApiError: LocalizedError {
    case notConfigured
    case invalidResponse
    case unauthorized
    case forbidden
    case conflict(String)
    case network
    case cancelled
    case server(statusCode: Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "服务尚未配置"
        case .invalidResponse: "服务响应异常"
        case .unauthorized: "登录已过期，请重新登录"
        case .forbidden: "当前账号无权执行此操作"
        case let .conflict(message): message.isEmpty ? "记录已被其他人更新，请刷新后重试" : message
        case .network: "网络连接异常，请检查网络后重试"
        case .cancelled: "操作已取消"
        case .server: "服务暂时不可用，请稍后重试"
        case let .message(message): message
        }
    }
}

private struct ApiEnvelope<Value: Decodable>: Decodable {
    let code: String
    let message: String
    let data: Value?
}

private struct ApiFailureEnvelope: Decodable {
    let code: String
    let message: String
}

final class ApiClient {
    static let shared = ApiClient()
    let baseURL: URL
    private let tokenStore = SecureTokenStore()
    private let session: URLSession
    var token: String? {
        didSet { tokenStore.write(token) }
    }
    var refreshToken: String? {
        didSet { tokenStore.writeRefresh(refreshToken) }
    }

    init(baseURL: URL? = nil) {
        let configuredURL = baseURL
            ?? ProcessInfo.processInfo.environment["XS_API_BASE_URL"].flatMap(URL.init(string:))
            ?? (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://api.example.com/")!
        self.baseURL = configuredURL
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
        self.token = tokenStore.read()
        self.refreshToken = tokenStore.readRefresh()
    }

    func makeRequest(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, contentType: String? = "application/json", idempotencyKey: String? = nil) -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            // Paths are normally compile-time endpoint constants. If a future
            // server-driven link is malformed, return a harmless request that
            // will fail through the normal HTTP/error boundary instead of
            // crashing the app while constructing a request.
            return URLRequest(url: baseURL)
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { return URLRequest(url: baseURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil, let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if ["POST", "PUT", "PATCH", "DELETE"].contains(method) {
            request.setValue(idempotencyKey ?? UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        }
        return request
    }

    func request<T: Decodable, Body: Encodable>(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Body?, type: T.Type, idempotencyKey: String? = nil) async throws -> T {
        let encodedBody = try body.map { try JSONEncoder().encode($0) }
        return try await request(makeRequest(path: path, method: method, query: query, body: encodedBody, idempotencyKey: idempotencyKey), type: type)
    }

    func request<T: Decodable>(path: String, method: String = "GET", query: [URLQueryItem] = [], type: T.Type, idempotencyKey: String? = nil) async throws -> T {
        try await request(makeRequest(path: path, method: method, query: query, idempotencyKey: idempotencyKey), type: type)
    }

    func send(path: String, method: String = "POST", query: [URLQueryItem] = [], body: Data? = nil, idempotencyKey: String? = nil) async throws {
        _ = try await perform(makeRequest(path: path, method: method, query: query, body: body, idempotencyKey: idempotencyKey))
    }

    /// Encodes workflow command payloads at the transport boundary so feature
    /// views never need to know about JSON or HTTP details.
    func send<Body: Encodable>(path: String, method: String = "POST", query: [URLQueryItem] = [], body: Body, idempotencyKey: String? = nil) async throws {
        try await send(path: path, method: method, query: query, body: JSONEncoder().encode(body), idempotencyKey: idempotencyKey)
    }

    /// Downloads private binary content through the same authenticated and
    /// refresh-aware boundary as JSON requests. Callers must still render the
    /// returned bytes only after the server has authorized the object.
    func download(path: String) async throws -> Data {
        try await perform(makeRequest(path: path))
    }

    func setSession(accessToken: String, refreshToken: String?) {
        token = accessToken
        self.refreshToken = refreshToken
    }

    func clearSession() {
        token = nil
        refreshToken = nil
    }

    func request<T: Decodable>(_ request: URLRequest, type: T.Type) async throws -> T {
        let data = try await perform(request)
        let decoder = JSONDecoder()
        do {
            if let envelope = try? decoder.decode(ApiEnvelope<T>.self, from: data), let value = envelope.data {
                return value
            }
            return try decoder.decode(T.self, from: data)
        } catch is DecodingError {
            throw ApiError.invalidResponse
        }
    }

    private func perform(_ originalRequest: URLRequest, allowRefresh: Bool = true) async throws -> Data {
        var request = originalRequest
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ApiError.invalidResponse }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401 where allowRefresh:
                if try await refreshSession() { return try await perform(originalRequest, allowRefresh: false) }
                clearSession()
                throw ApiError.unauthorized
            case 401:
                clearSession()
                throw ApiError.unauthorized
            case 403:
                throw ApiError.forbidden
            case 500...599:
                throw ApiError.server(statusCode: http.statusCode)
            default:
                if let failure = try? JSONDecoder().decode(ApiFailureEnvelope.self, from: data) {
                    if failure.code == "VERSION_CONFLICT" { throw ApiError.conflict(failure.message) }
                    if !failure.message.isEmpty { throw ApiError.message(failure.message) }
                }
                throw ApiError.invalidResponse
            }
        } catch let error as ApiError {
            throw error
        } catch is CancellationError {
            throw ApiError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw ApiError.cancelled
        } catch is URLError {
            throw ApiError.network
        } catch {
            throw ApiError.network
        }
    }

    private func refreshSession() async throws -> Bool {
        let body = try JSONEncoder().encode(RefreshRequest(refreshToken: refreshToken))
        let request = makeRequest(path: "v1/auth/refresh", method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
        let payload = try JSONDecoder().decode(ApiEnvelope<RefreshPayload>.self, from: data)
        guard let value = payload.data else { return false }
        setSession(accessToken: value.accessToken, refreshToken: value.refreshToken)
        return true
    }
}

private struct RefreshRequest: Encodable { let refreshToken: String? }
private struct RefreshPayload: Decodable { let accessToken: String; let refreshToken: String? }

/// Keychain-backed token storage. Local workflow state uses a separate
/// device-only Keychain item; credentials never rely on UserDefaults.
private struct SecureTokenStore {
    private let service = Bundle.main.bundleIdentifier ?? "com.xiangshang.youth"
    private let account = "api-token"
    private let refreshAccount = "refresh-token"

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ token: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard let token, !token.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(token.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) != errSecSuccess {
            var add = query
            add.merge(attributes) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func readRefresh() -> String? { read(account: refreshAccount) }
    func writeRefresh(_ token: String?) { write(token, account: refreshAccount) }

    private func read(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ token: String?, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        guard let token, !token.isEmpty else { SecItemDelete(query as CFDictionary); return }
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) != errSecSuccess { var add = query; add.merge(attributes) { _, new in new }; SecItemAdd(add as CFDictionary, nil) }
    }
}
