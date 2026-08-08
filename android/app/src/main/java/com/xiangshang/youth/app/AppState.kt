package com.xiangshang.youth.app

import android.app.Application
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
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
import com.xiangshang.youth.core.service.SupportMessage
import com.xiangshang.youth.core.service.ExpertAppointment
import com.xiangshang.youth.core.service.CourseUploadRecord
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.service.ApiClient
import com.xiangshang.youth.core.service.ApiError
import com.xiangshang.youth.core.util.ChildBindingValidator
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

enum class WorkflowCommandStatus { Idle, Submitting, Succeeded, Failed }
data class WorkflowCommandState(
    val status: WorkflowCommandStatus = WorkflowCommandStatus.Idle,
    val message: String? = null
) {
    val isSubmitting: Boolean get() = status == WorkflowCommandStatus.Submitting
}

data class AppUiState(
    val profile: UserProfile? = null,
    val role: UserRole? = null,
    val data: DashboardData? = null,
    val selectedChild: Student? = null,
    val loading: Boolean = false,
    val error: String? = null,
    val local: LocalFeatureState = LocalFeatureState(),
    val restoringSession: Boolean = false,
    val isOffline: Boolean = false,
    val reportOverrides: Map<String, DiagnosisReport> = emptyMap(),
    val reportLoadingStudentId: String? = null,
    val reportError: String? = null,
    val workflowStates: Map<String, WorkflowCommandState> = emptyMap()
) {
    val unreadMessageCount: Int get() = if (!local.settings.notificationsEnabled) 0 else data?.messages?.count { !it.isRead && it.id !in local.readMessageIds } ?: 0
    /** Local writes that still need acknowledgement or a retry. */
    val pendingSyncCount: Int get() = local.activityRegistrations.count { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed } + local.expertAppointments.count { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed } + local.courseUploads.count { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed } + local.taskStatusSyncStates.values.count { it == LocalSubmissionStatus.PendingSync || it == LocalSubmissionStatus.Failed }
}
class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val connectivityManager = application.getSystemService(ConnectivityManager::class.java)
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { setOffline(false) }
        override fun onLost(network: Network) { setOffline(!hasValidatedNetwork()) }
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) { setOffline(!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) }
    }
    private val repository: YouthRepository = RepositoryProvider.create()
    private val featureStore = LocalFeatureStore(application)
    private val initialLocal = featureStore.load()
    private val _state = MutableStateFlow(AppUiState(local = initialLocal, restoringSession = initialLocal.sessionActive))
    val state: StateFlow<AppUiState> = _state.asStateFlow()
    init {
        setOffline(!hasValidatedNetwork())
        runCatching { connectivityManager.registerDefaultNetworkCallback(networkCallback) }
        if (_state.value.local.sessionActive) restoreSession()
    }
    fun login(identifier: String = "", displayName: String? = null, onSuccess: () -> Unit = {}) = viewModelScope.launch {
        _state.value = _state.value.copy(loading = true, restoringSession = false)
        runCatching { repository.dashboard() }.onSuccess { data ->
            val profilePhone = AuthIdentity.displayPhone(identifier)
            val profileName = displayName?.trim().takeUnless { it.isNullOrEmpty() } ?: "王女士"
            val profile = UserProfile("u1", profileName, profilePhone, UserRole.Parent, data.school.name)
            val selected = data.students.firstOrNull { it.id == _state.value.local.selectedChildId && it.id in _state.value.local.boundChildIds }
            val local = _state.value.local.copy(sessionActive = true, sessionPhone = profile.phone, sessionRoleName = null, parentAccountName = profileName, selectedChildId = selected?.id)
            featureStore.save(local)
            _state.value = AppUiState(profile, data = data, selectedChild = selected, local = local)
            onSuccess()
        }.onFailure { handleDashboardFailure(it) }
    }
    fun refreshDashboard(onSuccess: () -> Unit = {}) = viewModelScope.launch {
        // Do not turn an explicit refresh tap into a network request while the
        // device is offline. Cached/Mock data remains usable and the banner
        // explains why the refresh is deferred.
        if (_state.value.profile == null || _state.value.loading || _state.value.isOffline) return@launch
        _state.value = _state.value.copy(loading = true, error = null)
        runCatching { repository.dashboard() }.onSuccess { data ->
            val selected = _state.value.selectedChild?.id?.let { id -> data.students.firstOrNull { it.id == id && id in _state.value.local.boundChildIds } }
            _state.value = _state.value.copy(data = data, selectedChild = selected, loading = false)
            onSuccess()
        }.onFailure { handleDashboardFailure(it) }
    }
    fun chooseRole(role: UserRole) {
        val local = _state.value.local.copy(sessionRoleName = role.name)
        featureStore.save(local)
        val parentName = _state.value.local.parentAccountName ?: _state.value.profile?.takeIf { it.role == UserRole.Parent }?.name ?: "王女士"
        _state.value = _state.value.copy(local = local, role = role, profile = _state.value.profile?.copy(role = role, name = if (role == UserRole.Teacher) "李老师" else if (role == UserRole.Principal) "周校长" else parentName))
    }
    fun clearRoleSelection() {
        val local = _state.value.local.copy(sessionRoleName = null)
        featureStore.save(local)
        _state.value = _state.value.copy(local = local, role = null)
    }
    fun selectPrincipalTask(taskId: String) = mutate { it.copy(selectedPrincipalTaskId = taskId) }
    fun setTeacherSportsWorkbench(enabled: Boolean) = mutate { it.copy(teacherUsesSportsWorkbench = enabled) }
    fun chooseChild(student: Student) {
        mutate { it.copy(selectedChildId = student.id) }
        _state.value = _state.value.copy(selectedChild = student)
    }
    fun markMessageRead(messageId: String) = mutate { it.copy(readMessageIds = it.readMessageIds + messageId) }
    fun markAllMessagesRead() = mutate { local ->
        local.copy(readMessageIds = local.readMessageIds + (_state.value.data?.messages?.map { it.id }.orEmpty()))
    }
    fun bindChild(name: String, code: String): Boolean {
        val child = ChildBindingValidator.findMatch(_state.value.data?.students.orEmpty(), name, code) ?: return false
        mutate { it.copy(boundChildIds = it.boundChildIds + child.id) }
        if (_state.value.selectedChild == null) chooseChild(child)
        return true
    }
    fun logout() { ApiClient.clearToken(); featureStore.clear(); _state.value = AppUiState() }
    fun report(student: Student): DiagnosisReport = _state.value.reportOverrides[student.id] ?: repository.report(student)
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
    fun clearWorkflowState(key: String) { _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState())) }

    private fun executeWorkflow(key: String, operation: suspend () -> Unit, onSuccess: (() -> Unit)? = null, onFailure: (() -> Unit)? = null) = viewModelScope.launch {
        val current = workflowState(key)
        if (current.isSubmitting) return@launch
        _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState(WorkflowCommandStatus.Submitting)))
        try {
            operation()
            onSuccess?.invoke()
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState(WorkflowCommandStatus.Succeeded, "已提交并完成同步确认。")))
        } catch (error: kotlinx.coroutines.CancellationException) {
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState()))
            throw error
        } catch (error: Throwable) {
            if (error is ApiError.Unauthorized) {
                handleDashboardFailure(error)
                return@launch
            }
            onFailure?.invoke()
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState(WorkflowCommandStatus.Failed, error.message ?: "提交失败，请重试")))
        }
    }

    fun submitActivityCommand(contactName: String, phone: String) = executeWorkflow("activity:health-growth-season-2026", {
        if (contactName.isBlank() || phone.filter(Char::isDigit).length != 11) throw IllegalArgumentException("请填写有效的联系人和手机号。")
        registerActivity(contactName.trim(), phone.trim())
        val record = _state.value.local.activityRegistrations.firstOrNull { it.activityId == "health-growth-season-2026" } ?: throw IllegalArgumentException("报名信息不完整。")
        repository.submitActivity(record)
    }, onSuccess = { markActivitySynced("health-growth-season-2026") }, onFailure = { markActivitySyncFailed("health-growth-season-2026") })

    fun submitExpertCommand(name: String, date: String, note: String) = executeWorkflow("expert:$name", {
        if (date.isBlank() || note.trim().isBlank()) throw IllegalArgumentException("请填写咨询时间和说明。")
        bookExpert(name, date.trim(), note.trim())
        val record = _state.value.local.expertAppointments.firstOrNull { it.expertName == name } ?: throw IllegalArgumentException("预约信息不完整。")
        repository.bookExpert(record)
    }, onSuccess = { markExpertSynced(name) }, onFailure = { markExpertSyncFailed(name) })

    fun submitCourseUploadCommand(taskId: String, attendance: Int, notes: String, attachment: String) = executeWorkflow("course:$taskId", {
        if (attendance <= 0 || notes.trim().isBlank() || attachment.trim().isBlank()) throw IllegalArgumentException("提交前请补齐出勤人数、课堂记录和附件。")
        saveCourseUpload(taskId, attendance, notes, attachment, true)
        val record = _state.value.local.courseUploads.firstOrNull { it.taskId == taskId } ?: throw IllegalArgumentException("课程记录不完整。")
        repository.uploadCourse(record)
    }, onSuccess = { markCourseSynced(taskId) }, onFailure = { markCourseSyncFailed(taskId) })

    fun syncPendingRecords() = executeWorkflow("sync-pending", {
        if (_state.value.profile == null) throw IllegalStateException("请登录后再同步本机记录。")
        if (_state.value.isOffline) throw IllegalStateException("当前网络不可用，记录会继续保存在本机。")
        var failed = 0
        _state.value.local.activityRegistrations.filter { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed }.forEach { record ->
            markActivitySyncSubmitting(record.activityId)
            try {
                repository.submitActivity(record)
                markActivitySynced(record.activityId)
            } catch (error: Throwable) {
                if (error is ApiError.Unauthorized) throw error
                markActivitySyncFailed(record.activityId); failed += 1
            }
        }
        _state.value.local.expertAppointments.filter { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed }.forEach { record ->
            markExpertSyncSubmitting(record.expertName)
            try {
                repository.bookExpert(record)
                markExpertSynced(record.expertName)
            } catch (error: Throwable) {
                if (error is ApiError.Unauthorized) throw error
                markExpertSyncFailed(record.expertName); failed += 1
            }
        }
        _state.value.local.courseUploads.filter { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed }.forEach { record ->
            markCourseSyncSubmitting(record.taskId)
            try {
                repository.uploadCourse(record)
                markCourseSynced(record.taskId)
            } catch (error: Throwable) {
                if (error is ApiError.Unauthorized) throw error
                markCourseSyncFailed(record.taskId); failed += 1
            }
        }
        _state.value.local.taskStatusSyncStates.filter { (_, syncStatus) -> syncStatus == LocalSubmissionStatus.PendingSync || syncStatus == LocalSubmissionStatus.Failed }.forEach { (studentId, _) ->
            val status = _state.value.local.studentTaskStatuses[studentId]
            if (status == null) {
                markTaskStatusSyncFailed(studentId)
                failed += 1
            } else {
                markTaskStatusSyncSubmitting(studentId)
                try {
                    repository.updateTaskStatus(studentId, status, _state.value.local.reviewNotes[studentId])
                    markTaskStatusSynced(studentId)
                } catch (error: Throwable) {
                    if (error is ApiError.Unauthorized) throw error
                    markTaskStatusSyncFailed(studentId); failed += 1
                }
            }
        }
        if (failed > 0) throw IllegalStateException("仍有 $failed 条记录等待网络恢复后重试。")
    })

    fun submitTaskStatusCommand(studentId: String, status: TaskStatus, note: String?) = executeWorkflow("task-status:$studentId", operation = {
        if (studentId.isBlank()) throw IllegalArgumentException("学生信息缺失。")
        val student = _state.value.data?.students?.firstOrNull { it.id == studentId }
            ?: throw IllegalArgumentException("未找到学生档案，请刷新名单后重试。")
        val current = _state.value.local.studentTaskStatuses[studentId] ?: student.taskStatus
        if (!current.allowsTransitionTo(status)) throw IllegalArgumentException("当前为${current.label}，不能直接变更为${status.label}。请按现场队列流程操作。")
        submitReviewDecision(studentId, status, note.orEmpty().ifBlank { "已完成状态处理" })
        markTaskStatusSyncPending(studentId)
        repository.updateTaskStatus(studentId, status, note)
    }, onSuccess = { markTaskStatusSynced(studentId) }, onFailure = { markTaskStatusSyncFailed(studentId) })

    fun submitClassPostCommand(author: String, content: String) = executeWorkflow("post:$author", operation = {
        if (content.trim().isBlank()) throw IllegalArgumentException("动态内容不能为空。")
        publishPost(author, content.trim())
        repository.publishClassPost(author, content.trim())
    })

    fun submitSupportCommand(content: String) = executeWorkflow("support", operation = {
        if (content.trim().isBlank()) throw IllegalArgumentException("请输入咨询内容。")
        sendSupport(content.trim())
        repository.sendSupportMessage(content.trim())
    })
    fun registerActivity(contactName: String, phone: String) {
        if (contactName.isBlank() || phone.filter(Char::isDigit).length != 11) return
        mutate { local ->
            val record = com.xiangshang.youth.core.service.ActivityRegistration(activityId = "health-growth-season-2026", contactName = contactName.trim(), phone = phone, status = LocalSubmissionStatus.PendingSync)
            local.copy(activityRegistered = true, activityRegistrations = listOf(record) + local.activityRegistrations.filterNot { it.activityId == record.activityId })
        }
    }
    fun completeAssessment(category: String) = mutate { it.copy(completedAssessments = it.completedAssessments + "${_state.value.selectedChild?.id ?: "anonymous"}-$category") }
    /** Progress can originate from a resumed player or a local draft; keep the
     * persisted value valid even if a caller supplies an out-of-range value. */
    fun updateCourseProgress(title: String, progress: Float) = mutate {
        it.copy(courseProgress = it.courseProgress + (title to progress.coerceIn(0f, 1f)))
    }
    fun sendSupport(text: String) { if (text.isBlank()) return; mutate { it.copy(supportMessages = it.supportMessages + SupportMessage(text, true) + SupportMessage("已收到您的咨询，客服老师会在工作时间内为您回复。", false)) } }
    fun publishPost(author: String, content: String) { if (content.isBlank()) return; mutate { it.copy(classPosts = listOf(ClassPost(author = author, content = content)) + it.classPosts) } }
    fun updatePost(id: String, content: String) { if (content.isBlank()) return; mutate { local -> local.copy(classPosts = local.classPosts.map { if (it.id == id) it.copy(content = content) else it }) } }
    fun togglePostLike(postId: String) = mutate { local -> local.copy(likedPostIds = if (postId in local.likedPostIds) local.likedPostIds - postId else local.likedPostIds + postId) }
    fun addPostComment(postId: String, content: String) { val trimmed = content.trim(); if (trimmed.isBlank()) return; mutate { local -> local.copy(postComments = local.postComments + (postId to (local.postComments[postId].orEmpty() + trimmed))) } }
    fun saveDraft(key: String, content: String) = mutate { it.copy(drafts = it.drafts + (key to content)) }
    fun clearDraft(key: String) = mutate { it.copy(drafts = it.drafts - key) }
    fun bookExpert(name: String, date: String, note: String) {
        if (date.isBlank() || note.isBlank()) return
        // Keep the local command idempotent while the remote appointment API is
        // still a seam. Reopening an expert card must not create duplicate rows.
        if (_state.value.local.expertAppointments.any {
                it.expertName == name &&
                    (it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Submitted)
            }) return
        mutate { it.copy(expertAppointments = listOf(ExpertAppointment(expertName = name, preferredDate = date, note = note, status = LocalSubmissionStatus.PendingSync)) + it.expertAppointments) }
    }
    fun saveCourseUpload(taskId: String, attendance: Int, notes: String, attachment: String, submit: Boolean) { if (attendance < 0 || (submit && (notes.isBlank() || attachment.isBlank()))) return; mutate { local -> val record=CourseUploadRecord(taskId=taskId, attendanceCount=attendance, notes=notes.trim(), attachmentName=attachment, status=if (submit) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Draft); local.copy(courseUploads=listOf(record)+local.courseUploads.filterNot { it.taskId==taskId }, uploadedTaskIds=if (submit) local.uploadedTaskIds+taskId else local.uploadedTaskIds) } }
    private fun markActivitySynced(activityId: String) = updateActivitySyncStatus(activityId, LocalSubmissionStatus.Submitted)
    private fun markActivitySyncSubmitting(activityId: String) = updateActivitySyncStatus(activityId, LocalSubmissionStatus.Submitting)
    private fun markActivitySyncFailed(activityId: String) = updateActivitySyncStatus(activityId, LocalSubmissionStatus.Failed)
    private fun updateActivitySyncStatus(activityId: String, status: LocalSubmissionStatus) = mutate { local -> local.copy(activityRegistrations = local.activityRegistrations.map { if (it.activityId == activityId) it.copy(status = status) else it }) }
    private fun markExpertSynced(name: String) = updateExpertSyncStatus(name, LocalSubmissionStatus.Submitted)
    private fun markExpertSyncSubmitting(name: String) = updateExpertSyncStatus(name, LocalSubmissionStatus.Submitting)
    private fun markExpertSyncFailed(name: String) = updateExpertSyncStatus(name, LocalSubmissionStatus.Failed)
    private fun updateExpertSyncStatus(name: String, status: LocalSubmissionStatus) = mutate { local -> local.copy(expertAppointments = local.expertAppointments.map { if (it.expertName == name) it.copy(status = status) else it }) }
    private fun markCourseSynced(taskId: String) = updateCourseSyncStatus(taskId, LocalSubmissionStatus.Submitted)
    private fun markCourseSyncSubmitting(taskId: String) = updateCourseSyncStatus(taskId, LocalSubmissionStatus.Submitting)
    private fun markCourseSyncFailed(taskId: String) = updateCourseSyncStatus(taskId, LocalSubmissionStatus.Failed)
    private fun updateCourseSyncStatus(taskId: String, status: LocalSubmissionStatus) = mutate { local -> local.copy(courseUploads = local.courseUploads.map { if (it.taskId == taskId) it.copy(status = status) else it }) }
    private fun markTaskStatusSynced(studentId: String) = updateTaskStatusSyncStatus(studentId, LocalSubmissionStatus.Submitted)
    private fun markTaskStatusSyncPending(studentId: String) = updateTaskStatusSyncStatus(studentId, LocalSubmissionStatus.PendingSync)
    private fun markTaskStatusSyncSubmitting(studentId: String) = updateTaskStatusSyncStatus(studentId, LocalSubmissionStatus.Submitting)
    private fun markTaskStatusSyncFailed(studentId: String) = updateTaskStatusSyncStatus(studentId, LocalSubmissionStatus.Failed)
    private fun updateTaskStatusSyncStatus(studentId: String, status: LocalSubmissionStatus) = mutate { local -> local.copy(taskStatusSyncStates = local.taskStatusSyncStates + (studentId to status)) }
    fun updateStudentTaskStatus(studentId: String, status: TaskStatus) {
        val current = _state.value.local.studentTaskStatuses[studentId]
            ?: _state.value.data?.students?.firstOrNull { it.id == studentId }?.taskStatus
            ?: return
        if (!current.allowsTransitionTo(status)) return
        mutate { local -> local.copy(studentTaskStatuses = local.studentTaskStatuses + (studentId to status)) }
    }
    fun submitReviewDecision(studentId: String, status: TaskStatus, note: String) {
        val trimmed = note.trim()
        if (trimmed.isBlank()) return
        val current = _state.value.local.studentTaskStatuses[studentId]
            ?: _state.value.data?.students?.firstOrNull { it.id == studentId }?.taskStatus
            ?: return
        if (!current.allowsTransitionTo(status)) return
        mutate { local -> local.copy(studentTaskStatuses = local.studentTaskStatuses + (studentId to status), reviewNotes = local.reviewNotes + (studentId to trimmed)) }
    }
    fun updateSettings(notificationsEnabled: Boolean? = null, reduceMotion: Boolean? = null) = mutate { local -> local.copy(settings = local.settings.copy(notificationsEnabled = notificationsEnabled ?: local.settings.notificationsEnabled, reduceMotion = reduceMotion ?: local.settings.reduceMotion)) }
    fun submitUpload(taskId: String) = saveCourseUpload(taskId, 0, "已确认课后测评记录", "课堂记录.jpg", true)
    fun checkInToday() {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        mutate { it.copy(checkedInToday = true, checkedInDate = today) }
    }
    fun clearError() { _state.value = _state.value.copy(error = null) }
    override fun onCleared() {
        runCatching { connectivityManager.unregisterNetworkCallback(networkCallback) }
        super.onCleared()
    }
    private fun hasValidatedNetwork(): Boolean = connectivityManager.activeNetwork?.let { network ->
        connectivityManager.getNetworkCapabilities(network)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
    } ?: false
    private fun setOffline(value: Boolean) {
        val wasOffline = _state.value.isOffline
        _state.value = _state.value.copy(isOffline = value)
        if (wasOffline && !value && _state.value.profile != null && _state.value.pendingSyncCount > 0) syncPendingRecords()
    }
    private fun restoreSession() = viewModelScope.launch {
        val local = _state.value.local
        _state.value = _state.value.copy(loading = true, restoringSession = true)
        runCatching { repository.dashboard() }.onSuccess { data ->
            val selected = data.students.firstOrNull { it.id == local.selectedChildId && it.id in local.boundChildIds }
            // Restore authentication/data, but do not restore the last workbench.
            // The next launch must show RoleSelect so a stale principal session
            // cannot prevent parent/teacher entry.
            _state.value = _state.value.copy(profile = UserProfile("u1", local.parentAccountName ?: "王女士", local.sessionPhone.ifBlank { "13800138000" }, UserRole.Parent, data.school.name), role = null, data = data, selectedChild = selected, loading = false, restoringSession = false)
        }.onFailure { error ->
            if (error is ApiError.Unauthorized) {
                featureStore.clear()
                _state.value = AppUiState(error = error.message, restoringSession = false)
            } else {
                // A persisted session whose dashboard cannot be refreshed is not
                // a usable authenticated state. Clear it before returning to the
                // login screen so the next launch cannot loop through RoleSelect
                // with a nil dashboard or keep retrying stale credentials.
                featureStore.clear()
                _state.value = AppUiState(error = error.message, restoringSession = false)
            }
        }
    }
    private fun handleDashboardFailure(error: Throwable) {
        if (error is ApiError.Unauthorized) {
            featureStore.clear()
            _state.value = AppUiState(error = error.message)
        } else _state.value = _state.value.copy(loading = false, error = error.message)
    }
    private fun mutate(transform: (LocalFeatureState) -> LocalFeatureState) { val local = transform(_state.value.local); featureStore.save(local); _state.value = _state.value.copy(local = local) }
}
