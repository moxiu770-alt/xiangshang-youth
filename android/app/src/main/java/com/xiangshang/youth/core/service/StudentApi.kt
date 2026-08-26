package com.xiangshang.youth.core.service

import com.xiangshang.youth.core.model.ParentChild
import com.xiangshang.youth.core.model.Student
import com.xiangshang.youth.core.model.PostureMetricSnapshot
import com.xiangshang.youth.core.model.BodyAssessmentRecord
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Body
import retrofit2.http.Header

interface StudentApi {
    @GET("v1/schools/{schoolId}/students")
    suspend fun students(@Path("schoolId") schoolId: String, @Query("classId") classId: String? = null): ApiEnvelope<List<Student>>

    @POST("v1/students/{studentId}/bind")
    suspend fun bindChild(@Path("studentId") studentId: String, @Query("code") bindingCode: String): ApiEnvelope<ParentChild>

    @POST("v1/students/bind")
    suspend fun bindChild(@Body request: BindingRequest): ApiEnvelope<ParentChild>

    @POST("v1/students/{studentId}/consent")
    suspend fun grantConsent(@Path("studentId") studentId: String, @Body request: ConsentRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<WriteAck>

    @POST("v1/students/{studentId}/consent")
    suspend fun revokeConsent(@Path("studentId") studentId: String, @Body request: ConsentRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<WriteAck>

    @POST("v1/students/{studentId}/body-assessments")
    suspend fun submitBodyAssessment(@Path("studentId") studentId: String, @Body request: BodyAssessmentRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<RemoteBodyAssessmentResult>

    @POST("v1/students/{studentId}/privacy-requests")
    suspend fun submitPrivacyRequest(@Path("studentId") studentId: String, @Body request: PrivacyRequestBody): ApiEnvelope<PrivacyRequestReceipt>
}

data class BindingRequest(val studentName: String, val code: String)
data class ConsentRequest(val consentVersion: String, val purpose: String = "body_assessment", val granted: Boolean = true, val consentId: String = java.util.UUID.randomUUID().toString(), val privacyPolicyVersion: String = consentVersion, val cameraConsentVersion: String = com.xiangshang.youth.core.model.LegalPolicy.CAMERA_CONSENT_VERSION, val algorithmNoticeVersion: String = com.xiangshang.youth.core.model.LegalPolicy.ALGORITHM_NOTICE_VERSION, val deviceInfoHash: String? = null, val appVersion: String? = null, val dataRetentionNoticeAccepted: Boolean = true)
data class PrivacyRequestBody(val requestType: String)
data class PrivacyRequestReceipt(val id: String, val requestType: String, val status: String, val createdAt: String, val jobId: String? = null)
data class BodySnapshotRequest(val captureTask: String, val sampleCount: Int, val confidence: Double, val metrics: PostureMetricSnapshot)
data class BodyAssessmentRequest(val heightCm: Double, val weightKg: Double, val overallLevel: String, val algorithmVersion: String, val consentVersion: String, val data: BodyAssessmentRecord, val snapshots: List<BodySnapshotRequest>)
data class RemoteBodyAssessmentResult(
    val postureReport: RemotePostureSummary? = null,
    val bmiAlgorithmVersion: String? = null,
    val heightAlgorithmVersion: String? = null,
    val modelRegistryVersion: String? = null
)
data class RemotePostureSummary(
    val algorithm: String,
    val overallLevel: String,
    val reasons: List<String> = emptyList(),
    val disclaimer: String = "",
    val riskScore: Int = 0,
    val qualityScore: Int = 0,
    val calibrationVersion: String? = null,
    val rulesSourceVersion: String? = null
)
