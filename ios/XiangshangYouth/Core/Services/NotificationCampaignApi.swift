import Foundation

struct NotificationCampaign: Codable, Identifiable {
    let notificationID: String
    let schoolID: String
    let senderTeacherID: String?
    let title: String
    let content: String
    let targetClassIDs: [String]
    let recipientScope: String
    let scheduledAt: String?
    let status: String
    let draftVersion: Int
    let sentAt: String?
    let failureReason: String?
    let idempotencyKey: String?
    let parentReceiptEnabled: Bool
    var id: String { notificationID }

    enum CodingKeys: String, CodingKey {
        case notificationID = "notificationId", schoolID = "schoolId", senderTeacherID = "senderTeacherId", title, content, targetClassIDs = "targetClassIds", recipientScope, scheduledAt, status, draftVersion, sentAt, failureReason, idempotencyKey, parentReceiptEnabled
    }
}

struct NotificationCampaignApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }

    func drafts(schoolID: String) async throws -> [NotificationCampaign] {
        try await client.request(path: "v1/classes/notifications/drafts", query: [URLQueryItem(name: "schoolId", value: schoolID)], type: [NotificationCampaign].self)
    }

    func detail(notificationID: String) async throws -> NotificationCampaignDetail {
        try await client.request(path: "v1/classes/notifications/\(notificationID)", type: NotificationCampaignDetail.self)
    }

    func createDraft(schoolID: String, classIDs: [String], title: String, content: String, recipientScope: String = "class", scheduledAt: String? = nil, parentReceiptEnabled: Bool = false, idempotencyKey: String? = nil) async throws -> NotificationCampaign {
        try await client.request(path: "v1/classes/notifications", method: "POST", body: NotificationCampaignRequest(schoolID: schoolID, classIDs: classIDs, title: title, content: content, status: "draft", recipientScope: recipientScope, scheduledAt: scheduledAt, parentReceiptEnabled: parentReceiptEnabled), type: NotificationCampaign.self, idempotencyKey: idempotencyKey)
    }

    func updateDraft(notificationID: String, schoolID: String, classIDs: [String], title: String, content: String, draftVersion: Int, recipientScope: String = "class", scheduledAt: String? = nil, parentReceiptEnabled: Bool = false, idempotencyKey: String? = nil) async throws -> NotificationCampaign {
        try await client.request(path: "v1/classes/notifications/\(notificationID)", method: "PUT", body: NotificationCampaignRequest(schoolID: schoolID, classIDs: classIDs, title: title, content: content, status: "draft", recipientScope: recipientScope, scheduledAt: scheduledAt, parentReceiptEnabled: parentReceiptEnabled, draftVersion: draftVersion), type: NotificationCampaign.self, idempotencyKey: idempotencyKey)
    }

    func sendDraft(notificationID: String) async throws -> NotificationCampaignReceipt {
        try await client.request(path: "v1/classes/notifications/\(notificationID)/send", method: "POST", body: EmptyNotificationRequest(), type: NotificationCampaignReceipt.self, idempotencyKey: "notification-send-\(notificationID)")
    }

    func retry(notificationID: String) async throws -> NotificationCampaignReceipt {
        try await client.request(path: "v1/classes/notifications/\(notificationID)/retry", method: "POST", body: EmptyNotificationRequest(), type: NotificationCampaignReceipt.self, idempotencyKey: "notification-retry-\(notificationID)")
    }

    func discard(notificationID: String) async throws {
        try await client.send(path: "v1/classes/notifications/\(notificationID)", method: "DELETE", idempotencyKey: "notification-discard-\(notificationID)")
    }

    func acknowledgeReceipt(notificationID: String) async throws -> NotificationReceiptAck {
        try await client.request(path: "v1/classes/notifications/\(notificationID)/receipt", method: "POST", body: EmptyNotificationRequest(), type: NotificationReceiptAck.self, idempotencyKey: "notification-receipt-\(notificationID)")
    }

    func send(schoolID: String, classID: String, title: String, content: String) async throws -> NotificationCampaignReceipt {
        try await client.request(path: "v1/classes/notifications", method: "POST", body: NotificationCampaignRequest(schoolID: schoolID, classIDs: [classID], title: title, content: content), type: NotificationCampaignReceipt.self)
    }
}

