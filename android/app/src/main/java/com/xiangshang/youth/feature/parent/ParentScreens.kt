package com.xiangshang.youth.feature.parent

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
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
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
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
import androidx.navigation.NavHostController
import com.xiangshang.youth.R
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.model.Student
import com.xiangshang.youth.core.model.DiagnosisReport
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.shared.component.*

@Composable
fun ParentHomeScreen(state: AppUiState, nav: NavHostController, registerActivity: (String, String) -> Unit, bookExpert: (String, String, String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, refreshDashboard: () -> Unit = {}, submitActivityCommand: (String, String) -> Unit = registerActivity, submitExpertCommand: (String, String, String) -> Unit = bookExpert) {
    val context = LocalContext.current
    val reduceMotion = LocalReduceMotion.current
    val transition = rememberInfiniteTransition(label = "parent-campaign")
    val animatedCampaignScale by transition.animateFloat(1f, if (reduceMotion) 1f else 1.035f, infiniteRepeatable(tween(4200, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "campaign-drift")
    val campaignScale = if (reduceMotion) 1f else animatedCampaignScale
    var article by remember { mutableStateOf<String?>(null) }
    var wechatError by remember { mutableStateOf(false) }
    var activityDetail by remember { mutableStateOf(false) }
    var activityName by rememberSaveable { mutableStateOf("王女士") }
    var activityPhone by rememberSaveable { mutableStateOf("13800138000") }
    var activityConsented by rememberSaveable { mutableStateOf(false) }
    var activityError by remember { mutableStateOf<String?>(null) }
    val activityDraftKey = "activity-registration-health-growth-season-2026"
    var expert by remember { mutableStateOf<String?>(null) }; var expertDate by remember { mutableStateOf("2026-09-12 上午") }; var expertNote by remember { mutableStateOf("想了解孩子的运动发展建议。") }; var expertSubmitted by remember { mutableStateOf(false) }
    val expertDraftKey = expert?.let { "expert-booking-$it" }
    LaunchedEffect(expert, state.local.expertAppointments) {
        expertSubmitted = expert?.let { selected ->
            state.local.expertAppointments.any {
                it.expertName == selected &&
                    (it.status == com.xiangshang.youth.core.service.LocalSubmissionStatus.PendingSync ||
                        it.status == com.xiangshang.youth.core.service.LocalSubmissionStatus.Submitted)
            }
        } ?: false
        val draft = expertDraftKey?.let { state.local.drafts[it] }
            ?.split("|", limit = 2)
            ?.takeIf { it.size == 2 }
        if (draft != null) {
            expertDate = draft[0]
            expertNote = draft[1]
        } else if (expert != null) {
            expertDate = "2026-09-12 上午"
            expertNote = "想了解孩子的运动发展建议。"
        }
    }
    Scaffold(containerColor = Canvas, bottomBar = { ParentBottomBar(nav, Destinations.Parent) }) { contentPadding ->
    Box(Modifier.padding(contentPadding).fillMaxSize(), contentAlignment = Alignment.TopCenter) {
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = { refreshDashboard() }, dismiss = LocalDashboardClearError.current); return@Scaffold }
    if (state.loading || state.data == null) { LoadingState(); return@Scaffold }
    if (state.selectedChild == null) {
        Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            ParentHeader("请先绑定孩子", { nav.navigate(Destinations.ChildrenBinding) }, { nav.navigateSingleTop(Destinations.Notifications) }, state.unreadMessageCount)
            EmptyState("绑定孩子后才能查看测评、报告和课程。")
            Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("去绑定孩子") }
        }
        return@Scaffold
    }
    val selectedChild = state.selectedChild
    Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight().background(Canvas).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(9.dp)) {
        ParentHeader(selectedChild.name, { nav.navigate(Destinations.Children) }, { nav.navigateSingleTop(Destinations.Notifications) }, state.unreadMessageCount, refreshDashboard, state.loading)
        Surface(Modifier.padding(horizontal = 10.dp).fillMaxWidth().semantics { role = Role.Button; contentDescription = "打开健康成长季活动报名" }.clickable {
            state.local.drafts[activityDraftKey]?.split("|", limit = 3)?.takeIf { it.size >= 2 }?.let { values ->
                activityName = values[0]
                activityPhone = values[1]
                activityConsented = values.getOrNull(2) == "1"
            } ?: run {
                // A fresh form should reflect the authenticated family
                // account. Existing locally persisted input above always wins.
                activityName = state.profile?.name ?: activityName
                activityPhone = state.profile?.phone ?: activityPhone
            }
            activityDetail = true
        }, color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
            Box(Modifier.height(108.dp)) {
                Image(painterResource(R.drawable.parent_campaign), null, Modifier.fillMaxSize().scale(campaignScale), contentScale = ContentScale.Crop)
                Box(Modifier.fillMaxHeight().fillMaxWidth(.72f).background(Brush.horizontalGradient(listOf(Color.White.copy(.96f), Color.White.copy(.58f), Color.Transparent))))
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("向上少年健康成长季", color = Navy, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                    Text("综合测评 · 运动表现更出彩", color = Color.Gray, fontSize = 10.sp)
                    LinearProgressIndicator({ .75f }, Modifier.width(145.dp).height(5.dp).clip(CircleShape), color = Green, trackColor = Sky)
                    Text("测评于：7月16日 - 8月15日", color = Color.Gray, fontSize = 8.sp)
                }
            }
        }
        Surface(Modifier.padding(horizontal = 10.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
            Column(Modifier.padding(11.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("综合测评", color = Blue, fontWeight = FontWeight.Bold, fontSize = 17.sp); Text("运动表现、心理健康、口腔健康状况", color = Color.Gray, fontSize = 9.sp) }; Icon(Icons.Filled.WbSunny, null, tint = Color(0xFFFFBD2E)) }
                Spacer(Modifier.height(8.dp)); Row { ParentMetric("体质", Icons.AutoMirrored.Filled.DirectionsRun, Blue, Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/fitness") }; Spacer(Modifier.width(7.dp)); ParentMetric("心理", Icons.Filled.Favorite, Color(0xFFFF6D9B), Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/mental") } }
                Spacer(Modifier.height(7.dp)); Row { ParentMetric("视力", Icons.Filled.RemoveRedEye, Green, Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/vision") }; Spacer(Modifier.width(7.dp)); ParentMetric("口腔", Icons.Filled.MedicalServices, Color(0xFFFFBD2E), Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/oral") } }
                Button(onClick = { nav.navigate("${Destinations.Assessment}/fitness") }, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp).height(29.dp), contentPadding = PaddingValues(horizontal = 28.dp)) { Text("继续测评", fontSize = 10.sp) }
            }
        }
        ParentQuickActions(nav, state.local.checkedInToday)
        ParentSection("专家团队", "点击专家查看")
        Row(Modifier.padding(horizontal = 14.dp)) { listOf(R.drawable.expert_professor to "张教授", R.drawable.expert_doctor to "李医生", R.drawable.expert_coach to "王教练", R.drawable.expert_counselor to "刘主任").forEach { (image, name) -> Column(Modifier.weight(1f).semantics { role = Role.Button; contentDescription = "预约$name" }.clickable { expert = name }, horizontalAlignment = Alignment.CenterHorizontally) { Image(painterResource(image), null, Modifier.size(37.dp).clip(CircleShape), contentScale = ContentScale.Crop); Text(name, color = Navy, fontSize = 9.sp) } } }
        ParentSection("健康科普", "点击文章查看")
        listOf("儿童科学长高的 5 个关键习惯", "居家体态训练 10 分钟").forEach { title -> Surface(Modifier.padding(horizontal = 12.dp, vertical = 3.dp).fillMaxWidth().semantics { role = Role.Button; contentDescription = "阅读健康科普：$title" }.clickable { wechatError = false; article = title }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.AutoMirrored.Filled.MenuBook, null, tint = Green); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text(title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 11.sp); Text("健康专栏 · 今日推荐", color = Color.Gray, fontSize = 8.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } } }
    } } }
    val activityCommand = state.workflowStates["activity:health-growth-season-2026"] ?: WorkflowCommandState()
    val activityFailed = activityCommand.status == WorkflowCommandStatus.Failed
    val activitySaved = state.local.activityRegistered && !activityFailed && !activityCommand.isSubmitting
    LaunchedEffect(activityCommand.status) { if (activityCommand.status == WorkflowCommandStatus.Succeeded) clearDraft(activityDraftKey) }
    if (activityDetail) AlertDialog(onDismissRequest = { activityDetail = false }, title = { Text("向上少年健康成长季") }, text = { Column { Text("7 月 16 日–8 月 15 日。完成四项健康测评后可查看个性化成长报告。") ; if (activitySaved) { Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Green, modifier = Modifier.padding(top = 10.dp)); Text("报名信息已保存；活动开始前将通过消息中心通知您。", color = Green, fontSize = 11.sp) } else { OutlinedTextField(value = activityName, onValueChange = { activityName = it; saveDraft(activityDraftKey, "$it|$activityPhone|${if (activityConsented) "1" else "0"}"); activityError = null }, label = { Text("联系人姓名") }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp)); OutlinedTextField(value = activityPhone, onValueChange = { activityPhone = it; saveDraft(activityDraftKey, "$activityName|$it|${if (activityConsented) "1" else "0"}"); activityError = null }, label = { Text("手机号") }, modifier = Modifier.fillMaxWidth().padding(top = 7.dp)); Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 6.dp)) { Checkbox(checked = activityConsented, onCheckedChange = { activityConsented = it; saveDraft(activityDraftKey, "$activityName|$activityPhone|${if (it) "1" else "0"}"); activityError = null }); Text("已阅读活动说明并同意接收报名通知", fontSize = 10.sp) }; activityError?.let { Text(it, color = Color.Red, fontSize = 10.sp) }; if (activityFailed) Text(activityCommand.message ?: "报名提交失败，请重试", color = Color.Red, fontSize = 10.sp) } } }, confirmButton = { TextButton(onClick = { when { activityName.isBlank() -> activityError = "请填写联系人姓名。"; activityPhone.filter(Char::isDigit).length != 11 -> activityError = "请填写 11 位手机号。"; !activityConsented -> activityError = "请先确认活动说明和通知授权。"; else -> submitActivityCommand(activityName.trim(), activityPhone.trim()) } }, enabled = !activityCommand.isSubmitting && (!state.local.activityRegistered || activityFailed)) { if (activityCommand.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(if (activityFailed) "重新提交" else "确认报名") } }, dismissButton = { TextButton(onClick = { activityDetail = false }) { Text("关闭") } })
    expert?.let { name -> val expertCommand = state.workflowStates["expert:$name"] ?: WorkflowCommandState(); val expertFailed = expertCommand.status == WorkflowCommandStatus.Failed; val expertSaved = expertSubmitted && !expertFailed && !expertCommand.isSubmitting; LaunchedEffect(expertCommand.status) { if (expertCommand.status == WorkflowCommandStatus.Succeeded) expertDraftKey?.let(clearDraft) }; AlertDialog(onDismissRequest = { expert = null; expertSubmitted = false }, title = { Text("$name · 健康成长专家") }, text = { if (expertSaved) Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Green, modifier = Modifier.size(42.dp)); Text("预约信息已保存，专家团队将尽快与您联系。", color = Navy, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp)) } else Column { Text("专业领域：儿童运动发展与健康评估。请填写咨询时间和需求。"); OutlinedTextField(value = expertDate, onValueChange = { value -> expertDate = value; expertDraftKey?.let { saveDraft(it, "$value|$expertNote") } }, label = { Text("期望咨询时间") }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)); OutlinedTextField(value = expertNote, onValueChange = { value -> expertNote = value; expertDraftKey?.let { saveDraft(it, "$expertDate|$value") } }, label = { Text("咨询说明") }, minLines = 2, modifier = Modifier.fillMaxWidth().padding(top = 7.dp)); if (expertFailed) Text(expertCommand.message ?: "预约提交失败，请重试", color = Color.Red, fontSize = 10.sp) } }, confirmButton = { TextButton(enabled = !expertCommand.isSubmitting && (expertSubmitted || (expertDate.isNotBlank() && expertNote.isNotBlank())), onClick = { if (expertSaved) { expert = null; expertSubmitted = false } else submitExpertCommand(name, expertDate.trim(), expertNote.trim()) }) { if (expertCommand.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(if (expertSaved) "完成" else if (expertFailed) "重新提交" else "提交预约") } }, dismissButton = if (expertSaved) null else ({ TextButton(onClick = { expert = null }) { Text("取消") } })) }
    article?.let { title -> AlertDialog(onDismissRequest = { article = null }, title = { Text(title) }, text = { Column { Text("完整内容由“向上少年健康成长”微信公众号提供。请在微信中搜索公众号查看。"); if (wechatError) Text("当前设备未安装微信，请直接搜索公众号：向上少年健康成长。", color = Color(0xFFD32F2F), fontSize = 11.sp, modifier = Modifier.padding(top = 10.dp)) } }, confirmButton = { TextButton(onClick = { val opened = runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("weixin://"))) }.isSuccess; if (opened) article = null else wechatError = true }) { Text(if (wechatError) "重试打开微信" else "打开微信") } }, dismissButton = { TextButton(onClick = { article = null }) { Text("关闭") } }) }
}

