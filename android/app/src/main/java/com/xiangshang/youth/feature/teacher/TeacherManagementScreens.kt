package com.xiangshang.youth.feature.teacher

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.net.toUri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.navigation.NavHostController
import com.xiangshang.youth.R
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.model.MessageItem
import com.xiangshang.youth.core.model.AssessmentScoreRules
import com.xiangshang.youth.core.model.TestItem
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.model.TaskStatus
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.service.CourseAttachmentStore
import com.xiangshang.youth.core.util.RoleMessageDestination
import com.xiangshang.youth.feature.parent.SettingsDialog
import com.xiangshang.youth.feature.parent.ClassNoticeDetailDialog
import com.xiangshang.youth.feature.parent.openMessageBusinessRoute
import java.time.Instant
import com.xiangshang.youth.shared.component.*

@Composable
fun TeacherAccountScreen(state: AppUiState, nav: NavHostController, logout: () -> Unit, updateSettings: (Boolean?, Boolean?, Boolean?, Boolean?) -> Unit, onChooseAnotherRole: () -> Unit, syncPending: () -> Unit = {}, submitAccountDeletionRequest: () -> Unit = {}) {
    var detail by remember { mutableStateOf<String?>(null) }; var settingsOpen by remember { mutableStateOf(false) }; var accountDeleteConfirmation by remember { mutableStateOf(false) }
    Scaffold(containerColor = Canvas, bottomBar = { TeacherBottomBar(nav, Destinations.Account) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight().padding(horizontal = 12.dp).verticalScroll(rememberScrollState())) {
            Text("我的", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 12.dp, bottom = 9.dp))
            val managedClassNames = state.managedTeacherClasses.map { it.name }
            val managedClassText = managedClassNames.joinToString("、").ifBlank { "暂无管理班级" }
            Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看教师个人资料" }.clickable { detail = "个人信息" }, color = Color.White, shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Image(painterResource(R.drawable.teacher_avatar), null, Modifier.size(52.dp).clip(CircleShape), contentScale = ContentScale.Crop); Spacer(Modifier.width(11.dp)); Column(Modifier.weight(1f)) { Text(state.activeDisplayName, color = Navy, fontWeight = FontWeight.Bold); Text("${state.profile?.schoolName ?: "学校"} · $managedClassText", color = Color.Gray, fontSize = 12.sp); Text(teacherCapabilitySummary(state), color = Green, fontSize = 12.sp) }; Icon(Icons.Filled.ChevronRight, "查看教师个人资料", tint = Color.Gray) } }
            Spacer(Modifier.height(10.dp))
            listOf("个人信息" to Icons.Filled.Person, "我的权限" to Icons.Filled.AdminPanelSettings, "工作数据" to Icons.Filled.BarChart, "设置" to Icons.Filled.Settings, "消息" to Icons.Filled.Notifications).forEach { (title, icon) -> Surface(Modifier.fillMaxWidth().padding(vertical = 4.dp).semantics { role = Role.Button; contentDescription = "打开$title" }.clickable { when (title) { "工作数据" -> nav.navigateSingleTop(Destinations.TeacherBoard); "设置" -> settingsOpen = true; "消息" -> nav.navigateSingleTop(RoleMessageDestination.resolve(UserRole.Teacher)); else -> detail = title } }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = Blue); Spacer(Modifier.width(10.dp)); Text(title, color = Navy, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f)); Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } } }
            Spacer(Modifier.height(9.dp)); OutlinedButton(onClick = onChooseAnotherRole, modifier = Modifier.fillMaxWidth().semantics { contentDescription = "重新选择使用角色" }) { Text("切换使用角色") }
            OutlinedButton(onClick = { accountDeleteConfirmation = true }, modifier = Modifier.fillMaxWidth().padding(top = 7.dp), colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.Red)) { Text("申请注销当前账户") }
            OutlinedButton(onClick = { logout(); nav.navigate(Destinations.Login) { popUpTo(nav.graph.id) { inclusive = true } } }, modifier = Modifier.fillMaxWidth().padding(top = 7.dp), colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.Red)) { Text("切换账号") }
        }
        }
    }
    detail?.let { title -> AlertDialog(onDismissRequest = { detail = null }, confirmButton = { TextButton(onClick = { detail = null }) { Text("我知道了") } }, title = { Text(title) }, text = { Text(if (title == "个人信息") "${state.activeDisplayName} · 当前负责班级将在学校统一账户管理后同步更新。" else "当前账户已获得授权班级的测评、预警与课程管理权限。") }) }
    if (settingsOpen) SettingsDialog(state.local.settings.notificationsEnabled, state.local.settings.reduceMotion, state.local.settings.voiceGuidanceEnabled, state.local.settings.analyticsEnabled, state.pendingSyncCount, state.workflowStates["sync-pending"] ?: WorkflowCommandState(), updateSettings, syncPending, clearLocalData = { logout(); nav.navigate(Destinations.Login) { popUpTo(nav.graph.id) { inclusive = true } } }) { settingsOpen = false }
    if (accountDeleteConfirmation) AlertDialog(onDismissRequest = { accountDeleteConfirmation = false }, title = { Text("申请注销当前账户？") }, text = { Text("账户会先进入审核队列。批准后将撤销登录会话并匿名化账户信息；学校侧已完成的测评记录按留存规则处理。") }, confirmButton = { TextButton(onClick = { submitAccountDeletionRequest(); accountDeleteConfirmation = false }, colors = ButtonDefaults.textButtonColors(contentColor = Color.Red)) { Text("提交注销申请") } }, dismissButton = { TextButton(onClick = { accountDeleteConfirmation = false }) { Text("取消") } })
}

