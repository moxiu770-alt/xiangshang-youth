import Foundation
struct TaskApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func tasks(schoolID: String, gradeID: String? = nil, classID: String? = nil) async throws -> [TestTask] { throw ApiError.notConfigured }
    func updateStatus(taskID: String, studentID: String, status: TaskStatus) async throws { throw ApiError.notConfigured }
}
