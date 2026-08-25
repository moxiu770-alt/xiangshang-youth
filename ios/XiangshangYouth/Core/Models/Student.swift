import Foundation

struct Student: Identifiable, Codable, Hashable {
    let id: String; let name: String; let gender: String; let grade: String; let className: String
    /// Stable class scope. `className` is display-only and must not be used for
    /// authorization or teacher roster filtering.
    let classID: String?
    let region: String; let isPovertyArea: Bool; let taskStatus: TaskStatus; let totalScore: Double?
    /// Monotonic server-side task row version used to prevent concurrent
    /// teacher updates from silently overwriting each other.
    let taskVersion: Int?
    /// ISO-8601 calendar date.  A real birthday, rather than grade, is required
    /// for the age/sex BMI reference calculation.
    let birthDate: String?

    enum CodingKeys: String, CodingKey { case id, name, gender, grade, className, classID = "classId", region, isPovertyArea, taskStatus, totalScore, taskVersion, birthDate }

    init(id: String, name: String, gender: String, grade: String, className: String, region: String, isPovertyArea: Bool, taskStatus: TaskStatus, totalScore: Double?, birthDate: String? = nil, taskVersion: Int? = nil, classID: String? = nil) {
        self.id = id; self.name = name; self.gender = gender; self.grade = grade; self.className = className
        self.classID = classID; self.region = region; self.isPovertyArea = isPovertyArea; self.taskStatus = taskStatus; self.totalScore = totalScore; self.birthDate = birthDate; self.taskVersion = taskVersion
    }
}