@Composable private fun ParentHeader(name: String, onClick: () -> Unit, onMessages: (() -> Unit)? = null, unreadCount: Int = 0, onRefresh: (() -> Unit)? = null, isRefreshing: Boolean = false) = Row(Modifier.fillMaxWidth().background(Color.White).padding(horizontal = 14.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) { Surface(Modifier.size(40.dp), color = Color(0xFF16AFA5), shape = CircleShape) { Text(name.take(1), color = Color.White, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 9.dp)) }; Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text(name, color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp); Text("三年级2班 · 点击切换孩子", color = Color.Gray, fontSize = 9.sp) }; IconButton(onClick = onClick) { Icon(Icons.Filled.ChevronRight, "切换孩子", tint = Blue) }; onRefresh?.let { action -> IconButton(onClick = action, enabled = !isRefreshing) { if (isRefreshing) CircularProgressIndicator(Modifier.size(17.dp), color = Blue, strokeWidth = 2.dp) else Icon(Icons.Filled.Refresh, "刷新数据", tint = Navy, modifier = Modifier.size(19.dp)) } }; onMessages?.let { action -> IconButton(onClick = action) { BadgedBox(badge = { if (unreadCount > 0) Badge(containerColor = Color.Red, modifier = Modifier.size(6.dp)) {} }) { Icon(Icons.Filled.NotificationsNone, contentDescription = "消息通知", tint = Navy, modifier = Modifier.size(20.dp)) } } } }

