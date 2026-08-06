import Foundation
struct StatsApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func dashboard(schoolID: String) async throws -> DashboardData {
        try await client.request(path: "v1/schools/\(schoolID)/dashboard", type: DashboardData.self)
    }
    func gradeStats(schoolID: String) async throws -> [Grade] {
        try await client.request(path: "v1/schools/\(schoolID)/grade-stats", type: [Grade].self)
    }
    func classStats(schoolID: String, gradeID: String? = nil) async throws -> [ClassInfo] {
        let query = gradeID.map { [URLQueryItem(name: "gradeId", value: $0)] } ?? []
        return try await client.request(path: "v1/schools/\(schoolID)/class-stats", query: query, type: [ClassInfo].self)
    }
}
