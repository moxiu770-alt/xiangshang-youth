import Foundation

/// Backend replacement seam. Network endpoints are intentionally isolated from presentation code.
final class RemoteRepository: YouthRepository {
    func loadDashboard() async throws -> DashboardData { throw ApiError.notConfigured }
    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }
}