@Composable fun NotificationsScreen(state: AppUiState, nav: NavHostController, markMessageRead: (String) -> Unit, markAllMessagesRead: () -> Unit) = AppScaffold("消息通知", onBack = { nav.popBackStack() }) {
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@AppScaffold }
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    if (state.data.messages.isEmpty()) { EmptyState("暂无消息通知"); return@AppScaffold }
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) { Text("全部通知", color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp); Spacer(Modifier.weight(1f)); if (state.unreadMessageCount > 0) TextButton(onClick = markAllMessagesRead, contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp), modifier = Modifier.semantics { contentDescription = "将全部通知标记为已读" }) { Text("全部已读", fontSize = 10.sp) }; Text("未读 ${state.unreadMessageCount}", color = Blue, fontSize = 10.sp) }
    state.data.messages.forEachIndexed { index, item ->
        var detail by remember { mutableStateOf(false) }
        Surface(Modifier.fillMaxWidth().padding(vertical = 4.dp).semantics { role = Role.Button; contentDescription = "查看通知：${item.title}" }.clickable { markMessageRead(item.id); detail = true }, color = Color.White, shape = RoundedCornerShape(11.dp), shadowElevation = 1.dp) {
            Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (item.category == "报告") Icons.Filled.Description else Icons.Filled.Notifications, null, tint = if (index == 0) Blue else Color(0xFFFF9D25), modifier = Modifier.size(25.dp))
                Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(item.title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); if (!item.isRead && item.id !in state.local.readMessageIds) Spacer(Modifier.width(5.dp)); if (!item.isRead && item.id !in state.local.readMessageIds) Box(Modifier.size(5.dp).background(Color.Red, CircleShape)) }; Text(item.content, color = Color.Gray, fontSize = 9.sp, maxLines = 2); Text("${item.category} · ${item.time}", color = Color.Gray, fontSize = 8.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.size(15.dp))
            }
        }
        if (detail) AlertDialog(onDismissRequest = { detail = false }, title = { Text(item.title) }, text = { Column { Text(item.content); Text("${item.category} · ${item.time}", color = Color.Gray, fontSize = 11.sp, modifier = Modifier.padding(top = 10.dp)) } }, confirmButton = { TextButton(onClick = { detail = false }) { Text("关闭") } })
    }
}
@Composable private fun ParentMetric(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, modifier: Modifier, onClick: () -> Unit) = Surface(modifier.semantics { role = Role.Button; contentDescription = "打开${label}测评" }.clickable(onClick = onClick), color = color.copy(.08f), shape = RoundedCornerShape(9.dp)) { Row(Modifier.padding(9.dp), verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = color, modifier = Modifier.size(21.dp)); Spacer(Modifier.width(8.dp)); Column { Text(label, color = Navy, fontWeight = FontWeight.Bold, fontSize = 10.sp); Text(if (label == "体质") "继续测评" else "开始测评", color = Color.Gray, fontSize = 8.sp) } } }
@Composable private fun ParentAction(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, modifier: Modifier, onClick: () -> Unit) = Column(modifier.semantics { role = Role.Button; contentDescription = label }, horizontalAlignment = Alignment.CenterHorizontally) { FilledIconButton(onClick = onClick, modifier = Modifier.size(39.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = color)) { Icon(icon, contentDescription = label, modifier = Modifier.size(20.dp)) }; Text(label, color = Navy, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, maxLines = 1) }

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
            Text(action, color = Color.Gray, fontSize = 10.sp)
        } else {
            TextButton(onClick = onAction, contentPadding = PaddingValues(horizontal = 2.dp, vertical = 0.dp)) {
                Text("$action ›", fontSize = 10.sp)
            }
        }
    }

