import Foundation

/// Backend replacement seam. Network endpoints are intentionally isolated from presentation code.
final class RemoteRepository: YouthRepository {
    private let statsApi: StatsApi
    private let reportApi: ReportApi
    private let workflowApi: WorkflowApi

    init(client: ApiClient = .shared) {
        self.statsApi = StatsApi(client: client)
        self.reportApi = ReportApi(client: client)
        self.workflowApi = WorkflowApi(client: client)
    }

    func loadDashboard() async throws -> DashboardData {
        try await statsApi.dashboard(schoolID: "school-1")
    }

    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }

    func loadReport(for student: Student) async throws -> DiagnosisReport {
        try await reportApi.report(studentID: student.id)
    }

    func submitActivity(_ value: ActivityRegistration) async throws { try await workflowApi.registerActivity(value) }
    func bookExpert(_ value: ExpertAppointment) async throws { try await workflowApi.bookExpert(value) }
    func uploadCourse(_ value: CourseUploadRecord) async throws { try await workflowApi.uploadCourse(value) }
    func updateTaskStatus(studentID: String, status: TaskStatus, note: String?) async throws { try await workflowApi.updateTaskStatus(studentID: studentID, status: status, note: note) }
    func publishClassPost(author: String, content: String) async throws { try await workflowApi.publishClassPost(author: author, content: content) }
    func sendSupportMessage(_ content: String) async throws { try await workflowApi.sendSupportMessage(content) }
}