struct NotificationCampaignDetail: Decodable, Identifiable {
    let notificationID: String
    let schoolID: String
    let senderTeacherID: String?
    let title: String
    let content: String
    let targetClassIDs: [String]
    let recipientScope: String
    let status: String
    let draftVersion: Int
    let scheduledAt: String?
    let sentAt: String?
    let failureReason: String?
    let parentReceiptEnabled: Bool
    let userReceiptStatus: String?
    let acknowledgedAt: String?
    let receiptStats: NotificationReceiptStats?
    var id: String { notificationID }

    enum CodingKeys: String, CodingKey {
        case notificationID = "notificationId", schoolID = "schoolId", senderTeacherID = "senderTeacherId", title, content, targetClassIDs = "targetClassIds", recipientScope, status, draftVersion, scheduledAt, sentAt, failureReason, parentReceiptEnabled, userReceiptStatus, acknowledgedAt, receiptStats
    }
}

struct NotificationReceiptStats: Decodable {
    let pending: Int
    let acknowledged: Int
    let total: Int
}

struct NotificationReceiptAck: Decodable {
    let id: String?
    let notificationID: String
    let receiverUserID: String?
    let status: String
    let acknowledgedAt: String?
    let version: Int?

    enum CodingKeys: String, CodingKey { case id, status, acknowledgedAt, version; case notificationID = "notificationId"; case receiverUserID = "receiverUserId" }
}

struct NotificationCampaignRequest: Encodable {
    let schoolID: String
    let classID: String
    let title: String
    let content: String
    let status: String?
    let targetClassIDs: [String]
    let recipientScope: String
    let scheduledAt: String?
    let audienceType = "class"
    let channel = "in_app"
    let parentReceiptEnabled: Bool
    let draftVersion: Int?

    init(schoolID: String, classIDs: [String], title: String, content: String, status: String? = nil, recipientScope: String = "class", scheduledAt: String? = nil, parentReceiptEnabled: Bool = false, draftVersion: Int? = nil) {
        let normalized = Array(Set(classIDs.filter { !$0.isEmpty })).sorted()
        self.schoolID = schoolID
        self.classID = normalized.first ?? ""
        self.title = title
        self.content = content
        self.status = status
        self.targetClassIDs = normalized
        self.recipientScope = recipientScope
        self.scheduledAt = scheduledAt
        self.parentReceiptEnabled = parentReceiptEnabled
        self.draftVersion = draftVersion
    }
    enum CodingKeys: String, CodingKey { case schoolID = "schoolId"; case classID = "classId"; case title, content, status, targetClassIDs = "targetClassIds", recipientScope, scheduledAt, audienceType, channel, parentReceiptEnabled, draftVersion }
}

private struct EmptyNotificationRequest: Encodable {}

struct NotificationCampaignReceipt: Decodable {
    let id: String
    let title: String
    let status: String
    let sentCount: Int
    let failureReason: String?
    let draftVersion: Int?
    let scheduledAt: String?
    let parentReceiptEnabled: Bool?

    enum CodingKeys: String, CodingKey { case id, notificationID = "notificationId", title, status, sentCount, failureReason, draftVersion, scheduledAt, parentReceiptEnabled }
    init(id: String, title: String, status: String, sentCount: Int, failureReason: String? = nil, draftVersion: Int? = nil, scheduledAt: String? = nil, parentReceiptEnabled: Bool? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.sentCount = sentCount
        self.failureReason = failureReason
        self.draftVersion = draftVersion
        self.scheduledAt = scheduledAt
        self.parentReceiptEnabled = parentReceiptEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedID = try? container.decode(String.self, forKey: .id) {
            id = decodedID
        } else {
            id = try container.decode(String.self, forKey: .notificationID)
        }
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        status = (try? container.decode(String.self, forKey: .status)) ?? ""
        sentCount = (try? container.decode(Int.self, forKey: .sentCount)) ?? 0
        failureReason = try? container.decodeIfPresent(String.self, forKey: .failureReason)
        draftVersion = try? container.decodeIfPresent(Int.self, forKey: .draftVersion)
        scheduledAt = try? container.decodeIfPresent(String.self, forKey: .scheduledAt)
        parentReceiptEnabled = try? container.decodeIfPresent(Bool.self, forKey: .parentReceiptEnabled)
    }
}
