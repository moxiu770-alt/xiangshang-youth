import Foundation

struct ClassInfo: Identifiable, Codable, Hashable { let id: String; let name: String; let gradeId: String; let teacherName: String; let studentCount: Int; let completionRate: Int }
