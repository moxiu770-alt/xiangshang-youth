package com.xiangshang.youth.core.model

import com.squareup.moshi.Json
data class TestTask(
    val id: String,
    val title: String,
    val date: String,
    val location: String,
    val gradeName: String,
    val className: String,
    val completedCount: Int,
    val totalCount: Int,
    val status: TaskStatus,
    val ruleVersion: String,
    val items: List<TestItem> = TestItem.entries,
    @param:Json(name = "classIds") val classIds: List<String> = emptyList(),
    @param:Json(name = "studentIds") val studentIds: List<String> = emptyList()
) {
    /** API aggregates are untrusted display data; never expose impossible
     * negative or over-complete progress to dashboard calculations. */
    val boundedTotalCount: Int get() = totalCount.coerceAtLeast(0)
    val boundedCompletedCount: Int get() = completedCount.coerceIn(0, boundedTotalCount)
    val completionRate: Int get() = if (boundedTotalCount == 0) 0 else kotlin.math.round(boundedCompletedCount.toDouble() / boundedTotalCount * 100).toInt()
    val normalizedItems: List<TestItem> get() = TestItem.entries.filter { it in items }

    /** Report-derived metrics require a service-confirmed completed result. */
    val hasPublishedResults: Boolean get() = boundedCompletedCount > 0 && boundedTotalCount > 0
    /**
     * The task count is an API aggregate. This helper only scopes the local
     * representative student rows used for risk and care detail cards.
     */
    fun scopedStudents(students: List<Student>): List<Student> {
        if (studentIds.isNotEmpty()) return students.filter { it.id in studentIds }
        if (classIds.isNotEmpty()) return students.filter { it.classId in classIds }
        // Display names are not authorization or roster keys. Until a remote
        // task carries an explicit scope, render the repository empty state.
        return emptyList()
    }

    /**
     * Mock rows may carry an old report while this task is still in progress.
     * Keep report-derived task averages limited to students completed in this
     * selected batch.
     */
    fun completedStudents(
        students: List<Student>,
        statusOf: (Student) -> TaskStatus
    ): List<Student> = scopedStudents(students).filter { statusOf(it) == TaskStatus.Completed }
}
