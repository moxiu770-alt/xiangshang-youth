package com.xiangshang.youth.core.model

import com.squareup.moshi.Json

enum class TaskStatus(val label: String) {
    @Json(name = "未签到")
    NotCheckedIn("未签到"),
    @Json(name = "已签到")
    CheckedIn("已签到"),
    @Json(name = "候测")
    Waiting("候测"),
    @Json(name = "测试中")
    Testing("测试中"),
    @Json(name = "已完成")
    Completed("已完成"),
    @Json(name = "待复核")
    Review("待复核"),
    @Json(name = "待补测")
    Retest("待补测"),
    @Json(name = "缺席")
    Absent("缺席");

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
    val gender: String = "",
    /** ISO-8601 calendar date used by BMI-for-age calculation. */
    val birthDate: String? = null,
    /** Monotonic server-side task row version for conflict-safe teacher edits. */
    val taskVersion: Int? = null,
    /** Stable class scope; className is display-only. */
    @Json(name = "classId") val classId: String? = null
)