@Composable
fun ChildrenScreen(state: AppUiState, nav: NavHostController, bindChild: (String, String) -> Boolean, choose: (Student) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, onBound: () -> Unit = {}) = AppScaffold("孩子管理", onBack = { nav.popBackStack() }) {
    var bindingOpen by rememberSaveable { mutableStateOf(false) }
    var childName by rememberSaveable { mutableStateOf(state.local.drafts["child-binding-name"].orEmpty()) }
    var bindingCode by rememberSaveable { mutableStateOf(state.local.drafts["child-binding-code"].orEmpty()) }
    var bindingError by remember { mutableStateOf<String?>(null) }
    var bindingHelpOpen by rememberSaveable { mutableStateOf(false) }
    val data = state.data
    val boundIds = state.local.boundChildIds
    val children = data?.students?.filter { it.id in boundIds }.orEmpty()
    when {
        state.error != null && state.data == null -> ErrorState(state.error, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current)
        state.loading || state.data == null -> LoadingState()
        else -> {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) { Text("已绑定孩子 ${children.size} 人", color = Navy, fontWeight = FontWeight.Bold); Spacer(Modifier.weight(1f)); Button(onClick = { bindingOpen = true }) { Text("绑定孩子", fontSize = 11.sp) } }
            if (children.isEmpty()) {
                EmptyState("暂无绑定孩子，请使用学校提供的绑定码添加孩子。")
            } else {
                children.forEach { child -> StudentCard(child) { choose(child) }; Spacer(Modifier.height(8.dp)) }
            }
        }
    }
    if (bindingOpen) AlertDialog(
        onDismissRequest = { bindingOpen = false },
        title = { Text("绑定孩子") },
        text = { Column { OutlinedTextField(value = childName, onValueChange = { childName = it; saveDraft("child-binding-name", it); bindingError = null }, label = { Text("孩子姓名") }, modifier = Modifier.fillMaxWidth()); OutlinedTextField(value = bindingCode, onValueChange = { bindingCode = it; saveDraft("child-binding-code", it); bindingError = null }, label = { Text("学校绑定码") }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)); Text("绑定码由学校或班主任提供，用于确认家庭与孩子关系。", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.padding(top = 7.dp)); TextButton(onClick = { bindingHelpOpen = true }, contentPadding = PaddingValues(horizontal = 0.dp, vertical = 0.dp), modifier = Modifier.semantics { contentDescription = "查看绑定码获取说明" }) { Text("绑定码在哪找？", color = Blue, fontSize = 10.sp) }; bindingError?.let { Text(it, color = Color.Red, fontSize = 10.sp, modifier = Modifier.padding(top = 5.dp)) } } },
        confirmButton = { TextButton(onClick = { if (bindChild(childName, bindingCode)) { childName = ""; bindingCode = ""; clearDraft("child-binding-name"); clearDraft("child-binding-code"); bindingError = null; bindingOpen = false; onBound() } else bindingError = "姓名或绑定码不匹配，请核对后重试。" }) { Text("确认绑定") } },
        dismissButton = { TextButton(onClick = { bindingOpen = false }) { Text("取消") } }
    )
    if (bindingHelpOpen) AlertDialog(
        onDismissRequest = { bindingHelpOpen = false },
        title = { Text("绑定码获取说明") },
        text = { Text("绑定码由学校后台生成。请联系班主任或学校管理员，在“家长绑定管理/学生档案”中获取孩子专属绑定码。若学校尚未发放，请先向班主任申请；平台不会自动猜测或生成绑定码。", color = Color.Gray, fontSize = 11.sp) },
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
    ParentHeader(selectedChild.name, onClick = { nav.navigate(Destinations.Children) })
    Spacer(Modifier.height(8.dp))
    Surface(Modifier.fillMaxWidth(), color = Sky, shape = RoundedCornerShape(12.dp)) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            val progress = ((report?.scores?.size ?: 0) / 7f).coerceIn(0f, 1f)
            val score = report?.scores?.sumOf { it.score } ?: 0.0
            CircularProgressIndicator({ progress }, Modifier.size(70.dp), color = Blue, strokeWidth = 7.dp)
            Spacer(Modifier.width(12.dp))
            Column {
                Text("健康综合测评", color = Navy, fontWeight = FontWeight.Bold)
                Text("覆盖孩子的运动与健康成长情况", color = Color.Gray, fontSize = 9.sp)
                LinearProgressIndicator({ progress }, Modifier.width(140.dp).padding(top = 7.dp), color = Green)
                Text("已完成 ${report?.scores?.size ?: 0} 项 · 进度 ${(progress * 100).toInt()}% · 总分 ${String.format(java.util.Locale.US, "%.1f", score)}", color = Blue, fontSize = 9.sp)
            }
        }
    }
    Spacer(Modifier.height(10.dp))
    ParentSection("健康测评结果", "查看详细报告") { nav.navigate(Destinations.Report) }
    Row {
        ScoreSummaryCard("体质", if ((report?.student?.totalScore ?: 35.0) >= 25) "良好" else "需关注", report?.date ?: "待测评") { nav.navigate(Destinations.Report) }
        Spacer(Modifier.width(7.dp))
        ScoreSummaryCard("视力", if ((report?.scores?.firstOrNull()?.score ?: 0.0) >= 3) "正常" else "需关注", report?.date ?: "待测评") { nav.navigate(Destinations.Report) }
    }
    Spacer(Modifier.height(10.dp))
    Text("体质成长档案", color = Navy, fontWeight = FontWeight.Bold)
    Surface(Modifier.fillMaxWidth().padding(top = 6.dp), color = Color.White, shape = RoundedCornerShape(10.dp)) {
        Column(Modifier.padding(11.dp)) {
            Text("身高成长趋势", color = Navy, fontWeight = FontWeight.Bold, fontSize = 11.sp)
            Row(Modifier.fillMaxWidth().height(72.dp).padding(top = 8.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                listOf(108, 114, 120, 126, 132).forEach { height ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.width(22.dp).height((height - 96).dp).background(if (height == 132) Blue else Blue.copy(.32f), RoundedCornerShape(4.dp)))
                        Text("$height", color = Color.Gray, fontSize = 7.sp)
                    }
                }
            }
            Text("遗传身高区间：165–173 cm · 运动表现持续向好", color = Color.Gray, fontSize = 8.sp)
        }
    }
    Spacer(Modifier.height(10.dp))
    Text("详细报告", color = Navy, fontWeight = FontWeight.Bold)
    listOf("体质" to "脊柱姿态 · 遗传身高 · 运动表现", "视力" to "屈光筛查 · 用眼习惯", "口腔" to "龋齿风险 · 牙列发育", "心理" to "情绪状态 · 同伴适应").forEach { (name, detail) ->
        Surface(Modifier.fillMaxWidth().padding(top = 6.dp).semantics { role = Role.Button; contentDescription = "查看${name}健康报告" }.clickable { nav.navigate(Destinations.Report) }, color = Color.White, shape = RoundedCornerShape(9.dp)) {
            Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (name == "体质") Icons.AutoMirrored.Filled.DirectionsRun else if (name == "视力") Icons.Filled.RemoveRedEye else if (name == "口腔") Icons.Filled.MedicalServices else Icons.Filled.Favorite, null, tint = Blue)
                Spacer(Modifier.width(9.dp))
                Column(Modifier.weight(1f)) { Text(name, color = Navy, fontWeight = FontWeight.Bold, fontSize = 11.sp); Text(detail, color = Color.Gray, fontSize = 8.sp) }
                Text("良好 ›", color = Green, fontSize = 9.sp)
            }
        }
    }
}
@Composable fun ParentMessagesScreen(state: AppUiState, nav: NavHostController, markMessageRead: (String) -> Unit, markAllMessagesRead: () -> Unit) {
    var selectedTitle by remember { mutableStateOf<String?>(null) }
    var selectedContent by remember { mutableStateOf("") }
    var selectedTime by remember { mutableStateOf("") }
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }
    ParentTabScaffold(nav, Destinations.Messages) {
    val data = state.data
    val dashboardError = state.error
    if (dashboardError != null && data == null) {
        ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current)
        return@ParentTabScaffold
    }
    if (state.loading || data == null) {
        LoadingState()
        return@ParentTabScaffold
    }
    if (state.unreadMessageCount > 0) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            TextButton(onClick = markAllMessagesRead, contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp), modifier = Modifier.semantics { contentDescription = "将全部消息标记为已读" }) { Text("全部已读", fontSize = 10.sp) }
        }
    }
    Row(Modifier.fillMaxWidth().padding(bottom = 7.dp), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        listOf("消息提醒", "系统通知").forEachIndexed { index, title ->
            FilterChip(selected = selectedTab == index, onClick = { selectedTab = index }, label = { Text(title, fontSize = 10.sp) }, modifier = Modifier.weight(1f))
        }
    }
    val visibleMessages = data.messages.filter { message -> if (selectedTab == 0) message.category != "系统" else message.category == "系统" }.ifEmpty { if (selectedTab == 0) data.messages else emptyList() }
    when {
        data.messages.isEmpty() || visibleMessages.isEmpty() -> EmptyState(if (selectedTab == 0) "暂无消息提醒" else "暂无系统通知")
        else -> visibleMessages.forEachIndexed { index, item -> Surface(Modifier.fillMaxWidth().padding(vertical = 4.dp).semantics { role = Role.Button; contentDescription = "查看消息：${item.title}" }.clickable { markMessageRead(item.id); selectedTitle = item.title; selectedContent = item.content; selectedTime = item.time }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(11.dp)) { Icon(if (index % 2 == 0) Icons.Filled.Warning else Icons.Filled.Notifications, null, tint = if (index % 2 == 0) Color.Red else Blue); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(item.title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); if (!item.isRead && item.id !in state.local.readMessageIds) Box(Modifier.size(5.dp).background(Color.Red, CircleShape).padding(start = 4.dp)) }; Text(item.content, color = Color.Gray, fontSize = 9.sp, maxLines = 1); Text(item.category, color = Blue, fontSize = 8.sp) }; Text(item.time, color = Color.Gray, fontSize = 8.sp) } } }
    }
}
    selectedTitle?.let { title -> AlertDialog(onDismissRequest = { selectedTitle = null }, title = { Text(title) }, text = { Column { Text(selectedContent); Text(selectedTime, color = Color.Gray, fontSize = 11.sp, modifier = Modifier.padding(top = 10.dp)) } }, confirmButton = { TextButton(onClick = { selectedTitle = null }) { Text("关闭") } }) }
}
@Composable
fun HealthProfileScreen(state: AppUiState, nav: NavHostController, checkInToday: () -> Unit) {
    var checkInDetail by rememberSaveable { mutableStateOf(false) }
    ParentTabScaffold(nav, Destinations.Health) {
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@ParentTabScaffold }
    if (state.loading || state.data == null) { LoadingState(); return@ParentTabScaffold }
    if (state.selectedChild == null) { EmptyState("暂无健康档案，请先完成孩子绑定。"); Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }, modifier = Modifier.align(Alignment.CenterHorizontally)) { Text("去绑定孩子") }; return@ParentTabScaffold }
    ParentSection("健康报告", "查看全部报告") { nav.navigate(Destinations.Report) }
    Row { ScoreSummaryCard("体质", "良好", "本月", onClick = { nav.navigate(Destinations.Report) }); Spacer(Modifier.width(6.dp)); ScoreSummaryCard("视力", "正常", "本月", onClick = { nav.navigate(Destinations.Report) }); Spacer(Modifier.width(6.dp)); ScoreSummaryCard("口腔", "良好", "本月", onClick = { nav.navigate(Destinations.Report) }) }
    Spacer(Modifier.height(9.dp))
    Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(11.dp)) {
        Column(Modifier.padding(11.dp)) {
            // Keep the calendar header actionable; a static label here made
            // the Android health page diverge from the iOS interaction model.
            ParentSection("本月打卡", "查看记录") { checkInDetail = true }
            Text("日    一    二    三    四    五    六", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
            Text("7     8     9    10    11    12    13\n14   15   16   17   18   19   20\n21   22   23   24   25   26   27", color = Green, fontSize = 10.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
            Button(onClick = { checkInToday(); checkInDetail = true }, enabled = !state.local.checkedInToday, modifier = Modifier.fillMaxWidth().padding(top = 9.dp)) { Text(if (state.local.checkedInToday) "今日已打卡" else "确认今日运动打卡") }
        }
    }
    Spacer(Modifier.height(9.dp))
    ParentActivities(nav)
    }
    if (checkInDetail) {
        AlertDialog(
            onDismissRequest = { checkInDetail = false },
            title = { Text("本月运动打卡记录") },
            text = { Text(if (state.local.checkedInToday) "本月已完成 15 次运动打卡，今天已打卡。" else "本月已完成 15 次运动打卡，今天还可以继续记录。", color = Color.Gray) },
            confirmButton = { TextButton(onClick = { checkInDetail = false }) { Text("知道了") } }
        )
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
            Column(Modifier.weight(1f)) { Text("为孩子推荐", color = Color.Gray, fontSize = 9.sp); Text("青少年体姿改善课程", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp); Text("每周 2 次 · 适合 7-10 岁", color = Green, fontSize = 8.sp) }
            Text("查看课程", color = Color.White, fontSize = 9.sp, modifier = Modifier.background(Color(0xFFFFB521), CircleShape).padding(horizontal = 9.dp, vertical = 5.dp))
        }
    }
}
@Composable private fun MiniActivity(image: Int, title: String, modifier: Modifier, onClick: () -> Unit) = Surface(onClick = onClick, modifier = modifier, color = Color.White, shape = RoundedCornerShape(8.dp)) { Column(Modifier.padding(4.dp)) { Image(painterResource(image), null, Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(6.dp)), contentScale = ContentScale.Crop); Text(title, color = Navy, fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1, modifier = Modifier.padding(top = 3.dp)) } }
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
@Composable private fun RowScope.ParentNavItem(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, selected: Boolean, onClick: () -> Unit) = NavigationBarItem(selected = selected, onClick = onClick, icon = { Icon(icon, null) }, label = { Text(label, fontSize = 9.sp) }, modifier = Modifier.semantics { contentDescription = "$label${if (selected) "，当前页面" else ""}" })

