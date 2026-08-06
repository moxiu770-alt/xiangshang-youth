package com.xiangshang.youth.core.repository

import com.xiangshang.youth.core.model.*

data class DashboardData(
    val school: School, val grades: List<Grade>, val classes: List<ClassInfo>,
    val students: List<Student>, val tasks: List<TestTask>, val children: List<ParentChild>,
    val messages: List<MessageItem>
)

interface YouthRepository {
    suspend fun dashboard(): DashboardData
    fun report(student: Student): DiagnosisReport
    /** Mock falls back synchronously; RemoteRepository replaces this with ReportApi. */
    suspend fun loadReport(student: Student): DiagnosisReport = report(student)
}