@Composable
fun TeacherClassBoardScreen(state: AppUiState, nav: NavHostController, onOpenReport: (com.xiangshang.youth.core.model.Student) -> Unit, reportForStudent: (com.xiangshang.youth.core.model.Student) -> com.xiangshang.youth.core.model.DiagnosisReport? = { null }, loadOverview: (String, com.xiangshang.youth.core.model.TestTask) -> Unit = { _, _ -> }) = AppScaffold("班级数据看板", onBack = { nav.popBackStack() }) {
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@AppScaffold }
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    var selectedClassId by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedTaskId by rememberSaveable { mutableStateOf<String?>(null) }
    val primaryClass = state.managedTeacherClasses.firstOrNull { it.id == selectedClassId } ?: state.managedTeacherClasses.firstOrNull()
    val primaryClassName = primaryClass?.name ?: "我的班级"
    val currentTask = state.data.tasks.firstOrNull { it.id == selectedTaskId } ?: state.data.tasks.firstOrNull()
    LaunchedEffect(primaryClass?.id, currentTask?.id) { if (primaryClass != null && currentTask != null) loadOverview(primaryClass.id, currentTask) }
    val classStudents = state.data.students.filter { it.classId == primaryClass?.id }
    if (classStudents.isEmpty()) {
        EmptyState("暂无${primaryClassName}数据，学生名单同步后会显示在这里。")
        return@AppScaffold
    }
    val context = LocalContext.current
    var selectedPeriod by rememberSaveable { mutableStateOf("本轮综合测评") }
    var historicalDetailShown by rememberSaveable { mutableStateOf(false) }
    val isHistorical = selectedPeriod == "2026春季"
    // The remote dashboard directory is bounded and may not contain every
    // student in the selected class. Only the server overview is allowed to
    // represent official completion/risk metrics in a remote session.
    // `dataAvailable=false` represents an unavailable aggregate, not a
    // completed task with zero students or zero risks.
    val overviewContext = com.xiangshang.youth.app.TeacherOverviewContext(state.profile?.schoolId.orEmpty(), primaryClass?.id.orEmpty(), currentTask?.id.orEmpty(), currentTask?.ruleVersion.orEmpty())
    val remoteOverview = state.teacherOverview?.takeIf { state.teacherOverviewContext == overviewContext && it.dataAvailable }
    val useRemoteOverview = state.repositoryAcknowledged
    val totalStudents = if (isHistorical) 0 else remoteOverview?.totalCount ?: if (useRemoteOverview) 0 else classStudents.size
    val completed = if (isHistorical) 0 else remoteOverview?.completedCount ?: if (useRemoteOverview) 0 else classStudents.count { state.taskStatus(it, currentTask?.id).name == "Completed" }
    val completionRate = if (totalStudents == 0) 0 else completed * 100 / totalStudents
    val officialReports = classStudents.filter(state::hasPublishedSchoolReport).mapNotNull(reportForStudent)
    val lowScoreStudentIds = officialReports.filter { it.requiresFollowUp }.map { it.student.id }.toSet()
    val risk = if (isHistorical) 0 else remoteOverview?.riskCount ?: if (useRemoteOverview) 0 else classStudents.count { val status = state.taskStatus(it, currentTask?.id); it.id in lowScoreStudentIds || status.name == "Review" || status.name == "Retest" }
    fun drillDown(action: () -> Unit) { if (isHistorical) historicalDetailShown = true else action() }
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(vertical = 4.dp)) {
        state.managedTeacherClasses.forEach { item ->
            FilterChip(selected = item.id == primaryClass?.id, onClick = { selectedClassId = item.id }, label = { Text(item.name, fontSize = 12.sp) })
        }
        state.data.tasks.forEach { item ->
            FilterChip(selected = item.id == currentTask?.id, onClick = { selectedTaskId = item.id }, label = { Text(item.title, fontSize = 12.sp, maxLines = 1) })
        }
        listOf("本轮综合测评", "2026春季").forEach { period ->
            FilterChip(selected = selectedPeriod == period, onClick = { selectedPeriod = period }, label = { Text(period, fontSize = 12.sp) })
        }
    }
    Spacer(Modifier.height(7.dp))
    if (isHistorical) Surface(Modifier.fillMaxWidth().padding(bottom = 7.dp).semantics { role = Role.Button; contentDescription = "查看2026春季归档说明" }.clickable { historicalDetailShown = true }, color = Color(0xFFF3EEFF), shape = RoundedCornerShape(9.dp)) { Row(Modifier.padding(9.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Archive, null, tint = Color(0xFF8A5AF5), modifier = Modifier.size(17.dp)); Spacer(Modifier.width(6.dp)); Text("2026春季为已归档汇总；学生明细请切换回本轮查看", color = Color(0xFF6F4DAD), fontSize = 12.sp, modifier = Modifier.weight(1f)); Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.size(14.dp)) } }
    if (!isHistorical && useRemoteOverview && remoteOverview == null) {
        EmptyState("当前班级统计正在同步。服务端返回本任务统计后，将显示完成率、风险分布和单项成绩。")
        return@AppScaffold
    }
    BoardCard("${primaryClassName}健康概览", if (isHistorical) "归档说明" else "查看明细", onClick = { drillDown { primaryClass?.id?.let { nav.navigateSingleTop("${Destinations.Students}?classId=$it") } } }) { Row { TeacherMetric("班级人数", "$totalStudents", Icons.Filled.Groups, Blue) { drillDown { primaryClass?.id?.let { nav.navigateSingleTop("${Destinations.Students}?classId=$it") } } }; TeacherMetric("已测评", "$completed", Icons.Filled.Visibility, Green) { drillDown { nav.navigateSingleTop(Destinations.Tasks) } }; TeacherMetric("测评率", "$completionRate%", Icons.Filled.Refresh, Green) { drillDown { nav.navigateSingleTop(Destinations.Tasks) } }; TeacherMetric("待处理预警", "$risk", Icons.Filled.WarningAmber, Color.Red) { drillDown { nav.navigateSingleTop(Destinations.Review) } } } }
    Spacer(Modifier.height(7.dp)); BoardCard("7 项运动项目进度", if (isHistorical) "归档说明" else "查看任务", onClick = { drillDown { nav.navigateSingleTop(Destinations.Tasks) } }) {
        Text("仅统计学校场地端的综合运动能力测评任务。", color = Color.Gray, fontSize = 12.sp)
        Spacer(Modifier.height(8.dp))
        TestItem.entries.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { item ->
                    Surface(onClick = { drillDown { nav.navigateSingleTop(Destinations.Tasks) } }, modifier = Modifier.weight(1f).heightIn(min = 72.dp), color = Sky, shape = RoundedCornerShape(12.dp)) {
                        Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, tint = Blue, modifier = Modifier.size(21.dp))
                            Spacer(Modifier.width(8.dp))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text(item.label, color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, maxLines = 2)
                                val metric = remoteOverview?.itemStats?.firstOrNull { it.itemCode == item.label }
                                Text(metric?.let { "${it.measuredCount}/${it.totalCount}人 · ${"%.1f".format(it.averageScore)}分" } ?: if (state.repositoryAcknowledged) "暂无该项目数据" else "单项数据待同步", color = Color.Gray, fontSize = 12.sp)
                            }
                        }
                    }
                }
                repeat(2 - row.size) { Spacer(Modifier.weight(1f)) }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
    Spacer(Modifier.height(8.dp)); BoardCard("测评平均完成趋势", if (isHistorical) "归档说明" else "查看详情", onClick = { drillDown { nav.navigateSingleTop(Destinations.Tasks) } }) { EmptyState(if (isHistorical) "暂无历史趋势数据" else "暂无趋势数据。完成多个测评周期后显示真实趋势。") }
    Spacer(Modifier.height(8.dp)); BoardCard("重点关注学生", if (isHistorical) "归档说明" else "查看全部", onClick = { drillDown { nav.navigateSingleTop(Destinations.Review) } }) { if (isHistorical) Text("历史周期数据尚未同步，不展示演示统计或学生明细。", color = Color.Gray, fontSize = 12.sp) else if (useRemoteOverview && remoteOverview == null) Text("风险学生名单正在同步。", color = Color.Gray, fontSize = 12.sp) else { classStudents.filter { student -> val status = state.taskStatus(student, currentTask?.id); student.id in lowScoreStudentIds || status.name == "Review" || status.name == "Retest" }.take(3).forEach { student -> val status = state.taskStatus(student, currentTask?.id); Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).semantics { role = Role.Button; contentDescription = "查看${student.name}报告，状态${status.label}" }.clickable { onOpenReport(student) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { Text("${student.name}   ${student.className}   ${status.label}", color = Navy, fontSize = 12.sp, modifier = Modifier.weight(1f)); Icon(Icons.Filled.ChevronRight, contentDescription = "查看${student.name}报告", tint = Color.Gray, modifier = Modifier.size(16.dp)) } }; if (risk == 0) Text("当前班级暂无重点风险学生", color = Color.Gray, fontSize = 12.sp) } }
    Spacer(Modifier.height(9.dp)); Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = {
            val report = "向上少年 · ${primaryClassName}${selectedPeriod}数据报告\\n测评完成率：$completionRate%\\n已完成：$completed / $totalStudents 人\\n待处理预警：$risk 人\\n评测标准：小学综合运动能力标准 v1.0"
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, report) }, "导出班级数据报告"))
        }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Icon(Icons.Filled.IosShare, null, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(5.dp)); Text("导出班级报告", fontSize = 12.sp) }
        Button(onClick = { drillDown { nav.navigateSingleTop(Destinations.Review) } }, modifier = Modifier.weight(1f).heightIn(min = 48.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE35D5B))) { Icon(Icons.Filled.WarningAmber, null, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(5.dp)); Text(if (isHistorical) "查看归档说明" else "处理重点预警", fontSize = 12.sp) }
    }
    if (historicalDetailShown) AlertDialog(onDismissRequest = { historicalDetailShown = false }, title = { Text("2026春季测评归档") }, text = { Column { Text("历史汇总尚未同步，当前不展示演示人数、完成率或风险数。", color = Navy); Text("历史学生明细需由学校管理端授权后查看。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp)) } }, confirmButton = { TextButton(onClick = { historicalDetailShown = false }) { Text("关闭") } })
}

@Composable private fun BoardCard(title: String, action: String, onClick: () -> Unit, body: @Composable ColumnScope.() -> Unit) = Surface(modifier = Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) { Column(Modifier.padding(12.dp)) { SectionHeader(title, action, onClick); Spacer(Modifier.height(8.dp)); body() } }

@Composable fun TeacherClassesScreen(state: AppUiState, nav: NavHostController) = AppScaffold("我管理的班级", onBack = { nav.popBackStack() }) {
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@AppScaffold }
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    val data = state.data
    when {
        data.classes.isEmpty() -> EmptyState("暂无管理班级，学校完成分班后这里会显示。")
        else -> state.managedTeacherClasses.forEach { item ->
            val classStudents = data.students.filter { it.classId == item.id }
            // Student rows can be a paged directory. The class aggregate is
            // the only authoritative completion rate in a remote session.
            val completionRate = if (state.repositoryAcknowledged || classStudents.isEmpty()) item.completionRate else classStudents.count { state.taskStatus(it, data.tasks.firstOrNull()?.id) == com.xiangshang.youth.core.model.TaskStatus.Completed } * 100 / classStudents.size
            Surface(Modifier.fillMaxWidth().padding(vertical = 5.dp).semantics { role = Role.Button; contentDescription = "查看${item.name}学生列表，完成率${completionRate}%" }.clickable { nav.navigate("${Destinations.Students}?classId=${item.id}") }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(13.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(item.name, color = Navy, fontWeight = FontWeight.Bold); Text(item.studentCount.toString() + "人 · " + item.teacherName, fontSize = 12.sp, color = Color.Gray) }; Text(completionRate.toString() + "%", color = Green, fontWeight = FontWeight.Bold, fontSize = 18.sp) } }
        }
    }
}
@Composable
fun StudentListScreen(state: AppUiState, nav: NavHostController, classId: String? = null, outstandingOnly: Boolean = false, unassignedOnly: Boolean = false, onOpenStudent: (com.xiangshang.youth.core.model.Student) -> Unit, reportForStudent: (com.xiangshang.youth.core.model.Student) -> com.xiangshang.youth.core.model.DiagnosisReport? = { null }) = AppScaffold(when { outstandingOnly -> "优秀学生评选"; unassignedOnly -> "待分班学生"; else -> "学生列表" }, onBack = { nav.popBackStack() }) {
    val loadMoreStudents = LocalLoadMoreStudents.current
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@AppScaffold }
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    when {
        state.data.students.isEmpty() -> EmptyState("暂无学生数据，班级名单同步后会显示在这里。")
        else -> {
            val students = state.data.students.filter { student ->
                (classId == null || student.classId == classId) &&
                    (!outstandingOnly || (state.hasPublishedSchoolReport(student) && (reportForStudent(student)?.totalScore ?: 0.0) >= 30.0)) &&
                    (!unassignedOnly || student.className.isBlank())
            }.sortedByDescending { reportForStudent(it)?.totalScore ?: -1.0 }
            if (students.isEmpty()) EmptyState(if (unassignedOnly) "暂无待分班学生，当前学生均已完成班级归属；学校同步新的待分班名单后会显示在这里。" else "暂无符合条件的学生，总分达到 30 分且已完成测评的学生会显示在这里。")
            else {
                students.forEach {
                    StudentCard(it) { onOpenStudent(it) }
                    Spacer(Modifier.height(7.dp))
                }
                val total = state.data.studentTotal
                val loaded = state.data.students.size
                if (total != null && loaded < total) {
                    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        state.studentsLoadError?.let { Text(it, color = Color.Red, fontSize = 12.sp, textAlign = TextAlign.Center) }
                        Button(
                            onClick = loadMoreStudents,
                            enabled = !state.studentsLoadingMore && !state.isOffline,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).semantics { contentDescription = "加载更多学生，已显示${loaded}人，共${total}人" }
                        ) {
                            if (state.studentsLoadingMore) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(6.dp))
                            Text(if (state.studentsLoadingMore) "正在加载" else "加载更多学生（已显示${loaded}/${total}）")
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun TeacherTasksScreen(state: AppUiState, nav: NavHostController, saveUpload: (String, Int, String, String, String?, Boolean) -> Unit, submitUpload: (String, Int, String, String, String?) -> Unit = { taskId, attendance, notes, attachment, attachmentReference -> saveUpload(taskId, attendance, notes, attachment, attachmentReference, true) }, saveDraft: (String, String) -> Unit = { _, _ -> }, clearDraft: (String) -> Unit = {}, root: Boolean = false) {
    val taskId = state.data?.tasks?.firstOrNull()?.id ?: "after-class-upload-local"
    val uploaded = state.local.uploadedTaskIds.contains(taskId)
    var formOpen by remember { mutableStateOf(false) }
    @Composable fun Content() {
        val dashboardError = state.error
        when {
            dashboardError != null && state.data == null -> ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current)
            state.loading || state.data == null -> LoadingState()
            else -> {
                Surface(Modifier.fillMaxWidth(), color = Color(0xFFFFF2E4), shape = RoundedCornerShape(10.dp)) {
                    Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.CameraAlt, null, tint = Color(0xFFFF8B1F)); Spacer(Modifier.width(8.dp))
                        Column(Modifier.weight(1f)) { Text("课后上传测评结果与照片", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("课堂照片、测评记录、出勤名单", color = Color.Gray, fontSize = 12.sp) }
                        TextButton(onClick = { formOpen = true }) { Text(if (uploaded) "查看记录" else "去上传") }
                    }
                }
                state.local.courseUploads.firstOrNull { it.taskId == taskId }?.let {
                    val label = when (it.status) { LocalSubmissionStatus.PendingSync -> "已保存 · 待同步"; LocalSubmissionStatus.Submitted -> "已同步"; LocalSubmissionStatus.Failed -> "同步失败，可在设置中重试"; else -> "草稿" }
                    Text("$label · 出勤 ${it.attendanceCount} 人 · ${it.attachmentName}", color = if (it.status == LocalSubmissionStatus.Failed) Color.Red else Green, fontSize = 12.sp, modifier = Modifier.padding(top = 7.dp))
                }
                Spacer(Modifier.height(9.dp))
                if (state.data.tasks.isEmpty()) EmptyState("暂无延时课程任务，学校发布任务后会显示在这里。") else state.data.tasks.forEach {
                    TestTaskCard(it) { nav.navigate("${Destinations.TaskDetail}/${it.id}") }; Spacer(Modifier.height(8.dp))
                }
            }
        }
    }
    if (root) {
        Scaffold(containerColor = Canvas, bottomBar = { TeacherBottomBar(nav, Destinations.SportsUpload, sportsTeacher = true) }) { padding ->
            Column(Modifier.padding(padding).padding(horizontal = 12.dp).verticalScroll(rememberScrollState())) { Text("延时课程上传", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 12.dp, bottom = 9.dp)); Content() }
        }
    } else AppScaffold("延时课程上传", onBack = { nav.popBackStack() }) { Content() }
    if (formOpen) UploadDialog(taskId, state, saveUpload, submitUpload, saveDraft, clearDraft) { formOpen = false }
    }

private fun attachmentDisplayName(value: String): String = runCatching {
    value.toUri().lastPathSegment?.substringAfterLast('/')
}.getOrNull()?.takeIf { it.isNotBlank() } ?: value.substringAfterLast('/').ifBlank { "未选择附件" }

@Composable
private fun UploadDialog(taskId: String, state: AppUiState, save: (String, Int, String, String, String?, Boolean) -> Unit, submit: (String, Int, String, String, String?) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, dismiss: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val existing = state.local.courseUploads.firstOrNull { it.taskId == taskId }
    val attendanceDraftKey = "course-upload-$taskId-attendance"
    val notesDraftKey = "course-upload-$taskId-notes"
    val attachmentDraftKey = "course-upload-$taskId-attachment"
    val attachmentReferenceDraftKey = "course-upload-$taskId-attachment-reference"
    // A new upload starts empty; only a persisted record or draft may restore
    // values. This prevents a demo classroom record from being submitted by
    // accident in a school build.
    var attendance by remember(taskId) { mutableStateOf(existing?.attendanceCount?.toString() ?: state.local.drafts[attendanceDraftKey].orEmpty()) }
    var notes by remember(taskId) { mutableStateOf(existing?.notes ?: state.local.drafts[notesDraftKey].orEmpty()) }
    var attachment by remember(taskId) { mutableStateOf(existing?.attachmentName ?: state.local.drafts[attachmentDraftKey].orEmpty()) }
    var attachmentReference by remember(taskId) { mutableStateOf(existing?.attachmentReference ?: state.local.drafts[attachmentReferenceDraftKey]) }
    var pendingCameraAttachment by remember { mutableStateOf<CourseAttachmentStore.Attachment?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var result by remember { mutableStateOf<String?>(null) }
    val command = state.workflowStates["course:$taskId"] ?: WorkflowCommandState()
    fun persistDraft() {
        saveDraft(attendanceDraftKey, attendance)
        saveDraft(notesDraftKey, notes)
        saveDraft(attachmentDraftKey, attachment)
        attachmentReference?.let { saveDraft(attachmentReferenceDraftKey, it) } ?: clearDraft(attachmentReferenceDraftKey)
    }
    fun clearFormDraft() {
        clearDraft(attendanceDraftKey)
        clearDraft(notesDraftKey)
        clearDraft(attachmentDraftKey)
        clearDraft(attachmentReferenceDraftKey)
    }
    LaunchedEffect(command.status) { if (command.status == WorkflowCommandStatus.Succeeded) clearFormDraft() }
    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) runCatching { CourseAttachmentStore.copyPickedImage(context, uri) }
            .onSuccess { saved -> attachment = saved.file.name; attachmentReference = saved.file.toUri().toString(); error = null; persistDraft() }
            .onFailure { error = it.message ?: "附件无法读取，请重新选择。" }
    }
    val cameraPicker = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { captured ->
        val saved = pendingCameraAttachment
        if (captured && saved != null && saved.file.length() > 0L) {
            attachment = saved.file.name
            attachmentReference = saved.file.toUri().toString()
            error = null
            persistDraft()
        } else {
            saved?.file?.delete()
            error = "没有获得照片，请重试或使用文件选择。"
        }
        pendingCameraAttachment = null
    }
    fun beginCameraCapture(): Unit {
        val captureResult = runCatching {
            CourseAttachmentStore.createCameraFile(context).also { saved ->
                pendingCameraAttachment = saved
                cameraPicker.launch(FileProvider.getUriForFile(context, "${context.packageName}.files", saved.file))
            }
        }
        captureResult.onFailure { error = it.message ?: "暂时无法打开相机，请使用文件选择照片。" }
    }
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> if (granted) beginCameraCapture() else error = "相机权限未开启，请在系统设置中允许相机，或使用文件选择。" }
    fun openCamera() {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) beginCameraCapture()
        else cameraPermission.launch(Manifest.permission.CAMERA)
    }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text("延时课程上传") },
        text = {
            if (result != null || command.status == WorkflowCommandStatus.Succeeded) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.CheckCircle, null, tint = Green, modifier = Modifier.size(42.dp))
                    Text(result ?: "课程记录已保存，联网后自动进入审核。", color = Navy, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
                }
            } else Column {
                OutlinedTextField(value = attendance, onValueChange = { attendance = it; error = null; persistDraft() }, label = { Text("出勤人数") }, isError = error != null)
                OutlinedTextField(value = notes, onValueChange = { notes = it; error = null; persistDraft() }, label = { Text("课堂记录") }, minLines = 2, isError = error != null)
                Text("附件：${attachment.takeIf { it.isNotBlank() } ?: "未选择照片"}", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
                OutlinedButton(onClick = { openCamera() }, modifier = Modifier.padding(top = 4.dp)) { Icon(Icons.Filled.PhotoCamera, null); Spacer(Modifier.width(5.dp)); Text("拍摄课堂照片") }
                OutlinedButton(onClick = { imagePicker.launch("image/*") }, modifier = Modifier.padding(top = 4.dp)) { Icon(Icons.Filled.Photo, null); Spacer(Modifier.width(5.dp)); Text("选择课堂照片") }
                error?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
                if (command.status == WorkflowCommandStatus.Failed) Text(command.message ?: "提交失败，请重试", color = Color.Red, fontSize = 12.sp)
            }
        },
        confirmButton = {
            TextButton(onClick = {
                if (result != null || command.status == WorkflowCommandStatus.Succeeded) dismiss() else {
                    val count = attendance.toIntOrNull()
                    if (count == null || count <= 0 || notes.isBlank() || attachment.isBlank() || attachmentReference.isNullOrBlank()) error = "请补齐有效出勤人数、课堂记录和可上传的照片附件。"
                    else submit(taskId, count, notes.trim(), attachment, attachmentReference)
                }
            }, enabled = !command.isSubmitting) { if (command.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(if (result != null || command.status == WorkflowCommandStatus.Succeeded) "完成" else if (command.status == WorkflowCommandStatus.Failed) "重新提交" else "提交审核") }
        },
        dismissButton = if (result == null && command.status != WorkflowCommandStatus.Succeeded) ({ TextButton(onClick = {
            val count = attendance.toIntOrNull() ?: 0
            save(taskId, count, notes.trim(), attachment, attachmentReference, false)
            clearFormDraft()
            result = "草稿已保存，可稍后继续编辑。"
        }) { Text("保存草稿") } }) else null
    )
}
@Composable
fun TeacherTaskDetailScreen(state: AppUiState, nav: NavHostController, taskId: String?, submitStatus: (String, com.xiangshang.youth.core.model.TaskStatus, String?) -> Unit) = AppScaffold("任务详情", onBack = { nav.popBackStack() }) {
    var selectedStudent by remember { mutableStateOf<com.xiangshang.youth.core.model.Student?>(null) }
    var rosterSearch by rememberSaveable { mutableStateOf("") }
    var rosterStatus by rememberSaveable { mutableStateOf<TaskStatus?>(null) }
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@AppScaffold }
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    val data = state.data
    val task = data.tasks.firstOrNull { it.id == taskId } ?: data.tasks.firstOrNull()
    if (task == null) { EmptyState("暂无体测任务，学校发布任务后会显示在这里。"); return@AppScaffold }
    TestTaskCard(task)
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        OutlinedTextField(rosterSearch, { rosterSearch = it }, label = { Text("搜索学生或班级") }, singleLine = true, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        var menuExpanded by remember { mutableStateOf(false) }
        Box {
            TextButton(onClick = { menuExpanded = true }) { Text(rosterStatus?.label ?: "状态") }
            DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                DropdownMenuItem(text = { Text("全部状态") }, onClick = { rosterStatus = null; menuExpanded = false })
                TaskStatus.entries.forEach { status -> DropdownMenuItem(text = { Text(status.label) }, onClick = { rosterStatus = status; menuExpanded = false }) }
            }
        }
    }
    Text("学生测评状态", color = Navy, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 10.dp))
    Text("点击学生按现场队列更新签到、候测、测试、复核或补测状态；不支持跨步骤直接完成。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(vertical = 5.dp))
    when {
        state.repositoryAcknowledged && state.taskRosterRecords[task.id] == null -> LoadingState()
        else -> {
            val managedClassIds = state.managedTeacherClasses.map { it.id }.toSet()
            state.taskRosterStudents(task.id, task).filter { student ->
                val query = rosterSearch.trim()
                student.classId in managedClassIds &&
                    (query.isEmpty() || student.name.contains(query, ignoreCase = true) || student.className.contains(query, ignoreCase = true)) &&
                    (rosterStatus == null || state.taskStatus(student, task.id) == rosterStatus)
            }.forEach { student ->
                val taskStatus = state.taskStatus(student, task.id)
                TeacherStudentStatusRow(student, taskStatus, state.taskSyncStatus(student, task.id)) { selectedStudent = student }
                Spacer(Modifier.height(5.dp))
            }
        }
    }
    selectedStudent?.let { student ->
        val current = state.taskStatus(student, task.id)
        StatusSelectorDialog(
            student.name,
            current,
            state.workflowStates["task-status:${task.id}|${student.id}"] ?: WorkflowCommandState(),
            onSelect = { status -> submitStatus(student.id, status, null) },
            dismiss = { selectedStudent = null }
        )
    }
}

