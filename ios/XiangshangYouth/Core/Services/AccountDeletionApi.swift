import Foundation

struct AccountDeletionReceipt: Decodable {
    let id: String
    let status: String
    let createdAt: String
    let completedAt: String?
}

struct AccountDeletionApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }

    func submit() async throws -> AccountDeletionReceipt {
        try await client.request(path: "v1/me/deletion-request", method: "POST", body: EmptyBody(), type: AccountDeletionReceipt.self)
    }
}

private struct EmptyBody: Encodable {}
