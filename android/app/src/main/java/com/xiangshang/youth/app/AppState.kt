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
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { setOffline(false) }
        override fun onLost(network: Network) { setOffline(!hasValidatedNetwork()) }
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) { setOffline(!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) }
    }
    internal val repository: YouthRepository = RepositoryProvider.create()
    private val featureStore = LocalFeatureStore(application)
    private val initialLocal = featureStore.load()
    /** A logout may happen while a cold-start restore is awaiting the
     * dashboard.  Keep a cancellable handle and a generation token so the
     * old account can never repopulate state after the user chose to exit. */
    private var sessionRestoreJob: Job? = null
    private var sessionGeneration = 0L
    internal val _state = MutableStateFlow(AppUiState(local = initialLocal, restoringSession = initialLocal.sessionActive, repositoryAcknowledged = repository.supportsRemoteAcknowledgement))
    val state: StateFlow<AppUiState> = _state.asStateFlow()
    init {
        setOffline(!hasValidatedNetwork())
        runCatching { connectivityManager.registerDefaultNetworkCallback(networkCallback) }
        if (_state.value.local.sessionActive) restoreSession()
    }
    fun login(identifier: String = "", verificationCode: String? = null, password: String? = null, displayName: String? = null, accountRole: UserRole? = null, onSuccess: () -> Unit = {}) = viewModelScope.launch {
        // Do not allow a fast double tap on WeChat/phone login to race two
        // dashboard loads and two session writes.
        if (_state.value.loading) return@launch
        if (repository.supportsRemoteAcknowledgement && identifier == AuthIdentity.wechatAuthorizationIdentifier) {
            _state.value = _state.value.copy(loading = true, error = null)
            runCatching {
                ApiClient.retrofit.create(AuthApi::class.java).startWechatAuthorization().data
                    ?: error("微信授权配置响应为空")
            }.onSuccess { authorization ->
                runCatching {
                    getApplication<Application>().startActivity(Intent(Intent.ACTION_VIEW, authorization.authorizeUrl.toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }.onFailure { _state.value = _state.value.copy(error = "无法打开微信授权，请确认已安装微信或改用手机号登录。") }
            }.onFailure { _state.value = _state.value.copy(error = it.localizedMessage ?: "微信授权暂不可用，请稍后重试。") }
            _state.value = _state.value.copy(loading = false)
            return@launch
        }
        _state.value = _state.value.copy(loading = true, restoringSession = false)
        runCatching {
            if (repository.supportsRemoteAcknowledgement) {
                val payload = ApiClient.retrofit.create(AuthApi::class.java).login(LoginRequest(identifier, verificationCode, password)).data
                    ?: error("登录响应为空")
                ApiClient.updateSession(payload.accessToken, payload.refreshToken)
                val profile = profileFromAuth(payload)
                repository.configureSession(profile)
                profile to repository.dashboard()
            } else {
                null to repository.dashboard()
            }
        }.onSuccess { (remoteProfile, data) ->
            val profile = remoteProfile ?: run {
                val profilePhone = AuthIdentity.displayPhone(identifier)
                val profileName = displayName?.trim().takeUnless { it.isNullOrEmpty() } ?: "王女士"
                val bucket = accountRole ?: UserRole.Parent
                UserProfile(
                    if (bucket == UserRole.Teacher) "teacher_li" else if (bucket == UserRole.Parent) "parent_wang" else "principal_zhou",
                    profileName, profilePhone, bucket, data.school.name,
                    // A Mock/offline login is a family-login fallback. Do not
                    // turn the existence of the teacher workbench into an
                    // account grant for every newly registered parent.
                    availableRoles = listOf(bucket),
                    authorizedClassIds = if (bucket == UserRole.Teacher) listOf("c31", "c32") else emptyList(),
                    capabilities = if (bucket == UserRole.Teacher) setOf("VIEW_CLASS_DASHBOARD", "MANAGE_CLASS_STUDENTS", "VIEW_TEST_TASKS", "UPDATE_TEST_STATUS", "REVIEW_RESULT", "REQUEST_RETEST", "UPLOAD_AFTER_SCHOOL_COURSE", "PUBLISH_CLASS_NOTICE") else emptySet()
                )
            }
            val bucket = profile.role
            val selected = data.students.firstOrNull { it.id == _state.value.local.selectedChildId && it.id in _state.value.local.boundChildIds }
            val local = _state.value.local.copy(
                sessionActive = true,
                sessionPhone = profile.phone,
                sessionRoleName = profile.role.name,
                accountBucketName = profile.role.name,
                parentAccountName = if (bucket == UserRole.Parent) profile.name else _state.value.local.parentAccountName,
                selectedChildId = selected?.id
            )
            featureStore.save(local)
            _state.value = AppUiState(profile, role = if (repository.supportsRemoteAcknowledgement) profile.role else accountRole, data = data, selectedChild = selected, local = local, repositoryAcknowledged = repository.supportsRemoteAcknowledgement)
            onSuccess()
        }.onFailure { handleDashboardFailure(it) }
    }

    /** Completes the one-time native callback from the server relay. */
    fun exchangeWechat(code: String, state: String, onSuccess: () -> Unit = {}) = viewModelScope.launch {
        if (_state.value.loading || code.isBlank() || state.isBlank()) return@launch
        _state.value = _state.value.copy(loading = true, error = null)
        runCatching {
            val payload = ApiClient.retrofit.create(AuthApi::class.java).exchangeWechat(WechatExchangeRequest(code, state)).data
                ?: error("微信登录响应为空")
            ApiClient.updateSession(payload.accessToken, payload.refreshToken)
            val profile = profileFromAuth(payload)
            repository.configureSession(profile)
            profile to repository.dashboard()
        }.onSuccess { (profile, data) ->
            val selected = data.students.firstOrNull { it.id == _state.value.local.selectedChildId && it.id in _state.value.local.boundChildIds }
            val local = _state.value.local.copy(sessionActive = true, sessionPhone = profile.phone, sessionRoleName = profile.role.name, accountBucketName = profile.role.name, parentAccountName = if (profile.role == UserRole.Parent) profile.name else _state.value.local.parentAccountName, selectedChildId = selected?.id)
            featureStore.save(local)
            _state.value = AppUiState(profile, role = profile.role, data = data, selectedChild = selected, local = local, repositoryAcknowledged = true)
            onSuccess()
        }.onFailure { handleDashboardFailure(it) }
        _state.value = _state.value.copy(loading = false)
    }
    fun register(name: String, phone: String, verificationCode: String, password: String, role: UserRole, onSuccess: () -> Unit = {}) = viewModelScope.launch {
        if (_state.value.loading) return@launch
        if (role != UserRole.Parent) {
            _state.value = _state.value.copy(error = "教师账号须由学校管理员开通后登录，不能自助注册。")
            return@launch
        }
        _state.value = _state.value.copy(loading = true, error = null)
        runCatching {
            if (repository.supportsRemoteAcknowledgement) {
                val payload = ApiClient.retrofit.create(AuthApi::class.java).register(RegisterRequest(name.trim(), phone, verificationCode, password, role.backendCode)).data
                    ?: error("注册响应为空")
                ApiClient.updateSession(payload.accessToken, payload.refreshToken)
                val profile = profileFromAuth(payload)
                repository.configureSession(profile)
                profile to repository.dashboard()
            } else {
                null to repository.dashboard()
            }
        }.onSuccess { (remoteProfile, data) ->
            val profile = remoteProfile ?: UserProfile(if (role == UserRole.Teacher) "teacher_li" else if (role == UserRole.Parent) "parent_wang" else "principal_zhou", name.trim(), phone, role, data.school.name, authorizedClassIds = if (role == UserRole.Teacher) listOf("c31", "c32") else emptyList(), capabilities = if (role == UserRole.Teacher) setOf("VIEW_CLASS_DASHBOARD", "MANAGE_CLASS_STUDENTS", "VIEW_TEST_TASKS", "UPDATE_TEST_STATUS", "REVIEW_RESULT", "REQUEST_RETEST", "UPLOAD_AFTER_SCHOOL_COURSE", "PUBLISH_CLASS_NOTICE") else emptySet())
            val selected = data.students.firstOrNull { it.id == _state.value.local.selectedChildId && it.id in _state.value.local.boundChildIds }
            val local = _state.value.local.copy(sessionActive = true, sessionPhone = profile.phone, sessionRoleName = profile.role.name, accountBucketName = profile.role.name, parentAccountName = if (profile.role == UserRole.Parent) profile.name else _state.value.local.parentAccountName, selectedChildId = selected?.id)
            featureStore.save(local)
            _state.value = AppUiState(profile, role = if (repository.supportsRemoteAcknowledgement) profile.role else role, data = data, selectedChild = selected, local = local, repositoryAcknowledged = repository.supportsRemoteAcknowledgement)
            onSuccess()
        }.onFailure { handleDashboardFailure(it) }
    }
    fun resetPassword(phone: String, verificationCode: String, password: String, onResult: (Boolean, String?) -> Unit) = viewModelScope.launch {
        if (!repository.supportsRemoteAcknowledgement) { onResult(true, null); return@launch }
        runCatching { ApiClient.retrofit.create(AuthApi::class.java).resetPassword(ResetPasswordRequest(phone, verificationCode, password)) }
            .onSuccess { onResult(true, null) }
            .onFailure { onResult(false, it.localizedMessage ?: "密码重置失败，请稍后重试") }
    }
    fun requestVerificationCode(account: String, purpose: String, onResult: (Boolean, String?) -> Unit) = viewModelScope.launch {
        if (account.filter(Char::isDigit).length != 11) { onResult(false, "请输入有效的 11 位手机号。"); return@launch }
        if (!repository.supportsRemoteAcknowledgement) { onResult(true, null); return@launch }
        runCatching { ApiClient.retrofit.create(AuthApi::class.java).sendVerificationCode(VerificationCodeRequest(account, purpose)) }
            .onSuccess { onResult(true, null) }
            .onFailure { onResult(false, it.localizedMessage ?: "验证码发送失败，请稍后重试") }
    }
    fun refreshDashboard(onSuccess: () -> Unit = {}) = viewModelScope.launch {
        // Do not turn an explicit refresh tap into a network request while the
        // device is offline. Cached/Mock data remains usable and the banner
        // explains why the refresh is deferred.
        if (_state.value.profile == null || _state.value.loading || _state.value.isOffline) return@launch
        _state.value = _state.value.copy(loading = true, error = null)
        runCatching { repository.dashboard() }.onSuccess { data ->
            val selected = _state.value.selectedChild?.id?.let { id -> data.students.firstOrNull { it.id == id && id in _state.value.local.boundChildIds } }
            _state.value = _state.value.copy(data = data, selectedChild = selected, loading = false, studentsLoadError = null)
            onSuccess()
        }.onFailure { handleDashboardFailure(it) }
    }
    /** Appends the next bounded remote student-directory page. */
    fun loadMoreStudents() = viewModelScope.launch {
        val current = _state.value.data ?: return@launch
        val total = current.studentTotal ?: return@launch
        val page = current.studentPage ?: return@launch
        val pageSize = current.studentPageSize ?: return@launch
        if (_state.value.studentsLoadingMore || _state.value.loading || _state.value.isOffline || total <= current.students.size) return@launch
        val nextPage = page + 1
        if ((nextPage - 1) * pageSize >= total) return@launch
        _state.value = _state.value.copy(studentsLoadingMore = true, studentsLoadError = null)
        try {
            val next = repository.dashboard(nextPage, pageSize)
            val existing = current.students.map { it.id }.toHashSet()
            val merged = current.students + next.students.filter { existing.add(it.id) }
            _state.value = _state.value.copy(data = next.copy(students = merged, studentTotal = next.studentTotal ?: total, studentPage = next.studentPage ?: nextPage, studentPageSize = next.studentPageSize ?: pageSize), studentsLoadingMore = false)
        } catch (error: Throwable) {
            if (error is ApiError.Unauthorized) handleDashboardFailure(error)
            else _state.value = _state.value.copy(studentsLoadingMore = false, studentsLoadError = error.localizedMessage ?: "学生名单加载失败，请重试")
        }
    }
    /**
     * A dashboard row only contains a student's latest summary.  Task detail
     * must load the selected task's rows, otherwise a student in two tasks can
     * be shown with the wrong status or optimistic-lock version.
     */
    fun loadTaskStudents(taskId: String) = viewModelScope.launch {
        if (taskId.isBlank() || !repository.supportsRemoteAcknowledgement || _state.value.isOffline) return@launch
        runCatching { repository.taskStudentRoster(taskId, page = 1, pageSize = 500, status = null, keyword = null) }.onSuccess { rows ->
            _state.value = _state.value.copy(taskRosterRecords = _state.value.taskRosterRecords + (taskId to rows))
            mutate { local ->
                val statuses = rows.associate { "${it.taskId}|${it.studentId}" to it.status }
                val versions = rows.associate { "${it.taskId}|${it.studentId}" to it.version }
                local.copy(
                    taskScopedStatuses = local.taskScopedStatuses + statuses,
                    taskScopedStatusVersions = local.taskScopedStatusVersions + versions
                )
            }
        }.onFailure { error ->
            if (error is ApiError.Unauthorized) handleDashboardFailure(error)
            else _state.value = _state.value.copy(error = error.localizedMessage ?: "任务学生状态加载失败，请重试")
        }
    }
    fun taskRosterStudents(taskId: String, fallbackTask: TestTask? = null): List<Student> {
        val current = _state.value
        val rows = current.taskRosterRecords[taskId].orEmpty()
        if (rows.isEmpty() && !repository.supportsRemoteAcknowledgement) {
            return fallbackTask?.scopedStudents(current.data?.students.orEmpty()).orEmpty()
        }
        return rows.map { row ->
            current.data?.students?.firstOrNull { it.id == row.studentId } ?: Student(
                id = row.studentId,
                name = row.studentName,
                grade = row.gradeName ?: fallbackTask?.gradeName.orEmpty(),
                className = row.className,
                region = current.data?.school?.region.orEmpty(),
                isPovertyArea = current.data?.school?.isPovertyArea ?: false,
                taskStatus = row.status,
                totalScore = null,
                gender = row.studentGender.orEmpty(),
                taskVersion = row.version,
                classId = row.classId
            )
        }
    }
    /**
     * A task can span an entire school, while a teacher claim normally covers
     * only a subset of its classes.  Keep this check close to every local
     * mutation as well as in the screen filter: hiding a row is not enough if
     * a stale deep link or a crafted UI event can still invoke the command.
     */
    private fun canManageTaskStudent(student: Student): Boolean {
        return _state.value.isTeacherAuthorizedFor(student)
    }
    fun submitTaskStatusBatch(taskId: String, studentIds: List<String>, status: TaskStatus, note: String? = null) = viewModelScope.launch {
        val ids = studentIds.distinct().filter { it.isNotBlank() }
        val commandKey = "task-batch:$taskId"
        if (taskId.isBlank() || ids.isEmpty() || _state.value.workflowStates[commandKey]?.isSubmitting == true) return@launch
        val roster = taskRosterStudents(taskId, _state.value.data?.tasks?.firstOrNull { it.id == taskId })
        val studentsById = (_state.value.data?.students.orEmpty() + roster).associateBy { it.id }
        if (ids.any { studentId -> studentsById[studentId]?.let { canManageTaskStudent(it) } != true }) {
            setWorkflow(commandKey, WorkflowCommandState(WorkflowCommandStatus.Failed, "只能更新已授权班级内的学生。"))
            return@launch
        }
        setWorkflow(commandKey, WorkflowCommandState(WorkflowCommandStatus.Submitting))
        val updates = ids.map { studentId ->
            com.xiangshang.youth.core.service.TaskStatusBatchItem(studentId, status, note, expectedVersion = _state.value.local.taskScopedStatusVersions["$taskId|$studentId"])
        }
        runCatching { repository.batchUpdateTaskStatus(taskId, updates) }
            .onSuccess { acknowledgement ->
                acknowledgement.items.orEmpty().forEach { row ->
                    mutate { local ->
                        val key = "$taskId|${row.studentId}"
                        local.copy(
                            taskScopedStatuses = local.taskScopedStatuses + (key to row.status),
                            taskScopedStatusVersions = local.taskScopedStatusVersions + (key to row.version),
                            taskScopedSyncStates = local.taskScopedSyncStates + (key to LocalSubmissionStatus.Submitted)
                        )
                    }
                }
                setWorkflow(commandKey, WorkflowCommandState(WorkflowCommandStatus.Succeeded, "已更新 ${acknowledgement.updated ?: acknowledgement.items.orEmpty().size} 名学生"))
            }
            .onFailure { setWorkflow(commandKey, WorkflowCommandState(WorkflowCommandStatus.Failed, it.localizedMessage ?: "批量更新失败，请重试")) }
    }
    fun loadTeacherOverview(classId: String, task: TestTask) = viewModelScope.launch {
        val profile = _state.value.profile ?: return@launch
        if (!repository.supportsRemoteAcknowledgement || profile.schoolId.isNullOrBlank()) return@launch
        val context = TeacherOverviewContext(profile.schoolId, classId, task.id, task.ruleVersion)
        _state.value = _state.value.copy(teacherOverview = null, teacherOverviewContext = context)
        runCatching { repository.teacherOverview(profile.schoolId, classId, task.id, task.ruleVersion) }
            .onSuccess { overview ->
                if (_state.value.teacherOverviewContext == context) {
                    _state.value = _state.value.copy(teacherOverview = overview)
                }
            }
            .onFailure {
                if (_state.value.teacherOverviewContext == context) {
                    _state.value = _state.value.copy(teacherOverview = null, error = it.localizedMessage ?: "班级统计加载失败，请重试")
                }
            }
    }
    /** A mobile role is usable only when it is present in the signed-in
     * account claims. `UserRole.mobileRoles` is a product capability list,
     * never a substitute for a teacher authorization grant. */
    fun canUseRole(role: UserRole): Boolean = _state.value.profile?.availableRoles?.contains(role) == true

    fun chooseRole(role: UserRole) {
        val visibleProfile = _state.value.profile
        if (!canUseRole(role)) return
        if (_state.value.role != role) _state.value = _state.value.copy(taskRosterRecords = emptyMap())
        // Preserve the family account name on the first upgrade from the
        // former session schema, before the active workbench overwrites it
        // with 李老师/周校长.
        val local = _state.value.local
            .let { current ->
                if (current.parentAccountName.isNullOrBlank() && visibleProfile?.role == UserRole.Parent) {
                    current.copy(parentAccountName = visibleProfile.name)
                } else current
            }
            .copy(sessionRoleName = role.name)
        featureStore.save(local)
        val parentName = local.parentAccountName ?: visibleProfile?.takeIf { it.role == UserRole.Parent }?.name ?: "家长"
        // Role switching must not overwrite a real account name with the seed
        // teacher/principal names. The Mock workbench has no separate teacher
        // account, so derive that display name from the managed class data; a
        // remote profile keeps the identity returned by the service.
        val roleName = if (repository.supportsRemoteAcknowledgement) {
            // The service owns the authenticated identity. A workbench switch
            // must never turn a real account into the bundled teacher_li demo.
            visibleProfile?.name ?: ""
        } else when (role) {
            UserRole.Parent -> parentName
            UserRole.Teacher -> if (visibleProfile?.role == UserRole.Teacher) {
                visibleProfile.name
            } else {
                _state.value.data?.classes?.firstOrNull()?.teacherName ?: visibleProfile?.name ?: "教师"
            }
            UserRole.Principal -> if (visibleProfile?.role == UserRole.Principal) visibleProfile.name else visibleProfile?.name ?: "校长"
        }
        val teacherMode = role == UserRole.Teacher
        val capabilities = if (teacherMode && !repository.supportsRemoteAcknowledgement && visibleProfile?.capabilities.isNullOrEmpty()) setOf("VIEW_CLASS_DASHBOARD", "MANAGE_CLASS_STUDENTS", "VIEW_TEST_TASKS", "UPDATE_TEST_STATUS", "REVIEW_RESULT", "REQUEST_RETEST", "UPLOAD_AFTER_SCHOOL_COURSE", "PUBLISH_CLASS_NOTICE") else visibleProfile?.capabilities.orEmpty()
        val classIds = if (teacherMode && !repository.supportsRemoteAcknowledgement && visibleProfile?.authorizedClassIds.isNullOrEmpty()) listOf("c31", "c32") else visibleProfile?.authorizedClassIds.orEmpty()
        _state.value = _state.value.copy(local = local, role = role, profile = visibleProfile?.copy(role = role, name = roleName, avatarInitials = roleName.take(1), authorizedClassIds = classIds, capabilities = capabilities))
    }
    fun clearRoleSelection() {
        val local = _state.value.local.copy(sessionRoleName = null)
        featureStore.save(local)
        _state.value = _state.value.copy(local = local, role = null, taskRosterRecords = emptyMap())
    }
    fun selectPrincipalTask(taskId: String) = mutate { it.copy(selectedPrincipalTaskId = taskId) }
    fun setTeacherSportsWorkbench(enabled: Boolean) = mutate { it.copy(teacherUsesSportsWorkbench = enabled) }
    fun recordHealthConsent(studentId: String, privacyVersion: String = "v1", cameraVersion: String = "v1", algorithmVersion: String = "posture-screening-v1") {
        val guardian = _state.value.profile ?: return
        val consent = com.xiangshang.youth.core.service.HealthConsentRecord(
            consentId = java.util.UUID.randomUUID().toString(), guardianUserId = guardian.id, childId = studentId,
            privacyPolicyVersion = privacyVersion, cameraConsentVersion = cameraVersion, algorithmNoticeVersion = algorithmVersion,
            agreedAt = BusinessClock.format("yyyy-MM-dd'T'HH:mm:ssXXX"), deviceInfo = "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}", dataRetentionNoticeAccepted = true
        )
        mutate { it.copy(healthConsents = it.healthConsents + (studentId to consent)) }
    }
    fun chooseChild(student: Student) {
        mutate { it.copy(selectedChildId = student.id) }
        _state.value = _state.value.copy(selectedChild = student)
        loadHealthCheckins(student.id)
        if (repository.supportsRemoteAcknowledgement) {
            loadFamilyHealthObservations(student.id)
            loadClassPosts()
            loadActivities()
        }
    }
    fun markMessageRead(messageId: String) {
        mutate { it.copy(readMessageIds = it.readMessageIds + messageId) }
        if (repository.supportsRemoteAcknowledgement) viewModelScope.launch {
            runCatching { repository.markMessageRead(messageId) }.onFailure { if (it is ApiError.Unauthorized) handleDashboardFailure(it) }
        }
    }
    fun markAllMessagesRead() = mutate { local ->
        local.copy(readMessageIds = local.readMessageIds + (_state.value.data?.messages?.map { it.id }.orEmpty()))
    }.also {
        if (repository.supportsRemoteAcknowledgement) _state.value.data?.messages.orEmpty().forEach { message -> viewModelScope.launch { runCatching { repository.markMessageRead(message.id) }.onFailure { if (it is ApiError.Unauthorized) handleDashboardFailure(it) } } }
    }
    fun bindChild(name: String, code: String): Boolean {
        if (repository.supportsRemoteAcknowledgement) {
            if (name.isBlank() || code.isBlank()) return false
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + ("child-binding" to WorkflowCommandState(WorkflowCommandStatus.Submitting)))
            viewModelScope.launch {
                runCatching { repository.bindChild(name.trim(), code.trim().uppercase()) }.onSuccess { binding ->
                    mutate { it.copy(boundChildIds = it.boundChildIds + binding.student.id, selectedChildId = it.selectedChildId ?: binding.student.id) }
                    _state.value = _state.value.copy(selectedChild = _state.value.selectedChild ?: binding.student, workflowStates = _state.value.workflowStates + ("child-binding" to WorkflowCommandState(WorkflowCommandStatus.Succeeded, "孩子已绑定")))
                    refreshDashboard()
                }.onFailure { error ->
                    _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + ("child-binding" to WorkflowCommandState(WorkflowCommandStatus.Failed, error.localizedMessage ?: "绑定失败")))
                    if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                }
            }
            // The request is asynchronous.  The screen observes the workflow
            // state and must not close the binding dialog until this coroutine
            // reports Succeeded.
            return false
        }
        val child = ChildBindingValidator.findMatch(_state.value.data?.students.orEmpty(), name, code) ?: return false
        mutate { it.copy(boundChildIds = it.boundChildIds + child.id) }
        if (_state.value.selectedChild == null) chooseChild(child)
        return true
    }
    fun logout() {
        sessionGeneration += 1
        sessionRestoreJob?.cancel()
        sessionRestoreJob = null
        ApiClient.clearToken()
        featureStore.clear()
        _state.value = AppUiState()
    }

    /**
     * Instrumentation-only identity fixture.  Public registration deliberately
     * never creates a teacher account; UI tests that cover the teacher
     * workbench must therefore use an explicit school-provisioned identity
     * with the same scoped claims a server session would provide.
     */
    fun startSchoolProvisionedTeacherFixtureForUiTest() {
        if (!BuildConfig.DEBUG) return
        viewModelScope.launch {
            val data = repository.dashboard()
            val profile = UserProfile(
                id = "teacher_ui_fixture",
                name = "学校授权教师",
                phone = "13800000001",
                role = UserRole.Teacher,
                schoolName = data.school.name,
                roleCode = "teacher",
                schoolId = data.school.id,
                availableRoles = listOf(UserRole.Teacher),
                authorizedClassIds = listOf("c31", "c32"),
                capabilities = setOf(
                    "VIEW_CLASS_DASHBOARD", "MANAGE_CLASS_STUDENTS", "VIEW_TEST_TASKS",
                    "UPDATE_TEST_STATUS", "REVIEW_RESULT", "REQUEST_RETEST",
                    "UPLOAD_AFTER_SCHOOL_COURSE", "PUBLISH_CLASS_NOTICE"
                )
            )
            repository.configureSession(profile)
            val local = _state.value.local.copy(
                sessionActive = true,
                sessionPhone = profile.phone,
                sessionRoleName = UserRole.Teacher.name,
                accountBucketName = UserRole.Teacher.name
            )
            featureStore.save(local)
            _state.value = AppUiState(
                profile = profile,
                role = UserRole.Teacher,
                data = data,
                local = local,
                repositoryAcknowledged = false,
                uiTestSchoolProvisionedTeacher = true
            )
        }
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
                    repository.grantHealthConsent(consent)
                    val canonicalReport = repository.submitBodyAssessment(studentId, record, "v1")
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

    fun completeAssessment(category: String, entries: Map<String, String> = emptyMap(), structuredAnswers: List<com.xiangshang.youth.core.service.HealthObservationAnswer>? = null) = mutate { local ->
        val childId = _state.value.selectedChild?.id ?: "anonymous"
        val completed = local.completedAssessments + "$childId-$category"
        if (category == "fitness") local.copy(completedAssessments = completed)
        else {
            val previous = local.familyHealthRecords["$childId-$category"]
            val answers = structuredAnswers ?: makeStructuredObservationAnswers(category, entries)
            val record = com.xiangshang.youth.core.service.FamilyHealthRecord(childId, category, BusinessClock.format("yyyy-MM-dd HH:mm"), entries, formVersion = "family-observation-v2", submittedAt = BusinessClock.format("yyyy-MM-dd HH:mm"), version = (previous?.version ?: 0) + 1, frequency = entries["频率"], severity = entries["严重程度"], structuredAnswers = answers)
            local.copy(completedAssessments = completed, familyHealthRecords = local.familyHealthRecords + ("$childId-$category" to record), healthObservationSyncStates = local.healthObservationSyncStates + ("$childId|$category" to if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Submitted))
        }
    }.also {
        if (repository.supportsRemoteAcknowledgement && category != "fitness") {
            val childId = _state.value.selectedChild?.id ?: return@also
            val record = _state.value.local.familyHealthRecords["$childId-$category"] ?: return@also
            executeWorkflow("health-observation:$childId:$category", operation = {
                val canonical = repository.submitHealthObservation(childId, category, record)
                if (_state.value.selectedChild?.id == childId) {
                    mutate { local -> local.copy(completedAssessments = local.completedAssessments + "$childId-$category", familyHealthRecords = local.familyHealthRecords + ("$childId-$category" to canonical), healthObservationSyncStates = local.healthObservationSyncStates + ("$childId|$category" to LocalSubmissionStatus.Submitted)) }
                }
            }, onFailure = { mutate { local -> local.copy(healthObservationSyncStates = local.healthObservationSyncStates + ("$childId|$category" to LocalSubmissionStatus.Failed)) } })
        }
    }

    private fun makeStructuredObservationAnswers(category: String, entries: Map<String, String>): List<com.xiangshang.youth.core.service.HealthObservationAnswer> {
        val questionIds = mapOf(
            "基础信息" to "profile-confirmed",
            "用眼习惯" to "vision-screen-time",
            "视力筛查" to "vision-screening",
            "口腔习惯" to "oral-hygiene",
            "口腔筛查" to "oral-screening",
            "开始说明" to "mental-consent",
            "家庭感受记录" to "mental-observations",
            "家庭观察结果" to "mental-follow-up",
            "频率" to "observation-frequency",
            "严重程度" to "observation-severity",
            "补充说明" to "observation-note"
        )
        return entries.keys.sortedBy { questionIds[it] ?: it }.mapNotNull { key ->
            val raw = entries[key]?.trim().orEmpty()
            if (raw.isBlank()) return@mapNotNull null
            val parts = raw.split("｜", limit = 2)
            val selection = parts.firstOrNull()?.trim().orEmpty()
            val note = parts.getOrNull(1)?.trim()?.takeIf { it.isNotBlank() }
            val type = when (key) {
                "频率" -> "frequency"
                "严重程度" -> "severity"
                "补充说明" -> "text"
                "家庭感受记录" -> "multiple"
                else -> "single"
            }
            val required = type !in setOf("frequency", "severity", "text")
            val selected = if (type == "text") emptyList() else selection.split('、', ',', '，').map { it.trim() }.filter { it.isNotBlank() }
            com.xiangshang.youth.core.service.HealthObservationAnswer(
                questionId = questionIds[key] ?: "$category-$key",
                questionType = type,
                selectedOptionIds = selected,
                note = if (type == "text") selection.ifBlank { note } else note,
                required = required
            )
        }
    }

    fun loadFamilyHealthObservations(studentId: String) = viewModelScope.launch {
        if (!repository.supportsRemoteAcknowledgement) return@launch
        runCatching { repository.loadHealthObservations(studentId) }
            .onSuccess { records ->
                if (_state.value.selectedChild?.id != studentId) return@onSuccess
                mutate { local ->
                    val updatedRecords = local.familyHealthRecords.toMutableMap()
                    val completed = local.completedAssessments.toMutableSet()
                    records.forEach { record ->
                        updatedRecords["$studentId-${record.category}"] = record
                        completed += "$studentId-${record.category}"
                    }
                    local.copy(familyHealthRecords = updatedRecords, completedAssessments = completed)
                }
            }
            .onFailure { error ->
                _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + ("health-observation-load:$studentId" to WorkflowCommandState(WorkflowCommandStatus.Failed, error.localizedMessage ?: "健康记录加载失败")))
            }
    }
    fun loadHealthCheckins(studentId: String) = viewModelScope.launch {
        if (!repository.supportsRemoteAcknowledgement) return@launch
        runCatching { repository.loadHealthCheckins(studentId) }
            .onSuccess { records ->
                if (_state.value.selectedChild?.id != studentId) return@onSuccess
                mutate { local ->
                    val merged = records + local.healthCheckins.filterNot { localRecord -> records.any { it.id == localRecord.id || (it.childId == studentId && it.checkInDate == localRecord.checkInDate) } }
                    local.copy(healthCheckins = merged, checkedInDates = local.checkedInDates + records.map { it.checkInDate }, checkedInToday = records.any { it.checkInDate == BusinessClock.day() })
                }
            }
            .onFailure { error -> if (error is ApiError.Unauthorized) handleDashboardFailure(error) }
    }

    fun publishPost(author: String, content: String, attachments: List<com.xiangshang.youth.core.service.ClassPostAttachment> = emptyList()): String? {
        if (content.isBlank()) return null
        val id = java.util.UUID.randomUUID().toString()
        val classId = _state.value.profile?.authorizedClassIds?.firstOrNull() ?: _state.value.selectedChild?.classId
        mutate { it.copy(classPosts = listOf(ClassPost(id = id, author = author, content = content, status = LocalSubmissionStatus.PendingSync, classId = classId, displayName = privacyDisplayName(author), visibilityScope = "class", moderationStatus = "pending_review", pinned = false, attachments = attachments, authorRole = if (_state.value.role == UserRole.Teacher) "teacher" else "parent")) + it.classPosts) }
        return id
    }
    fun updatePost(id: String, content: String) { if (content.isBlank()) return; mutate { local -> local.copy(classPosts = local.classPosts.map { if (it.id == id) it.copy(content = content, status = LocalSubmissionStatus.PendingSync) else it }) } }
    internal fun updatePostSyncStatus(id: String, status: LocalSubmissionStatus, serverPostId: String? = null) = mutate { local ->
        local.copy(classPosts = local.classPosts.map { post ->
            if (post.id == id) post.copy(status = status, postId = serverPostId ?: post.postId, ownedByCurrentUser = post.ownedByCurrentUser || !serverPostId.isNullOrBlank()) else post
        })
    }
    fun togglePostLike(postId: String) = mutate { local -> local.copy(likedPostIds = if (postId in local.likedPostIds) local.likedPostIds - postId else local.likedPostIds + postId) }
    fun addPostComment(postId: String, content: String) {
        val trimmed = content.trim()
        if (trimmed.isBlank()) return
        val post = _state.value.local.classPosts.firstOrNull { it.id == postId || it.postId == postId }
        val serverPostId = post?.postId
        mutate { local -> local.copy(postComments = local.postComments + (postId to (local.postComments[postId].orEmpty() + trimmed))) }
        if (!repository.supportsRemoteAcknowledgement || serverPostId.isNullOrBlank()) return
        executeWorkflow("class-post:comment:$serverPostId", operation = {
            repository.addClassPostComment(serverPostId, trimmed)
        }, onFailure = {
            mutate { local ->
                val updated = local.postComments[postId].orEmpty().dropLast(1) + "$trimmed（同步失败）"
                local.copy(postComments = local.postComments + (postId to updated))
            }
        })
    }
    fun saveDraft(key: String, content: String) = mutate { it.copy(drafts = it.drafts + (key to content)) }
    fun clearDraft(key: String) = mutate { it.copy(drafts = it.drafts - key) }
    private fun privacyDisplayName(value: String): String {
        val first = value.trim().firstOrNull() ?: return "本班家长"
        return "${first}同学家长"
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
    fun updateSettings(notificationsEnabled: Boolean? = null, reduceMotion: Boolean? = null, voiceGuidanceEnabled: Boolean? = null) = mutate { local -> local.copy(settings = local.settings.copy(notificationsEnabled = notificationsEnabled ?: local.settings.notificationsEnabled, reduceMotion = reduceMotion ?: local.settings.reduceMotion, voiceGuidanceEnabled = voiceGuidanceEnabled ?: local.settings.voiceGuidanceEnabled)) }
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
    override fun onCleared() {
        runCatching { connectivityManager.unregisterNetworkCallback(networkCallback) }
        super.onCleared()
    }
    private fun hasValidatedNetwork(): Boolean = connectivityManager.activeNetwork?.let { network ->
        connectivityManager.getNetworkCapabilities(network)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
    } ?: false
    /** Builds a mobile profile from server-owned claims, never from local demo defaults. */
    private fun profileFromAuth(payload: com.xiangshang.youth.core.service.AuthResponse): UserProfile = profileFromClaims(
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
        if (!value && _state.value.profile != null && _state.value.pendingSyncCount > 0 && !workflowState("sync-pending").isSubmitting) syncPendingRecords()
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
                val selected = data.students.firstOrNull { it.id == local.selectedChildId && it.id in local.boundChildIds }
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
                _state.value = _state.value.copy(profile = visibleProfile, role = null, data = data, selectedChild = selected, loading = false, restoringSession = false)
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
                    // A persisted session whose dashboard cannot be refreshed is not
                    // a usable authenticated state. Clear it before returning to the
                    // login screen so the next launch cannot loop through RoleSelect
                    // with a nil dashboard or keep retrying stale credentials.
                    featureStore.clear()
                    _state.value = AppUiState(error = error.message, restoringSession = false)
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
    internal fun mutate(transform: (LocalFeatureState) -> LocalFeatureState) { val local = transform(_state.value.local); featureStore.save(local); _state.value = _state.value.copy(local = local) }
    /** Narrow state seam for the remote-content domain extensions. */
    internal fun updateRemoteTargetState(transform: (AppUiState) -> AppUiState) {
        _state.value = transform(_state.value)
    }
}
