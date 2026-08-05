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
fun ParentHomeScreen(state: AppUiState, nav: NavHostController, registerActivity: (String, String) -> Unit, checkInToday: () -> Unit, bookExpert: (String, String, String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit) {
    val context = LocalContext.current
    val reduceMotion = LocalReduceMotion.current
    val transition = rememberInfiniteTransition(label = "parent-campaign")
    val animatedCampaignScale by transition.animateFloat(1f, if (reduceMotion) 1f else 1.035f, infiniteRepeatable(tween(4200, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "campaign-drift")
    val campaignScale = if (reduceMotion) 1f else animatedCampaignScale
    var article by remember { mutableStateOf<String?>(null) }
    var activityDetail by remember { mutableStateOf(false) }
    var activityName by rememberSaveable { mutableStateOf("王女士") }
    var activityPhone by rememberSaveable { mutableStateOf("13800138000") }
    var activityConsented by rememberSaveable { mutableStateOf(false) }
    var activityError by remember { mutableStateOf<String?>(null) }
    val activityDraftKey = "activity-registration-health-growth-season-2026"
    var expert by remember { mutableStateOf<String?>(null) }; var expertDate by remember { mutableStateOf("2026-09-12 上午") }; var expertNote by remember { mutableStateOf("想了解孩子的运动发展建议。") }; var expertSubmitted by remember { mutableStateOf(false) }
    Scaffold(containerColor = Canvas, bottomBar = { ParentBottomBar(nav, Destinations.Parent) }) { contentPadding ->
    if (state.loading || state.data == null) { LoadingState(); return@Scaffold }
    if (state.selectedChild == null) {
        Column(Modifier.fillMaxSize().padding(contentPadding).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            ParentHeader("请先绑定孩子", { nav.navigate(Destinations.Children) }, { nav.navigate(Destinations.Notifications) }, state.unreadMessageCount)
            EmptyState("绑定孩子后才能查看测评、报告和课程。")
            Button(onClick = { nav.navigate(Destinations.Children) }) { Text("去绑定孩子") }
        }
        return@Scaffold
    }
    Column(Modifier.fillMaxSize().padding(contentPadding).background(Canvas).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(9.dp)) {
        ParentHeader(state.selectedChild?.name ?: "王小明", { nav.navigate(Destinations.Children) }, { nav.navigate(Destinations.Notifications) }, state.unreadMessageCount)
        Surface(Modifier.padding(horizontal = 10.dp).fillMaxWidth().semantics { role = Role.Button; contentDescription = "打开健康成长季活动报名" }.clickable { state.local.drafts[activityDraftKey]?.split("|", limit = 2)?.takeIf { it.size == 2 }?.let { (name, phone) -> activityName = name; activityPhone = phone }; activityDetail = true }, color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
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
                Spacer(Modifier.height(8.dp)); Row { ParentMetric("体质", Icons.Filled.DirectionsRun, Blue, Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/fitness") }; Spacer(Modifier.width(7.dp)); ParentMetric("心理", Icons.Filled.Favorite, Color(0xFFFF6D9B), Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/mental") } }
                Spacer(Modifier.height(7.dp)); Row { ParentMetric("视力", Icons.Filled.RemoveRedEye, Green, Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/vision") }; Spacer(Modifier.width(7.dp)); ParentMetric("口腔", Icons.Filled.MedicalServices, Color(0xFFFFBD2E), Modifier.weight(1f)) { nav.navigate("${Destinations.Assessment}/oral") } }
                Button(onClick = { nav.navigate("${Destinations.Assessment}/fitness") }, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp).height(29.dp), contentPadding = PaddingValues(horizontal = 28.dp)) { Text("继续测评", fontSize = 10.sp) }
            }
        }
        Row(Modifier.padding(horizontal = 10.dp)) { ParentAction("测评报告", Icons.Filled.Assignment, Blue, Modifier.weight(1f)) { nav.navigate(Destinations.Report) }; ParentAction("健康提醒", Icons.Filled.Warning, Color.Red, Modifier.weight(1f)) { nav.navigate(Destinations.Messages) }; ParentAction(if (state.local.checkedInToday) "今日已打卡" else "打卡记录", Icons.Filled.FactCheck, Green, Modifier.weight(1f)) { checkInToday(); nav.navigate(Destinations.Health) }; ParentAction("推荐课程", Icons.Filled.SmartDisplay, Color(0xFFFF9D25), Modifier.weight(1f)) { nav.navigate(Destinations.Courses) } }
        ParentSection("专家团队", "点击专家查看")
        Row(Modifier.padding(horizontal = 14.dp)) { listOf(R.drawable.expert_professor to "张教授", R.drawable.expert_doctor to "李医生", R.drawable.expert_coach to "王教练", R.drawable.expert_counselor to "刘主任").forEach { (image, name) -> Column(Modifier.weight(1f).semantics { role = Role.Button; contentDescription = "预约$name" }.clickable { expert = name }, horizontalAlignment = Alignment.CenterHorizontally) { Image(painterResource(image), null, Modifier.size(37.dp).clip(CircleShape), contentScale = ContentScale.Crop); Text(name, color = Navy, fontSize = 9.sp) } } }
        ParentSection("健康科普", "点击文章查看")
        listOf("儿童科学长高的 5 个关键习惯", "居家体态训练 10 分钟").forEach { title -> Surface(Modifier.padding(horizontal = 12.dp, vertical = 3.dp).fillMaxWidth().semantics { role = Role.Button; contentDescription = "阅读健康科普：$title" }.clickable { article = title }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.MenuBook, null, tint = Green); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text(title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 11.sp); Text("健康专栏 · 今日推荐", color = Color.Gray, fontSize = 8.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } } }
    } }
    if (activityDetail) AlertDialog(onDismissRequest = { activityDetail = false }, title = { Text("向上少年健康成长季") }, text = { Column { Text("7 月 16 日–8 月 15 日。完成四项健康测评后可查看个性化成长报告。") ; if (state.local.activityRegistered) { Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Green, modifier = Modifier.padding(top = 10.dp)); Text("报名已提交，活动开始前将通过消息中心通知您。", color = Green, fontSize = 11.sp) } else { OutlinedTextField(value = activityName, onValueChange = { activityName = it; saveDraft(activityDraftKey, "$it|$activityPhone"); activityError = null }, label = { Text("联系人姓名") }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp)); OutlinedTextField(value = activityPhone, onValueChange = { activityPhone = it; saveDraft(activityDraftKey, "$activityName|$it"); activityError = null }, label = { Text("手机号") }, modifier = Modifier.fillMaxWidth().padding(top = 7.dp)); Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 6.dp)) { Checkbox(checked = activityConsented, onCheckedChange = { activityConsented = it; activityError = null }); Text("已阅读活动说明并同意接收报名通知", fontSize = 10.sp) }; activityError?.let { Text(it, color = Color.Red, fontSize = 10.sp) } } } }, confirmButton = { TextButton(onClick = { when { activityName.isBlank() -> activityError = "请填写联系人姓名。"; activityPhone.filter(Char::isDigit).length != 11 -> activityError = "请填写 11 位手机号。"; !activityConsented -> activityError = "请先确认活动说明和通知授权。"; else -> { registerActivity(activityName.trim(), activityPhone.trim()); clearDraft(activityDraftKey) } } }, enabled = !state.local.activityRegistered) { Text(if (state.local.activityRegistered) "已报名" else "确认报名") } }, dismissButton = { TextButton(onClick = { activityDetail = false }) { Text("关闭") } })
    expert?.let { name -> AlertDialog(onDismissRequest = { expert = null; expertSubmitted = false }, title = { Text("$name · 健康成长专家") }, text = { if (expertSubmitted) Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Green, modifier = Modifier.size(42.dp)); Text("预约已提交，专家团队会在 1 个工作日内确认。", color = Navy, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp)) } else Column { Text("专业领域：儿童运动发展与健康评估。请填写咨询时间和需求。"); OutlinedTextField(value = expertDate, onValueChange = { expertDate = it }, label = { Text("期望咨询时间") }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)); OutlinedTextField(value = expertNote, onValueChange = { expertNote = it }, label = { Text("咨询说明") }, minLines = 2, modifier = Modifier.fillMaxWidth().padding(top = 7.dp)) } }, confirmButton = { TextButton(enabled = expertSubmitted || (expertDate.isNotBlank() && expertNote.isNotBlank()), onClick = { if (expertSubmitted) { expert = null; expertSubmitted = false } else { bookExpert(name, expertDate.trim(), expertNote.trim()); expertSubmitted = true } }) { Text(if (expertSubmitted) "完成" else "提交预约") } }, dismissButton = if (expertSubmitted) null else ({ TextButton(onClick = { expert = null }) { Text("取消") } })) }
    article?.let { title -> AlertDialog(onDismissRequest = { article = null }, title = { Text(title) }, text = { Text("完整内容由“向上少年健康成长”微信公众号提供。请在微信中搜索公众号查看。") }, confirmButton = { TextButton(onClick = { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("weixin://"))) }; article = null }) { Text("打开微信") } }, dismissButton = { TextButton(onClick = { article = null }) { Text("取消") } }) }
}

