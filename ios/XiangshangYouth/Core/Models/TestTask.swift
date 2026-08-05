import Foundation

enum TaskStatus: String, CaseIterable, Codable, Hashable { case notCheckedIn = "未签到", checkedIn = "已签到", waiting = "候测", testing = "测试中", completed = "已完成", review = "待复核", retest = "待补测", absent = "缺席" }

struct TestTask: Identifiable, Codable, Hashable { let id: String; let title: String; let date: String; let location: String; let gradeName: String; let className: String; let items: [TestItem]; let completedCount: Int; let totalCount: Int; let status: TaskStatus; let ruleVersion: String }
