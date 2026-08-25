package com.xiangshang.youth.feature.parent

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.model.MessageItem
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.model.BodyAttentionLevel
import com.xiangshang.youth.core.model.bodyAssessmentAgeMonths
import com.xiangshang.youth.core.util.MessageBusinessRoutePolicy
import com.xiangshang.youth.shared.component.*
import java.time.Instant

/** Resolves only business routes that the current mobile session is allowed
 * to open. Unknown, expired or out-of-scope messages stay in the detail view
 * instead of silently navigating to a guessed destination. */
fun openMessageBusinessRoute(
    item: MessageItem,
    state: AppUiState,
    nav: NavHostController,
    role: UserRole,
    openCourseTarget: (childId: String, courseId: String?, lessonId: String?, title: String) -> Unit = { _, _, _, _ -> },
    openActivityTarget: (activityId: String) -> Unit = {},
    openExpertAppointmentTarget: (appointmentId: String) -> Unit = {},
    openClassNoticeTarget: (MessageItem) -> Unit = {}
): Boolean {
    if (MessageBusinessRoutePolicy.isExpired(item.expiresAt)) return false
    val route = MessageBusinessRoutePolicy.normalizeRoute(item.businessRoute)
    return when (route) {
        "report" -> {
            val childId = item.childId ?: return false
            val allowed = role == UserRole.Parent && (childId == state.selectedChild?.id || childId in state.local.boundChildIds)
            if (!allowed) false else { nav.navigate(Destinations.ReportRoute.replace("{studentId}", childId)); true }
        }
        "task", "retest" -> {
            val taskId = item.taskId ?: item.businessId ?: return false
            val task = state.data?.tasks?.firstOrNull { it.id == taskId } ?: return false
            val allowed = when (role) {
                UserRole.Teacher -> state.managedTeacherClasses.any { classInfo -> task.classIds.contains(classInfo.id) } || task.classIds.isEmpty() && state.teacherHasCapability("VIEW_TEST_TASKS")
                UserRole.Parent -> item.childId == state.selectedChild?.id || item.childId in state.local.boundChildIds
                else -> false
            }
            if (!allowed) false else { nav.navigate(Destinations.TaskDetailRoute.replace("{taskId}", task.id)); true }
        }
        "course", "lesson" -> {
            val target = MessageBusinessRoutePolicy.courseTarget(item) ?: return false
            val allowed = role == UserRole.Parent && (target.childId == state.selectedChild?.id || target.childId in state.local.boundChildIds)
            if (!allowed) false else {
                openCourseTarget(target.childId, target.courseId, target.lessonId, target.title)
                nav.navigate(Destinations.Courses)
                true
            }
        }
        "activity" -> item.businessId?.takeIf { role == UserRole.Parent }?.let { openActivityTarget(it); nav.navigate(Destinations.Activities); true } ?: false
        "expertappointment" -> item.businessId?.takeIf { role == UserRole.Parent }?.let { openExpertAppointmentTarget(it); nav.navigate(Destinations.Experts); true } ?: false
        "childbinding" -> if (role == UserRole.Parent) { nav.navigate(Destinations.ChildrenBinding); true } else false
        "classnotice" -> item.businessId?.takeIf { it.isNotBlank() }?.let { openClassNoticeTarget(item); true } ?: false
        else -> false
    }
}

