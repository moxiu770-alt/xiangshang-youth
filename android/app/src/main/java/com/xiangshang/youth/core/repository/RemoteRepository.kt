package com.xiangshang.youth.core.repository
import com.xiangshang.youth.core.mock.MockRepository
import com.xiangshang.youth.core.model.*
import com.xiangshang.youth.core.service.ApiClient
import com.xiangshang.youth.core.service.ReportApi
import com.xiangshang.youth.core.service.StatsApi
import com.xiangshang.youth.core.service.WorkflowApi
import com.xiangshang.youth.core.service.ActivityRegistrationRequest
import com.xiangshang.youth.core.service.ExpertAppointmentRequest
import com.xiangshang.youth.core.service.CourseUploadRequest
import com.xiangshang.youth.core.service.WorkflowTaskStatusRequest
import com.xiangshang.youth.core.service.ClassPostRequest
import com.xiangshang.youth.core.service.SupportMessageRequest

/**
 * Remote endpoints are enabled by RepositoryProvider when backend wiring is available.
 * Report rendering keeps a typed local fallback so a temporarily unavailable endpoint never
 * crashes a student-detail route during a staged rollout.
 */
class RemoteRepository(
    private val statsApi: StatsApi = ApiClient.retrofit.create(StatsApi::class.java),
    private val reportApi: ReportApi = ApiClient.retrofit.create(ReportApi::class.java),
    private val workflowApi: WorkflowApi = ApiClient.retrofit.create(WorkflowApi::class.java),
    private val reportFallback: YouthRepository = MockRepository()
) : YouthRepository {
    override suspend fun dashboard(): DashboardData = statsApi.dashboard("school-1")
    override fun report(student: Student): DiagnosisReport = reportFallback.report(student)
    override suspend fun loadReport(student: Student): DiagnosisReport = reportApi.report(student.id)
    override suspend fun submitActivity(value: com.xiangshang.youth.core.service.ActivityRegistration) {
        workflowApi.registerActivity(value.activityId, ActivityRegistrationRequest(value.contactName, value.phone))
    }
    override suspend fun bookExpert(value: com.xiangshang.youth.core.service.ExpertAppointment) {
        workflowApi.bookExpert(ExpertAppointmentRequest(value.expertName, value.preferredDate, value.note))
    }
    override suspend fun uploadCourse(value: com.xiangshang.youth.core.service.CourseUploadRecord) {
        workflowApi.uploadCourse(CourseUploadRequest(value.taskId, value.attendanceCount, value.notes, value.attachmentName))
    }
    override suspend fun updateTaskStatus(studentId: String, status: TaskStatus, note: String?) {
        workflowApi.updateTaskStatus(studentId, WorkflowTaskStatusRequest(status, note))
    }
    override suspend fun publishClassPost(author: String, content: String) {
        workflowApi.publishClassPost(ClassPostRequest(author, content))
    }
    override suspend fun sendSupportMessage(content: String) {
        workflowApi.sendSupportMessage(SupportMessageRequest(content))
    }
}
