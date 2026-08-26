package com.xiangshang.youth.feature.parent

import android.content.Intent
import android.app.DatePickerDialog
import android.graphics.BitmapFactory
import android.widget.VideoView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.core.net.toUri
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.navigation.NavHostController
import kotlinx.coroutines.delay
import java.util.Calendar
import com.xiangshang.youth.R
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.model.Student
import com.xiangshang.youth.core.model.DiagnosisReport
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.model.BodyAttentionLevel
import com.xiangshang.youth.core.model.bodyAssessmentAgeMonths
import com.xiangshang.youth.core.service.FeatureRollout
import com.xiangshang.youth.core.service.ClassPost
import com.xiangshang.youth.core.service.ClassPostAttachment
import com.xiangshang.youth.core.service.CourseAttachmentStore
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.service.RemoteLesson
import com.xiangshang.youth.core.service.RemoteActivity
import com.xiangshang.youth.core.service.RemoteExpert
import com.xiangshang.youth.core.service.ExpertAvailableSlot
import com.xiangshang.youth.core.util.RoleMessageDestination
import com.xiangshang.youth.core.util.BusinessClock
import com.xiangshang.youth.shared.component.*

private fun postSyncLabel(status: LocalSubmissionStatus): String = when (status) {
    LocalSubmissionStatus.Submitted -> "已同步"
    LocalSubmissionStatus.Failed -> "同步失败，可在设置中重试"
    LocalSubmissionStatus.Submitting -> "正在同步"
    LocalSubmissionStatus.Draft -> "未完成"
    LocalSubmissionStatus.PendingSync -> "已保存，联网后自动同步"
}

private fun supportSyncLabel(status: LocalSubmissionStatus): String = when (status) {
    LocalSubmissionStatus.Submitted -> "已同步"
    LocalSubmissionStatus.Failed -> "同步失败，可在设置中重试"
    LocalSubmissionStatus.Submitting -> "正在同步"
    LocalSubmissionStatus.Draft -> "未完成"
    LocalSubmissionStatus.PendingSync -> "已保存，联网后自动同步"
}

@Composable
fun ParentHomeScreen(state: AppUiState, nav: NavHostController, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, refreshDashboard: () -> Unit = {}, submitExpertCommand: (String, String, String, String?, String?, String?, String?, String?) -> Unit, clearWorkflow: (String) -> Unit = {}, loadActivities: () -> Unit = {}, loadExperts: () -> Unit = {}, loadExpertSlots: (String) -> Unit = {}) {
    val context = LocalContext.current
    var article by remember { mutableStateOf<String?>(null) }
    var wechatError by remember { mutableStateOf(false) }
    var expert by remember { mutableStateOf<RemoteExpert?>(null) }; var expertDate by remember { mutableStateOf("") }; var expertNote by remember { mutableStateOf("") }; var expertSubmitted by remember { mutableStateOf(false) }; var expertEditing by rememberSaveable { mutableStateOf(false) }; var expertSlot by rememberSaveable { mutableStateOf("") }; var selectedSlot by remember { mutableStateOf<ExpertAvailableSlot?>(null) }
    val expertId = expert?.expertId.orEmpty()
    val expertDraftKey = expert?.let { "expert-booking-${it.expertId}-${state.selectedChild?.id ?: "none"}" }
    val legacyExpertDraftKey = expert?.let { "expert-booking-${it.expertId}" }
    val remoteSlots = state.expertSlots[expertId].orEmpty()
    val availableExpertSlots = if (remoteSlots.isNotEmpty()) remoteSlots.map { it.slotLabel() } else if (state.repositoryAcknowledged) emptyList() else listOf("09:00-09:30", "10:00-10:30", "14:00-14:30", "16:00-16:30")
    fun saveExpertDraft() { expertDraftKey?.let { saveDraft(it, "$expertDate|$expertNote") } }
    fun openExpertDatePicker() {
        val calendar = Calendar.getInstance()
        DatePickerDialog(context, { _, year, month, day ->
            val dateText = "${year}年${month + 1}月${day}日"
            expertDate = if (expertSlot.isBlank()) dateText else "$dateText $expertSlot"
            saveExpertDraft()
        }, calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH), calendar.get(Calendar.DAY_OF_MONTH)).show()
    }
    LaunchedEffect(Unit) {
        loadActivities()
        loadExperts()
    }
    LaunchedEffect(expertId) {
        if (expertId.isNotBlank()) loadExpertSlots(expertId)
    }
    LaunchedEffect(expert, state.local.expertAppointments) {
        expertSubmitted = expert?.let { selected ->
            state.local.expertAppointments.any {
                it.expertId == selected.expertId &&
                    (it.childId == state.selectedChild?.id || it.childId == null) &&
                    (it.status == com.xiangshang.youth.core.service.LocalSubmissionStatus.PendingSync ||
                        it.status == com.xiangshang.youth.core.service.LocalSubmissionStatus.Submitted)
            }
        } ?: false
        val draft = expertDraftKey?.let { state.local.drafts[it] ?: legacyExpertDraftKey?.let { key -> state.local.drafts[key] } }
            ?.split("|", limit = 2)
            ?.takeIf { it.size == 2 }
        if (draft != null) {
            expertDate = draft[0]
            expertNote = draft[1]
        } else if (expert != null) {
            state.local.expertAppointments.firstOrNull { it.expertId == expertId && (it.childId == state.selectedChild?.id || it.childId == null) }?.let { saved ->
                expertDate = saved.preferredDate
                expertNote = saved.note
            } ?: run { expertDate = ""; expertNote = "" }
        }
    }
    Scaffold(containerColor = Canvas, bottomBar = { ParentBottomBar(nav, Destinations.Parent) }) { contentPadding ->
    Box(Modifier.padding(contentPadding).fillMaxSize(), contentAlignment = Alignment.TopCenter) {
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = { refreshDashboard() }, dismiss = LocalDashboardClearError.current); return@Scaffold }
    if (state.loading || state.data == null) { LoadingState(); return@Scaffold }
    if (state.selectedChild == null) {
        Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            ParentHeader("请先绑定孩子", "尚未选择孩子", { nav.navigate(Destinations.ChildrenBinding) }, { nav.navigateSingleTop(RoleMessageDestination.resolve(UserRole.Parent)) }, state.unreadMessageCount)
            EmptyState("绑定孩子后才能查看测评、报告和课程。")
            Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("去绑定孩子") }
        }
        return@Scaffold
    }
    val selectedChild = state.selectedChild
    Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight().background(Canvas).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(9.dp)) {
        ParentHeader(selectedChild.name, "${selectedChild.grade} · ${selectedChild.className} · 点击切换孩子", { nav.navigate(Destinations.Children) }, { nav.navigateSingleTop(RoleMessageDestination.resolve(UserRole.Parent)) }, state.unreadMessageCount, refreshDashboard, state.loading)
        Surface(Modifier.padding(horizontal = 12.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
            Column(Modifier.padding(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("孩子本周健康任务", color = Navy, fontWeight = FontWeight.Bold, fontSize = 17.sp); Text("优先完成身体测评，其他家庭记录可稍后填写", color = Color.Gray, fontSize = 12.sp) }; Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, tint = Blue, modifier = Modifier.size(25.dp)) }
                Spacer(Modifier.height(8.dp)); Row { ParentMetric("体质", Icons.AutoMirrored.Filled.DirectionsRun, Blue, Modifier.weight(1f)) { nav.navigate(Destinations.BodyAssessment) }; Spacer(Modifier.width(7.dp)); ParentMetric("心理", Icons.Filled.Favorite, Color(0xFFFF6D9B), Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/mental") } }
                Spacer(Modifier.height(7.dp)); Row { ParentMetric("视力", Icons.Filled.RemoveRedEye, Green, Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/vision") }; Spacer(Modifier.width(7.dp)); ParentMetric("口腔", Icons.Filled.MedicalServices, Color(0xFFFFBD2E), Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/oral") } }
                Button(onClick = { nav.navigate(Destinations.BodyAssessment) }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp).heightIn(min = 48.dp), shape = RoundedCornerShape(12.dp)) { Text("开始身体测评", fontSize = 14.sp, fontWeight = FontWeight.Bold) }
            }
        }
        ParentQuickActions(nav, state.local.checkedInToday)
        ParentSection("成长活动", "查看全部") { nav.navigate(Destinations.Activities) }
        val displayActivities = if (state.remoteActivities.isNotEmpty()) state.remoteActivities else if (!state.repositoryAcknowledged) listOf(RemoteActivity("health-growth-season-2026", title = "向上少年健康成长季", description = "综合测评 · 运动表现更出彩", capacity = 60, remainingCapacity = 18, registrationEndAt = "2026-09-10")) else emptyList()
        val firstActivity = displayActivities.firstOrNull()
        if (state.activitiesLoading) {
            LoadingState()
        } else if (firstActivity == null) {
            EmptyState("暂无可报名活动，学校发布后会显示在这里。")
        } else Surface(Modifier.padding(horizontal = 12.dp).fillMaxWidth().semantics { role = Role.Button; contentDescription = "打开${firstActivity.title}活动报名" }.clickable {
            // The home card is an entry point only. ActivityListScreen owns
            // registration, draft restoration and conflict handling.
            nav.navigate(Destinations.Activities)
        }, color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
            Box(Modifier.height(108.dp)) {
                Image(painterResource(R.drawable.parent_campaign), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                Box(Modifier.fillMaxHeight().fillMaxWidth(.72f).background(Brush.horizontalGradient(listOf(Color.White.copy(.96f), Color.White.copy(.58f), Color.Transparent))))
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(firstActivity.title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                    Text(firstActivity.description ?: "综合测评 · 运动表现更出彩", color = Color.Gray, fontSize = 12.sp, maxLines = 1)
                    val capacity = firstActivity.capacity
                    val remaining = firstActivity.remainingCapacity
                    if (capacity != null && capacity > 0 && remaining != null && remaining in 0..capacity) {
                        val registered = capacity - remaining
                        LinearProgressIndicator({ (registered.toFloat() / capacity.toFloat()).coerceIn(0f, 1f) }, Modifier.width(145.dp).height(5.dp).clip(CircleShape), color = Green, trackColor = Sky)
                        Text("已报名 $registered/$capacity", color = Color.Gray, fontSize = 12.sp)
                    } else if (!state.repositoryAcknowledged) {
                        Text("报名进度以活动详情为准", color = Color.Gray, fontSize = 12.sp)
                    }
                    Text(firstActivity.registrationEndAt?.take(10)?.let { "报名截止 · $it" } ?: if (state.repositoryAcknowledged) "活动时间以学校通知为准" else "2026 秋季测评 · 以学校通知为准", color = Color.Gray, fontSize = 12.sp)
                }
            }
        }
        ParentSection("专家团队", "查看全部") { nav.navigate(Destinations.Experts) }
        val displayExperts = if (state.remoteExperts.isNotEmpty()) state.remoteExperts else if (!state.repositoryAcknowledged) fallbackExperts() else emptyList()
        if (state.expertsLoading) {
            LoadingState()
        } else if (displayExperts.isEmpty()) {
            EmptyState("暂无可预约专家，学校开通后会显示在这里。")
        } else {
            Row(Modifier.padding(horizontal = 14.dp)) { displayExperts.take(4).forEach { item -> Column(Modifier.weight(1f).heightIn(min = 64.dp).semantics { role = Role.Button; contentDescription = "预约${item.name}" }.clickable { expert = item; expertSlot = ""; selectedSlot = null; expertDate = ""; expertNote = "" }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) { Image(painterResource(expertAvatarRes(item.expertId)), null, Modifier.size(40.dp).clip(CircleShape), contentScale = ContentScale.Crop); Text(item.name, color = Navy, fontSize = 12.sp) } } }
        }
        ParentSection("健康科普", "点击文章查看")
        if (state.repositoryAcknowledged) {
            EmptyState("暂无健康科普内容，学校或平台发布后会显示在这里。")
        } else {
            listOf("儿童科学长高的 5 个关键习惯", "居家体态训练 10 分钟").forEach { title -> Surface(Modifier.padding(horizontal = 12.dp, vertical = 3.dp).fillMaxWidth().heightIn(min = 64.dp).semantics { role = Role.Button; contentDescription = "阅读健康科普：$title" }.clickable { wechatError = false; article = title }, color = Color.White, shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.AutoMirrored.Filled.MenuBook, null, tint = Green); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text(title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp); Text("健康专栏 · 今日推荐", color = Color.Gray, fontSize = 12.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } } }
        }
    } } }
    expert?.let { selectedExpert -> val expertCommandKey = "expert:${selectedExpert.expertId}${state.selectedChild?.id?.let { ":$it" } ?: ""}"; val expertCommand = state.workflowStates[expertCommandKey] ?: WorkflowCommandState(); val expertFailed = expertCommand.status == WorkflowCommandStatus.Failed; val expertSaved = expertSubmitted && !expertFailed && !expertCommand.isSubmitting; LaunchedEffect(expertCommand.status) { if (expertCommand.status == WorkflowCommandStatus.Succeeded) { expertDraftKey?.let(clearDraft); expertEditing = false } }; AlertDialog(onDismissRequest = { expert = null; expertSubmitted = false; expertEditing = false }, title = { Text("${selectedExpert.name} · ${selectedExpert.title ?: "健康成长专家"}") }, text = { if (expertSaved && !expertEditing) Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Green, modifier = Modifier.size(42.dp)); Text(if (state.repositoryAcknowledged) "预约已确认。" else "预约已保存，联网后自动同步。", color = Navy, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp)); Text(expertDate, color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp)); TextButton(onClick = { expertEditing = true; clearWorkflow(expertCommandKey) }) { Text("修改预约信息") } } else Column { Text(selectedExpert.bio ?: "请选择服务端可预约时段，提交后会安排跟进。"); OutlinedButton(onClick = { openExpertDatePicker() }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) { Icon(Icons.Filled.CalendarMonth, null); Spacer(Modifier.width(6.dp)); Text(if (expertDate.isBlank()) "选择预约日期" else expertDate.substringBefore(" ")) }; Text("可预约时段", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp)); if (availableExpertSlots.isEmpty()) Text(state.expertSlotErrors[selectedExpert.expertId] ?: "当前暂无可预约时段", color = Color.Gray, fontSize = 12.sp); availableExpertSlots.chunked(2).forEach { row -> Row(Modifier.fillMaxWidth().padding(top = 5.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { slot -> FilterChip(selected = expertDate.contains(slot), onClick = { expertSlot = slot; selectedSlot = remoteSlots.firstOrNull { it.slotLabel() == slot }; val baseDate = expertDate.substringBefore(" ").ifBlank { "" }; expertDate = if (baseDate.isBlank()) slot else "$baseDate $slot"; saveExpertDraft() }, label = { Text(slot, fontSize = 12.sp) }, modifier = Modifier.weight(1f).heightIn(min = 44.dp)) }; repeat(2 - row.size) { Spacer(Modifier.weight(1f)) } } }; OutlinedTextField(value = expertNote, onValueChange = { value -> expertNote = value; saveExpertDraft() }, label = { Text("咨询说明") }, minLines = 2, modifier = Modifier.fillMaxWidth().padding(top = 7.dp)); if (expertFailed) Text(expertCommand.message ?: "预约提交失败，请重试", color = Color.Red, fontSize = 12.sp) } }, confirmButton = { TextButton(enabled = !expertCommand.isSubmitting && ((expertSaved && !expertEditing) || (expertDate.isNotBlank() && expertNote.isNotBlank())), onClick = { if (expertSaved && !expertEditing) { expert = null; expertSubmitted = false } else submitExpertCommand(selectedExpert.name, expertDate.trim(), expertNote.trim(), selectedExpert.expertId, selectedSlot?.serviceId, selectedSlot?.slotId, selectedSlot?.scheduledStartAt, selectedSlot?.scheduledEndAt) }) { if (expertCommand.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(if (expertSaved && !expertEditing) "完成" else if (expertEditing) "更新预约" else if (expertFailed) "重新提交" else "提交预约") } }, dismissButton = if (expertSaved && !expertEditing) null else ({ TextButton(onClick = { expert = null; expertEditing = false }) { Text("取消") } })) }
    article?.let { title -> AlertDialog(onDismissRequest = { article = null }, title = { Text(title) }, text = { Column { Text("完整内容由“向上少年健康成长”微信公众号提供。请在微信中搜索公众号查看。"); if (wechatError) Text("当前设备未安装微信，请直接搜索公众号：向上少年健康成长。", color = Color(0xFFD32F2F), fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp)) } }, confirmButton = { TextButton(onClick = { val opened = runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, "weixin://".toUri())) }.isSuccess; if (opened) article = null else wechatError = true }) { Text(if (wechatError) "重试打开微信" else "打开微信") } }, dismissButton = { TextButton(onClick = { article = null }) { Text("关闭") } }) }
}

