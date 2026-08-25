package com.xiangshang.youth.core.repository

import com.xiangshang.youth.core.model.*
import com.xiangshang.youth.core.service.TaskStudentStatusRecord
import com.xiangshang.youth.core.service.TeacherAnalyticsOverview
import com.xiangshang.youth.core.service.RemoteLesson
import com.xiangshang.youth.core.service.PlaybackSource
import com.xiangshang.youth.core.service.LessonProgressAck
import com.xiangshang.youth.core.service.HealthConsentRecord
import com.xiangshang.youth.core.service.RemoteActivity
import com.xiangshang.youth.core.service.RemoteExpert
import com.xiangshang.youth.core.service.ExpertAvailableSlot
import com.xiangshang.youth.core.service.ActivityRegistrationAck
import com.xiangshang.youth.core.service.ExpertAppointmentAck
import com.xiangshang.youth.core.service.FollowAlongSessionRecord
import com.xiangshang.youth.core.service.TrainingSessionRecord
import com.xiangshang.youth.core.service.ClassPost

data class DashboardData(
    val school: School, val grades: List<Grade>, val classes: List<ClassInfo>,
    val students: List<Student>, val tasks: List<TestTask>, val children: List<ParentChild>,
    val messages: List<MessageItem>,
    /**
     * The dashboard keeps aggregate metrics complete while the student
     * directory is page-limited.  Null means the data source is the bundled
     * MockRepository (or an older service that has not opted into paging).
     */
    val studentTotal: Int? = null,
    val studentPage: Int? = null,
    val studentPageSize: Int? = null
)

