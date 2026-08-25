package com.xiangshang.youth.feature.parent

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.xiangshang.youth.R
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.service.ExpertAvailableSlot
import com.xiangshang.youth.core.service.RemoteActivity
import com.xiangshang.youth.core.service.RemoteExpert
import com.xiangshang.youth.shared.component.*

fun fallbackExperts(): List<RemoteExpert> = listOf(
    RemoteExpert("expert-zhang-child-sports", name = "张教授", title = "儿童运动发展", bio = "儿童运动发展与家庭训练建议", status = "active"),
    RemoteExpert("expert-li-growth-screening", name = "李医生", title = "儿童健康评估", bio = "成长筛查与家庭观察建议", status = "active"),
    RemoteExpert("expert-wang-youth-training", name = "王教练", title = "青少年运动训练", bio = "动作训练和运动习惯建立", status = "active"),
    RemoteExpert("expert-liu-family-support", name = "刘主任", title = "儿童心理成长", bio = "家庭支持与心理观察", status = "active")
)

fun expertAvatarRes(expertId: String): Int = when {
    expertId.contains("li-growth") -> R.drawable.expert_doctor
    expertId.contains("wang") -> R.drawable.expert_coach
    expertId.contains("liu") -> R.drawable.expert_counselor
    else -> R.drawable.expert_professor
}

fun ExpertAvailableSlot.slotLabel(): String {
    fun time(value: String): String = value.substringAfter("T", value).take(5).ifBlank { value.takeLast(8).take(5) }
    return "${time(scheduledStartAt)}-${time(scheduledEndAt)}"
}

@Composable fun ParentHeader(name: String, subtitle: String, onClick: () -> Unit, onMessages: (() -> Unit)? = null, unreadCount: Int = 0, onRefresh: (() -> Unit)? = null, isRefreshing: Boolean = false) = Row(Modifier.fillMaxWidth().background(Color.White).padding(horizontal = 14.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) { Surface(Modifier.size(40.dp), color = Color(0xFF16AFA5), shape = CircleShape) { Text(name.take(1), color = Color.White, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 9.dp)) }; Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text(name, color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp); Text(subtitle, color = Color.Gray, fontSize = 12.sp) }; IconButton(onClick = onClick) { Icon(Icons.Filled.ChevronRight, "切换孩子", tint = Blue) }; onRefresh?.let { action -> IconButton(onClick = action, enabled = !isRefreshing) { if (isRefreshing) CircularProgressIndicator(Modifier.size(17.dp), color = Blue, strokeWidth = 2.dp) else Icon(Icons.Filled.Refresh, "刷新数据", tint = Navy, modifier = Modifier.size(19.dp)) } }; onMessages?.let { action -> IconButton(onClick = action) { BadgedBox(badge = { if (unreadCount > 0) Badge(containerColor = Color.Red, modifier = Modifier.size(6.dp)) {} }) { Icon(Icons.Filled.NotificationsNone, contentDescription = "消息通知", tint = Navy, modifier = Modifier.size(20.dp)) } } } }

