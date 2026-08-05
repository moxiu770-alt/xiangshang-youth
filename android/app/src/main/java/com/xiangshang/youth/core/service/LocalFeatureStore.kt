package com.xiangshang.youth.core.service

import android.content.Context
import com.xiangshang.youth.core.model.TaskStatus
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class LocalFeatureState(
    val activityRegistered: Boolean = false,
    val activityRegistrations: List<ActivityRegistration> = emptyList(),
    val completedAssessments: Set<String> = emptySet(),
    val courseProgress: Map<String, Float> = emptyMap(),
    val supportMessages: List<SupportMessage> = emptyList(),
    val classPosts: List<ClassPost> = emptyList(),
    val likedPostIds: Set<String> = emptySet(),
    val postComments: Map<String, List<String>> = emptyMap(),
    val uploadedTaskIds: Set<String> = emptySet(),
    val checkedInToday: Boolean = false,
    val checkedInDate: String? = null,
    val drafts: Map<String, String> = emptyMap(),
    val expertAppointments: List<ExpertAppointment> = emptyList(),
    val courseUploads: List<CourseUploadRecord> = emptyList(),
    val studentTaskStatuses: Map<String, TaskStatus> = emptyMap(),
    val reviewNotes: Map<String, String> = emptyMap(),
    val sessionActive: Boolean = false,
    val sessionPhone: String = "",
    val sessionRoleName: String? = null,
    val selectedChildId: String? = null,
    val boundChildIds: Set<String> = emptySet(),
    val readMessageIds: Set<String> = emptySet(),
    val settings: LocalAppSettings = LocalAppSettings()
)
data class SupportMessage(val text: String, val mine: Boolean)
data class ActivityRegistration(val id: String = java.util.UUID.randomUUID().toString(), val activityId: String, val contactName: String, val phone: String, val status: LocalSubmissionStatus = LocalSubmissionStatus.Submitted)
data class ClassPost(val id: String = java.util.UUID.randomUUID().toString(), val author: String, val content: String)
enum class LocalSubmissionStatus { Draft, Submitting, Submitted, Failed }
data class ExpertAppointment(val id: String = java.util.UUID.randomUUID().toString(), val expertName: String, val preferredDate: String, val note: String, val status: LocalSubmissionStatus = LocalSubmissionStatus.Submitted)
data class CourseUploadRecord(val id: String = java.util.UUID.randomUUID().toString(), val taskId: String, val attendanceCount: Int, val notes: String, val attachmentName: String, val status: LocalSubmissionStatus = LocalSubmissionStatus.Draft)
data class LocalAppSettings(val notificationsEnabled: Boolean = true, val reduceMotion: Boolean = false)

