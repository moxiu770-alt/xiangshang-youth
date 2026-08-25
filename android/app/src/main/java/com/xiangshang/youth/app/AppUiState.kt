package com.xiangshang.youth.app

import com.xiangshang.youth.core.model.ClassInfo
import com.xiangshang.youth.core.model.DiagnosisReport
import com.xiangshang.youth.core.model.Student
import com.xiangshang.youth.core.model.TaskStatus
import com.xiangshang.youth.core.model.TestTask
import com.xiangshang.youth.core.model.UserProfile
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.repository.DashboardData
import com.xiangshang.youth.core.service.ActivityRegistrationAck
import com.xiangshang.youth.core.service.ExpertAppointmentAck
import com.xiangshang.youth.core.service.ExpertAvailableSlot
import com.xiangshang.youth.core.service.LocalFeatureState
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.service.NotificationCampaign
import com.xiangshang.youth.core.service.RemoteActivity
import com.xiangshang.youth.core.service.RemoteExpert
import com.xiangshang.youth.core.service.RemoteLesson
import com.xiangshang.youth.core.service.TaskStudentStatusRecord
import com.xiangshang.youth.core.service.TeacherAnalyticsOverview

enum class WorkflowCommandStatus { Idle, Submitting, Succeeded, Failed }

data class WorkflowCommandState(
    val status: WorkflowCommandStatus = WorkflowCommandStatus.Idle,
    val message: String? = null
) {
    val isSubmitting: Boolean get() = status == WorkflowCommandStatus.Submitting
}

/** A report recommendation resolves against the selected child's remote
 * catalogue by stable IDs. Titles are never used as remote identifiers. */
data class CourseRecommendationTarget(
    val childId: String,
    val courseId: String?,
    val lessonId: String?,
    val title: String
)

/** Immutable UI snapshot kept separate from [AppViewModel]'s orchestration.
 * This gives feature-level tests a stable state contract without coupling them
 * to Android services, storage or navigation. */
