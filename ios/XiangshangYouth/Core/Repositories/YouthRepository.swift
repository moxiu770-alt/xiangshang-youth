import Foundation

protocol YouthRepository {
    func loadDashboard() async throws -> DashboardData
    func report(for student: Student) -> DiagnosisReport
    /// Async report seam used by the detail route. Mock repositories inherit a
    /// deterministic fallback; RemoteRepository replaces it with ReportApi.
    func loadReport(for student: Student) async throws -> DiagnosisReport
    func submitActivity(_ value: ActivityRegistration) async throws
    func bookExpert(_ value: ExpertAppointment) async throws
    func uploadCourse(_ value: CourseUploadRecord) async throws
    func updateTaskStatus(studentID: String, status: TaskStatus, note: String?) async throws
    func publishClassPost(author: String, content: String) async throws
    func sendSupportMessage(_ content: String) async throws
}

extension YouthRepository {
    func loadReport(for student: Student) async throws -> DiagnosisReport {
        report(for: student)
    }

    func submitActivity(_ value: ActivityRegistration) async throws {}
    func bookExpert(_ value: ExpertAppointment) async throws {}
    func uploadCourse(_ value: CourseUploadRecord) async throws {}
    func updateTaskStatus(studentID: String, status: TaskStatus, note: String?) async throws {}
    func publishClassPost(author: String, content: String) async throws {}
    func sendSupportMessage(_ content: String) async throws {}
}