@Composable fun ParentCoursesScreen(state: AppUiState, nav: NavHostController, updateCourseProgress: (String, Float) -> Unit, sendSupport: (String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, openSupport: Boolean = false, submitSupport: (String) -> Unit = sendSupport, clearWorkflow: (String) -> Unit = {}) {
    var paid by remember { mutableStateOf(false) }
    var detail by rememberSaveable(openSupport) { mutableStateOf<String?>(if (openSupport) "客服咨询" else null) }
    var selectedCourse by rememberSaveable { mutableStateOf<String?>(null) }
    var catalogOpen by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(openSupport) { if (openSupport) clearWorkflow("support") }
    ParentTabScaffold(nav, Destinations.Courses) {
        val dashboardError = state.error
        if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@ParentTabScaffold }
        if (state.loading || state.data == null) { LoadingState(); return@ParentTabScaffold }
        if (state.selectedChild == null) { EmptyState("暂无孩子档案，请先完成孩子绑定。"); Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("去绑定孩子") }; return@ParentTabScaffold }
        val selectedChild = state.selectedChild
        Text("我的课程", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 10.dp)); Text("${selectedChild.name} · ${selectedChild.className}", color = Color.Gray, fontSize = 10.sp); Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth().background(Sky, RoundedCornerShape(9.dp))) { listOf("公益课程", "学校课程").forEachIndexed { index, text -> Text(text, color = if (paid == (index == 1)) Color.White else Blue, fontWeight = FontWeight.Bold, fontSize = 11.sp, textAlign = TextAlign.Center, modifier = Modifier.weight(1f).padding(8.dp).semantics { role = Role.Tab; contentDescription = "切换到$text" }.background(if (paid == (index == 1)) Blue else Color.Transparent, RoundedCornerShape(8.dp)).clickable { paid = index == 1 }) } }
        Spacer(Modifier.height(10.dp)); ParentSection(if (paid) "精选学校课程" else "公益课堂", "全部课程") { catalogOpen = true }
        val items = if (paid) {
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
        items.chunked(2).forEach { row -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { (title, icon) -> Surface(Modifier.weight(1f).height(105.dp).semantics { role = Role.Button; contentDescription = "打开课程：$title" }.clickable { selectedCourse = title }, color = Sky, shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(12.dp)) { Icon(icon, null, tint = Blue); Spacer(Modifier.height(8.dp)); Text(title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); val progress = state.local.courseProgress[title] ?: 0f; Text(if (progress > 0f) "学习进度 ${(progress * 100).toInt()}%" else if (paid) "校内课程 · 查看课程" else "公益 · 立即学习", color = Green, fontSize = 9.sp) } } }; if (row.size == 1) Spacer(Modifier.weight(1f)) }; Spacer(Modifier.height(8.dp)) }
        Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "打开课程咨询" }.clickable { clearWorkflow("support"); detail = "客服咨询" }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.AutoMirrored.Filled.Message, null, tint = Blue); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text("课程咨询", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("客服老师会在工作时间回复您", color = Color.Gray, fontSize = 9.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } }
    }
    detail?.let { title -> SimpleDialog(title = title, messages = state.local.supportMessages, drafts = state.local.drafts, send = sendSupport, submit = submitSupport, command = state.workflowStates["support"] ?: WorkflowCommandState(), commandDriven = title == "客服咨询", saveDraft = saveDraft, clearDraft = clearDraft, dismiss = { detail = null }) }
    if (catalogOpen) CourseCatalogDialog(
        paid = paid,
        onOpenCourse = { title -> catalogOpen = false; selectedCourse = title },
        dismiss = { catalogOpen = false }
    )
    selectedCourse?.let { title -> CourseLessonDialog(
        title = title,
        initialProgress = state.local.courseProgress[title] ?: 0f,
        updateCourseProgress = updateCourseProgress,
        dismiss = { selectedCourse = null }
    ) }
}

/** A course is a real local workflow even while the production media endpoint
 * is unavailable: progress is only recorded after the learner starts it. */
@Composable
private fun CourseLessonDialog(
    title: String,
    initialProgress: Float,
    updateCourseProgress: (String, Float) -> Unit,
    dismiss: () -> Unit
) {
    var progress by rememberSaveable(title) { mutableFloatStateOf(initialProgress) }
    var playing by rememberSaveable(title) { mutableStateOf(false) }
    val nextProgress = (progress + .25f).coerceAtMost(1f)
    AlertDialog(
        onDismissRequest = {
            if (progress > initialProgress) updateCourseProgress(title, progress)
            dismiss()
        },
        title = { Text(title) },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Icon(if (playing) Icons.Filled.PauseCircle else Icons.Filled.PlayCircle, null, tint = Blue, modifier = Modifier.size(56.dp))
                Text("课程视频已准备，学习进度会保存在本机并在联网后同步。", color = Color.Gray, fontSize = 11.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
                LinearProgressIndicator({ progress }, Modifier.fillMaxWidth().padding(top = 16.dp).height(7.dp).clip(CircleShape), color = Green, trackColor = Sky)
                Text("学习进度 ${(progress * 100).toInt()}%", color = Green, fontSize = 11.sp, modifier = Modifier.padding(top = 7.dp))
            }
        },
        confirmButton = {
            TextButton(onClick = {
                playing = !playing
                if (playing) {
                    progress = nextProgress
                    updateCourseProgress(title, progress)
                }
            }) {
                Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, null, modifier = Modifier.size(17.dp))
                Spacer(Modifier.width(4.dp))
                Text(if (playing) "暂停学习" else if (progress >= 1f) "再次学习" else "播放课程")
            }
        },
        dismissButton = { TextButton(onClick = { if (progress > initialProgress) updateCourseProgress(title, progress); dismiss() }) { Text("完成") } }
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
                Text("选择课程后可开始学习，学习进度将保存在本机。", color = Color.Gray, fontSize = 11.sp)
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

