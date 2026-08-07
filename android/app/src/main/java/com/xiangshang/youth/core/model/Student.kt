package com.xiangshang.youth.core.model
enum class TaskStatus(val label: String) {
    NotCheckedIn("未签到"), CheckedIn("已签到"), Waiting("候测"), Testing("测试中"), Completed("已完成"), Review("待复核"), Retest("待补测"), Absent("缺席");

    /** Keeps field-test actions on the documented queue state machine. */
    fun allowedNextStatuses(): List<TaskStatus> = when (this) {
        NotCheckedIn -> listOf(CheckedIn, Absent)
        CheckedIn -> listOf(NotCheckedIn, Waiting, Absent)
        Waiting -> listOf(Testing, Retest, Absent)
        Testing -> listOf(Completed, Review, Retest, Absent)
        Completed -> listOf(Review, Retest)
        Review -> listOf(Completed, Retest)
        Retest -> listOf(CheckedIn, Absent)
        Absent -> listOf(CheckedIn)
    }

    fun allowsTransitionTo(next: TaskStatus): Boolean = next == this || next in allowedNextStatuses()
}
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
