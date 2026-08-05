package com.xiangshang.youth.core.model
enum class TaskStatus(val label: String) { NotCheckedIn("未签到"), CheckedIn("已签到"), Waiting("候测"), Testing("测试中"), Completed("已完成"), Review("待复核"), Retest("待补测"), Absent("缺席") }
data class Student(
    val id: String,
    val name: String,
    val grade: String,
    val className: String,
    val region: String,
    val isPovertyArea: Boolean,
    val taskStatus: TaskStatus,
    val totalScore: Double?,
    val gender: String = ""
)