@Composable
fun ReviewListScreen(state: AppUiState, nav: NavHostController, submitDecision: (String, com.xiangshang.youth.core.model.TaskStatus, String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, loadBodyReviews: () -> Unit = {}, submitBodyReview: (com.xiangshang.youth.core.model.BodyScreeningReviewItem, com.xiangshang.youth.core.model.BodyScreeningReviewDecision, String, Set<com.xiangshang.youth.core.model.BodyCaptureTask>) -> Unit = { _, _, _, _ -> }, submitStatus: (String, com.xiangshang.youth.core.model.TaskStatus, String?, String?) -> Unit = { studentId, status, note, _ -> submitDecision(studentId, status, note.orEmpty()) }) = AppScaffold("预警中心", onBack = { nav.popBackStack() }) {
    var selectedStudent by remember { mutableStateOf<com.xiangshang.youth.core.model.Student?>(null) }
    var selectedBodyReview by remember { mutableStateOf<com.xiangshang.youth.core.model.BodyScreeningReviewItem?>(null) }
    var reviewMode by rememberSaveable { mutableIntStateOf(0) }
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@AppScaffold }
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(selected = reviewMode == 0, onClick = { reviewMode = 0 }, label = { Text("学校体测") }, modifier = Modifier.weight(1f))
        FilterChip(selected = reviewMode == 1, onClick = { reviewMode = 1 }, label = { Text("家庭身体观察") }, modifier = Modifier.weight(1f))
    }
    LaunchedEffect(reviewMode) { if (reviewMode == 1) loadBodyReviews() }
    if (reviewMode == 1) {
        BodyScreeningReviewQueue(state, onOpen = { selectedBodyReview = it }, retry = loadBodyReviews)
        selectedBodyReview?.let { item -> BodyScreeningReviewDialog(item, state.workflowStates["body-screening-review:${item.reviewId}"] ?: WorkflowCommandState(), submitBodyReview) { selectedBodyReview = null } }
        return@AppScaffold
    }
    val data = state.data
    val reviewTaskId = data.tasks.firstOrNull()?.id
    val managedClassIds = state.managedTeacherClasses.map { it.id }.toSet()
    val students = data.students.filter { student ->
        if (student.classId == null || student.classId !in managedClassIds) return@filter false
        val status = state.taskStatus(student, reviewTaskId)
        status.name == "Review" || status.name == "Retest" || status.name == "Absent"
    }
    Text("待处理 ${students.size} 人", color = Color.Red, fontWeight = FontWeight.Bold, fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp, bottom = 6.dp))
    students.forEach { student ->
        TeacherStudentStatusRow(student, state.taskStatus(student, reviewTaskId), state.taskSyncStatus(student, reviewTaskId)) { selectedStudent = student }
        state.taskReviewNote(student, reviewTaskId)?.let { note ->
            Text("复核意见：$note", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(start = 12.dp, top = 3.dp))
        }
        Spacer(Modifier.height(7.dp))
    }
    if (students.isEmpty()) EmptyState("当前没有待复核、待补测或缺席学生。")
    selectedStudent?.let { student ->
        val current = state.taskStatus(student, reviewTaskId)
        val draftKey = "review-note-${student.id}"
        ReviewDecisionDialog(
            student.name,
            current,
            state.local.drafts[draftKey] ?: state.taskReviewNote(student, reviewTaskId).orEmpty(),
            state.workflowStates["task-status:${reviewTaskId ?: "missing-task"}|${student.id}"] ?: WorkflowCommandState(),
            onDraftChanged = { saveDraft(draftKey, it) },
            onSubmit = { status, note -> submitStatus(student.id, status, note, reviewTaskId) },
            onSuccess = { clearDraft(draftKey); selectedStudent = null },
            dismiss = { selectedStudent = null }
        )
    }
}