@Composable private fun ParentHeader(name: String, onClick: () -> Unit, onMessages: (() -> Unit)? = null, unreadCount: Int = 0) = Row(Modifier.fillMaxWidth().background(Color.White).padding(horizontal = 14.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) { Surface(Modifier.size(40.dp), color = Color(0xFF16AFA5), shape = CircleShape) { Text(name.take(1), color = Color.White, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 9.dp)) }; Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text(name, color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp); Text("三年级2班 · 点击切换孩子", color = Color.Gray, fontSize = 9.sp) }; IconButton(onClick = onClick) { Icon(Icons.Filled.ChevronRight, "切换孩子", tint = Blue) }; onMessages?.let { action -> IconButton(onClick = action) { BadgedBox(badge = { if (unreadCount > 0) Badge(containerColor = Color.Red, modifier = Modifier.size(6.dp)) {} }) { Icon(Icons.Filled.NotificationsNone, contentDescription = "消息通知", tint = Navy, modifier = Modifier.size(20.dp)) } } } }

@Composable fun NotificationsScreen(state: AppUiState, nav: NavHostController, markMessageRead: (String) -> Unit) = AppScaffold("消息通知", onBack = { nav.popBackStack() }) {
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    if (state.data.messages.isEmpty()) { EmptyState("暂无消息通知"); return@AppScaffold }
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) { Text("全部通知", color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp); Spacer(Modifier.weight(1f)); Text("未读 ${state.unreadMessageCount}", color = Blue, fontSize = 10.sp) }
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
fun ChildrenScreen(state: AppUiState, nav: NavHostController, bindChild: (String, String) -> Boolean, choose: (Student) -> Unit) = AppScaffold("孩子管理", onBack = { nav.popBackStack() }) {
    var bindingOpen by rememberSaveable { mutableStateOf(false) }
    var childName by rememberSaveable { mutableStateOf("") }
    var bindingCode by rememberSaveable { mutableStateOf("") }
    var bindingError by remember { mutableStateOf<String?>(null) }
    val data = state.data
    val boundIds = state.local.boundChildIds
    val children = data?.students?.filter { it.id in boundIds }.orEmpty()
    when {
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
        text = { Column { OutlinedTextField(value = childName, onValueChange = { childName = it; bindingError = null }, label = { Text("孩子姓名") }, modifier = Modifier.fillMaxWidth()); OutlinedTextField(value = bindingCode, onValueChange = { bindingCode = it; bindingError = null }, label = { Text("绑定码（示例 XS-S03）") }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)); Text("绑定码由学校或班主任提供，用于确认家庭与孩子关系。", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.padding(top = 7.dp)); bindingError?.let { Text(it, color = Color.Red, fontSize = 10.sp, modifier = Modifier.padding(top = 5.dp)) } } },
        confirmButton = { TextButton(onClick = { if (bindChild(childName, bindingCode)) { childName = ""; bindingCode = ""; bindingError = null; bindingOpen = false } else bindingError = "姓名或绑定码不匹配，请核对后重试。" }) { Text("确认绑定") } },
        dismissButton = { TextButton(onClick = { bindingOpen = false }) { Text("取消") } }
    )
}
@Composable
fun ParentEvaluationsScreen(state: AppUiState, nav: NavHostController, report: DiagnosisReport?) = ParentTabScaffold(nav, Destinations.ParentEvaluations) {
    if (state.loading || state.data == null) { LoadingState(); return@ParentTabScaffold }
    if (state.selectedChild == null) { EmptyState("暂无孩子档案，请先完成孩子绑定。"); return@ParentTabScaffold }
    state.selectedChild?.let { ParentHeader(it.name, onClick = { nav.navigate(Destinations.Children) }) }
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
                Icon(if (name == "体质") Icons.Filled.DirectionsRun else if (name == "视力") Icons.Filled.RemoveRedEye else if (name == "口腔") Icons.Filled.MedicalServices else Icons.Filled.Favorite, null, tint = Blue)
                Spacer(Modifier.width(9.dp))
                Column(Modifier.weight(1f)) { Text(name, color = Navy, fontWeight = FontWeight.Bold, fontSize = 11.sp); Text(detail, color = Color.Gray, fontSize = 8.sp) }
                Text("良好 ›", color = Green, fontSize = 9.sp)
            }
        }
    }
}
@Composable fun ParentMessagesScreen(state: AppUiState, nav: NavHostController, markMessageRead: (String) -> Unit) {
    var selectedTitle by remember { mutableStateOf<String?>(null) }
    var selectedContent by remember { mutableStateOf("") }
    var selectedTime by remember { mutableStateOf("") }
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }
    ParentTabScaffold(nav, Destinations.Messages) {
    Row(Modifier.fillMaxWidth().padding(bottom = 7.dp), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        listOf("消息提醒", "系统通知").forEachIndexed { index, title ->
            FilterChip(selected = selectedTab == index, onClick = { selectedTab = index }, label = { Text(title, fontSize = 10.sp) }, modifier = Modifier.weight(1f))
        }
    }
    val data = state.data
    val visibleMessages = data?.messages.orEmpty().filter { message -> if (selectedTab == 0) message.category != "系统" else message.category == "系统" }.ifEmpty { if (selectedTab == 0) data?.messages.orEmpty() else emptyList() }
    when {
        state.loading || data == null -> LoadingState()
        data.messages.isEmpty() || visibleMessages.isEmpty() -> EmptyState(if (selectedTab == 0) "暂无消息提醒" else "暂无系统通知")
        else -> visibleMessages.forEachIndexed { index, item -> Surface(Modifier.fillMaxWidth().padding(vertical = 4.dp).semantics { role = Role.Button; contentDescription = "查看消息：${item.title}" }.clickable { markMessageRead(item.id); selectedTitle = item.title; selectedContent = item.content; selectedTime = item.time }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(11.dp)) { Icon(if (index % 2 == 0) Icons.Filled.Warning else Icons.Filled.Notifications, null, tint = if (index % 2 == 0) Color.Red else Blue); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(item.title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); if (!item.isRead && item.id !in state.local.readMessageIds) Box(Modifier.size(5.dp).background(Color.Red, CircleShape).padding(start = 4.dp)) }; Text(item.content, color = Color.Gray, fontSize = 9.sp, maxLines = 1); Text(item.category, color = Blue, fontSize = 8.sp) }; Text(item.time, color = Color.Gray, fontSize = 8.sp) } } }
    }
}
    selectedTitle?.let { title -> AlertDialog(onDismissRequest = { selectedTitle = null }, title = { Text(title) }, text = { Column { Text(selectedContent); Text(selectedTime, color = Color.Gray, fontSize = 11.sp, modifier = Modifier.padding(top = 10.dp)) } }, confirmButton = { TextButton(onClick = { selectedTitle = null }) { Text("关闭") } }) }
}
@Composable
fun HealthProfileScreen(state: AppUiState, nav: NavHostController) = ParentTabScaffold(nav, Destinations.Health) {
    if (state.loading || state.data == null) { LoadingState(); return@ParentTabScaffold }
    if (state.selectedChild == null) { EmptyState("暂无健康档案，请先完成孩子绑定。"); return@ParentTabScaffold }
    ParentSection("健康报告", "查看全部报告") { nav.navigate(Destinations.Report) }
    Row { ScoreSummaryCard("体质", "良好", "本月"); Spacer(Modifier.width(6.dp)); ScoreSummaryCard("视力", "正常", "本月"); Spacer(Modifier.width(6.dp)); ScoreSummaryCard("口腔", "良好", "本月") }
    Spacer(Modifier.height(9.dp))
    Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(11.dp)) {
        Column(Modifier.padding(11.dp)) {
            ParentSection("本月打卡", "记录自动同步")
            Text("日    一    二    三    四    五    六", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
            Text("7     8     9    10    11    12    13\n14   15   16   17   18   19   20\n21   22   23   24   25   26   27", color = Green, fontSize = 10.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        }
    }
    Spacer(Modifier.height(9.dp))
    ParentActivities(nav)
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
@Composable private fun ParentTabScaffold(nav: NavHostController, selected: String, body: @Composable ColumnScope.() -> Unit) = Scaffold(containerColor = Canvas, bottomBar = { ParentBottomBar(nav, selected) }) { padding -> Column(Modifier.padding(padding).fillMaxSize().padding(horizontal = 12.dp).verticalScroll(rememberScrollState()), content = body) }
@Composable private fun ParentBottomBar(nav: NavHostController, selected: String) = NavigationBar(containerColor = Color.White, tonalElevation = 1.dp) {
    fun go(route: String) { nav.navigate(route) { popUpTo(Destinations.Parent) { saveState = true }; launchSingleTop = true; restoreState = true } }
    ParentNavItem("首页", Icons.Filled.Home, selected == Destinations.Parent) { go(Destinations.Parent) }
    ParentNavItem("我的评测", Icons.Filled.Assignment, selected == Destinations.ParentEvaluations) { go(Destinations.ParentEvaluations) }
    ParentNavItem("我的课程", Icons.Filled.PlayCircle, selected == Destinations.Courses) { go(Destinations.Courses) }
    ParentNavItem("班级圈", Icons.Filled.Groups, selected == Destinations.Circle) { go(Destinations.Circle) }
    ParentNavItem("我的", Icons.Filled.Person, selected == Destinations.Account) { go(Destinations.Account) }
}
@Composable private fun RowScope.ParentNavItem(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, selected: Boolean, onClick: () -> Unit) = NavigationBarItem(selected = selected, onClick = onClick, icon = { Icon(icon, null) }, label = { Text(label, fontSize = 9.sp) })

@Composable fun ParentCoursesScreen(state: AppUiState, nav: NavHostController, updateCourseProgress: (String, Float) -> Unit, sendSupport: (String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit) {
    var paid by remember { mutableStateOf(false) }; var detail by remember { mutableStateOf<String?>(null) }
    ParentTabScaffold(nav, Destinations.Courses) {
        if (state.loading || state.data == null) { LoadingState(); return@ParentTabScaffold }
        if (state.selectedChild == null) { EmptyState("暂无孩子档案，请先完成孩子绑定。"); Button(onClick = { nav.navigate(Destinations.Children) }) { Text("去绑定孩子") }; return@ParentTabScaffold }
        Text("我的课程", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 10.dp)); Text("${state.selectedChild?.name ?: "王小明"} · ${state.selectedChild?.className ?: "三年级2班"}", color = Color.Gray, fontSize = 10.sp); Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth().background(Sky, RoundedCornerShape(9.dp))) { listOf("公益课程", "学校课程").forEachIndexed { index, text -> Text(text, color = if (paid == (index == 1)) Color.White else Blue, fontWeight = FontWeight.Bold, fontSize = 11.sp, textAlign = TextAlign.Center, modifier = Modifier.weight(1f).padding(8.dp).semantics { role = Role.Tab; contentDescription = "切换到$text" }.background(if (paid == (index == 1)) Blue else Color.Transparent, RoundedCornerShape(8.dp)).clickable { paid = index == 1 }) } }
        Spacer(Modifier.height(10.dp)); ParentSection(if (paid) "精选学校课程" else "公益课堂", "全部课程") { detail = if (paid) "全部学校课程" else "全部公益课程" }
        val items = listOf("体质成长课" to Icons.Filled.DirectionsRun, "视力守护课" to Icons.Filled.RemoveRedEye, "口腔健康课" to Icons.Filled.MedicalServices, "心理舒展课" to Icons.Filled.Favorite)
        items.chunked(2).forEach { row -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { (title, icon) -> Surface(Modifier.weight(1f).height(105.dp).semantics { role = Role.Button; contentDescription = "打开课程：$title" }.clickable { updateCourseProgress(title, .8f); detail = title }, color = Sky, shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(12.dp)) { Icon(icon, null, tint = Blue); Spacer(Modifier.height(8.dp)); Text(title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text(if ((state.local.courseProgress[title] ?: 0f) > 0f) "学习进度 80%" else if (paid) "校内课程 · 查看课程" else "公益 · 立即学习", color = Green, fontSize = 9.sp) } } }; if (row.size == 1) Spacer(Modifier.weight(1f)) }; Spacer(Modifier.height(8.dp)) }
        Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "打开课程咨询" }.clickable { detail = "客服咨询" }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Message, null, tint = Blue); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text("课程咨询", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("客服老师会在工作时间回复您", color = Color.Gray, fontSize = 9.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } }
    }
    detail?.let { SimpleDialog(title = it, messages = state.local.supportMessages, drafts = state.local.drafts, send = sendSupport, saveDraft = saveDraft, clearDraft = clearDraft, dismiss = { detail = null }) }
}

