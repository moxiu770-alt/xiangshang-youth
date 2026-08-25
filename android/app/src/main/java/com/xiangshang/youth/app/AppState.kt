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
import com.xiangshang.youth.core.service.SupportMessage
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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

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
    /** A logout may happen while a cold-start restore is awaiting the
     * dashboard.  Keep a cancellable handle and a generation token so the
     * old account can never repopulate state after the user chose to exit. */
    private var sessionRestoreJob: Job? = null
    private var sessionGeneration = 0L
    private val _state = MutableStateFlow(AppUiState(local = initialLocal, restoringSession = initialLocal.sessionActive, repositoryAcknowledged = repository.supportsRemoteAcknowledgement))
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
        return current.taskRosterRecords[taskId].orEmpty().map { row ->
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
    fun submitTaskStatusBatch(taskId: String, studentIds: List<String>, status: TaskStatus, note: String? = null) = viewModelScope.launch {
        val ids = studentIds.distinct().filter { it.isNotBlank() }
        val commandKey = "task-batch:$taskId"
        if (taskId.isBlank() || ids.isEmpty() || _state.value.workflowStates[commandKey]?.isSubmitting == true) return@launch
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
        runCatching { repository.teacherOverview(profile.schoolId, classId, task.id, task.ruleVersion) }
            .onSuccess { overview -> _state.value = _state.value.copy(teacherOverview = overview) }
            .onFailure { _state.value = _state.value.copy(teacherOverview = null, error = it.localizedMessage ?: "班级统计加载失败，请重试") }
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
    private fun setWorkflow(key: String, value: WorkflowCommandState) { _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to value)) }
    private fun childWorkflowKey(prefix: String, childId: String? = _state.value.selectedChild?.id): String =
        childId?.takeIf { it.isNotBlank() }?.let { "$prefix:$it" } ?: prefix
    fun clearWorkflowState(key: String) { _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState())) }

    private fun executeWorkflow(key: String, operation: suspend () -> Unit, onSuccess: (() -> Unit)? = null, onFailure: (() -> Unit)? = null, successMessage: (() -> String)? = null, onError: ((Throwable) -> Unit)? = null) = viewModelScope.launch {
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

    fun submitActivityCommand(contactName: String, phone: String, activityId: String = "health-growth-season-2026") = executeWorkflow(childWorkflowKey("activity:$activityId"), {
        if (contactName.isBlank() || phone.filter(Char::isDigit).length != 11) throw IllegalArgumentException("请填写有效的联系人和手机号。")
        registerActivity(contactName.trim(), phone.trim(), activityId)
        val childId = _state.value.selectedChild?.id
        val record = _state.value.local.activityRegistrations.firstOrNull { it.activityId == activityId && (it.childId == childId || it.childId == null) } ?: throw IllegalArgumentException("报名信息不完整。")
        val ack = if (record.registrationId == null) repository.submitActivity(record) else repository.updateActivityRegistration(record)
        applyActivityAck(activityId, ack, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync)
    }, onSuccess = { if (repository.supportsRemoteAcknowledgement) loadActivities() }, onFailure = { markActivitySyncFailed(activityId) })

    fun submitExpertCommand(name: String, date: String, note: String, expertId: String? = null, serviceId: String? = null, slotId: String? = null, scheduledStartAt: String? = null, scheduledEndAt: String? = null) = executeWorkflow(childWorkflowKey("expert:${expertId?.takeIf { it.isNotBlank() } ?: "unresolved"}"), {
        val stableId = expertId?.takeIf { it.isNotBlank() } ?: throw IllegalArgumentException("专家信息缺少编号，请刷新专家列表后重试。")
        if (date.isBlank() || note.trim().isBlank()) throw IllegalArgumentException("请填写咨询时间和说明。")
        bookExpert(name, date.trim(), note.trim(), stableId, serviceId, slotId, scheduledStartAt, scheduledEndAt)
        val childId = _state.value.selectedChild?.id
        val record = _state.value.local.expertAppointments.firstOrNull { it.expertId == stableId && (it.childId == childId || it.childId == null) } ?: throw IllegalArgumentException("预约信息不完整。")
        val ack = repository.bookExpert(record)
        applyExpertAck(stableId, ack, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync)
    }, onSuccess = { if (repository.supportsRemoteAcknowledgement) loadExperts() }, onFailure = {
        expertId?.takeIf { it.isNotBlank() }?.let { stableId ->
            _state.value.local.expertAppointments.firstOrNull { it.expertId == stableId }?.let(::markExpertSyncFailed)
        }
    })

    fun submitCourseUploadCommand(taskId: String, attendance: Int, notes: String, attachment: String, attachmentReference: String?) = executeWorkflow("course:$taskId", {
        if (attendance <= 0 || notes.trim().isBlank() || attachment.trim().isBlank() || attachmentReference.isNullOrBlank()) throw IllegalArgumentException("提交前请补齐出勤人数、课堂记录和可上传的照片附件。")
        saveCourseUpload(taskId, attendance, notes, attachment, attachmentReference, true)
        val record = _state.value.local.courseUploads.firstOrNull { it.taskId == taskId } ?: throw IllegalArgumentException("课程记录不完整。")
        repository.uploadCourse(record)
    }, onSuccess = { updateCourseSyncStatus(taskId, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync) }, onFailure = { markCourseSyncFailed(taskId) })

    fun submitPrivacyRequest(studentId: String, requestType: String) {
        val key = "privacy:$studentId:$requestType"
        if (_state.value.data?.students?.none { it.id == studentId } != false) {
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState(WorkflowCommandStatus.Failed, "未找到孩子信息，请重新选择后再试。")))
            return
        }
        executeWorkflow(key, { repository.submitPrivacyRequest(studentId, requestType) }, successMessage = {
            if (repository.supportsRemoteAcknowledgement) {
                if (requestType == "export") "导出申请已提交，文件生成后会在消息中心通知。" else "删除申请已提交，需经学校/平台审核；审核前不会删除任何记录。"
            } else "申请已保存到本机记录。接入学校服务后可提交审核。"
        })
    }

    fun revokeHealthConsent(studentId: String, version: String = "v1") {
        val key = "privacy:$studentId:consent-revoke"
        if (_state.value.data?.students?.none { it.id == studentId } != false) {
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState(WorkflowCommandStatus.Failed, "未找到孩子信息，请重新选择后再试。")))
            return
        }
        executeWorkflow(key, { repository.revokeHealthConsent(studentId, version) }, onSuccess = {
            val existing = _state.value.local.healthConsents[studentId] ?: return@executeWorkflow
            mutate { it.copy(healthConsents = it.healthConsents + (studentId to existing.copy(revokedAt = BusinessClock.format("yyyy-MM-dd'T'HH:mm:ssXXX")))) }
        }, successMessage = {
            if (repository.supportsRemoteAcknowledgement) "已撤回身体测评数据使用同意；新的身体测评需重新授权。" else "撤回记录已保存在本机，接入学校服务后提交。"
        })
    }

    fun submitAccountDeletionRequest() {
        executeWorkflow("privacy:account-deletion", { repository.submitAccountDeletionRequest() }, successMessage = {
            if (repository.supportsRemoteAcknowledgement) "注销申请已提交，平台审核通过后会撤销会话并匿名化账户。" else "注销申请已保存到本机记录，接入学校服务后提交审核。"
        })
    }

    fun syncPendingRecords() = executeWorkflow("sync-pending", {
        if (_state.value.profile == null) throw IllegalStateException("请登录后再同步本机记录。")
        if (_state.value.isOffline) throw IllegalStateException("当前网络不可用，记录会继续保存在本机。")
        if (!repository.supportsRemoteAcknowledgement) return@executeWorkflow
        var failed = 0
        _state.value.local.activityRegistrations.filter { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed }.forEach { record ->
            markActivitySyncSubmitting(record.activityId)
            try {
                val ack = if (record.registrationId == null) repository.submitActivity(record) else repository.updateActivityRegistration(record)
                applyActivityAck(record.activityId, ack, LocalSubmissionStatus.Submitted)
            } catch (error: Throwable) {
                if (error is ApiError.Unauthorized) throw error
                markActivitySyncFailed(record.activityId); failed += 1
            }
        }
        _state.value.local.expertAppointments.filter { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed }.forEach { record ->
            markExpertSyncSubmitting(record)
            try {
                val ack = repository.bookExpert(record)
                val expertId = record.expertId ?: throw IllegalStateException("本地预约缺少专家编号，请刷新专家列表后重新预约。")
                applyExpertAck(expertId, ack, LocalSubmissionStatus.Submitted)
            } catch (error: Throwable) {
                if (error is ApiError.Unauthorized) throw error
                markExpertSyncFailed(record); failed += 1
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
            if (status == null) {
                markTaskStatusSyncFailed(studentId, taskId)
                failed += 1
            } else {
                markTaskStatusSyncSubmitting(studentId, taskId)
                val expectedVersion = _state.value.local.taskScopedStatusVersions[key]
                    ?: if (_state.value.repositoryAcknowledged) _state.value.data?.students?.firstOrNull { it.id == studentId }?.taskVersion
                    else _state.value.local.taskStatusVersions[studentId] ?: _state.value.data?.students?.firstOrNull { it.id == studentId }?.taskVersion
                try {
                    val acknowledgedVersion = repository.updateTaskStatus(taskId, studentId, status, _state.value.local.taskScopedReviewNotes[key] ?: _state.value.local.reviewNotes[studentId], expectedVersion)
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
        var acknowledgedVersion: Int? = null
        val key = _state.value.taskKey(taskId, studentId)
        executeWorkflow("task-status:$key", operation = {
        if (studentId.isBlank()) throw IllegalArgumentException("学生信息缺失。")
        val student = _state.value.data?.students?.firstOrNull { it.id == studentId }
            ?: throw IllegalArgumentException("未找到学生档案，请刷新名单后重试。")
        val current = _state.value.taskStatus(student, taskId)
        if (!current.allowsTransitionTo(status)) throw IllegalArgumentException("当前为${current.label}，不能直接变更为${status.label}。请按现场队列流程操作。")
        val expectedVersion = _state.value.local.taskScopedStatusVersions[key]
            ?: if (_state.value.repositoryAcknowledged) student.taskVersion else _state.value.local.taskStatusVersions[studentId] ?: student.taskVersion
        submitReviewDecision(studentId, status, note.orEmpty().ifBlank { "已完成状态处理" }, taskId)
        markTaskStatusSyncPending(studentId, taskId)
        acknowledgedVersion = repository.updateTaskStatus(taskId ?: "unscoped", studentId, status, note, expectedVersion)
        }, onSuccess = {
            acknowledgeTaskStatusVersion(studentId, taskId, acknowledgedVersion)
            updateTaskStatusSyncStatus(studentId, taskId, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync)
        }, onFailure = { markTaskStatusSyncFailed(studentId, taskId) }, onError = { error -> if (error is ApiError.Conflict) resetTaskStatusProjectionAfterConflict(studentId, taskId) })
    }

    fun submitClassPostCommand(author: String, content: String, attachments: List<com.xiangshang.youth.core.service.ClassPostAttachment> = emptyList()): Job {
        var postIdForCommand: String? = null
        var serverPostId: String? = null
        val workflowKey = "post:${_state.value.profile?.id ?: "session"}"
        return executeWorkflow(workflowKey, operation = {
        if (content.trim().isBlank()) throw IllegalArgumentException("动态内容不能为空。")
        postIdForCommand = publishPost(author, content.trim(), attachments)
        val post = postIdForCommand?.let { id -> _state.value.local.classPosts.firstOrNull { it.id == id } }
            ?: throw IllegalStateException("动态草稿保存失败，请重试。")
        serverPostId = repository.publishClassPost(author, content.trim(), _state.value.profile?.schoolId, post.classId, attachments)
        }, onSuccess = { postIdForCommand?.let { updatePostSyncStatus(it, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync, serverPostId) } }, onFailure = { postIdForCommand?.let { updatePostSyncStatus(it, LocalSubmissionStatus.Failed) } })
    }

    fun deleteClassPostCommand(post: ClassPost) {
        val serverPostId = post.postId
        if (serverPostId.isNullOrBlank()) {
            mutate { local -> local.copy(classPosts = local.classPosts.filterNot { it.id == post.id }) }
            return
        }
        executeWorkflow("class-post:delete:$serverPostId", operation = {
            repository.deleteClassPost(serverPostId)
        }, onSuccess = {
            mutate { local -> local.copy(classPosts = local.classPosts.filterNot { it.id == post.id || it.postId == serverPostId }) }
        })
    }

    fun reportClassPostCommand(post: ClassPost, reason: String = "不适合班级圈展示") {
        val serverPostId = post.postId ?: return
        val cleanReason = reason.trim()
        if (cleanReason.isBlank()) return
        executeWorkflow("class-post:report:$serverPostId", operation = {
            repository.reportClassPost(serverPostId, cleanReason)
        }, onSuccess = {
            mutate { local -> local.copy(classPosts = local.classPosts.map { if (it.id == post.id || it.postId == serverPostId) it.copy(reportStatus = "reported") else it }) }
        })
    }

    fun setClassPostPinnedCommand(post: ClassPost, pinned: Boolean) {
        val serverPostId = post.postId ?: return
        executeWorkflow("class-post:pin:$serverPostId", operation = {
            repository.setClassPostPinned(serverPostId, pinned)
        }, onSuccess = {
            mutate { local -> local.copy(classPosts = local.classPosts.map { if (it.id == post.id || it.postId == serverPostId) it.copy(pinned = pinned) else it }) }
        })
    }

    /** Sends a school notification through the dedicated notification contract.
     * It deliberately does not reuse the class-circle post workflow: a notice
     * has a target class, an auditable sender and a delivery acknowledgement. */
    fun submitClassNoticeCommand(classId: String, title: String, content: String) = executeWorkflow("notice:$classId", operation = {
        val profile = _state.value.profile ?: throw ApiError.Unauthorized
        if (_state.value.role != UserRole.Teacher || !_state.value.teacherHasCapability("PUBLISH_CLASS_NOTICE")) {
            throw ApiError.Forbidden
        }
        if (classId.isBlank() || classId !in _state.value.managedTeacherClasses.map { it.id }) {
            throw ApiError.Forbidden
        }
        val cleanTitle = title.trim()
        val cleanContent = content.trim()
        if (cleanTitle.length < 2) throw IllegalArgumentException("请填写通知标题。")
        if (cleanContent.length < 4) throw IllegalArgumentException("请填写通知内容。")
        repository.sendClassNotice(profile.schoolId.orEmpty(), classId, cleanTitle, cleanContent)
    })

    fun loadNotificationDrafts() = viewModelScope.launch {
        val schoolId = _state.value.profile?.schoolId.orEmpty()
        if (schoolId.isBlank()) return@launch
        _state.value = _state.value.copy(notificationDraftsLoading = true, notificationDraftsError = null)
        runCatching { repository.listNotificationDrafts(schoolId) }
            .onSuccess { drafts -> _state.value = _state.value.copy(notificationDrafts = drafts, notificationDraftsLoading = false, notificationDraftsError = null) }
            .onFailure { error -> _state.value = _state.value.copy(notificationDraftsLoading = false, notificationDraftsError = error.localizedMessage ?: "通知草稿加载失败") }
    }

    fun saveNotificationDraft(notificationId: String?, classIds: List<String>, title: String, content: String, draftVersion: Int?, parentReceiptEnabled: Boolean, scheduledAt: String? = null, onSaved: (com.xiangshang.youth.core.service.NotificationCampaign?) -> Unit = {}) = viewModelScope.launch {
        val profile = _state.value.profile ?: run { onSaved(null); return@launch }
        val targets = classIds.distinct().filter { it.isNotBlank() }
        val cleanTitle = title.trim()
        val cleanContent = content.trim()
        val key = "notice:draft"
        if (targets.isEmpty() || cleanTitle.length < 2 || cleanContent.length < 4) {
            setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Failed, "请填写标题、正文并选择授权班级。"))
            onSaved(null)
            return@launch
        }
        setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Submitting))
        runCatching {
            if (notificationId != null && draftVersion != null) repository.updateNotificationDraft(notificationId, profile.schoolId.orEmpty(), targets, cleanTitle, cleanContent, draftVersion, parentReceiptEnabled = parentReceiptEnabled, scheduledAt = scheduledAt)
            else repository.createNotificationDraft(profile.schoolId.orEmpty(), targets, cleanTitle, cleanContent, parentReceiptEnabled = parentReceiptEnabled, scheduledAt = scheduledAt)
        }.onSuccess { draft ->
            _state.value = _state.value.copy(
                notificationDrafts = listOf(draft) + _state.value.notificationDrafts.filterNot { it.notificationId == draft.notificationId },
                workflowStates = _state.value.workflowStates + (key to WorkflowCommandState(WorkflowCommandStatus.Succeeded, "通知草稿已保存。"))
            )
            onSaved(draft)
        }.onFailure { error ->
            setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Failed, error.localizedMessage ?: "通知草稿保存失败"))
            onSaved(null)
        }
    }

    fun sendNotificationDraft(notificationId: String) = executeWorkflow("notice:send:$notificationId", operation = {
        repository.sendNotification(notificationId)
    }, onSuccess = {
        _state.value = _state.value.copy(notificationDrafts = _state.value.notificationDrafts.filterNot { it.notificationId == notificationId })
    })

    fun discardNotificationDraft(notificationId: String) = executeWorkflow("notice:discard:$notificationId", operation = {
        repository.discardNotificationDraft(notificationId)
    }, onSuccess = {
        _state.value = _state.value.copy(notificationDrafts = _state.value.notificationDrafts.filterNot { it.notificationId == notificationId })
    })

    fun loadClassNoticeDetail(notificationId: String, onLoaded: (com.xiangshang.youth.core.service.NotificationCampaignDetail?) -> Unit = {}) = viewModelScope.launch {
        val key = "notice:detail:$notificationId"
        setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Submitting))
        runCatching { repository.loadClassNotice(notificationId) }
            .onSuccess { detail ->
                setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Succeeded, "通知详情已加载。"))
                onLoaded(detail)
            }
            .onFailure { error ->
                setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Failed, error.localizedMessage ?: "通知详情加载失败"))
                onLoaded(null)
            }
    }

    fun acknowledgeClassNotice(notificationId: String, onDone: (Boolean) -> Unit = {}) = executeWorkflow("notice:receipt:$notificationId", operation = {
        repository.acknowledgeClassNotice(notificationId)
    }, onSuccess = { onDone(true) }, onFailure = { onDone(false) }, successMessage = { "已确认收到，学校会看到回执。" })

    fun submitSupportCommand(content: String) {
        val normalized = content.trim()
        val key = "support"
        if (normalized.isBlank()) {
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + (key to WorkflowCommandState(WorkflowCommandStatus.Failed, "请输入咨询内容。")))
            return
        }
        val message = createSupportMessage(normalized)
        executeWorkflow(key, operation = { repository.sendSupportMessage(normalized) }, onSuccess = {
            updateSupportSyncStatus(message.id, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync)
        }, onFailure = { updateSupportSyncStatus(message.id, LocalSubmissionStatus.Failed) })
    }
    fun registerActivity(contactName: String, phone: String, activityId: String = "health-growth-season-2026") {
        if (contactName.isBlank() || phone.filter(Char::isDigit).length != 11) return
        val childId = _state.value.selectedChild?.id
        mutate { local ->
            val previous = local.activityRegistrations.firstOrNull { it.activityId == activityId && it.childId == childId }
            val record = com.xiangshang.youth.core.service.ActivityRegistration(
                id = previous?.id ?: java.util.UUID.randomUUID().toString(),
                activityId = activityId,
                contactName = contactName.trim(),
                phone = phone,
                status = LocalSubmissionStatus.PendingSync,
                registrationId = previous?.registrationId,
                childId = childId,
                contactUserId = previous?.contactUserId,
                capacity = previous?.capacity,
                remainingCapacity = previous?.remainingCapacity,
                registrationStartAt = previous?.registrationStartAt,
                registrationEndAt = previous?.registrationEndAt,
                registrationStatus = previous?.registrationStatus ?: "pending",
                version = previous?.version
            )
            local.copy(activityRegistered = true, activityRegistrations = listOf(record) + local.activityRegistrations.filterNot { it.activityId == record.activityId && it.childId == childId })
        }
    }
    fun cancelActivityRegistration(activityId: String = "health-growth-season-2026") {
        val childId = _state.value.selectedChild?.id
        mutate { local ->
            val remaining = local.activityRegistrations.filterNot { it.activityId == activityId && (it.childId == childId || it.childId == null) }
            local.copy(
                activityRegistered = remaining.any { it.registrationStatus != "cancelled" },
                activityRegistrations = remaining
            )
        }
        clearDraft("activity-registration-$activityId")
        clearWorkflowState("activity:$activityId")
    }

    /**
     * [registrationKey] is the server registration id in remote mode, or the
     * locally generated draft id while offline. Activity id remains only a
     * legacy Mock fallback and is never sent to the cancel endpoint as a
     * registration identifier.
     */
    fun cancelActivityRegistrationCommand(registrationKey: String) = executeWorkflow(childWorkflowKey("activity-cancel:$registrationKey"), {
        val childId = _state.value.selectedChild?.id
        val record = _state.value.local.activityRegistrations.firstOrNull {
            (it.registrationId == registrationKey || it.id == registrationKey ||
                (!repository.supportsRemoteAcknowledgement && it.activityId == registrationKey)) &&
                (it.childId == childId || it.childId == null)
        }
            ?: return@executeWorkflow
        if (repository.supportsRemoteAcknowledgement && record.registrationId != null) {
            val ack = repository.cancelActivityRegistration(record)
            applyActivityAck(record.activityId, ack, LocalSubmissionStatus.Submitted)
        } else {
            cancelActivityRegistration(record.activityId)
        }
    }, onSuccess = { if (repository.supportsRemoteAcknowledgement) loadActivities() })
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
    fun saveBodyAssessment(student: Student, record: BodyAssessmentRecord) = mutate { local ->
        val history = (local.bodyAssessmentHistory[student.id].orEmpty() + record).takeLast(24)
        local.copy(bodyAssessments = local.bodyAssessments + (student.id to record), bodyAssessmentHistory = local.bodyAssessmentHistory + (student.id to history), bodyAssessmentDrafts = local.bodyAssessmentDrafts - student.id, completedAssessments = local.completedAssessments + "${student.id}-身体测评", bodyAssessmentSyncStates = local.bodyAssessmentSyncStates + (student.id to if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Submitted))
    }.also {
        if (repository.supportsRemoteAcknowledgement) {
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + ("body-assessment-${student.id}" to WorkflowCommandState(WorkflowCommandStatus.Submitting)))
            viewModelScope.launch {
                runCatching {
                    val consent = _state.value.local.healthConsents[student.id]
                        ?: throw ApiError.Client("请先完成监护人授权后再同步身体测评")
                    if (consent.revokedAt != null) throw ApiError.Client("监护人授权已撤回，请重新确认后再同步身体测评")
                    repository.grantHealthConsent(consent)
                    val canonicalReport = repository.submitBodyAssessment(student.id, record, "v1")
                    if (canonicalReport != null) {
                        val current = _state.value.local.bodyAssessments[student.id]
                        if (current != null) {
                            val canonical = current.copy(postureReport = canonicalReport)
                            val history = _state.value.local.bodyAssessmentHistory[student.id].orEmpty().toMutableList()
                            if (history.isNotEmpty()) history[history.lastIndex] = canonical
                            mutate { local -> local.copy(bodyAssessments = local.bodyAssessments + (student.id to canonical), bodyAssessmentHistory = local.bodyAssessmentHistory + (student.id to history)) }
                        }
                    }
                }.onSuccess { updateBodyAssessmentSyncStatus(student.id, LocalSubmissionStatus.Submitted); _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + ("body-assessment-${student.id}" to WorkflowCommandState(WorkflowCommandStatus.Succeeded, "测评已同步学校后台"))) }
                    .onFailure { error ->
                        updateBodyAssessmentSyncStatus(student.id, LocalSubmissionStatus.Failed)
                        _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + ("body-assessment-${student.id}" to WorkflowCommandState(WorkflowCommandStatus.Failed, error.localizedMessage ?: "同步失败")))
                        if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                    }
            }
        }
    }
    fun saveBodyAssessmentDraft(student: Student, draft: BodyAssessmentDraft) = mutate { local ->
        local.copy(bodyAssessmentDrafts = local.bodyAssessmentDrafts + (student.id to draft))
    }
    fun toggleBodyPlanDay(student: Student, key: String) = mutate { local -> val record = local.bodyAssessments[student.id] ?: return@mutate local; local.copy(bodyAssessments = local.bodyAssessments + (student.id to record.copy(planDays = if (key in record.planDays) record.planDays - key else record.planDays + key))) }
    /** Progress can originate from a resumed player or a local draft; keep the
     * persisted value valid even if a caller supplies an out-of-range value. */
    companion object {
        fun courseProgressKey(childId: String, courseId: String, moduleId: String = "default", lessonId: String): String = "course|$childId|$courseId|$moduleId|$lessonId"
    }
    fun courseProgress(childId: String, courseId: String, moduleId: String = "default", lessonId: String, legacyTitle: String? = null): Float {
        val key = courseProgressKey(childId, courseId, moduleId, lessonId)
        return _state.value.local.courseProgress[key] ?: legacyTitle?.let { _state.value.local.courseProgress[it] } ?: 0f
    }
    fun updateCourseProgress(title: String, progress: Float) = mutate {
        it.copy(courseProgress = it.courseProgress + (title to progress.coerceIn(0f, 1f)))
    }
    fun updateCourseProgress(childId: String, courseId: String, moduleId: String = "default", lessonId: String, progress: Float) = mutate {
        it.copy(courseProgress = it.courseProgress + (courseProgressKey(childId, courseId, moduleId, lessonId) to progress.coerceIn(0f, 1f)))
    }
    /** Remote course lists never fall back to bundled cards: an empty result is
     * a truthful school-side assignment state. */
    fun loadActivities() {
        _state.value = _state.value.copy(activitiesLoading = true, activitiesError = null)
        viewModelScope.launch {
            runCatching { repository.activities(_state.value.selectedChild?.id) to repository.activityRegistrationHistory() }
                .onSuccess { (activities, history) -> _state.value = _state.value.copy(activitiesLoading = false, remoteActivities = activities, activityRegistrationHistory = history) }
                .onFailure { error ->
                    if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                    else _state.value = _state.value.copy(activitiesLoading = false, activitiesError = error.message ?: "活动加载失败")
                }
        }
    }

    fun loadExperts() {
        _state.value = _state.value.copy(expertsLoading = true, expertsError = null)
        viewModelScope.launch {
            runCatching { repository.experts() to repository.expertAppointmentHistory() }
                .onSuccess { (experts, history) -> _state.value = _state.value.copy(expertsLoading = false, remoteExperts = experts, expertAppointmentHistory = history) }
                .onFailure { error ->
                    if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                    else _state.value = _state.value.copy(expertsLoading = false, expertsError = error.message ?: "专家加载失败")
                }
        }
    }

    fun loadClassPosts(cursor: String? = null) {
        if (!repository.supportsRemoteAcknowledgement) return
        _state.value = _state.value.copy(classPostsLoading = true, classPostsError = null)
        viewModelScope.launch {
            val teacherMode = _state.value.role == UserRole.Teacher
            val selectedChildId = if (teacherMode) null else _state.value.selectedChild?.id
            val selectedClassId = if (teacherMode) _state.value.managedTeacherClasses.firstOrNull()?.id else _state.value.selectedChild?.classId
            runCatching { repository.loadClassPosts(_state.value.profile?.schoolId, selectedClassId, cursor) }
                .onSuccess { page ->
                    if (teacherMode) {
                        if (selectedClassId != null && _state.value.managedTeacherClasses.none { it.id == selectedClassId }) return@onSuccess
                    } else if (_state.value.selectedChild?.id != selectedChildId || _state.value.selectedChild?.classId != selectedClassId) return@onSuccess
                    mutate { local -> local.copy(classPosts = if (cursor == null) page.posts else local.classPosts + page.posts) }
                    _state.value = _state.value.copy(classPostsLoading = false, classPostsNextCursor = page.nextCursor)
                }
                .onFailure { error ->
                    if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                    else _state.value = _state.value.copy(classPostsLoading = false, classPostsError = error.message ?: "班级圈加载失败")
                }
        }
    }

    fun loadClassPostAttachment(fileId: String) {
        if (!repository.supportsRemoteAcknowledgement || fileId.isBlank() || _state.value.classPostAttachmentBytes.containsKey(fileId)) return
        _state.value = _state.value.copy(classPostAttachmentErrors = _state.value.classPostAttachmentErrors - fileId)
        viewModelScope.launch {
            runCatching { repository.loadClassPostAttachment(fileId) }
                .onSuccess { bytes -> _state.value = _state.value.copy(classPostAttachmentBytes = _state.value.classPostAttachmentBytes + (fileId to bytes)) }
                .onFailure { error -> _state.value = _state.value.copy(classPostAttachmentErrors = _state.value.classPostAttachmentErrors + (fileId to (error.message ?: "附件暂时无法打开"))) }
        }
    }

    fun loadExpertSlots(expertId: String) {
        if (expertId.isBlank()) return
        _state.value = _state.value.copy(expertSlotErrors = _state.value.expertSlotErrors - expertId)
        viewModelScope.launch {
            runCatching { repository.expertSlots(expertId) }
                .onSuccess { slots -> _state.value = _state.value.copy(expertSlots = _state.value.expertSlots + (expertId to slots)) }
                .onFailure { error ->
                    if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                    else _state.value = _state.value.copy(expertSlotErrors = _state.value.expertSlotErrors + (expertId to (error.message ?: "时段加载失败")))
                }
        }
    }

    fun loadCourses(childId: String) {
        if (!repository.supportsRemoteAcknowledgement) return
        // Reset synchronously before dispatching I/O.  This prevents a course
        // recommendation for a newly selected child from resolving against a
        // previous child's catalogue during a fast child switch.
        _state.value = _state.value.copy(coursesLoading = true, coursesError = null, remoteCourses = emptyList(), coursesChildId = childId)
        viewModelScope.launch {
            runCatching { repository.courses(childId) }
            .onSuccess { courses ->
                if (_state.value.coursesChildId == childId) _state.value = _state.value.copy(coursesLoading = false, remoteCourses = courses)
            }
            .onFailure { error ->
                if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                else if (_state.value.coursesChildId == childId) _state.value = _state.value.copy(coursesLoading = false, coursesError = error.message ?: "课程加载失败")
            }
        }
    }
    fun saveRemoteLessonProgress(childId: String, lesson: com.xiangshang.youth.core.service.RemoteLesson, lastPositionMs: Int, completed: Boolean) = viewModelScope.launch {
        if (!repository.supportsRemoteAcknowledgement) return@launch
        runCatching { repository.saveLessonProgress(childId, lesson.lessonId, lastPositionMs, completed, lesson.version) }
            .onSuccess { ack ->
                val key = courseProgressKey(childId, lesson.courseId, lesson.moduleId ?: "default", lesson.lessonId)
                mutate { it.copy(courseProgress = it.courseProgress + (key to if (ack.completed) 1f else (ack.lastPositionMs.toFloat() / lesson.durationMs.coerceAtLeast(1)).coerceIn(0f, 1f))) }
                _state.value = _state.value.copy(remoteCourses = _state.value.remoteCourses.map { current ->
                    if (current.lessonId == ack.lessonId) current.copy(lastPositionMs = ack.lastPositionMs, completed = ack.completed, version = ack.version) else current
                })
            }
            .onFailure { if (it is ApiError.Unauthorized) handleDashboardFailure(it) }
    }

    fun openRecommendedCourse(childId: String, courseId: String?, lessonId: String?, title: String) {
        _state.value = _state.value.copy(
            courseRecommendationTarget = CourseRecommendationTarget(childId, courseId, lessonId, title)
        )
    }
    fun openActivityTarget(activityId: String) { _state.value = _state.value.copy(pendingActivityId = activityId) }
    fun clearActivityTarget() { _state.value = _state.value.copy(pendingActivityId = null) }
    fun openExpertAppointmentTarget(appointmentId: String) { _state.value = _state.value.copy(pendingExpertAppointmentId = appointmentId) }
    fun clearExpertAppointmentTarget() { _state.value = _state.value.copy(pendingExpertAppointmentId = null) }

    fun clearRecommendedCourseTarget() {
        _state.value = _state.value.copy(courseRecommendationTarget = null)
    }

    fun saveFollowAlongSession(record: FollowAlongSessionRecord) {
        mutate { local ->
        val history = (local.followAlongSessions + record).takeLast(90)
        val key = "follow-along-${record.childId}"
        val previous = local.courseProgress[key] ?: 0f
        val dayKey = record.completedAt.take(10)
        val updatedBody = if (record.cameraVerified) local.bodyAssessments[record.childId]?.let { it.copy(planDays = it.planDays + dayKey) } else null
        local.copy(
            followAlongSessions = history,
            followAlongSyncStates = local.followAlongSyncStates + (record.id to if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Submitted),
            courseProgress = if (record.cameraVerified) local.courseProgress + (key to maxOf(previous, record.completionRatio).coerceIn(0f, 1f)) else local.courseProgress,
            checkedInDates = if (record.cameraVerified) local.checkedInDates + dayKey else local.checkedInDates,
            bodyAssessments = if (updatedBody != null) local.bodyAssessments + (record.childId to updatedBody) else local.bodyAssessments
        )
        }
        if (repository.supportsRemoteAcknowledgement && !_state.value.isOffline) syncFollowAlongSession(record)
    }
    private fun updateFollowAlongSyncStatus(sessionId: String, status: LocalSubmissionStatus) = mutate { local ->
        local.copy(followAlongSyncStates = local.followAlongSyncStates + (sessionId to status))
    }
    private fun syncFollowAlongSession(record: FollowAlongSessionRecord) = viewModelScope.launch {
        updateFollowAlongSyncStatus(record.id, LocalSubmissionStatus.Submitting)
        try {
            repository.submitFollowAlongSession(record)
            updateFollowAlongSyncStatus(record.id, LocalSubmissionStatus.Submitted)
        } catch (error: Throwable) {
            if (error is ApiError.Unauthorized) handleDashboardFailure(error)
            else updateFollowAlongSyncStatus(record.id, LocalSubmissionStatus.Failed)
        }
    }
    /** Legacy local composer hook. New submit flows use the tracked command above. */
    fun sendSupport(text: String) { createSupportMessage(text) }
    private fun createSupportMessage(text: String): SupportMessage {
        val message = SupportMessage(text = text, mine = true, status = LocalSubmissionStatus.PendingSync)
        mutate { it.copy(supportMessages = it.supportMessages + message) }
        return message
    }
    private fun updateSupportSyncStatus(id: String, status: LocalSubmissionStatus) = mutate { local ->
        local.copy(supportMessages = local.supportMessages.map { if (it.id == id) it.copy(status = status) else it })
    }
    fun publishPost(author: String, content: String, attachments: List<com.xiangshang.youth.core.service.ClassPostAttachment> = emptyList()): String? {
        if (content.isBlank()) return null
        val id = java.util.UUID.randomUUID().toString()
        val classId = _state.value.profile?.authorizedClassIds?.firstOrNull() ?: _state.value.selectedChild?.classId
        mutate { it.copy(classPosts = listOf(ClassPost(id = id, author = author, content = content, status = LocalSubmissionStatus.PendingSync, classId = classId, displayName = privacyDisplayName(author), visibilityScope = "class", moderationStatus = "pending_review", pinned = false, attachments = attachments, authorRole = if (_state.value.role == UserRole.Teacher) "teacher" else "parent")) + it.classPosts) }
        return id
    }
    fun updatePost(id: String, content: String) { if (content.isBlank()) return; mutate { local -> local.copy(classPosts = local.classPosts.map { if (it.id == id) it.copy(content = content, status = LocalSubmissionStatus.PendingSync) else it }) } }
    private fun updatePostSyncStatus(id: String, status: LocalSubmissionStatus, serverPostId: String? = null) = mutate { local ->
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
    fun bookExpert(name: String, date: String, note: String, expertIdOverride: String? = null, serviceId: String? = null, slotId: String? = null, scheduledStartAt: String? = null, scheduledEndAt: String? = null) {
        if (date.isBlank() || note.isBlank()) return
        val expertId = expertIdOverride?.takeIf { it.isNotBlank() } ?: return
        val childId = _state.value.selectedChild?.id
        // An update replaces the existing local projection. This preserves
        // idempotency without preventing a family from correcting a booking.
        mutate { local ->
            local.copy(expertAppointments = listOf(ExpertAppointment(expertName = name, preferredDate = date, note = note, status = LocalSubmissionStatus.PendingSync, expertId = expertId, serviceId = serviceId?.takeIf { it.isNotBlank() }, slotId = slotId?.takeIf { it.isNotBlank() }, childId = childId, appointmentStatus = "pending", scheduledStartAt = scheduledStartAt, scheduledEndAt = scheduledEndAt)) + local.expertAppointments.filterNot { it.expertId == expertId && (it.childId == childId || it.childId == null) })
        }
    }
    /** Uses a server appointment id when available; expert id is data scope,
     * not the identity of a booking. */
    fun cancelExpertCommand(appointmentKey: String) = executeWorkflow(childWorkflowKey("expert-cancel:$appointmentKey"), {
        val childId = _state.value.selectedChild?.id
        val record = _state.value.local.expertAppointments.firstOrNull {
            (it.appointmentId == appointmentKey || it.id == appointmentKey ||
                (!repository.supportsRemoteAcknowledgement && it.expertId == appointmentKey)) &&
                (it.childId == childId || it.childId == null)
        } ?: return@executeWorkflow
        if (repository.supportsRemoteAcknowledgement && record.appointmentId != null) {
            val ack = repository.cancelExpert(record)
            applyExpertAck(record.expertId ?: throw IllegalArgumentException("预约记录缺少专家编号，请刷新后重试。"), ack, LocalSubmissionStatus.Submitted)
        } else {
            mutate { local -> local.copy(expertAppointments = local.expertAppointments.filterNot { it.id == record.id }) }
        }
    }, onSuccess = { if (repository.supportsRemoteAcknowledgement) loadExperts() })

    fun rescheduleExpertCommand(name: String, date: String, note: String, expertId: String, serviceId: String?, slotId: String?, scheduledStartAt: String?, scheduledEndAt: String?) : Unit {
        val childId = _state.value.selectedChild?.id
        executeWorkflow(childWorkflowKey("expert:$expertId", childId), {
        if (slotId.isNullOrBlank()) throw IllegalArgumentException("请选择可预约时段。")
        val existing = _state.value.local.expertAppointments.firstOrNull { it.expertId == expertId && (it.childId == childId || it.childId == null) }
        if (existing?.appointmentId == null || !repository.supportsRemoteAcknowledgement) {
            bookExpert(name, date, note, expertId, serviceId, slotId, scheduledStartAt, scheduledEndAt)
            val record = _state.value.local.expertAppointments.firstOrNull { it.expertId == expertId && (it.childId == childId || it.childId == null) } ?: throw IllegalArgumentException("预约信息不完整。")
            applyExpertAck(expertId, repository.bookExpert(record), if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync)
        } else {
            val transport = existing.copy(expertName = name, preferredDate = date, note = note, expertId = expertId, serviceId = serviceId, slotId = slotId, scheduledStartAt = scheduledStartAt, scheduledEndAt = scheduledEndAt)
            applyExpertAck(expertId, repository.rescheduleExpert(transport, slotId), LocalSubmissionStatus.Submitted)
        }
    }, onSuccess = { if (repository.supportsRemoteAcknowledgement) loadExperts() }, onFailure = {
        _state.value.local.expertAppointments.firstOrNull { it.expertId == expertId && (it.childId == childId || it.childId == null) }?.let(::markExpertSyncFailed)
        })
    }

    private fun privacyDisplayName(value: String): String {
        val first = value.trim().firstOrNull() ?: return "本班家长"
        return "${first}同学家长"
    }
    fun saveCourseUpload(taskId: String, attendance: Int, notes: String, attachment: String, attachmentReference: String? = null, submit: Boolean) {
        val trimmedNotes = notes.trim()
        val trimmedAttachment = attachment.trim()
        if (attendance < 0 || (submit && !CourseUploadValidator.isValidForSubmission(attendance, trimmedNotes, trimmedAttachment, attachmentReference))) return
        mutate { local ->
            val record = CourseUploadRecord(taskId=taskId, attendanceCount=attendance, notes=trimmedNotes, attachmentName=trimmedAttachment, attachmentReference=attachmentReference, status=if (submit) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Draft)
            local.copy(courseUploads=listOf(record)+local.courseUploads.filterNot { it.taskId==taskId }, uploadedTaskIds=if (submit) local.uploadedTaskIds+taskId else local.uploadedTaskIds)
        }
    }
    private fun applyActivityAck(activityId: String, ack: ActivityRegistrationAck, status: LocalSubmissionStatus) {
        mutate { local ->
            val selectedChildId = ack.childId ?: _state.value.selectedChild?.id
            val exactRegistrationIndex = local.activityRegistrations.indexOfFirst {
                it.activityId == activityId && it.registrationId == ack.registrationId
            }
            val targetIndex = if (exactRegistrationIndex >= 0) exactRegistrationIndex else {
                local.activityRegistrations.indexOfFirst {
                    it.activityId == activityId && (it.childId == selectedChildId || it.childId == null)
                }
            }
            val projected = local.activityRegistrations.mapIndexed { index, value ->
                if (index == targetIndex) value.copy(
                        status = status,
                        registrationId = ack.registrationId,
                        childId = ack.childId ?: value.childId,
                        contactName = ack.contactName ?: value.contactName,
                        phone = ack.phone ?: value.phone,
                        registrationStatus = ack.status,
                        version = ack.version
                    ) else value
                }
            local.copy(
                activityRegistered = projected.any { it.registrationStatus != "cancelled" },
                activityRegistrations = projected
            )
        }
        _state.value = _state.value.copy(activityRegistrationHistory = listOf(ack) + _state.value.activityRegistrationHistory.filterNot { it.registrationId == ack.registrationId })
    }
    private fun applyExpertAck(expertId: String, ack: ExpertAppointmentAck, status: LocalSubmissionStatus) {
        mutate { local ->
            val targetChildId = ack.childId ?: _state.value.selectedChild?.id
            val targetIndex = local.expertAppointments.indexOfFirst {
                it.expertId == expertId && (it.childId == targetChildId || it.childId == null)
            }
            local.copy(expertAppointments = local.expertAppointments.mapIndexed { index, value ->
                if (index == targetIndex) value.copy(
                    status = status,
                    appointmentId = ack.appointmentId,
                    expertId = ack.expertId ?: value.expertId,
                    serviceId = ack.serviceId ?: value.serviceId,
                    slotId = ack.slotId ?: value.slotId,
                    childId = ack.childId ?: value.childId,
                    expertName = ack.expertName ?: value.expertName,
                    preferredDate = ack.preferredDate ?: value.preferredDate,
                    note = ack.note ?: value.note,
                    appointmentStatus = ack.status,
                    expectedVersion = ack.version,
                    scheduledStartAt = ack.scheduledStartAt ?: value.scheduledStartAt,
                    scheduledEndAt = ack.scheduledEndAt ?: value.scheduledEndAt
                ) else value
            })
        }
        _state.value = _state.value.copy(expertAppointmentHistory = listOf(ack) + _state.value.expertAppointmentHistory.filterNot { it.appointmentId == ack.appointmentId })
    }
    private fun markActivitySynced(activityId: String) = updateActivitySyncStatus(activityId, LocalSubmissionStatus.Submitted)
    private fun markActivitySyncSubmitting(activityId: String) = updateActivitySyncStatus(activityId, LocalSubmissionStatus.Submitting)
    private fun markActivitySyncFailed(activityId: String) = updateActivitySyncStatus(activityId, LocalSubmissionStatus.Failed)
    private fun updateActivitySyncStatus(activityId: String, status: LocalSubmissionStatus) = mutate { local -> local.copy(activityRegistrations = local.activityRegistrations.map { if (it.activityId == activityId) it.copy(status = status) else it }) }
    private fun markExpertSynced(record: ExpertAppointment) = updateExpertSyncStatus(record, LocalSubmissionStatus.Submitted)
    private fun markExpertSyncSubmitting(record: ExpertAppointment) = updateExpertSyncStatus(record, LocalSubmissionStatus.Submitting)
    private fun markExpertSyncFailed(record: ExpertAppointment) = updateExpertSyncStatus(record, LocalSubmissionStatus.Failed)
    private fun updateExpertSyncStatus(record: ExpertAppointment, status: LocalSubmissionStatus) = mutate { local ->
        local.copy(expertAppointments = local.expertAppointments.map { value ->
            if (value.id == record.id) value.copy(status = status) else value
        })
    }
    private fun markCourseSynced(taskId: String) = updateCourseSyncStatus(taskId, LocalSubmissionStatus.Submitted)
    private fun markCourseSyncSubmitting(taskId: String) = updateCourseSyncStatus(taskId, LocalSubmissionStatus.Submitting)
    private fun markCourseSyncFailed(taskId: String) = updateCourseSyncStatus(taskId, LocalSubmissionStatus.Failed)
    private fun updateCourseSyncStatus(taskId: String, status: LocalSubmissionStatus) = mutate { local -> local.copy(courseUploads = local.courseUploads.map { if (it.taskId == taskId) it.copy(status = status) else it }) }
    private fun markTaskStatusSynced(studentId: String, taskId: String? = null) = updateTaskStatusSyncStatus(studentId, taskId, LocalSubmissionStatus.Submitted)
    private fun markTaskStatusSyncPending(studentId: String, taskId: String? = null) = updateTaskStatusSyncStatus(studentId, taskId, LocalSubmissionStatus.PendingSync)
    private fun markTaskStatusSyncSubmitting(studentId: String, taskId: String? = null) = updateTaskStatusSyncStatus(studentId, taskId, LocalSubmissionStatus.Submitting)
    private fun markTaskStatusSyncFailed(studentId: String, taskId: String? = null) = updateTaskStatusSyncStatus(studentId, taskId, LocalSubmissionStatus.Failed)
    private fun updateTaskStatusSyncStatus(studentId: String, taskId: String? = null, status: LocalSubmissionStatus) = mutate { local ->
        val key = _state.value.taskKey(taskId, studentId)
        local.copy(
            taskScopedSyncStates = local.taskScopedSyncStates + (key to status),
            taskStatusSyncStates = if (_state.value.repositoryAcknowledged) local.taskStatusSyncStates else local.taskStatusSyncStates + (studentId to status)
        )
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
                studentTaskStatuses = if (_state.value.repositoryAcknowledged) local.studentTaskStatuses else local.studentTaskStatuses - studentId,
                taskScopedStatuses = local.taskScopedStatuses - key,
                taskScopedStatusVersions = local.taskScopedStatusVersions - key,
                taskScopedSyncStates = local.taskScopedSyncStates + (key to LocalSubmissionStatus.Failed),
                taskStatusVersions = if (_state.value.repositoryAcknowledged) local.taskStatusVersions else local.taskStatusVersions - studentId,
                taskStatusSyncStates = if (_state.value.repositoryAcknowledged) local.taskStatusSyncStates else local.taskStatusSyncStates + (studentId to LocalSubmissionStatus.Failed)
            )
        }
    }
    private fun updateBodyAssessmentSyncStatus(studentId: String, status: LocalSubmissionStatus) = mutate { local -> local.copy(bodyAssessmentSyncStates = local.bodyAssessmentSyncStates + (studentId to status)) }
    fun updateStudentTaskStatus(studentId: String, status: TaskStatus, taskId: String? = null) {
        val student = _state.value.data?.students?.firstOrNull { it.id == studentId } ?: return
        val current = _state.value.taskStatus(student, taskId)
        if (!current.allowsTransitionTo(status)) return
        mutate { local -> local.copy(taskScopedStatuses = local.taskScopedStatuses + (_state.value.taskKey(taskId, studentId) to status), studentTaskStatuses = if (_state.value.repositoryAcknowledged) local.studentTaskStatuses else local.studentTaskStatuses + (studentId to status)) }
    }
    fun submitReviewDecision(studentId: String, status: TaskStatus, note: String, taskId: String? = null) {
        val trimmed = note.trim()
        if (trimmed.isBlank()) return
        val student = _state.value.data?.students?.firstOrNull { it.id == studentId } ?: return
        val current = _state.value.taskStatus(student, taskId)
        if (!current.allowsTransitionTo(status)) return
        mutate { local -> local.copy(taskScopedStatuses = local.taskScopedStatuses + (_state.value.taskKey(taskId, studentId) to status), taskScopedReviewNotes = local.taskScopedReviewNotes + (_state.value.taskKey(taskId, studentId) to trimmed), studentTaskStatuses = if (_state.value.repositoryAcknowledged) local.studentTaskStatuses else local.studentTaskStatuses + (studentId to status), reviewNotes = if (_state.value.repositoryAcknowledged) local.reviewNotes else local.reviewNotes + (studentId to trimmed)) }
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
    private fun handleDashboardFailure(error: Throwable) {
        if (error is ApiError.Unauthorized) {
            featureStore.clear()
            _state.value = AppUiState(error = error.message)
        } else _state.value = _state.value.copy(loading = false, error = error.message)
    }
    private fun mutate(transform: (LocalFeatureState) -> LocalFeatureState) { val local = transform(_state.value.local); featureStore.save(local); _state.value = _state.value.copy(local = local) }
}