@Composable fun ParentMetric(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, modifier: Modifier, onClick: () -> Unit) = Surface(modifier.heightIn(min = 64.dp).semantics { role = Role.Button; contentDescription = "打开${label}测评" }.clickable(onClick = onClick), color = color.copy(.08f), shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = color, modifier = Modifier.size(22.dp)); Spacer(Modifier.width(8.dp)); Column { Text(label, color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp); Text(if (label == "体质") "继续测评" else "开始测评", color = Color.Gray, fontSize = 12.sp) } } }
@Composable private fun ActivityStatusPill(label: String, value: String, color: Color, modifier: Modifier = Modifier) = Surface(modifier, color = color.copy(alpha = .10f), shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(8.dp)) { Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text(label, color = Color.Gray, fontSize = 12.sp) } }
@Composable
fun ActivityListScreen(
    state: AppUiState,
    nav: NavHostController,
    loadActivities: () -> Unit,
    submitActivityCommand: (String, String, String) -> Unit,
    saveDraft: (String, String) -> Unit,
    clearDraft: (String) -> Unit,
    clearWorkflow: (String) -> Unit,
    cancelActivityRegistration: (String) -> Unit,
    initialActivityId: String? = null,
    clearInitialActivity: () -> Unit = {}
) = AppScaffold("成长活动", onBack = { nav.popBackStack() }) {
    var selectedActivity by remember { mutableStateOf<RemoteActivity?>(null) }
    var contactName by rememberSaveable { mutableStateOf("") }
    var contactPhone by rememberSaveable { mutableStateOf("") }
    var consented by rememberSaveable { mutableStateOf(false) }
    var editing by rememberSaveable { mutableStateOf(false) }
    var formError by remember { mutableStateOf<String?>(null) }
    var showHistory by remember { mutableStateOf(false) }
    val selectedChildId = state.selectedChild?.id
    val visibleRegistrationHistory = state.activityRegistrationHistory.filter { it.childId == selectedChildId || it.childId == null }
    LaunchedEffect(Unit) { loadActivities() }
    val displayActivities = if (state.remoteActivities.isNotEmpty()) {
        state.remoteActivities
    } else if (!state.repositoryAcknowledged) {
        listOf(RemoteActivity("health-growth-season-2026", title = "向上少年健康成长季", description = "综合测评 · 运动表现更出彩", capacity = 60, remainingCapacity = 18, registrationEndAt = "2026-09-10"))
    } else {
        emptyList()
    }
    LaunchedEffect(initialActivityId, displayActivities) {
        initialActivityId?.let { id -> displayActivities.firstOrNull { it.activityId == id }?.let { selectedActivity = it; clearInitialActivity() } }
    }

        when {
            state.activitiesLoading -> LoadingState()
            state.repositoryAcknowledged && state.activitiesError != null -> ErrorState(state.activitiesError, retry = loadActivities)
            displayActivities.isEmpty() -> EmptyState("暂无可报名活动，学校发布后会显示在这里。")
        else -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            displayActivities.forEach { activity ->
                val saved = state.local.activityRegistrations.firstOrNull { it.activityId == activity.activityId && (it.childId == selectedChildId || it.childId == null) }
                Surface(
                    modifier = Modifier.fillMaxWidth().semantics {
                        role = Role.Button
                        contentDescription = "查看活动：${activity.title}"
                    }.clickable {
                        selectedActivity = activity
                        val draftKey = "activity-registration-${activity.activityId}-${selectedChildId ?: "none"}"
                        val legacyDraftKey = "activity-registration-${activity.activityId}"
                        val draft = (state.local.drafts[draftKey] ?: state.local.drafts[legacyDraftKey])?.split("|", limit = 3)
                        if (draft != null && draft.size >= 2) {
                            contactName = draft[0]
                            contactPhone = draft[1]
                            consented = draft.getOrNull(2) == "1"
                        } else {
                            contactName = saved?.contactName ?: state.activeDisplayName
                            contactPhone = saved?.phone ?: state.profile?.phone?.takeIf { it.filter(Char::isDigit).length == 11 }.orEmpty()
                            consented = saved != null
                        }
                        editing = saved == null
                        formError = null
                    },
                    color = Color.White,
                    shape = RoundedCornerShape(14.dp),
                    shadowElevation = 1.dp
                ) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(activity.title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                                Text(activity.description ?: "活动安排以学校通知为准。", color = Color.Gray, fontSize = 13.sp, maxLines = 2)
                            }
                            Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray)
                        }
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ActivityStatusPill("剩余名额", activity.remainingCapacity?.let { remaining -> activity.capacity?.let { "$remaining/$it" } ?: "$remaining" } ?: "待发布", Green, Modifier.weight(1f))
                            ActivityStatusPill("截止时间", activity.registrationEndAt?.take(10) ?: "待通知", Blue, Modifier.weight(1f))
                            ActivityStatusPill("报名状态", saved?.registrationStatus?.let(::activityStatusLabel) ?: activity.registrationStatus?.let(::activityStatusLabel) ?: "未报名", Color(0xFFFF9D25), Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
    if (visibleRegistrationHistory.isNotEmpty()) {
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("报名历史", color = Navy, fontWeight = FontWeight.Bold, fontSize = 15.sp, modifier = Modifier.weight(1f))
            TextButton(onClick = { showHistory = true }) { Text("查看全部", fontSize = 13.sp) }
        }
        visibleRegistrationHistory.take(5).forEach { item ->
            Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) {
                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(item.activityTitle ?: item.activityId, color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                        Text(item.updatedAt?.take(16)?.let { "更新时间 · $it" } ?: "报名记录", color = Color.Gray, fontSize = 12.sp)
                    }
                    Text(activityStatusLabel(item.status), color = if (item.status == "cancelled") Color.Red else Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                }
            }
        }
    }

    if (showHistory) {
        AlertDialog(
            onDismissRequest = { showHistory = false },
            title = { Text("报名历史") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    visibleRegistrationHistory.forEach { item ->
                        Surface(Modifier.fillMaxWidth(), color = Color(0xFFF7FAFF), shape = RoundedCornerShape(12.dp)) {
                            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(verticalAlignment = Alignment.Top) {
                                    Column(Modifier.weight(1f)) {
                                        Text(item.activityTitle ?: item.activityId, color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                        Text("报名编号 ${item.registrationId}", color = Color.Gray, fontSize = 12.sp)
                                    }
                                    Text(activityStatusLabel(item.status), color = if (item.status == "cancelled") Color.Red else Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                                }
                                Row(Modifier.fillMaxWidth()) {
                                    Text(item.updatedAt?.take(16)?.let { "更新 $it" } ?: "待学校同步时间", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.weight(1f))
                                    Text("版本 ${item.version}", color = Color.Gray, fontSize = 12.sp)
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showHistory = false }) { Text("关闭") } }
        )
    }

    selectedActivity?.let { activity ->
        val activityId = activity.activityId
        val draftKey = "activity-registration-$activityId-${selectedChildId ?: "none"}"
        val commandState = state.workflowStates["activity:$activityId${selectedChildId?.let { ":$it" } ?: ""}"] ?: WorkflowCommandState()
        val saved = state.local.activityRegistrations.firstOrNull { it.activityId == activityId && (it.childId == selectedChildId || it.childId == null) }
        val activityCancellationKey = saved?.registrationId ?: saved?.id ?: activityId
        val cancelCommandState = state.workflowStates["activity-cancel:$activityCancellationKey${selectedChildId?.let { ":$it" } ?: ""}"] ?: WorkflowCommandState()
        val failed = commandState.status == WorkflowCommandStatus.Failed
        val savedAndStable = saved != null && saved.registrationStatus != "cancelled" && !failed && !commandState.isSubmitting
        LaunchedEffect(cancelCommandState.status) {
            if (cancelCommandState.status == WorkflowCommandStatus.Succeeded) selectedActivity = null
        }
        LaunchedEffect(commandState.status, activityId) {
            if (commandState.status == WorkflowCommandStatus.Succeeded) {
                clearDraft(draftKey)
                editing = false
            }
        }
        AlertDialog(
            onDismissRequest = {
                selectedActivity = null
                editing = false
                formError = null
            },
            title = { Text(activity.title) },
            text = {
                Column {
                    if (cancelCommandState.status == WorkflowCommandStatus.Failed) {
                        Text(cancelCommandState.message ?: "取消报名失败，请重试", color = Color.Red, fontSize = 12.sp)
                    }
                    Text(activity.description ?: "报名信息会提交给学校确认，活动时间以学校通知为准。")
                    Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ActivityStatusPill("剩余名额", activity.remainingCapacity?.let { remaining -> activity.capacity?.let { "$remaining/$it" } ?: "$remaining" } ?: "待发布", Green, Modifier.weight(1f))
                        ActivityStatusPill("报名截止", activity.registrationEndAt?.take(10) ?: "待通知", Blue, Modifier.weight(1f))
                        ActivityStatusPill("学校确认", saved?.registrationStatus?.let(::activityStatusLabel) ?: activity.registrationStatus?.let(::activityStatusLabel) ?: "未报名", Color(0xFFFF9D25), Modifier.weight(1f))
                    }
                    if (savedAndStable && !editing) {
                        Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Green, modifier = Modifier.padding(top = 12.dp))
                        Text(if (state.repositoryAcknowledged) "报名记录已保存，后续状态以学校确认为准。" else "报名信息已保存，联网后自动同步。", color = Green, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
                        Text("${saved?.contactName.orEmpty()} · ${saved?.phone.orEmpty()}", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(onClick = {
                                contactName = saved?.contactName.orEmpty()
                                contactPhone = saved?.phone.orEmpty()
                                consented = true
                                editing = true
                                clearWorkflow("activity:$activityId${selectedChildId?.let { ":$it" } ?: ""}")
                            }) { Text("修改报名") }
                            TextButton(
                                onClick = {
                                    cancelActivityRegistration(activityCancellationKey)
                                    editing = false
                                },
                                colors = ButtonDefaults.textButtonColors(contentColor = Color.Red)
                            ) { Text("取消报名") }
                        }
                    } else {
                        OutlinedTextField(
                            value = contactName,
                            onValueChange = {
                                contactName = it
                                saveDraft(draftKey, "$it|$contactPhone|${if (consented) "1" else "0"}")
                                formError = null
                            },
                            label = { Text("联系人姓名") },
                            modifier = Modifier.fillMaxWidth().padding(top = 10.dp)
                        )
                        OutlinedTextField(
                            value = contactPhone,
                            onValueChange = {
                                contactPhone = it
                                saveDraft(draftKey, "$contactName|$it|${if (consented) "1" else "0"}")
                                formError = null
                            },
                            label = { Text("手机号") },
                            modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                        )
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 6.dp)) {
                            Checkbox(
                                checked = consented,
                                onCheckedChange = {
                                    consented = it
                                    saveDraft(draftKey, "$contactName|$contactPhone|${if (it) "1" else "0"}")
                                    formError = null
                                }
                            )
                            Text("已阅读活动说明并同意接收报名通知", fontSize = 12.sp)
                        }
                        formError?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
                        if (failed) Text(commandState.message ?: "报名提交失败，请重试。", color = Color.Red, fontSize = 12.sp)
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = !commandState.isSubmitting && (!savedAndStable || editing || failed),
                    onClick = {
                        when {
                            contactName.isBlank() -> formError = "请填写联系人姓名。"
                            contactPhone.filter(Char::isDigit).length != 11 -> formError = "请填写 11 位手机号。"
                            !consented -> formError = "请先确认活动说明和通知授权。"
                            else -> submitActivityCommand(contactName.trim(), contactPhone.trim(), activityId)
                        }
                    }
                ) {
                    if (commandState.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    else Text(if (failed) "重新提交" else if (editing) "更新报名" else "确认报名")
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    selectedActivity = null
                    editing = false
                    formError = null
                }) { Text("关闭") }
            }
        )
    }
}

