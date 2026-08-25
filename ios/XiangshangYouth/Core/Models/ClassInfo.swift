import Foundation

struct ClassInfo: Identifiable, Codable, Hashable {
    let id: String; let name: String; let gradeId: String; let teacherName: String; let studentCount: Int; let completionRate: Int
    /// Stable teacher identity returned by the school authorization service.
    /// `nil` is retained for decoding older fixtures; new data must provide it.
    let teacherID: String?

    init(id: String, name: String, gradeId: String, teacherName: String, studentCount: Int, completionRate: Int, teacherID: String? = nil) {
        self.id = id; self.name = name; self.gradeId = gradeId; self.teacherName = teacherName; self.studentCount = studentCount; self.completionRate = completionRate; self.teacherID = teacherID
    }
    var boundedCompletionRate: Int { min(100, max(0, completionRate)) }
    var completedStudentEstimate: Int { Int((Double(max(0, studentCount)) * Double(boundedCompletionRate) / 100).rounded()) }
}