@Composable
fun NotificationsScreen(
    state: AppUiState,
    nav: NavHostController,
    markMessageRead: (String) -> Unit,
    markAllMessagesRead: () -> Unit,
    openCourseTarget: (String, String?, String?, String) -> Unit = { _, _, _, _ -> },
    openActivityTarget: (String) -> Unit = {},
    openExpertAppointmentTarget: (String) -> Unit = {},
    loadClassNoticeDetail: (String, (com.xiangshang.youth.core.service.NotificationCampaignDetail?) -> Unit) -> Unit = { _, done -> done(null) },
    acknowledgeClassNotice: (String, (Boolean) -> Unit) -> Unit = { _, done -> done(false) }
) = AppScaffold("消息通知", onBack = { nav.popBackStack() }) {
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@AppScaffold }
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    if (state.data.messages.isEmpty()) { EmptyState("暂无消息通知"); return@AppScaffold }
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) { Text("全部通知", color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp); Spacer(Modifier.weight(1f)); if (state.unreadMessageCount > 0) TextButton(onClick = markAllMessagesRead, contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp), modifier = Modifier.semantics { contentDescription = "将全部通知标记为已读" }) { Text("全部已读", fontSize = 12.sp) }; Text("未读 ${state.unreadMessageCount}", color = Blue, fontSize = 12.sp) }
    state.data.messages.forEachIndexed { index, item ->
        var detail by remember { mutableStateOf(false) }
        Surface(Modifier.fillMaxWidth().padding(vertical = 4.dp).semantics { role = Role.Button; contentDescription = "查看通知：${item.title}" }.clickable { markMessageRead(item.id); if (!openMessageBusinessRoute(item, state, nav, UserRole.Parent, openCourseTarget, openActivityTarget, openExpertAppointmentTarget, openClassNoticeTarget = { detail = true })) detail = true }, color = Color.White, shape = RoundedCornerShape(11.dp), shadowElevation = 1.dp) {
            Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (item.category == "报告") Icons.Filled.Description else Icons.Filled.Notifications, null, tint = if (index == 0) Blue else Color(0xFFFF9D25), modifier = Modifier.size(25.dp))
                Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(item.title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); if (!item.isRead && item.id !in state.local.readMessageIds) Spacer(Modifier.width(5.dp)); if (!item.isRead && item.id !in state.local.readMessageIds) Box(Modifier.size(5.dp).background(Color.Red, CircleShape)) }; Text(item.content, color = Color.Gray, fontSize = 12.sp, maxLines = 2); Text("${item.category} · ${item.time}", color = Color.Gray, fontSize = 12.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.size(15.dp))
            }
        }
        if (detail) {
            val noticeId = item.businessId?.takeIf { MessageBusinessRoutePolicy.normalizeRoute(item.businessRoute) == "classnotice" }
            if (noticeId != null) {
                ClassNoticeDetailDialog(item, noticeId, state, loadClassNoticeDetail, acknowledgeClassNotice) { detail = false }
            } else {
                AlertDialog(onDismissRequest = { detail = false }, title = { Text(item.title) }, text = { Column { if (item.expiresAt?.let { runCatching { Instant.parse(it) }.getOrNull()?.isBefore(Instant.now()) } == true) Text("该通知已过期，不能继续打开。", color = Color.Gray) else Text(item.content); Text("${item.category} · ${item.time}", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp)) } }, confirmButton = { TextButton(onClick = { detail = false }) { Text("关闭") } })
            }
        }
    }
}

@Composable
fun ParentMessagesScreen(
    state: AppUiState,
    nav: NavHostController,
    markMessageRead: (String) -> Unit,
    markAllMessagesRead: () -> Unit,
    openCourseTarget: (String, String?, String?, String) -> Unit = { _, _, _, _ -> },
    openActivityTarget: (String) -> Unit = {},
    openExpertAppointmentTarget: (String) -> Unit = {}
) {
    var selectedTitle by remember { mutableStateOf<String?>(null) }
    var selectedContent by remember { mutableStateOf("") }
    var selectedTime by remember { mutableStateOf("") }
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }
    AppScaffold("消息中心", onBack = { nav.popBackStack() }) {
        val data = state.data
        val dashboardError = state.error
        if (dashboardError != null && data == null) {
            ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current)
            return@AppScaffold
        }
        if (state.loading || data == null) {
            LoadingState()
            return@AppScaffold
        }
        if (state.unreadMessageCount > 0) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = markAllMessagesRead, contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp), modifier = Modifier.semantics { contentDescription = "将全部消息标记为已读" }) { Text("全部已读", fontSize = 12.sp) }
            }
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 7.dp), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            listOf("消息提醒", "系统通知").forEachIndexed { index, title ->
                FilterChip(selected = selectedTab == index, onClick = { selectedTab = index }, label = { Text(title, fontSize = 12.sp) }, modifier = Modifier.weight(1f))
            }
        }
        val bodyReminder = state.selectedChild?.let { child ->
            state.local.bodyAssessments[child.id]?.let { body ->
                val level = body.level(child.bodyAssessmentAgeMonths, child.gender)
                val title = when (level) {
                    BodyAttentionLevel.Red -> "身体测评需优先关注"
                    BodyAttentionLevel.Yellow -> "身体测评复测提醒"
                    BodyAttentionLevel.Pending -> "请完成身体测评记录"
                    BodyAttentionLevel.Unavailable -> "请完善身体测评资料"
                    BodyAttentionLevel.Green -> "身体测评已完成"
                }
                MessageItem("body-${child.id}-${body.measuredAt}", title, "BMI ${"%.1f".format(body.bmi)} · ${level.label}。建议复测：${body.nextFollowUp}", "刚刚", "健康提醒", false)
            }
        }
        val allMessages = listOfNotNull(bodyReminder) + data.messages
        val visibleMessages = allMessages.filter { message -> if (selectedTab == 0) message.category != "系统" else message.category == "系统" }.ifEmpty { if (selectedTab == 0) allMessages else emptyList() }
        when {
            data.messages.isEmpty() || visibleMessages.isEmpty() -> EmptyState(if (selectedTab == 0) "暂无消息提醒" else "暂无系统通知")
            else -> visibleMessages.forEachIndexed { index, item ->
                Surface(
                    Modifier.fillMaxWidth().padding(vertical = 4.dp).semantics { role = Role.Button; contentDescription = "查看消息：${item.title}" }.clickable {
                        markMessageRead(item.id)
                        if (!openMessageBusinessRoute(item, state, nav, UserRole.Parent, openCourseTarget, openActivityTarget, openExpertAppointmentTarget, openClassNoticeTarget = {
                                selectedTitle = item.title
                                selectedContent = item.content
                                selectedTime = item.time
                            })) {
                            selectedTitle = item.title
                            selectedContent = if (item.expiresAt?.let { runCatching { Instant.parse(it) }.getOrNull()?.isBefore(Instant.now()) } == true) "该通知已过期，不能继续打开。" else messageRouteFallback(item)
                            selectedTime = item.time
                        }
                    },
                    color = Color.White,
                    shape = RoundedCornerShape(10.dp)
                ) {
                    Row(Modifier.padding(11.dp)) {
                        Icon(if (index % 2 == 0) Icons.Filled.Warning else Icons.Filled.Notifications, null, tint = if (index % 2 == 0) Color.Red else Blue)
                        Spacer(Modifier.width(9.dp))
                        Column(Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(item.title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                                if (!item.isRead && item.id !in state.local.readMessageIds) Box(Modifier.size(5.dp).background(Color.Red, CircleShape).padding(start = 4.dp))
                            }
                            Text(item.content, color = Color.Gray, fontSize = 12.sp, maxLines = 1)
                            Text(item.category, color = Blue, fontSize = 12.sp)
                        }
                        Text(item.time, color = Color.Gray, fontSize = 12.sp)
                    }
                }
            }
        }
    }
    selectedTitle?.let { title ->
        AlertDialog(
            onDismissRequest = { selectedTitle = null },
            title = { Text(title) },
            text = { Column { Text(selectedContent); Text(selectedTime, color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp)) } },
            confirmButton = { TextButton(onClick = { selectedTitle = null }) { Text("关闭") } }
        )
    }
}

