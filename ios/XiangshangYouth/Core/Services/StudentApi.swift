import Foundation
struct StudentApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func students(schoolID: String) async throws -> [Student] {
        try await client.request(path: "v1/schools/\(schoolID)/students", type: [Student].self)
    }
    func bindChild(studentID: String, bindingCode: String) async throws -> ParentChild {
        try await client.request(path: "v1/students/\(studentID)/bind", method: "POST", query: [URLQueryItem(name: "code", value: bindingCode)], type: ParentChild.self)
    }
}