@Composable fun ParentClassCircleScreen(state: AppUiState, nav: NavHostController, publishPost: (String, String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, toggleLike: (String) -> Unit, addComment: (String, String) -> Unit, submitPost: (String, String) -> Unit = publishPost, clearWorkflow: (String) -> Unit = {}) {
    var detail by remember { mutableStateOf<String?>(null) }
    var filter by rememberSaveable { mutableIntStateOf(0) }
    var commentPost by rememberSaveable { mutableStateOf<String?>(null) }
    var comment by rememberSaveable { mutableStateOf("") }
    var commentSubmitted by rememberSaveable { mutableStateOf(false) }
    val pinnedAnnouncementId = "teacher-announcement"
    val pinnedAnnouncementLiked = pinnedAnnouncementId in state.local.likedPostIds
    val context = LocalContext.current
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
        Text("${selectedChild.name} · ${selectedChild.className} · 42人", color = Color.Gray, fontSize = 10.sp)
        Surface(Modifier.fillMaxWidth().padding(top = 9.dp), color = Sky, shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("本班家校圈", color = Navy, fontWeight = FontWeight.Bold, fontSize = 15.sp); Text("分享运动成长，和老师保持联系", color = Color.Gray, fontSize = 9.sp) }; Column(horizontalAlignment = Alignment.End) { Text("42", color = Blue, fontWeight = FontWeight.Bold, fontSize = 20.sp); Text("班级成员", color = Color.Gray, fontSize = 8.sp) } } }
        Row(Modifier.fillMaxWidth().padding(top = 9.dp), horizontalArrangement = Arrangement.spacedBy(7.dp)) { listOf("全部", "老师动态", "家长分享").forEachIndexed { index, title -> FilterChip(selected = filter == index, onClick = { filter = index }, label = { Text(title, fontSize = 10.sp) }) } }
        Button(onClick = { clearWorkflow("post:王女士"); detail = "发布班级动态" }, modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp)) { Icon(Icons.Filled.Edit, null); Spacer(Modifier.width(7.dp)); Text("发布班级动态") }
        val posts = state.local.classPosts.filter { filter == 0 || (filter == 1 && it.author.contains("老师")) || (filter == 2 && !it.author.contains("老师")) }
        // Keep the teacher announcement at the top of the whole/teacher feeds.
        // It is intentionally excluded only from the parent-sharing filter.
        if (filter != 2) {
                Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.School, null, tint = Blue); Spacer(Modifier.width(8.dp))
                            Column { Text("李老师", color = Blue, fontWeight = FontWeight.Bold, fontSize = 11.sp); Text("今天 08:30 · 置顶通知", color = Color.Gray, fontSize = 8.sp) }
                        }
                        Text("本周运动打卡已开启，欢迎家长分享孩子的练习瞬间。", color = Navy, fontSize = 11.sp, modifier = Modifier.padding(top = 7.dp))
                        Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            Text(if (pinnedAnnouncementLiked) "已赞 13" else "♡ 12", color = if (pinnedAnnouncementLiked) Blue else Color.Gray, fontSize = 9.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = if (pinnedAnnouncementLiked) "取消点赞" else "点赞" }.clickable { toggleLike(pinnedAnnouncementId) })
                            Text("评论 ${3 + state.local.postComments[pinnedAnnouncementId].orEmpty().size}", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "评论置顶通知" }.clickable { openComment(pinnedAnnouncementId) })
                            Spacer(Modifier.weight(1f)); Text("班级通知", color = Blue, fontSize = 9.sp)
                        }
                        ClassCircleCommentPreview(state.local.postComments[pinnedAnnouncementId].orEmpty())
                    }
                }
        }
        posts.forEach { post ->
            Surface(Modifier.padding(vertical = 4.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp), shadowElevation = 1.dp) { Column(Modifier.padding(11.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.AccountCircle, null, tint = Sky, modifier = Modifier.size(28.dp)); Spacer(Modifier.width(8.dp)); Column { Text(post.author, color = Blue, fontWeight = FontWeight.Bold, fontSize = 10.sp); Text("刚刚发布 · 本班可见", color = Color.Gray, fontSize = 8.sp) }; Spacer(Modifier.weight(1f)) }
                Text(post.content, color = Navy, fontSize = 11.sp, modifier = Modifier.padding(top = 5.dp))
                Row(Modifier.fillMaxWidth().padding(top = 7.dp), horizontalArrangement = Arrangement.spacedBy(15.dp)) { Text(if (post.id in state.local.likedPostIds) "已赞" else "点赞", color = if (post.id in state.local.likedPostIds) Blue else Color.Gray, fontSize = 9.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = if (post.id in state.local.likedPostIds) "取消点赞" else "点赞" }.clickable { toggleLike(post.id) }); Text("评论", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "评论这条动态" }.clickable { openComment(post.id) }); Spacer(Modifier.weight(1f)); Text("分享", color = Blue, fontSize = 9.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "分享这条动态" }.clickable { runCatching { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, post.content) }, "分享班级动态")) } }) }
                ClassCircleCommentPreview(state.local.postComments[post.id].orEmpty())
            } }
        }
        ParentSection("班级之星", "榜单展示") { detail = "班级之星榜单" }; Row(Modifier.fillMaxWidth()) { listOf("勤劳之星" to "陈乐乐", "运动之星" to "王小明", "阅读之星" to "李安然").forEach { (star, name) -> Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Filled.Star, null, tint = Color(0xFFFFBD2E)); Text(star, color = Navy, fontSize = 9.sp); Text(name, color = Color.Gray, fontSize = 8.sp) } } }
        Spacer(Modifier.height(10.dp)); Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(12.dp)) { ParentSection("本月打卡", "记录自动同步") { detail = "本月运动打卡记录" }; Text("✓  ✓  ✓  ✓  ·  ✓  ✓  ·  ✓  ✓  ✓  ✓  ✓  ·  ✓", color = Green, fontSize = 15.sp); Text("本月已完成 15 次运动打卡", color = Color.Gray, fontSize = 9.sp) } }
        Spacer(Modifier.height(10.dp)); ParentSection("延时课堂精彩瞬间", "点击课程查看") { nav.navigate(Destinations.Courses) }; Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) { MiniActivity(R.drawable.activity_football, "足球启蒙", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) }; MiniActivity(R.drawable.activity_classroom, "健康课堂", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) }; MiniActivity(R.drawable.activity_balance, "亲子平衡", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) } }
        Spacer(Modifier.height(10.dp)); ParentSection("推荐课程", "查看详情") { nav.navigate(Destinations.Courses) }; ParentActivities(nav); Spacer(Modifier.height(8.dp)); ParentSection("我的课程", "全部课程") { nav.navigate(Destinations.Courses) }; Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.CalendarMonth, null, tint = Green); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text("我的运动安排", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("周三 15:30–16:30 · 足球基础训练", color = Color.Gray, fontSize = 9.sp) }; Text("已预约", color = Green, fontSize = 9.sp) } }
    }
    detail?.let { title -> SimpleDialog(title = title, drafts = state.local.drafts, send = { content -> if (title == "发布班级动态") publishPost("王女士", content) }, submit = { content -> if (title == "发布班级动态") submitPost("王女士", content) }, command = state.workflowStates["post:王女士"] ?: WorkflowCommandState(), commandDriven = title == "发布班级动态", saveDraft = saveDraft, clearDraft = clearDraft, dismiss = { detail = null }) }
    commentPost?.let { postId -> AlertDialog(onDismissRequest = { commentPost = null }, title = { Text(if (commentSubmitted) "评论已发布" else "给这条动态留言") }, text = { if (commentSubmitted) Text("班级成员可以看到你的留言。", color = Green) else OutlinedTextField(value = comment, onValueChange = { comment = it; saveDraft("class-comment-$postId", it) }, label = { Text("评论内容") }, minLines = 2) }, confirmButton = { TextButton(enabled = commentSubmitted || comment.trim().isNotBlank(), onClick = { if (commentSubmitted) commentPost = null else { addComment(postId, comment); clearDraft("class-comment-$postId"); commentSubmitted = true } }) { Text(if (commentSubmitted) "完成" else "发布评论") } }, dismissButton = if (commentSubmitted) null else ({ TextButton(onClick = { commentPost = null }) { Text("取消") } })) }
}

