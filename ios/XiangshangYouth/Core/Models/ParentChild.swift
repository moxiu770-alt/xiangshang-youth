import Foundation

struct ParentChild: Identifiable, Codable { let id: String; let parentId: String; let student: Student; let relation: String }
