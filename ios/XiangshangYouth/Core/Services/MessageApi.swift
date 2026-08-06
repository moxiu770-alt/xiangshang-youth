import Foundation
struct MessageApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func messages(userID: String) async throws -> [MessageItem] {
        try await client.request(path: "v1/users/\(userID)/messages", type: [MessageItem].self)
    }
    func markRead(messageID: String) async throws {
        try await client.send(path: "v1/messages/\(messageID)/read")
    }
}
