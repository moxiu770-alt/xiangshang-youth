import Foundation

struct Student: Identifiable, Codable, Hashable {
    let id: String; let name: String; let gender: String; let grade: String; let className: String
    let region: String; let isPovertyArea: Bool; let taskStatus: TaskStatus; let totalScore: Double?
}