@Composable
private fun BodyScreeningReviewQueue(state: AppUiState, onOpen: (com.xiangshang.youth.core.model.BodyScreeningReviewItem) -> Unit, retry: () -> Unit) {
    when {
        !state.teacherHasCapability("REVIEW_RESULT") -> ErrorState("当前账号没有身体观察复核权限。")
        state.bodyScreeningReviewsLoading && state.bodyScreeningReviews.isEmpty() -> LoadingState()
        state.bodyScreeningReviewsError != null && state.bodyScreeningReviews.isEmpty() -> ErrorState(state.bodyScreeningReviewsError, retry = retry)
        state.bodyScreeningReviews.isEmpty() -> EmptyState("暂无身体观察待复核记录。算法不确定、质量边界或风险候选记录将在这里显示。")
        else -> {
            Text("待处理 ${state.bodyScreeningReviews.size} 条 · 仅展示结构化证据，不包含原始照片或视频", color = Color.Gray, fontSize = 13.sp, modifier = Modifier.padding(vertical = 9.dp))
            state.bodyScreeningReviews.forEach { item ->
                Surface(
                    modifier = Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "${item.studentDisplayName}身体观察待复核，质量分${item.qualityScore ?: "未知"}" }.clickable { onOpen(item) },
                    color = Color.White,
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Column(Modifier.padding(15.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(item.studentDisplayName, color = Navy, fontSize = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                            Text("质量 ${item.qualityScore ?: "--"}", color = if ((item.qualityScore ?: 0) >= 70) Green else Color(0xFFFF8A24), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray)
                        }
                        Text("${item.attempts.size} 项结构化证据 · ${item.reasonCodes.joinToString("、") { bodyReviewReason(it) }}", color = Color.Gray, fontSize = 13.sp)
                        Text("${item.protocolVersion ?: "协议版本待同步"} · v${item.version}", color = Color.Gray, fontSize = 12.sp)
                    }
                }
                Spacer(Modifier.height(8.dp))
            }
        }
    }
}