@Composable private fun ClassCircleCommentPreview(comments: List<String>) {
    if (comments.isEmpty()) return
    Column(Modifier.fillMaxWidth().padding(top = 6.dp)) {
        HorizontalDivider(color = Color(0xFFF0F2F7))
        Text("最新评论", color = Color.Gray, fontSize = 8.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 5.dp))
        comments.takeLast(2).forEach { comment ->
            Text("王女士：$comment", color = Navy, fontSize = 9.sp, maxLines = 2, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

@Composable fun AccountScreen(state: AppUiState, nav: NavHostController, chooseRole: (UserRole) -> Unit, logout: () -> Unit, updateSettings: (Boolean?, Boolean?) -> Unit, sendSupport: (String) -> Unit, onRoleSelected: (UserRole) -> Unit = chooseRole, submitSupport: (String) -> Unit = sendSupport, clearWorkflow: (String) -> Unit = {}, saveDraft: (String, String) -> Unit = { _, _ -> }, clearDraft: (String) -> Unit = {}, syncPending: () -> Unit = {}) {
    var settingsOpen by remember { mutableStateOf(false) }
    var accountInfo by remember { mutableStateOf<String?>(null) }
    ParentTabScaffold(nav, Destinations.Account) {
        Text("我的", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 10.dp)); Spacer(Modifier.height(8.dp))
        Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看个人资料" }.clickable { accountInfo = "个人资料" }, color = Color.White, shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Surface(Modifier.size(52.dp), color = Sky, shape = CircleShape) { Text((state.profile?.name ?: "王").take(1), color = Blue, fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 13.dp)) }; Spacer(Modifier.width(11.dp)); Column(Modifier.weight(1f)) { Text(state.profile?.name ?: "王女士", color = Navy, fontWeight = FontWeight.Bold); Text(state.profile?.schoolName ?: "向上实验小学", color = Color.Gray, fontSize = 9.sp); Text(state.role?.label ?: "家长", color = Blue, fontSize = 9.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } }
        Spacer(Modifier.height(8.dp)); Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) { AccountMetric("已绑定孩子", state.local.boundChildIds.size.toString(), Blue, Modifier.weight(1f)) { nav.navigate(Destinations.Children) }; AccountMetric("成长报告", if (state.selectedChild == null) "0" else "1", Green, Modifier.weight(1f)) { if (state.selectedChild != null) nav.navigate(Destinations.Report) else nav.navigate(Destinations.ChildrenBinding) }; AccountMetric("未读消息", state.unreadMessageCount.toString(), Color(0xFFFF638E), Modifier.weight(1f)) { nav.navigate(Destinations.Messages) } }
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
        Text("服务与安全", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp, bottom = 2.dp)); AccountRow("帮助与反馈", Icons.AutoMirrored.Filled.HelpOutline, Blue) { clearWorkflow("support"); accountInfo = "帮助与反馈" }; AccountRow("用户协议与隐私政策", Icons.Filled.Description, Color.Gray) { accountInfo = "用户协议与隐私政策" }
        Spacer(Modifier.height(8.dp)); Text("切换使用角色", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) { listOf(UserRole.Parent, UserRole.Teacher, UserRole.Principal).forEach { role -> OutlinedButton(onClick = { onRoleSelected(role) }, modifier = Modifier.weight(1f)) { Text(role.label, fontSize = 9.sp) } } }
        OutlinedButton(onClick = { logout(); nav.navigate(Destinations.Login) { popUpTo(nav.graph.id) { inclusive = true } } }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp), colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.Red)) { Text("切换账号") }
    }
    if (settingsOpen) SettingsDialog(state.local.settings.notificationsEnabled, state.local.settings.reduceMotion, state.pendingSyncCount, state.workflowStates["sync-pending"] ?: WorkflowCommandState(), updateSettings, syncPending, clearLocalData = { logout(); nav.navigate(Destinations.Login) { popUpTo(nav.graph.id) { inclusive = true } } }) { settingsOpen = false }
    accountInfo?.let { title -> AccountInfoDialog(title, state, submitSupport, saveDraft, clearDraft) { accountInfo = null } }
}

@Composable fun SettingsDialog(notifications: Boolean, reduceMotion: Boolean, pendingSyncCount: Int, syncState: WorkflowCommandState, update: (Boolean?, Boolean?) -> Unit, syncNow: () -> Unit = {}, clearLocalData: () -> Unit = {}, dismiss: () -> Unit) {
    var notify by remember { mutableStateOf(notifications) }
    var reduce by remember { mutableStateOf(reduceMotion) }
    var permissionMessage by remember { mutableStateOf<String?>(null) }
    var clearConfirmation by remember { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        notify = granted
        permissionMessage = if (granted) null else "系统通知权限未开启，可在系统设置中允许通知。"
    }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text("设置") },
        text = { Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("接收测评与班级通知", modifier = Modifier.weight(1f))
                Switch(checked = notify, onCheckedChange = { enabled ->
                    if (enabled && Build.VERSION.SDK_INT >= 33) permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    else { notify = enabled; permissionMessage = null }
                })
            }
            Row(verticalAlignment = Alignment.CenterVertically) { Text("减少动态效果", modifier = Modifier.weight(1f)); Switch(checked = reduce, onCheckedChange = { reduce = it }) }
            permissionMessage?.let { Text(it, color = Color(0xFFFF8B1F), fontSize = 10.sp, modifier = Modifier.padding(top = 7.dp)) }
            Text("设置会自动保存并在下次启动后保留。", color = Color.Gray, fontSize = 10.sp, modifier = Modifier.padding(top = 9.dp))
            Text("本机同步", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp, modifier = Modifier.padding(top = 12.dp))
            Text("待同步记录：$pendingSyncCount 条", color = if (pendingSyncCount == 0) Green else Color(0xFFFF8B1F), fontSize = 11.sp)
            Text(if (pendingSyncCount == 0) "当前没有等待同步的本地操作。" else "记录已安全保存在本设备；联网后会自动重试，也可以立即同步。", color = Color.Gray, fontSize = 10.sp, modifier = Modifier.padding(top = 3.dp))
            TextButton(onClick = syncNow, enabled = pendingSyncCount > 0 && !syncState.isSubmitting, contentPadding = PaddingValues(horizontal = 0.dp, vertical = 2.dp)) { if (syncState.isSubmitting) CircularProgressIndicator(Modifier.size(15.dp), strokeWidth = 2.dp) else Text("立即同步", color = Blue, fontSize = 11.sp) }
            if (syncState.status == WorkflowCommandStatus.Succeeded) Text(syncState.message ?: "同步完成。", color = Green, fontSize = 10.sp)
            if (syncState.status == WorkflowCommandStatus.Failed) Text(syncState.message ?: "同步失败，请重试。", color = Color.Red, fontSize = 10.sp)
            Spacer(Modifier.height(8.dp))
            Text("退出登录会清除本机保存的绑定孩子、草稿和通知状态；不会删除学校侧的测评记录。", color = Color.Gray, fontSize = 10.sp)
            TextButton(onClick = { clearConfirmation = true }, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red), modifier = Modifier.align(Alignment.Start)) { Text("清除本机数据并退出登录") }
        } },
        confirmButton = { TextButton(onClick = { update(notify, reduce); dismiss() }) { Text("保存") } },
        dismissButton = { TextButton(onClick = dismiss) { Text("取消") } }
    )
    if (clearConfirmation) AlertDialog(
        onDismissRequest = { clearConfirmation = false },
        title = { Text("清除本机数据？") },
        text = { Text("此操作会移除本设备上的登录态、孩子绑定和本地草稿，后续可重新登录。") },
        confirmButton = { TextButton(onClick = { clearConfirmation = false; clearLocalData() }, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red)) { Text("清除并退出") } },
        dismissButton = { TextButton(onClick = { clearConfirmation = false }) { Text("取消") } }
    )
}

@Composable
private fun AccountInfoDialog(title: String, state: AppUiState, submitSupport: (String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, dismiss: () -> Unit) {
    val feedbackDraftKey = "account-feedback"
    var feedback by rememberSaveable(title) { mutableStateOf(state.local.drafts[feedbackDraftKey].orEmpty()) }
    var submitted by rememberSaveable(title) { mutableStateOf(false) }
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
                if (submitted) Text("反馈已保存，客服会在工作时间内回复。", color = Green)
                else Column {
                    OutlinedTextField(value = feedback, onValueChange = { feedback = it; saveDraft(feedbackDraftKey, it) }, label = { Text("问题描述") }, minLines = 3)
                    if (command.status == WorkflowCommandStatus.Failed) Text(command.message ?: "提交失败，请重试。", color = Color.Red, fontSize = 10.sp, modifier = Modifier.padding(top = 6.dp))
                    if (command.isSubmitting) Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 6.dp)) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(7.dp)); Text("正在提交反馈…", color = Blue, fontSize = 10.sp) }
                    Text("绑定码由学校或班主任提供；报告生成后会在消息中心通知。", color = Color.Gray, fontSize = 10.sp, modifier = Modifier.padding(top = 7.dp))
                }
            } else if (title == "个人资料") {
                val profile = state.profile
                val phone = profile?.phone.orEmpty()
                val maskedPhone = if (phone.filter(Char::isDigit).length >= 7) {
                    val digits = phone.filter(Char::isDigit)
                    "${digits.take(3)}****${digits.takeLast(4)}"
                } else "未绑定手机号"
                Text("${profile?.name ?: "王女士"}\n绑定学校：${profile?.schoolName ?: "向上实验小学"}\n当前角色：${state.role?.label ?: "家长"}\n手机号：$maskedPhone\n\n资料由家庭账户维护，后续可在学校服务同步后更新。", color = Color.Gray, fontSize = 11.sp)
            } else {
                Text("向上少年仅在获得授权后处理学生健康与运动数据，用于测评、报告和课程建议。儿童账号和家庭绑定数据不会用于商业推广。\n\n协议版本：2026.1", color = Color.Gray, fontSize = 11.sp)
            }
        },
        confirmButton = {
            TextButton(enabled = !command.isSubmitting && (title != "帮助与反馈" || submitted || feedback.trim().isNotEmpty()), onClick = {
                if (title == "帮助与反馈" && !submitted) submitSupport(feedback.trim()) else dismiss()
            }) { Text(if (title == "帮助与反馈" && !submitted) if (command.status == WorkflowCommandStatus.Failed) "重新提交" else "提交反馈" else "完成") }
        },
        dismissButton = if (submitted || title != "帮助与反馈") null else ({ TextButton(onClick = dismiss) { Text("取消") } })
    )
}