/** Front-end persistence used until the remote workflow APIs are connected. */
class LocalFeatureStore(context: Context) {
    private val prefs = context.getSharedPreferences("xiangshang_local_features", Context.MODE_PRIVATE)
    fun load(): LocalFeatureState = LocalFeatureState(
        activityRegistered = prefs.getBoolean("activity_registered", false),
        activityRegistrations = decodeActivityRegistrations(prefs.getString("activity_registrations", null)),
        completedAssessments = prefs.getStringSet("completed_assessments", emptySet()) ?: emptySet(),
        courseProgress = decodeProgress(prefs.getString("course_progress", null)),
        supportMessages = decodeMessages(prefs.getString("support_messages", null)),
        classPosts = decodePosts(prefs.getString("class_posts", null)),
        likedPostIds = prefs.getStringSet("liked_post_ids", emptySet()) ?: emptySet(),
        postComments = decodeComments(prefs.getString("post_comments", null)),
        uploadedTaskIds = prefs.getStringSet("uploaded_task_ids", emptySet()) ?: emptySet(),
        checkedInToday = prefs.getString("checked_in_date", null) == today(),
        checkedInDate = prefs.getString("checked_in_date", null),
        drafts = decodeStringMap(prefs.getString("drafts", null)),
        expertAppointments = decodeAppointments(prefs.getString("expert_appointments", null)),
        courseUploads = decodeUploads(prefs.getString("course_uploads", null)),
        studentTaskStatuses = decodeTaskStatuses(prefs.getString("student_task_statuses", null)),
        reviewNotes = decodeStringMap(prefs.getString("review_notes", null)),
        sessionActive = prefs.getBoolean("session_active", false),
        sessionPhone = prefs.getString("session_phone", "").orEmpty(),
        sessionRoleName = prefs.getString("session_role_name", null),
        selectedChildId = prefs.getString("selected_child_id", null),
        boundChildIds = prefs.getStringSet("bound_child_ids", emptySet()) ?: emptySet(),
        readMessageIds = prefs.getStringSet("read_message_ids", emptySet()) ?: emptySet(),
        settings = LocalAppSettings(prefs.getBoolean("notifications_enabled", true), prefs.getBoolean("reduce_motion", false))
    )
    fun save(value: LocalFeatureState) {
        val normalizedCheckInDate = if (value.checkedInToday) value.checkedInDate ?: today() else value.checkedInDate
        prefs.edit()
        .putBoolean("activity_registered", value.activityRegistered)
        .putString("activity_registrations", JSONArray().apply { value.activityRegistrations.forEach { put(JSONObject().put("id", it.id).put("activityId", it.activityId).put("contactName", it.contactName).put("phone", it.phone).put("status", it.status.name)) } }.toString())
        .putStringSet("completed_assessments", value.completedAssessments)
        .putString("course_progress", JSONObject(value.courseProgress).toString())
        .putString("support_messages", JSONArray().apply { value.supportMessages.forEach { put(JSONObject().put("text", it.text).put("mine", it.mine)) } }.toString())
        .putString("class_posts", JSONArray().apply { value.classPosts.forEach { put(JSONObject().put("id", it.id).put("author", it.author).put("content", it.content)) } }.toString())
        .putStringSet("liked_post_ids", value.likedPostIds)
        .putString("post_comments", JSONObject().apply { value.postComments.forEach { (postId, comments) -> put(postId, JSONArray(comments)) } }.toString())
        .putStringSet("uploaded_task_ids", value.uploadedTaskIds)
        .putBoolean("checked_in_today", value.checkedInToday)
        .putString("checked_in_date", normalizedCheckInDate)
        .putString("drafts", JSONObject(value.drafts).toString())
        .putString("expert_appointments", JSONArray().apply { value.expertAppointments.forEach { put(JSONObject().put("id", it.id).put("expertName", it.expertName).put("preferredDate", it.preferredDate).put("note", it.note).put("status", it.status.name)) } }.toString())
        .putString("course_uploads", JSONArray().apply { value.courseUploads.forEach { put(JSONObject().put("id", it.id).put("taskId", it.taskId).put("attendanceCount", it.attendanceCount).put("notes", it.notes).put("attachmentName", it.attachmentName).put("status", it.status.name)) } }.toString())
        .putString("student_task_statuses", JSONObject(value.studentTaskStatuses.mapValues { it.value.name }).toString())
        .putString("review_notes", JSONObject(value.reviewNotes).toString())
        .putBoolean("session_active", value.sessionActive)
        .putString("session_phone", value.sessionPhone)
        .putString("session_role_name", value.sessionRoleName)
        .putString("selected_child_id", value.selectedChildId)
        .putStringSet("bound_child_ids", value.boundChildIds)
        .putStringSet("read_message_ids", value.readMessageIds)
        .putBoolean("notifications_enabled", value.settings.notificationsEnabled)
        .putBoolean("reduce_motion", value.settings.reduceMotion).apply()
    }
    fun clear() { prefs.edit().clear().apply() }
    private fun decodeProgress(raw: String?): Map<String, Float> = runCatching { JSONObject(raw ?: "{}").keys().asSequence().associateWith { JSONObject(raw ?: "{}").optDouble(it).toFloat() } }.getOrDefault(emptyMap())
    private fun decodeStringMap(raw: String?): Map<String, String> = runCatching { JSONObject(raw ?: "{}").keys().asSequence().associateWith { JSONObject(raw ?: "{}").optString(it) } }.getOrDefault(emptyMap())
    private fun decodeMessages(raw: String?): List<SupportMessage> = runCatching { val a = JSONArray(raw ?: "[]"); List(a.length()) { SupportMessage(a.getJSONObject(it).optString("text"), a.getJSONObject(it).optBoolean("mine")) } }.getOrDefault(emptyList())
    private fun decodeActivityRegistrations(raw: String?): List<ActivityRegistration> = runCatching { val a = JSONArray(raw ?: "[]"); List(a.length()) { val o = a.getJSONObject(it); ActivityRegistration(o.optString("id"), o.optString("activityId"), o.optString("contactName"), o.optString("phone"), o.optString("status").let { runCatching { LocalSubmissionStatus.valueOf(it) }.getOrDefault(LocalSubmissionStatus.Submitted) }) } }.getOrDefault(emptyList())
    private fun decodePosts(raw: String?): List<ClassPost> = runCatching { val a = JSONArray(raw ?: "[]"); List(a.length()) { ClassPost(a.getJSONObject(it).optString("id", java.util.UUID.randomUUID().toString()), a.getJSONObject(it).optString("author"), a.getJSONObject(it).optString("content")) } }.getOrDefault(emptyList())
    private fun decodeComments(raw: String?): Map<String, List<String>> = runCatching { val value = JSONObject(raw ?: "{}"); value.keys().asSequence().associateWith { key -> val array = value.optJSONArray(key) ?: JSONArray(); List(array.length()) { index -> array.optString(index) } } }.getOrDefault(emptyMap())
    private fun decodeAppointments(raw: String?): List<ExpertAppointment> = runCatching { val a = JSONArray(raw ?: "[]"); List(a.length()) { val o=a.getJSONObject(it); ExpertAppointment(o.optString("id"), o.optString("expertName"), o.optString("preferredDate"), o.optString("note"), o.optString("status").let { runCatching { LocalSubmissionStatus.valueOf(it) }.getOrDefault(LocalSubmissionStatus.Submitted) }) } }.getOrDefault(emptyList())
    private fun decodeUploads(raw: String?): List<CourseUploadRecord> = runCatching { val a = JSONArray(raw ?: "[]"); List(a.length()) { val o=a.getJSONObject(it); CourseUploadRecord(o.optString("id"), o.optString("taskId"), o.optInt("attendanceCount"), o.optString("notes"), o.optString("attachmentName"), o.optString("status").let { runCatching { LocalSubmissionStatus.valueOf(it) }.getOrDefault(LocalSubmissionStatus.Draft) }) } }.getOrDefault(emptyList())
    private fun decodeTaskStatuses(raw: String?): Map<String, TaskStatus> = runCatching { val value = JSONObject(raw ?: "{}"); value.keys().asSequence().mapNotNull { key -> runCatching { key to TaskStatus.valueOf(value.getString(key)) }.getOrNull() }.toMap() }.getOrDefault(emptyMap())
    private fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
}
