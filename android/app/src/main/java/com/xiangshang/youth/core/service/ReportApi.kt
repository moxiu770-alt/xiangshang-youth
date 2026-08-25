package com.xiangshang.youth.core.service

import com.xiangshang.youth.core.model.DiagnosisReport
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

interface ReportApi {
    @GET("v1/students/{studentId}/report")
    suspend fun report(@Path("studentId") studentId: String): ApiEnvelope<DiagnosisReport>

    @POST("v1/students/{studentId}/report/refresh")
    suspend fun refresh(@Path("studentId") studentId: String): ApiEnvelope<DiagnosisReport>
}
