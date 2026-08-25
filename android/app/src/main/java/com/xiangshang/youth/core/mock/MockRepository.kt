package com.xiangshang.youth.core.mock

import com.xiangshang.youth.core.model.*
import com.xiangshang.youth.core.repository.DashboardData
import com.xiangshang.youth.core.repository.YouthRepository

class MockRepository : YouthRepository {
    private val school = School("school-1", "向上实验小学", "南湖校区", "广东省韶关市乳源瑶族自治县", true)
    private val grades = listOf(Grade("g3", "三年级", "小学三年级运动能力标准 v1.0"), Grade("g4", "四年级", "小学四年级运动能力标准 v1.0"), Grade("g5", "五年级", "小学五年级运动能力标准 v1.0"))
    private val classes = listOf(
        ClassInfo("c31", "三年级1班", "g3", "李老师", 10, 80, "teacher_li"), ClassInfo("c32", "三年级2班", "g3", "李老师", 10, 70, "teacher_li"),
        ClassInfo("c41", "四年级1班", "g4", "王老师", 10, 90, "teacher_wang"), ClassInfo("c42", "四年级2班", "g4", "赵老师", 10, 80, "teacher_zhao"),
        ClassInfo("c51", "五年级1班", "g5", "陈老师", 10, 85, "teacher_chen"), ClassInfo("c52", "五年级2班", "g5", "孙老师", 10, 75, "teacher_sun")
    )
    private val students = listOf("王小明","王小雨","陈子涵","刘一诺","张梓轩","李思远","周语桐","黄俊杰","吴欣怡","郑浩然","孙可心","何雨泽","杨子墨","朱思妍","马晨曦","胡宇航","林佳宁","郭子轩","高诗涵","罗锦程").mapIndexed { i, name ->
        val pairs = listOf("三年级" to "三年级1班","三年级" to "三年级2班","四年级" to "四年级1班","四年级" to "四年级2班","五年级" to "五年级1班","五年级" to "五年级2班")
        // Keep the deterministic demo sequence aligned with the iOS MockRepository.
        // The order is intentionally not TaskStatus.entries order: it mirrors the
        // reference task board, which needs completed, review, retest and absent
        // rows visible on the first screen.
        val statuses = listOf(TaskStatus.Completed, TaskStatus.Completed, TaskStatus.Review, TaskStatus.Retest, TaskStatus.Waiting, TaskStatus.NotCheckedIn, TaskStatus.Completed, TaskStatus.Testing, TaskStatus.Absent, TaskStatus.CheckedIn)
        val year = if (pairs[i % 6].first.contains("三")) 2017 else if (pairs[i % 6].first.contains("四")) 2016 else 2015
        val status = statuses[i % statuses.size]
        // A student-card score is only shown after a published school report;
        // unfinished, absent and review rows stay explicitly scoreless.
        val publishedScore = if (status == TaskStatus.Completed) if (i == 0) 28.5 else 22.0 else null
        Student("s" + (i + 1).toString().padStart(2, '0'), name, pairs[i % 6].first, pairs[i % 6].second, school.region, i % 3 == 0, status, publishedScore, if (i % 2 == 0) "男" else "女", "$year-${(i % 12 + 1).toString().padStart(2, '0')}-${(i % 27 + 1).toString().padStart(2, '0')}", classId = classes[i % classes.size].id)
    }
    private val tasks = listOf(
        TestTask("t1","2026年秋季综合运动能力测评","2026-08-20 09:00","南湖校区体育馆","全校","三至五年级 · 6个班级",15,20,TaskStatus.Testing,"小学综合运动能力标准 v1.0", classIds = classes.map { it.id }, studentIds = students.map { it.id }),
        TestTask("t2","四年级专项补测","2026-09-15 14:00","风雨操场","四年级","四年级1班",8,10,TaskStatus.Retest,"小学四年级运动能力标准 v1.0", classIds = listOf("c41"), studentIds = students.filter { it.classId == "c41" }.map { it.id }),
        TestTask("t3","五年级秋季综合运动能力测评","2026-09-18 09:00","南湖校区体育馆","五年级","五年级1班、2班",0,20,TaskStatus.NotCheckedIn,"小学五年级运动能力标准 v1.0", classIds = listOf("c51", "c52"), studentIds = students.filter { it.classId in setOf("c51", "c52") }.map { it.id })
    )
    override suspend fun dashboard(studentPage: Int?, studentPageSize: Int?) = DashboardData(school, grades, classes, students, tasks, listOf(ParentChild("pc1","p1",students[0],"母子"), ParentChild("pc2","p1",students[1],"母女")), listOf(
        MessageItem("m1", "体质提醒", "体质指标偏低，建议关注饮食与运动习惯。", "08:30", "健康提醒", false),
        MessageItem("m2", "视力提醒", "用眼时长超过建议时长，建议合理用眼。", "昨天 21:00", "健康提醒", true),
        MessageItem("m3", "口腔提醒", "建议定期进行口腔健康检查。", "昨天 20:00", "成长关注", true),
        MessageItem("m4", "心理提醒", "情绪状态良好，继续保持。", "昨天 18:30", "成长关注", true),
        MessageItem("m5", "成长提醒", "本月完成2次运动打卡，继续保持运动习惯。", "07-15 16:20", "系统", true),
        MessageItem("m6", "打卡提醒", "今日运动打卡未完成，快去打卡吧！", "07-15 08:00", "系统", true)
    ))
    override suspend fun taskStudentStatuses(taskId: String): List<com.xiangshang.youth.core.service.TaskStudentStatusRecord> {
        val task = tasks.firstOrNull { it.id == taskId } ?: return emptyList()
        return task.scopedStudents(students).map { student ->
            com.xiangshang.youth.core.service.TaskStudentStatusRecord("$taskId-${student.id}", taskId, student.id, student.taskStatus, student.taskVersion ?: 1, student.name, student.className, student.gender, student.classId?.let { id -> classes.firstOrNull { it.id == id }?.gradeId }, student.grade, student.classId)
        }
    }
    override fun report(student: Student): DiagnosisReport {
        val scoreValues = if (student.id == "s01") listOf(4.5, 4.0, 3.5, 4.5, 4.0, 3.5, 4.5) else listOf(3.5, 3.0, 2.5, 3.5, 3.0, 3.5, 3.0)
        val scores = TestItem.entries.mapIndexed { i, item ->
            val confidence = if (i == 2) 0.72 else 0.94 + (i % 3) * 0.02
            ScoreResult(item, scoreValues[i], if (scoreValues[i] < 3.5) "建议重点练习" else "表现良好", confidence, if (confidence < 0.8) ScoreReviewStatus.PendingReview else ScoreReviewStatus.Passed)
        }
        val risks = if (scoreValues.any { it < 3 }) listOf("倒退平衡项目偏弱，建议4周后复测") else listOf("暂无高风险提示")
        return DiagnosisReport("r-" + student.id, student, "2026-08-20", scores, listOf("协调性良好","敏捷性优秀","平衡能力待提升"), risks, listOf("每周进行3次平衡与核心训练，每次15分钟","练习脚步变向时注意控制重心"), listOf(CourseSuggestion("course-1", "儿童协调性提升课", "12分钟/节", "平衡与敏捷", true), CourseSuggestion("course-2", "球类基础控球练习", "15分钟/节", "手脚协调", true)), student.grade + "运动能力标准 v1.0", RegionPolicy("policy-${student.grade}", student.region, if (student.isPovertyArea) "贫困地区专项帮扶" else null, student.grade + "运动能力标准 v1.0", "2026-08-01"))
    }
}