@Composable fun ParentClassCircleScreen(state: AppUiState, nav: NavHostController, publishPost: (String, String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, toggleLike: (String) -> Unit, addComment: (String, String) -> Unit) {
    var detail by remember { mutableStateOf<String?>(null) }
    var filter by rememberSaveable { mutableIntStateOf(0) }
    var commentPost by remember { mutableStateOf<String?>(null) }
    var comment by remember { mutableStateOf("") }
    var commentSubmitted by remember { mutableStateOf(false) }
    val context = LocalContext.current
    ParentTabScaffold(nav, Destinations.Circle) {
        if (state.loading || state.data == null) { LoadingState(); return@ParentTabScaffold }
        if (state.selectedChild == null) { EmptyState("暂无孩子档案，请先完成孩子绑定。"); Button(onClick = { nav.navigate(Destinations.Children) }) { Text("去绑定孩子") }; return@ParentTabScaffold }
        Text("班级圈", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 10.dp))
        Text("${state.selectedChild?.name ?: "王小明"} · ${state.selectedChild?.className ?: "三年级2班"} · 42人", color = Color.Gray, fontSize = 10.sp)
        Surface(Modifier.fillMaxWidth().padding(top = 9.dp), color = Sky, shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("本班家校圈", color = Navy, fontWeight = FontWeight.Bold, fontSize = 15.sp); Text("分享运动成长，和老师保持联系", color = Color.Gray, fontSize = 9.sp) }; Column(horizontalAlignment = Alignment.End) { Text("42", color = Blue, fontWeight = FontWeight.Bold, fontSize = 20.sp); Text("班级成员", color = Color.Gray, fontSize = 8.sp) } } }
        Row(Modifier.fillMaxWidth().padding(top = 9.dp), horizontalArrangement = Arrangement.spacedBy(7.dp)) { listOf("全部", "老师动态", "家长分享").forEachIndexed { index, title -> FilterChip(selected = filter == index, onClick = { filter = index }, label = { Text(title, fontSize = 10.sp) }) } }
        Button(onClick = { detail = "发布班级动态" }, modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp)) { Icon(Icons.Filled.Edit, null); Spacer(Modifier.width(7.dp)); Text("发布班级动态") }
        val posts = state.local.classPosts.filter { filter == 0 || (filter == 1 && it.author.contains("老师")) || (filter == 2 && !it.author.contains("老师")) }
        if (posts.isEmpty()) {
            Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(12.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.School, null, tint = Blue); Spacer(Modifier.width(8.dp)); Column { Text("李老师", color = Blue, fontWeight = FontWeight.Bold, fontSize = 11.sp); Text("今天 08:30 · 置顶通知", color = Color.Gray, fontSize = 8.sp) } }; Text("本周运动打卡已开启，欢迎家长分享孩子的练习瞬间。", color = Navy, fontSize = 11.sp, modifier = Modifier.padding(top = 7.dp)); Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) { Text("♡ 12", color = Color.Gray, fontSize = 9.sp); Text("评论 3", color = Color.Gray, fontSize = 9.sp); Text("班级通知", color = Blue, fontSize = 9.sp) } } }
        }
        posts.forEach { post ->
            Surface(Modifier.padding(vertical = 4.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp), shadowElevation = 1.dp) { Column(Modifier.padding(11.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.AccountCircle, null, tint = Sky, modifier = Modifier.size(28.dp)); Spacer(Modifier.width(8.dp)); Column { Text(post.author, color = Blue, fontWeight = FontWeight.Bold, fontSize = 10.sp); Text("刚刚发布 · 本班可见", color = Color.Gray, fontSize = 8.sp) }; Spacer(Modifier.weight(1f)) }
                Text(post.content, color = Navy, fontSize = 11.sp, modifier = Modifier.padding(top = 5.dp))
                Row(Modifier.fillMaxWidth().padding(top = 7.dp), horizontalArrangement = Arrangement.spacedBy(15.dp)) { Text(if (post.id in state.local.likedPostIds) "已赞" else "点赞", color = if (post.id in state.local.likedPostIds) Blue else Color.Gray, fontSize = 9.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = if (post.id in state.local.likedPostIds) "取消点赞" else "点赞" }.clickable { toggleLike(post.id) }); Text("评论", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "评论这条动态" }.clickable { commentSubmitted = false; comment = ""; commentPost = post.id }); Spacer(Modifier.weight(1f)); Text("分享", color = Blue, fontSize = 9.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "分享这条动态" }.clickable { runCatching { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, post.content) }, "分享班级动态")) } }) }
            } }
        }
        ParentSection("班级之星", "榜单展示") { detail = "班级之星榜单" }; Row(Modifier.fillMaxWidth()) { listOf("勤劳之星" to "陈乐乐", "运动之星" to "王小明", "阅读之星" to "李安然").forEach { (star, name) -> Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Filled.Star, null, tint = Color(0xFFFFBD2E)); Text(star, color = Navy, fontSize = 9.sp); Text(name, color = Color.Gray, fontSize = 8.sp) } } }
        Spacer(Modifier.height(10.dp)); Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(12.dp)) { ParentSection("本月打卡", "记录自动同步") { detail = "本月运动打卡记录" }; Text("✓  ✓  ✓  ✓  ·  ✓  ✓  ·  ✓  ✓  ✓  ✓  ✓  ·  ✓", color = Green, fontSize = 15.sp); Text("本月已完成 15 次运动打卡", color = Color.Gray, fontSize = 9.sp) } }
        Spacer(Modifier.height(10.dp)); ParentSection("延时课堂精彩瞬间", "点击课程查看") { nav.navigate(Destinations.Courses) }; Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) { MiniActivity(R.drawable.activity_football, "足球启蒙", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) }; MiniActivity(R.drawable.activity_classroom, "健康课堂", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) }; MiniActivity(R.drawable.activity_balance, "亲子平衡", Modifier.weight(1f)) { nav.navigate(Destinations.Courses) } }
        Spacer(Modifier.height(10.dp)); ParentSection("推荐课程", "查看详情") { nav.navigate(Destinations.Courses) }; ParentActivities(nav); Spacer(Modifier.height(8.dp)); ParentSection("我的课程", "全部课程") { nav.navigate(Destinations.Courses) }; Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.CalendarMonth, null, tint = Green); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text("我的运动安排", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("周三 15:30–16:30 · 足球基础训练", color = Color.Gray, fontSize = 9.sp) }; Text("已预约", color = Green, fontSize = 9.sp) } }
    }
    detail?.let { title -> SimpleDialog(title = title, drafts = state.local.drafts, send = { content -> if (title == "发布班级动态") publishPost("王女士", content) }, saveDraft = saveDraft, clearDraft = clearDraft, dismiss = { detail = null }) }
    commentPost?.let { postId -> AlertDialog(onDismissRequest = { commentPost = null }, title = { Text(if (commentSubmitted) "评论已发布" else "给这条动态留言") }, text = { if (commentSubmitted) Text("班级成员可以看到你的留言。", color = Green) else OutlinedTextField(value = comment, onValueChange = { comment = it }, label = { Text("评论内容") }, minLines = 2) }, confirmButton = { TextButton(enabled = commentSubmitted || comment.trim().isNotBlank(), onClick = { if (commentSubmitted) commentPost = null else { addComment(postId, comment); commentSubmitted = true } }) { Text(if (commentSubmitted) "完成" else "发布评论") } }, dismissButton = if (commentSubmitted) null else ({ TextButton(onClick = { commentPost = null }) { Text("取消") } })) }
}