@Composable private fun ParentAction(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, modifier: Modifier, onClick: () -> Unit) = Column(modifier.semantics { role = Role.Button; contentDescription = label }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) { FilledIconButton(onClick = onClick, modifier = Modifier.size(44.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = color)) { Icon(icon, contentDescription = label, modifier = Modifier.size(21.dp)) }; Text(label, color = Navy, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, textAlign = TextAlign.Center) }

/** Keep the reference's compact four-up row at normal type size, but give
 * labels enough width at accessibility sizes instead of truncating them. */
@Composable private fun ParentQuickActions(nav: NavHostController, checkedInToday: Boolean) {
    val actions = listOf(
        Triple("测评报告", Icons.AutoMirrored.Filled.Assignment, Blue) to Destinations.Report,
        Triple("健康提醒", Icons.Filled.Warning, Color.Red) to Destinations.Messages,
        Triple(if (checkedInToday) "今日已打卡" else "打卡记录", Icons.AutoMirrored.Filled.FactCheck, Green) to Destinations.Health,
        Triple("推荐课程", Icons.Filled.SmartDisplay, Color(0xFFFF9D25)) to Destinations.Courses
    )
    val columns = if (LocalDensity.current.fontScale > 1.25f) 2 else 4
    Column(Modifier.padding(horizontal = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        actions.chunked(columns).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                row.forEach { (item, destination) ->
                    ParentAction(item.first, item.second, item.third, Modifier.weight(1f)) { nav.navigate(destination) }
                }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}
@Composable
private fun ParentSection(title: String, action: String, onAction: (() -> Unit)? = null) =
    Row(Modifier.padding(horizontal = 12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp)
        Spacer(Modifier.weight(1f))
        if (onAction == null) {
            Text(action, color = Color.Gray, fontSize = 12.sp)
        } else {
            TextButton(onClick = onAction, contentPadding = PaddingValues(horizontal = 2.dp, vertical = 0.dp)) {
                Text("$action ›", fontSize = 12.sp)
            }
        }
    }

@Composable
fun ChildrenScreen(state: AppUiState, nav: NavHostController, bindChild: (String, String) -> Boolean, choose: (Student) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, clearWorkflow: (String) -> Unit = {}, onBound: () -> Unit = {}) = AppScaffold("孩子管理", onBack = { nav.popBackStack() }) {
    var bindingOpen by rememberSaveable { mutableStateOf(false) }
    var childName by rememberSaveable { mutableStateOf(state.local.drafts["child-binding-name"].orEmpty()) }
    var bindingCode by rememberSaveable { mutableStateOf(state.local.drafts["child-binding-code"].orEmpty()) }
    var bindingError by remember { mutableStateOf<String?>(null) }
    var bindingHelpOpen by rememberSaveable { mutableStateOf(false) }
    val bindingState = state.workflowStates["child-binding"] ?: WorkflowCommandState()
    val data = state.data
    val boundIds = state.local.boundChildIds
    val children = data?.students?.filter { it.id in boundIds }.orEmpty()
    when {
        state.error != null && state.data == null -> ErrorState(state.error, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current)
        state.loading || state.data == null -> LoadingState()
        else -> {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) { Text("已绑定孩子 ${children.size} 人", color = Navy, fontWeight = FontWeight.Bold); Spacer(Modifier.weight(1f)); Button(onClick = { bindingOpen = true }) { Text("绑定孩子", fontSize = 12.sp) } }
            if (children.isEmpty()) {
                EmptyState("暂无绑定孩子，请使用学校提供的绑定码添加孩子。")
            } else {
                children.forEach { child -> StudentCard(child) { choose(child) }; Spacer(Modifier.height(8.dp)) }
            }
        }
    }
    LaunchedEffect(bindingState.status, bindingOpen) {
        if (bindingOpen && bindingState.status == WorkflowCommandStatus.Succeeded) {
            childName = ""; bindingCode = ""
            clearDraft("child-binding-name"); clearDraft("child-binding-code")
            bindingError = null; bindingOpen = false; clearWorkflow("child-binding")
            onBound()
        } else if (bindingOpen && bindingState.status == WorkflowCommandStatus.Failed) {
            bindingError = bindingState.message ?: "绑定失败，请核对信息后重试。"
        }
    }
    if (bindingOpen) AlertDialog(
            onDismissRequest = { bindingOpen = false; clearWorkflow("child-binding") },
        title = { Text("绑定孩子") },
        text = { Column { OutlinedTextField(value = childName, onValueChange = { childName = it; saveDraft("child-binding-name", it); bindingError = null }, label = { Text("孩子姓名") }, modifier = Modifier.fillMaxWidth()); OutlinedTextField(value = bindingCode, onValueChange = { bindingCode = it; saveDraft("child-binding-code", it); bindingError = null }, label = { Text("学校绑定码") }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)); Text("绑定码由学校或班主任提供，用于确认家庭与孩子关系。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 7.dp)); TextButton(onClick = { bindingHelpOpen = true }, contentPadding = PaddingValues(horizontal = 0.dp, vertical = 0.dp), modifier = Modifier.semantics { contentDescription = "查看绑定码获取说明" }) { Text("绑定码在哪找？", color = Blue, fontSize = 12.sp) }; bindingError?.let { Text(it, color = Color.Red, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp)) } } },
        confirmButton = { TextButton(
            enabled = !bindingState.isSubmitting,
            onClick = {
                if (state.repositoryAcknowledged) {
                    if (childName.isBlank() || bindingCode.isBlank()) bindingError = "请填写孩子姓名和学校绑定码。"
                    else bindChild(childName, bindingCode)
                } else if (bindChild(childName, bindingCode)) {
                    childName = ""; bindingCode = ""
                    clearDraft("child-binding-name"); clearDraft("child-binding-code")
                    bindingError = null; bindingOpen = false; onBound()
                } else bindingError = "姓名或绑定码不匹配，请核对后重试。"
            }
        ) {
            if (bindingState.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            Spacer(Modifier.width(4.dp)); Text(if (bindingState.isSubmitting) "正在绑定…" else "确认绑定")
        } },
        dismissButton = { TextButton(onClick = { bindingOpen = false; clearWorkflow("child-binding") }) { Text("取消") } }
    )
    if (bindingHelpOpen) AlertDialog(
        onDismissRequest = { bindingHelpOpen = false },
        title = { Text("绑定码获取说明") },
        text = { Text("绑定码由学校后台生成。请联系班主任或学校管理员，在“家长绑定管理/学生档案”中获取孩子专属绑定码。若学校尚未发放，请先向班主任申请；平台不会代填或生成绑定码。", color = Color.Gray, fontSize = 12.sp) },
        confirmButton = { TextButton(onClick = { bindingHelpOpen = false }) { Text("知道了") } }
    )
}
@Composable
fun ParentEvaluationsScreen(state: AppUiState, nav: NavHostController, report: DiagnosisReport?) = ParentTabScaffold(nav, Destinations.ParentEvaluations) {
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@ParentTabScaffold }
    if (state.loading || state.data == null) { LoadingState(); return@ParentTabScaffold }
    if (state.selectedChild == null) { EmptyState("暂无孩子档案，请先完成孩子绑定。"); Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }, modifier = Modifier.align(Alignment.CenterHorizontally)) { Text("去绑定孩子") }; return@ParentTabScaffold }
    val selectedChild = state.selectedChild
    val bodyHistory = state.local.bodyAssessmentHistory[selectedChild.id].orEmpty().takeLast(5)
    val measuredHeights = bodyHistory.map { it.heightCm }
    val latestHeight = measuredHeights.lastOrNull()
    val geneticReference = bodyHistory.lastOrNull()?.geneticHeightReference(selectedChild.gender)
    val heightDevelopment = bodyHistory.lastOrNull()?.heightDevelopmentAssessment(selectedChild.bodyAssessmentAgeMonths, selectedChild.gender)
    ParentHeader(selectedChild.name, "${selectedChild.grade} · ${selectedChild.className} · 成长小档案", onClick = { nav.navigate(Destinations.Children) })
    Spacer(Modifier.height(8.dp))
    val publishedReport = report?.takeIf { state.hasPublishedSchoolReport(selectedChild) }
    val reportAwaitingSync = state.hasPublishedSchoolReport(selectedChild) && publishedReport == null && state.repositoryAcknowledged
    Surface(Modifier.fillMaxWidth(), color = Sky, shape = RoundedCornerShape(12.dp)) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            val progress = (publishedReport?.scoreCompletionRatio ?: 0.0).toFloat().coerceIn(0f, 1f)
            Box(Modifier.size(76.dp).semantics { contentDescription = "学校运动能力测评进度 ${(progress * 100).toInt()}%" }, contentAlignment = Alignment.Center) {
                CircularProgressIndicator({ progress }, Modifier.fillMaxSize(), color = Blue, trackColor = Blue.copy(alpha = .14f), strokeWidth = 7.dp)
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text("${(progress * 100).toInt()}%", color = Blue, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    Text("7 项", color = Color.Gray, fontSize = 12.sp)
                }
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text("学校运动能力测评", color = Navy, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                Surface(color = Blue.copy(alpha = .10f), shape = CircleShape) { Text(publishedReport?.let { if (it.isComplete) it.riskLevel.label else "待完成" } ?: if (reportAwaitingSync) "报告更新中" else "等待报告", color = Blue, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)) }
                LinearProgressIndicator({ progress }, Modifier.fillMaxWidth().height(7.dp).clip(CircleShape), color = Green, trackColor = Blue.copy(alpha = .10f))
                Text(publishedReport?.let { if (it.isComplete) "已完成 7 项 · 总分 ${String.format(java.util.Locale.US, "%.1f", it.totalScore)} / 35" else "已完成 ${it.scoredItemCount} 项 · 进度 ${(progress * 100).toInt()}%" } ?: if (reportAwaitingSync) "报告正在更新，点击刷新" else "完成学校体测后生成报告", color = Color.Gray, fontSize = 12.sp)
            }
        }
    }
    Spacer(Modifier.height(10.dp))
    ParentSection("学校运动体测", if (publishedReport != null) "查看 7 项报告" else if (reportAwaitingSync) "获取报告" else "等待报告") { nav.navigate(Destinations.Report) }
    Row {
        ScoreSummaryCard("7 项体测", publishedReport?.let { if (it.isComplete) it.riskLevel.label else "待完成" } ?: if (reportAwaitingSync) "报告更新中" else "等待报告", publishedReport?.date ?: if (reportAwaitingSync) "报告更新中" else "等待报告") { nav.navigate(Destinations.Report) }
        Spacer(Modifier.width(7.dp))
        ScoreSummaryCard("总分", publishedReport?.let { if (it.isComplete) String.format(java.util.Locale.US, "%.1f / 35", it.totalScore) else "待完成 ${it.scoredItemCount}/7 项" } ?: if (reportAwaitingSync) "报告更新中" else "等待报告", if (publishedReport == null) { if (reportAwaitingSync) "报告更新中" else "完成测评后生成" } else "本轮学校体测") { nav.navigate(Destinations.Report) }
    }
    Spacer(Modifier.height(10.dp))
    Text("体质成长档案", color = Navy, fontWeight = FontWeight.Bold)
    Text(latestHeight?.let { "最新实测 ${"%.1f".format(it)} cm" } ?: "等待身体测评实测", color = Color.Gray, fontSize = 12.sp)
    Surface(Modifier.fillMaxWidth().padding(top = 6.dp), color = Color.White, shape = RoundedCornerShape(10.dp)) {
        Column(Modifier.padding(11.dp)) {
            Text("身高实测趋势", color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            if (measuredHeights.isEmpty()) {
                Text("暂无实测趋势，完成身体测评后开始积累。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.height(72.dp).padding(top = 18.dp))
            } else Row(Modifier.fillMaxWidth().height(72.dp).padding(top = 8.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                val minHeight = measuredHeights.minOrNull() ?: 0.0
                val range = ((measuredHeights.maxOrNull() ?: minHeight) - minHeight).coerceAtLeast(1.0)
                measuredHeights.forEachIndexed { index, height ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.width(22.dp).height((20 + (height - minHeight) / range * 36).dp).background(if (index == measuredHeights.lastIndex) Blue else Blue.copy(.32f), RoundedCornerShape(4.dp)))
                        Text("%.0f".format(height), color = Color.Gray, fontSize = 12.sp)
                    }
                }
            }
            Text(geneticReference?.let { val range = bodyHistory.lastOrNull()?.geneticHeightRange(selectedChild.gender); "遗传靶身高中位：${"%.1f".format(it)} cm · 区间 ${"%.1f".format(range?.start)}–${"%.1f".format(range?.endInclusive)} cm" } ?: "补充父母身高后显示遗传靶身高区间", color = Color.Gray, fontSize = 12.sp)
            Text(heightDevelopment?.let { "当前身高发育：${it.level.label} · ${it.ageYears}岁参考中位 ${"%.1f".format(it.median)} cm" } ?: "7–18 岁身高发育等级将在生日与实测值完整后显示", color = Color.Gray, fontSize = 12.sp)
        }
    }
    Spacer(Modifier.height(10.dp))
    Text("家庭健康记录", color = Navy, fontWeight = FontWeight.Bold)
    Text("家长填写", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 2.dp))
    listOf("vision" to "视力" to "用眼习惯与家庭观察", "oral" to "口腔" to "口腔习惯与家庭观察", "mental" to "心理" to "情绪与同伴互动感受").forEach { (pair, detail) ->
        val (category, name) = pair
        val saved = "${selectedChild.id}-$category" in state.local.completedAssessments
        Surface(Modifier.fillMaxWidth().padding(top = 6.dp).semantics { role = Role.Button; contentDescription = if (saved) "查看${name}家庭健康记录" else "填写${name}家庭健康记录" }.clickable { nav.navigate("${Destinations.Assessment}/$category") }, color = Color.White, shape = RoundedCornerShape(9.dp)) {
            Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (name == "视力") Icons.Filled.RemoveRedEye else if (name == "口腔") Icons.Filled.MedicalServices else Icons.Filled.Favorite, null, tint = if (name == "视力") Green else if (name == "口腔") Color(0xFFFFBD2E) else Color(0xFFFF6D9B))
                Spacer(Modifier.width(9.dp))
                Column(Modifier.weight(1f)) { Text(name, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text(detail, color = Color.Gray, fontSize = 12.sp) }
                Text(if (saved) "已保存 ›" else "去填写 ›", color = if (name == "视力") Green else if (name == "口腔") Color(0xFFFF9D25) else Color(0xFFFF6D9B), fontSize = 12.sp)
            }
        }
    }
}
@Composable
fun HealthProfileScreen(state: AppUiState, nav: NavHostController, checkInToday: (String, Int, String, String?, Boolean, String?) -> Unit, reportForStudent: (Student) -> DiagnosisReport?) {
    var checkInDetail by rememberSaveable { mutableStateOf(false) }
    var checkInForm by rememberSaveable { mutableStateOf(false) }
    var activityType by rememberSaveable { mutableStateOf("") }
    var durationText by rememberSaveable { mutableStateOf("20") }
    var intensity by rememberSaveable { mutableStateOf("moderate") }
    var feeling by rememberSaveable { mutableStateOf("") }
    var completedRecommended by rememberSaveable { mutableStateOf(false) }
    var parentNote by rememberSaveable { mutableStateOf("") }
    var checkInError by rememberSaveable { mutableStateOf<String?>(null) }
    var growthReportOpen by rememberSaveable { mutableStateOf(false) }
    val rolloutRevision by FeatureRollout.revision.collectAsState()
    val selectedChildForCheckIn = state.selectedChild
    val dialogCheckInDates = remember(state.local.healthCheckins, selectedChildForCheckIn?.id) {
        selectedChildForCheckIn?.let { child -> state.local.healthCheckins.filter { it.childId == child.id }.map { it.checkInDate }.toSet() }.orEmpty()
    }
    val checkedInTodayForDialog = BusinessClock.day() in dialogCheckInDates
    ParentTabScaffold(nav, Destinations.Health) {
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@ParentTabScaffold }
    if (state.loading || state.data == null) { LoadingState(); return@ParentTabScaffold }
    val selectedChild = state.selectedChild
    if (selectedChild == null) { EmptyState("暂无健康档案，请先完成孩子绑定。"); Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }, modifier = Modifier.align(Alignment.CenterHorizontally)) { Text("去绑定孩子") }; return@ParentTabScaffold }
    val selectedChildCheckInDates = remember(state.local.healthCheckins, selectedChild.id) { state.local.healthCheckins.filter { it.childId == selectedChild.id }.map { it.checkInDate }.toSet() }
    val checkedInTodayForChild = BusinessClock.day() in selectedChildCheckInDates
    val schoolReportPublished = state.hasPublishedSchoolReport(selectedChild)
    val schoolReport = if (schoolReportPublished) reportForStudent(selectedChild) else null
    val reportAwaitingSync = schoolReportPublished && schoolReport == null && state.repositoryAcknowledged
    ParentSection("学校运动体测报告", if (schoolReport != null) "查看 7 项报告" else if (reportAwaitingSync) "获取报告" else "等待报告") { nav.navigate(Destinations.Report) }
    Row { ScoreSummaryCard("7 项体测", schoolReport?.let { if (it.totalScore >= 25) "良好" else "需关注" } ?: if (reportAwaitingSync) "报告更新中" else "等待报告", schoolReport?.date ?: if (reportAwaitingSync) "报告更新中" else "等待报告", onClick = { nav.navigate(Destinations.Report) }); Spacer(Modifier.width(6.dp)); ScoreSummaryCard("总分", schoolReport?.let { String.format(java.util.Locale.US, "%.1f / 35", it.totalScore) } ?: if (reportAwaitingSync) "报告更新中" else "等待报告", if (schoolReport == null) { if (reportAwaitingSync) "报告更新中" else "完成测评后生成" } else "本轮学校体测", onClick = { nav.navigate(Destinations.Report) }) }
    Spacer(Modifier.height(9.dp))
    if (rolloutRevision >= 0 && FeatureRollout.isEnabled(FeatureRollout.Feature.GrowthInsights)) Surface(onClick = { growthReportOpen = true }, modifier = Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.AutoGraph, "成长周报与月报", tint = Blue); Spacer(Modifier.width(9.dp))
            Column(Modifier.weight(1f)) { Text("成长周报与月报", color = Navy, fontWeight = FontWeight.Bold); Text("汇总真实打卡与测评记录，并说明计划调整原因", color = Color.Gray, fontSize = 12.sp) }
            Icon(Icons.Filled.ChevronRight, null, tint = Blue)
        }
    }
    state.selectedChild.let { child -> state.local.bodyAssessments[child.id]?.let { body -> Spacer(Modifier.height(9.dp)); Surface(onClick = { nav.navigate(Destinations.BodyAssessment) }, modifier = Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.AccessibilityNew, null, tint = Green); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text("身体测评", color = Navy, fontWeight = FontWeight.Bold); Text("BMI ${"%.1f".format(body.bmi)} · ${body.level(child.bodyAssessmentAgeMonths, child.gender).label} · 建议复测 ${body.nextFollowUp}", color = Color.Gray, fontSize = 12.sp, maxLines = 2) }; Icon(Icons.Filled.ChevronRight, null, tint = Blue) } } } ?: run { Spacer(Modifier.height(9.dp)); OutlinedButton(onClick = { nav.navigate(Destinations.BodyAssessment) }, modifier = Modifier.fillMaxWidth()) { Text("完成身体测评：BMI 与姿态观察") } } }
    val archivedCategories = listOf("vision" to "视力", "oral" to "口腔", "mental" to "心理").filter { (key, _) -> state.local.familyHealthRecords.containsKey("${state.selectedChild.id}-$key") }
    if (archivedCategories.isNotEmpty()) {
        Spacer(Modifier.height(9.dp))
        Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) {
            Column(Modifier.padding(12.dp)) {
                Text("家庭健康记录", color = Navy, fontWeight = FontWeight.Bold)
                archivedCategories.forEach { (key, label) ->
                    Row(
                        Modifier.fillMaxWidth().padding(top = 10.dp)
                            .semantics { role = Role.Button; contentDescription = "查看${label}家庭记录" }
                            .clickable { nav.navigate("${Destinations.Assessment}/$key") },
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(if (key == "vision") Icons.Filled.RemoveRedEye else if (key == "oral") Icons.Filled.MedicalServices else Icons.Filled.Favorite, null, tint = if (key == "vision") Green else if (key == "oral") Color(0xFFFFBD2E) else Color(0xFFFF6D9B))
                        Spacer(Modifier.width(9.dp))
                        Column(Modifier.weight(1f)) { Text("${label}家庭记录已保存", color = Navy, fontSize = 12.sp, fontWeight = FontWeight.SemiBold); Text("家长填写 · ${state.local.familyHealthRecords["${state.selectedChild.id}-$key"]?.completedAt ?: "历史记录"}", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 2.dp)) }
                        Text("查看", color = Blue, fontSize = 12.sp)
                        Icon(Icons.Filled.ChevronRight, null, tint = Blue, modifier = Modifier.size(15.dp))
                    }
                }
            }
        }
    }
    Spacer(Modifier.height(9.dp))
    val calendar = java.util.Calendar.getInstance(BusinessClock.timeZone)
    val monthStart = (calendar.clone() as java.util.Calendar).apply { set(java.util.Calendar.DAY_OF_MONTH, 1) }
    val monthCells: List<Int?> = List(monthStart.get(java.util.Calendar.DAY_OF_WEEK) - 1) { null } + (1..monthStart.getActualMaximum(java.util.Calendar.DAY_OF_MONTH)).map { it }
    Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(11.dp)) {
        Column(Modifier.padding(11.dp)) {
            // Keep the calendar header actionable; a static label here made
            // the Android health page diverge from the iOS interaction model.
            ParentSection("本月打卡", "查看记录") { checkInDetail = true }
            Text(BusinessClock.format("yyyy年M月", monthStart.time), color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
            Row(Modifier.fillMaxWidth()) { listOf("日", "一", "二", "三", "四", "五", "六").forEach { Text(it, color = Color.Gray, fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.weight(1f)) } }
            monthCells.chunked(7).forEach { week -> Row(Modifier.fillMaxWidth().padding(top = 3.dp)) { week.forEach { day -> Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { if (day != null) { val date = (monthStart.clone() as java.util.Calendar).apply { set(java.util.Calendar.DAY_OF_MONTH, day) }; val key = BusinessClock.day(date.time); Text("$day", color = if (key in selectedChildCheckInDates) Green else Navy, fontSize = 12.sp, fontWeight = if (key in selectedChildCheckInDates) FontWeight.Bold else FontWeight.Normal, modifier = if (key in selectedChildCheckInDates) Modifier.background(Green.copy(alpha = .12f), CircleShape).padding(horizontal = 5.dp, vertical = 2.dp) else Modifier.padding(vertical = 2.dp)) } } } } }
            Button(onClick = { checkInForm = true; checkInError = null }, enabled = !checkedInTodayForChild, modifier = Modifier.fillMaxWidth().padding(top = 9.dp)) { Text(if (checkedInTodayForChild) "今日已打卡" else "记录今日运动") }
        }
    }
    Spacer(Modifier.height(9.dp))
    ParentActivities(nav)
    }
    if (checkInDetail) {
        AlertDialog(
            onDismissRequest = { checkInDetail = false },
            title = { Text("本月运动打卡记录") },
            text = { val prefix = BusinessClock.format("yyyy-MM"); val count = dialogCheckInDates.count { it.startsWith(prefix) }; Column { Text(if (checkedInTodayForDialog) "本月已完成 $count 次运动打卡，今天已打卡。" else "本月已完成 $count 次运动打卡，今天还可以继续记录。", color = Color.Gray); Text("打卡记录会自动保存并同步。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp)) } },
            confirmButton = { TextButton(onClick = { checkInDetail = false }) { Text("知道了") } }
        )
    }
    if (checkInForm) {
        AlertDialog(
            onDismissRequest = { checkInForm = false },
            title = { Text("记录今日运动") },
            text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(activityType, { activityType = it; checkInError = null }, label = { Text("运动类型") }, placeholder = { Text("如：跟练、跑步、球类") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(durationText, { durationText = it.filter(Char::isDigit); checkInError = null }, label = { Text("运动时长（分钟）") }, singleLine = true, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number), modifier = Modifier.fillMaxWidth())
                Text("运动强度", color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf("low" to "轻松", "moderate" to "适中", "high" to "较高").forEach { (value, label) -> FilterChip(selected = intensity == value, onClick = { intensity = value }, label = { Text(label, fontSize = 12.sp) }, modifier = Modifier.weight(1f).heightIn(min = 44.dp)) } }
                OutlinedTextField(feeling, { feeling = it }, label = { Text("运动后感受（选填）") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
                Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(completedRecommended, { completedRecommended = it }); Text("完成了今日建议训练", fontSize = 13.sp) }
                OutlinedTextField(parentNote, { parentNote = it }, label = { Text("家长备注（选填）") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
                checkInError?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
            } },
            confirmButton = { TextButton(onClick = {
                val minutes = durationText.toIntOrNull()
                when { activityType.trim().isBlank() -> checkInError = "请填写运动类型。"; minutes == null || minutes !in 1..1440 -> checkInError = "请输入 1–1440 分钟。"; else -> { checkInToday(activityType, minutes, intensity, feeling, completedRecommended, parentNote); checkInForm = false; checkInDetail = true } }
            }) { Text("保存记录") } },
            dismissButton = { TextButton(onClick = { checkInForm = false }) { Text("取消") } }
        )
    }
    if (growthReportOpen) {
        val selectedChild = state.selectedChild
        val officialSchoolScore = selectedChild
            ?.takeIf(state::hasPublishedSchoolReport)
            ?.let(reportForStudent)
            ?.totalScore
        GrowthInsightDialog(state, officialSchoolScore = officialSchoolScore, dismiss = { growthReportOpen = false }, openCourses = { nav.navigate(Destinations.Courses) })
    }
}

@Composable
private fun ParentActivities(nav: NavHostController) = Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
    ParentSection("最近家庭运动", "查看全部") { nav.navigate(Destinations.Courses) }
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp), modifier = Modifier.fillMaxWidth()) { MiniActivity(R.drawable.activity_classroom, "课间活力操", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) }; MiniActivity(R.drawable.activity_football, "足球启蒙", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) }; MiniActivity(R.drawable.activity_balance, "平衡挑战", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) } }
    Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看推荐课程：青少年体姿改善课程" }.clickable { nav.navigate(Destinations.Courses) }, color = Color.White, shape = RoundedCornerShape(11.dp)) {
        Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Image(painterResource(R.drawable.activity_balance), null, Modifier.size(58.dp).clip(RoundedCornerShape(9.dp)), contentScale = ContentScale.Crop)
            Spacer(Modifier.width(9.dp))
            Column(Modifier.weight(1f)) { Text("为孩子推荐", color = Color.Gray, fontSize = 12.sp); Text("青少年体姿改善课程", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp); Text("每周 2 次 · 适合 7-10 岁", color = Green, fontSize = 12.sp) }
            Text("查看课程", color = Color.White, fontSize = 12.sp, modifier = Modifier.background(Color(0xFFFFB521), CircleShape).padding(horizontal = 9.dp, vertical = 5.dp))
        }
    }
}
@Composable private fun MiniActivity(image: Int, title: String, modifier: Modifier, onClick: () -> Unit) = Surface(onClick = onClick, modifier = modifier, color = Color.White, shape = RoundedCornerShape(8.dp)) { Column(Modifier.padding(4.dp)) { Image(painterResource(image), null, Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(6.dp)), contentScale = ContentScale.Crop); Text(title, color = Navy, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1, modifier = Modifier.padding(top = 3.dp)) } }
@Composable private fun ParentTabScaffold(nav: NavHostController, selected: String, body: @Composable ColumnScope.() -> Unit) = Scaffold(containerColor = Canvas, bottomBar = { ParentBottomBar(nav, selected) }) { padding ->
    Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight().padding(horizontal = 12.dp).verticalScroll(rememberScrollState()), content = body)
    }
}
@Composable private fun ParentBottomBar(nav: NavHostController, selected: String) = NavigationBar(containerColor = Color.White, tonalElevation = 1.dp) {
    fun go(route: String) { nav.navigate(route) { popUpTo(Destinations.Parent) { saveState = true }; launchSingleTop = true; restoreState = true } }
    ParentNavItem("首页", Icons.Filled.Home, selected == Destinations.Parent) { go(Destinations.Parent) }
    ParentNavItem("我的评测", Icons.AutoMirrored.Filled.Assignment, selected == Destinations.ParentEvaluations) { go(Destinations.ParentEvaluations) }
    ParentNavItem("我的课程", Icons.Filled.PlayCircle, selected == Destinations.Courses) { go(Destinations.Courses) }
    ParentNavItem("班级圈", Icons.Filled.Groups, selected == Destinations.Circle) { go(Destinations.Circle) }
    ParentNavItem("我的", Icons.Filled.Person, selected == Destinations.Account) { go(Destinations.Account) }
}
@Composable private fun RowScope.ParentNavItem(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, selected: Boolean, onClick: () -> Unit) = NavigationBarItem(selected = selected, onClick = onClick, icon = { Icon(icon, null) }, label = { Text(label, fontSize = 12.sp, maxLines = 1) }, modifier = Modifier.semantics { contentDescription = "$label${if (selected) "，当前页面" else ""}" })