interface YouthRepository {
    /** Mock writes are local-only and cannot count as a school-side acknowledgement. */
    val supportsRemoteAcknowledgement: Boolean get() = false
    fun configureSession(profile: UserProfile) {}
    suspend fun bindChild(name: String, code: String): ParentChild { error("服务尚未配置") }
    suspend fun markMessageRead(messageId: String) {}
    suspend fun grantHealthConsent(studentId: String, version: String) {}
    /** Reuses the locally persisted guardian consent ID during retry/sync. */
    suspend fun grantHealthConsent(consent: HealthConsentRecord) = grantHealthConsent(consent.childId, consent.privacyPolicyVersion)
    suspend fun revokeHealthConsent(studentId: String, version: String) {}
    suspend fun submitBodyAssessment(studentId: String, record: BodyAssessmentRecord, consentVersion: String): PostureAssessmentReport? = null
    suspend fun loadHealthObservations(studentId: String): List<com.xiangshang.youth.core.service.FamilyHealthRecord> = emptyList()
    suspend fun submitHealthObservation(studentId: String, category: String, record: com.xiangshang.youth.core.service.FamilyHealthRecord): com.xiangshang.youth.core.service.FamilyHealthRecord = record
    suspend fun loadHealthCheckins(studentId: String, from: String? = null, to: String? = null): List<com.xiangshang.youth.core.service.HealthCheckInRecord> = emptyList()
    suspend fun submitHealthCheckin(record: com.xiangshang.youth.core.service.HealthCheckInRecord, expectedVersion: Int? = null): com.xiangshang.youth.core.service.HealthCheckInRecord = record
    suspend fun dashboard(studentPage: Int? = null, studentPageSize: Int? = null): DashboardData
    suspend fun taskStudentStatuses(taskId: String): List<TaskStudentStatusRecord> = emptyList()
    suspend fun taskStudentRoster(taskId: String, page: Int, pageSize: Int, status: TaskStatus?, keyword: String?): List<TaskStudentStatusRecord> = taskStudentStatuses(taskId)
    suspend fun teacherOverview(schoolId: String, classId: String, taskId: String, standardVersion: String): TeacherAnalyticsOverview? = null
    fun report(student: Student): DiagnosisReport
    /** Mock renders its deterministic local report; RemoteRepository returns an explicit unavailable state until ReportApi responds. */
    suspend fun loadReport(student: Student): DiagnosisReport = report(student)
    suspend fun submitActivity(value: com.xiangshang.youth.core.service.ActivityRegistration): ActivityRegistrationAck =
        ActivityRegistrationAck(value.registrationId ?: value.id, value.activityId, value.childId, value.contactName, value.phone, value.registrationStatus ?: "pending", value.version ?: 1)
    suspend fun updateActivityRegistration(value: com.xiangshang.youth.core.service.ActivityRegistration): ActivityRegistrationAck = submitActivity(value)
    suspend fun cancelActivityRegistration(value: com.xiangshang.youth.core.service.ActivityRegistration): ActivityRegistrationAck =
        ActivityRegistrationAck(value.registrationId ?: value.id, value.activityId, value.childId, value.contactName, value.phone, "cancelled", (value.version ?: 0) + 1)
    suspend fun activityRegistrationHistory(): List<ActivityRegistrationAck> = emptyList()
    suspend fun bookExpert(value: com.xiangshang.youth.core.service.ExpertAppointment): ExpertAppointmentAck =
        ExpertAppointmentAck(value.appointmentId ?: value.id, value.expertId, value.serviceId, value.slotId, value.childId, value.expertName, value.preferredDate, value.scheduledStartAt, value.scheduledEndAt, value.appointmentStatus ?: "pending", value.expectedVersion ?: 1, value.note)
    suspend fun rescheduleExpert(value: com.xiangshang.youth.core.service.ExpertAppointment, slotId: String): ExpertAppointmentAck = bookExpert(value)
    suspend fun cancelExpert(value: com.xiangshang.youth.core.service.ExpertAppointment): ExpertAppointmentAck =
        ExpertAppointmentAck(value.appointmentId ?: value.id, value.expertId, value.serviceId, value.slotId, value.childId, value.expertName, value.preferredDate, value.scheduledStartAt, value.scheduledEndAt, "cancelled", (value.expectedVersion ?: 0) + 1, value.note)
    suspend fun expertAppointmentHistory(): List<ExpertAppointmentAck> = emptyList()
    suspend fun activities(childId: String? = null): List<RemoteActivity> = listOf(RemoteActivity("health-growth-season-2026", title = "向上少年健康成长季", description = "2026 秋季测评，活动时间以学校通知为准。", capacity = 60, registrationEndAt = "2026-09-10", remainingCapacity = 18))
    suspend fun experts(): List<RemoteExpert> = listOf(
        RemoteExpert("expert-zhang-child-sports", name = "张教授", title = "儿童运动发展", bio = "儿童运动发展与家庭训练建议", status = "active"),
        RemoteExpert("expert-li-growth-screening", name = "李医生", title = "儿童健康评估", bio = "成长筛查与家庭观察建议", status = "active"),
        RemoteExpert("expert-wang-youth-training", name = "王教练", title = "青少年运动训练", bio = "动作训练和运动习惯建立", status = "active"),
        RemoteExpert("expert-liu-family-support", name = "刘主任", title = "儿童心理成长", bio = "家庭支持与心理观察", status = "active")
    )
    suspend fun expertSlots(expertId: String): List<ExpertAvailableSlot> = emptyList()
    suspend fun uploadCourse(value: com.xiangshang.youth.core.service.CourseUploadRecord) {}
    /** IDs rather than titles keep progress independent across children and lessons. */
    suspend fun courses(childId: String): List<RemoteLesson> = emptyList()
    suspend fun lessonPlayback(lessonId: String): PlaybackSource { error("服务尚未配置") }
    suspend fun saveLessonProgress(childId: String, lessonId: String, lastPositionMs: Int, completed: Boolean, expectedVersion: Int?): LessonProgressAck =
        LessonProgressAck(lessonId, lastPositionMs, completed, version = 0)
    suspend fun loadFollowAlongSessions(childId: String, from: String? = null, to: String? = null): List<TrainingSessionRecord> = emptyList()
    suspend fun submitFollowAlongSession(record: FollowAlongSessionRecord): TrainingSessionRecord? = null
    /** Returns the acknowledged server version, or null for local/mock stores. */
    suspend fun updateTaskStatus(studentId: String, status: TaskStatus, note: String?, expectedVersion: Int?): Int? = null
    /** Task-aware write; older adapters may fall back to the legacy endpoint. */
    suspend fun updateTaskStatus(taskId: String, studentId: String, status: TaskStatus, note: String?, expectedVersion: Int?): Int? = updateTaskStatus(studentId, status, note, expectedVersion)
    suspend fun batchUpdateTaskStatus(taskId: String, updates: List<com.xiangshang.youth.core.service.TaskStatusBatchItem>): com.xiangshang.youth.core.service.TaskBatchStatusAck = com.xiangshang.youth.core.service.TaskBatchStatusAck()
    suspend fun taskStatusHistory(taskId: String, studentId: String): List<com.xiangshang.youth.core.service.TaskStatusEvent> = emptyList()
    suspend fun publishClassPost(author: String, content: String, schoolId: String? = null, classId: String? = null, attachments: List<com.xiangshang.youth.core.service.ClassPostAttachment> = emptyList()): String? = null
    suspend fun loadClassPosts(schoolId: String?, classId: String?, cursor: String?): ClassPostPage = ClassPostPage()
    suspend fun loadClassPostAttachment(fileId: String): ByteArray = error("服务尚未配置")
    suspend fun deleteClassPost(postId: String) {}
    suspend fun reportClassPost(postId: String, reason: String) {}
    suspend fun setClassPostPinned(postId: String, pinned: Boolean) {}
    suspend fun addClassPostComment(postId: String, content: String): com.xiangshang.youth.core.service.ClassPostCommentAck =
        com.xiangshang.youth.core.service.ClassPostCommentAck("local-${System.currentTimeMillis()}", postId, content = content, status = "pending_sync", ownedByCurrentUser = true)
    suspend fun loadClassPostComments(postId: String, cursor: String?): com.xiangshang.youth.core.service.ClassPostCommentPage = com.xiangshang.youth.core.service.ClassPostCommentPage()
    suspend fun deleteClassPostComment(postId: String, commentId: String) {}
    suspend fun listNotificationDrafts(schoolId: String): List<com.xiangshang.youth.core.service.NotificationCampaign> = emptyList()
    suspend fun loadClassNotice(notificationId: String): com.xiangshang.youth.core.service.NotificationCampaignDetail =
        com.xiangshang.youth.core.service.NotificationCampaignDetail(notificationId, "", title = "班级通知", content = "通知内容将在学校数据同步后显示。")
    suspend fun acknowledgeClassNotice(notificationId: String): com.xiangshang.youth.core.service.NotificationReceiptAck =
        com.xiangshang.youth.core.service.NotificationReceiptAck(notificationId = notificationId, status = "pending_sync")
    suspend fun createNotificationDraft(schoolId: String, classIds: List<String>, title: String, content: String, recipientScope: String = "class", scheduledAt: String? = null, parentReceiptEnabled: Boolean = false): com.xiangshang.youth.core.service.NotificationCampaign =
        com.xiangshang.youth.core.service.NotificationCampaign("local-${System.currentTimeMillis()}", schoolId, title = title, content = content, targetClassIds = classIds, recipientScope = recipientScope, scheduledAt = scheduledAt, status = "draft", parentReceiptEnabled = parentReceiptEnabled)
    suspend fun updateNotificationDraft(notificationId: String, schoolId: String, classIds: List<String>, title: String, content: String, draftVersion: Int, recipientScope: String = "class", scheduledAt: String? = null, parentReceiptEnabled: Boolean = false): com.xiangshang.youth.core.service.NotificationCampaign =
        com.xiangshang.youth.core.service.NotificationCampaign(notificationId, schoolId, title = title, content = content, targetClassIds = classIds, recipientScope = recipientScope, scheduledAt = scheduledAt, status = "draft", draftVersion = draftVersion + 1, parentReceiptEnabled = parentReceiptEnabled)
    suspend fun sendNotification(notificationId: String): com.xiangshang.youth.core.service.NotificationCampaignReceipt = com.xiangshang.youth.core.service.NotificationCampaignReceipt(notificationId, "", "pending_sync")
    suspend fun retryNotification(notificationId: String): com.xiangshang.youth.core.service.NotificationCampaignReceipt = sendNotification(notificationId)
    suspend fun discardNotificationDraft(notificationId: String) {}
    suspend fun sendClassNotice(schoolId: String, classId: String, title: String, content: String): com.xiangshang.youth.core.service.NotificationCampaignReceipt = com.xiangshang.youth.core.service.NotificationCampaignReceipt("local-${System.currentTimeMillis()}", title, "pending_sync")
    suspend fun sendSupportMessage(content: String) {}
    suspend fun submitPrivacyRequest(studentId: String, requestType: String) {}
    suspend fun submitAccountDeletionRequest() {}
}

data class ClassPostPage(val posts: List<ClassPost> = emptyList(), val nextCursor: String? = null)
