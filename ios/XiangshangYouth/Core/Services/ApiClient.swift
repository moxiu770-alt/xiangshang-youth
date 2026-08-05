import Foundation

enum ApiError: LocalizedError {
    case notConfigured
    case invalidResponse
    case unauthorized
    case network
    case server(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "服务尚未配置"
        case .invalidResponse: "服务响应异常"
        case .unauthorized: "登录已过期，请重新登录"
        case .network: "网络连接异常，请检查网络后重试"
        case .server: "服务暂时不可用，请稍后重试"
        }
    }
}

final class ApiClient {
    static let shared = ApiClient(); private init() {}
    var token: String?
    func request<T: Decodable>(_ request: URLRequest, type: T.Type) async throws -> T {
        var request = request; if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ApiError.invalidResponse }
            switch http.statusCode {
            case 200..<300:
                return try JSONDecoder().decode(T.self, from: data)
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
        } catch is URLError {
            throw ApiError.network
        } catch is DecodingError {
            throw ApiError.invalidResponse
        } catch {
            throw ApiError.network
        }
    }
}
