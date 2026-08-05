import Foundation
struct MessageApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func messages(userID: String) async throws -> [MessageItem] { throw ApiError.notConfigured }
    func markRead(messageID: String) async throws { throw ApiError.notConfigured }
}
