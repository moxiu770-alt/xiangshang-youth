import Foundation

enum PrivacyRequestType: String, Codable {
    case export
    case delete

    var actionTitle: String { self == .export ? "导出数据" : "删除/匿名化申请" }
}

struct PrivacyRequestReceipt: Decodable {
    let id: String
    let requestType: PrivacyRequestType
    let status: String
    let createdAt: String
    let jobID: String?

    enum CodingKeys: String, CodingKey {
        case id, requestType, status, createdAt, jobID = "jobId"
    }

    init(id: String, requestType: PrivacyRequestType, status: String, createdAt: String, jobID: String?) {
        self.id = id; self.requestType = requestType; self.status = status; self.createdAt = createdAt; self.jobID = jobID
    }
}

struct PrivacyApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }

    func submit(studentID: String, type: PrivacyRequestType) async throws -> PrivacyRequestReceipt {
        try await client.request(path: "v1/students/\(studentID)/privacy-requests", method: "POST", body: PrivacyRequestBody(requestType: type), type: PrivacyRequestReceipt.self)
    }
}

private struct PrivacyRequestBody: Encodable { let requestType: PrivacyRequestType }
