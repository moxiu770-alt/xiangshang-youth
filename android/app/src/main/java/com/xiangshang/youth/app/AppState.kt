package com.xiangshang.youth.app

import android.app.Application
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import androidx.core.net.toUri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.xiangshang.youth.core.model.*
import com.xiangshang.youth.core.repository.DashboardData
import com.xiangshang.youth.core.repository.RepositoryProvider
import com.xiangshang.youth.core.repository.YouthRepository
import com.xiangshang.youth.core.util.AuthIdentity
import com.xiangshang.youth.core.service.ClassPost
import com.xiangshang.youth.core.service.LocalFeatureState
import com.xiangshang.youth.core.service.LocalFeatureStore
import com.xiangshang.youth.core.service.ExpertAppointment
import com.xiangshang.youth.core.service.ActivityRegistrationAck
import com.xiangshang.youth.core.service.ExpertAppointmentAck
import com.xiangshang.youth.core.service.CourseUploadRecord
import com.xiangshang.youth.core.service.CourseUploadValidator
import com.xiangshang.youth.core.service.FollowAlongSessionRecord
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.service.ApiClient
import com.xiangshang.youth.core.service.ApiError
import com.xiangshang.youth.core.service.AuthApi
import com.xiangshang.youth.core.service.LoginRequest
import com.xiangshang.youth.core.service.RegisterRequest
import com.xiangshang.youth.core.service.ResetPasswordRequest
import com.xiangshang.youth.core.service.VerificationCodeRequest
import com.xiangshang.youth.core.service.WechatExchangeRequest
import com.xiangshang.youth.core.util.ChildBindingValidator
import com.xiangshang.youth.core.util.BusinessClock
import com.xiangshang.youth.BuildConfig
import com.xiangshang.youth.core.sync.PendingSyncScheduler
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class AppViewModel(application: Application) : AndroidViewModel(application) {
    /** Stable key functions live in their domain files; this companion keeps
     * source compatibility for UI callers while the state holder stays lean. */
    companion object {
        fun courseProgressKey(childId: String, courseId: String, moduleId: String = "default", lessonId: String): String =
            "course|$childId|$courseId|$moduleId|$lessonId"
    }
    private val connectivityManager = application.getSystemService(ConnectivityManager::class.java)
    private var networkCallbackRegistered = false
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { setOffline(false) }
        override fun onLost(network: Network) { setOffline(!hasValidatedNetwork()) }
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) { setOffline(!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) }
    }
    internal val repository: YouthRepository = RepositoryProvider.create()
    internal val featureStore = LocalFeatureStore(application)
    private val initialLocal = featureStore.load()
    /** A logout may happen while a cold-start restore is awaiting the
     * dashboard.  Keep a cancellable handle and a generation token so the
     * old account can never repopulate state after the user chose to exit. */
    internal var sessionRestoreJob: Job? = null
    internal var sessionGeneration = 0L
    internal val _state = MutableStateFlow(AppUiState(local = initialLocal, restoringSession = initialLocal.sessionActive, repositoryAcknowledged = repository.supportsRemoteAcknowledgement))
    val state: StateFlow<AppUiState> = _state.asStateFlow()
    init {
        setOffline(!hasValidatedNetwork())
        runCatching { connectivityManager.registerDefaultNetworkCallback(networkCallback) }
            .onSuccess { networkCallbackRegistered = true }
        if (_state.value.local.sessionActive) restoreSession()
    }

    /**
     * Server-side guardian bindings are authoritative. A parent signing in on
     * a new device must immediately see children already bound by the school
     * or another device instead of being sent back to the binding prompt.
     */
    internal fun reconcileChildScope(
        profile: UserProfile,
        data: DashboardData,
        local: LocalFeatureState
    ): Pair<LocalFeatureState, Student?> {
        if (repository.supportsRemoteAcknowledgement && profile.role == UserRole.Parent) {
            val authorized = data.children.map { it.student }
            val ids = authorized.map { it.id }.toSet()
            val selectedId = local.selectedChildId?.takeIf(ids::contains) ?: authorized.firstOrNull()?.id
            val selected = authorized.firstOrNull { it.id == selectedId }
            return local.copy(boundChildIds = ids, selectedChildId = selected?.id) to selected
        }
        val selected = data.students.firstOrNull {
            it.id == local.selectedChildId && it.id in local.boundChildIds
        }
        return local.copy(selectedChildId = selected?.id) to selected
    }
    fun report(student: Student): DiagnosisReport = _state.value.reportOverrides[student.id] ?: repository.report(student)
    /** In remote mode, only render a report that came from ReportApi. */
    fun visibleReport(student: Student): DiagnosisReport? =
        if (_state.value.repositoryAcknowledged) _state.value.reportOverrides[student.id] else report(student)
    fun refreshReport(student: Student) = viewModelScope.launch {
        if (_state.value.profile == null || _state.value.reportLoadingStudentId != null) return@launch
        _state.value = _state.value.copy(reportLoadingStudentId = student.id, reportError = null)
        try {
            val report = repository.loadReport(student)
            // Logout/account switching can happen while a request is in flight;
            // do not leak the previous account's response into the new session.
            if (_state.value.profile == null) return@launch
            val reports = _state.value.reportOverrides + (student.id to report)
            _state.value = _state.value.copy(reportOverrides = reports, reportLoadingStudentId = null)
        } catch (error: kotlinx.coroutines.CancellationException) {
            _state.value = _state.value.copy(reportLoadingStudentId = null)
            throw error
        } catch (error: Throwable) {
            if (error is ApiError.Unauthorized) {
                handleDashboardFailure(error)
            } else {
                _state.value = _state.value.copy(reportLoadingStudentId = null, reportError = error.message ?: "报告刷新失败")
            }
        }
    }
    fun clearReportError() { _state.value = _state.value.copy(reportError = null) }
    fun workflowState(key: String): WorkflowCommandState = _state.value.workflowStates[key] ?: WorkflowCommandState()
    /** Shared by the separated notification/workflow domain files. */
    internal fun setWorkflow(key: String, value: WorkflowCommandState) { _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to value)) }
    internal fun childWorkflowKey(prefix: String, childId: String? = _state.value.selectedChild?.id): String =
        childId?.takeIf { it.isNotBlank() }?.let { "$prefix:$it" } ?: prefix
    fun clearWorkflowState(key: String) { _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState())) }

    internal fun executeWorkflow(key: String, operation: suspend () -> Unit, onSuccess: (() -> Unit)? = null, onFailure: (() -> Unit)? = null, successMessage: (() -> String)? = null, onError: ((Throwable) -> Unit)? = null) = viewModelScope.launch {
        val current = workflowState(key)
        if (current.isSubmitting) return@launch
        _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState(WorkflowCommandStatus.Submitting)))
        try {
            operation()
            onSuccess?.invoke()
            val message = successMessage?.invoke() ?: if (repository.supportsRemoteAcknowledgement) "已提交并收到学校服务确认。" else "已保存到本机，等待学校服务接入后同步确认。"
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState(WorkflowCommandStatus.Succeeded, message)))
        } catch (error: kotlinx.coroutines.CancellationException) {
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState()))
            throw error
        } catch (error: Throwable) {
            if (error is ApiError.Unauthorized) {
                handleDashboardFailure(error)
                return@launch
            }
            onError?.invoke(error)
            onFailure?.invoke()
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState(WorkflowCommandStatus.Failed, error.message ?: "提交失败，请重试")))
        }
    }

    fun syncPendingRecords() = executeWorkflow("sync-pending", {
        if (_state.value.profile == null) throw IllegalStateException("请登录后再同步本机记录。")
        if (_state.value.isOffline) throw IllegalStateException("当前网络不可用，记录会继续保存在本机。")
        if (!repository.supportsRemoteAcknowledgement) return@executeWorkflow
        var failed = syncPendingSchedulingRecords() + syncPendingCourseUploads()
        _state.value.local.classPosts.filter { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed }.forEach { post ->
            updatePostSyncStatus(post.id, LocalSubmissionStatus.Submitting)
            try {
                val serverPostId = repository.publishClassPost(post.author, post.content, _state.value.profile?.schoolId, post.classId, post.attachments)
                updatePostSyncStatus(post.id, LocalSubmissionStatus.Submitted, serverPostId)
            } catch (error: Throwable) {
                if (error is ApiError.Unauthorized) throw error
                updatePostSyncStatus(post.id, LocalSubmissionStatus.Failed); failed += 1
            }
        }
        _state.value.local.supportMessages.filter { it.mine && (it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed) }.forEach { message ->
            updateSupportSyncStatus(message.id, LocalSubmissionStatus.Submitting)
            try {
                repository.sendSupportMessage(message.text)
                updateSupportSyncStatus(message.id, LocalSubmissionStatus.Submitted)
            } catch (error: Throwable) {
                if (error is ApiError.Unauthorized) throw error
                updateSupportSyncStatus(message.id, LocalSubmissionStatus.Failed); failed += 1
            }
        }
        _state.value.local.bodyAssessmentSyncStates.filter { (_, syncStatus) -> syncStatus == LocalSubmissionStatus.PendingSync || syncStatus == LocalSubmissionStatus.Failed }.forEach { (studentId, _) ->
            val record = _state.value.local.bodyAssessments[studentId]
            if (record == null) {
                updateBodyAssessmentSyncStatus(studentId, LocalSubmissionStatus.Failed)
                failed += 1
            } else {
                updateBodyAssessmentSyncStatus(studentId, LocalSubmissionStatus.Submitting)
                try {
                    val consent = _state.value.local.healthConsents[studentId]
                        ?: throw ApiError.Client("请先完成监护人授权后再提交身体测评")
                    if (consent.revokedAt != null) throw ApiError.Client("监护人授权已撤回，请重新确认后再提交身体测评")
                    if (consent.privacyPolicyVersion != com.xiangshang.youth.core.model.LegalPolicy.PRIVACY_POLICY_VERSION ||
                        consent.cameraConsentVersion != com.xiangshang.youth.core.model.LegalPolicy.CAMERA_CONSENT_VERSION ||
                        consent.algorithmNoticeVersion != com.xiangshang.youth.core.model.LegalPolicy.ALGORITHM_NOTICE_VERSION
                    ) throw ApiError.Client("授权说明已更新，请重新确认后再同步身体测评")
                    repository.grantHealthConsent(consent)
                    val canonicalReport = repository.submitBodyAssessment(studentId, record, consent.privacyPolicyVersion)
                    if (canonicalReport != null) {
                        mutate { local ->
                            val current = local.bodyAssessments[studentId] ?: return@mutate local
                            val canonical = current.copy(postureReport = canonicalReport)
                            val history = local.bodyAssessmentHistory[studentId].orEmpty().toMutableList()
                            if (history.isNotEmpty()) history[history.lastIndex] = canonical
                            local.copy(bodyAssessments = local.bodyAssessments + (studentId to canonical), bodyAssessmentHistory = local.bodyAssessmentHistory + (studentId to history))
                        }
                    }
                    updateBodyAssessmentSyncStatus(studentId, LocalSubmissionStatus.Submitted)
                } catch (error: Throwable) {
                    if (error is ApiError.Unauthorized) throw error
                    updateBodyAssessmentSyncStatus(studentId, LocalSubmissionStatus.Failed); failed += 1
                }
            }
        }
        _state.value.local.followAlongSyncStates.filter { (_, syncStatus) -> syncStatus == LocalSubmissionStatus.PendingSync || syncStatus == LocalSubmissionStatus.Failed }.forEach { (sessionId, _) ->
            val record = _state.value.local.followAlongSessions.firstOrNull { it.id == sessionId }
            if (record == null) {
                updateFollowAlongSyncStatus(sessionId, LocalSubmissionStatus.Failed)
                failed += 1
            } else {
                updateFollowAlongSyncStatus(sessionId, LocalSubmissionStatus.Submitting)
                try {
                    repository.submitFollowAlongSession(record)
                    updateFollowAlongSyncStatus(sessionId, LocalSubmissionStatus.Submitted)
                } catch (error: Throwable) {
                    if (error is ApiError.Unauthorized) throw error
                    updateFollowAlongSyncStatus(sessionId, LocalSubmissionStatus.Failed)
                    failed += 1
                }
            }
        }
        _state.value.local.healthObservationSyncStates.filter { (_, syncStatus) -> syncStatus == LocalSubmissionStatus.PendingSync || syncStatus == LocalSubmissionStatus.Failed }.forEach { (key, _) ->
            val parts = key.split("|", limit = 2)
            val childId = parts.firstOrNull().orEmpty()
            val category = parts.getOrNull(1).orEmpty()
            val record = _state.value.local.familyHealthRecords["$childId-$category"]
            if (record == null) { mutate { it.copy(healthObservationSyncStates = it.healthObservationSyncStates + (key to LocalSubmissionStatus.Failed)) }; failed += 1 }
            else {
                mutate { it.copy(healthObservationSyncStates = it.healthObservationSyncStates + (key to LocalSubmissionStatus.Submitting)) }
                try {
                    val canonical = repository.submitHealthObservation(childId, category, record)
                    mutate { it.copy(familyHealthRecords = it.familyHealthRecords + ("$childId-$category" to canonical), healthObservationSyncStates = it.healthObservationSyncStates + (key to LocalSubmissionStatus.Submitted)) }
                } catch (error: Throwable) {
                    if (error is ApiError.Unauthorized) throw error
                    mutate { it.copy(healthObservationSyncStates = it.healthObservationSyncStates + (key to LocalSubmissionStatus.Failed)) }; failed += 1
                }
            }
        }
        _state.value.local.healthCheckinSyncStates.filter { (_, syncStatus) -> syncStatus == LocalSubmissionStatus.PendingSync || syncStatus == LocalSubmissionStatus.Failed }.forEach { (recordId, _) ->
            val record = _state.value.local.healthCheckins.firstOrNull { it.id == recordId }
            if (record == null) { mutate { it.copy(healthCheckinSyncStates = it.healthCheckinSyncStates + (recordId to LocalSubmissionStatus.Failed)) }; failed += 1 }
            else {
                mutate { it.copy(healthCheckinSyncStates = it.healthCheckinSyncStates + (recordId to LocalSubmissionStatus.Submitting)) }
                try {
                    val canonical = repository.submitHealthCheckin(record, record.version.takeIf { it > 0 })
                    mutate { local -> local.copy(healthCheckins = listOf(canonical) + local.healthCheckins.filterNot { it.id == recordId || (it.childId == canonical.childId && it.checkInDate == canonical.checkInDate) }, healthCheckinSyncStates = local.healthCheckinSyncStates + (recordId to LocalSubmissionStatus.Submitted) + (canonical.id to LocalSubmissionStatus.Submitted)) }
                } catch (error: Throwable) {
                    if (error is ApiError.Unauthorized) throw error
                    mutate { it.copy(healthCheckinSyncStates = it.healthCheckinSyncStates + (recordId to LocalSubmissionStatus.Failed)) }; failed += 1
                }
            }
        }
        _state.value.local.taskScopedSyncStates.filter { (_, syncStatus) -> syncStatus == LocalSubmissionStatus.PendingSync || syncStatus == LocalSubmissionStatus.Failed }.forEach { (key, _) ->
            val parts = key.split("|", limit = 2)
            val taskId = parts.firstOrNull().orEmpty()
            val studentId = parts.getOrNull(1).orEmpty()
            val status = _state.value.local.taskScopedStatuses[key]
            if (taskId.isBlank() || taskId == "missing-task") {
                // A pre-migration student-only record has no safe remote target.
                // Leave a visible failed item for the user instead of guessing a
                // task and contaminating another assessment's state.
                markTaskStatusSyncFailed(studentId, taskId)
                failed += 1
            } else if (status == null) {
                markTaskStatusSyncFailed(studentId, taskId)
                failed += 1
            } else {
                markTaskStatusSyncSubmitting(studentId, taskId)
                val expectedVersion = _state.value.local.taskScopedStatusVersions[key]
                    ?: if (_state.value.repositoryAcknowledged) _state.value.data?.students?.firstOrNull { it.id == studentId }?.taskVersion
                    else _state.value.data?.students?.firstOrNull { it.id == studentId }?.taskVersion
                try {
                    val acknowledgedVersion = repository.updateTaskStatus(taskId, studentId, status, _state.value.local.taskScopedReviewNotes[key], expectedVersion)
                    acknowledgeTaskStatusVersion(studentId, taskId, acknowledgedVersion)
                    markTaskStatusSynced(studentId, taskId)
                } catch (error: Throwable) {
                    if (error is ApiError.Unauthorized) throw error
                    markTaskStatusSyncFailed(studentId, taskId); failed += 1
                }
            }
        }
        if (failed > 0) throw IllegalStateException("仍有 $failed 条记录等待网络恢复后重试。")
    })

    fun submitTaskStatusCommand(studentId: String, status: TaskStatus, note: String?, taskId: String? = null) : Unit {
        if (taskId.isNullOrBlank()) {
            setWorkflow("task-status:$studentId", WorkflowCommandState(WorkflowCommandStatus.Failed, "任务信息缺失，请返回任务列表后重试。"))
            return
        }
        var acknowledgedVersion: Int? = null
        val key = _state.value.taskKey(taskId, studentId)
        executeWorkflow("task-status:$key", operation = {
        if (studentId.isBlank()) throw IllegalArgumentException("学生信息缺失。")
        val student = _state.value.data?.students?.firstOrNull { it.id == studentId }
            ?: throw IllegalArgumentException("未找到学生档案，请刷新名单后重试。")
        if (!canManageTaskStudent(student)) throw ApiError.Forbidden
        val current = _state.value.taskStatus(student, taskId)
        if (!current.allowsTransitionTo(status)) throw IllegalArgumentException("当前为${current.label}，不能直接变更为${status.label}。请按现场队列流程操作。")
        val expectedVersion = _state.value.local.taskScopedStatusVersions[key]
            ?: student.taskVersion
        submitReviewDecision(studentId, status, note.orEmpty().ifBlank { "已完成状态处理" }, taskId)
        markTaskStatusSyncPending(studentId, taskId)
        acknowledgedVersion = repository.updateTaskStatus(requireNotNull(taskId), studentId, status, note, expectedVersion)
        }, onSuccess = {
            acknowledgeTaskStatusVersion(studentId, taskId, acknowledgedVersion)
            updateTaskStatusSyncStatus(studentId, taskId, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync)
        }, onFailure = { markTaskStatusSyncFailed(studentId, taskId) }, onError = { error -> if (error is ApiError.Conflict) resetTaskStatusProjectionAfterConflict(studentId, taskId) })
    }

    private fun markTaskStatusSynced(studentId: String, taskId: String? = null) = updateTaskStatusSyncStatus(studentId, taskId, LocalSubmissionStatus.Submitted)
    private fun markTaskStatusSyncPending(studentId: String, taskId: String? = null) = updateTaskStatusSyncStatus(studentId, taskId, LocalSubmissionStatus.PendingSync)
    private fun markTaskStatusSyncSubmitting(studentId: String, taskId: String? = null) = updateTaskStatusSyncStatus(studentId, taskId, LocalSubmissionStatus.Submitting)
    private fun markTaskStatusSyncFailed(studentId: String, taskId: String? = null) = updateTaskStatusSyncStatus(studentId, taskId, LocalSubmissionStatus.Failed)
    private fun updateTaskStatusSyncStatus(studentId: String, taskId: String? = null, status: LocalSubmissionStatus) = mutate { local ->
        val key = _state.value.taskKey(taskId, studentId)
        local.copy(taskScopedSyncStates = local.taskScopedSyncStates + (key to status))
    }
    /** Stores the acknowledged task-row version used by the next teacher edit. */
    private fun acknowledgeTaskStatusVersion(studentId: String, taskId: String?, serverVersion: Int?) {
        if (!repository.supportsRemoteAcknowledgement) return
        val next = serverVersion ?: return
        mutate { local -> local.copy(taskScopedStatusVersions = local.taskScopedStatusVersions + (_state.value.taskKey(taskId, studentId) to next)) }
    }
    /** Removes a stale local overlay after the server rejects an optimistic write. */
    private fun resetTaskStatusProjectionAfterConflict(studentId: String, taskId: String? = null) {
        mutate { local ->
            val key = _state.value.taskKey(taskId, studentId)
            local.copy(
                taskScopedStatuses = local.taskScopedStatuses - key,
                taskScopedStatusVersions = local.taskScopedStatusVersions - key,
                taskScopedSyncStates = local.taskScopedSyncStates + (key to LocalSubmissionStatus.Failed)
            )
        }
    }
    internal fun updateBodyAssessmentSyncStatus(studentId: String, status: LocalSubmissionStatus) = mutate { local -> local.copy(bodyAssessmentSyncStates = local.bodyAssessmentSyncStates + (studentId to status)) }
    fun updateStudentTaskStatus(studentId: String, status: TaskStatus, taskId: String? = null) {
        val student = _state.value.data?.students?.firstOrNull { it.id == studentId } ?: return
        val current = _state.value.taskStatus(student, taskId)
        if (!current.allowsTransitionTo(status)) return
        mutate { local -> local.copy(taskScopedStatuses = local.taskScopedStatuses + (_state.value.taskKey(taskId, studentId) to status)) }
    }
    fun submitReviewDecision(studentId: String, status: TaskStatus, note: String, taskId: String? = null) {
        val trimmed = note.trim()
        if (trimmed.isBlank()) return
        val student = _state.value.data?.students?.firstOrNull { it.id == studentId } ?: return
        val current = _state.value.taskStatus(student, taskId)
        if (!current.allowsTransitionTo(status)) return
        mutate { local -> local.copy(taskScopedStatuses = local.taskScopedStatuses + (_state.value.taskKey(taskId, studentId) to status), taskScopedReviewNotes = local.taskScopedReviewNotes + (_state.value.taskKey(taskId, studentId) to trimmed)) }
    }
    fun updateSettings(notificationsEnabled: Boolean? = null, reduceMotion: Boolean? = null, voiceGuidanceEnabled: Boolean? = null, analyticsEnabled: Boolean? = null) {
        mutate { local -> local.copy(settings = local.settings.copy(notificationsEnabled = notificationsEnabled ?: local.settings.notificationsEnabled, reduceMotion = reduceMotion ?: local.settings.reduceMotion, voiceGuidanceEnabled = voiceGuidanceEnabled ?: local.settings.voiceGuidanceEnabled, analyticsEnabled = analyticsEnabled ?: local.settings.analyticsEnabled)) }
        com.xiangshang.youth.core.util.FrontendTelemetry.configure(_state.value.local.settings.analyticsEnabled && _state.value.repositoryAcknowledged)
    }
    /** Submission data must come from the validated upload form. */
    fun submitUpload(taskId: String, attendance: Int, notes: String, attachment: String, attachmentReference: String? = null) = saveCourseUpload(taskId, attendance, notes, attachment, attachmentReference, submit = true)
    fun checkInToday(activityType: String = "家庭运动", durationMinutes: Int = 20, intensity: String = "moderate", feeling: String? = null, completedRecommended: Boolean = false, parentNote: String? = null) {
        val childId = _state.value.selectedChild?.id ?: return
        val today = BusinessClock.day()
        val previous = _state.value.local.healthCheckins.firstOrNull { it.childId == childId && it.checkInDate == today }
        val record = com.xiangshang.youth.core.service.HealthCheckInRecord(previous?.id ?: java.util.UUID.randomUUID().toString(), childId, today, activityType.trim().ifBlank { "家庭运动" }, durationMinutes.coerceIn(1, 1440), intensity, feeling?.trim()?.takeIf { it.isNotEmpty() }, completedRecommended, parentNote?.trim()?.takeIf { it.isNotEmpty() }, previous?.version ?: 0)
        mutate { local -> local.copy(checkedInToday = true, checkedInDate = today, checkedInDates = local.checkedInDates + today, healthCheckins = listOf(record) + local.healthCheckins.filterNot { it.childId == childId && it.checkInDate == today }, healthCheckinSyncStates = local.healthCheckinSyncStates + (record.id to if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Submitted)) }
        if (repository.supportsRemoteAcknowledgement && !_state.value.isOffline) {
            viewModelScope.launch {
                mutate { it.copy(healthCheckinSyncStates = it.healthCheckinSyncStates + (record.id to LocalSubmissionStatus.Submitting)) }
                runCatching { repository.submitHealthCheckin(record, previous?.version) }
                    .onSuccess { canonical -> mutate { local -> local.copy(healthCheckins = listOf(canonical) + local.healthCheckins.filterNot { it.id == record.id || (it.childId == childId && it.checkInDate == today) }, healthCheckinSyncStates = local.healthCheckinSyncStates + (record.id to LocalSubmissionStatus.Submitted) + (canonical.id to LocalSubmissionStatus.Submitted)) } }
                    .onFailure { error -> if (error is ApiError.Unauthorized) handleDashboardFailure(error) else mutate { it.copy(healthCheckinSyncStates = it.healthCheckinSyncStates + (record.id to LocalSubmissionStatus.Failed)) } }
            }
        }
    }
    fun clearError() { _state.value = _state.value.copy(error = null) }
    private fun hasValidatedNetwork(): Boolean = connectivityManager.activeNetwork?.let { network ->
        connectivityManager.getNetworkCapabilities(network)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
    } ?: false
    /** Builds a mobile profile from server-owned claims, never from local demo defaults. */
    internal fun profileFromAuth(payload: com.xiangshang.youth.core.service.AuthResponse): UserProfile = profileFromClaims(
        payload.user,
        payload.accountRoles.orEmpty().map { it.roleCode to it },
        payload.roles.map { it.code to null },
        payload.activeRole
    )
    private fun profileFromSession(payload: com.xiangshang.youth.core.service.AuthSessionClaims): UserProfile = profileFromClaims(
        payload.user,
        payload.accountRoles.orEmpty().map { it.roleCode to it },
        payload.roles.map { it.code to null },
        payload.activeRole
    )
    private fun profileFromClaims(
        user: com.xiangshang.youth.core.service.BackendUser,
        accountRoles: List<Pair<String, com.xiangshang.youth.core.service.MobileAccountRole?>>,
        legacyRoles: List<Pair<String, com.xiangshang.youth.core.service.MobileAccountRole?>>,
        activeRoleCode: String? = user.roleCode
    ): UserProfile {
        val allRoles = if (accountRoles.isNotEmpty()) accountRoles else legacyRoles
        val primary = UserRole.fromBackendCode(activeRoleCode ?: user.role) ?: error("账号角色不支持移动端")
        val allowedRoles = allRoles.mapNotNull { UserRole.fromBackendCode(it.first) }.ifEmpty { listOf(primary) }
        val activeClaim = accountRoles.firstOrNull { it.first == primary.backendCode }?.second
        return UserProfile(
            user.id, user.name, user.phone, primary, user.schoolName,
            user.avatarInitials ?: user.name.take(1), user.roleCode, user.schoolId,
            allowedRoles,
            user.authorizedClassIds.ifEmpty { activeClaim?.authorizedClassIds.orEmpty() },
            user.capabilities.ifEmpty { activeClaim?.capabilities.orEmpty() }
        )
    }
    private fun setOffline(value: Boolean) {
        _state.value = _state.value.copy(isOffline = value)
        // Restore/relaunch can report an online path without a preceding
        // offline transition. Retry persisted writes whenever a session is
        // usable and the sync command is not already running.
        if (!value && _state.value.profile == null && _state.value.local.sessionActive && !_state.value.restoringSession) {
            restoreSession()
        } else if (!value && _state.value.profile != null && _state.value.data == null && !_state.value.loading) {
            refreshDashboard()
        } else if (!value && _state.value.profile != null && _state.value.pendingSyncCount > 0 && !workflowState("sync-pending").isSubmitting) {
            syncPendingRecords()
        }
    }
    private fun restoreSession() {
        sessionRestoreJob?.cancel()
        val generation = ++sessionGeneration
        sessionRestoreJob = viewModelScope.launch {
            val local = _state.value.local
            _state.value = _state.value.copy(loading = true, restoringSession = true)
            try {
                val (profile, data) = if (repository.supportsRemoteAcknowledgement) {
                    val payload = ApiClient.retrofit.create(AuthApi::class.java).session().data ?: error("登录状态已失效")
                    val restored = profileFromSession(payload)
                    repository.configureSession(restored)
                    restored to repository.dashboard()
                } else null to repository.dashboard()
                if (generation != sessionGeneration) return@launch
                val accountBucket = local.accountBucketName
                    ?.let { name -> UserRole.values().firstOrNull { it.name == name } }
                    ?: UserRole.Parent
                // Restore authentication/data, but do not restore the last workbench.
                // The next launch must show RoleSelect so a stale principal session
                // cannot prevent parent/teacher entry.
                val visibleProfile = profile ?: UserProfile(
                    "u1", local.parentAccountName ?: "王女士", local.sessionPhone.ifBlank { "未绑定手机号" }, accountBucket, data.school.name,
                    availableRoles = listOf(accountBucket)
                )
                val (reconciledLocal, selected) = reconcileChildScope(visibleProfile, data, local)
                featureStore.save(reconciledLocal)
                _state.value = _state.value.copy(profile = visibleProfile, role = null, data = data, selectedChild = selected, local = reconciledLocal, loading = false, restoringSession = false)
                // The network callback may have fired before the asynchronous
                // session restore populated profile. Retry persisted writes now
                // that the authenticated dashboard is available.
                if (!_state.value.isOffline && _state.value.pendingSyncCount > 0) syncPendingRecords()
            } catch (_: CancellationException) {
                // logout or a newer restore owns the screen now.
                return@launch
            } catch (error: Throwable) {
                if (generation != sessionGeneration) return@launch
                if (error is ApiError.Unauthorized) {
                    featureStore.clear()
                    _state.value = AppUiState(error = error.message, restoringSession = false)
                } else {
                    // A transient network/backend failure is not proof that the
                    // credentials are invalid. Preserve the durable session and
                    // offline writes; only an explicit 401 clears authentication.
                    _state.value = _state.value.copy(
                        loading = false,
                        restoringSession = false,
                        error = error.message ?: "暂时无法恢复数据，请检查网络后重试"
                    )
                }
            }
        }
    }
    internal fun handleDashboardFailure(error: Throwable) {
        if (error is ApiError.Unauthorized) {
            featureStore.clear()
            _state.value = AppUiState(error = error.message)
        } else _state.value = _state.value.copy(loading = false, error = error.message)
    }
    internal fun mutate(transform: (LocalFeatureState) -> LocalFeatureState) {
        val local = transform(_state.value.local)
        featureStore.save(local)
        _state.value = _state.value.copy(local = local)
        if (_state.value.pendingSyncCount > 0) PendingSyncScheduler.enqueue(getApplication())
    }

    internal fun releaseBackgroundResources() {
        if (!networkCallbackRegistered) return
        runCatching { connectivityManager.unregisterNetworkCallback(networkCallback) }
        networkCallbackRegistered = false
    }

    override fun onCleared() {
        releaseBackgroundResources()
        super.onCleared()
    }
    /** Narrow state seam for the remote-content domain extensions. */
    internal fun updateRemoteTargetState(transform: (AppUiState) -> AppUiState) {
        _state.value = transform(_state.value)
    }
}
