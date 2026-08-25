package com.xiangshang.youth.core.service

import com.xiangshang.youth.core.model.TaskStatus
import com.xiangshang.youth.core.model.TestTask
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Body
import retrofit2.http.Header
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.PUT
import okhttp3.RequestBody
import okhttp3.ResponseBody
import retrofit2.Response

data class TaskStatusRequest(val status: TaskStatus, val note: String? = null, val expectedVersion: Int? = null, val clientOperationId: String = java.util.UUID.randomUUID().toString())
data class TaskStatusBatchItem(val studentId: String, val status: TaskStatus, val note: String? = null, val reasonCode: String? = null, val expectedVersion: Int? = null, val clientOperationId: String = java.util.UUID.randomUUID().toString())
data class TaskBatchStatusRequest(val updates: List<TaskStatusBatchItem>)
data class TaskBatchStatusAck(val updated: Int? = null, val items: List<TaskStudentStatusRecord>? = null)
data class TaskStatusEvent(val id: String, val taskId: String, val studentId: String, val fromStatus: TaskStatus, val toStatus: TaskStatus, val note: String? = null, val reasonCode: String? = null, val operatorTeacherId: String? = null, val resultingVersion: Int? = null, val createdAt: String)
data class TaskStudentStatusRecord(
    val id: String,
    val taskId: String,
    val studentId: String,
    val status: TaskStatus,
    val version: Int,
    val studentName: String,
    val className: String,
    val studentGender: String? = null,
    val gradeId: String? = null,
    val gradeName: String? = null,
    val classId: String? = null
)

interface TaskApi {
    @GET("v1/schools/{schoolId}/tasks")
    suspend fun tasks(@Path("schoolId") schoolId: String, @Query("gradeId") gradeId: String? = null, @Query("classId") classId: String? = null): ApiEnvelope<List<TestTask>>

    @GET("v1/tasks/{taskId}/students")
    suspend fun taskStudents(@Path("taskId") taskId: String, @Query("page") page: Int? = null, @Query("pageSize") pageSize: Int? = null, @Query("status") status: String? = null, @Query("keyword") keyword: String? = null, @Query("paged") paged: Int? = null): ApiEnvelope<List<TaskStudentStatusRecord>>

