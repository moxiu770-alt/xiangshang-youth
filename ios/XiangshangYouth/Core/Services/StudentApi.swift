import Foundation
struct StudentApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func students(schoolID: String) async throws -> [Student] { throw ApiError.notConfigured }
    func bindChild(studentID: String, bindingCode: String) async throws -> ParentChild { throw ApiError.notConfigured }
}