private fun activityStatusLabel(status: String): String = when (status.lowercase()) {
    "confirmed" -> "已确认"
    "pending" -> "待确认"
    "cancelled", "canceled" -> "已取消"
    "rejected" -> "未通过"
    "full" -> "名额已满"
    "closed" -> "已截止"
    else -> status
}

private fun appointmentStatusLabel(status: String): String = when (status.lowercase()) {
    "confirmed" -> "已确认"
    "pending" -> "待确认"
    "reschedule_requested" -> "改期待确认"
    "cancelled", "canceled" -> "已取消"
    "completed" -> "已完成"
    "rejected" -> "未通过"
    else -> status
}

@Composable
fun ExpertListScreen(
    state: AppUiState,
    nav: NavHostController,
    loadExperts: () -> Unit,
    loadExpertSlots: (String) -> Unit,
    submitExpertCommand: (String, String, String, String?, String?, String?, String?, String?) -> Unit,
    rescheduleExpertCommand: (String, String, String, String, String?, String?, String?, String?) -> Unit,
    cancelExpertCommand: (String, String) -> Unit,
    saveDraft: (String, String) -> Unit,
    clearDraft: (String) -> Unit,
    clearWorkflow: (String) -> Unit,
    initialExpertId: String? = null,
    clearInitialExpert: () -> Unit = {}
) = AppScaffold("专家团队", onBack = { nav.popBackStack() }) {
    var selectedExpert by remember { mutableStateOf<RemoteExpert?>(null) }
    var selectedSlot by remember { mutableStateOf<ExpertAvailableSlot?>(null) }
    var preferredDate by rememberSaveable { mutableStateOf("") }
    var note by rememberSaveable { mutableStateOf("") }
    var editing by rememberSaveable { mutableStateOf(false) }
    var formError by remember { mutableStateOf<String?>(null) }
    var showHistory by remember { mutableStateOf(false) }
    val selectedChildId = state.selectedChild?.id
    val visibleAppointmentHistory = state.expertAppointmentHistory.filter { it.childId == selectedChildId || it.childId == null }
    LaunchedEffect(Unit) { loadExperts() }
    val displayExperts = if (state.remoteExperts.isNotEmpty()) {
        state.remoteExperts
    } else if (!state.repositoryAcknowledged) {
        fallbackExperts()
    } else {
        emptyList()
    }
    LaunchedEffect(initialExpertId, displayExperts) {
        initialExpertId?.let { id -> displayExperts.firstOrNull { it.expertId == id }?.let { selectedExpert = it; clearInitialExpert() } }
    }

        when {
            state.expertsLoading -> LoadingState()
            state.repositoryAcknowledged && state.expertsError != null -> ErrorState(state.expertsError, retry = loadExperts)
            displayExperts.isEmpty() -> EmptyState("暂无可预约专家，学校开通后会显示在这里。")
        else -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            displayExperts.forEach { expert ->
                Surface(
                    modifier = Modifier.fillMaxWidth().semantics {
                        role = Role.Button
                        contentDescription = "查看专家：${expert.name}"
                    }.clickable {
                        selectedExpert = expert
                        selectedSlot = null
                        formError = null
                        loadExpertSlots(expert.expertId)
                        val draftKey = "expert-booking-${expert.expertId}-${selectedChildId ?: "none"}"
                        val legacyDraftKey = "expert-booking-${expert.expertId}"
                        val draft = (state.local.drafts[draftKey] ?: state.local.drafts[legacyDraftKey])?.split("|", limit = 2)
                        preferredDate = draft?.getOrNull(0).orEmpty()
                        note = draft?.getOrNull(1).orEmpty()
                        editing = state.local.expertAppointments.none { it.expertId == expert.expertId && (it.childId == selectedChildId || it.childId == null) }
                    },
                    color = Color.White,
                    shape = RoundedCornerShape(14.dp),
                    shadowElevation = 1.dp
                ) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Image(painterResource(expertAvatarRes(expert.expertId)), null, Modifier.size(56.dp).clip(CircleShape), contentScale = ContentScale.Crop)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(expert.name, color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                            Text(expert.title ?: "健康成长专家", color = Blue, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            Text(expert.bio ?: "学校开通后展示专家简介、服务范围和可预约时段。", color = Color.Gray, fontSize = 13.sp, maxLines = 2)
                        }
                        Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray)
                    }
                }
            }
        }
    }
    if (visibleAppointmentHistory.isNotEmpty()) {
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("预约历史", color = Navy, fontWeight = FontWeight.Bold, fontSize = 15.sp, modifier = Modifier.weight(1f))
            TextButton(onClick = { showHistory = true }) { Text("查看全部", fontSize = 13.sp) }
        }
        visibleAppointmentHistory.take(5).forEach { item ->
            Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) {
                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(item.expertName ?: item.expertId ?: "专家预约", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                        Text(item.preferredDate ?: item.scheduledStartAt?.take(16) ?: "预约时间待确认", color = Color.Gray, fontSize = 12.sp)
                    }
                    Text(appointmentStatusLabel(item.status), color = if (item.status == "cancelled") Color.Red else Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                }
            }
        }
    }

    if (showHistory) {
        AlertDialog(
            onDismissRequest = { showHistory = false },
            title = { Text("预约历史") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    visibleAppointmentHistory.forEach { item ->
                        Surface(Modifier.fillMaxWidth(), color = Color(0xFFF7FAFF), shape = RoundedCornerShape(12.dp)) {
                            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(verticalAlignment = Alignment.Top) {
                                    Column(Modifier.weight(1f)) {
                                        Text(item.expertName ?: item.expertId ?: "专家预约", color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                        Text("预约编号 ${item.appointmentId}", color = Color.Gray, fontSize = 12.sp)
                                    }
                                    Text(appointmentStatusLabel(item.status), color = if (item.status == "cancelled") Color.Red else Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                                }
                                Text(item.preferredDate ?: item.scheduledStartAt?.take(16) ?: "预约时间待确认", color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                                Row(Modifier.fillMaxWidth()) {
                                    Text(item.updatedAt?.take(16)?.let { "更新 $it" } ?: "待学校同步时间", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.weight(1f))
                                    Text("版本 ${item.version}", color = Color.Gray, fontSize = 12.sp)
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showHistory = false }) { Text("关闭") } }
        )
    }

    selectedExpert?.let { expert ->
        val expertId = expert.expertId
        val draftKey = "expert-booking-$expertId-${selectedChildId ?: "none"}"
        val slots = state.expertSlots[expertId].orEmpty()
        val slotLabels = if (slots.isNotEmpty()) slots.map { it.slotLabel() } else if (state.repositoryAcknowledged) emptyList() else listOf("09:00-09:30", "10:00-10:30", "14:00-14:30", "16:00-16:30")
        val commandState = state.workflowStates["expert:$expertId${selectedChildId?.let { ":$it" } ?: ""}"] ?: WorkflowCommandState()
        val saved = state.local.expertAppointments.firstOrNull { it.expertId == expertId && (it.childId == selectedChildId || it.childId == null) }
        val expertCancellationKey = saved?.appointmentId ?: saved?.id ?: expertId
        val cancelCommandState = state.workflowStates["expert-cancel:$expertCancellationKey${selectedChildId?.let { ":$it" } ?: ""}"] ?: WorkflowCommandState()
        val failed = commandState.status == WorkflowCommandStatus.Failed
        val savedAndStable = saved != null && saved.appointmentStatus != "cancelled" && !failed && !commandState.isSubmitting
        LaunchedEffect(cancelCommandState.status) {
            if (cancelCommandState.status == WorkflowCommandStatus.Succeeded) selectedExpert = null
        }
        LaunchedEffect(commandState.status, expertId) {
            if (commandState.status == WorkflowCommandStatus.Succeeded) {
                clearDraft(draftKey)
                editing = false
            }
        }
        AlertDialog(
            onDismissRequest = {
                selectedExpert = null
                selectedSlot = null
                editing = false
                formError = null
            },
            title = { Text("${expert.name} · ${expert.title ?: "健康成长专家"}") },
            text = {
                Column {
                    if (cancelCommandState.status == WorkflowCommandStatus.Failed) {
                        Text(cancelCommandState.message ?: "取消预约失败，请重试", color = Color.Red, fontSize = 12.sp)
                    }
                    Text(expert.bio ?: "请选择服务端返回的可预约时段，提交后由学校服务人员跟进确认。")
                    if (savedAndStable && !editing) {
                        Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Green, modifier = Modifier.padding(top = 12.dp))
                        Text(if (state.repositoryAcknowledged) "预约记录已保存，后续状态以学校确认为准。" else "预约已保存，联网后自动同步。", color = Green, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
                        Text(saved?.preferredDate.orEmpty(), color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(onClick = {
                                preferredDate = saved?.preferredDate.orEmpty()
                                note = saved?.note.orEmpty()
                                editing = true
                                clearWorkflow("expert:$expertId${selectedChildId?.let { ":$it" } ?: ""}")
                            }) { Text("修改预约") }
                            TextButton(onClick = {
                                cancelExpertCommand(expertCancellationKey, expert.name)
                            }, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red)) { Text("取消预约") }
                        }
                    //noinspection SuspiciousIndentation
                    } else {
                        Text("可预约时段", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp))
                        if (slotLabels.isEmpty()) {
                            Text(state.expertSlotErrors[expertId] ?: "当前暂无可预约时段", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
                        }
                        slotLabels.chunked(2).forEach { row ->
                            Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                row.forEach { label ->
                                    FilterChip(
                                        selected = preferredDate.contains(label),
                                        onClick = {
                                            selectedSlot = slots.firstOrNull { it.slotLabel() == label }
                                            preferredDate = label
                                            saveDraft(draftKey, "$preferredDate|$note")
                                            formError = null
                                        },
                                        label = { Text(label, fontSize = 12.sp) },
                                        modifier = Modifier.weight(1f).heightIn(min = 44.dp)
                                    )
                                }
                                repeat(2 - row.size) { Spacer(Modifier.weight(1f)) }
                            }
                        }
                        OutlinedTextField(
                            value = note,
                            onValueChange = {
                                note = it
                                saveDraft(draftKey, "$preferredDate|$it")
                                formError = null
                            },
                            label = { Text("咨询说明") },
                            minLines = 2,
                            modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                        )
                        formError?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
                        if (failed) Text(commandState.message ?: "预约提交失败，请重试。", color = Color.Red, fontSize = 12.sp)
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = !commandState.isSubmitting && ((savedAndStable && !editing) || preferredDate.isNotBlank() && note.isNotBlank()),
                    onClick = {
                        if (savedAndStable && !editing) {
                            selectedExpert = null
                            selectedSlot = null
                        } else if (preferredDate.isBlank()) {
                            formError = "请选择可预约时段。"
                        } else if (note.isBlank()) {
                            formError = "请填写咨询说明。"
                        } else {
                            if (editing) rescheduleExpertCommand(expert.name, preferredDate.trim(), note.trim(), expertId, selectedSlot?.serviceId, selectedSlot?.slotId, selectedSlot?.scheduledStartAt, selectedSlot?.scheduledEndAt)
                            else submitExpertCommand(expert.name, preferredDate.trim(), note.trim(), expertId, selectedSlot?.serviceId, selectedSlot?.slotId, selectedSlot?.scheduledStartAt, selectedSlot?.scheduledEndAt)
                        }
                    }
                ) {
                    if (commandState.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    else Text(if (savedAndStable && !editing) "完成" else if (failed) "重新提交" else if (editing) "更新预约" else "提交预约")
                }
            },
            dismissButton = if (savedAndStable && !editing) null else ({
                TextButton(onClick = {
                    selectedExpert = null
                    selectedSlot = null
                    editing = false
                    formError = null
                }) { Text("取消") }
            })
        )
    }
}