@Composable fun ParentCoursesScreen(state: AppUiState, nav: NavHostController, updateCourseProgress: (String, Float) -> Unit, sendSupport: (String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, loadCourses: (String) -> Unit = {}, saveRemoteProgress: (String, RemoteLesson, Int, Boolean) -> Unit = { _, _, _, _ -> }, clearRecommendedCourse: () -> Unit = {}, openSupport: Boolean = false, submitSupport: (String) -> Unit = sendSupport, clearWorkflow: (String) -> Unit = {}) {
    var paid by remember { mutableStateOf(false) }
    var detail by rememberSaveable(openSupport) { mutableStateOf<String?>(if (openSupport) "客服咨询" else null) }
    var selectedCourse by rememberSaveable { mutableStateOf<String?>(null) }
    var catalogOpen by rememberSaveable { mutableStateOf(false) }
    var recommendationError by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(openSupport) { if (openSupport) clearWorkflow("support") }
    ParentTabScaffold(nav, Destinations.Courses) {
        val dashboardError = state.error
        if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@ParentTabScaffold }
        if (state.loading || state.data == null) { LoadingState(); return@ParentTabScaffold }
        if (state.selectedChild == null) { EmptyState("暂无孩子档案，请先完成孩子绑定。"); Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("去绑定孩子") }; return@ParentTabScaffold }
        val selectedChild = state.selectedChild
        LaunchedEffect(selectedChild.id) { if (state.repositoryAcknowledged) loadCourses(selectedChild.id) }
        LaunchedEffect(state.courseRecommendationTarget, state.coursesLoading, state.coursesChildId, state.remoteCourses) {
            val target = state.courseRecommendationTarget ?: return@LaunchedEffect
            if (target.childId != selectedChild.id) return@LaunchedEffect
            if (!state.repositoryAcknowledged) {
                selectedCourse = target.lessonId ?: target.title
                clearRecommendedCourse()
                return@LaunchedEffect
            }
            // `coursesChildId` makes a fast child switch safe: no result or
            // error from a former child's request can open a lesson here.
            if (state.coursesChildId != selectedChild.id || state.coursesLoading) return@LaunchedEffect
            val courseId = target.courseId
            val lessonId = target.lessonId
            if (courseId.isNullOrBlank() || lessonId.isNullOrBlank()) {
                recommendationError = "该报告的课程建议尚未包含可播放课程信息，请在学校同步课程后再试。"
            } else if (state.coursesError == null) {
                val lesson = state.remoteCourses.firstOrNull { it.courseId == courseId && it.lessonId == lessonId }
                if (lesson != null) selectedCourse = lesson.lessonId
                else recommendationError = "学校暂未为该孩子分配这节推荐课程。"
            }
            if (state.coursesError == null) clearRecommendedCourse()
        }
        Text("我的课程", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 10.dp)); Text("${selectedChild.name} · ${selectedChild.className}", color = Color.Gray, fontSize = 12.sp); Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth().background(Sky, RoundedCornerShape(9.dp))) { listOf("公益课程", "学校课程").forEachIndexed { index, text -> Text(text, color = if (paid == (index == 1)) Color.White else Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.weight(1f).padding(8.dp).semantics { role = Role.Tab; contentDescription = "切换到$text" }.background(if (paid == (index == 1)) Blue else Color.Transparent, RoundedCornerShape(8.dp)).clickable { paid = index == 1 }) } }
        Spacer(Modifier.height(10.dp)); ParentSection(if (paid) "精选学校课程" else "公益课堂", "全部课程") { catalogOpen = true }
        val items = if (state.repositoryAcknowledged) state.remoteCourses.map { it.lessonId to Icons.Filled.PlayCircle } else if (paid) {
            listOf(
                "校内体能提升课" to Icons.AutoMirrored.Filled.DirectionsRun,
                "校园视力守护课" to Icons.Filled.RemoveRedEye,
                "课后运动巩固课" to Icons.Filled.FitnessCenter,
                "亲子运动指导课" to Icons.Filled.Groups
            )
        } else {
            listOf(
                "体质成长课" to Icons.AutoMirrored.Filled.DirectionsRun,
                "视力守护课" to Icons.Filled.RemoveRedEye,
                "口腔健康课" to Icons.Filled.MedicalServices,
                "心理舒展课" to Icons.Filled.Favorite
            )
        }
        when {
            state.repositoryAcknowledged && state.coursesLoading -> LoadingState()
            state.repositoryAcknowledged && state.coursesError != null -> ErrorState(state.coursesError, retry = { loadCourses(selectedChild.id) })
            state.repositoryAcknowledged && items.isEmpty() -> EmptyState("暂无已分配课程，学校或平台分配后会显示在这里。")
            else -> items.chunked(2).forEach { row -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { (itemId, icon) -> val remote = state.remoteCourses.firstOrNull { it.lessonId == itemId }; val displayTitle = remote?.title ?: itemId; Surface(Modifier.weight(1f).height(105.dp).semantics { role = Role.Button; contentDescription = "打开课程：$displayTitle" }.clickable { selectedCourse = itemId }, color = Sky, shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(12.dp)) { Icon(icon, null, tint = Blue); Spacer(Modifier.height(8.dp)); Text(displayTitle, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); val key = if (remote == null) com.xiangshang.youth.app.AppViewModel.courseProgressKey(selectedChild.id, "legacy-$itemId", lessonId = "legacy-$itemId") else com.xiangshang.youth.app.AppViewModel.courseProgressKey(selectedChild.id, remote.courseId, remote.moduleId ?: "default", remote.lessonId); val progress = state.local.courseProgress[key] ?: remote?.let { if (it.completed) 1f else (it.lastPositionMs.toFloat() / it.durationMs.coerceAtLeast(1)).coerceIn(0f,1f) } ?: state.local.courseProgress[itemId] ?: 0f; Text(if (progress > 0f) "学习进度 ${(progress * 100).toInt()}%" else "开始学习", color = Green, fontSize = 12.sp) } } }; if (row.size == 1) Spacer(Modifier.weight(1f)) }; Spacer(Modifier.height(8.dp)) }
        }
        Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "打开课程咨询" }.clickable { clearWorkflow("support"); detail = "客服咨询" }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.AutoMirrored.Filled.Message, null, tint = Blue); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text("课程咨询", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("填写后自动保存并同步", color = Color.Gray, fontSize = 12.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } }
    }
    detail?.let { title -> SimpleDialog(title = title, messages = state.local.supportMessages, drafts = state.local.drafts, send = sendSupport, submit = submitSupport, command = state.workflowStates["support"] ?: WorkflowCommandState(), commandDriven = title == "客服咨询", saveDraft = saveDraft, clearDraft = clearDraft, dismiss = { detail = null }) }
    if (catalogOpen) CourseCatalogDialog(
        paid = paid,
        onOpenCourse = { title -> catalogOpen = false; selectedCourse = title },
        dismiss = { catalogOpen = false }
    )
    selectedCourse?.let { title -> CourseLessonDialog(
        title = state.remoteCourses.firstOrNull { it.lessonId == title }?.title ?: title,
        initialProgress = state.remoteCourses.firstOrNull { it.lessonId == title }?.let { if (it.completed) 1f else (it.lastPositionMs.toFloat() / it.durationMs.coerceAtLeast(1)).coerceIn(0f,1f) } ?: state.selectedChild?.let { state.local.courseProgress[com.xiangshang.youth.app.AppViewModel.courseProgressKey(it.id, "legacy-$title", lessonId = "legacy-$title")] } ?: state.local.courseProgress[title] ?: 0f,
        updateCourseProgress = { _, progress -> state.selectedChild?.let { child ->
            state.remoteCourses.firstOrNull { it.lessonId == title }?.let { lesson ->
                updateCourseProgress(com.xiangshang.youth.app.AppViewModel.courseProgressKey(child.id, lesson.courseId, lesson.moduleId ?: "default", lesson.lessonId), progress)
            } ?: updateCourseProgress(com.xiangshang.youth.app.AppViewModel.courseProgressKey(child.id, "legacy-$title", lessonId = "legacy-$title"), progress)
        } },
        videoSource = state.remoteCourses.firstOrNull { it.lessonId == title }?.videoSource,
        mockVideoAllowed = !state.repositoryAcknowledged,
        initialPositionMs = state.remoteCourses.firstOrNull { it.lessonId == title }?.lastPositionMs ?: 0,
        onRemoteSave = { position, completed -> state.selectedChild?.let { child -> state.remoteCourses.firstOrNull { it.lessonId == title }?.let { lesson -> saveRemoteProgress(child.id, lesson, position, completed) } } },
        dismiss = { selectedCourse = null }
    ) }
    recommendationError?.let { message ->
        AlertDialog(
            onDismissRequest = { recommendationError = null },
            title = { Text("暂无法打开课程") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { recommendationError = null }) { Text("知道了") } }
        )
    }
}

