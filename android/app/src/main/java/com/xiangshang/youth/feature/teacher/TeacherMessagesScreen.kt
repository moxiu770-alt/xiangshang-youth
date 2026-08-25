package com.xiangshang.youth.feature.teacher

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
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
import com.xiangshang.youth.app.AppUiState
import com.xiangshang.youth.app.Blue
import com.xiangshang.youth.app.Green
import com.xiangshang.youth.app.LocalDashboardClearError
import com.xiangshang.youth.app.Navy
import com.xiangshang.youth.core.model.MessageItem
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.service.NotificationCampaignDetail
import com.xiangshang.youth.core.util.MessageBusinessRoutePolicy
import com.xiangshang.youth.feature.parent.ClassNoticeDetailDialog
import com.xiangshang.youth.feature.parent.openMessageBusinessRoute
import com.xiangshang.youth.shared.component.*
import java.time.Instant

/** Teacher inbox is a secondary page, never an extra bottom tab. */
@Composable
fun TeacherMessagesScreen(
    state: AppUiState,
    nav: NavHostController,
    markMessageRead: (String) -> Unit,
    markAllMessagesRead: () -> Unit,
    refreshDashboard: () -> Unit = {},
    loadClassNoticeDetail: (String, (NotificationCampaignDetail?) -> Unit) -> Unit = { _, done -> done(null) },
    acknowledgeClassNotice: (String, (Boolean) -> Unit) -> Unit = { _, done -> done(false) }
) = AppScaffold("消息中心", onBack = { nav.popBackStack() }) {
    var selected by remember { mutableStateOf<MessageItem?>(null) }
    when {
        state.error != null && state.data == null -> ErrorState(state.error, retry = refreshDashboard, dismiss = LocalDashboardClearError.current)
        state.loading || state.data == null -> LoadingState()
        state.data.messages.isEmpty() -> EmptyState("暂无消息通知，新的测评和班级通知会显示在这里。")
        else -> {
            if (state.unreadMessageCount > 0) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { TextButton(onClick = markAllMessagesRead, contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp), modifier = Modifier.semantics { contentDescription = "将全部消息标记为已读" }) { Text("全部已读", fontSize = 12.sp) } }
            state.data.messages.forEach { item ->
                val presentation = teacherMessagePresentation(item)
                val unread = !item.isRead && item.id !in state.local.readMessageIds
                Surface(Modifier.fillMaxWidth().padding(vertical = 4.dp).semantics { role = Role.Button; contentDescription = "查看消息：${item.title}" }.clickable { markMessageRead(item.id); if (!openMessageBusinessRoute(item, state, nav, UserRole.Teacher, openClassNoticeTarget = { selected = item })) selected = item }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) { Icon(presentation.first, null, tint = presentation.second); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(item.title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); if (unread) { Spacer(Modifier.width(5.dp)); Box(Modifier.size(5.dp).background(Color.Red, CircleShape)) } }; Text(item.content, color = Color.Gray, fontSize = 12.sp, maxLines = 1) }; Text(item.time, color = Color.Gray, fontSize = 12.sp); Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.size(15.dp)) } }
            }
        }
    }
    selected?.let { item ->
        val noticeId = item.businessId?.takeIf { MessageBusinessRoutePolicy.normalizeRoute(item.businessRoute) == "classnotice" }
        if (noticeId != null) ClassNoticeDetailDialog(item, noticeId, state, loadClassNoticeDetail, acknowledgeClassNotice) { selected = null }
        else AlertDialog(onDismissRequest = { selected = null }, title = { Text(item.title) }, text = { Column { if (item.expiresAt?.let { runCatching { Instant.parse(it) }.getOrNull()?.isBefore(Instant.now()) } == true) Text("该通知已过期，不能继续打开。", color = Color.Gray) else Text(item.content); Text(item.time, color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp)); Text("已读", color = Green, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp)) } }, confirmButton = { TextButton(onClick = { selected = null }) { Text("关闭") } })
    }
}

private fun teacherMessagePresentation(item: MessageItem): Pair<androidx.compose.ui.graphics.vector.ImageVector, Color> = when {
    item.category == "系统" -> Icons.Filled.Settings to Color(0xFF9A60F5)
    item.title.contains("体质") -> Icons.Filled.Warning to Color.Red
    item.title.contains("视力") -> Icons.Filled.Visibility to Green
    item.title.contains("口腔") -> Icons.Filled.MedicalServices to Color(0xFF9A60F5)
    else -> Icons.Filled.Notifications to Blue
}
