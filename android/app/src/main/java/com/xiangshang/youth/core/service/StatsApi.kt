package com.xiangshang.youth.core.service

import com.xiangshang.youth.core.repository.DashboardData
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query

data class TeacherAnalyticsItem(val itemCode: String, val totalCount: Int, val measuredCount: Int, val completionRate: Int, val averageScore: Double, val riskCount: Int)
data class TeacherAnalyticsOverview(val totalCount: Int, val completedCount: Int, val reviewCount: Int, val retestCount: Int, val absentCount: Int, val riskCount: Int, val lowScoreCount: Int, val itemStats: List<TeacherAnalyticsItem> = emptyList(), val dataAvailable: Boolean = false)

interface StatsApi {
    @GET("v1/teacher/analytics/overview")
    suspend fun teacherOverview(@Query("schoolId") schoolId: String, @Query("classId") classId: String, @Query("taskId") taskId: String, @Query("standardVersion") standardVersion: String): ApiEnvelope<TeacherAnalyticsOverview>
    @GET("v1/schools/{schoolId}/dashboard")
    suspend fun dashboard(
        @Path("schoolId") schoolId: String,
        @Query("studentPage") studentPage: Int? = null,
        @Query("studentPageSize") studentPageSize: Int? = null
    ): ApiEnvelope<DashboardData>

    @GET("v1/schools/{schoolId}/grade-stats")
    suspend fun gradeStats(@Path("schoolId") schoolId: String): ApiEnvelope<List<com.xiangshang.youth.core.model.Grade>>

    @GET("v1/schools/{schoolId}/class-stats")
    suspend fun classStats(@Path("schoolId") schoolId: String, @Query("gradeId") gradeId: String? = null): ApiEnvelope<List<com.xiangshang.youth.core.model.ClassInfo>>
}
