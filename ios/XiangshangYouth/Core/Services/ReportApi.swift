import Foundation
struct ReportApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func report(studentID: String) async throws -> DiagnosisReport { throw ApiError.notConfigured }
    func refresh(studentID: String) async throws -> DiagnosisReport { throw ApiError.notConfigured }
}
