package com.xiangshang.youth.app

import android.app.Application
import android.content.Intent
import androidx.core.net.toUri
import androidx.lifecycle.viewModelScope
import com.xiangshang.youth.BuildConfig
import com.xiangshang.youth.core.model.*
import com.xiangshang.youth.core.service.*
import com.xiangshang.youth.core.sync.PendingSyncScheduler
import com.xiangshang.youth.core.util.AuthIdentity
import com.xiangshang.youth.core.util.BusinessClock
import com.xiangshang.youth.core.util.ChildBindingValidator
import kotlinx.coroutines.launch

fun AppViewModel.login(identifier: String = "", verificationCode: String? = null, password: String? = null, displayName: String? = null, accountRole: UserRole? = null, onSuccess: () -> Unit = {}) = viewModelScope.launch {
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
            val sessionLocal = _state.value.local.copy(
                sessionActive = true,
                sessionPhone = profile.phone,
                sessionRoleName = profile.role.name,
                accountBucketName = profile.role.name,
                parentAccountName = if (bucket == UserRole.Parent) profile.name else _state.value.local.parentAccountName
            )
            val (local, selected) = reconcileChildScope(profile, data, sessionLocal)
            featureStore.save(local)
            _state.value = AppUiState(profile, role = if (repository.supportsRemoteAcknowledgement) profile.role else accountRole, data = data, selectedChild = selected, local = local, repositoryAcknowledged = repository.supportsRemoteAcknowledgement)
            onSuccess()
        }.onFailure { handleDashboardFailure(it) }
    }

    /** Completes the one-time native callback from the server relay. */
fun AppViewModel.exchangeWechat(code: String, state: String, onSuccess: () -> Unit = {}) = viewModelScope.launch {
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
            val sessionLocal = _state.value.local.copy(sessionActive = true, sessionPhone = profile.phone, sessionRoleName = profile.role.name, accountBucketName = profile.role.name, parentAccountName = if (profile.role == UserRole.Parent) profile.name else _state.value.local.parentAccountName)
            val (local, selected) = reconcileChildScope(profile, data, sessionLocal)
            featureStore.save(local)
            _state.value = AppUiState(profile, role = profile.role, data = data, selectedChild = selected, local = local, repositoryAcknowledged = true)
            onSuccess()
        }.onFailure { handleDashboardFailure(it) }
        _state.value = _state.value.copy(loading = false)
    }
fun AppViewModel.register(name: String, phone: String, verificationCode: String, password: String, role: UserRole, onSuccess: () -> Unit = {}) = viewModelScope.launch {
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
            val sessionLocal = _state.value.local.copy(sessionActive = true, sessionPhone = profile.phone, sessionRoleName = profile.role.name, accountBucketName = profile.role.name, parentAccountName = if (profile.role == UserRole.Parent) profile.name else _state.value.local.parentAccountName)
            val (local, selected) = reconcileChildScope(profile, data, sessionLocal)
            featureStore.save(local)
            _state.value = AppUiState(profile, role = if (repository.supportsRemoteAcknowledgement) profile.role else role, data = data, selectedChild = selected, local = local, repositoryAcknowledged = repository.supportsRemoteAcknowledgement)
            onSuccess()
        }.onFailure { handleDashboardFailure(it) }
    }
fun AppViewModel.resetPassword(phone: String, verificationCode: String, password: String, onResult: (Boolean, String?) -> Unit) = viewModelScope.launch {
        if (!repository.supportsRemoteAcknowledgement) { onResult(true, null); return@launch }
        runCatching { ApiClient.retrofit.create(AuthApi::class.java).resetPassword(ResetPasswordRequest(phone, verificationCode, password)) }
            .onSuccess { onResult(true, null) }
            .onFailure { onResult(false, it.localizedMessage ?: "密码重置失败，请稍后重试") }
    }
fun AppViewModel.requestVerificationCode(account: String, purpose: String, onResult: (Boolean, String?) -> Unit) = viewModelScope.launch {
        if (account.filter(Char::isDigit).length != 11) { onResult(false, "请输入有效的 11 位手机号。"); return@launch }
        if (!repository.supportsRemoteAcknowledgement) { onResult(true, null); return@launch }
        runCatching { ApiClient.retrofit.create(AuthApi::class.java).sendVerificationCode(VerificationCodeRequest(account, purpose)) }
            .onSuccess { onResult(true, null) }
            .onFailure { onResult(false, it.localizedMessage ?: "验证码发送失败，请稍后重试") }
    }
