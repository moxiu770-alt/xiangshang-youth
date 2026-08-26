package com.xiangshang.youth.core.repository
import com.xiangshang.youth.core.model.*
import com.xiangshang.youth.BuildConfig
import com.xiangshang.youth.core.service.ApiClient
import com.xiangshang.youth.core.service.ApiError
import com.xiangshang.youth.core.service.requireData
import com.xiangshang.youth.core.service.ReportApi
import com.xiangshang.youth.core.service.StatsApi
import com.xiangshang.youth.core.service.WorkflowApi
import com.xiangshang.youth.core.service.TaskApi
import com.xiangshang.youth.core.service.ActivityRegistrationRequest
import com.xiangshang.youth.core.service.ActivityRegistrationUpdateRequest
import com.xiangshang.youth.core.service.ExpertAppointmentRequest
import com.xiangshang.youth.core.service.ExpertRescheduleRequest
import com.xiangshang.youth.core.service.CourseUploadRequest
import com.xiangshang.youth.core.service.FileApi
import com.xiangshang.youth.core.service.FilePresignRequest
import com.xiangshang.youth.core.service.ClassPostRequest
import com.xiangshang.youth.core.service.ClassPostAttachmentRequest
import com.xiangshang.youth.core.service.SupportMessageRequest
import com.xiangshang.youth.core.service.StudentApi
import com.xiangshang.youth.core.service.AccountApi
import com.xiangshang.youth.core.service.EmptyAccountRequest
import com.xiangshang.youth.core.service.MessageApi
import com.xiangshang.youth.core.service.NotificationApi
import com.xiangshang.youth.core.service.NotificationCampaignRequest
import com.xiangshang.youth.core.service.BindingRequest
import com.xiangshang.youth.core.service.ConsentRequest
import com.xiangshang.youth.core.service.BodyAssessmentRequest
import com.xiangshang.youth.core.service.BodySnapshotRequest
import com.xiangshang.youth.core.service.CourseAttachmentStore
import com.xiangshang.youth.core.service.CourseApi
import com.xiangshang.youth.core.service.LessonProgressWrite
import com.xiangshang.youth.core.service.LessonProgressAck
import com.xiangshang.youth.core.service.PlaybackSource
import com.xiangshang.youth.core.service.RemoteLesson
import com.xiangshang.youth.core.service.HealthConsentRecord
import com.xiangshang.youth.core.service.HealthObservationApi
import com.xiangshang.youth.core.service.ClassPostApi
import com.xiangshang.youth.core.service.ClassPost
import com.xiangshang.youth.core.service.ClassPostAttachment
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.service.FollowAlongSessionRecord
import com.xiangshang.youth.core.service.TrainingSessionRecord
import com.xiangshang.youth.core.service.TrainingSessionRequest
import com.xiangshang.youth.core.service.HealthObservationRequest
import com.xiangshang.youth.core.service.RemoteHealthObservation
import com.xiangshang.youth.core.service.RemoteHealthObservationAnswer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.security.MessageDigest

/**
 * Remote endpoints are enabled by RepositoryProvider when backend wiring is available.
 * A report that has not been returned by the school service is represented as an explicit
 * unavailable state; bundled Mock scores are never shown as if they were remote results.
 */