    @PATCH("v1/tasks/{taskId}/students/{studentId}/status")
    suspend fun updateStatus(@Path("taskId") taskId: String, @Path("studentId") studentId: String, @retrofit2.http.Body body: TaskStatusRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<WriteAck>

    @POST("v1/tasks/{taskId}/students/batch-status")
    suspend fun batchUpdateStatus(@Path("taskId") taskId: String, @Body body: TaskBatchStatusRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<TaskBatchStatusAck>

    @GET("v1/tasks/{taskId}/students/{studentId}/status-history")
    suspend fun statusHistory(@Path("taskId") taskId: String, @Path("studentId") studentId: String): ApiEnvelope<List<TaskStatusEvent>>
}

/** Write-side command boundary kept beside the read APIs for staged rollout. */
interface WorkflowApi {
    @GET("v1/students/{studentId}/training-sessions")
    suspend fun trainingSessions(@Path("studentId") studentId: String, @Query("from") from: String? = null, @Query("to") to: String? = null): ApiEnvelope<List<TrainingSessionRecord>>

    @POST("v1/students/{studentId}/training-sessions")
    suspend fun submitTrainingSession(@Path("studentId") studentId: String, @Body body: TrainingSessionRequest): ApiEnvelope<TrainingSessionRecord>

    @GET("v1/students/{studentId}/health-checkins")
    suspend fun healthCheckins(@Path("studentId") studentId: String, @Query("from") from: String? = null, @Query("to") to: String? = null): ApiEnvelope<List<HealthCheckInRecord>>

    @POST("v1/students/{studentId}/health-checkins")
    suspend fun submitHealthCheckin(@Path("studentId") studentId: String, @Body body: HealthCheckInRequest): ApiEnvelope<HealthCheckInRecord>

    @GET("v1/activities")
    suspend fun activities(@Query("childId") childId: String? = null): ApiEnvelope<List<RemoteActivity>>

    @GET("v1/experts")
    suspend fun experts(): ApiEnvelope<List<RemoteExpert>>

    @GET("v1/experts/{expertId}/available-slots")
    suspend fun availableSlots(@Path("expertId") expertId: String): ApiEnvelope<List<ExpertAvailableSlot>>

    @POST("v1/activities/{activityId}/registrations")
    suspend fun registerActivity(@Path("activityId") activityId: String, @Body body: ActivityRegistrationRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<ActivityRegistrationAck>

    @GET("v1/activities/registrations/history")
    suspend fun activityRegistrationHistory(): ApiEnvelope<List<ActivityRegistrationAck>>

    @PUT("v1/activities/{activityId}/registrations/{registrationId}")
    suspend fun updateActivityRegistration(@Path("activityId") activityId: String, @Path("registrationId") registrationId: String, @Body body: ActivityRegistrationUpdateRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<ActivityRegistrationAck>

    @POST("v1/activities/{activityId}/registrations/{registrationId}/cancel")
    suspend fun cancelActivityRegistration(@Path("activityId") activityId: String, @Path("registrationId") registrationId: String, @Body body: CancellationRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<ActivityRegistrationAck>

    @POST("v1/expert-appointments")
    suspend fun bookExpert(@Body body: ExpertAppointmentRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<ExpertAppointmentAck>

    @GET("v1/expert-appointments/history")
    suspend fun expertAppointmentHistory(): ApiEnvelope<List<ExpertAppointmentAck>>

    @PUT("v1/expert-appointments/{appointmentId}/reschedule")
    suspend fun rescheduleExpert(@Path("appointmentId") appointmentId: String, @Body body: ExpertRescheduleRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<ExpertAppointmentAck>

    @POST("v1/expert-appointments/{appointmentId}/cancel")
    suspend fun cancelExpert(@Path("appointmentId") appointmentId: String, @Body body: CancellationRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<ExpertAppointmentAck>

    @POST("v1/courses/uploads")
    suspend fun uploadCourse(@Body body: CourseUploadRequest): ApiEnvelope<WriteAck>

    @PATCH("v1/students/{studentId}/task-status")
    suspend fun updateTaskStatus(@Path("studentId") studentId: String, @Body body: WorkflowTaskStatusRequest): ApiEnvelope<WriteAck>

    @POST("v1/class-posts")
    suspend fun publishClassPost(@Body body: ClassPostRequest): ApiEnvelope<WriteAck>

    @POST("v1/support/messages")
    suspend fun sendSupportMessage(@Body body: SupportMessageRequest): ApiEnvelope<WriteAck>
}

interface ClassPostApi {
    @GET("v1/class-posts")
    suspend fun list(@retrofit2.http.Query("schoolId") schoolId: String?, @retrofit2.http.Query("classId") classId: String?, @retrofit2.http.Query("cursor") cursor: String? = null, @retrofit2.http.Query("pageSize") pageSize: Int = 20): ApiEnvelope<RemoteClassPostPage>

    @retrofit2.http.DELETE("v1/class-posts/{postId}")
    suspend fun delete(@retrofit2.http.Path("postId") postId: String, @retrofit2.http.Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<WriteAck>

    @POST("v1/class-posts/{postId}/report")
    suspend fun report(@retrofit2.http.Path("postId") postId: String, @Body body: ClassPostReportRequest, @retrofit2.http.Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<WriteAck>

    @POST("v1/class-posts/{postId}/pin")
    suspend fun pin(@retrofit2.http.Path("postId") postId: String, @Body body: ClassPostPinRequest, @retrofit2.http.Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<WriteAck>

    @POST("v1/class-posts/{postId}/comments")
    suspend fun addComment(@retrofit2.http.Path("postId") postId: String, @Body body: ClassPostCommentRequest, @retrofit2.http.Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<ClassPostCommentAck>

    @GET("v1/class-posts/{postId}/comments")
    suspend fun comments(@retrofit2.http.Path("postId") postId: String, @retrofit2.http.Query("cursor") cursor: String? = null, @retrofit2.http.Query("pageSize") pageSize: Int = 20): ApiEnvelope<ClassPostCommentPage>

    @retrofit2.http.DELETE("v1/class-posts/{postId}/comments/{commentId}")
    suspend fun deleteComment(@retrofit2.http.Path("postId") postId: String, @retrofit2.http.Path("commentId") commentId: String, @retrofit2.http.Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<ClassPostCommentAck>
}

data class RemoteClassPostPage(val items: List<RemoteClassPost> = emptyList(), val nextCursor: String? = null)
data class ClassPostReportRequest(val reason: String)
data class ClassPostPinRequest(val pinned: Boolean)
data class ClassPostCommentRequest(val content: String)
data class ClassPostCommentAck(val commentId: String, val postId: String, val displayName: String? = null, val content: String? = null, val status: String? = null, val createdAt: String? = null, val ownedByCurrentUser: Boolean? = null)
data class ClassPostCommentPage(val items: List<ClassPostCommentAck> = emptyList(), val nextCursor: String? = null)
data class RemoteClassPost(
    val postId: String,
    val schoolId: String? = null,
    val classId: String? = null,
    val displayName: String? = null,
    val content: String,
    val status: String? = null,
    val visibilityScope: String? = null,
    val moderationStatus: String? = null,
    val pinned: Boolean? = null,
    val reportStatus: String? = null,
    val authorRole: String? = null,
    val ownedByCurrentUser: Boolean? = null,
    val attachments: List<RemoteClassPostAttachment>? = null,
    val createdAt: String? = null
)
data class RemoteClassPostAttachment(val id: String, val type: String, val objectId: String? = null, val thumbnailObjectId: String? = null)

data class ActivityRegistrationRequest(val contactName: String, val phone: String, val childId: String? = null)
data class ActivityRegistrationUpdateRequest(val contactName: String, val phone: String, val childId: String? = null, val expectedVersion: Int? = null)
data class ExpertAppointmentRequest(val expertName: String, val preferredDate: String, val note: String, val expertId: String? = null, val serviceId: String? = null, val slotId: String? = null, val childId: String? = null)
data class ExpertRescheduleRequest(val slotId: String, val expectedVersion: Int? = null)
data class CancellationRequest(val expectedVersion: Int? = null)
data class RemoteActivity(
    val activityId: String,
    val schoolId: String? = null,
    val title: String,
    val description: String? = null,
    val startsAt: String? = null,
    val endsAt: String? = null,
    val capacity: Int? = null,
    val registrationStartAt: String? = null,
    val registrationEndAt: String? = null,
    val status: String = "open",
    val version: Int? = null,
    val registeredCount: Int? = null,
    val remainingCapacity: Int? = null,
    val registrationId: String? = null,
    val registrationStatus: String? = null,
    val childId: String? = null
)
data class RemoteExpert(
    val expertId: String,
    val schoolId: String? = null,
    val name: String,
    val title: String? = null,
    val bio: String? = null,
    val status: String? = null
)
data class ExpertAvailableSlot(
    val slotId: String,
    val expertId: String,
    val serviceId: String? = null,
    val scheduledStartAt: String,
    val scheduledEndAt: String,
    val capacity: Int? = null,
    val version: Int? = null,
    val remainingCapacity: Int? = null
)
data class ActivityRegistrationAck(
    val registrationId: String,
    val activityId: String,
    val childId: String? = null,
    val contactName: String? = null,
    val phone: String? = null,
    val status: String,
    val version: Int? = null,
    val createdAt: String? = null,
    val updatedAt: String? = null,
    val cancelledAt: String? = null,
    val activityTitle: String? = null,
    val startsAt: String? = null,
    val endsAt: String? = null
)
data class ExpertAppointmentAck(
    val appointmentId: String,
    val expertId: String? = null,
    val serviceId: String? = null,
    val slotId: String? = null,
    val childId: String? = null,
    val expertName: String? = null,
    val preferredDate: String? = null,
    val scheduledStartAt: String? = null,
    val scheduledEndAt: String? = null,
    val status: String,
    val version: Int? = null,
    val note: String? = null,
    val createdAt: String? = null,
    val updatedAt: String? = null,
    val cancelledAt: String? = null
)
data class TrainingSessionRequest(
    val sessionId: String,
    val dayId: Int,
    val completedAt: String,
    val durationSeconds: Int,
    val completionRatio: Float,
    val qualityScore: Int,
    val cameraVerified: Boolean,
    val visualUnits: Map<String, Int>,
    val manualUnits: Int,
    val modelVersion: String,
    val mode: String = "guidedTraining"
)
data class TrainingSessionRecord(
    val id: String,
    val childId: String,
    val dayId: Int,
    val completedAt: String,
    val durationSeconds: Int,
    val completionRatio: Float,
    val qualityScore: Int,
    val cameraVerified: Boolean,
    val visualUnits: Map<String, Int> = emptyMap(),
    val manualUnits: Int,
    val modelVersion: String,
    val mode: String,
    val createdAt: String? = null,
    val updatedAt: String? = null
)
data class HealthCheckInRequest(
    val checkInDate: String,
    val activityType: String,
    val durationMinutes: Int,
    val intensity: String,
    val feeling: String? = null,
    val completedRecommended: Boolean = false,
    val parentNote: String? = null,
    val expectedVersion: Int? = null
)
data class HealthCheckInRecord(
    val id: String,
    val childId: String,
    val checkInDate: String,
    val activityType: String,
    val durationMinutes: Int,
    val intensity: String,
    val feeling: String? = null,
    val completedRecommended: Boolean = false,
    val parentNote: String? = null,
    val version: Int = 1,
    val createdAt: String? = null,
    val updatedAt: String? = null
)
data class CourseUploadRequest(val taskId: String, val attendanceCount: Int, val notes: String, val attachmentName: String, val attachmentFileId: String)
data class FilePresignRequest(val fileName: String, val contentType: String, val fileSize: Long, val purpose: String)
data class FileUploadTicket(val id: String)
data class FileUploadReceipt(val id: String, val status: String)

interface FileApi {
    @POST("v1/files/presign")
    suspend fun presign(@Body body: FilePresignRequest): ApiEnvelope<FileUploadTicket>

    @PUT("v1/files/{fileId}/content")
    suspend fun upload(@Path("fileId") fileId: String, @Body body: RequestBody): ApiEnvelope<FileUploadReceipt>

    @retrofit2.http.Streaming
    @GET("v1/files/{fileId}/content")
    suspend fun download(@Path("fileId") fileId: String): Response<ResponseBody>
}

interface HealthObservationApi {
    @retrofit2.http.GET("v1/students/{studentId}/health-observations")
    suspend fun list(@retrofit2.http.Path("studentId") studentId: String): ApiEnvelope<List<RemoteHealthObservation>>

    @retrofit2.http.POST("v1/students/{studentId}/health-observations")
    suspend fun submit(@retrofit2.http.Path("studentId") studentId: String, @Body body: HealthObservationRequest): ApiEnvelope<RemoteHealthObservation>
}

data class HealthObservationRequest(
    val category: String,
    val formVersion: String,
    val answers: List<RemoteHealthObservationAnswer>,
    val frequency: String? = null,
    val severity: String? = null,
    val note: String? = null,
    val expectedVersion: Int? = null
)
data class RemoteHealthObservation(
    val id: String,
    val childId: String,
    val category: String,
    val formVersion: String,
    val answers: List<RemoteHealthObservationAnswer> = emptyList(),
    val frequency: String? = null,
    val severity: String? = null,
    val note: String? = null,
    val version: Int? = null,
    val submittedAt: String? = null,
    val updatedAt: String? = null
)
data class RemoteHealthObservationAnswer(
    val questionId: String,
    val questionType: String,
    val selectedOptionIds: List<String> = emptyList(),
    val note: String? = null,
    val required: Boolean = true
)
data class WorkflowTaskStatusRequest(val status: TaskStatus, val note: String? = null, val expectedVersion: Int? = null)
data class ClassPostRequest(
    val author: String,
    val content: String,
    val schoolId: String? = null,
    val classId: String? = null,
    val attachments: List<ClassPostAttachmentRequest> = emptyList()
)
data class ClassPostAttachmentRequest(val id: String, val type: String, val objectId: String, val thumbnailObjectId: String? = null)
data class SupportMessageRequest(val content: String)
