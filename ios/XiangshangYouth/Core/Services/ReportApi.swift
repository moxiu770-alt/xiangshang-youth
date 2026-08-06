import Foundation
struct ReportApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func report(studentID: String) async throws -> DiagnosisReport {
        try await client.request(path: "v1/students/\(studentID)/report", type: DiagnosisReport.self)
    }
    func refresh(studentID: String) async throws -> DiagnosisReport {
        try await client.request(path: "v1/students/\(studentID)/report/refresh", method: "POST", type: DiagnosisReport.self)
    }
}
