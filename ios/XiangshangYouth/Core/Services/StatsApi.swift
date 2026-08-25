import Foundation
struct StatsApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func dashboard(schoolID: String, studentPage: Int? = nil, studentPageSize: Int? = nil) async throws -> DashboardData {
        var query: [URLQueryItem] = []
        if let studentPage { query.append(URLQueryItem(name: "studentPage", value: String(studentPage))) }
        if let studentPageSize { query.append(URLQueryItem(name: "studentPageSize", value: String(studentPageSize))) }
        return try await client.request(path: "v1/schools/\(schoolID)/dashboard", query: query, type: DashboardData.self)
    }
    func gradeStats(schoolID: String) async throws -> [Grade] {
        try await client.request(path: "v1/schools/\(schoolID)/grade-stats", type: [Grade].self)
    }
    func classStats(schoolID: String, gradeID: String? = nil) async throws -> [ClassInfo] {
        let query = gradeID.map { [URLQueryItem(name: "gradeId", value: $0)] } ?? []
        return try await client.request(path: "v1/schools/\(schoolID)/class-stats", query: query, type: [ClassInfo].self)
    }
    func teacherOverview(schoolID: String, classID: String, taskID: String, standardVersion: String) async throws -> TeacherAnalyticsOverview {
        try await client.request(path: "v1/teacher/analytics/overview", query: [URLQueryItem(name: "schoolId", value: schoolID), URLQueryItem(name: "classId", value: classID), URLQueryItem(name: "taskId", value: taskID), URLQueryItem(name: "standardVersion", value: standardVersion)], type: TeacherAnalyticsOverview.self)
    }
}

struct TeacherAnalyticsOverview: Decodable, Equatable {
    struct Item: Decodable, Equatable { let itemCode: String; let totalCount: Int; let measuredCount: Int; let completionRate: Int; let averageScore: Double; let riskCount: Int }
    let totalCount: Int; let completedCount: Int; let reviewCount: Int; let retestCount: Int; let absentCount: Int; let riskCount: Int; let lowScoreCount: Int
    let itemStats: [Item]; let dataAvailable: Bool
}
