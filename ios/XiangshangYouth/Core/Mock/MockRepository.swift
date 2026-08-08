import Foundation

/// Default data source for phase one. Switch AppEnvironment.repository to RemoteRepository when backend is ready.
final class MockRepository: YouthRepository {
    static let shared = MockRepository()
    let school = School(id: "school-1", name: "向上实验小学", campus: "南湖校区", region: "广东省韶关市乳源瑶族自治县", isPovertyArea: true)
    let grades = [Grade(id: "g3", name: "三年级", standardVersion: "小学三年级运动能力标准 v1.0"), Grade(id: "g4", name: "四年级", standardVersion: "小学四年级运动能力标准 v1.0"), Grade(id: "g5", name: "五年级", standardVersion: "小学五年级运动能力标准 v1.0")]
    let classes = [
        ClassInfo(id: "c31", name: "三年级1班", gradeId: "g3", teacherName: "李老师", studentCount: 10, completionRate: 80), ClassInfo(id: "c32", name: "三年级2班", gradeId: "g3", teacherName: "李老师", studentCount: 10, completionRate: 70),
        ClassInfo(id: "c41", name: "四年级1班", gradeId: "g4", teacherName: "王老师", studentCount: 10, completionRate: 90), ClassInfo(id: "c42", name: "四年级2班", gradeId: "g4", teacherName: "赵老师", studentCount: 10, completionRate: 80),
        ClassInfo(id: "c51", name: "五年级1班", gradeId: "g5", teacherName: "陈老师", studentCount: 10, completionRate: 85), ClassInfo(id: "c52", name: "五年级2班", gradeId: "g5", teacherName: "孙老师", studentCount: 10, completionRate: 75)
    ]
    lazy var students: [Student] = {
        let statuses: [TaskStatus] = [.completed, .completed, .review, .retest, .waiting, .notCheckedIn, .completed, .testing, .absent, .checkedIn]
        let classPairs = [("三年级", "三年级1班"), ("三年级", "三年级2班"), ("四年级", "四年级1班"), ("四年级", "四年级2班"), ("五年级", "五年级1班"), ("五年级", "五年级2班")]
        let names = ["王小明", "王小雨", "陈子涵", "刘一诺", "张梓轩", "李思远", "周语桐", "黄俊杰", "吴欣怡", "郑浩然", "孙可心", "何雨泽", "杨子墨", "朱思妍", "马晨曦", "胡宇航", "林佳宁", "郭子轩", "高诗涵", "罗锦程"]
        return names.enumerated().map { index, name in
            let pair = classPairs[index % classPairs.count]
            return Student(id: String(format: "s%02d", index + 1), name: name, gender: index % 2 == 0 ? "男" : "女", grade: pair.0, className: pair.1, region: school.region, isPovertyArea: index % 3 == 0, taskStatus: statuses[index % statuses.count], totalScore: index % 5 == 2 ? 19.5 : Double(24 + index % 11))
        }
    }()
    lazy var tasks: [TestTask] = [
        TestTask(id: "t1", title: "2026年秋季综合运动能力测评", date: "2026-09-12 09:00", location: "南湖校区体育馆", gradeName: "全校", className: "三至五年级 · 6个班级", items: TestItem.allCases, completedCount: 15, totalCount: 20, status: .testing, ruleVersion: "小学综合运动能力标准 v1.0"),
        TestTask(id: "t2", title: "四年级专项补测", date: "2026-09-15 14:00", location: "风雨操场", gradeName: "四年级", className: "四年级1班", items: TestItem.allCases, completedCount: 8, totalCount: 10, status: .retest, ruleVersion: "小学四年级运动能力标准 v1.0"),
        TestTask(id: "t3", title: "五年级秋季综合运动能力测评", date: "2026-09-18 09:00", location: "南湖校区体育馆", gradeName: "五年级", className: "五年级1班、2班", items: TestItem.allCases, completedCount: 0, totalCount: 20, status: .notCheckedIn, ruleVersion: "小学五年级运动能力标准 v1.0")
    ]
    func report(for student: Student) -> DiagnosisReport {
        let scores: [Double] = student.id == "s01" ? [4.5, 4, 3.5, 4.5, 4, 3.5, 4.5] : [3.5, 3, 2.5, 3.5, 3, 3.5, 3]
        return DiagnosisReport(id: "r-\(student.id)", student: student, assessmentDate: "2026-09-12", scores: zip(TestItem.allCases, scores).enumerated().map { index, pair in
            let confidence = index == 2 ? 0.72 : 0.94 + Double(index % 3) * 0.02
            return ScoreResult(id: pair.0.id, item: pair.0, score: pair.1, note: pair.1 < 3.5 ? "建议重点练习" : "表现良好", confidence: confidence, reviewStatus: confidence < 0.8 ? .pendingReview : .passed)
        }, abilityTags: ["协调性良好", "敏捷性优秀", "平衡能力待提升"], riskAlerts: scores.contains(where: { $0 < 3 }) ? ["倒退平衡项目偏弱，建议4周后复测"] : ["暂无高风险提示"], trainingAdvice: ["每周进行3次平衡与核心训练，每次15分钟", "练习脚步变向时注意控制重心"], courseSuggestions: [CourseSuggestion(id: "course1", title: "儿童协调性提升课", duration: "12分钟/节", focus: "平衡与敏捷", isPublicBenefit: true), CourseSuggestion(id: "course2", title: "球类基础控球练习", duration: "15分钟/节", focus: "手脚协调", isPublicBenefit: true)], ruleVersion: student.grade.replacingOccurrences(of: "年级", with: "年级运动能力标准 v1.0"), regionPolicy: RegionPolicy(id: "policy-(student.grade)", region: student.region, povertyAreaLabel: student.isPovertyArea ? "贫困地区专项帮扶" : nil, standardVersion: student.grade.replacingOccurrences(of: "年级", with: "年级运动能力标准 v1.0"), effectiveDate: "2026-09-01"))
    }
    func loadDashboard() async throws -> DashboardData { try await Task.sleep(for: .milliseconds(350)); return DashboardData(school: school, students: students, classes: classes, grades: grades, tasks: tasks, parentChildren: [ParentChild(id: "pc1", parentId: "p1", student: students[0], relation: "母子"), ParentChild(id: "pc2", parentId: "p1", student: students[1], relation: "母女")], messages: [MessageItem(id: "m1", title: "体质提醒", content: "体质指标偏低，建议关注饮食与运动习惯。", time: "08:30", isRead: false, category: "健康提醒"), MessageItem(id: "m2", title: "视力提醒", content: "用眼时长超过建议时长，建议合理用眼。", time: "昨天 21:00", isRead: true, category: "健康提醒"), MessageItem(id: "m3", title: "口腔提醒", content: "建议定期进行口腔健康检查。", time: "昨天 20:00", isRead: true, category: "成长关注"), MessageItem(id: "m4", title: "心理提醒", content: "情绪状态良好，继续保持。", time: "昨天 18:30", isRead: true, category: "成长关注"), MessageItem(id: "m5", title: "成长提醒", content: "本月完成2次运动打卡，继续保持运动习惯。", time: "07-15 16:20", isRead: true, category: "系统"), MessageItem(id: "m6", title: "打卡提醒", content: "今日运动打卡未完成，快去打卡吧！", time: "07-15 08:00", isRead: true, category: "系统")]) }
}

struct DashboardData: Codable { let school: School; let students: [Student]; let classes: [ClassInfo]; let grades: [Grade]; let tasks: [TestTask]; let parentChildren: [ParentChild]; let messages: [MessageItem] }