/** A course is a real local workflow even while the production media endpoint
 * is unavailable: progress is only recorded after the learner starts it. */
@Composable
private fun CourseLessonDialog(
    title: String,
    initialProgress: Float,
    updateCourseProgress: (String, Float) -> Unit,
    videoSource: String? = null,
    mockVideoAllowed: Boolean = true,
    initialPositionMs: Int = 0,
    onRemoteSave: ((Int, Boolean) -> Unit)? = null,
    dismiss: () -> Unit
) {
    var progress by rememberSaveable(title) { mutableFloatStateOf(initialProgress) }
    var playing by rememberSaveable(title) { mutableStateOf(false) }
    var videoView by remember { mutableStateOf<VideoView?>(null) }
    var playbackError by rememberSaveable(title) { mutableStateOf<String?>(null) }
    LaunchedEffect(playing, videoView) {
        while (playing && videoView != null) {
            videoView?.let { view ->
                val duration = view.duration
                if (duration > 0) {
                    progress = (view.currentPosition.toFloat() / duration.toFloat()).coerceIn(0f, 1f)
                    if (progress >= 1f) playing = false
                }
            }
            delay(500)
        }
    }
    AlertDialog(
        onDismissRequest = {
            if (progress > initialProgress) updateCourseProgress(title, progress)
            videoView?.let { onRemoteSave?.invoke(it.currentPosition.coerceAtLeast(0), progress >= .999f) }
            dismiss()
        },
        title = { Text(title) },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                AndroidView(
                    factory = { context ->
                        VideoView(context).apply {
                            videoView = this
                            val source = videoSource ?: if (mockVideoAllowed) "android.resource://${context.packageName}/${R.raw.follow_along_training}" else null
                            if (source != null) setVideoURI(source.toUri()) else playbackError = "课程视频待同步，请稍后重试。"
                            setOnPreparedListener { mediaPlayer ->
                                if (initialPositionMs > 0) mediaPlayer.seekTo(initialPositionMs) else if (initialProgress > 0f) mediaPlayer.seekTo((mediaPlayer.duration * initialProgress).toInt())
                            }
                            setOnErrorListener { _, _, _ -> playbackError = "课程视频暂时无法播放，请重试。"; playing = false; true }
                            setOnCompletionListener { progress = 1f; playing = false; updateCourseProgress(title, 1f) }
                        }
                    },
                    update = { view -> if (playing) view.start() else view.pause() },
                    modifier = Modifier.fillMaxWidth().height(160.dp).clip(RoundedCornerShape(10.dp))
                )
                playbackError?.let { error ->
                    Text(error, color = Color(0xFFD64545), fontSize = 12.sp, modifier = Modifier.padding(top = 7.dp))
                    TextButton(onClick = { playbackError = null; videoView?.seekTo(0); playing = true }) { Text("重试播放") }
                }
                Text("课程播放进度会自动保存，联网后同步。", color = Color.Gray, fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
                LinearProgressIndicator({ progress }, Modifier.fillMaxWidth().padding(top = 16.dp).height(7.dp).clip(CircleShape), color = Green, trackColor = Sky)
                Text("学习进度 ${(progress * 100).toInt()}%", color = Green, fontSize = 12.sp, modifier = Modifier.padding(top = 7.dp))
            }
        },
        confirmButton = {
            TextButton(onClick = {
                playing = !playing
            }, enabled = videoSource != null || mockVideoAllowed) {
                Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, null, modifier = Modifier.size(17.dp))
                Spacer(Modifier.width(4.dp))
                Text(if (playing) "暂停学习" else if (progress >= 1f) "再次学习" else "播放课程")
            }
        },
        dismissButton = { TextButton(onClick = { if (progress > initialProgress) updateCourseProgress(title, progress); videoView?.let { onRemoteSave?.invoke(it.currentPosition.coerceAtLeast(0), progress >= .999f) }; dismiss() }) { Text("完成") } }
    )
}