@Composable
private fun BodyScreeningReviewDialog(
    item: com.xiangshang.youth.core.model.BodyScreeningReviewItem,
    command: WorkflowCommandState,
    submit: (com.xiangshang.youth.core.model.BodyScreeningReviewItem, com.xiangshang.youth.core.model.BodyScreeningReviewDecision, String, Set<com.xiangshang.youth.core.model.BodyCaptureTask>) -> Unit,
    dismiss: () -> Unit
) {
    var decision by rememberSaveable(item.reviewId) { mutableStateOf(com.xiangshang.youth.core.model.BodyScreeningReviewDecision.ContinueObservation) }
    var comment by rememberSaveable(item.reviewId) { mutableStateOf("") }
    // BodyCaptureTask is not Bundle-saveable. Keeping the selection scoped to
    // the currently visible dialog avoids a process-restoration crash while
    // the durable review itself remains server-owned.
    var tasks by remember(item.reviewId) { mutableStateOf(setOf<com.xiangshang.youth.core.model.BodyCaptureTask>()) }
    LaunchedEffect(command.status) { if (command.status == WorkflowCommandStatus.Succeeded) dismiss() }
    AlertDialog(
        onDismissRequest = { if (!command.isSubmitting) dismiss() },
        title = { Text("身体观察复核") },
        text = {
            Column(Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("${item.studentDisplayName} · 总质量 ${item.qualityScore ?: "未提供"}", color = Navy, fontWeight = FontWeight.Bold)
                item.attempts.forEach { attempt ->
                    Surface(color = Canvas, shape = RoundedCornerShape(12.dp)) {
                        Column(Modifier.padding(11.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(bodyCaptureTitle(attempt.captureTask), color = Navy, fontWeight = FontWeight.Bold)
                            Text("置信度 ${(attempt.confidence * 100).toInt()}% · ${attempt.sampleCount} 个有效样本 · ${attempt.attemptCount} 次采集", color = Color.Gray, fontSize = 13.sp)
                            attempt.qualityScore?.let { LinearProgressIndicator(progress = { it / 100f }, modifier = Modifier.fillMaxWidth(), color = if (it >= 70) Green else Color(0xFFFF8A24)) }
                            attempt.evidenceMetrics.forEach { metric ->
                                Column(
                                    Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = "${metric.label}，${metric.displayedValue}，来源${metric.sourceTitle}" },
                                    verticalArrangement = Arrangement.spacedBy(2.dp)
                                ) {
                                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                        Text(metric.label, color = Navy, fontSize = 14.sp, modifier = Modifier.weight(1f))
                                        Text(metric.displayedValue, color = Navy, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                    }
                                    Text(metric.sourceTitle, color = Color.Gray, fontSize = 12.sp)
                                }
                            }
                            if (attempt.evidenceMetrics.isEmpty()) Text("本动作暂无可展示的白名单指标，仅可依据采集质量决定是否重采。", color = Color.Gray, fontSize = 12.sp)
                        }
                    }
                }
                Text("“相对投影值”和“摄像头估计”不是物理厘米、ATR 或 Cobb 角。不提供原始照片或视频；复核结论仅用于健康管理与后续行动，不构成医疗诊断。", color = Color.Gray, fontSize = 12.sp)
                Text("处理方式", color = Navy, fontWeight = FontWeight.Bold)
                com.xiangshang.youth.core.model.BodyScreeningReviewDecision.entries.forEach { option ->
                    FilterChip(selected = decision == option, onClick = { decision = option }, label = { Text(option.label) }, modifier = Modifier.fillMaxWidth())
                }
                OutlinedTextField(value = comment, onValueChange = { comment = it }, label = { Text("复核依据和后续处理说明") }, minLines = 3, modifier = Modifier.fillMaxWidth())
                if (decision == com.xiangshang.youth.core.model.BodyScreeningReviewDecision.Recapture) {
                    Text("选择需要重新采集的动作", color = Navy, fontWeight = FontWeight.Bold)
                    com.xiangshang.youth.core.model.BodyCaptureTask.entries.forEach { task ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(checked = task in tasks, onCheckedChange = { checked -> tasks = if (checked) tasks + task else tasks - task })
                            Text(task.title, color = Navy)
                        }
                    }
                }
                if (command.status == WorkflowCommandStatus.Failed) Text(command.message ?: "提交失败，请重试", color = Color.Red, fontSize = 13.sp)
            }
        },
        confirmButton = { TextButton(onClick = { submit(item, decision, comment, tasks) }, enabled = !command.isSubmitting) { if (command.isSubmitting) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("确认提交") } },
        dismissButton = { TextButton(onClick = dismiss, enabled = !command.isSubmitting) { Text("取消") } }
    )
}

