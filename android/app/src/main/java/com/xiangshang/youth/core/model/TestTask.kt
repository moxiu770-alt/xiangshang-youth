package com.xiangshang.youth.core.model
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
    val items: List<TestItem> = TestItem.entries
) {
    /**
     * The task count is an API aggregate. This helper only scopes the local
     * representative student rows used for risk and care detail cards.
     */
    fun scopedStudents(students: List<Student>): List<Student> {
        if (gradeName == "全校") return students
        val classNames = className.split("、").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
        val matchingClasses = students.filter { student ->
            student.grade == gradeName && (classNames.isEmpty() || student.className in classNames)
        }
        return matchingClasses.ifEmpty { students.filter { it.grade == gradeName } }
    }
}
