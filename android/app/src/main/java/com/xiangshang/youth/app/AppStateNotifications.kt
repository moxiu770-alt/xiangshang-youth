package com.xiangshang.youth.app

import androidx.lifecycle.viewModelScope
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.service.ApiError
import com.xiangshang.youth.core.service.NotificationCampaign
import com.xiangshang.youth.core.service.NotificationCampaignDetail
import kotlinx.coroutines.launch

/**
 * School notifications are kept away from the general session state because
 * their draft, delivery and acknowledgement lifecycles have distinct rules.
 */
fun AppViewModel.submitClassNoticeCommand(classId: String, title: String, content: String) =
    executeWorkflow("notice:$classId", operation = {
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

fun AppViewModel.loadNotificationDrafts() = viewModelScope.launch {
    val schoolId = _state.value.profile?.schoolId.orEmpty()
    if (schoolId.isBlank()) return@launch
    _state.value = _state.value.copy(notificationDraftsLoading = true, notificationDraftsError = null)
    runCatching { repository.listNotificationDrafts(schoolId) }
        .onSuccess { drafts ->
            _state.value = _state.value.copy(notificationDrafts = drafts, notificationDraftsLoading = false, notificationDraftsError = null)
        }
        .onFailure { error ->
            _state.value = _state.value.copy(notificationDraftsLoading = false, notificationDraftsError = error.localizedMessage ?: "通知草稿加载失败")
        }
}

fun AppViewModel.saveNotificationDraft(
    notificationId: String?,
    classIds: List<String>,
    title: String,
    content: String,
    draftVersion: Int?,
    parentReceiptEnabled: Boolean,
    scheduledAt: String? = null,
    onSaved: (NotificationCampaign?) -> Unit = {}
) = viewModelScope.launch {
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
        if (notificationId != null && draftVersion != null) {
            repository.updateNotificationDraft(notificationId, profile.schoolId.orEmpty(), targets, cleanTitle, cleanContent, draftVersion, parentReceiptEnabled = parentReceiptEnabled, scheduledAt = scheduledAt)
        } else {
            repository.createNotificationDraft(profile.schoolId.orEmpty(), targets, cleanTitle, cleanContent, parentReceiptEnabled = parentReceiptEnabled, scheduledAt = scheduledAt)
        }
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

fun AppViewModel.sendNotificationDraft(notificationId: String) = executeWorkflow("notice:send:$notificationId", operation = {
    repository.sendNotification(notificationId)
}, onSuccess = {
    _state.value = _state.value.copy(notificationDrafts = _state.value.notificationDrafts.filterNot { it.notificationId == notificationId })
})

fun AppViewModel.discardNotificationDraft(notificationId: String) = executeWorkflow("notice:discard:$notificationId", operation = {
    repository.discardNotificationDraft(notificationId)
}, onSuccess = {
    _state.value = _state.value.copy(notificationDrafts = _state.value.notificationDrafts.filterNot { it.notificationId == notificationId })
})

fun AppViewModel.loadClassNoticeDetail(notificationId: String, onLoaded: (NotificationCampaignDetail?) -> Unit = {}) = viewModelScope.launch {
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

fun AppViewModel.acknowledgeClassNotice(notificationId: String, onDone: (Boolean) -> Unit = {}) =
    executeWorkflow("notice:receipt:$notificationId", operation = {
        repository.acknowledgeClassNotice(notificationId)
    }, onSuccess = { onDone(true) }, onFailure = { onDone(false) }, successMessage = { "已确认收到，学校会看到回执。" })