private fun bodyCaptureTitle(code: String): String = com.xiangshang.youth.core.model.BodyCaptureTask.entries.firstOrNull { it.apiCode == code }?.title ?: code
private fun bodyReviewReason(code: String): String = when (code) {
    "MODEL_PENDING_HUMAN_VALIDATION" -> "模型待人工验证"
    "RISK_CANDIDATE" -> "存在关注指标"
    "HIGH_UNCERTAINTY" -> "算法不确定性较高"
    "LOW_CONFIDENCE" -> "关键点置信度不足"
    "REPEATABILITY_FAILED" -> "两次采集一致性不足"
    else -> code.replace('_', ' ')
}

@Composable
private fun TeacherStudentStatusRow(student: com.xiangshang.youth.core.model.Student, status: com.xiangshang.youth.core.model.TaskStatus, syncState: LocalSubmissionStatus? = null, onClick: () -> Unit) = Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "更新${student.name}的测评状态，当前${status.label}${syncState?.let { "，${it.taskStatusLabel()}" } ?: ""}" }.clickable(onClick = onClick), color = Color.White, shape = RoundedCornerShape(10.dp)) {
    Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(student.name.take(1), color = Color.White, modifier = Modifier.background(Blue, CircleShape).padding(9.dp))
        Spacer(Modifier.width(9.dp))
        Column(Modifier.weight(1f)) { Text(student.name, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("${student.grade} · ${student.className}", color = Color.Gray, fontSize = 12.sp) }
        Column(horizontalAlignment = Alignment.End) {
            Text(status.label, color = statusColor(status), fontWeight = FontWeight.Bold, fontSize = 12.sp, modifier = Modifier.background(statusColor(status).copy(alpha = .12f), RoundedCornerShape(12.dp)).padding(horizontal = 8.dp, vertical = 4.dp))
            syncState?.let { Text(it.taskStatusLabel(), color = if (it == LocalSubmissionStatus.Failed) Color.Red else Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 2.dp)) }
        }
        Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.padding(start = 5.dp).size(16.dp))
    }
}

