import Foundation
struct StatsApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func dashboard(schoolID: String) async throws -> DashboardData { throw ApiError.notConfigured }
    func gradeStats(schoolID: String) async throws -> [Grade] { throw ApiError.notConfigured }
    func classStats(schoolID: String, gradeID: String? = nil) async throws -> [ClassInfo] { throw ApiError.notConfigured }
}
