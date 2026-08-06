package com.xiangshang.youth.core.service

import com.xiangshang.youth.core.model.TaskStatus
import com.xiangshang.youth.core.model.TestTask
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Body
import retrofit2.http.Path
import retrofit2.http.Query

data class TaskStatusRequest(val status: TaskStatus, val note: String? = null)

interface TaskApi {
    @GET("v1/schools/{schoolId}/tasks")
    suspend fun tasks(@Path("schoolId") schoolId: String, @Query("gradeId") gradeId: String? = null, @Query("classId") classId: String? = null): List<TestTask>

    @PATCH("v1/tasks/{taskId}/students/{studentId}/status")
    suspend fun updateStatus(@Path("taskId") taskId: String, @Path("studentId") studentId: String, @retrofit2.http.Body body: TaskStatusRequest)
}

/** Write-side command boundary kept beside the read APIs for staged rollout. */
interface WorkflowApi {
    @POST("v1/activities/{activityId}/registrations")
    suspend fun registerActivity(@Path("activityId") activityId: String, @Body body: ActivityRegistrationRequest)

    @POST("v1/expert-appointments")
    suspend fun bookExpert(@Body body: ExpertAppointmentRequest)

    @POST("v1/courses/uploads")
    suspend fun uploadCourse(@Body body: CourseUploadRequest)

    @PATCH("v1/students/{studentId}/task-status")
    suspend fun updateTaskStatus(@Path("studentId") studentId: String, @Body body: WorkflowTaskStatusRequest)

    @POST("v1/class-posts")
    suspend fun publishClassPost(@Body body: ClassPostRequest)

    @POST("v1/support/messages")
    suspend fun sendSupportMessage(@Body body: SupportMessageRequest)
}

data class ActivityRegistrationRequest(val contactName: String, val phone: String)
data class ExpertAppointmentRequest(val expertName: String, val preferredDate: String, val note: String)
data class CourseUploadRequest(val taskId: String, val attendanceCount: Int, val notes: String, val attachmentName: String)
data class WorkflowTaskStatusRequest(val status: TaskStatus, val note: String? = null)
data class ClassPostRequest(val author: String, val content: String)
data class SupportMessageRequest(val content: String)
