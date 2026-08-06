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
