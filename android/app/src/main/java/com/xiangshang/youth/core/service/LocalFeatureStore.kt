package com.xiangshang.youth.core.service

import android.content.Context
import com.xiangshang.youth.core.model.TaskStatus
import com.xiangshang.youth.core.model.BodyAssessmentRecord
import com.xiangshang.youth.core.model.BodyCaptureTask
import com.xiangshang.youth.core.model.BodyAssessmentDraft
import org.json.JSONArray
import org.json.JSONObject
import com.xiangshang.youth.core.util.BusinessClock

data class LocalFeatureState(
    val activityRegistered: Boolean = false,
    val activityRegistrations: List<ActivityRegistration> = emptyList(),
    val completedAssessments: Set<String> = emptySet(),
    /** Completed family observations remain available after draft cleanup. */
    val familyHealthRecords: Map<String, FamilyHealthRecord> = emptyMap(),
    val healthObservationSyncStates: Map<String, LocalSubmissionStatus> = emptyMap(),
    val bodyAssessments: Map<String, BodyAssessmentRecord> = emptyMap(),
    val bodyAssessmentHistory: Map<String, List<BodyAssessmentRecord>> = emptyMap(),
    val bodyAssessmentDrafts: Map<String, BodyAssessmentDraft> = emptyMap(),
    /** Remote acknowledgement state for completed family body assessments. */
    val bodyAssessmentSyncStates: Map<String, LocalSubmissionStatus> = emptyMap(),
    val healthConsents: Map<String, HealthConsentRecord> = emptyMap(),
    val courseProgress: Map<String, Float> = emptyMap(),
    /** Guided-training receipts; raw camera frames are never persisted. */
    val followAlongSessions: List<FollowAlongSessionRecord> = emptyList(),
    val followAlongSyncStates: Map<String, LocalSubmissionStatus> = emptyMap(),
    val supportMessages: List<SupportMessage> = emptyList(),
    val classPosts: List<ClassPost> = emptyList(),
    val likedPostIds: Set<String> = emptySet(),
    val postComments: Map<String, List<String>> = emptyMap(),
    val uploadedTaskIds: Set<String> = emptySet(),
    val checkedInToday: Boolean = false,
    val checkedInDate: String? = null,
    val checkedInDates: Set<String> = emptySet(),
    val healthCheckins: List<HealthCheckInRecord> = emptyList(),
    val healthCheckinSyncStates: Map<String, LocalSubmissionStatus> = emptyMap(),
    val drafts: Map<String, String> = emptyMap(),
    val expertAppointments: List<ExpertAppointment> = emptyList(),
    val courseUploads: List<CourseUploadRecord> = emptyList(),
    val studentTaskStatuses: Map<String, TaskStatus> = emptyMap(),
    /** Authoritative task-scoped state. Key format: taskId|studentId. */
    val taskScopedStatuses: Map<String, TaskStatus> = emptyMap(),
    val taskScopedStatusVersions: Map<String, Int> = emptyMap(),
    val taskScopedSyncStates: Map<String, LocalSubmissionStatus> = emptyMap(),
    val taskScopedReviewNotes: Map<String, String> = emptyMap(),
    /** Last server task-row version observed for each student. */
    val taskStatusVersions: Map<String, Int> = emptyMap(),
    /** Remote acknowledgement state for locally applied teacher queue updates. */
    val taskStatusSyncStates: Map<String, LocalSubmissionStatus> = emptyMap(),
    val reviewNotes: Map<String, String> = emptyMap(),
    val sessionActive: Boolean = false,
    val sessionPhone: String = "",
    val sessionRoleName: String? = null,
    /** Registration bucket selected when this account was created. */
    val accountBucketName: String? = null,
    /** Stable account identity, independent of the selected role workbench. */
    val parentAccountName: String? = null,
    val selectedChildId: String? = null,
    val boundChildIds: Set<String> = emptySet(),
    val selectedPrincipalTaskId: String? = null,
    val teacherUsesSportsWorkbench: Boolean = false,
    val readMessageIds: Set<String> = emptySet(),
    val settings: LocalAppSettings = LocalAppSettings()
)
/** A local receipt is not a customer-service response. */
data class SupportMessage(
    val text: String,
    val mine: Boolean,
    val id: String = java.util.UUID.randomUUID().toString(),
    val status: LocalSubmissionStatus = if (mine) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Submitted
)
data class ActivityRegistration(
    val id: String = java.util.UUID.randomUUID().toString(),
    val activityId: String,
    val contactName: String,
    val phone: String,
    val status: LocalSubmissionStatus = LocalSubmissionStatus.PendingSync,
    val registrationId: String? = null,
    val childId: String? = null,
    val contactUserId: String? = null,
    val capacity: Int? = null,
    val remainingCapacity: Int? = null,
    val registrationStartAt: String? = null,
    val registrationEndAt: String? = null,
    val registrationStatus: String? = null,
    val version: Int? = null
)
/** Local visibility is not the same as a school-side acknowledgement. */
data class ClassPost(
    val id: String = java.util.UUID.randomUUID().toString(),
    val author: String,
    val content: String,
    val status: LocalSubmissionStatus = LocalSubmissionStatus.PendingSync,
    val postId: String? = null,
    val classId: String? = null,
    val displayName: String? = null,
    val visibilityScope: String? = "class",
    val moderationStatus: String? = "pending_review",
    val pinned: Boolean = false,
    val reportStatus: String? = null,
    val attachments: List<ClassPostAttachment> = emptyList(),
    val authorRole: String? = null,
    /** Server-owned projection; names and aliases must never determine this. */
    val ownedByCurrentUser: Boolean = false
)
data class ClassPostAttachment(val id: String, val type: String, val objectId: String? = null, val localReference: String? = null, val thumbnailObjectId: String? = null)
enum class LocalSubmissionStatus { Draft, Submitting, PendingSync, Submitted, Failed }
data class FamilyHealthRecord(
    val childId: String,
    val category: String,
    val completedAt: String,
    val entries: Map<String, String>,
    val formVersion: String? = null,
    val submittedAt: String? = null,
    val version: Int? = null,
    val frequency: String? = null,
    val severity: String? = null,
    val structuredAnswers: List<HealthObservationAnswer> = emptyList()
)
data class HealthObservationAnswer(val questionId: String, val questionType: String, val selectedOptionIds: List<String>, val note: String? = null, val required: Boolean = true)
data class HealthConsentRecord(val consentId: String, val guardianUserId: String, val childId: String, val privacyPolicyVersion: String, val cameraConsentVersion: String, val algorithmNoticeVersion: String, val agreedAt: String, val revokedAt: String? = null, val deviceInfo: String, val dataRetentionNoticeAccepted: Boolean)
data class ExpertAppointment(
    val id: String = java.util.UUID.randomUUID().toString(),
    val expertName: String,
    val preferredDate: String,
    val note: String,
    val status: LocalSubmissionStatus = LocalSubmissionStatus.PendingSync,
    val expertId: String? = null,
    val appointmentId: String? = null,
    val serviceId: String? = null,
    val slotId: String? = null,
    val childId: String? = null,
    val appointmentStatus: String? = null,
    val expectedVersion: Int? = null,
    val scheduledStartAt: String? = null,
    val scheduledEndAt: String? = null
)
data class CourseUploadRecord(
    val id: String = java.util.UUID.randomUUID().toString(),
    val taskId: String,
    val attendanceCount: Int,
    val notes: String,
    val attachmentName: String,
    /** Local private-file URI. A name or picker URI is not an upload receipt. */
    val attachmentReference: String? = null,
    val status: LocalSubmissionStatus = LocalSubmissionStatus.Draft
)
data class LocalAppSettings(
    val notificationsEnabled: Boolean = true,
    val reduceMotion: Boolean = false,
    /** Shared speech preference for posture capture and guided training. */
    val voiceGuidanceEnabled: Boolean = true
)
data class FollowAlongSessionRecord(
    val id: String = java.util.UUID.randomUUID().toString(),
    val childId: String,
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

/** Front-end persistence used until the remote workflow APIs are connected. */
class LocalFeatureStore(context: Context) {
    private val prefs = SecurePreferences(context, "xiangshang_local_features")
    fun load(): LocalFeatureState = LocalFeatureState(
        activityRegistered = prefs.getBoolean("activity_registered", false),
        activityRegistrations = decodeActivityRegistrations(prefs.getString("activity_registrations", null)),
        completedAssessments = prefs.getStringSet("completed_assessments", emptySet()) ?: emptySet(),
        familyHealthRecords = decodeFamilyHealthRecords(prefs.getString("family_health_records", null)),
        healthObservationSyncStates = decodeSubmissionStatuses(prefs.getString("health_observation_sync_states", null)),
        bodyAssessments = decodeBodyAssessments(prefs.getString("body_assessments", null)),
        bodyAssessmentHistory = decodeBodyAssessmentHistory(prefs.getString("body_assessment_history", null)),
        bodyAssessmentDrafts = decodeBodyAssessmentDrafts(prefs.getString("body_assessment_drafts", null)),
        bodyAssessmentSyncStates = decodeSubmissionStatuses(prefs.getString("body_assessment_sync_states", null)),
        healthConsents = decodeHealthConsents(prefs.getString("health_consents", null)),
        courseProgress = decodeProgress(prefs.getString("course_progress", null)),
        followAlongSessions = decodeFollowAlongSessions(prefs.getString("follow_along_sessions", null)),
        followAlongSyncStates = decodeSubmissionStatuses(prefs.getString("follow_along_sync_states", null)),
        supportMessages = decodeMessages(prefs.getString("support_messages", null)),
        classPosts = decodePosts(prefs.getString("class_posts", null)),
        likedPostIds = prefs.getStringSet("liked_post_ids", emptySet()) ?: emptySet(),
        postComments = decodeComments(prefs.getString("post_comments", null)),
        uploadedTaskIds = prefs.getStringSet("uploaded_task_ids", emptySet()) ?: emptySet(),
        checkedInToday = prefs.getString("checked_in_date", null) == today(),
        checkedInDate = prefs.getString("checked_in_date", null),
        checkedInDates = (prefs.getStringSet("checked_in_dates", emptySet()) ?: emptySet()).ifEmpty { prefs.getString("checked_in_date", null)?.let(::setOf) ?: emptySet() },
        healthCheckins = decodeHealthCheckins(prefs.getString("health_checkins", null)),
        healthCheckinSyncStates = decodeSubmissionStatuses(prefs.getString("health_checkin_sync_states", null)),
        drafts = decodeStringMap(prefs.getString("drafts", null)),
        expertAppointments = decodeAppointments(prefs.getString("expert_appointments", null)),
        courseUploads = decodeUploads(prefs.getString("course_uploads", null)),
        studentTaskStatuses = decodeTaskStatuses(prefs.getString("student_task_statuses", null)),
        taskScopedStatuses = decodeTaskStatuses(prefs.getString("task_scoped_statuses", null)),
        taskScopedStatusVersions = decodeIntMap(prefs.getString("task_scoped_status_versions", null)),
        taskScopedSyncStates = decodeSubmissionStatuses(prefs.getString("task_scoped_sync_states", null)),
        taskScopedReviewNotes = decodeStringMap(prefs.getString("task_scoped_review_notes", null)),
        taskStatusVersions = decodeIntMap(prefs.getString("task_status_versions", null)),
        taskStatusSyncStates = decodeSubmissionStatuses(prefs.getString("task_status_sync_states", null)),
        reviewNotes = decodeStringMap(prefs.getString("review_notes", null)),
        sessionActive = prefs.getBoolean("session_active", false),
        sessionPhone = prefs.getString("session_phone", "").orEmpty(),
        sessionRoleName = prefs.getString("session_role_name", null),
        accountBucketName = prefs.getString("account_bucket_name", null),
        parentAccountName = prefs.getString("parent_account_name", null),
        selectedChildId = prefs.getString("selected_child_id", null),
        boundChildIds = prefs.getStringSet("bound_child_ids", emptySet()) ?: emptySet(),
        selectedPrincipalTaskId = prefs.getString("selected_principal_task_id", null),
        teacherUsesSportsWorkbench = prefs.getBoolean("teacher_uses_sports_workbench", false),
        readMessageIds = prefs.getStringSet("read_message_ids", emptySet()) ?: emptySet(),
        settings = LocalAppSettings(
            notificationsEnabled = prefs.getBoolean("notifications_enabled", true),
            reduceMotion = prefs.getBoolean("reduce_motion", false),
            voiceGuidanceEnabled = prefs.getBoolean("voice_guidance_enabled", true)
        )
    )
    fun save(value: LocalFeatureState) {
        val normalizedCheckInDate = if (value.checkedInToday) value.checkedInDate ?: today() else value.checkedInDate
        val normalizedCheckInDates = value.checkedInDates + listOfNotNull(normalizedCheckInDate)
        prefs.edit()
        .putBoolean("activity_registered", value.activityRegistered)
        .putString("activity_registrations", JSONArray().apply { value.activityRegistrations.forEach { put(JSONObject().put("id", it.id).put("activityId", it.activityId).put("contactName", it.contactName).put("phone", it.phone).put("status", it.status.name).put("registrationId", it.registrationId).put("childId", it.childId).put("contactUserId", it.contactUserId).put("capacity", it.capacity).put("remainingCapacity", it.remainingCapacity).put("registrationStartAt", it.registrationStartAt).put("registrationEndAt", it.registrationEndAt).put("registrationStatus", it.registrationStatus).put("version", it.version)) } }.toString())
        .putStringSet("completed_assessments", value.completedAssessments)
        .putString("family_health_records", JSONObject().apply { value.familyHealthRecords.forEach { (id, record) -> put(id, JSONObject().put("childId", record.childId).put("category", record.category).put("completedAt", record.completedAt).put("entries", JSONObject(record.entries)).put("formVersion", record.formVersion).put("submittedAt", record.submittedAt).put("version", record.version).put("frequency", record.frequency).put("severity", record.severity).put("structuredAnswers", JSONArray().apply { record.structuredAnswers.forEach { answer -> put(JSONObject().put("questionId", answer.questionId).put("questionType", answer.questionType).put("selectedOptionIds", JSONArray(answer.selectedOptionIds)).put("note", answer.note).put("required", answer.required)) } })) } }.toString())
        .putString("health_observation_sync_states", JSONObject(value.healthObservationSyncStates.mapValues { it.value.name }).toString())
        .putString("body_assessments", JSONObject().apply { value.bodyAssessments.forEach { (id, r) -> put(id, bodyRecordJson(r)) } }.toString())
        .putString("body_assessment_history", JSONObject().apply { value.bodyAssessmentHistory.forEach { (id, records) -> put(id, JSONArray().apply { records.forEach { r -> put(bodyRecordJson(r)) } }) } }.toString())
        .putString("body_assessment_drafts", JSONObject().apply { value.bodyAssessmentDrafts.forEach { (id, draft) -> put(id, JSONObject().put("stage", draft.stage).put("guardianReady", draft.guardianReady).put("consentAcknowledged", draft.consentAcknowledged).put("environmentReady", draft.environmentReady).put("height", draft.heightCm).put("weight", draft.weightKg).put("captures", JSONArray(draft.captures.map { it.name })).put("asymmetric", draft.asymmetric).put("gait", draft.gaitConcern).put("visualHint", draft.visualObservationHint).put("captureHints", JSONObject(draft.captureObservationHints)).put("fatherHeight", draft.fatherHeightCm).put("motherHeight", draft.motherHeightCm)) } }.toString())
        .putString("body_assessment_sync_states", JSONObject(value.bodyAssessmentSyncStates.mapValues { it.value.name }).toString())
        .putString("health_consents", JSONObject().apply { value.healthConsents.forEach { (id, consent) -> put(id, JSONObject().put("consentId", consent.consentId).put("guardianUserId", consent.guardianUserId).put("childId", consent.childId).put("privacyPolicyVersion", consent.privacyPolicyVersion).put("cameraConsentVersion", consent.cameraConsentVersion).put("algorithmNoticeVersion", consent.algorithmNoticeVersion).put("agreedAt", consent.agreedAt).put("revokedAt", consent.revokedAt).put("deviceInfo", consent.deviceInfo).put("dataRetentionNoticeAccepted", consent.dataRetentionNoticeAccepted)) } }.toString())
        .putString("course_progress", JSONObject(value.courseProgress).toString())
        .putString("follow_along_sessions", JSONArray().apply { value.followAlongSessions.takeLast(90).forEach { session -> put(JSONObject().put("id", session.id).put("childId", session.childId).put("dayId", session.dayId).put("completedAt", session.completedAt).put("durationSeconds", session.durationSeconds).put("completionRatio", session.completionRatio).put("qualityScore", session.qualityScore).put("cameraVerified", session.cameraVerified).put("visualUnits", JSONObject(session.visualUnits)).put("manualUnits", session.manualUnits).put("modelVersion", session.modelVersion).put("mode", session.mode)) } }.toString())
        .putString("follow_along_sync_states", JSONObject(value.followAlongSyncStates.mapValues { it.value.name }).toString())
        .putString("support_messages", JSONArray().apply { value.supportMessages.forEach { put(JSONObject().put("id", it.id).put("text", it.text).put("mine", it.mine).put("status", it.status.name)) } }.toString())
        .putString("class_posts", JSONArray().apply { value.classPosts.forEach { put(JSONObject().put("id", it.id).put("author", it.author).put("content", it.content).put("status", it.status.name).put("postId", it.postId).put("classId", it.classId).put("displayName", it.displayName).put("visibilityScope", it.visibilityScope).put("moderationStatus", it.moderationStatus).put("pinned", it.pinned).put("reportStatus", it.reportStatus).put("authorRole", it.authorRole).put("ownedByCurrentUser", it.ownedByCurrentUser).put("attachments", JSONArray().apply { it.attachments.forEach { attachment -> put(JSONObject().put("id", attachment.id).put("type", attachment.type).put("objectId", attachment.objectId).put("localReference", attachment.localReference).put("thumbnailObjectId", attachment.thumbnailObjectId)) } })) } }.toString())
        .putStringSet("liked_post_ids", value.likedPostIds)
        .putString("post_comments", JSONObject().apply { value.postComments.forEach { (postId, comments) -> put(postId, JSONArray(comments)) } }.toString())
        .putStringSet("uploaded_task_ids", value.uploadedTaskIds)
        .putBoolean("checked_in_today", value.checkedInToday)
        .putString("checked_in_date", normalizedCheckInDate)
        .putStringSet("checked_in_dates", normalizedCheckInDates)
        .putString("health_checkins", JSONArray().apply { value.healthCheckins.takeLast(366).forEach { item -> put(JSONObject().put("id", item.id).put("childId", item.childId).put("checkInDate", item.checkInDate).put("activityType", item.activityType).put("durationMinutes", item.durationMinutes).put("intensity", item.intensity).put("feeling", item.feeling).put("completedRecommended", item.completedRecommended).put("parentNote", item.parentNote).put("version", item.version).put("createdAt", item.createdAt).put("updatedAt", item.updatedAt)) } }.toString())
        .putString("health_checkin_sync_states", JSONObject(value.healthCheckinSyncStates.mapValues { it.value.name }).toString())
        .putString("drafts", JSONObject(value.drafts).toString())
        .putString("expert_appointments", JSONArray().apply { value.expertAppointments.forEach { put(JSONObject().put("id", it.id).put("expertName", it.expertName).put("preferredDate", it.preferredDate).put("note", it.note).put("status", it.status.name).put("expertId", it.expertId).put("appointmentId", it.appointmentId).put("serviceId", it.serviceId).put("slotId", it.slotId).put("childId", it.childId).put("appointmentStatus", it.appointmentStatus).put("expectedVersion", it.expectedVersion).put("scheduledStartAt", it.scheduledStartAt).put("scheduledEndAt", it.scheduledEndAt)) } }.toString())
        .putString("course_uploads", JSONArray().apply { value.courseUploads.forEach { put(JSONObject().put("id", it.id).put("taskId", it.taskId).put("attendanceCount", it.attendanceCount).put("notes", it.notes).put("attachmentName", it.attachmentName).put("attachmentReference", it.attachmentReference).put("status", it.status.name)) } }.toString())
        .putString("student_task_statuses", JSONObject(value.studentTaskStatuses.mapValues { it.value.name }).toString())
        .putString("task_scoped_statuses", JSONObject(value.taskScopedStatuses.mapValues { it.value.name }).toString())
        .putString("task_scoped_status_versions", JSONObject(value.taskScopedStatusVersions).toString())
        .putString("task_scoped_sync_states", JSONObject(value.taskScopedSyncStates.mapValues { it.value.name }).toString())
        .putString("task_scoped_review_notes", JSONObject(value.taskScopedReviewNotes).toString())
        .putString("task_status_versions", JSONObject(value.taskStatusVersions).toString())
        .putString("task_status_sync_states", JSONObject(value.taskStatusSyncStates.mapValues { it.value.name }).toString())
        .putString("review_notes", JSONObject(value.reviewNotes).toString())
        .putBoolean("session_active", value.sessionActive)
        .putString("session_phone", value.sessionPhone)
        .putString("session_role_name", value.sessionRoleName)
        .putString("account_bucket_name", value.accountBucketName)
        .putString("parent_account_name", value.parentAccountName)
        .putString("selected_child_id", value.selectedChildId)
        .putStringSet("bound_child_ids", value.boundChildIds)
        .putString("selected_principal_task_id", value.selectedPrincipalTaskId)
        .putBoolean("teacher_uses_sports_workbench", value.teacherUsesSportsWorkbench)
        .putStringSet("read_message_ids", value.readMessageIds)
        .putBoolean("notifications_enabled", value.settings.notificationsEnabled)
        .putBoolean("reduce_motion", value.settings.reduceMotion)
        .putBoolean("voice_guidance_enabled", value.settings.voiceGuidanceEnabled).apply()
    }
    fun clear() { prefs.edit().clear().apply() }
    private fun decodeProgress(raw: String?): Map<String, Float> = runCatching { JSONObject(raw ?: "{}").keys().asSequence().associateWith { JSONObject(raw ?: "{}").optDouble(it).toFloat() } }.getOrDefault(emptyMap())
    private fun decodeFollowAlongSessions(raw: String?): List<FollowAlongSessionRecord> = runCatching {
        val array = JSONArray(raw ?: "[]")
        List(array.length()) { index ->
            val item = array.getJSONObject(index)
            val visual = item.optJSONObject("visualUnits")?.let { value -> value.keys().asSequence().associateWith { key -> value.optInt(key) } }.orEmpty()
            FollowAlongSessionRecord(item.optString("id").ifBlank { java.util.UUID.randomUUID().toString() }, item.optString("childId"), item.optInt("dayId"), item.optString("completedAt"), item.optInt("durationSeconds"), item.optDouble("completionRatio").toFloat().coerceIn(0f, 1f), item.optInt("qualityScore").coerceIn(0, 100), item.optBoolean("cameraVerified"), visual, item.optInt("manualUnits"), item.optString("modelVersion"), item.optString("mode", "guidedTraining"))
        }
    }.getOrDefault(emptyList())
    private fun decodeHealthCheckins(raw: String?): List<HealthCheckInRecord> = runCatching {
        val array = JSONArray(raw ?: "[]")
        List(array.length()) { index ->
            val item = array.getJSONObject(index)
            HealthCheckInRecord(item.optString("id").ifBlank { java.util.UUID.randomUUID().toString() }, item.optString("childId"), item.optString("checkInDate"), item.optString("activityType"), item.optInt("durationMinutes"), item.optString("intensity", "moderate"), item.optString("feeling").takeIf { it.isNotBlank() && it != "null" }, item.optBoolean("completedRecommended"), item.optString("parentNote").takeIf { it.isNotBlank() && it != "null" }, item.optInt("version", 1), item.optString("createdAt").takeIf { it.isNotBlank() && it != "null" }, item.optString("updatedAt").takeIf { it.isNotBlank() && it != "null" })
        }
    }.getOrDefault(emptyList())
    private fun decodeFamilyHealthRecords(raw: String?): Map<String, FamilyHealthRecord> = runCatching { val root = JSONObject(raw ?: "{}"); root.keys().asSequence().associateWith { id -> val record = root.getJSONObject(id); val answers = record.optJSONArray("structuredAnswers") ?: JSONArray(); FamilyHealthRecord(record.optString("childId"), record.optString("category"), record.optString("completedAt"), record.optJSONObject("entries")?.let { entries -> entries.keys().asSequence().associateWith { key -> entries.optString(key) } }.orEmpty(), record.optString("formVersion").takeIf { it.isNotBlank() && it != "null" }, record.optString("submittedAt").takeIf { it.isNotBlank() && it != "null" }, record.optInt("version", -1).takeIf { it >= 0 }, record.optString("frequency").takeIf { it.isNotBlank() && it != "null" }, record.optString("severity").takeIf { it.isNotBlank() && it != "null" }, List(answers.length()) { index -> val answer = answers.getJSONObject(index); val selected = answer.optJSONArray("selectedOptionIds") ?: JSONArray(); HealthObservationAnswer(answer.optString("questionId"), answer.optString("questionType", "text"), List(selected.length()) { selected.optString(it) }.filter { it.isNotBlank() }, answer.optString("note").takeIf { it.isNotBlank() && it != "null" }, answer.optBoolean("required", true)) }) } }.getOrDefault(emptyMap())
    private fun decodeHealthConsents(raw: String?): Map<String, HealthConsentRecord> = runCatching { val root = JSONObject(raw ?: "{}"); root.keys().asSequence().associateWith { id -> val value = root.getJSONObject(id); HealthConsentRecord(value.optString("consentId", id), value.optString("guardianUserId"), value.optString("childId", id), value.optString("privacyPolicyVersion", "v1"), value.optString("cameraConsentVersion", "v1"), value.optString("algorithmNoticeVersion", "posture-screening-v1"), value.optString("agreedAt"), value.optString("revokedAt").takeIf { it.isNotBlank() && it != "null" }, value.optString("deviceInfo"), value.optBoolean("dataRetentionNoticeAccepted", true)) } }.getOrDefault(emptyMap())
    private fun bodyRecordJson(r: BodyAssessmentRecord) = JSONObject().put("height", r.heightCm).put("weight", r.weightKg).put("measured", r.measuredAt).put("captures", JSONArray(r.captures.map { it.name })).put("asymmetric", r.asymmetric).put("gait", r.gaitConcern).put("followup", r.nextFollowUp).put("plan", JSONArray(r.planDays)).put("visualHint", r.visualObservationHint).put("captureHints", JSONObject(r.captureObservationHints)).put("fatherHeight", r.fatherHeightCm).put("motherHeight", r.motherHeightCm).put("ageMonthsAtMeasurement", r.ageMonthsAtMeasurement)
    private fun decodeBodyRecord(o: JSONObject): BodyAssessmentRecord { val c = o.optJSONArray("captures") ?: JSONArray(); val p = o.optJSONArray("plan") ?: JSONArray(); val hints = o.optJSONObject("captureHints")?.let { value -> value.keys().asSequence().associateWith { key -> value.optString(key) }.filterValues { it.isNotBlank() && it != "null" } }.orEmpty(); val age = o.optInt("ageMonthsAtMeasurement", -1).takeIf { it >= 0 }; return BodyAssessmentRecord(o.optDouble("height"), o.optDouble("weight"), o.optString("measured"), (0 until c.length()).mapNotNull { runCatching { BodyCaptureTask.valueOf(c.getString(it)) }.getOrNull() }.toSet(), o.optBoolean("asymmetric"), o.optBoolean("gait"), o.optString("followup"), (0 until p.length()).map { p.getString(it) }.toSet(), o.optString("visualHint").takeIf { it.isNotBlank() && it != "null" }, o.optionalDouble("fatherHeight"), o.optionalDouble("motherHeight"), hints, ageMonthsAtMeasurement = age) }
    private fun decodeBodyAssessments(raw: String?): Map<String, BodyAssessmentRecord> = runCatching { val root = JSONObject(raw ?: "{}"); root.keys().asSequence().associateWith { id -> decodeBodyRecord(root.getJSONObject(id)) } }.getOrDefault(emptyMap())
    private fun decodeBodyAssessmentHistory(raw: String?): Map<String, List<BodyAssessmentRecord>> = runCatching { val root = JSONObject(raw ?: "{}"); root.keys().asSequence().associateWith { id -> val array = root.getJSONArray(id); List(array.length()) { decodeBodyRecord(array.getJSONObject(it)) } } }.getOrDefault(emptyMap())
    companion object {
        /** Internal for regression tests: incomplete legacy drafts must never invent measurements. */
        internal fun legacyBodyAssessmentDraft(stage: Int, heightCm: Double?, weightKg: Double?, captures: Set<BodyCaptureTask> = emptySet(), asymmetric: Boolean = false, gaitConcern: Boolean = false, visualHint: String? = null, fatherHeightCm: Double? = null, motherHeightCm: Double? = null, captureHints: Map<String, String> = emptyMap()): BodyAssessmentDraft = BodyAssessmentDraft(stage = stage, heightCm = heightCm ?: 0.0, weightKg = weightKg ?: 0.0, captures = captures, asymmetric = asymmetric, gaitConcern = gaitConcern, visualObservationHint = visualHint, fatherHeightCm = fatherHeightCm, motherHeightCm = motherHeightCm, captureObservationHints = captureHints)
        internal fun decodeBodyAssessmentDrafts(raw: String?): Map<String, BodyAssessmentDraft> = runCatching {
            val root = JSONObject(raw ?: "{}")
            buildMap {
                val keys = root.keys()
                while (keys.hasNext()) {
                    val id = keys.next()
                    val o = root.optJSONObject(id) ?: continue
                    val captures = o.optJSONArray("captures") ?: JSONArray()
                    val fatherHeight = o.takeIf { it.has("fatherHeight") && !it.isNull("fatherHeight") }?.optDouble("fatherHeight")
                    val motherHeight = o.takeIf { it.has("motherHeight") && !it.isNull("motherHeight") }?.optDouble("motherHeight")
                    val captureHints = o.optJSONObject("captureHints")?.let { hints -> hints.keys().asSequence().associateWith { key -> hints.optString(key) }.filterValues { it.isNotBlank() && it != "null" } }.orEmpty()
                    put(id, legacyBodyAssessmentDraft(o.optInt("stage"), if (o.has("height")) o.optDouble("height") else null, if (o.has("weight")) o.optDouble("weight") else null, (0 until captures.length()).mapNotNull { runCatching { BodyCaptureTask.valueOf(captures.getString(it)) }.getOrNull() }.toSet(), o.optBoolean("asymmetric"), o.optBoolean("gait"), o.optString("visualHint").takeIf { it.isNotBlank() && it != "null" }, fatherHeight, motherHeight, captureHints).copy(guardianReady = o.optBoolean("guardianReady"), consentAcknowledged = o.optBoolean("consentAcknowledged"), environmentReady = o.optBoolean("environmentReady")))
                }
            }
        }.getOrDefault(emptyMap())
    }
    private fun JSONObject.optionalDouble(name: String): Double? = if (has(name) && !isNull(name)) optDouble(name) else null
    private fun decodeStringMap(raw: String?): Map<String, String> = runCatching { JSONObject(raw ?: "{}").keys().asSequence().associateWith { JSONObject(raw ?: "{}").optString(it) } }.getOrDefault(emptyMap())
    private fun decodeMessages(raw: String?): List<SupportMessage> = runCatching {
        val array = JSONArray(raw ?: "[]")
        List(array.length()) { index ->
            val item = array.getJSONObject(index)
            val mine = item.optBoolean("mine")
            val status = item.optString("status")
                .takeIf { it.isNotBlank() }
                ?.let { runCatching { LocalSubmissionStatus.valueOf(it) }.getOrNull() }
                ?: if (mine) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Submitted
            SupportMessage(
                id = item.optString("id").takeIf { it.isNotBlank() } ?: java.util.UUID.randomUUID().toString(),
                text = item.optString("text"),
                mine = mine,
                status = status
            )
        }
    }.getOrDefault(emptyList())
    private fun decodeActivityRegistrations(raw: String?): List<ActivityRegistration> = runCatching { val a = JSONArray(raw ?: "[]"); List(a.length()) { val o = a.getJSONObject(it); ActivityRegistration(o.optString("id"), o.optString("activityId"), o.optString("contactName"), o.optString("phone"), o.optString("status").let { runCatching { LocalSubmissionStatus.valueOf(it) }.getOrDefault(LocalSubmissionStatus.PendingSync) }, o.optString("registrationId").takeIf { it.isNotBlank() && it != "null" }, o.optString("childId").takeIf { it.isNotBlank() && it != "null" }, o.optString("contactUserId").takeIf { it.isNotBlank() && it != "null" }, o.optInt("capacity", -1).takeIf { it >= 0 }, o.optInt("remainingCapacity", -1).takeIf { it >= 0 }, o.optString("registrationStartAt").takeIf { it.isNotBlank() && it != "null" }, o.optString("registrationEndAt").takeIf { it.isNotBlank() && it != "null" }, o.optString("registrationStatus").takeIf { it.isNotBlank() && it != "null" }, o.optInt("version", -1).takeIf { it >= 0 }) } }.getOrDefault(emptyList())
    private fun decodePosts(raw: String?): List<ClassPost> = runCatching { val a = JSONArray(raw ?: "[]"); List(a.length()) { val o = a.getJSONObject(it); val attachments = o.optJSONArray("attachments") ?: JSONArray(); ClassPost(o.optString("id", java.util.UUID.randomUUID().toString()), o.optString("author"), o.optString("content"), o.optString("status").let { runCatching { LocalSubmissionStatus.valueOf(it) }.getOrDefault(LocalSubmissionStatus.PendingSync) }, o.optString("postId").takeIf { it.isNotBlank() && it != "null" }, o.optString("classId").takeIf { it.isNotBlank() && it != "null" }, o.optString("displayName").takeIf { it.isNotBlank() && it != "null" }, o.optString("visibilityScope", "class"), o.optString("moderationStatus", "pending_review"), o.optBoolean("pinned"), o.optString("reportStatus").takeIf { it.isNotBlank() && it != "null" }, List(attachments.length()) { index -> val item = attachments.getJSONObject(index); ClassPostAttachment(item.optString("id"), item.optString("type"), item.optString("objectId").takeIf { it.isNotBlank() && it != "null" }, item.optString("localReference").takeIf { it.isNotBlank() && it != "null" }, item.optString("thumbnailObjectId").takeIf { it.isNotBlank() && it != "null" }) }, o.optString("authorRole").takeIf { it.isNotBlank() && it != "null" }, o.optBoolean("ownedByCurrentUser")) } }.getOrDefault(emptyList())
    private fun decodeComments(raw: String?): Map<String, List<String>> = runCatching { val value = JSONObject(raw ?: "{}"); value.keys().asSequence().associateWith { key -> val array = value.optJSONArray(key) ?: JSONArray(); List(array.length()) { index -> array.optString(index) } } }.getOrDefault(emptyMap())
    private fun decodeAppointments(raw: String?): List<ExpertAppointment> = runCatching { val a = JSONArray(raw ?: "[]"); List(a.length()) { val o=a.getJSONObject(it); ExpertAppointment(o.optString("id"), o.optString("expertName"), o.optString("preferredDate"), o.optString("note"), o.optString("status").let { runCatching { LocalSubmissionStatus.valueOf(it) }.getOrDefault(LocalSubmissionStatus.PendingSync) }, o.optString("expertId").takeIf { it.isNotBlank() && it != "null" }, o.optString("appointmentId").takeIf { it.isNotBlank() && it != "null" }, o.optString("serviceId").takeIf { it.isNotBlank() && it != "null" }, o.optString("slotId").takeIf { it.isNotBlank() && it != "null" }, o.optString("childId").takeIf { it.isNotBlank() && it != "null" }, o.optString("appointmentStatus").takeIf { it.isNotBlank() && it != "null" }, o.optInt("expectedVersion", -1).takeIf { it >= 0 }, o.optString("scheduledStartAt").takeIf { it.isNotBlank() && it != "null" }, o.optString("scheduledEndAt").takeIf { it.isNotBlank() && it != "null" }) } }.getOrDefault(emptyList())
    private fun decodeUploads(raw: String?): List<CourseUploadRecord> = runCatching { val a = JSONArray(raw ?: "[]"); List(a.length()) { val o=a.getJSONObject(it); CourseUploadRecord(o.optString("id"), o.optString("taskId"), o.optInt("attendanceCount"), o.optString("notes"), o.optString("attachmentName"), o.optString("attachmentReference").takeIf { it.isNotBlank() && it != "null" }, o.optString("status").let { runCatching { LocalSubmissionStatus.valueOf(it) }.getOrDefault(LocalSubmissionStatus.Draft) }) } }.getOrDefault(emptyList())
    private fun decodeTaskStatuses(raw: String?): Map<String, TaskStatus> = runCatching { val value = JSONObject(raw ?: "{}"); value.keys().asSequence().mapNotNull { key -> runCatching { key to TaskStatus.valueOf(value.getString(key)) }.getOrNull() }.toMap() }.getOrDefault(emptyMap())
    private fun decodeIntMap(raw: String?): Map<String, Int> = runCatching { val value = JSONObject(raw ?: "{}"); value.keys().asSequence().mapNotNull { key -> value.optInt(key, Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE }?.let { key to it } }.toMap() }.getOrDefault(emptyMap())
    private fun decodeSubmissionStatuses(raw: String?): Map<String, LocalSubmissionStatus> = runCatching { val value = JSONObject(raw ?: "{}"); value.keys().asSequence().mapNotNull { key -> runCatching { key to LocalSubmissionStatus.valueOf(value.getString(key)) }.getOrNull() }.toMap() }.getOrDefault(emptyMap())
    private fun today(): String = BusinessClock.day()
}
