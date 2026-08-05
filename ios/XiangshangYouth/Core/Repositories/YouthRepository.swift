import Foundation

protocol YouthRepository { func loadDashboard() async throws -> DashboardData; func report(for student: Student) -> DiagnosisReport }
