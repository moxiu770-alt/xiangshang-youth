package com.xiangshang.youth.app

import androidx.lifecycle.viewModelScope
import com.xiangshang.youth.core.model.BodyAssessmentDraft
import com.xiangshang.youth.core.model.BodyAssessmentRecord
import com.xiangshang.youth.core.model.Student
import com.xiangshang.youth.core.service.ApiError
import com.xiangshang.youth.core.service.FollowAlongSessionRecord
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.util.BusinessClock
import kotlinx.coroutines.launch

/** Privacy operations remain child-scoped and validate the visible dashboard
 * before constructing a write request. They live with health consent rather
 * than the cross-domain session holder. */
fun AppViewModel.submitPrivacyRequest(studentId: String, requestType: String) {
    val key = "privacy:$studentId:$requestType"
    if (_state.value.data?.students?.none { it.id == studentId } != false) {
        setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Failed, "未找到孩子信息，请重新选择后再试。"))
        return
    }
    executeWorkflow(key, { repository.submitPrivacyRequest(studentId, requestType) }, successMessage = {
        if (repository.supportsRemoteAcknowledgement) {
            if (requestType == "export") "导出申请已提交，文件生成后会在消息中心通知。" else "删除申请已提交，需经学校/平台审核；审核前不会删除任何记录。"
        } else "申请已保存到本机记录。接入学校服务后可提交审核。"
    })
}

fun AppViewModel.revokeHealthConsent(studentId: String, version: String? = null) {
    val key = "privacy:$studentId:consent-revoke"
    if (_state.value.data?.students?.none { it.id == studentId } != false) {
        setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Failed, "未找到孩子信息，请重新选择后再试。"))
        return
    }
    val resolvedVersion = version?.takeIf { it.isNotBlank() }
        ?: _state.value.local.healthConsents[studentId]?.privacyPolicyVersion?.takeIf { it.isNotBlank() }
    if (resolvedVersion == null) {
        setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Failed, "未找到有效的监护人授权版本，请重新完成授权。"))
        return
    }
    executeWorkflow(key, { repository.revokeHealthConsent(studentId, resolvedVersion) }, onSuccess = {
        val existing = _state.value.local.healthConsents[studentId] ?: return@executeWorkflow
        mutate { it.copy(healthConsents = it.healthConsents + (studentId to existing.copy(revokedAt = BusinessClock.format("yyyy-MM-dd'T'HH:mm:ssXXX")))) }
    }, successMessage = {
        if (repository.supportsRemoteAcknowledgement) "已撤回身体测评数据使用同意；新的身体测评需重新授权。" else "撤回记录已保存在本机，接入学校服务后提交。"
    })
}

fun AppViewModel.submitAccountDeletionRequest() = executeWorkflow(
    "privacy:account-deletion",
    { repository.submitAccountDeletionRequest() },
    successMessage = {
        if (repository.supportsRemoteAcknowledgement) "注销申请已提交，平台审核通过后会撤销会话并匿名化账户。" else "注销申请已保存到本机记录，接入学校服务后提交审核。"
    }
)

/** Child-scoped body assessment and guided training receipt lifecycle. */
fun AppViewModel.saveBodyAssessment(student: Student, record: BodyAssessmentRecord) {
    mutate { local ->
        val history = (local.bodyAssessmentHistory[student.id].orEmpty() + record).takeLast(24)
        local.copy(bodyAssessments = local.bodyAssessments + (student.id to record), bodyAssessmentHistory = local.bodyAssessmentHistory + (student.id to history), bodyAssessmentDrafts = local.bodyAssessmentDrafts - student.id, completedAssessments = local.completedAssessments + "${student.id}-身体测评", bodyAssessmentSyncStates = local.bodyAssessmentSyncStates + (student.id to if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Submitted))
    }
    if (!repository.supportsRemoteAcknowledgement) return
    _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + ("body-assessment-${student.id}" to WorkflowCommandState(WorkflowCommandStatus.Submitting)))
    viewModelScope.launch {
        runCatching {
            val consent = _state.value.local.healthConsents[student.id] ?: throw ApiError.Client("请先完成监护人授权后再同步身体测评")
            if (consent.revokedAt != null) throw ApiError.Client("监护人授权已撤回，请重新确认后再同步身体测评")
            if (consent.privacyPolicyVersion != com.xiangshang.youth.core.model.LegalPolicy.PRIVACY_POLICY_VERSION ||
                consent.cameraConsentVersion != com.xiangshang.youth.core.model.LegalPolicy.CAMERA_CONSENT_VERSION ||
                consent.algorithmNoticeVersion != com.xiangshang.youth.core.model.LegalPolicy.ALGORITHM_NOTICE_VERSION
            ) throw ApiError.Client("授权说明已更新，请返回监护人授权步骤重新确认")
            repository.grantHealthConsent(consent)
            repository.submitBodyAssessment(student.id, record, consent.privacyPolicyVersion)
        }.onSuccess { report ->
            if (report != null) mutate { local ->
                val current = local.bodyAssessments[student.id] ?: return@mutate local
                val canonical = current.copy(postureReport = report); val history = local.bodyAssessmentHistory[student.id].orEmpty().toMutableList()
                if (history.isNotEmpty()) history[history.lastIndex] = canonical
                local.copy(bodyAssessments = local.bodyAssessments + (student.id to canonical), bodyAssessmentHistory = local.bodyAssessmentHistory + (student.id to history))
            }
            updateBodyAssessmentSyncStatus(student.id, LocalSubmissionStatus.Submitted)
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + ("body-assessment-${student.id}" to WorkflowCommandState(WorkflowCommandStatus.Succeeded, "测评已同步学校后台")))
        }.onFailure { error ->
            updateBodyAssessmentSyncStatus(student.id, LocalSubmissionStatus.Failed)
            _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + ("body-assessment-${student.id}" to WorkflowCommandState(WorkflowCommandStatus.Failed, error.localizedMessage ?: "同步失败")))
            if (error is ApiError.Unauthorized) handleDashboardFailure(error)
        }
    }
}