private fun LocalSubmissionStatus.taskStatusLabel(): String = when (this) {
    LocalSubmissionStatus.Draft -> "本地草稿"
    LocalSubmissionStatus.PendingSync -> "待同步"
    LocalSubmissionStatus.Submitting -> "同步中"
    LocalSubmissionStatus.Submitted -> "已同步"
    LocalSubmissionStatus.Failed -> "同步失败"
}

@Composable
private fun StatusSelectorDialog(
    studentName: String,
    current: com.xiangshang.youth.core.model.TaskStatus,
    command: WorkflowCommandState,
    onSelect: (com.xiangshang.youth.core.model.TaskStatus) -> Unit,
    dismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text("更新${studentName}的测评状态") },
        text = {
            Column {
                when (command.status) {
                    WorkflowCommandStatus.Submitting -> Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(7.dp)); Text("正在提交状态…", color = Blue, fontSize = 12.sp) }
                    WorkflowCommandStatus.Succeeded -> Text(command.message ?: "状态已提交。", color = Green, fontSize = 12.sp)
                    WorkflowCommandStatus.Failed -> Text(command.message ?: "提交失败，请重试。", color = Color.Red, fontSize = 12.sp)
                    WorkflowCommandStatus.Idle -> Unit
                }
                current.allowedNextStatuses().forEach { status ->
                    TextButton(onClick = { onSelect(status) }, enabled = !command.isSubmitting, modifier = Modifier.fillMaxWidth()) {
                        Text(
                            status.label,
                            color = if (status == current) Blue else Navy,
                            fontWeight = if (status == current) FontWeight.Bold else FontWeight.Normal
                        )
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = dismiss) { Text(if (command.status == WorkflowCommandStatus.Succeeded) "完成" else "取消") } }
    )
}