@Composable fun AccountScreen(state: AppUiState, nav: NavHostController, chooseRole: (UserRole) -> Unit, logout: () -> Unit, updateSettings: (Boolean?, Boolean?) -> Unit, sendSupport: (String) -> Unit) {
    var settingsOpen by remember { mutableStateOf(false) }
    var accountInfo by remember { mutableStateOf<String?>(null) }
    ParentTabScaffold(nav, Destinations.Account) {
        Text("我的", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 10.dp)); Spacer(Modifier.height(8.dp))
        Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看个人资料" }.clickable { accountInfo = "个人资料" }, color = Color.White, shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Surface(Modifier.size(52.dp), color = Sky, shape = CircleShape) { Text((state.profile?.name ?: "王").take(1), color = Blue, fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 13.dp)) }; Spacer(Modifier.width(11.dp)); Column(Modifier.weight(1f)) { Text(state.profile?.name ?: "王女士", color = Navy, fontWeight = FontWeight.Bold); Text(state.profile?.schoolName ?: "向上实验小学", color = Color.Gray, fontSize = 9.sp); Text(state.role?.label ?: "家长", color = Blue, fontSize = 9.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } }
        Spacer(Modifier.height(8.dp)); Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) { AccountMetric("已绑定孩子", state.local.boundChildIds.size.toString(), Blue, Modifier.weight(1f)) { nav.navigate(Destinations.Children) }; AccountMetric("成长报告", if (state.selectedChild == null) "0" else "1", Green, Modifier.weight(1f)) { if (state.selectedChild != null) nav.navigate(Destinations.Report) }; AccountMetric("未读消息", state.unreadMessageCount.toString(), Color(0xFFFF638E), Modifier.weight(1f)) { nav.navigate(Destinations.Messages) } }
        Text("家庭服务", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 12.dp, bottom = 2.dp)); AccountRow("孩子管理", Icons.Filled.People, Blue) { nav.navigate(Destinations.Children) }
        Text("账户与设置", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp, bottom = 2.dp)); listOf("我的健康档案" to Icons.Filled.Favorite, "我的课程" to Icons.Filled.PlayCircle, "客服咨询" to Icons.Filled.Message, "设置" to Icons.Filled.Settings, "消息" to Icons.Filled.Notifications).forEach { (title, icon) -> AccountRow(title, icon, Blue) {
            when (title) {
                "我的健康档案" -> nav.navigate(Destinations.Health)
                "我的课程", "客服咨询" -> nav.navigate(Destinations.Courses)
                "消息" -> nav.navigate(Destinations.Messages)
                "设置" -> settingsOpen = true
            }
        } }
        Text("服务与安全", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp, bottom = 2.dp)); AccountRow("帮助与反馈", Icons.Filled.HelpOutline, Blue) { accountInfo = "帮助与反馈" }; AccountRow("用户协议与隐私政策", Icons.Filled.Description, Color.Gray) { accountInfo = "用户协议与隐私政策" }
        Spacer(Modifier.height(8.dp)); Text("切换使用角色", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) { listOf(UserRole.Parent, UserRole.Teacher, UserRole.Principal).forEach { role -> OutlinedButton(onClick = { chooseRole(role); val destination = if (role == UserRole.Parent) Destinations.Parent else if (role == UserRole.Teacher) Destinations.Teacher else Destinations.Principal; nav.navigate(destination) { popUpTo(Destinations.Account) { inclusive = true }; launchSingleTop = true } }, modifier = Modifier.weight(1f)) { Text(role.label, fontSize = 9.sp) } } }
        OutlinedButton(onClick = { logout(); nav.navigate(Destinations.Login) { popUpTo(nav.graph.id) { inclusive = true } } }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp), colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.Red)) { Text("切换账号") }
    }
    if (settingsOpen) SettingsDialog(state.local.settings.notificationsEnabled, state.local.settings.reduceMotion, updateSettings) { settingsOpen = false }
    accountInfo?.let { title -> AccountInfoDialog(title, sendSupport) { accountInfo = null } }
}

