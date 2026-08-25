import Foundation

enum TaskStatus: String, CaseIterable, Codable, Hashable {
    case notCheckedIn = "未签到", checkedIn = "已签到", waiting = "候测", testing = "测试中", completed = "已完成", review = "待复核", retest = "待补测", absent = "缺席"

    /// App-side guardrail for the field-test queue. The server remains the
    /// authority, but the UI must never offer impossible jumps such as
    /// “未签到 → 已完成”. Exceptional states are deliberately routed through
    /// the review flow where a handling note is recorded.
    var allowedNextStatuses: [TaskStatus] {
        switch self {
        case .notCheckedIn: [.checkedIn, .absent]
        case .checkedIn: [.notCheckedIn, .waiting, .absent]
        case .waiting: [.testing, .retest, .absent]
        case .testing: [.completed, .review, .retest, .absent]
        case .completed: [.review, .retest]
        case .review: [.completed, .retest]
        case .retest: [.checkedIn, .absent]
        case .absent: [.checkedIn]
        }
    }

    func allowsTransition(to next: TaskStatus) -> Bool { next == self || allowedNextStatuses.contains(next) }
}

struct TestTask: Identifiable, Codable, Hashable {
    let id: String; let title: String; let date: String; let location: String; let gradeName: String; let className: String; let items: [TestItem]; let completedCount: Int; let totalCount: Int; let status: TaskStatus; let ruleVersion: String
    /// Names are presentation-only. Remote task scope is always supplied with
    /// stable student/class IDs so same-name classes can never share a queue.
    let classIDs: [String]
    let studentIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, date, location, gradeName, className, items, completedCount, totalCount, status, ruleVersion
        case classIDs = "classIds"
        case studentIDs = "studentIds"
    }

    init(id: String, title: String, date: String, location: String, gradeName: String, className: String, items: [TestItem], completedCount: Int, totalCount: Int, status: TaskStatus, ruleVersion: String, classIDs: [String] = [], studentIDs: [String] = []) {
        self.id = id; self.title = title; self.date = date; self.location = location
        self.gradeName = gradeName; self.className = className; self.items = items
        self.completedCount = completedCount; self.totalCount = totalCount; self.status = status; self.ruleVersion = ruleVersion
        self.classIDs = classIDs; self.studentIDs = studentIDs
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(String.self, forKey: .id)
        title = try box.decode(String.self, forKey: .title)
        date = try box.decode(String.self, forKey: .date)
        location = try box.decode(String.self, forKey: .location)
        gradeName = try box.decode(String.self, forKey: .gradeName)
        className = try box.decode(String.self, forKey: .className)
        items = try box.decodeIfPresent([TestItem].self, forKey: .items) ?? []
        completedCount = try box.decode(Int.self, forKey: .completedCount)
        totalCount = try box.decode(Int.self, forKey: .totalCount)
        status = try box.decode(TaskStatus.self, forKey: .status)
        ruleVersion = try box.decode(String.self, forKey: .ruleVersion)
        classIDs = try box.decodeIfPresent([String].self, forKey: .classIDs) ?? []
        studentIDs = try box.decodeIfPresent([String].self, forKey: .studentIDs) ?? []
    }

    /// API aggregates are untrusted display data. Keep progress monotonic and
    /// bounded even when an old task row contains a negative or over-count.
    var boundedTotalCount: Int { max(0, totalCount) }
    var boundedCompletedCount: Int { min(boundedTotalCount, max(0, completedCount)) }
    var completionRate: Int {
        guard boundedTotalCount > 0 else { return 0 }
        return Int((Double(boundedCompletedCount) / Double(boundedTotalCount) * 100).rounded())
    }
    var normalizedItems: [TestItem] { TestItem.allCases.filter { items.contains($0) } }

    /// Report-derived metrics are not meaningful until the assessment service
    /// has published at least one completed result for this batch.
    var hasPublishedResults: Bool { boundedCompletedCount > 0 && boundedTotalCount > 0 }

    /// Keeps local dashboard cards aligned with the assessment batch selected
    /// by the user.  The backend aggregate remains authoritative for counts;
    /// this only scopes representative student-level details such as risks.
    func scopedStudents(from students: [Student]) -> [Student] {
        let studentScope = Set(studentIDs)
        if !studentScope.isEmpty { return students.filter { studentScope.contains($0.id) } }
        let classScope = Set(classIDs)
        if !classScope.isEmpty { return students.filter { student in classScope.contains(student.classID ?? "") } }
        // A remote response without a stable scope must not silently use the
        // display names as a primary key. It is safer to show the sync empty
        // state until the server returns the authoritative roster.
        return []
    }

    /// The bundled student rows can contain a prior report while the selected
    /// batch is still waiting or being tested. Dashboard score averages must
    /// use only the people whose status is complete in this batch.
    func completedStudents(from students: [Student], statusFor: (Student) -> TaskStatus) -> [Student] {
        scopedStudents(from: students).filter { statusFor($0) == .completed }
    }
}