@Composable
private fun ReviewDecisionDialog(
    studentName: String,
    current: com.xiangshang.youth.core.model.TaskStatus,
    initialNote: String,
    command: WorkflowCommandState,
    onDraftChanged: (String) -> Unit,
    onSubmit: (com.xiangshang.youth.core.model.TaskStatus, String) -> Unit,
    onSuccess: () -> Unit,
    dismiss: () -> Unit
) {
    var note by rememberSaveable(studentName) { mutableStateOf(initialNote) }
    var selectedStatus by rememberSaveable(studentName) { mutableStateOf(current) }
    var validation by rememberSaveable(studentName) { mutableStateOf<String?>(null) }
    LaunchedEffect(command.status) { if (command.status == WorkflowCommandStatus.Succeeded) onSuccess() }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text("处理${studentName}预警") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text("记录证据核验结果、是否需要补测及后续处理。", color = Color.Gray, fontSize = 12.sp)
                OutlinedTextField(value = note, onValueChange = { note = it; onDraftChanged(it); validation = null }, label = { Text("复核 / 补测处理意见") }, minLines = 3, isError = validation != null)
                validation?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
                when (command.status) {
                    WorkflowCommandStatus.Submitting -> Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(7.dp)); Text("正在提交处理…", color = Blue, fontSize = 12.sp) }
                    WorkflowCommandStatus.Failed -> Text(command.message ?: "提交失败，请重试。", color = Color.Red, fontSize = 12.sp)
                    else -> Unit
                }
                Text("处理结论", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                current.allowedNextStatuses().forEach { status ->
                    FilterChip(selected = selectedStatus == status, onClick = { selectedStatus = status }, label = { Text(status.label, fontSize = 12.sp) })
                }
            }
        },
        confirmButton = {
            TextButton(enabled = !command.isSubmitting, onClick = {
                if (note.trim().isBlank()) validation = "请填写复核或补测处理意见。" else onSubmit(selectedStatus, note)
            }) { if (command.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(if (command.status == WorkflowCommandStatus.Failed) "重新提交" else "提交处理") }
        },
        dismissButton = { TextButton(onClick = dismiss) { Text("取消") } }
    )
}

private fun statusColor(status: com.xiangshang.youth.core.model.TaskStatus): Color = when (status.name) {
    "Completed" -> Green; "Review", "Absent" -> Color.Red; "Retest" -> Color(0xFFFF8B1F); "Testing" -> Blue; else -> Color(0xFF7B8798)
}