data class AppUiState(
    val profile: UserProfile? = null,
    val role: UserRole? = null,
    val data: DashboardData? = null,
    val selectedChild: Student? = null,
    val loading: Boolean = false,
    val error: String? = null,
    val local: LocalFeatureState = LocalFeatureState(),
    val restoringSession: Boolean = false,
    val repositoryAcknowledged: Boolean = false,
    val isOffline: Boolean = false,
    val reportOverrides: Map<String, DiagnosisReport> = emptyMap(),
    val reportLoadingStudentId: String? = null,
    val reportError: String? = null,
    val workflowStates: Map<String, WorkflowCommandState> = emptyMap(),
    val studentsLoadingMore: Boolean = false,
    val studentsLoadError: String? = null,
    val teacherOverview: TeacherAnalyticsOverview? = null,
    val remoteActivities: List<RemoteActivity> = emptyList(),
    val activitiesLoading: Boolean = false,
    val activitiesError: String? = null,
    val activityRegistrationHistory: List<ActivityRegistrationAck> = emptyList(),
    val remoteExperts: List<RemoteExpert> = emptyList(),
    val expertsLoading: Boolean = false,
    val expertsError: String? = null,
    val expertSlots: Map<String, List<ExpertAvailableSlot>> = emptyMap(),
    val expertSlotErrors: Map<String, String> = emptyMap(),
    val expertAppointmentHistory: List<ExpertAppointmentAck> = emptyList(),
    val classPostsLoading: Boolean = false,
    val classPostsError: String? = null,
    val classPostsNextCursor: String? = null,
    val classPostAttachmentBytes: Map<String, ByteArray> = emptyMap(),
    val classPostAttachmentErrors: Map<String, String> = emptyMap(),
    val remoteCourses: List<RemoteLesson> = emptyList(),
    val coursesLoading: Boolean = false,
    val coursesError: String? = null,
    val coursesChildId: String? = null,
    val notificationDrafts: List<NotificationCampaign> = emptyList(),
    val notificationDraftsLoading: Boolean = false,
    val notificationDraftsError: String? = null,
    val courseRecommendationTarget: CourseRecommendationTarget? = null,
    val pendingActivityId: String? = null,
    val pendingExpertAppointmentId: String? = null,
    /** Authoritative task roster rows, independent from the paged dashboard directory. */
    val taskRosterRecords: Map<String, List<TaskStudentStatusRecord>> = emptyMap()
) {
    fun taskRosterStudents(taskId: String, fallbackTask: TestTask? = null): List<Student> = taskRosterRecords[taskId].orEmpty().map { row ->
        data?.students?.firstOrNull { it.id == row.studentId } ?: Student(
            id = row.studentId,
            name = row.studentName,
            grade = row.gradeName ?: fallbackTask?.gradeName.orEmpty(),
            className = row.className,
            region = data?.school?.region.orEmpty(),
            isPovertyArea = data?.school?.isPovertyArea ?: false,
            taskStatus = row.status,
            totalScore = null,
            gender = row.studentGender.orEmpty(),
            taskVersion = row.version,
            classId = row.classId
        )
    }

    val managedTeacherClasses: List<ClassInfo>
        get() {
            if (role != UserRole.Teacher && profile?.role != UserRole.Teacher) return emptyList()
            val ids = profile?.authorizedClassIds.orEmpty().toSet()
            val teacherId = profile?.id
            return data?.classes.orEmpty().filter { it.id in ids || (it.teacherId != null && it.teacherId == teacherId) }
        }

    fun teacherHasCapability(capability: String): Boolean {
        if (role != UserRole.Teacher && profile?.role != UserRole.Teacher) return false
        val claims = profile?.capabilities.orEmpty()
        return (claims.isEmpty() && !repositoryAcknowledged && capability == "VIEW_CLASS_DASHBOARD") || capability in claims
    }

    fun taskKey(taskId: String?, studentId: String): String = "${taskId ?: "unscoped"}|$studentId"

    fun taskStatus(student: Student, taskId: String? = null): TaskStatus {
        val key = taskKey(taskId, student.id)
        return if (taskId != null) local.taskScopedStatuses[key] ?: student.taskStatus else local.taskScopedStatuses[key] ?: if (repositoryAcknowledged) student.taskStatus else local.studentTaskStatuses[student.id] ?: student.taskStatus
    }

    fun taskSyncStatus(student: Student, taskId: String? = null): LocalSubmissionStatus? {
        val key = taskKey(taskId, student.id)
        return if (taskId != null) local.taskScopedSyncStates[key] else local.taskScopedSyncStates[key] ?: local.taskStatusSyncStates[student.id]
    }

    fun taskReviewNote(student: Student, taskId: String? = null): String? {
        val key = taskKey(taskId, student.id)
        return if (taskId != null) local.taskScopedReviewNotes[key] else local.taskScopedReviewNotes[key] ?: local.reviewNotes[student.id]
    }

    val unreadMessageCount: Int get() = if (!local.settings.notificationsEnabled) 0 else data?.messages?.count { !it.isRead && it.id !in local.readMessageIds } ?: 0

    val activeDisplayName: String get() {
        val name = profile?.name?.trim().orEmpty()
        if (name.isNotEmpty()) return name
        return when (role) {
            UserRole.Teacher -> "教师"
            UserRole.Principal -> "校长"
            else -> "家长"
        }
    }

    val pendingSyncCount: Int get() = local.activityRegistrations.count { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed } + local.expertAppointments.count { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed } + local.courseUploads.count { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed } + local.classPosts.count { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed } + local.supportMessages.count { it.mine && (it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed) } + local.taskStatusSyncStates.values.count { it == LocalSubmissionStatus.PendingSync || it == LocalSubmissionStatus.Failed } + local.bodyAssessmentSyncStates.values.count { it == LocalSubmissionStatus.PendingSync || it == LocalSubmissionStatus.Failed } + local.followAlongSyncStates.values.count { it == LocalSubmissionStatus.PendingSync || it == LocalSubmissionStatus.Failed } + local.healthObservationSyncStates.values.count { it == LocalSubmissionStatus.PendingSync || it == LocalSubmissionStatus.Failed } + local.healthCheckinSyncStates.values.count { it == LocalSubmissionStatus.PendingSync || it == LocalSubmissionStatus.Failed }

    fun hasPublishedSchoolReport(student: Student): Boolean {
        val status = data?.tasks?.firstOrNull()?.let { taskStatus(student, it.id) } ?: taskStatus(student)
        val dashboard = data ?: return false
        return status == TaskStatus.Completed && dashboard.tasks.any { task ->
            task.hasPublishedResults && task.scopedStudents(dashboard.students).any { it.id == student.id }
        }
    }
}