fun AppViewModel.canUseRole(role: UserRole): Boolean = _state.value.profile?.availableRoles?.contains(role) == true

fun AppViewModel.chooseRole(role: UserRole) {
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
fun AppViewModel.clearRoleSelection() {
        val local = _state.value.local.copy(sessionRoleName = null)
        featureStore.save(local)
        _state.value = _state.value.copy(local = local, role = null, taskRosterRecords = emptyMap())
    }
fun AppViewModel.selectPrincipalTask(taskId: String) = mutate { it.copy(selectedPrincipalTaskId = taskId) }
fun AppViewModel.setTeacherSportsWorkbench(enabled: Boolean) = mutate { it.copy(teacherUsesSportsWorkbench = enabled) }
fun AppViewModel.recordHealthConsent(
        studentId: String,
        privacyVersion: String = com.xiangshang.youth.core.model.LegalPolicy.PRIVACY_POLICY_VERSION,
        cameraVersion: String = com.xiangshang.youth.core.model.LegalPolicy.CAMERA_CONSENT_VERSION,
        algorithmVersion: String = com.xiangshang.youth.core.model.LegalPolicy.ALGORITHM_NOTICE_VERSION
    ) {
        val guardian = _state.value.profile ?: return
        val consent = com.xiangshang.youth.core.service.HealthConsentRecord(
            consentId = java.util.UUID.randomUUID().toString(), guardianUserId = guardian.id, childId = studentId,
            privacyPolicyVersion = privacyVersion, cameraConsentVersion = cameraVersion, algorithmNoticeVersion = algorithmVersion,
            agreedAt = BusinessClock.format("yyyy-MM-dd'T'HH:mm:ssXXX"), deviceInfo = "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}", dataRetentionNoticeAccepted = true
        )
        mutate { it.copy(healthConsents = it.healthConsents + (studentId to consent)) }
    }
fun AppViewModel.chooseChild(student: Student) {
        mutate { it.copy(selectedChildId = student.id) }
        _state.value = _state.value.copy(selectedChild = student)
        loadHealthCheckins(student.id)
        if (repository.supportsRemoteAcknowledgement) {
            loadFamilyHealthObservations(student.id)
            loadClassPosts()
            loadActivities()
        }
    }
fun AppViewModel.markMessageRead(messageId: String) {
        mutate { it.copy(readMessageIds = it.readMessageIds + messageId) }
        if (repository.supportsRemoteAcknowledgement) viewModelScope.launch {
            runCatching { repository.markMessageRead(messageId) }.onFailure { if (it is ApiError.Unauthorized) handleDashboardFailure(it) }
        }
    }
fun AppViewModel.markAllMessagesRead() = mutate { local ->
        local.copy(readMessageIds = local.readMessageIds + (_state.value.data?.messages?.map { it.id }.orEmpty()))
    }.also {
        if (repository.supportsRemoteAcknowledgement) _state.value.data?.messages.orEmpty().forEach { message -> viewModelScope.launch { runCatching { repository.markMessageRead(message.id) }.onFailure { if (it is ApiError.Unauthorized) handleDashboardFailure(it) } } }
    }
fun AppViewModel.bindChild(name: String, code: String): Boolean {
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
fun AppViewModel.logout() {
        sessionGeneration += 1
        sessionRestoreJob?.cancel()
        sessionRestoreJob = null
        ApiClient.clearToken()
        com.xiangshang.youth.core.util.FrontendTelemetry.configure(false)
        featureStore.clear()
        _state.value = AppUiState()
    }

    /**
     * Instrumentation-only identity fixture.  Public registration deliberately
     * never creates a teacher account; UI tests that cover the teacher
     * workbench must therefore use an explicit school-provisioned identity
     * with the same scoped claims a server session would provide.
     */
fun AppViewModel.startSchoolProvisionedTeacherFixtureForUiTest() {
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
