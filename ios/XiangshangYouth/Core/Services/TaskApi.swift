import Foundation
struct TaskApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func tasks(schoolID: String, gradeID: String? = nil, classID: String? = nil) async throws -> [TestTask] {
        let query = [
            gradeID.map { URLQueryItem(name: "gradeId", value: $0) },
            classID.map { URLQueryItem(name: "classId", value: $0) }
        ].compactMap { $0 }
        return try await client.request(path: "v1/schools/\(schoolID)/tasks", query: query, type: [TestTask].self)
    }
    func updateStatus(taskID: String, studentID: String, status: TaskStatus) async throws {
        let body = try JSONEncoder().encode(TaskStatusRequest(status: status))
        try await client.send(path: "v1/tasks/\(taskID)/students/\(studentID)/status", method: "PATCH", body: body)
    }
}

private struct TaskStatusRequest: Encodable { let status: TaskStatus }

/// Write-side API seam for local-first workflows. The MockRepository uses the
/// default no-op implementations on YouthRepository; RemoteRepository can be
/// enabled later without changing form or navigation code.
struct WorkflowApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }

    func registerActivity(_ value: ActivityRegistration) async throws {
        try await client.send(path: "v1/activities/\(value.activityID)/registrations", body: ActivityRegistrationRequest(contactName: value.contactName, phone: value.phone))
    }

    func bookExpert(_ value: ExpertAppointment) async throws {
        try await client.send(path: "v1/expert-appointments", body: ExpertAppointmentRequest(expertName: value.expertName, preferredDate: value.preferredDate, note: value.note))
    }

    func uploadCourse(_ value: CourseUploadRecord) async throws {
        try await client.send(path: "v1/courses/uploads", body: CourseUploadRequest(taskID: value.taskID, attendanceCount: value.attendanceCount, notes: value.notes, attachmentName: value.attachmentName))
    }

    func updateTaskStatus(studentID: String, status: TaskStatus, note: String?) async throws {
        try await client.send(path: "v1/students/\(studentID)/task-status", method: "PATCH", body: WorkflowTaskStatusRequest(status: status, note: note))
    }

    func publishClassPost(author: String, content: String) async throws {
        try await client.send(path: "v1/class-posts", body: ClassPostRequest(author: author, content: content))
    }

    func sendSupportMessage(_ content: String) async throws {
        try await client.send(path: "v1/support/messages", body: SupportMessageRequest(content: content))
    }
}

private struct ActivityRegistrationRequest: Encodable { let contactName: String; let phone: String }
private struct ExpertAppointmentRequest: Encodable { let expertName: String; let preferredDate: String; let note: String }
private struct CourseUploadRequest: Encodable { let taskID: String; let attendanceCount: Int; let notes: String; let attachmentName: String }
private struct WorkflowTaskStatusRequest: Encodable { let status: TaskStatus; let note: String? }
private struct ClassPostRequest: Encodable { let author: String; let content: String }
private struct SupportMessageRequest: Encodable { let content: String }
