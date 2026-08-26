import Foundation

struct ProductEventInput: Encodable, Equatable {
    let eventID: UUID
    let eventName: String
    let coarseValue: String?
    let platform: String
    let appVersion: String
    let clientSessionID: UUID
    let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case eventName, coarseValue, platform, appVersion, occurredAt
        case eventID = "eventId"
        case clientSessionID = "clientSessionId"
    }
}

private struct ProductEventBatch: Encodable { let events: [ProductEventInput] }
private struct ProductEventReceipt: Decodable { let acceptedCount: Int; let duplicateCount: Int }

enum ProductEventApi {
    static func submit(_ events: [ProductEventInput]) async throws {
        guard !events.isEmpty else { return }
        _ = try await ApiClient.shared.request(
            path: "v1/mobile/events", method: "POST", body: ProductEventBatch(events: Array(events.prefix(20))),
            type: ProductEventReceipt.self, idempotencyKey: events.first?.eventID.uuidString
        )
    }
}
