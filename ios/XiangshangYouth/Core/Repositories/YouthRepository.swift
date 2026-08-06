import Foundation

protocol YouthRepository {
    func loadDashboard() async throws -> DashboardData
    func report(for student: Student) -> DiagnosisReport
    /// Async report seam used by the detail route. Mock repositories inherit a
    /// deterministic fallback; RemoteRepository replaces it with ReportApi.
    func loadReport(for student: Student) async throws -> DiagnosisReport
}

extension YouthRepository {
    func loadReport(for student: Student) async throws -> DiagnosisReport {
        report(for: student)
    }
}