private fun messageRouteFallback(item: MessageItem): String {
    return when (MessageBusinessRoutePolicy.normalizeRoute(item.businessRoute)) {
        "course", "lesson" -> "该课程通知缺少孩子、课程或课节编号，暂时不能打开指定课程。"
        "report", "task", "retest" -> "当前账号无法打开这条通知关联的孩子、任务或报告。"
        "activity", "expertappointment" -> "该通知缺少可打开的业务编号，暂时只能查看通知内容。"
        "classnotice" -> "该班级通知缺少通知编号，暂时只能查看文字内容。"
        else -> item.content
    }
}

@Composable
fun ClassNoticeDetailDialog(
    item: MessageItem,
    notificationId: String,
    state: AppUiState,
    loadClassNoticeDetail: (String, (com.xiangshang.youth.core.service.NotificationCampaignDetail?) -> Unit) -> Unit,
    acknowledgeClassNotice: (String, (Boolean) -> Unit) -> Unit,
    dismiss: () -> Unit
) {
    var detail by remember(notificationId) { mutableStateOf<com.xiangshang.youth.core.service.NotificationCampaignDetail?>(null) }
    val detailState = state.workflowStates["notice:detail:$notificationId"] ?: WorkflowCommandState()
    val receiptState = state.workflowStates["notice:receipt:$notificationId"] ?: WorkflowCommandState()
    LaunchedEffect(notificationId) { loadClassNoticeDetail(notificationId) { detail = it } }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(detail?.title ?: item.title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                when {
                    detailState.status == WorkflowCommandStatus.Submitting && detail == null -> Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)); Text("正在加载通知详情", fontSize = 14.sp) }
                    detailState.status == WorkflowCommandStatus.Failed && detail == null -> {
                        Text(detailState.message ?: "通知详情加载失败", color = Color(0xFFD64545), fontSize = 14.sp)
                        TextButton(onClick = { loadClassNoticeDetail(notificationId) { detail = it } }) { Text("重试") }
                    }
                    else -> {
                        val notice = detail
                        Text(notice?.content ?: item.content, color = Navy, fontSize = 14.sp)
                        Text(notice?.sentAt?.let { "发送时间 $it" } ?: "${item.category} · ${item.time}", color = Color.Gray, fontSize = 12.sp)
                        if (notice?.parentReceiptEnabled == true) {
                            val acknowledged = notice.userReceiptStatus == "acknowledged"
                            Surface(color = if (acknowledged) Green.copy(.10f) else Blue.copy(.08f), shape = RoundedCornerShape(10.dp)) {
                                Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text(if (acknowledged) "已确认收到" else "需要家长确认", color = if (acknowledged) Green else Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                    if (notice.receiptStats != null && state.role == UserRole.Teacher) Text("已确认 ${notice.receiptStats.acknowledged}/${notice.receiptStats.total}，待确认 ${notice.receiptStats.pending}", color = Blue, fontSize = 12.sp)
                                    if (!acknowledged && state.role == UserRole.Parent) Button(onClick = { acknowledgeClassNotice(notificationId) { if (it) loadClassNoticeDetail(notificationId) { loaded -> detail = loaded } } }, enabled = receiptState.status != WorkflowCommandStatus.Submitting) { Text(if (receiptState.status == WorkflowCommandStatus.Submitting) "提交中" else "确认收到") }
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = dismiss) { Text("关闭") } }
    )
}
