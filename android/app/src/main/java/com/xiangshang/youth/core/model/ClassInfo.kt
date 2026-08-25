package com.xiangshang.youth.core.model
data class ClassInfo(val id: String, val name: String, val gradeId: String, val teacherName: String, val studentCount: Int, val completionRate: Int, val teacherId: String? = null) {
    val boundedCompletionRate: Int get() = completionRate.coerceIn(0, 100)
    val completedStudentEstimate: Int get() = kotlin.math.round(studentCount.coerceAtLeast(0) * boundedCompletionRate / 100.0).toInt()
}
