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

    /// Keeps local dashboard cards aligned with the assessment batch selected
    /// by the user.  The backend aggregate remains authoritative for counts;
    /// this only scopes representative student-level details such as risks.
    func scopedStudents(from students: [Student]) -> [Student] {
        let classNames = Set(className.split(separator: "、").map(String.init))
        let matchingClasses = students.filter { student in
            student.grade == gradeName && (classNames.isEmpty || classNames.contains(student.className))
        }
        return matchingClasses.isEmpty ? students.filter { $0.grade == gradeName } : matchingClasses
    }
}
