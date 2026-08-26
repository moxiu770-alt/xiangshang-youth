package com.xiangshang.youth.app

import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.service.SupportMessage

/** Support conversation state has its own submission lifecycle and must not
 * be coupled to authentication, tasks or child-health mutations. */
fun AppViewModel.submitSupportCommand(content: String) {
    val normalized = content.trim()
    val key = "support"
    if (normalized.isBlank()) {
        setWorkflow(key, WorkflowCommandState(WorkflowCommandStatus.Failed, "请输入咨询内容。"))
        return
    }
    val message = createSupportMessage(normalized)
    executeWorkflow(key, operation = { repository.sendSupportMessage(normalized) }, onSuccess = {
        updateSupportSyncStatus(message.id, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync)
    }, onFailure = { updateSupportSyncStatus(message.id, LocalSubmissionStatus.Failed) })
}

/** Legacy local composer hook. New submit flows use the tracked command above. */
fun AppViewModel.sendSupport(text: String) { createSupportMessage(text) }

private fun AppViewModel.createSupportMessage(text: String): SupportMessage {
    val message = SupportMessage(text = text, mine = true, status = LocalSubmissionStatus.PendingSync)
    mutate { it.copy(supportMessages = it.supportMessages + message) }
    return message
}

internal fun AppViewModel.updateSupportSyncStatus(id: String, status: LocalSubmissionStatus) = mutate { local ->
    local.copy(supportMessages = local.supportMessages.map { if (it.id == id) it.copy(status = status) else it })
}