@Composable
private fun CourseCatalogDialog(paid: Boolean, onOpenCourse: (String) -> Unit, dismiss: () -> Unit) {
    val courses = if (paid) listOf("校内体能提升课", "校园视力守护课", "课后运动巩固课", "亲子运动指导课") else listOf("体质成长课", "视力守护课", "口腔健康课", "心理舒展课")
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(if (paid) "学校课程目录" else "公益课程目录") },
        text = {
            Column {
                Text("选择课程后可开始学习，进度会自动保存。", color = Color.Gray, fontSize = 12.sp)
                courses.forEach { course ->
                    Row(
                        Modifier.fillMaxWidth().padding(top = 8.dp).semantics { role = Role.Button; contentDescription = "学习$course" }.clickable { onOpenCourse(course) }.padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Filled.PlayCircle, null, tint = Blue, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(course, color = Navy, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.size(17.dp))
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = dismiss) { Text("关闭") } }
    )
}

@Composable fun ParentClassCircleScreen(state: AppUiState, nav: NavHostController, publishPost: (String, String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, toggleLike: (String) -> Unit, addComment: (String, String) -> Unit, submitPost: (String, String, List<ClassPostAttachment>) -> Unit = { author, content, _ -> publishPost(author, content) }, clearWorkflow: (String) -> Unit = {}, loadClassPosts: () -> Unit = {}, loadClassPostAttachment: (String) -> Unit = {}, deletePost: (ClassPost) -> Unit = {}, reportPost: (ClassPost) -> Unit = {}) {
    var detail by remember { mutableStateOf<String?>(null) }
    var filter by rememberSaveable { mutableIntStateOf(0) }
    var commentPost by rememberSaveable { mutableStateOf<String?>(null) }
    var comment by rememberSaveable { mutableStateOf("") }
    var commentSubmitted by rememberSaveable { mutableStateOf(false) }
    var postDraft by rememberSaveable { mutableStateOf("") }
    var postAttachmentReference by rememberSaveable { mutableStateOf<String?>(null) }
    var postAttachmentName by rememberSaveable { mutableStateOf<String?>(null) }
    var postAttachmentType by rememberSaveable { mutableStateOf("image") }
    var postAttachmentError by rememberSaveable { mutableStateOf<String?>(null) }
    val pinnedAnnouncementId = "teacher-announcement"
    val pinnedAnnouncementLiked = pinnedAnnouncementId in state.local.likedPostIds
    val context = LocalContext.current
    val currentParentName = state.activeDisplayName
    val currentParentKey = "post:${state.profile?.id ?: "session"}"
    val currentParentDraftKey = "class-post-${state.profile?.id ?: "session"}"
    val attachmentPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            runCatching { CourseAttachmentStore.copyPickedMedia(context, uri) }
                .onSuccess { saved ->
                    postAttachmentReference = saved.file.toURI().toString()
                    postAttachmentName = saved.file.name
                    postAttachmentType = if (saved.mimeType == "video/mp4") "video" else "image"
                    postAttachmentError = null
                }
                .onFailure { postAttachmentError = it.message ?: "附件读取失败，请重新选择。" }
        }
    }
    fun openComment(postId: String) {
        commentSubmitted = false
        comment = state.local.drafts["class-comment-$postId"].orEmpty()
        commentPost = postId
    }
    ParentTabScaffold(nav, Destinations.Circle) {
        val dashboardError = state.error
        if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@ParentTabScaffold }
        if (state.loading || state.data == null) { LoadingState(); return@ParentTabScaffold }
        if (state.selectedChild == null) { EmptyState("暂无孩子档案，请先完成孩子绑定。"); Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("去绑定孩子") }; return@ParentTabScaffold }
        Text("班级圈", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 10.dp))
        val selectedChild = state.selectedChild
        LaunchedEffect(selectedChild.id) { loadClassPosts() }
        val classMemberCount = selectedChild.classId?.let { classId -> state.data.students.count { it.classId == classId } } ?: 0
        val classTeacherName = selectedChild.classId?.let { classId -> state.data.classes.firstOrNull { it.id == classId }?.teacherName } ?: "班级教师"
        val visibleClassmates = emptyList<com.xiangshang.youth.core.model.Student>()
        val currentMonthPrefix = BusinessClock.format("yyyy-MM")
        val currentMonthCheckInCount = state.local.checkedInDates.count { it.startsWith(currentMonthPrefix) }
        Text("${selectedChild.name} · ${selectedChild.className} · ${classMemberCount}人", color = Color.Gray, fontSize = 12.sp)
        Surface(Modifier.fillMaxWidth().padding(top = 9.dp), color = Sky, shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("本班家校圈", color = Navy, fontWeight = FontWeight.Bold, fontSize = 15.sp); Text("分享运动成长，和老师保持联系", color = Color.Gray, fontSize = 12.sp) }; Column(horizontalAlignment = Alignment.End) { Text("$classMemberCount", color = Blue, fontWeight = FontWeight.Bold, fontSize = 20.sp); Text("班级成员", color = Color.Gray, fontSize = 12.sp) } } }
        Row(Modifier.fillMaxWidth().padding(top = 9.dp), horizontalArrangement = Arrangement.spacedBy(7.dp)) { listOf("全部", "老师动态", "家长分享").forEachIndexed { index, title -> FilterChip(selected = filter == index, onClick = { filter = index }, label = { Text(title, fontSize = 12.sp) }) } }
        Button(onClick = {
            clearWorkflow(currentParentKey)
            postDraft = state.local.drafts[currentParentDraftKey] ?: state.local.drafts["class-post-$currentParentName"].orEmpty()
            postAttachmentReference = null
            postAttachmentName = null
            postAttachmentType = "image"
            postAttachmentError = null
            detail = "发布班级动态"
        }, modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp)) { Icon(Icons.Filled.Edit, null); Spacer(Modifier.width(7.dp)); Text("发布班级动态") }
        val posts = state.local.classPosts.filter { filter == 0 || (filter == 1 && it.authorRole == "teacher") || (filter == 2 && it.authorRole != "teacher") }
        if (state.repositoryAcknowledged && state.classPostsLoading) {
            LoadingState()
        } else if (state.repositoryAcknowledged && state.classPostsError != null) {
            ErrorState(state.classPostsError, retry = loadClassPosts)
        } else if (state.repositoryAcknowledged && posts.isEmpty()) {
            EmptyState("暂无班级动态，学校发布或家长分享后会显示在这里。")
        }
        // Keep the teacher announcement at the top of the whole/teacher feeds.
        // It is intentionally excluded only from the parent-sharing filter.
        if (!state.repositoryAcknowledged && filter != 2) {
                Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.School, null, tint = Blue); Spacer(Modifier.width(8.dp))
                            Column { Text(classTeacherName, color = Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("今天 08:30 · 置顶通知", color = Color.Gray, fontSize = 12.sp) }
                        }
                        Text("本周运动打卡已开启，欢迎家长分享孩子的练习瞬间。", color = Navy, fontSize = 12.sp, modifier = Modifier.padding(top = 7.dp))
                        Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            Text(if (pinnedAnnouncementLiked) "已赞 13" else "♡ 12", color = if (pinnedAnnouncementLiked) Blue else Color.Gray, fontSize = 12.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = if (pinnedAnnouncementLiked) "取消点赞" else "点赞" }.clickable { toggleLike(pinnedAnnouncementId) })
                            Text("评论 ${3 + state.local.postComments[pinnedAnnouncementId].orEmpty().size}", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "评论置顶通知" }.clickable { openComment(pinnedAnnouncementId) })
                            Spacer(Modifier.weight(1f)); Text("班级通知", color = Blue, fontSize = 12.sp)
                        }
                        ClassCircleCommentPreview(state.local.postComments[pinnedAnnouncementId].orEmpty())
                    }
                }
        }
        posts.forEach { post ->
            // A remote moderation status is not proof of ownership. Only a
            // confirmed owner or a purely local draft may expose delete.
            val canDelete = post.ownedByCurrentUser || post.postId == null
            Surface(Modifier.padding(vertical = 4.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp), shadowElevation = 1.dp) { Column(Modifier.padding(11.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.AccountCircle, null, tint = Sky, modifier = Modifier.size(28.dp)); Spacer(Modifier.width(8.dp)); Column { Text(post.author, color = Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("刚刚发布 · ${postSyncLabel(post.status)}", color = if (post.status == LocalSubmissionStatus.Failed) Color.Red else Color.Gray, fontSize = 12.sp) }; Spacer(Modifier.weight(1f)); TextButton(onClick = { if (canDelete) deletePost(post) else reportPost(post) }, contentPadding = PaddingValues(horizontal = 6.dp, vertical = 0.dp), modifier = Modifier.semantics { contentDescription = if (canDelete) "删除本人班级动态" else "举报这条班级动态" }) { Text(if (canDelete) "删除" else "举报", fontSize = 12.sp, color = if (canDelete) Color.Red else Color.Gray) } }
                Text(post.content, color = Navy, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp))
                if (post.attachments.isNotEmpty()) ClassPostAttachments(state, post.attachments, post.moderationStatus, loadClassPostAttachment)
                Row(Modifier.fillMaxWidth().padding(top = 7.dp), horizontalArrangement = Arrangement.spacedBy(15.dp)) { Text(if (post.id in state.local.likedPostIds) "已赞" else "点赞", color = if (post.id in state.local.likedPostIds) Blue else Color.Gray, fontSize = 12.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = if (post.id in state.local.likedPostIds) "取消点赞" else "点赞" }.clickable { toggleLike(post.id) }); Text("评论", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "评论这条动态" }.clickable { openComment(post.id) }); Spacer(Modifier.weight(1f)); Text("分享", color = Blue, fontSize = 12.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "分享这条动态" }.clickable { runCatching { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, post.content) }, "分享班级动态")) } }) }
                ClassCircleCommentPreview(state.local.postComments[post.id].orEmpty())
            } }
        }
        ParentSection("本班互动", "查看说明") { detail = "班级互动说明" }
        if (visibleClassmates.isEmpty()) Text("暂无本班可见名单，学校完成分班后会显示在这里。", color = Color.Gray, fontSize = 12.sp)
        else {
            Row(Modifier.fillMaxWidth()) { visibleClassmates.forEach { student ->
                val isBoundChild = student.id == selectedChild.id
                val displayName = if (isBoundChild) student.name else "${student.name.take(1)}同学"
                Column(Modifier.weight(1f).semantics { contentDescription = if (isBoundChild) "当前孩子，${student.className}" else "本班同学，${student.className}" }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Surface(Modifier.size(36.dp), color = Blue, shape = CircleShape) { Text(student.name.take(1), color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp)) }
                    Text(displayName, color = Navy, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    Text(student.className, color = Color.Gray, fontSize = 12.sp, maxLines = 1)
                }
            } }
            Text("本页不展示或生成班级评优、排名；学校正式表彰以班主任通知为准。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp))
        }
        Spacer(Modifier.height(10.dp)); Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(12.dp)) { ParentSection("本月打卡", "查看记录") { detail = "本月运动打卡记录" }; Row(verticalAlignment = Alignment.CenterVertically) { Icon(if (currentMonthCheckInCount == 0) Icons.Filled.EventAvailable else Icons.Filled.CheckCircle, null, tint = if (currentMonthCheckInCount == 0) Color.Gray else Green, modifier = Modifier.size(17.dp)); Spacer(Modifier.width(6.dp)); Text(if (currentMonthCheckInCount == 0) "本月尚未开始运动打卡" else "本月已保存 $currentMonthCheckInCount 次运动打卡", color = if (currentMonthCheckInCount == 0) Color.Gray else Green, fontSize = 12.sp, fontWeight = FontWeight.SemiBold) }; Text("打卡记录会自动保存并同步。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp)) } }
        if (state.repositoryAcknowledged) {
            ParentSection("课程动态", "进入课程") { nav.navigate(Destinations.Courses) }
            EmptyState("暂无课程动态，学校或平台分配课程后会显示在这里。")
        } else {
            Spacer(Modifier.height(10.dp)); ParentSection("延时课堂精彩瞬间", "点击课程查看") { nav.navigate(Destinations.Courses) }; Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) { MiniActivity(R.drawable.activity_football, "足球启蒙", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) }; MiniActivity(R.drawable.activity_classroom, "健康课堂", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) }; MiniActivity(R.drawable.activity_balance, "亲子平衡", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) } }
            Spacer(Modifier.height(10.dp)); ParentSection("推荐课程", "查看详情") { nav.navigate(Destinations.Courses) }; ParentActivities(nav); Spacer(Modifier.height(8.dp)); ParentSection("我的课程", "全部课程") { nav.navigate(Destinations.Courses) }; Surface(onClick = { nav.navigate(Destinations.Courses) }, modifier = Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "推荐训练，每周 2 次，足球基础训练，查看课程" }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.CalendarMonth, null, tint = Green); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text("推荐训练", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("每周 2 次 · 足球基础训练", color = Color.Gray, fontSize = 12.sp) }; Text("去查看", color = Green, fontSize = 12.sp); Spacer(Modifier.width(4.dp)); Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Green, modifier = Modifier.size(14.dp)) } }
        }
    }
    detail?.let { title ->
        if (title == "班级互动说明") {
            AlertDialog(
                onDismissRequest = { detail = null },
                title = { Text(title) },
                text = { Column { Text("仅展示当前本班可见学生名单，便于家长确认交流范围。", color = Navy); Text("班级评优、排名及表彰由学校和班主任统一发布，本页不生成。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 9.dp)) } },
                confirmButton = { TextButton(onClick = { detail = null }) { Text("知道了") } }
            )
        } else if (title == "发布班级动态") {
            val command = state.workflowStates[currentParentKey] ?: WorkflowCommandState()
            LaunchedEffect(command.status) {
                if (command.status == WorkflowCommandStatus.Succeeded) {
                    clearDraft(currentParentDraftKey)
                    detail = null
                }
            }
            AlertDialog(
                onDismissRequest = { detail = null },
                title = { Text("发布班级动态") },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                        Text("内容仅本班可见，请勿发布完整学生姓名、证件、病历或无关学生照片。", color = Color.Gray, fontSize = 12.sp)
                        OutlinedTextField(
                            value = postDraft,
                            onValueChange = { value ->
                                postDraft = value
                                saveDraft(currentParentDraftKey, value)
                                postAttachmentError = null
                            },
                            label = { Text("动态内容") },
                            minLines = 4,
                            modifier = Modifier.fillMaxWidth()
                        )
                        Surface(color = Sky, shape = RoundedCornerShape(10.dp), modifier = Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Filled.Photo, contentDescription = null, tint = Blue)
                                    Spacer(Modifier.width(7.dp))
                                    Text(postAttachmentName ?: "可添加 1 个图片或视频附件", color = if (postAttachmentName == null) Color.Gray else Blue, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    OutlinedButton(onClick = { attachmentPicker.launch(arrayOf("image/jpeg", "image/png", "video/mp4")) }) { Text(if (postAttachmentName == null) "选择附件" else "更换附件") }
                                    if (postAttachmentName != null) TextButton(onClick = { postAttachmentReference = null; postAttachmentName = null; postAttachmentType = "image"; postAttachmentError = null }, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red)) { Text("移除") }
                                }
                                Text("仅支持 JPG、PNG 或 MP4，最大 20MB。提交时会通过学校文件服务上传，App 不保存相册原始路径。", color = Color.Gray, fontSize = 12.sp)
                                postAttachmentError?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
                            }
                        }
                        if (command.status == WorkflowCommandStatus.Failed) Text(command.message ?: "发布失败，请重试。", color = Color.Red, fontSize = 12.sp)
                    }
                },
                confirmButton = {
                    TextButton(
                        enabled = !command.isSubmitting && postDraft.trim().isNotBlank(),
                        onClick = {
                            val attachments = postAttachmentReference?.let { reference ->
                                listOf(ClassPostAttachment(id = postAttachmentName ?: "班级圈附件", type = postAttachmentType, localReference = reference))
                            }.orEmpty()
                            submitPost(currentParentName, postDraft.trim(), attachments)
                        }
                    ) {
                        if (command.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(if (command.status == WorkflowCommandStatus.Failed) "重新发布" else "发布")
                    }
                },
                dismissButton = { TextButton(onClick = { detail = null }) { Text("取消") } }
            )
        } else {
            SimpleDialog(title = title, drafts = state.local.drafts, send = { content -> if (title == "发布班级动态") publishPost(currentParentName, content) }, submit = { content -> if (title == "发布班级动态") submitPost(currentParentName, content, emptyList()) }, command = state.workflowStates[currentParentKey] ?: WorkflowCommandState(), commandDriven = title == "发布班级动态", saveDraft = saveDraft, clearDraft = clearDraft, dismiss = { detail = null })
        }
    }
    commentPost?.let { postId -> AlertDialog(onDismissRequest = { commentPost = null }, title = { Text(if (commentSubmitted) "评论已保存" else "给这条动态留言") }, text = { if (commentSubmitted) Text(if (state.repositoryAcknowledged) "评论已提交到班级圈，审核状态以学校服务为准。" else "评论已保存，联网后自动同步到班级圈。", color = Green) else OutlinedTextField(value = comment, onValueChange = { comment = it; saveDraft("class-comment-$postId", it) }, label = { Text("评论内容") }, minLines = 2) }, confirmButton = { TextButton(enabled = commentSubmitted || comment.trim().isNotBlank(), onClick = { if (commentSubmitted) commentPost = null else { addComment(postId, comment); clearDraft("class-comment-$postId"); commentSubmitted = true } }) { Text(if (commentSubmitted) "完成" else "保存评论") } }, dismissButton = if (commentSubmitted) null else ({ TextButton(onClick = { commentPost = null }) { Text("取消") } })) }
}