@Composable private fun AccountMetric(title: String, value: String, color: Color, modifier: Modifier, onClick: () -> Unit) = Surface(onClick = onClick, modifier = modifier, color = Color.White, shape = RoundedCornerShape(10.dp), shadowElevation = 1.dp) { Column(Modifier.padding(vertical = 10.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) { Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 18.sp); Text(title, color = Color.Gray, fontSize = 9.sp) } }
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
    val initial = if (title == "客服咨询") "我想了解体质成长课程。" else ""
    var draft by remember(title) { mutableStateOf(drafts[draftKey] ?: initial) }
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
                    if (!commandDriven) success = if (title == "客服咨询") "咨询已保存；客服老师将在工作时间内回复。" else "动态已保存，网络可用时将同步到本班家校圈。"
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
                    Text("客服老师：您好，请问想咨询哪一类课程？")
                    OutlinedTextField(value = draft, onValueChange = { draft = it; validation = null; saveDraft(draftKey, it) }, label = { Text("咨询内容") }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp), isError = validation != null)
                    messages.takeLast(4).forEach { Text((if (it.mine) "您：" else "客服老师：") + it.text, color = if (it.mine) Navy else Green, fontSize = 11.sp, modifier = Modifier.padding(top = 5.dp)) }
                }
                title == "发布班级动态" -> OutlinedTextField(value = draft, onValueChange = { draft = it; validation = null; saveDraft(draftKey, it) }, label = { Text("动态内容") }, placeholder = { Text("分享孩子的运动成长") }, modifier = Modifier.fillMaxWidth(), isError = validation != null)
                else -> Text("该功能的数据将在连接学校服务后自动同步。")
            }
            validation?.let { Text(it, color = Color.Red, fontSize = 10.sp, modifier = Modifier.padding(top = 5.dp)) }
        }
    )
}

@Composable fun AssessmentFlowScreen(state: AppUiState, nav: NavHostController, category: String, completeAssessment: (String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit) {
    val childKey = state.selectedChild?.id ?: "anonymous"
    if (state.selectedChild == null) { AppScaffold("绑定孩子", onBack = { nav.popBackStack() }) { EmptyState("请先绑定孩子，再开始健康测评。"); Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("去绑定孩子") } }; return }
    val selectedChild = state.selectedChild
    val title = when (category) { "vision" -> "视力"; "oral" -> "口腔"; "mental" -> "心理"; else -> "体质" }
    val icon = when (category) { "vision" -> Icons.Filled.RemoveRedEye; "oral" -> Icons.Filled.MedicalServices; "mental" -> Icons.Filled.Favorite; else -> Icons.AutoMirrored.Filled.DirectionsRun }
    val tint = when (category) { "vision" -> Green; "oral" -> Color(0xFFFFBD2E); "mental" -> Color(0xFFFF6D9B); else -> Blue }
    val steps = when (category) { "fitness" -> listOf("基础信息", "遗传身高", "脊柱姿态", "运动表现"); "vision" -> listOf("基础信息", "用眼习惯", "视力筛查"); "oral" -> listOf("基础信息", "口腔习惯", "口腔筛查"); else -> listOf("授权登录", "心理问卷", "结果回传") }
    val progressKey = "assessment-progress-${selectedChild.id}-$category"
    var step by rememberSaveable(childKey, category) {
        mutableIntStateOf(state.local.drafts[progressKey]?.toIntOrNull()?.coerceIn(0, steps.lastIndex) ?: 0)
    }
    var done by rememberSaveable(childKey, category) { mutableStateOf("$childKey-$category" in state.local.completedAssessments) }
    var answer by rememberSaveable(childKey, category, step) { mutableStateOf("") }
    var validation by rememberSaveable(childKey, category, step) { mutableStateOf<String?>(null) }
    val draftKey = "assessment-${selectedChild.id}-$category-$step"
    LaunchedEffect(draftKey) { answer = state.local.drafts[draftKey].orEmpty() }
    // `rememberSaveable` covers rotations only.  Persist the step independently
    // so an assessment remains resumable after Android reclaims the process.
    LaunchedEffect(progressKey, step, done) {
        if (!done) saveDraft(progressKey, step.toString())
    }
    Scaffold(containerColor = Canvas) { padding -> Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
        Row(Modifier.fillMaxWidth().background(Color.White).padding(14.dp), verticalAlignment = Alignment.CenterVertically) { IconButton(onClick = { nav.popBackStack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回") }; Text("${title}测评", color = Navy, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), textAlign = TextAlign.Center); Spacer(Modifier.width(48.dp)) }
        Column(Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) { Icon(icon, null, tint = tint, modifier = Modifier.size(52.dp)); Text("${selectedChild.name}的${title}测评", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 7.dp)); Text(if (category == "fitness") "完成身高、体态与学校运动表现记录" else "请根据孩子最近情况完成本次测评", color = Color.Gray, fontSize = 10.sp) }
        Row(Modifier.padding(horizontal = 16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { steps.forEachIndexed { index, item -> Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) { Surface(Modifier.size(25.dp), color = if (index <= step) tint else Color.LightGray, shape = CircleShape) { Text("${index + 1}", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 5.dp)) }; Text(item, color = if (index <= step) tint else Color.Gray, fontSize = 8.sp, maxLines = 1) }; if (index < steps.lastIndex) Spacer(Modifier.width(2.dp)) } }
        Surface(Modifier.padding(16.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) { Column(Modifier.padding(14.dp)) { Text(if (done) "健康记录已保存" else steps[step], color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp); Spacer(Modifier.height(8.dp)); Text(if (done) "本次健康记录已保存到本机健康档案；学校正式体测成绩不会由此页面生成。" else if (category == "mental") "将跳转至第三方心理系统授权登录，完成后自动回传结果。" else if (category == "fitness") when(step) { 0 -> "确认孩子的出生日期、当前身高和体重。"; 1 -> "填写父母身高，系统会计算遗传身高区间。"; 2 -> "按引导上传或记录站立姿态筛查结果。"; else -> "学校场地端完成运动发展测试后，正式 7 项成绩会在上传后同步。" } else "填写健康习惯并确认本次${title}筛查结果。", color = Color.Gray, fontSize = 11.sp); if (done) { Text("这不是学校正式体测报告；正式成绩由场地端生成并同步。", color = Blue, fontSize = 10.sp, modifier = Modifier.padding(top = 10.dp)) }; if (!done) { OutlinedTextField(value = answer, onValueChange = { answer = it; saveDraft(draftKey, it); validation = null }, label = { Text("本步骤记录") }, placeholder = { Text("填写后自动保存草稿") }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp)); Text("可退出后继续填写。", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.padding(top = 4.dp)) }; validation?.let { Text(it, color = Color.Red, fontSize = 10.sp, modifier = Modifier.padding(top = 5.dp)) } } }
        Button(onClick = { if (done) { nav.navigate(Destinations.Health) } else if (answer.isBlank()) { validation = "请填写本步骤信息后再继续。" } else if (step < steps.lastIndex) { step += 1; answer = state.local.drafts["assessment-${selectedChild.id}-$category-$step"] ?: "" } else { steps.indices.forEach { index -> clearDraft("assessment-${selectedChild.id}-$category-$index") }; clearDraft(progressKey); completeAssessment(category); done = true } }, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp).fillMaxWidth().height(48.dp)) { Text(if (done) "查看健康档案" else if (step == steps.lastIndex) "保存健康记录" else "保存并下一步") }
    } }
}
