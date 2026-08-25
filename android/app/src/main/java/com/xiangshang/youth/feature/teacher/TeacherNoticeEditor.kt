package com.xiangshang.youth.feature.teacher

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.service.NotificationCampaign

/**
 * The notice editor is intentionally independent from the class-circle feed.
 * It works only with IDs in [AppUiState.managedTeacherClasses], so the UI
 * cannot broaden a teacher's server-authorized scope.
 */
@Composable
fun TeacherNoticeEditorDialog(
    state: AppUiState,
    initialClassId: String?,
    workflowStates: Map<String, WorkflowCommandState>,
    saveDraft: (String, String) -> Unit,
    clearDraft: (String) -> Unit,
    loadNotificationDrafts: () -> Unit,
    saveNotificationDraft: (String?, List<String>, String, String, Int?, Boolean, String?, (NotificationCampaign?) -> Unit) -> Unit,
    sendNotificationDraft: (String) -> Unit,
    discardNotificationDraft: (String) -> Unit,
    onSuccess: () -> Unit,
    onDismiss: () -> Unit
) {
    val classes = state.managedTeacherClasses
    val selectedClassIds = remember { mutableStateListOf<String>() }
    var title by rememberSaveable { mutableStateOf("") }
    var content by rememberSaveable { mutableStateOf("") }
    var notificationId by rememberSaveable { mutableStateOf<String?>(null) }
    var draftVersion by rememberSaveable { mutableStateOf<Int?>(null) }
    var parentReceiptEnabled by rememberSaveable { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmed by remember { mutableStateOf(false) }
    val draftKey = "teacher-notice-draft:${selectedClassIds.joinToString(",")}"
    val draft = state.local.drafts[draftKey].orEmpty()
    val draftCommand = workflowStates["notice:draft"] ?: WorkflowCommandState()
    val sendCommand = notificationId?.let { workflowStates["notice:send:$it"] } ?: WorkflowCommandState()
    val command = if (draftCommand.isSubmitting) draftCommand else sendCommand

    LaunchedEffect(Unit) {
        initialClassId?.takeIf { it.isNotBlank() }?.let { if (it !in selectedClassIds) selectedClassIds.add(it) }
        loadNotificationDrafts()
    }
    LaunchedEffect(state.notificationDrafts) {
        if (notificationId == null) {
            state.notificationDrafts.firstOrNull()?.let { remote ->
                notificationId = remote.notificationId
                draftVersion = remote.draftVersion
                title = remote.title
                content = remote.content
                parentReceiptEnabled = remote.parentReceiptEnabled
                selectedClassIds.clear()
                selectedClassIds.addAll(remote.targetClassIds.filter { id -> classes.any { it.id == id } })
            }
        }
        if (title.isBlank() && content.isBlank() && draft.isNotBlank()) {
            title = draft.substringBefore("\n", draft).trim()
            content = draft.substringAfter("\n", "").trim()
        }
    }
    LaunchedEffect(sendCommand.status) {
        if (sendCommand.status == WorkflowCommandStatus.Succeeded) {
            confirmed = true
            clearDraft(draftKey)
            onSuccess()
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("发班级通知") },
        text = {
            if (confirmed) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Filled.CheckCircle, contentDescription = "通知发送成功", tint = Green, modifier = Modifier.size(42.dp))
                    Text("通知已提交，家长将在消息中心收到。", color = Navy, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
                }
            } else Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.verticalScroll(rememberScrollState())) {
                Text("接收班级", color = Navy, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold, fontSize = 14.sp)
                classes.forEach { target ->
                    Row(Modifier.fillMaxWidth().clickable(enabled = !command.isSubmitting) {
                        if (target.id in selectedClassIds) selectedClassIds.remove(target.id) else selectedClassIds.add(target.id)
                    }, verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = target.id in selectedClassIds, onCheckedChange = { checked ->
                            if (checked && target.id !in selectedClassIds) selectedClassIds.add(target.id)
                            if (!checked) selectedClassIds.remove(target.id)
                        }, enabled = !command.isSubmitting)
                        Text(target.name, color = Navy)
                    }
                }
                OutlinedTextField(value = title, onValueChange = { title = it; saveDraft(draftKey, (it.trim() + "\n" + content.trim()).trim()); error = null }, label = { Text("通知标题") }, singleLine = true, enabled = !command.isSubmitting, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = content, onValueChange = { content = it; saveDraft(draftKey, (title.trim() + "\n" + it.trim()).trim()); error = null }, label = { Text("通知内容") }, minLines = 4, enabled = !command.isSubmitting, modifier = Modifier.fillMaxWidth())
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Switch(checked = parentReceiptEnabled, onCheckedChange = { parentReceiptEnabled = it }, enabled = !command.isSubmitting)
                    Spacer(Modifier.width(8.dp))
                    Text("需要家长确认回执", color = Navy, fontSize = 13.sp)
                }
                Text("仅发送给当前教师已授权的班级", color = Color.Gray, fontSize = 12.sp)
                if (state.notificationDraftsLoading) Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(7.dp)); Text("正在恢复服务端草稿…", color = Blue, fontSize = 12.sp) }
                state.notificationDraftsError?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
                error?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
                if (draftCommand.status == WorkflowCommandStatus.Failed) Text(draftCommand.message ?: "保存失败，请重试。", color = Color.Red, fontSize = 12.sp)
                if (sendCommand.status == WorkflowCommandStatus.Failed) Text(sendCommand.message ?: "发送失败，请重试。", color = Color.Red, fontSize = 12.sp)
                if (command.isSubmitting) Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(7.dp)); Text("正在处理…", color = Blue, fontSize = 12.sp) }
            }
        },
        confirmButton = {
            TextButton(enabled = !command.isSubmitting, onClick = {
                if (confirmed) onDismiss()
                else if (selectedClassIds.isEmpty()) error = "请选择接收班级。"
                else if (title.trim().length < 2) error = "请填写通知标题。"
                else if (content.trim().length < 4) error = "请填写通知内容。"
                else saveNotificationDraft(notificationId, selectedClassIds.toList(), title.trim(), content.trim(), draftVersion, parentReceiptEnabled, null) { saved ->
                    if (saved != null) {
                        notificationId = saved.notificationId
                        draftVersion = saved.draftVersion
                        sendNotificationDraft(saved.notificationId)
                    }
                }
            }) { if (command.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(if (confirmed) "完成" else if (command.status == WorkflowCommandStatus.Failed) "重新发送" else "发送通知") }
        },
        dismissButton = {
            Row {
                if (notificationId != null) TextButton(enabled = !command.isSubmitting, onClick = { notificationId?.let(discardNotificationDraft); onDismiss() }) { Text("放弃草稿") }
                TextButton(enabled = !command.isSubmitting, onClick = {
                    if (!confirmed) {
                        val value = (title.trim() + "\n" + content.trim()).trim()
                        if (selectedClassIds.isNotEmpty() && title.trim().length >= 2 && content.trim().length >= 4) {
                            saveNotificationDraft(notificationId, selectedClassIds.toList(), title.trim(), content.trim(), draftVersion, parentReceiptEnabled, null) { saved ->
                                notificationId = saved?.notificationId ?: notificationId
                                draftVersion = saved?.draftVersion ?: draftVersion
                            }
                        } else if (value.isNotBlank()) saveDraft(draftKey, value)
                    }
                    onDismiss()
                }) { Text("保存草稿") }
            }
        }
    )
}