@Composable
private fun ClassPostAttachments(state: AppUiState, attachments: List<ClassPostAttachment>, moderationStatus: String? = null, loadAttachment: (String) -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(top = 6.dp)) {
        Text("${attachments.size} 个附件 · ${if (moderationStatus == "approved" || moderationStatus == "published") "已审核" else "待审核"}", color = Blue, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Row(Modifier.fillMaxWidth().padding(top = 5.dp), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            attachments.take(3).forEach { attachment ->
                val bytes = attachment.objectId?.let { state.classPostAttachmentBytes[it] }
                val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                Surface(
                    onClick = { attachment.objectId?.let(loadAttachment) },
                    modifier = Modifier.weight(1f).height(72.dp).semantics {
                        role = Role.Button
                        contentDescription = if (attachment.type == "video") "查看班级圈视频附件" else "查看班级圈图片附件"
                    },
                    color = Sky,
                    shape = RoundedCornerShape(8.dp)
                ) {
                    if (bitmap != null) Image(bitmap.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    else Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        Icon(if (attachment.type == "video") Icons.Filled.Videocam else Icons.Filled.Photo, null, tint = if (attachment.objectId?.let { state.classPostAttachmentErrors[it] } == null) Blue else Color.Red)
                        Text(if (attachment.objectId?.let { state.classPostAttachmentErrors[it] } == null) "查看附件" else "重试", color = if (attachment.objectId?.let { state.classPostAttachmentErrors[it] } == null) Blue else Color.Red, fontSize = 12.sp)
                    }
                }
            }
        }
    }
}

@Composable private fun ClassCircleCommentPreview(comments: List<String>) {
    if (comments.isEmpty()) return
    Column(Modifier.fillMaxWidth().padding(top = 6.dp)) {
        HorizontalDivider(color = Color(0xFFF0F2F7))
        Text("最新评论", color = Color.Gray, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 5.dp))
        comments.takeLast(2).forEach { comment ->
            Text("我的留言：$comment", color = Navy, fontSize = 12.sp, maxLines = 2, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

@Composable fun AccountScreen(state: AppUiState, nav: NavHostController, chooseRole: (UserRole) -> Unit, logout: () -> Unit, updateSettings: (Boolean?, Boolean?, Boolean?) -> Unit, sendSupport: (String) -> Unit, onRoleSelected: (UserRole) -> Unit = chooseRole, submitSupport: (String) -> Unit = sendSupport, clearWorkflow: (String) -> Unit = {}, saveDraft: (String, String) -> Unit = { _, _ -> }, clearDraft: (String) -> Unit = {}, syncPending: () -> Unit = {}, submitPrivacyRequest: (String, String) -> Unit = { _, _ -> }, revokeHealthConsent: (String) -> Unit = {}, submitAccountDeletionRequest: () -> Unit = {}) {
    var settingsOpen by remember { mutableStateOf(false) }
    var accountInfo by remember { mutableStateOf<String?>(null) }
    ParentTabScaffold(nav, Destinations.Account) {
        Text("我的", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 10.dp)); Spacer(Modifier.height(8.dp))
        Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看个人资料" }.clickable { accountInfo = "个人资料" }, color = Color.White, shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Surface(Modifier.size(52.dp), color = Sky, shape = CircleShape) { Text(state.activeDisplayName.take(1), color = Blue, fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 13.dp)) }; Spacer(Modifier.width(11.dp)); Column(Modifier.weight(1f)) { Text(state.activeDisplayName, color = Navy, fontWeight = FontWeight.Bold); Text(state.profile?.schoolName ?: "学校", color = Color.Gray, fontSize = 12.sp); Text(state.role?.label ?: "家长", color = Blue, fontSize = 12.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } }
        val publishedReportCount = state.data?.students.orEmpty().count { it.id in state.local.boundChildIds && state.hasPublishedSchoolReport(it) }
        Spacer(Modifier.height(8.dp)); Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) { AccountMetric("已绑定孩子", state.local.boundChildIds.size.toString(), Blue, Modifier.weight(1f)) { nav.navigate(Destinations.Children) }; AccountMetric("成长报告", publishedReportCount.toString(), Green, Modifier.weight(1f)) { if (state.selectedChild != null) nav.navigate(Destinations.Report) else nav.navigate(Destinations.ChildrenBinding) }; AccountMetric("未读消息", state.unreadMessageCount.toString(), Color(0xFFFF638E), Modifier.weight(1f)) { nav.navigate(Destinations.Messages) } }
        if (state.pendingSyncCount > 0) Surface(onClick = { settingsOpen = true }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp).semantics { role = Role.Button; contentDescription = "有${state.pendingSyncCount}条记录等待同步，查看同步状态" }, color = Color(0xFFFFF3E0), shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Sync, null, tint = Color(0xFFFF8B1F)); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text("有 ${state.pendingSyncCount} 条记录等待同步", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("已保存，联网后自动同步", color = Color.Gray, fontSize = 12.sp) }; Text("查看", color = Blue, fontSize = 12.sp); Icon(Icons.Filled.ChevronRight, null, tint = Blue, modifier = Modifier.size(15.dp)) } }
        Text("家庭服务", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 12.dp, bottom = 2.dp)); AccountRow("孩子管理", Icons.Filled.People, Blue) { nav.navigate(Destinations.Children) }
        Text("账户与设置", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp, bottom = 2.dp)); listOf("我的健康档案" to Icons.Filled.Favorite, "我的课程" to Icons.Filled.PlayCircle, "客服咨询" to Icons.AutoMirrored.Filled.Message, "设置" to Icons.Filled.Settings, "消息" to Icons.Filled.Notifications).forEach { (title, icon) -> AccountRow(title, icon, Blue) {
            when (title) {
                "我的健康档案" -> nav.navigate(Destinations.Health)
                "我的课程" -> nav.navigate(Destinations.Courses)
                "客服咨询" -> nav.navigate("${Destinations.Courses}?openSupport=true")
                "消息" -> nav.navigate(Destinations.Messages)
                "设置" -> settingsOpen = true
            }
        } }
        Text("服务与安全", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp, bottom = 2.dp)); AccountRow("帮助与反馈", Icons.AutoMirrored.Filled.HelpOutline, Blue) { clearWorkflow("support"); accountInfo = "帮助与反馈" }; AccountRow("数据与隐私", Icons.Filled.PrivacyTip, Green) { accountInfo = "数据与隐私" }; AccountRow("用户协议与隐私政策", Icons.Filled.Description, Color.Gray) { accountInfo = "用户协议与隐私政策" }
        val availableRoles = if (state.repositoryAcknowledged) state.profile?.availableRoles.orEmpty() else UserRole.mobileRoles
        if (availableRoles.isNotEmpty()) { Spacer(Modifier.height(8.dp)); Text("切换使用角色", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) { availableRoles.filter { it in UserRole.mobileRoles }.forEach { role -> OutlinedButton(onClick = { onRoleSelected(role) }, modifier = Modifier.weight(1f)) { Text(role.label, fontSize = 12.sp) } } } }
        OutlinedButton(onClick = { logout(); nav.navigate(Destinations.Login) { popUpTo(nav.graph.id) { inclusive = true } } }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp), colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.Red)) { Text("切换账号") }
    }
    if (settingsOpen) SettingsDialog(state.local.settings.notificationsEnabled, state.local.settings.reduceMotion, state.local.settings.voiceGuidanceEnabled, state.pendingSyncCount, state.workflowStates["sync-pending"] ?: WorkflowCommandState(), updateSettings, syncPending, clearLocalData = { logout(); nav.navigate(Destinations.Login) { popUpTo(nav.graph.id) { inclusive = true } } }) { settingsOpen = false }
    accountInfo?.let { title -> AccountInfoDialog(title, state, submitSupport, saveDraft, clearDraft, submitPrivacyRequest, revokeHealthConsent, submitAccountDeletionRequest) { accountInfo = null } }
}

