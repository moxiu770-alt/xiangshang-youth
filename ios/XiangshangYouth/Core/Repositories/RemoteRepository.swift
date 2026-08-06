import Foundation

/// Backend replacement seam. Network endpoints are intentionally isolated from presentation code.
final class RemoteRepository: YouthRepository {
    private let statsApi: StatsApi

    init(client: ApiClient = .shared) {
        self.statsApi = StatsApi(client: client)
    }

    func loadDashboard() async throws -> DashboardData {
        try await statsApi.dashboard(schoolID: "school-1")
    }

    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }
}
