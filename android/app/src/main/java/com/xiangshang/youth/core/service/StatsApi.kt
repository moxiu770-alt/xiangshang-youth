package com.xiangshang.youth.core.service

import com.xiangshang.youth.core.repository.DashboardData
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query

interface StatsApi {
    @GET("v1/schools/{schoolId}/dashboard")
    suspend fun dashboard(@Path("schoolId") schoolId: String): DashboardData

    @GET("v1/schools/{schoolId}/grade-stats")
    suspend fun gradeStats(@Path("schoolId") schoolId: String): List<com.xiangshang.youth.core.model.Grade>

    @GET("v1/schools/{schoolId}/class-stats")
    suspend fun classStats(@Path("schoolId") schoolId: String, @Query("gradeId") gradeId: String? = null): List<com.xiangshang.youth.core.model.ClassInfo>
}