@Composable fun SettingsDialog(notifications: Boolean, reduceMotion: Boolean, voiceGuidance: Boolean, pendingSyncCount: Int, syncState: WorkflowCommandState, update: (Boolean?, Boolean?, Boolean?) -> Unit, syncNow: () -> Unit = {}, clearLocalData: () -> Unit = {}, dismiss: () -> Unit) {
    var notify by remember { mutableStateOf(notifications) }
    var reduce by remember { mutableStateOf(reduceMotion) }
    var voice by remember { mutableStateOf(voiceGuidance) }
    var clearConfirmation by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text("设置") },
        text = { Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("显示应用内测评与班级提醒", modifier = Modifier.weight(1f))
                Switch(checked = notify, onCheckedChange = { enabled ->
                    notify = enabled
                })
            }
            Row(verticalAlignment = Alignment.CenterVertically) { Text("减少动态效果", modifier = Modifier.weight(1f)); Switch(checked = reduce, onCheckedChange = { reduce = it }) }
            Row(verticalAlignment = Alignment.CenterVertically) { Text("语音动作引导", modifier = Modifier.weight(1f)); Switch(checked = voice, onCheckedChange = { voice = it }) }
            Text("当前显示应用内消息；开启系统通知后可及时收到提醒。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 9.dp))
            Text("同步状态", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp, modifier = Modifier.padding(top = 12.dp))
            Text("待同步记录：$pendingSyncCount 条", color = if (pendingSyncCount == 0) Green else Color(0xFFFF8B1F), fontSize = 12.sp)
            Text(if (pendingSyncCount == 0) "当前没有等待同步的操作。" else "记录已保存，联网后会自动同步。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 3.dp))
            TextButton(onClick = syncNow, enabled = pendingSyncCount > 0 && !syncState.isSubmitting, contentPadding = PaddingValues(horizontal = 0.dp, vertical = 2.dp)) { if (syncState.isSubmitting) CircularProgressIndicator(Modifier.size(15.dp), strokeWidth = 2.dp) else Text("立即同步", color = Blue, fontSize = 12.sp) }
            if (syncState.status == WorkflowCommandStatus.Succeeded) Text(syncState.message ?: "同步完成。", color = Green, fontSize = 12.sp)
            if (syncState.status == WorkflowCommandStatus.Failed) Text(syncState.message ?: "同步失败，请重试。", color = Color.Red, fontSize = 12.sp)
            Spacer(Modifier.height(8.dp))
            Text("退出登录会清除设备上的绑定孩子、草稿和通知状态；学校测评记录不会受影响。", color = Color.Gray, fontSize = 12.sp)
            TextButton(onClick = { clearConfirmation = true }, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red), modifier = Modifier.align(Alignment.Start)) { Text("清除设备数据并退出登录") }
        } },
        confirmButton = { TextButton(onClick = { update(notify, reduce, voice); dismiss() }) { Text("保存") } },
        dismissButton = { TextButton(onClick = dismiss) { Text("取消") } }
    )
    if (clearConfirmation) AlertDialog(
        onDismissRequest = { clearConfirmation = false },
        title = { Text("清除设备数据？") },
        text = { Text("此操作会移除本设备上的登录态、孩子绑定和本地草稿，后续可重新登录。") },
        confirmButton = { TextButton(onClick = { clearConfirmation = false; clearLocalData() }, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red)) { Text("清除并退出") } },
        dismissButton = { TextButton(onClick = { clearConfirmation = false }) { Text("取消") } }
    )
}

@Composable
private fun AccountInfoDialog(title: String, state: AppUiState, submitSupport: (String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, submitPrivacyRequest: (String, String) -> Unit, revokeHealthConsent: (String) -> Unit, submitAccountDeletionRequest: () -> Unit, dismiss: () -> Unit) {
    val feedbackDraftKey = "account-feedback"
    var feedback by rememberSaveable(title) { mutableStateOf(state.local.drafts[feedbackDraftKey].orEmpty()) }
    var submitted by rememberSaveable(title) { mutableStateOf(false) }
    var deleteConfirmation by rememberSaveable(title) { mutableStateOf(false) }
    var revokeConfirmation by rememberSaveable(title) { mutableStateOf(false) }
    var accountDeleteConfirmation by rememberSaveable(title) { mutableStateOf(false) }
    val command = if (title == "帮助与反馈") state.workflowStates["support"] ?: WorkflowCommandState() else WorkflowCommandState()
    LaunchedEffect(command.status) {
        if (command.status == WorkflowCommandStatus.Succeeded) {
            submitted = true
            clearDraft(feedbackDraftKey)
        }
    }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(title) },
        text = {
            if (title == "帮助与反馈") {
                if (submitted) Text("反馈已保存，联网后自动同步。", color = Green)
                else Column {
                    OutlinedTextField(value = feedback, onValueChange = { feedback = it; saveDraft(feedbackDraftKey, it) }, label = { Text("问题描述") }, minLines = 3)
                    if (command.status == WorkflowCommandStatus.Failed) Text(command.message ?: "提交失败，请重试。", color = Color.Red, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
                    if (command.isSubmitting) Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 6.dp)) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(7.dp)); Text("正在提交反馈…", color = Blue, fontSize = 12.sp) }
                    Text("绑定码由学校或班主任提供；报告生成后会在消息中心通知。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 7.dp))
                }
            } else if (title == "个人资料") {
                val profile = state.profile
                val phone = profile?.phone.orEmpty()
                val maskedPhone = if (phone.filter(Char::isDigit).length >= 7) {
                    val digits = phone.filter(Char::isDigit)
                    "${digits.take(3)}****${digits.takeLast(4)}"
                } else "未绑定手机号"
                Text("${state.activeDisplayName}\n绑定学校：${profile?.schoolName ?: "学校"}\n当前角色：${state.role?.label ?: "家长"}\n手机号：$maskedPhone\n\n资料由家庭账户维护，联网后可更新。", color = Color.Gray, fontSize = 12.sp)
            } else if (title == "数据与隐私") {
                val child = state.selectedChild
                val exportState = child?.let { state.workflowStates["privacy:${it.id}:export"] } ?: WorkflowCommandState()
                val deleteState = child?.let { state.workflowStates["privacy:${it.id}:delete"] } ?: WorkflowCommandState()
                val revokeState = child?.let { state.workflowStates["privacy:${it.id}:consent-revoke"] } ?: WorkflowCommandState()
                val accountDeleteState = state.workflowStates["privacy:account-deletion"] ?: WorkflowCommandState()
                Column {
                    Text("当前孩子：${child?.name ?: "请先绑定并选择孩子"}", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                    Text("仅可为已绑定孩子提交申请。导出文件生成后会在消息中心通知；删除申请需要学校或平台审核，审核前不会删除任何记录。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
                    TextButton(onClick = { child?.let { submitPrivacyRequest(it.id, "export") } }, enabled = child != null && !exportState.isSubmitting, contentPadding = PaddingValues(horizontal = 0.dp, vertical = 6.dp)) { if (exportState.isSubmitting) CircularProgressIndicator(Modifier.size(15.dp), strokeWidth = 2.dp) else Text("申请导出孩子数据", color = Blue) }
                    if (exportState.status == WorkflowCommandStatus.Succeeded) Text(exportState.message.orEmpty(), color = Green, fontSize = 12.sp)
                    if (exportState.status == WorkflowCommandStatus.Failed) Text(exportState.message ?: "提交失败，请重试。", color = Color.Red, fontSize = 12.sp)
                    TextButton(onClick = { deleteConfirmation = true }, enabled = child != null && !deleteState.isSubmitting, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red), contentPadding = PaddingValues(horizontal = 0.dp, vertical = 6.dp)) { if (deleteState.isSubmitting) CircularProgressIndicator(Modifier.size(15.dp), strokeWidth = 2.dp) else Text("申请删除/匿名化处理") }
                    if (deleteState.status == WorkflowCommandStatus.Succeeded) Text(deleteState.message.orEmpty(), color = Green, fontSize = 12.sp)
                    if (deleteState.status == WorkflowCommandStatus.Failed) Text(deleteState.message ?: "提交失败，请重试。", color = Color.Red, fontSize = 12.sp)
                    TextButton(onClick = { revokeConfirmation = true }, enabled = child != null && !revokeState.isSubmitting, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red), contentPadding = PaddingValues(horizontal = 0.dp, vertical = 6.dp)) { if (revokeState.isSubmitting) CircularProgressIndicator(Modifier.size(15.dp), strokeWidth = 2.dp) else Text("撤回身体测评数据使用同意") }
                    if (revokeState.status == WorkflowCommandStatus.Succeeded) Text(revokeState.message.orEmpty(), color = Green, fontSize = 12.sp)
                    if (revokeState.status == WorkflowCommandStatus.Failed) Text(revokeState.message ?: "提交失败，请重试。", color = Color.Red, fontSize = 12.sp)
                    TextButton(onClick = { accountDeleteConfirmation = true }, enabled = !accountDeleteState.isSubmitting, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red), contentPadding = PaddingValues(horizontal = 0.dp, vertical = 6.dp)) { if (accountDeleteState.isSubmitting) CircularProgressIndicator(Modifier.size(15.dp), strokeWidth = 2.dp) else Text("申请注销当前账户") }
                    if (accountDeleteState.status == WorkflowCommandStatus.Succeeded) Text(accountDeleteState.message.orEmpty(), color = Green, fontSize = 12.sp)
                    if (accountDeleteState.status == WorkflowCommandStatus.Failed) Text(accountDeleteState.message ?: "提交失败，请重试。", color = Color.Red, fontSize = 12.sp)
                }
            } else {
                Text("向上少年仅在获得授权后处理学生健康与运动数据，用于测评、报告和课程建议。儿童账号和家庭绑定数据不会用于商业推广。\n\n协议版本：2026.1", color = Color.Gray, fontSize = 12.sp)
            }
        },
        confirmButton = {
            TextButton(enabled = !command.isSubmitting && (title != "帮助与反馈" || submitted || feedback.trim().isNotEmpty()), onClick = {
                if (title == "帮助与反馈" && !submitted) submitSupport(feedback.trim()) else dismiss()
            }) { Text(if (title == "帮助与反馈" && !submitted) if (command.status == WorkflowCommandStatus.Failed) "重新提交" else "提交反馈" else "完成") }
        },
        dismissButton = if (submitted || title != "帮助与反馈") null else ({ TextButton(onClick = dismiss) { Text("取消") } })
    )
    if (deleteConfirmation) AlertDialog(
        onDismissRequest = { deleteConfirmation = false },
        title = { Text("提交删除/匿名化申请？") },
        text = { Text("此操作不会立即删除数据。学校或平台审核通过前，测评记录仍会保留。") },
        confirmButton = { TextButton(onClick = { state.selectedChild?.let { submitPrivacyRequest(it.id, "delete") }; deleteConfirmation = false }, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red)) { Text("提交申请") } },
        dismissButton = { TextButton(onClick = { deleteConfirmation = false }) { Text("取消") } }
    )
    if (revokeConfirmation) AlertDialog(
        onDismissRequest = { revokeConfirmation = false },
        title = { Text("撤回身体测评数据使用同意？") },
        text = { Text("撤回后，新的身体测评提交前需要重新授权；已完成的学校记录不会被自动删除。") },
        confirmButton = { TextButton(onClick = { state.selectedChild?.let { revokeHealthConsent(it.id) }; revokeConfirmation = false }, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red)) { Text("确认撤回") } },
        dismissButton = { TextButton(onClick = { revokeConfirmation = false }) { Text("取消") } }
    )
    if (accountDeleteConfirmation) AlertDialog(
        onDismissRequest = { accountDeleteConfirmation = false },
        title = { Text("申请注销当前账户？") },
        text = { Text("账户会先进入审核队列。批准后将撤销登录会话并匿名化账户信息；学校侧已完成的测评记录按留存规则处理。") },
        confirmButton = { TextButton(onClick = { submitAccountDeletionRequest(); accountDeleteConfirmation = false }, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red)) { Text("提交注销申请") } },
        dismissButton = { TextButton(onClick = { accountDeleteConfirmation = false }) { Text("取消") } }
    )
}

@Composable private fun AccountMetric(title: String, value: String, color: Color, modifier: Modifier, onClick: () -> Unit) = Surface(onClick = onClick, modifier = modifier, color = Color.White, shape = RoundedCornerShape(10.dp), shadowElevation = 1.dp) { Column(Modifier.padding(vertical = 10.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) { Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 18.sp); Text(title, color = Color.Gray, fontSize = 12.sp) } }
@Composable private fun AccountRow(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, onClick: () -> Unit) = Surface(onClick = onClick, modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp), color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = color); Spacer(Modifier.width(10.dp)); Text(title, color = Navy, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f)); Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } }

@Composable
private fun SimpleDialog(
    title: String,
    messages: List<com.xiangshang.youth.core.service.SupportMessage> = emptyList(),
    drafts: Map<String, String> = emptyMap(),
    send: (String) -> Unit = {},
    submit: (String) -> Unit = send,
    command: WorkflowCommandState = WorkflowCommandState(),
    commandDriven: Boolean = false,
    saveDraft: (String, String) -> Unit = { _, _ -> },
    clearDraft: (String) -> Unit = {},
    dismiss: () -> Unit
) {
    val draftKey = "dialog-$title"
    // A support composer must start empty. Prefilling a sentence makes a
    // commercial form look like an automated demo and can cause accidental
    // submission of text the family did not write. Restore only an explicit
    // locally saved draft.
    var draft by remember(title) { mutableStateOf(drafts[draftKey].orEmpty()) }
    var validation by remember(title) { mutableStateOf<String?>(null) }
    var success by remember(title) { mutableStateOf<String?>(null) }
    LaunchedEffect(command.status) {
        if (command.status == WorkflowCommandStatus.Succeeded) {
            success = command.message ?: "提交成功。"
            clearDraft(draftKey)
        }
    }
    val isEditable = title == "客服咨询" || title == "发布班级动态"
    AlertDialog(
        onDismissRequest = dismiss,
        confirmButton = {
            TextButton(enabled = !command.isSubmitting && (!isEditable || success != null || draft.isNotBlank()), onClick = {
                if (!isEditable) {
                    dismiss()
                } else if (success != null) {
                    dismiss()
                } else if (draft.trim().isBlank()) {
                    validation = if (title == "客服咨询") "请输入咨询内容。" else "动态内容不能为空。"
                } else {
                    if (commandDriven) submit(draft.trim()) else {
                        send(draft.trim())
                        clearDraft(draftKey)
                    }
                    validation = null
                    if (!commandDriven) success = if (title == "客服咨询") "咨询已保存，联网后自动同步。" else "动态已保存，联网后自动同步到班级圈。"
                }
            }) { if (command.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(if (success != null) "完成" else if (command.status == WorkflowCommandStatus.Failed) "重新提交" else if (title == "客服咨询") "发送咨询" else if (title == "发布班级动态") "发布" else "我知道了") }
        },
        dismissButton = if (success == null) ({ TextButton(onClick = dismiss) { Text("取消") } }) else null,
        title = { Text(title) },
        text = {
            when {
                command.status == WorkflowCommandStatus.Failed -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Filled.ErrorOutline, contentDescription = null, tint = Color.Red, modifier = Modifier.size(42.dp))
                    Text(command.message ?: "提交失败，请重试。", color = Color.Red, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
                }
                success != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Green, modifier = Modifier.size(42.dp))
                    Text(success.orEmpty(), color = Navy, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
                }
                title == "客服咨询" -> Column {
                    Text("咨询内容会自动保存并同步，提交后由服务团队跟进。", color = Color.Gray, fontSize = 12.sp)
                    OutlinedTextField(value = draft, onValueChange = { draft = it; validation = null; saveDraft(draftKey, it) }, label = { Text("咨询内容") }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp), isError = validation != null)
                    messages.takeLast(4).forEach { message -> Text((if (message.mine) "您：" else "服务团队：") + message.text + if (message.mine) " · ${supportSyncLabel(message.status)}" else "", color = if (message.status == LocalSubmissionStatus.Failed) Color.Red else if (message.mine) Navy else Green, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp)) }
                }
                title == "发布班级动态" -> OutlinedTextField(value = draft, onValueChange = { draft = it; validation = null; saveDraft(draftKey, it) }, label = { Text("动态内容") }, placeholder = { Text("分享孩子的运动成长") }, modifier = Modifier.fillMaxWidth(), isError = validation != null)
                else -> Text("内容会自动保存并同步。")
            }
            validation?.let { Text(it, color = Color.Red, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp)) }
        }
    )
}

@Composable fun AssessmentFlowScreen(state: AppUiState, nav: NavHostController, category: String, completeAssessment: (String, Map<String, String>) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, loadHealthObservations: (String) -> Unit = {}) {
    val childKey = state.selectedChild?.id ?: "anonymous"
    if (state.selectedChild == null) { AppScaffold("绑定孩子", onBack = { nav.popBackStack() }) { EmptyState("请先绑定孩子，再开始健康测评。"); Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("去绑定孩子") } }; return }
    val selectedChild = state.selectedChild
    val title = when (category) { "vision" -> "视力"; "oral" -> "口腔"; "mental" -> "心理"; else -> "体质" }
    val icon = when (category) { "vision" -> Icons.Filled.RemoveRedEye; "oral" -> Icons.Filled.MedicalServices; "mental" -> Icons.Filled.Favorite; else -> Icons.AutoMirrored.Filled.DirectionsRun }
    val tint = when (category) { "vision" -> Green; "oral" -> Color(0xFFFFBD2E); "mental" -> Color(0xFFFF6D9B); else -> Blue }
    val steps = when (category) { "fitness" -> listOf("基础信息", "遗传身高", "脊柱姿态", "运动表现"); "vision" -> listOf("基础信息", "用眼习惯", "视力筛查"); "oral" -> listOf("基础信息", "口腔习惯", "口腔筛查"); else -> listOf("开始说明", "家庭感受记录", "家庭观察结果") }
    val progressKey = "assessment-progress-${selectedChild.id}-$category"
    var step by rememberSaveable(childKey, category) {
        mutableIntStateOf(state.local.drafts[progressKey]?.toIntOrNull()?.coerceIn(0, steps.lastIndex) ?: 0)
    }
    val options = observationOptions(category, step)
    val hasArchivedRecord = state.local.familyHealthRecords.containsKey("${selectedChild.id}-$category")
    // Older versions kept only a completion marker. Without archived answers
    // it must remain an editable form, not a false saved family record.
    var done by rememberSaveable(childKey, category) { mutableStateOf(if (category == "fitness") "$childKey-$category" in state.local.completedAssessments else hasArchivedRecord) }
    var answer by rememberSaveable(childKey, category, step) { mutableStateOf("") }
    var validation by rememberSaveable(childKey, category, step) { mutableStateOf<String?>(null) }
    val draftKey = "assessment-${selectedChild.id}-$category-$step"
    LaunchedEffect(draftKey) { answer = state.local.drafts[draftKey].orEmpty() }
    LaunchedEffect(selectedChild.id, category) {
        if (category != "fitness") loadHealthObservations(selectedChild.id)
    }
    // `rememberSaveable` covers rotations only.  Persist the step independently
    // so an assessment remains resumable after Android reclaims the process.
    LaunchedEffect(progressKey, step, done) {
        if (!done) saveDraft(progressKey, step.toString())
    }
    Scaffold(containerColor = Canvas) { padding -> Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
        Row(Modifier.fillMaxWidth().background(Color.White).padding(14.dp), verticalAlignment = Alignment.CenterVertically) { IconButton(onClick = { nav.popBackStack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回") }; Text("${title}测评", color = Navy, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), textAlign = TextAlign.Center); Spacer(Modifier.width(48.dp)) }
        Column(Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) { Icon(icon, null, tint = tint, modifier = Modifier.size(52.dp)); Text("${selectedChild.name}的${title}测评", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 7.dp)); Text(if (category == "fitness") "完成身高、体态与学校运动表现记录" else "请根据孩子最近情况完成本次测评", color = Color.Gray, fontSize = 12.sp) }
        Row(Modifier.padding(horizontal = 16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { steps.forEachIndexed { index, item -> Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) { Surface(Modifier.size(25.dp), color = if (index <= step) tint else Color.LightGray, shape = CircleShape) { Text("${index + 1}", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 5.dp)) }; Text(item, color = if (index <= step) tint else Color.Gray, fontSize = 12.sp, maxLines = 1) }; if (index < steps.lastIndex) Spacer(Modifier.width(2.dp)) } }
        Surface(Modifier.padding(16.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) { Column(Modifier.padding(14.dp)) { val record = state.local.familyHealthRecords["${selectedChild.id}-$category"]; Text(if (done) if (category == "fitness") "学校运动表现记录" else "家庭健康记录已保存" else steps[step], color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp); Spacer(Modifier.height(8.dp)); Text(if (done) if (category == "fitness") "本页只记录学校运动表现信息；正式 7 项体测成绩仍以场地端报告为准。" else "本次家庭健康记录已保存，不会作为学校正式测评结果。" else if (category == "mental") when (step) { 0 -> "请由家长陪同完成。这是家庭观察记录，不会发起第三方授权，也不会生成心理诊断。"; 1 -> "记录孩子最近一周的情绪、睡眠或同伴互动感受；可多选，避免填写不必要的敏感隐私。"; else -> "保存后可在健康档案查看。若持续担忧，请联系学校心理老师或医疗专业人员。" } else if (category == "fitness") when(step) { 0 -> "确认孩子的出生日期、当前身高和体重。"; 1 -> "填写父母身高，系统会计算遗传身高区间。"; 2 -> "按引导上传或记录站立姿态筛查结果。"; else -> "学校场地端完成运动发展测试后，正式 7 项成绩会在上传后同步。" } else "填写健康习惯并确认本次${title}筛查结果。", color = Color.Gray, fontSize = 12.sp); if (record != null) Text("最后保存：${record.completedAt}", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp)); if (done) { steps.forEachIndexed { index, label -> Column(Modifier.fillMaxWidth().padding(top = 9.dp).background(tint.copy(alpha = .06f), RoundedCornerShape(8.dp)).padding(9.dp)) { Text(label, color = tint, fontSize = 12.sp, fontWeight = FontWeight.SemiBold); Text(record?.entries?.get(label).orEmpty().ifBlank { state.local.drafts["assessment-${selectedChild.id}-$category-$index"].orEmpty().ifBlank { "未填写" } }, color = Navy, fontSize = 12.sp, modifier = Modifier.padding(top = 3.dp)) } }; Text(if (category == "fitness") "学校正式体测报告由场地端生成；本页不生成或替代正式 7 项成绩。" else "这是家长填写并保存在设备的家庭健康记录，不替代学校筛查、专业诊断或治疗。", color = Blue, fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp)) }; if (category == "mental" && step == 0 && !done) { Text("这是家庭感受记录，不替代专业心理筛查、诊断或治疗。", color = tint, fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp)) }; if (!done) { if (category == "fitness") OutlinedTextField(value = answer, onValueChange = { answer = it; saveDraft(draftKey, it); validation = null }, label = { Text("本步骤记录") }, placeholder = { Text("填写后保存为草稿") }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp)) else StructuredObservationOptions(options, tint, answer, category == "mental" && step == 1, if (category == "vision" && step == 1) "用眼频率（可补充说明）" else if (category == "oral" && step == 1) "口腔习惯频率（可补充说明）" else if (category == "mental" && step == 1) "近一周家庭感受（可多选）" else if (category == "mental") "需要关注的程度" else if (category == "vision") "视力观察情况" else "口腔观察情况") { value -> answer = value; saveDraft(draftKey, value); validation = null }; Text("可退出后继续填写。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp)) }; validation?.let { Text(it, color = Color.Red, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp)) } } }
        if (done && category != "fitness") OutlinedButton(onClick = { val saved = state.local.familyHealthRecords["${selectedChild.id}-$category"]?.entries.orEmpty(); steps.forEachIndexed { index, label -> saveDraft(saved[label].orEmpty().ifBlank { state.local.drafts["assessment-${selectedChild.id}-$category-$index"].orEmpty() }, "assessment-${selectedChild.id}-$category-$index") }; step = 0; answer = state.local.drafts["assessment-${selectedChild.id}-$category-0"].orEmpty(); validation = null; done = false }, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp).fillMaxWidth()) { Icon(Icons.Filled.Edit, null); Spacer(Modifier.width(7.dp)); Text("重新填写家庭记录") }
        if (!done && category != "fitness" && hasArchivedRecord) { Text("正在编辑新版本；完成保存前，原健康记录仍会保留。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)); TextButton(onClick = { steps.indices.forEach { index -> clearDraft("assessment-${selectedChild.id}-$category-$index") }; clearDraft(progressKey); step = 0; answer = ""; validation = null; done = true }, modifier = Modifier.fillMaxWidth()) { Text("取消本次编辑，保留原记录") } }
        Button(onClick = { if (done) { nav.navigate(Destinations.Health) } else if (answer.isBlank()) { validation = "请选择或填写本步骤信息后再继续。" } else if (step < steps.lastIndex) { step += 1; answer = state.local.drafts["assessment-${selectedChild.id}-$category-$step"] ?: "" } else { val base = steps.indices.associate { index -> steps[index] to state.local.drafts["assessment-${selectedChild.id}-$category-$index"].orEmpty() }; val entries = if (category == "fitness") base else base + ("频率" to base[steps.getOrElse(1) { steps.first() }].orEmpty()) + ("严重程度" to base[steps.last()].orEmpty()); clearDraft(progressKey); completeAssessment(category, entries); done = true } }, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp).fillMaxWidth().height(48.dp)) { Text(if (done) "查看健康档案" else if (step == steps.lastIndex) "保存健康记录" else "保存并下一步") }
    } }
}

private fun observationOptions(category: String, step: Int): List<String> = when (category) {
    "vision" -> when (step) {
        0 -> listOf("孩子资料已确认", "需要补充观察")
        1 -> listOf("很少超过30分钟", "每天1小时左右", "每天2小时以上", "经常近距离用眼")
        else -> listOf("未发现明显异常", "偶尔眯眼/揉眼", "经常看不清", "已建议线下检查")
    }
    "oral" -> when (step) {
        0 -> listOf("孩子资料已确认", "需要补充观察")
        1 -> listOf("早晚刷牙", "每天一次", "偶尔漏刷", "需家长提醒")
        else -> listOf("未发现明显不适", "偶尔牙龈出血", "近期牙痛/龋齿", "已建议线下检查")
    }
    "mental" -> when (step) {
        0 -> listOf("已阅读说明", "稍后再填写")
        1 -> listOf("睡眠和情绪稳定", "偶尔低落/烦躁", "近期压力较明显", "需与老师沟通")
        else -> listOf("未发现持续困扰", "需要继续观察", "希望老师关注", "建议寻求专业支持")
    }
    else -> emptyList()
}

@Composable private fun StructuredObservationOptions(options: List<String>, tint: Color, value: String, allowsMultiple: Boolean = false, questionLabel: String = "", onValueChange: (String) -> Unit) {
    var note by rememberSaveable(value) { mutableStateOf(value.substringAfter("｜", "")) }
    Column(Modifier.fillMaxWidth().padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (questionLabel.isNotBlank()) Text(questionLabel, color = Color.Gray, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        options.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { option ->
                    val selectedValues = value.substringBefore("｜").split('、', ',', '，').map { it.trim() }.filter { it.isNotBlank() }
                    val selected = option in selectedValues
                    FilterChip(
                        selected = selected,
                        onClick = {
                            val nextValues = if (allowsMultiple) { if (selected) selectedValues.filter { it != option } else selectedValues + option } else listOf(option)
                            val selection = nextValues.joinToString("、")
                            val next = if (note.isBlank()) selection else "$selection｜$note"
                            onValueChange(next)
                        },
                        label = { Text(option, fontSize = 12.sp) },
                        modifier = Modifier.weight(1f).heightIn(min = 44.dp),
                        colors = FilterChipDefaults.filterChipColors(selectedContainerColor = tint.copy(alpha = .14f), selectedLabelColor = Navy)
                    )
                }
                repeat(2 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        OutlinedTextField(value = note, onValueChange = { text -> note = text; val selected = value.substringBefore("｜").takeIf { it.isNotBlank() } ?: options.firstOrNull().orEmpty(); onValueChange(if (text.isBlank()) selected else "$selected｜$text") }, label = { Text("补充说明（选填）") }, minLines = 1, modifier = Modifier.fillMaxWidth())
    }
}
