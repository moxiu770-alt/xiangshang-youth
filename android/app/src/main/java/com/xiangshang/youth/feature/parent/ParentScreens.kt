package com.xiangshang.youth.feature.parent

import android.content.Intent
import android.app.DatePickerDialog
import android.graphics.BitmapFactory
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

internal fun postSyncLabel(status: LocalSubmissionStatus): String = when (status) {
    LocalSubmissionStatus.Submitted -> "已同步"
    LocalSubmissionStatus.Failed -> "同步失败，可在设置中重试"
    LocalSubmissionStatus.Submitting -> "正在同步"
    LocalSubmissionStatus.Draft -> "未完成"
    LocalSubmissionStatus.PendingSync -> "已保存，联网后自动同步"
}
internal fun supportSyncLabel(status: LocalSubmissionStatus): String = when (status) {
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
    val bodyAssessmentActionTitle = when {
        state.local.bodyAssessmentDrafts[selectedChild.id] != null -> "继续身体测评"
        state.local.bodyAssessments[selectedChild.id] != null -> "查看身体测评结果"
        else -> "开始身体测评"
    }
    val bodyAssessmentCardDetail = when (bodyAssessmentActionTitle) {
        "继续身体测评" -> "已保存本次进度，可从上次步骤继续"
        "查看身体测评结果" -> "测评已完成，可查看结果与训练计划"
        else -> "优先完成身体测评，其他家庭记录可稍后填写"
    }
    Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight().background(Canvas).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(9.dp)) {
        ParentHeader(selectedChild.name, "${selectedChild.grade} · ${selectedChild.className} · 点击切换孩子", { nav.navigate(Destinations.Children) }, { nav.navigateSingleTop(RoleMessageDestination.resolve(UserRole.Parent)) }, state.unreadMessageCount, refreshDashboard, state.loading)
        Surface(Modifier.padding(horizontal = 12.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
            Column(Modifier.padding(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("孩子本周健康任务", color = Navy, fontWeight = FontWeight.Bold, fontSize = 17.sp); Text(bodyAssessmentCardDetail, color = Color.Gray, fontSize = 12.sp) }; Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, tint = Blue, modifier = Modifier.size(25.dp)) }
                Spacer(Modifier.height(8.dp)); Row { ParentMetric("体质", Icons.AutoMirrored.Filled.DirectionsRun, Blue, Modifier.weight(1f)) { nav.navigate(Destinations.BodyAssessment) }; Spacer(Modifier.width(7.dp)); ParentMetric("心理", Icons.Filled.Favorite, Color(0xFFFF6D9B), Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/mental") } }
                Spacer(Modifier.height(7.dp)); Row { ParentMetric("视力", Icons.Filled.RemoveRedEye, Green, Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/vision") }; Spacer(Modifier.width(7.dp)); ParentMetric("口腔", Icons.Filled.MedicalServices, Color(0xFFFFBD2E), Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/oral") } }
                Button(onClick = { nav.navigate(Destinations.BodyAssessment) }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp).heightIn(min = 48.dp), shape = RoundedCornerShape(12.dp)) { Text(bodyAssessmentActionTitle, fontSize = 14.sp, fontWeight = FontWeight.Bold) }
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
internal fun ParentSection(title: String, action: String, onAction: (() -> Unit)? = null) =
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
internal fun ParentActivities(nav: NavHostController) = Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
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
@Composable internal fun MiniActivity(image: Int, title: String, modifier: Modifier, onClick: () -> Unit) = Surface(onClick = onClick, modifier = modifier, color = Color.White, shape = RoundedCornerShape(8.dp)) { Column(Modifier.padding(4.dp)) { Image(painterResource(image), null, Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(6.dp)), contentScale = ContentScale.Crop); Text(title, color = Navy, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1, modifier = Modifier.padding(top = 3.dp)) } }
@Composable internal fun ParentTabScaffold(nav: NavHostController, selected: String, body: @Composable ColumnScope.() -> Unit) = Scaffold(containerColor = Canvas, bottomBar = { ParentBottomBar(nav, selected) }) { padding ->
    Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight().padding(horizontal = 12.dp).verticalScroll(rememberScrollState()), content = body)
    }
}
@Composable internal fun ParentBottomBar(nav: NavHostController, selected: String) = NavigationBar(containerColor = Color.White, tonalElevation = 1.dp) {
    fun go(route: String) { nav.navigate(route) { popUpTo(Destinations.Parent) { saveState = true }; launchSingleTop = true; restoreState = true } }
    ParentNavItem("首页", Icons.Filled.Home, selected == Destinations.Parent) { go(Destinations.Parent) }
    ParentNavItem("我的评测", Icons.AutoMirrored.Filled.Assignment, selected == Destinations.ParentEvaluations) { go(Destinations.ParentEvaluations) }
    ParentNavItem("我的课程", Icons.Filled.PlayCircle, selected == Destinations.Courses) { go(Destinations.Courses) }
    ParentNavItem("班级圈", Icons.Filled.Groups, selected == Destinations.Circle) { go(Destinations.Circle) }
    ParentNavItem("我的", Icons.Filled.Person, selected == Destinations.Account) { go(Destinations.Account) }
}
@Composable private fun RowScope.ParentNavItem(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, selected: Boolean, onClick: () -> Unit) = NavigationBarItem(selected = selected, onClick = onClick, icon = { Icon(icon, null) }, label = { Text(label, fontSize = 12.sp, maxLines = 1) }, modifier = Modifier.semantics { contentDescription = "$label${if (selected) "，当前页面" else ""}" })