fun AppViewModel.refreshLatestBodyAssessment(student: Student) {
    if (!repository.supportsRemoteAcknowledgement) return
    val record = _state.value.local.bodyAssessments[student.id] ?: return
    val key = "body-assessment-refresh-${student.id}"
    setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Submitting))
    viewModelScope.launch {
        runCatching { repository.loadLatestBodyAssessment(student.id, record) }
            .onSuccess { report ->
                if (_state.value.selectedChild?.id != student.id) return@onSuccess
                if (report != null) mutate { local ->
                    val current = local.bodyAssessments[student.id] ?: return@mutate local
                    val canonical = current.copy(postureReport = report)
                    val history = local.bodyAssessmentHistory[student.id].orEmpty().toMutableList()
                    if (history.isNotEmpty()) history[history.lastIndex] = canonical
                    local.copy(bodyAssessments = local.bodyAssessments + (student.id to canonical), bodyAssessmentHistory = local.bodyAssessmentHistory + (student.id to history))
                }
                setWorkflow(key, if (report == null) WorkflowCommandState(WorkflowCommandStatus.Failed, "学校服务尚未返回身体观察结果。") else WorkflowCommandState(WorkflowCommandStatus.Succeeded, "复核状态已更新"))
            }
            .onFailure { error ->
                setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Failed, error.localizedMessage ?: "复核状态更新失败"))
                if (error is ApiError.Unauthorized) handleDashboardFailure(error)
            }
    }
}

fun AppViewModel.saveBodyAssessmentDraft(student: Student, draft: BodyAssessmentDraft) = mutate { local -> local.copy(bodyAssessmentDrafts = local.bodyAssessmentDrafts + (student.id to draft)) }
fun AppViewModel.toggleBodyPlanDay(student: Student, key: String) = mutate { local ->
    val record = local.bodyAssessments[student.id] ?: return@mutate local
    local.copy(bodyAssessments = local.bodyAssessments + (student.id to record.copy(planDays = if (key in record.planDays) record.planDays - key else record.planDays + key)))
}

fun AppViewModel.saveFollowAlongSession(record: FollowAlongSessionRecord) {
    mutate { local ->
        val key = "follow-along-${record.childId}"; val day = record.completedAt.take(10); val parentConfirmed = record.mode == "parentConfirmedAssistedTraining" && record.completionRatio >= 1f; val acceptedCompletion = record.cameraVerified || parentConfirmed; val body = if (acceptedCompletion) local.bodyAssessments[record.childId]?.copy(planDays = local.bodyAssessments[record.childId]?.planDays.orEmpty() + day) else null
        local.copy(followAlongSessions = (local.followAlongSessions + record).takeLast(90), followAlongSyncStates = local.followAlongSyncStates + (record.id to if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Submitted), courseProgress = if (acceptedCompletion) local.courseProgress + (key to maxOf(local.courseProgress[key] ?: 0f, record.completionRatio).coerceIn(0f, 1f)) else local.courseProgress, checkedInDates = if (acceptedCompletion) local.checkedInDates + day else local.checkedInDates, bodyAssessments = if (body != null) local.bodyAssessments + (record.childId to body) else local.bodyAssessments)
    }
    if (repository.supportsRemoteAcknowledgement && !_state.value.isOffline) syncFollowAlongSession(record)
}

internal fun AppViewModel.updateFollowAlongSyncStatus(id: String, status: LocalSubmissionStatus) = mutate { it.copy(followAlongSyncStates = it.followAlongSyncStates + (id to status)) }
internal fun AppViewModel.syncFollowAlongSession(record: FollowAlongSessionRecord) = viewModelScope.launch {
    updateFollowAlongSyncStatus(record.id, LocalSubmissionStatus.Submitting)
    try { repository.submitFollowAlongSession(record); updateFollowAlongSyncStatus(record.id, LocalSubmissionStatus.Submitted) }
    catch (error: Throwable) { if (error is ApiError.Unauthorized) handleDashboardFailure(error) else updateFollowAlongSyncStatus(record.id, LocalSubmissionStatus.Failed) }
}