@Composable fun SettingsDialog(notifications: Boolean, reduceMotion: Boolean, update: (Boolean?, Boolean?) -> Unit, dismiss: () -> Unit) {
    var notify by remember { mutableStateOf(notifications) }
    var reduce by remember { mutableStateOf(reduceMotion) }
    var permissionMessage by remember { mutableStateOf<String?>(null) }
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
        } },
        confirmButton = { TextButton(onClick = { update(notify, reduce); dismiss() }) { Text("保存") } },
        dismissButton = { TextButton(onClick = dismiss) { Text("取消") } }
    )
}

@Composable
private fun AccountInfoDialog(title: String, sendSupport: (String) -> Unit, dismiss: () -> Unit) {
    var feedback by rememberSaveable(title) { mutableStateOf("") }
    var submitted by rememberSaveable(title) { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(title) },
        text = {
            if (title == "帮助与反馈") {
                if (submitted) Text("反馈已提交，客服会在工作时间内回复。", color = Green)
                else Column {
                    OutlinedTextField(value = feedback, onValueChange = { feedback = it }, label = { Text("问题描述") }, minLines = 3)
                    Text("绑定码由学校或班主任提供；报告生成后会在消息中心通知。", color = Color.Gray, fontSize = 10.sp, modifier = Modifier.padding(top = 7.dp))
                }
            } else if (title == "个人资料") {
                Text("王女士\n绑定学校：向上实验小学\n当前角色：家长\n\n资料由家庭账户维护，后续可在学校服务同步后更新。", color = Color.Gray, fontSize = 11.sp)
            } else {
                Text("向上少年仅在获得授权后处理学生健康与运动数据，用于测评、报告和课程建议。儿童账号和家庭绑定数据不会用于商业推广。\n\n协议版本：2026.1", color = Color.Gray, fontSize = 11.sp)
            }
        },
        confirmButton = {
            TextButton(enabled = title != "帮助与反馈" || submitted || feedback.trim().isNotEmpty(), onClick = {
                if (title == "帮助与反馈" && !submitted) { sendSupport(feedback.trim()); submitted = true } else dismiss()
            }) { Text(if (title == "帮助与反馈" && !submitted) "提交反馈" else "完成") }
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
    saveDraft: (String, String) -> Unit = { _, _ -> },
    clearDraft: (String) -> Unit = {},
    dismiss: () -> Unit
) {
    val draftKey = "dialog-$title"
    val initial = if (title == "客服咨询") "我想了解体质成长课程。" else ""
    var draft by remember(title) { mutableStateOf(drafts[draftKey] ?: initial) }
    var validation by remember(title) { mutableStateOf<String?>(null) }
    var success by remember(title) { mutableStateOf<String?>(null) }
    val isEditable = title == "客服咨询" || title == "发布班级动态"
    AlertDialog(
        onDismissRequest = dismiss,
        confirmButton = {
            TextButton(enabled = !isEditable || success != null || draft.isNotBlank(), onClick = {
                if (!isEditable) {
                    dismiss()
                } else if (success != null) {
                    dismiss()
                } else if (draft.trim().isBlank()) {
                    validation = if (title == "客服咨询") "请输入咨询内容。" else "动态内容不能为空。"
                } else {
                    send(draft.trim())
                    clearDraft(draftKey)
                    validation = null
                    success = if (title == "客服咨询") "咨询已提交，客服老师将在工作时间内回复。" else "动态已发布到本班家校圈。"
                }
            }) { Text(if (success != null) "完成" else if (title == "客服咨询") "发送咨询" else if (title == "发布班级动态") "发布" else "我知道了") }
        },
        dismissButton = if (success == null) ({ TextButton(onClick = dismiss) { Text("取消") } }) else null,
        title = { Text(title) },
        text = {
            when {
                success != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Green, modifier = Modifier.size(42.dp))
                    Text(success!!, color = Navy, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
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
    var step by remember { mutableIntStateOf(0) }; var done by remember { mutableStateOf(false) }; var answer by remember { mutableStateOf("") }; var validation by remember { mutableStateOf<String?>(null) }
    if (state.selectedChild == null) { AppScaffold("绑定孩子", onBack = { nav.popBackStack() }) { EmptyState("请先绑定孩子，再开始健康测评。"); Button(onClick = { nav.navigate(Destinations.Children) }) { Text("去绑定孩子") } }; return }
    val title = when (category) { "vision" -> "视力"; "oral" -> "口腔"; "mental" -> "心理"; else -> "体质" }
    val icon = when (category) { "vision" -> Icons.Filled.RemoveRedEye; "oral" -> Icons.Filled.MedicalServices; "mental" -> Icons.Filled.Favorite; else -> Icons.Filled.DirectionsRun }
    val tint = when (category) { "vision" -> Green; "oral" -> Color(0xFFFFBD2E); "mental" -> Color(0xFFFF6D9B); else -> Blue }
    val steps = when (category) { "fitness" -> listOf("基础信息", "遗传身高", "脊柱姿态", "运动表现"); "vision" -> listOf("基础信息", "用眼习惯", "视力筛查"); "oral" -> listOf("基础信息", "口腔习惯", "口腔筛查"); else -> listOf("授权登录", "心理问卷", "结果回传") }
    val draftKey = "assessment-${state.selectedChild?.id ?: "anonymous"}-$category-$step"
    LaunchedEffect(draftKey) { answer = state.local.drafts[draftKey].orEmpty() }
    Scaffold(containerColor = Canvas) { padding -> Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
        Row(Modifier.fillMaxWidth().background(Color.White).padding(14.dp), verticalAlignment = Alignment.CenterVertically) { IconButton(onClick = { nav.popBackStack() }) { Icon(Icons.Filled.ArrowBack, null) }; Text("${title}测评", color = Navy, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), textAlign = TextAlign.Center); Spacer(Modifier.width(48.dp)) }
        Column(Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) { Icon(icon, null, tint = tint, modifier = Modifier.size(52.dp)); Text("${state.selectedChild?.name ?: "王小明"}的${title}测评", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 7.dp)); Text(if (category == "fitness") "完成身高、体态与学校运动表现记录" else "请根据孩子最近情况完成本次测评", color = Color.Gray, fontSize = 10.sp) }
        Row(Modifier.padding(horizontal = 16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { steps.forEachIndexed { index, item -> Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) { Surface(Modifier.size(25.dp), color = if (index <= step) tint else Color.LightGray, shape = CircleShape) { Text("${index + 1}", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 5.dp)) }; Text(item, color = if (index <= step) tint else Color.Gray, fontSize = 8.sp, maxLines = 1) }; if (index < steps.lastIndex) Spacer(Modifier.width(2.dp)) } }
        Surface(Modifier.padding(16.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) { Column(Modifier.padding(14.dp)) { Text(if (done) "测评已保存" else steps[step], color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp); Spacer(Modifier.height(8.dp)); Text(if (done) "结果已写入健康档案。" else if (category == "mental") "将跳转至第三方心理系统授权登录，完成后自动回传结果。" else if (category == "fitness") when(step) { 0 -> "确认孩子的出生日期、当前身高和体重。"; 1 -> "填写父母身高，系统会计算遗传身高区间。"; 2 -> "按引导上传或记录站立姿态筛查结果。"; else -> "学校场地端完成运动发展测试后，结果将自动同步至本页。" } else "填写健康习惯并确认本次${title}筛查结果。", color = Color.Gray, fontSize = 11.sp); if (!done) { OutlinedTextField(value = answer, onValueChange = { answer = it; saveDraft(draftKey, it); validation = null }, label = { Text("本步骤记录") }, placeholder = { Text("填写后自动保存草稿") }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp)); Text("可退出后继续填写。", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.padding(top = 4.dp)) }; validation?.let { Text(it, color = Color.Red, fontSize = 10.sp, modifier = Modifier.padding(top = 5.dp)) } } }
        Button(onClick = { if (done) { nav.navigate(Destinations.Report) } else if (answer.isBlank()) { validation = "请填写本步骤信息后再继续。" } else if (step < steps.lastIndex) { step += 1; answer = state.local.drafts["assessment-${state.selectedChild?.id ?: "anonymous"}-$category-$step"] ?: "" } else { steps.indices.forEach { index -> clearDraft("assessment-${state.selectedChild?.id ?: "anonymous"}-$category-$index") }; completeAssessment(category); done = true } }, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp).fillMaxWidth().height(48.dp)) { Text(if (done) "查看报告" else if (step == steps.lastIndex) "完成并保存" else "保存并下一步") }
    } }
}
