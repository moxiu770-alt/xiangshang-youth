package com.xiangshang.youth.core.mock

import com.xiangshang.youth.core.model.*
import com.xiangshang.youth.core.repository.DashboardData
import com.xiangshang.youth.core.repository.YouthRepository

class MockRepository : YouthRepository {
    private val school = School("school-1", "向上实验小学", "南湖校区", "广东省韶关市乳源瑶族自治县", true)
    private val grades = listOf(Grade("g3", "三年级", "小学三年级运动能力标准 v1.0"), Grade("g4", "四年级", "小学四年级运动能力标准 v1.0"), Grade("g5", "五年级", "小学五年级运动能力标准 v1.0"))
    private val classes = listOf(
        ClassInfo("c31", "三年级1班", "g3", "李老师", 10, 80), ClassInfo("c32", "三年级2班", "g3", "李老师", 10, 70),
        ClassInfo("c41", "四年级1班", "g4", "王老师", 10, 90), ClassInfo("c42", "四年级2班", "g4", "赵老师", 10, 80),
        ClassInfo("c51", "五年级1班", "g5", "陈老师", 10, 85), ClassInfo("c52", "五年级2班", "g5", "孙老师", 10, 75)
    )
    private val students = listOf("王小明","王小雨","陈子涵","刘一诺","张梓轩","李思远","周语桐","黄俊杰","吴欣怡","郑浩然","孙可心","何雨泽","杨子墨","朱思妍","马晨曦","胡宇航","林佳宁","郭子轩","高诗涵","罗锦程").mapIndexed { i, name ->
        val pairs = listOf("三年级" to "三年级1班","三年级" to "三年级2班","四年级" to "四年级1班","四年级" to "四年级2班","五年级" to "五年级1班","五年级" to "五年级2班")
        // Keep the deterministic demo sequence aligned with the iOS MockRepository.
        // The order is intentionally not TaskStatus.entries order: it mirrors the
        // reference task board, which needs completed, review, retest and absent
        // rows visible on the first screen.
        val statuses = listOf(TaskStatus.Completed, TaskStatus.Completed, TaskStatus.Review, TaskStatus.Retest, TaskStatus.Waiting, TaskStatus.NotCheckedIn, TaskStatus.Completed, TaskStatus.Testing, TaskStatus.Absent, TaskStatus.CheckedIn)
        Student("s" + (i + 1).toString().padStart(2, '0'), name, pairs[i % 6].first, pairs[i % 6].second, school.region, i % 3 == 0, statuses[i % statuses.size], if (i % 5 == 2) 19.5 else 24.0 + i % 11)
    }
    private val tasks = listOf(
        TestTask("t1","2026年秋季综合运动能力测评","2026-09-12 09:00","南湖校区体育馆","三年级","三年级1班、2班",15,20,TaskStatus.Testing,"小学三年级运动能力标准 v1.0"),
        TestTask("t2","四年级专项补测","2026-09-15 14:00","风雨操场","四年级","四年级1班",8,10,TaskStatus.Retest,"小学四年级运动能力标准 v1.0"),
        TestTask("t3","五年级秋季综合运动能力测评","2026-09-18 09:00","南湖校区体育馆","五年级","五年级1班、2班",0,20,TaskStatus.NotCheckedIn,"小学五年级运动能力标准 v1.0")
    )
    override suspend fun dashboard() = DashboardData(school, grades, classes, students, tasks, listOf(ParentChild("pc1","p1",students[0],"母子"), ParentChild("pc2","p1",students[1],"母女")), listOf(MessageItem("m1","测评报告已生成","王小明的秋季综合运动能力测评报告已生成。","今天 10:30","报告",false), MessageItem("m2","补测提醒","请关注班级补测安排，携带运动鞋按时到场。","昨天 16:00","任务",true)))
    override fun report(student: Student): DiagnosisReport {
        val scoreValues = if (student.id == "s01") listOf(4.5, 4.0, 3.5, 4.5, 4.0, 3.5, 4.5) else listOf(3.5, 3.0, 2.5, 3.5, 3.0, 3.5, 3.0)
        val scores = TestItem.entries.mapIndexed { i, item ->
            val confidence = if (i == 2) 0.72 else 0.94 + (i % 3) * 0.02
            ScoreResult(item, scoreValues[i], if (scoreValues[i] < 3.5) "建议重点练习" else "表现良好", confidence, if (confidence < 0.8) ScoreReviewStatus.PendingReview else ScoreReviewStatus.Passed)
        }
        val risks = if (scoreValues.any { it < 3 }) listOf("倒退平衡项目偏弱，建议4周后复测") else listOf("暂无高风险提示")
        return DiagnosisReport("r-" + student.id, student, "2026-09-12", scores, listOf("协调性良好","敏捷性优秀","平衡能力待提升"), risks, listOf("每周进行3次平衡与核心训练，每次15分钟","练习脚步变向时注意控制重心"), listOf(CourseSuggestion("course-1", "儿童协调性提升课", "12分钟/节", "平衡与敏捷", true), CourseSuggestion("course-2", "球类基础控球练习", "15分钟/节", "手脚协调", true)), student.grade + "运动能力标准 v1.0")
    }
}
