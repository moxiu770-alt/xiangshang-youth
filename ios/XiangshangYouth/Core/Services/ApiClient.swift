import Foundation
import Security

enum ApiError: LocalizedError {
    case notConfigured
    case invalidResponse
    case unauthorized
    case network
    case cancelled
    case server(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "服务尚未配置"
        case .invalidResponse: "服务响应异常"
        case .unauthorized: "登录已过期，请重新登录"
        case .network: "网络连接异常，请检查网络后重试"
        case .cancelled: "操作已取消"
        case .server: "服务暂时不可用，请稍后重试"
        }
    }
}

final class ApiClient {
    static let shared = ApiClient()
    let baseURL: URL
    private let tokenStore = SecureTokenStore()
    private let session: URLSession
    var token: String? {
        didSet { tokenStore.write(token) }
    }

    init(baseURL: URL? = nil) {
        let configuredURL = baseURL
            ?? ProcessInfo.processInfo.environment["XS_API_BASE_URL"].flatMap(URL.init(string:))
            ?? URL(string: "https://api.example.com/")!
        self.baseURL = configuredURL
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
        self.token = tokenStore.read()
    }

    func makeRequest(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    func request<T: Decodable, Body: Encodable>(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Body?, type: T.Type) async throws -> T {
        let encodedBody = try body.map { try JSONEncoder().encode($0) }
        return try await request(makeRequest(path: path, method: method, query: query, body: encodedBody), type: type)
    }

    func request<T: Decodable>(path: String, method: String = "GET", query: [URLQueryItem] = [], type: T.Type) async throws -> T {
        try await request(makeRequest(path: path, method: method, query: query), type: type)
    }

    func send(path: String, method: String = "POST", query: [URLQueryItem] = [], body: Data? = nil) async throws {
        _ = try await perform(makeRequest(path: path, method: method, query: query, body: body))
    }

    func request<T: Decodable>(_ request: URLRequest, type: T.Type) async throws -> T {
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch is DecodingError {
            throw ApiError.invalidResponse
        }
    }

    private func perform(_ originalRequest: URLRequest) async throws -> Data {
        var request = originalRequest
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ApiError.invalidResponse }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                token = nil
                throw ApiError.unauthorized
            case 500...599:
                throw ApiError.server(statusCode: http.statusCode)
            default:
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
}

/// Keychain-backed token storage. UserDefaults continues to hold only local UI
/// drafts and mock interaction state; credentials never rely on that store.
private struct SecureTokenStore {
    private let service = Bundle.main.bundleIdentifier ?? "com.xiangshang.youth"
    private let account = "api-token"

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
}