class RemoteRepository(
    private val statsApi: StatsApi = ApiClient.retrofit.create(StatsApi::class.java),
    private val reportApi: ReportApi = ApiClient.retrofit.create(ReportApi::class.java),
    private val workflowApi: WorkflowApi = ApiClient.retrofit.create(WorkflowApi::class.java),
    private val taskApi: TaskApi = ApiClient.retrofit.create(TaskApi::class.java),
    private val fileApi: FileApi = ApiClient.retrofit.create(FileApi::class.java),
    private val studentApi: StudentApi = ApiClient.retrofit.create(StudentApi::class.java),
    private val messageApi: MessageApi = ApiClient.retrofit.create(MessageApi::class.java),
    private val accountApi: AccountApi = ApiClient.retrofit.create(AccountApi::class.java),
    private val courseApi: CourseApi = ApiClient.retrofit.create(CourseApi::class.java),
    private val notificationApi: NotificationApi = ApiClient.retrofit.create(NotificationApi::class.java),
    private val healthObservationApi: HealthObservationApi = ApiClient.retrofit.create(HealthObservationApi::class.java),
    private val classPostApi: ClassPostApi = ApiClient.retrofit.create(ClassPostApi::class.java),
    private var schoolId: String = BuildConfig.SCHOOL_ID
) : YouthRepository {
    override val supportsRemoteAcknowledgement: Boolean = true
    override fun configureSession(profile: UserProfile) { profile.schoolId?.takeIf { it.isNotBlank() }?.let { schoolId = it } }
    override suspend fun dashboard(studentPage: Int?, studentPageSize: Int?): DashboardData = statsApi.dashboard(
        schoolId,
        // Never request an unbounded student directory on a production device.
        // Aggregates remain school-wide; the list is loaded incrementally.
        studentPage ?: 1,
        (studentPageSize ?: 100).coerceIn(1, 100)
    ).data ?: throw ApiError.InvalidResponse
    override fun report(student: Student): DiagnosisReport = DiagnosisReport.unavailable(student)
    override suspend fun loadReport(student: Student): DiagnosisReport = reportApi.report(student.id).data ?: throw ApiError.InvalidResponse
    override suspend fun bindChild(name: String, code: String): ParentChild = studentApi.bindChild(BindingRequest(name, code)).data ?: throw ApiError.InvalidResponse
    override suspend fun markMessageRead(messageId: String) { messageApi.markRead(messageId) }
    override suspend fun grantHealthConsent(studentId: String, version: String) { studentApi.grantConsent(studentId, ConsentRequest(version), "consent-$studentId-$version".sha256()) }
    override suspend fun grantHealthConsent(consent: HealthConsentRecord) {
        studentApi.grantConsent(consent.childId, ConsentRequest(
            consentVersion = consent.privacyPolicyVersion,
            consentId = consent.consentId,
            privacyPolicyVersion = consent.privacyPolicyVersion,
            cameraConsentVersion = consent.cameraConsentVersion,
            algorithmNoticeVersion = consent.algorithmNoticeVersion,
            deviceInfoHash = consent.deviceInfo.sha256(),
            appVersion = BuildConfig.VERSION_NAME,
            dataRetentionNoticeAccepted = consent.dataRetentionNoticeAccepted
        ), "consent-${consent.consentId}".sha256())
    }
    override suspend fun loadHealthObservations(studentId: String): List<com.xiangshang.youth.core.service.FamilyHealthRecord> =
        healthObservationApi.list(studentId).requireData().map(::toLocalHealthRecord)

    override suspend fun submitHealthObservation(studentId: String, category: String, record: com.xiangshang.youth.core.service.FamilyHealthRecord): com.xiangshang.youth.core.service.FamilyHealthRecord {
        val answers = record.structuredAnswers.map { answer ->
            RemoteHealthObservationAnswer(answer.questionId, answer.questionType, answer.selectedOptionIds, answer.note, answer.required)
        }
        // The local record version is the post-edit version. Send the version
        // read before this edit (0 for a new record) for optimistic locking.
        val expectedVersion = record.version?.let { (it - 1).coerceAtLeast(0) }
        return healthObservationApi.submit(studentId, HealthObservationRequest(category, record.formVersion ?: "family-observation-v1", answers, record.frequency, record.severity, record.entries["补充说明"], expectedVersion)).data?.let(::toLocalHealthRecord) ?: throw ApiError.InvalidResponse
    }

    override suspend fun loadClassPosts(schoolId: String?, classId: String?, cursor: String?): ClassPostPage {
        val page = classPostApi.list(schoolId, classId, cursor).data ?: throw ApiError.InvalidResponse
        return ClassPostPage(page.items.map { remote ->
            ClassPost(
                author = remote.displayName ?: "班级成员",
                content = remote.content,
                status = LocalSubmissionStatus.Submitted,
                postId = remote.postId,
                classId = remote.classId,
                displayName = remote.displayName,
                visibilityScope = remote.visibilityScope,
                moderationStatus = remote.moderationStatus,
                pinned = remote.pinned == true,
                reportStatus = remote.reportStatus,
                attachments = remote.attachments.orEmpty().map { ClassPostAttachment(it.id, it.type, it.objectId, null, it.thumbnailObjectId) },
                authorRole = remote.authorRole,
                ownedByCurrentUser = remote.ownedByCurrentUser == true
            )
        }, page.nextCursor)
    }
    override suspend fun loadClassPostAttachment(fileId: String): ByteArray {
        val response = fileApi.download(fileId)
        if (!response.isSuccessful) throw ApiError.Client("附件暂时无法打开")
        return response.body()?.bytes() ?: throw ApiError.InvalidResponse
    }
    override suspend fun deleteClassPost(postId: String) {
        classPostApi.delete(postId, "class-post-delete-$postId")
    }
    override suspend fun reportClassPost(postId: String, reason: String) {
        classPostApi.report(postId, com.xiangshang.youth.core.service.ClassPostReportRequest(reason), "class-post-report-${("$postId:$reason").sha256()}")
    }
    override suspend fun setClassPostPinned(postId: String, pinned: Boolean) {
        classPostApi.pin(postId, com.xiangshang.youth.core.service.ClassPostPinRequest(pinned), "class-post-pin-$postId-$pinned")
    }
    override suspend fun addClassPostComment(postId: String, content: String): com.xiangshang.youth.core.service.ClassPostCommentAck {
        return classPostApi.addComment(postId, com.xiangshang.youth.core.service.ClassPostCommentRequest(content), "class-post-comment-${("$postId:$content").sha256()}").data
            ?: throw ApiError.InvalidResponse
    }
    override suspend fun loadClassPostComments(postId: String, cursor: String?): com.xiangshang.youth.core.service.ClassPostCommentPage {
        return classPostApi.comments(postId, cursor).data ?: throw ApiError.InvalidResponse
    }
    override suspend fun deleteClassPostComment(postId: String, commentId: String) {
        classPostApi.deleteComment(postId, commentId, "class-post-comment-delete-$postId-$commentId")
    }

    private fun toLocalHealthRecord(remote: RemoteHealthObservation): com.xiangshang.youth.core.service.FamilyHealthRecord {
        val entries = remote.answers.associate { it.questionId to it.selectedOptionIds.joinToString("、") }
        return com.xiangshang.youth.core.service.FamilyHealthRecord(
            childId = remote.childId,
            category = remote.category,
            completedAt = remote.submittedAt ?: remote.updatedAt.orEmpty(),
            entries = entries,
            formVersion = remote.formVersion,
            submittedAt = remote.submittedAt,
            version = remote.version,
            frequency = remote.frequency,
            severity = remote.severity,
            structuredAnswers = remote.answers.map { com.xiangshang.youth.core.service.HealthObservationAnswer(it.questionId, it.questionType, it.selectedOptionIds, it.note, it.required) }
        )
    }
    override suspend fun revokeHealthConsent(studentId: String, version: String) { studentApi.revokeConsent(studentId, ConsentRequest(version, granted = false), "consent-revoke-$studentId-$version".sha256()) }
    override suspend fun submitBodyAssessment(studentId: String, record: BodyAssessmentRecord, consentVersion: String): PostureAssessmentReport? {
        val snapshots = record.postureReport?.snapshots.orEmpty().map { (task, snapshot) -> BodySnapshotRequest(task.apiCode, snapshot.sampleCount, snapshot.confidence, snapshot) }
        val key = "body-assessment-$studentId-${record.measuredAt}-${record.postureReport?.algorithm ?: BodyAssessmentRecord.ruleVersion}".sha256()
        val response = studentApi.submitBodyAssessment(studentId, BodyAssessmentRequest(record.heightCm, record.weightKg, record.postureReport?.overallLevel?.name?.lowercase() ?: "pending", record.postureReport?.algorithm ?: BodyAssessmentRecord.ruleVersion, consentVersion, record, snapshots), key).data
            ?: throw ApiError.InvalidResponse
        if (response.bmiAlgorithmVersion != BodyAssessmentRecord.bmiAlgorithmVersion) {
            throw ApiError.ModelContract("服务端返回了未支持的 BMI 算法版本：${response.bmiAlgorithmVersion ?: "missing"}")
        }
        if (response.heightAlgorithmVersion != BodyAssessmentRecord.heightAlgorithmVersion) {
            throw ApiError.ModelContract("服务端返回了未支持的身高算法版本：${response.heightAlgorithmVersion ?: "missing"}")
        }
        if (response.modelRegistryVersion != AssessmentScoreRules.modelRegistryVersion) {
            throw ApiError.ModelContract("服务端返回了未支持的模型注册表版本：${response.modelRegistryVersion ?: "missing"}")
        }
        val summary = response.postureReport ?: return null
        if (summary.algorithm != PostureAssessmentReport.algorithmVersion) {
            throw ApiError.ModelContract("服务端返回了未支持的姿态算法版本：${summary.algorithm}")
        }
        if (summary.calibrationVersion != PostureAssessmentReport.calibrationVersion) {
            throw ApiError.ModelContract("服务端返回了未支持的标定版本：${summary.calibrationVersion}")
        }
        if (summary.rulesSourceVersion != PostureScreeningRules.rulesSourceVersion) {
            throw ApiError.ModelContract("服务端返回了未支持的姿态规则版本：${summary.rulesSourceVersion}")
        }
        val local = record.postureReport ?: return null
        val level = runCatching { BodyAttentionLevel.valueOf(summary.overallLevel.replaceFirstChar { it.uppercase() }) }.getOrDefault(local.overallLevel)
        return local.copy(algorithm = summary.algorithm, overallLevel = level, reasons = summary.reasons, disclaimer = summary.disclaimer, riskScore = summary.riskScore, qualityScore = summary.qualityScore, calibrationVersion = summary.calibrationVersion, rulesSourceVersion = summary.rulesSourceVersion)
    }
    override suspend fun submitActivity(value: com.xiangshang.youth.core.service.ActivityRegistration): com.xiangshang.youth.core.service.ActivityRegistrationAck =
        workflowApi.registerActivity(value.activityId, ActivityRegistrationRequest(value.contactName, value.phone, value.childId), "activity-register-${value.id.sha256()}").data ?: throw ApiError.InvalidResponse
    override suspend fun updateActivityRegistration(value: com.xiangshang.youth.core.service.ActivityRegistration): com.xiangshang.youth.core.service.ActivityRegistrationAck =
        value.registrationId?.let { registrationId -> workflowApi.updateActivityRegistration(value.activityId, registrationId, ActivityRegistrationUpdateRequest(value.contactName, value.phone, value.childId, value.version), "activity-update-${("$registrationId:${value.version ?: 0}:${value.id}").sha256()}").data ?: throw ApiError.InvalidResponse }
            ?: submitActivity(value)
    override suspend fun cancelActivityRegistration(value: com.xiangshang.youth.core.service.ActivityRegistration): com.xiangshang.youth.core.service.ActivityRegistrationAck =
        workflowApi.cancelActivityRegistration(value.activityId, value.registrationId ?: throw ApiError.Client("缺少报名记录编号，请刷新后重试"), com.xiangshang.youth.core.service.CancellationRequest(value.version), "activity-cancel-${("${value.registrationId}:${value.version ?: 0}").sha256()}").data ?: throw ApiError.InvalidResponse
    override suspend fun activityRegistrationHistory(): List<com.xiangshang.youth.core.service.ActivityRegistrationAck> =
        workflowApi.activityRegistrationHistory().requireData()
    override suspend fun bookExpert(value: com.xiangshang.youth.core.service.ExpertAppointment): com.xiangshang.youth.core.service.ExpertAppointmentAck =
        workflowApi.bookExpert(ExpertAppointmentRequest(value.expertName, value.preferredDate, value.note, value.expertId, value.serviceId, value.slotId, value.childId), "expert-book-${value.id.sha256()}").data ?: throw ApiError.InvalidResponse
    override suspend fun rescheduleExpert(value: com.xiangshang.youth.core.service.ExpertAppointment, slotId: String): com.xiangshang.youth.core.service.ExpertAppointmentAck =
        workflowApi.rescheduleExpert(value.appointmentId ?: throw ApiError.Client("缺少预约记录编号，请刷新后重试"), ExpertRescheduleRequest(slotId, value.expectedVersion), "expert-reschedule-${("${value.appointmentId}:$slotId:${value.expectedVersion ?: 0}").sha256()}").data ?: throw ApiError.InvalidResponse
    override suspend fun cancelExpert(value: com.xiangshang.youth.core.service.ExpertAppointment): com.xiangshang.youth.core.service.ExpertAppointmentAck =
        workflowApi.cancelExpert(value.appointmentId ?: throw ApiError.Client("缺少预约记录编号，请刷新后重试"), com.xiangshang.youth.core.service.CancellationRequest(value.expectedVersion), "expert-cancel-${("${value.appointmentId}:${value.expectedVersion ?: 0}").sha256()}").data ?: throw ApiError.InvalidResponse
    override suspend fun expertAppointmentHistory(): List<com.xiangshang.youth.core.service.ExpertAppointmentAck> =
        workflowApi.expertAppointmentHistory().requireData()
    override suspend fun activities(childId: String?): List<com.xiangshang.youth.core.service.RemoteActivity> =
        workflowApi.activities(childId).requireData()
    override suspend fun experts(): List<com.xiangshang.youth.core.service.RemoteExpert> =
        workflowApi.experts().requireData()
    override suspend fun expertSlots(expertId: String): List<com.xiangshang.youth.core.service.ExpertAvailableSlot> =
        workflowApi.availableSlots(expertId).requireData()
    override suspend fun uploadCourse(value: com.xiangshang.youth.core.service.CourseUploadRecord) {
        val attachment = withContext(Dispatchers.IO) { CourseAttachmentStore.read(value.attachmentReference) }
        val ticket = fileApi.presign(FilePresignRequest(attachment.file.name, attachment.mimeType, attachment.file.length(), "course_upload_attachment")).data
            ?: throw ApiError.InvalidResponse
        val receipt = fileApi.upload(ticket.id, attachment.requestBody()).data ?: throw ApiError.InvalidResponse
        if (receipt.status != "uploaded") throw ApiError.ModelContract("附件上传未完成")
        val operationKey = "${value.taskId}|${value.attendanceCount}|${value.notes}|${receipt.id}".sha256()
        workflowApi.uploadCourse(CourseUploadRequest(value.taskId, value.attendanceCount, value.notes, value.attachmentName, receipt.id), "course-upload-$operationKey")
    }
    override suspend fun courses(childId: String): List<RemoteLesson> =
        courseApi.courses(childId).requireData()
    override suspend fun lessonPlayback(lessonId: String): PlaybackSource =
        courseApi.playback(lessonId).data ?: throw ApiError.InvalidResponse
    override suspend fun saveLessonProgress(childId: String, lessonId: String, lastPositionMs: Int, completed: Boolean, expectedVersion: Int?): LessonProgressAck =
        courseApi.saveProgress(childId, lessonId, LessonProgressWrite(lastPositionMs, completed, expectedVersion)).data
            ?: throw ApiError.InvalidResponse
    override suspend fun loadFollowAlongSessions(childId: String, from: String?, to: String?): List<TrainingSessionRecord> =
        workflowApi.trainingSessions(childId, from, to).requireData()
    override suspend fun submitFollowAlongSession(record: FollowAlongSessionRecord): TrainingSessionRecord =
        workflowApi.submitTrainingSession(record.childId, TrainingSessionRequest(record.id, record.dayId, record.completedAt, record.durationSeconds, record.completionRatio, record.qualityScore, record.cameraVerified, record.visualUnits, record.manualUnits, record.modelVersion, record.mode)).data
            ?: throw ApiError.InvalidResponse
    override suspend fun loadHealthCheckins(studentId: String, from: String?, to: String?): List<com.xiangshang.youth.core.service.HealthCheckInRecord> =
        workflowApi.healthCheckins(studentId, from, to).requireData()
    override suspend fun submitHealthCheckin(record: com.xiangshang.youth.core.service.HealthCheckInRecord, expectedVersion: Int?): com.xiangshang.youth.core.service.HealthCheckInRecord =
        workflowApi.submitHealthCheckin(record.childId, com.xiangshang.youth.core.service.HealthCheckInRequest(record.checkInDate, record.activityType, record.durationMinutes, record.intensity, record.feeling, record.completedRecommended, record.parentNote, expectedVersion)).data
            ?: throw ApiError.InvalidResponse
    override suspend fun updateTaskStatus(taskId: String, studentId: String, status: TaskStatus, note: String?, expectedVersion: Int?): Int? {
        require(taskId.isNotBlank() && taskId != "unscoped") { "任务编号缺失，无法更新学生测评状态" }
        val operationId = java.util.UUID.randomUUID().toString()
        return taskApi.updateStatus(taskId, studentId, com.xiangshang.youth.core.service.TaskStatusRequest(status, note, expectedVersion, operationId), "task-status-${operationId.sha256()}").data?.version
    }
    override suspend fun batchUpdateTaskStatus(taskId: String, updates: List<com.xiangshang.youth.core.service.TaskStatusBatchItem>): com.xiangshang.youth.core.service.TaskBatchStatusAck {
        val operationKey = updates.map { it.clientOperationId }.sorted().joinToString(",")
        return taskApi.batchUpdateStatus(taskId, com.xiangshang.youth.core.service.TaskBatchStatusRequest(updates), "task-batch-status-${operationKey.sha256()}").requireData()
    }
    override suspend fun taskStatusHistory(taskId: String, studentId: String): List<com.xiangshang.youth.core.service.TaskStatusEvent> = taskApi.statusHistory(taskId, studentId).requireData()
    override suspend fun taskStudentStatuses(taskId: String): List<com.xiangshang.youth.core.service.TaskStudentStatusRecord> {
        return taskApi.taskStudents(taskId).requireData()
    }
    override suspend fun taskStudentRoster(taskId: String, page: Int, pageSize: Int, status: TaskStatus?, keyword: String?): List<com.xiangshang.youth.core.service.TaskStudentStatusRecord> {
        return taskApi.taskStudents(taskId, page, pageSize.coerceIn(1, 200), status?.label, keyword).requireData()
    }
    override suspend fun teacherOverview(schoolId: String, classId: String, taskId: String, standardVersion: String): com.xiangshang.youth.core.service.TeacherAnalyticsOverview? =
        statsApi.teacherOverview(schoolId, classId, taskId, standardVersion).data
    override suspend fun publishClassPost(author: String, content: String, schoolId: String?, classId: String?, attachments: List<com.xiangshang.youth.core.service.ClassPostAttachment>): String? {
        val uploaded = attachments.map { attachment ->
            val objectId = attachment.objectId ?: run {
                val stored = withContext(Dispatchers.IO) { CourseAttachmentStore.read(attachment.localReference) }
                val ticket = fileApi.presign(FilePresignRequest(stored.file.name, stored.mimeType, stored.file.length(), "class_post_attachment")).data
                    ?: throw ApiError.InvalidResponse
                val receipt = fileApi.upload(ticket.id, stored.requestBody()).data ?: throw ApiError.InvalidResponse
                if (receipt.status != "uploaded") throw ApiError.ModelContract("班级圈附件上传未完成")
                receipt.id
            }
            ClassPostAttachmentRequest(attachment.id, attachment.type, objectId, attachment.thumbnailObjectId)
        }
        val operationKey = listOf(
            schoolId.orEmpty(), classId.orEmpty(), author, content,
            uploaded.map { it.objectId }.sorted().joinToString(",")
        ).joinToString("|").sha256()
        return workflowApi.publishClassPost(ClassPostRequest(author, content, schoolId, classId, uploaded), "class-post-create-$operationKey").data?.postId
    }
    override suspend fun listNotificationDrafts(schoolId: String): List<com.xiangshang.youth.core.service.NotificationCampaign> {
        return notificationApi.drafts(schoolId).requireData()
    }
    override suspend fun loadClassNotice(notificationId: String): com.xiangshang.youth.core.service.NotificationCampaignDetail {
        return notificationApi.detail(notificationId).data ?: throw ApiError.InvalidResponse
    }
    override suspend fun acknowledgeClassNotice(notificationId: String): com.xiangshang.youth.core.service.NotificationReceiptAck {
        return notificationApi.acknowledgeReceipt(notificationId, idempotencyKey = "notification-receipt-$notificationId").data ?: throw ApiError.InvalidResponse
    }
    override suspend fun createNotificationDraft(schoolId: String, classIds: List<String>, title: String, content: String, recipientScope: String, scheduledAt: String?, parentReceiptEnabled: Boolean): com.xiangshang.youth.core.service.NotificationCampaign {
        val targets = classIds.distinct().filter { it.isNotBlank() }
        return notificationApi.createDraft(NotificationCampaignRequest(schoolId, targets.firstOrNull().orEmpty(), title, content, status = "draft", targetClassIds = targets, recipientScope = recipientScope, scheduledAt = scheduledAt, parentReceiptEnabled = parentReceiptEnabled), "notification-create-${("$schoolId:${targets.sorted()}:$title:$content:${scheduledAt.orEmpty()}").sha256()}").data ?: throw ApiError.InvalidResponse
    }
    override suspend fun updateNotificationDraft(notificationId: String, schoolId: String, classIds: List<String>, title: String, content: String, draftVersion: Int, recipientScope: String, scheduledAt: String?, parentReceiptEnabled: Boolean): com.xiangshang.youth.core.service.NotificationCampaign {
        val targets = classIds.distinct().filter { it.isNotBlank() }
        return notificationApi.updateDraft(notificationId, NotificationCampaignRequest(schoolId, targets.firstOrNull().orEmpty(), title, content, status = "draft", targetClassIds = targets, recipientScope = recipientScope, scheduledAt = scheduledAt, parentReceiptEnabled = parentReceiptEnabled, draftVersion = draftVersion), "notification-update-${("$notificationId:$draftVersion:$title:$content").sha256()}").data ?: throw ApiError.InvalidResponse
    }
    override suspend fun sendNotification(notificationId: String): com.xiangshang.youth.core.service.NotificationCampaignReceipt {
        return notificationApi.sendDraft(notificationId, idempotencyKey = "notification-send-$notificationId").data ?: throw ApiError.InvalidResponse
    }
    override suspend fun retryNotification(notificationId: String): com.xiangshang.youth.core.service.NotificationCampaignReceipt {
        return notificationApi.retry(notificationId, idempotencyKey = "notification-retry-$notificationId").data ?: throw ApiError.InvalidResponse
    }
    override suspend fun discardNotificationDraft(notificationId: String) {
        notificationApi.discard(notificationId, idempotencyKey = "notification-discard-$notificationId")
    }
    override suspend fun sendClassNotice(schoolId: String, classId: String, title: String, content: String): com.xiangshang.youth.core.service.NotificationCampaignReceipt {
        return notificationApi.send(NotificationCampaignRequest(schoolId, classId, title, content)).data ?: throw ApiError.InvalidResponse
    }
    override suspend fun sendSupportMessage(content: String) {
        workflowApi.sendSupportMessage(SupportMessageRequest(content))
    }
    override suspend fun submitPrivacyRequest(studentId: String, requestType: String) {
        studentApi.submitPrivacyRequest(studentId, com.xiangshang.youth.core.service.PrivacyRequestBody(requestType)).data
            ?: throw ApiError.InvalidResponse
    }
    override suspend fun submitAccountDeletionRequest() {
        accountApi.submitDeletionRequest(EmptyAccountRequest()).data ?: throw ApiError.InvalidResponse
    }
}

private fun String.sha256(): String = MessageDigest.getInstance("SHA-256")
    .digest(toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
