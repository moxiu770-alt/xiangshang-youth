import Foundation

struct CourseApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func courses(childID: String) async throws -> [RemoteLesson] { try await client.request(path: "v1/students/\(childID)/courses", type: [RemoteLesson].self) }
    func playback(lessonID: String) async throws -> PlaybackSource { try await client.request(path: "v1/lessons/\(lessonID)/playback", type: PlaybackSource.self) }
    func saveProgress(childID: String, lessonID: String, lastPositionMs: Int, completed: Bool, expectedVersion: Int?) async throws -> LessonProgressAck {
        try await client.request(path: "v1/students/\(childID)/lessons/\(lessonID)/progress", method: "PUT", body: LessonProgressWrite(lastPositionMs: lastPositionMs, completed: completed, expectedVersion: expectedVersion), type: LessonProgressAck.self)
    }
}
struct RemoteLesson: Decodable { let courseID: String; let moduleID: String?; let lessonID: String; let title: String; let lessonTitle: String; let durationMs: Int; let videoSource: String?; let lastPositionMs: Int; let completed: Bool; let version: Int; enum CodingKeys: String, CodingKey { case title, lessonTitle, durationMs, videoSource, lastPositionMs, completed, version; case courseID = "courseId"; case moduleID = "moduleId"; case lessonID = "lessonId" } }
extension RemoteLesson: Identifiable { var id: String { lessonID } }
struct CaptionTrack: Decodable { let url: String?; let uri: String?; let language: String?; let label: String?; let mimeType: String? }
struct PlaybackSource: Decodable { let lessonID: String; let courseID: String; let videoSource: String; let durationMs: Int; let captions: [CaptionTrack]?; let playbackSessionID: String?; let expiresAt: String?; let refreshAfterSeconds: Int?; enum CodingKeys: String, CodingKey { case videoSource, durationMs, captions, expiresAt, refreshAfterSeconds; case lessonID = "lessonId"; case courseID = "courseId"; case playbackSessionID = "playbackSessionId" } }
private struct LessonProgressWrite: Encodable { let lastPositionMs: Int; let completed: Bool; let expectedVersion: Int? }
struct LessonProgressAck: Decodable { let lessonID: String; let lastPositionMs: Int; let completed: Bool; let version: Int; enum CodingKeys: String, CodingKey { case lastPositionMs, completed, version; case lessonID = "lessonId" } }
