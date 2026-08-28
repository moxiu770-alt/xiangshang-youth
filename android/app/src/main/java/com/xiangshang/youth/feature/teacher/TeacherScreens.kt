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

private fun postSyncLabel(status: LocalSubmissionStatus): String = when (status) {
    LocalSubmissionStatus.Submitted -> "已同步"
    LocalSubmissionStatus.Failed -> "同步失败，可在设置中重试"
    LocalSubmissionStatus.Submitting -> "正在同步"
    LocalSubmissionStatus.Draft -> "未完成"
    LocalSubmissionStatus.PendingSync -> "已保存，联网后自动同步"
}

internal fun teacherCapabilitySummary(state: AppUiState): String {
    val capabilities = state.profile?.capabilities.orEmpty()
    val labels = buildList {
        if ("MANAGE_CLASS_STUDENTS" in capabilities || "VIEW_CLASS_DASHBOARD" in capabilities) add("班级管理")
        if ("UPLOAD_AFTER_SCHOOL_COURSE" in capabilities) add("延时课程")
        if ("REVIEW_RESULT" in capabilities || "REQUEST_RETEST" in capabilities) add("复核与补测")
        if ("PUBLISH_CLASS_NOTICE" in capabilities) add("班级通知")
    }
    return if (labels.isEmpty()) "已授权工作台" else labels.joinToString(" · ")
}

/** Mirrors the two teacher workbenches in the supplied mobile reference screens. */
@Composable
fun TeacherHomeScreen(state: AppUiState, nav: NavHostController, setSportsWorkbench: (Boolean) -> Unit, refreshDashboard: () -> Unit = {}, reportForStudent: (com.xiangshang.youth.core.model.Student) -> com.xiangshang.youth.core.model.DiagnosisReport? = { null }) {
    val sportsTeacher = state.local.teacherUsesSportsWorkbench
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) {
        TeacherUnavailableState(state, nav, dashboardError, refreshDashboard)
        return
    }
    if (state.loading || state.data == null) {
        TeacherUnavailableState(state, nav, null, refreshDashboard)
        return
    }
    val reduceMotion = LocalReduceMotion.current
    Scaffold(containerColor = Canvas, bottomBar = { TeacherBottomBar(nav, sportsTeacher = sportsTeacher) }) { inset ->
        Box(Modifier.padding(inset).fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        LazyColumn(
            modifier = Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight(),
            contentPadding = PaddingValues(bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item { TeacherIdentity(state.activeDisplayName, sportsTeacher, nav, state.unreadMessageCount, state.loading, refreshDashboard, onSwitchRole = { if (state.teacherHasCapability("UPLOAD_AFTER_SCHOOL_COURSE")) setSportsWorkbench(!sportsTeacher) }, classSubtitle = state.managedTeacherClasses.joinToString("、") { it.name }.ifBlank { "授权班级" }, schoolName = state.profile?.schoolName ?: "学校") }
            item { TeacherRoleSwitch(sportsTeacher, setSportsWorkbench, state.teacherHasCapability("UPLOAD_AFTER_SCHOOL_COURSE")) }
            item {
                // The application-level accessibility setting must affect the
                // role-panel swap too.  Leaving AnimatedContent's default
                // transform here made “减少动态效果” incomplete on Android.
                AnimatedContent(
                    targetState = sportsTeacher,
                    transitionSpec = {
                        if (reduceMotion) {
                            EnterTransition.None togetherWith ExitTransition.None
                        } else {
                            fadeIn(animationSpec = tween(180)) togetherWith fadeOut(animationSpec = tween(120))
                        }
                    },
                    label = "teacher-role-content"
                ) { isSports ->
                    if (isSports) SportsTeacherPanel(state, nav) else ClassTeacherPanel(state, nav, reportForStudent)
                }
            }
        }
        }
    }
}

@Composable
private fun TeacherIdentity(name: String, sportsTeacher: Boolean, nav: NavHostController, unreadCount: Int, isRefreshing: Boolean, onRefresh: () -> Unit, onSwitchRole: (() -> Unit)? = null, classSubtitle: String = "授权班级", schoolName: String = "学校") = Row(
    Modifier.fillMaxWidth().background(Color.White).padding(horizontal = 13.dp, vertical = 8.dp),
    verticalAlignment = Alignment.CenterVertically
) {
    Image(painterResource(R.drawable.teacher_avatar), name, Modifier.size(44.dp).clip(CircleShape), contentScale = ContentScale.Crop)
    Spacer(Modifier.width(8.dp))
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(name, color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Text(schoolName, color = Color(0xFF7B8798), fontSize = 16.sp)
        Text(if (sportsTeacher) "延时课程工作台" else classSubtitle, color = Green, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
    }
    onSwitchRole?.let { action ->
        AssistChip(onClick = action, label = { Text("切换角色", fontSize = 16.sp) }, modifier = Modifier.heightIn(min = 44.dp))
        Spacer(Modifier.width(7.dp))
    }
    IconButton(onClick = onRefresh, enabled = !isRefreshing) { if (isRefreshing) CircularProgressIndicator(Modifier.size(17.dp), color = Blue, strokeWidth = 2.dp) else Icon(Icons.Filled.Refresh, contentDescription = "刷新数据", tint = Navy, modifier = Modifier.size(19.dp)) }
        IconButton(onClick = { nav.navigateSingleTop(RoleMessageDestination.resolve(UserRole.Teacher)) }) { BadgedBox(badge = { if (unreadCount > 0) Badge(containerColor = Color.Red, modifier = Modifier.size(6.dp)) {} }) { Icon(Icons.Filled.NotificationsNone, contentDescription = "消息通知", tint = Navy, modifier = Modifier.size(20.dp)) } }
}

@Composable
private fun TeacherRoleSwitch(sports: Boolean, onSelect: (Boolean) -> Unit, canUseSports: Boolean) = Row(
    Modifier.fillMaxWidth().padding(horizontal = 18.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)
) {
    TeacherRoleChip("班级工作台", Icons.Filled.Groups, !sports, Blue, Modifier.weight(1f)) { onSelect(false) }
    // Role selection is an identity control, so it shares the blue account
    // palette with “班主任”. Green is reserved for completed/healthy metrics.
    if (canUseSports) TeacherRoleChip("延时课程", Icons.AutoMirrored.Filled.DirectionsRun, sports, Blue, Modifier.weight(1f)) { onSelect(true) }
}

@Composable
private fun TeacherRoleChip(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, selected: Boolean, color: Color, modifier: Modifier, onClick: () -> Unit) {
    Surface(modifier = modifier.heightIn(min = 48.dp).semantics { role = Role.Button; contentDescription = "切换为$label" }.clickable(onClick = onClick), color = if (selected) color else color.copy(alpha = .14f), shape = RoundedCornerShape(9.dp)) {
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = if (selected) Color.White else color, modifier = Modifier.size(21.dp))
            Spacer(Modifier.width(9.dp)); Text(label, color = if (selected) Color.White else color, fontWeight = FontWeight.Bold, fontSize = 16.sp)
        }
    }
}

@Composable
private fun ClassTeacherPanel(state: AppUiState, nav: NavHostController, reportForStudent: (com.xiangshang.youth.core.model.Student) -> com.xiangshang.youth.core.model.DiagnosisReport?) = Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
    val managedClasses = state.managedTeacherClasses
    val managedClassIds = managedClasses.map { it.id }.toSet()
    val primaryClassId = managedClasses.firstOrNull()?.id
    val primaryClassName = managedClasses.firstOrNull()?.name ?: "我的班级"
    val classStudents = state.data?.students?.filter { it.classId in managedClassIds }.orEmpty()
    val currentTaskId = state.data?.tasks?.firstOrNull()?.id
    val measured = classStudents.count { state.taskStatus(it, currentTaskId).name == "Completed" }
    val officialReports = classStudents.filter(state::hasPublishedSchoolReport).mapNotNull(reportForStudent)
    val lowScoreStudentIds = officialReports.filter { it.requiresFollowUp }.map { it.student.id }.toSet()
    val highScoreStudentIds = officialReports.filter { it.isComplete && it.totalScore >= AssessmentScoreRules.highTotalThreshold && !it.requiresReview }.map { it.student.id }.toSet()
    val risk = classStudents.count { val status = state.taskStatus(it, currentTaskId); it.id in lowScoreStudentIds || status.name == "Review" || status.name == "Retest" }
    Text("▣  仅查看所有测评数据及授权数据", Modifier.fillMaxWidth(), color = Color(0xFF7F8792), fontSize = 16.sp, textAlign = TextAlign.Center)
    Surface(Modifier.padding(horizontal = 18.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
        Column(Modifier.padding(vertical = 10.dp)) {
            SectionHeader("班级健康概览", "查看班级看板") { nav.navigateSingleTop(Destinations.TeacherBoard) }
            Row(Modifier.fillMaxWidth().padding(top = 9.dp)) {
                TeacherMetric("班级人数", "${classStudents.size}", Icons.Filled.Groups, Blue) { primaryClassId?.let { nav.navigateSingleTop("${Destinations.Students}?classId=$it") } }
                TeacherMetric("已测评", "$measured", Icons.Filled.Visibility, Green, actionDescription = "打开体测任务") { nav.navigateSingleTop(Destinations.Tasks) }
                TeacherMetric("测评率", "${if (classStudents.isEmpty()) 0 else measured * 100 / classStudents.size}%", Icons.Filled.Refresh, Green) { nav.navigateSingleTop(Destinations.TeacherBoard) }
                TeacherMetric("待处理预警", "$risk", Icons.Filled.WarningAmber, Color(0xFFFF4242)) { nav.navigateSingleTop(Destinations.Review) }
            }
            HorizontalDivider(Modifier.padding(horizontal = 18.dp, vertical = 8.dp), color = Color(0xFFF0F2F7))
            Text("问题分布（人）", Modifier.padding(horizontal = 18.dp), color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Row(Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 7.dp)) {
                TeacherIssue(Icons.Filled.WarningAmber, "${lowScoreStudentIds.size}", "低分", Color(0xFFFFB024)) { nav.navigateSingleTop(Destinations.TeacherBoard) }; TeacherIssue(Icons.AutoMirrored.Filled.DirectionsRun, "${highScoreStudentIds.size}", "表现良好", Blue) { primaryClassId?.let { nav.navigateSingleTop("${Destinations.Students}?classId=$it") } }
                TeacherIssue(Icons.Filled.RateReview, "${classStudents.count { state.taskStatus(it, currentTaskId).name == "Review" }}", "待复核", Color(0xFF9A60F5)) { nav.navigateSingleTop(Destinations.Review) }; TeacherIssue(Icons.Filled.EventRepeat, "${classStudents.count { state.taskStatus(it, currentTaskId).name == "Retest" }}", "待补测", Color(0xFFFF638E)) { nav.navigateSingleTop(Destinations.Tasks) }
            }
        }
    }
    TeacherActionGrid(nav)
    if (state.repositoryAcknowledged) {
        EmptyState("今日任务由学校数据同步后显示")
    } else {
        Surface(Modifier.padding(horizontal = 18.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp), shadowElevation = 1.dp) {
            Column(Modifier.padding(vertical = 9.dp)) {
                SectionHeader("今日任务", "查看全部") { nav.navigateSingleTop(Destinations.Tasks) }
                SportsTask("16:30", "16:30 · 17:10", "$primaryClassName 综合测评", Green) { nav.navigateSingleTop(Destinations.Tasks) }
                SportsTask("17:20", "17:20 · 18:00", "体能提升课", Blue) { nav.navigateSingleTop(Destinations.Tasks) }
            }
        }
    }
}

@Composable
internal fun RowScope.TeacherMetric(label: String, value: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, actionDescription: String? = null, onClick: () -> Unit) = Surface(onClick = onClick, modifier = Modifier.weight(1f).semantics { role = Role.Button; contentDescription = actionDescription ?: "$label：$value，查看详情" }, color = Color.Transparent, shape = RoundedCornerShape(8.dp)) {
    Column(Modifier.fillMaxWidth().padding(vertical = 3.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, color = Color(0xFF798699), fontSize = 16.sp)
        Row(verticalAlignment = Alignment.CenterVertically) { Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 19.sp); Spacer(Modifier.width(3.dp)); Icon(icon, null, tint = color, modifier = Modifier.size(15.dp)) }
    }
}

@Composable
private fun RowScope.TeacherIssue(icon: androidx.compose.ui.graphics.vector.ImageVector, value: String, label: String, color: Color, onClick: () -> Unit) = Surface(onClick = onClick, modifier = Modifier.weight(1f).semantics { role = Role.Button; contentDescription = "$label：$value，查看详情" }, color = Color.Transparent, shape = RoundedCornerShape(8.dp)) {
    Column(Modifier.fillMaxWidth().padding(vertical = 3.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, contentDescription = label, tint = color, modifier = Modifier.size(20.dp)); Text(value, color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp); Text(label, color = Color(0xFF7D8797), fontSize = 16.sp)
    }
}

@Composable
private fun TeacherActionGrid(nav: NavHostController) {
    val actions = listOf(
        Triple("班级看板", Icons.Filled.Dashboard, Blue), Triple("预警中心", Icons.Filled.Warning, Color(0xFFFF4444)),
        Triple("学生列表", Icons.Filled.Groups, Green), Triple("待分班学生", Icons.Filled.PersonAdd, Color(0xFFFF9E24)),
        Triple("查看延时课", Icons.AutoMirrored.Filled.DirectionsRun, Color(0xFF10C9B7)), Triple("优秀学生评选", Icons.Filled.WorkspacePremium, Color(0xFF8755F4)),
        // Keep the required class-management surface reachable from the
        // teacher workbench instead of duplicating the student-list shortcut.
        Triple("班级管理", Icons.Filled.Badge, Color(0xFFFF9E24))
    )
    // Compose scales sp automatically.  At large system font sizes, a four-up
    // grid squeezes labels into unreadable ellipses, so use the same two-up
    // accessibility layout as iOS while keeping the reference four-up layout
    // at the default font scale.
    val columns = if (LocalDensity.current.fontScale > 1.25f) 2 else 4
    Column(Modifier.padding(horizontal = 18.dp).fillMaxWidth().background(Color.White, RoundedCornerShape(10.dp)).padding(9.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        actions.chunked(columns).forEach { row -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            row.forEach { (title, icon, color) ->
                Surface(Modifier.weight(1f).heightIn(min = 67.dp).semantics { role = Role.Button; contentDescription = title }.clickable { nav.navigate(when (title) { "班级看板" -> Destinations.TeacherBoard; "班级管理" -> Destinations.Classes; "预警中心" -> Destinations.Review; "优秀学生评选" -> Destinations.OutstandingStudents; "待分班学生" -> Destinations.UnassignedStudents; "学生列表" -> Destinations.Students; else -> Destinations.Tasks }) }, color = color.copy(alpha = .055f), shape = RoundedCornerShape(9.dp)) {
                    Column(Modifier.fillMaxSize().padding(vertical = 7.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) { Surface(color = color, shape = RoundedCornerShape(12.dp), modifier = Modifier.size(31.dp)) { Icon(icon, null, tint = Color.White, modifier = Modifier.padding(7.dp)) }; Spacer(Modifier.height(4.dp)); Text(title, color = Navy, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = if (columns == 2) 2 else 1, textAlign = TextAlign.Center) }
                }
            }
            repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
        } }
    }
}

@Composable
private fun SportsTeacherPanel(state: AppUiState, nav: NavHostController) = Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
    val tasks = state.data?.tasks.orEmpty()
    val taskCounts = tasks.map { task ->
        val taskStudents = task.scopedStudents(state.data?.students.orEmpty())
        if (taskStudents.isEmpty()) task.completedCount to task.totalCount
        else taskStudents.count { state.taskStatus(it, task.id) == com.xiangshang.youth.core.model.TaskStatus.Completed } to taskStudents.size
    }
    val completed = taskCounts.sumOf { it.first }
    val total = taskCounts.sumOf { it.second }.coerceAtLeast(1)
    Surface(Modifier.padding(horizontal = 18.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
        Column(Modifier.padding(vertical = 10.dp)) {
                SectionHeader("近日测评提醒", "查看全部") { nav.navigateSingleTop(Destinations.Tasks) }
            Row(Modifier.fillMaxWidth().padding(top = 9.dp)) { TeacherMetric("待测班级", "${tasks.count { it.completedCount < it.totalCount }}", Icons.Filled.Folder, Blue) { nav.navigateSingleTop(Destinations.Tasks) }; TeacherMetric("测评学生", "$total", Icons.Filled.Person, Green) { nav.navigateSingleTop(Destinations.Students) }; TeacherMetric("今日排班", "${tasks.size}", Icons.Filled.CalendarMonth, Color(0xFFFF9D28)) { nav.navigateSingleTop(Destinations.Tasks) }; TeacherMetric("待上传", "${tasks.count { it.completedCount < it.totalCount }}", Icons.Filled.CloudUpload, Color(0xFF8B5AF5)) { nav.navigateSingleTop(Destinations.Tasks) } }
            Row(Modifier.padding(horizontal = 13.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) { Text("进度", color = Color(0xFF738094), fontSize = 16.sp); Spacer(Modifier.width(8.dp)); LinearProgressIndicator({ completed.toFloat() / total }, Modifier.weight(1f).height(5.dp).clip(CircleShape), color = Green, trackColor = Color(0xFFDEF1E8)); Spacer(Modifier.width(8.dp)); Text("${completed * 100 / total}%", color = Green, fontSize = 16.sp, fontWeight = FontWeight.Bold) }
        }
    }
    Row(Modifier.padding(horizontal = 18.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { SportsShortcut("学生管理", Icons.Filled.Groups, Green, Modifier.weight(1f)) { nav.navigateSingleTop(Destinations.Students) }; SportsShortcut("班级排课", Icons.Filled.CalendarMonth, Blue, Modifier.weight(1f)) { nav.navigateSingleTop(Destinations.Tasks) } }
    Surface(Modifier.padding(horizontal = 18.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(vertical = 10.dp)) { SectionHeader("今日任务", "查看全部") { nav.navigateSingleTop(Destinations.Tasks) }; if (tasks.isEmpty()) { Text("暂无已排期任务", color = Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(horizontal = 13.dp, vertical = 10.dp)) } else { tasks.take(2).forEachIndexed { index, task -> val color = if (index == 0) Green else Blue; SportsTask(task.date.substringAfter(" ").take(5), task.date, "${task.className} · ${task.title}", color) { nav.navigateSingleTop(Destinations.TaskDetailRoute.replace("{taskId}", task.id)) } } } } }
    Surface(Modifier.padding(horizontal = 18.dp).fillMaxWidth().semantics { role = Role.Button; contentDescription = "上传课后测评结果和照片" }.clickable { nav.navigateSingleTop(Destinations.Tasks) }, color = Color(0xFFFFAA25), shape = RoundedCornerShape(9.dp)) { Row(Modifier.padding(vertical = 10.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.CameraAlt, null, tint = Color.White, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(7.dp)); Text("课后上传测评结果记录与照片", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp) } }
}

@Composable private fun SportsShortcut(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, modifier: Modifier, onClick: () -> Unit) = Surface(modifier.height(82.dp).semantics { role = Role.Button; contentDescription = "查看$label" }.clickable(onClick = onClick), color = color.copy(alpha = .065f), shape = RoundedCornerShape(10.dp)) { Row(Modifier.fillMaxSize().padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = color, modifier = Modifier.size(27.dp)); Spacer(Modifier.width(9.dp)); Column { Text(label, color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp); Text("查看详情 ›", color = color, fontSize = 16.sp) } } }
@Composable private fun SportsTask(time: String, duration: String, title: String, color: Color, onClick: (() -> Unit)? = null) = Row(Modifier.padding(horizontal = 13.dp, vertical = 6.dp).then(if (onClick == null) Modifier else Modifier.clickable(onClick = onClick).semantics { role = Role.Button; contentDescription = "查看任务：$title，$duration" }), verticalAlignment = Alignment.CenterVertically) { Surface(color = color.copy(alpha = .13f), shape = CircleShape, modifier = Modifier.size(28.dp)) { Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, tint = color, modifier = Modifier.padding(6.dp)) }; Spacer(Modifier.width(8.dp)); Column(Modifier.weight(1f)) { Text(duration, color = Color(0xFF778497), fontSize = 16.sp); Text(title, color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 16.sp) }; Text(time, color = color, fontWeight = FontWeight.Bold, fontSize = 16.sp); if (onClick != null) { Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.size(15.dp)) } }
@Composable internal fun SectionHeader(title: String, action: String, onClick: () -> Unit) = Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) { Text(title, color = Blue, fontWeight = FontWeight.Bold, fontSize = 15.sp, modifier = Modifier.semantics { heading() }); Spacer(Modifier.weight(1f)); Text(action + "  ›", color = Blue, fontSize = 16.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "$title：$action" }.clickable(onClick = onClick)) }

@Composable
internal fun TeacherBottomBar(nav: NavHostController, selected: String = Destinations.Teacher, sportsTeacher: Boolean = false) = NavigationBar(containerColor = Color.White, tonalElevation = 1.dp) {
    fun go(route: String) { nav.navigate(route) { popUpTo(Destinations.Teacher) { saveState = true }; launchSingleTop = true; restoreState = true } }
    NavigationBarItem(selected = selected == Destinations.Teacher, onClick = { go(Destinations.Teacher) }, icon = { Icon(Icons.Filled.Home, null) }, label = { Text("首页", fontSize = 16.sp, maxLines = 1) }, modifier = Modifier.semantics { contentDescription = "首页${if (selected == Destinations.Teacher) "，当前页面" else ""}" })
    val secondary = if (sportsTeacher) Destinations.SportsUpload else Destinations.TeacherCircle
    NavigationBarItem(selected = selected == secondary, onClick = { go(secondary) }, icon = { Icon(if (sportsTeacher) Icons.Filled.CameraAlt else Icons.Filled.Dashboard, null) }, label = { Text(if (sportsTeacher) "延时上传" else "班级圈", fontSize = 16.sp, maxLines = 1) }, modifier = Modifier.semantics { contentDescription = "${if (sportsTeacher) "延时上传" else "班级圈"}${if (selected == secondary) "，当前页面" else ""}" })
    NavigationBarItem(selected = selected == Destinations.Account, onClick = { go(Destinations.Account) }, icon = { Icon(Icons.Filled.PersonOutline, null) }, label = { Text("我的", fontSize = 16.sp, maxLines = 1) }, modifier = Modifier.semantics { contentDescription = "我的${if (selected == Destinations.Account) "，当前页面" else ""}" })
}

@Composable
fun TeacherClassCircleScreen(
    state: AppUiState,
    nav: NavHostController,
    publishPost: (String, String) -> Unit,
    updatePost: (String, String) -> Unit,
    saveDraft: (String, String) -> Unit,
    clearDraft: (String) -> Unit,
    refreshDashboard: () -> Unit = {},
    submitPost: (String, String) -> Unit = publishPost,
    loadNotificationDrafts: () -> Unit = {},
    saveNotificationDraft: (String?, List<String>, String, String, Int?, Boolean, String?, (com.xiangshang.youth.core.service.NotificationCampaign?) -> Unit) -> Unit = { _, _, _, _, _, _, _, done -> done(null) },
    sendNotificationDraft: (String) -> Unit = {},
    discardNotificationDraft: (String) -> Unit = {},
    clearWorkflow: (String) -> Unit = {},
    loadClassPosts: (String?) -> Unit = {},
    deleteClassPost: (com.xiangshang.youth.core.service.ClassPost) -> Unit = {},
    reportClassPost: (com.xiangshang.youth.core.service.ClassPost) -> Unit = {},
    setClassPostPinned: (com.xiangshang.youth.core.service.ClassPost, Boolean) -> Unit = { _, _ -> }
) {
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) {
        TeacherUnavailableState(state, nav, dashboardError, refreshDashboard, selected = Destinations.TeacherCircle)
        return
    }
    if (state.loading || state.data == null) {
        TeacherUnavailableState(state, nav, null, refreshDashboard, selected = Destinations.TeacherCircle)
        return
    }
    // A first-time school account can have a successful dashboard response but
    // no roster yet. Keep the teacher workbench chrome in that empty state so
    // the teacher can still switch tabs, open notifications, or retry later.
    if (state.data.students.isEmpty()) {
        TeacherEmptyRootState(state, nav, Destinations.TeacherCircle, "暂无班级动态，班级名单同步后会显示在这里。")
        return
    }
    var composer by remember { mutableStateOf(false) }
    var noticeComposer by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    var editingPost by remember { mutableStateOf<com.xiangshang.youth.core.service.ClassPost?>(null) }
    val composerDraftKey = "teacher-class-circle-composer"
    val currentTeacherName = state.activeDisplayName
    // Display names are presentation data and may collide. Workflow and
    // draft state must be scoped by the stable account id instead.
    val currentTeacherKey = "post:${state.profile?.id ?: "session"}"
    val primaryClassId = state.managedTeacherClasses.firstOrNull()?.id
    val primaryClassName = state.managedTeacherClasses.firstOrNull()?.name ?: "我的班级"
    val primaryClassCount = state.data.students.count { it.classId == primaryClassId }
    LaunchedEffect(state.repositoryAcknowledged, primaryClassId) {
        if (state.repositoryAcknowledged) loadClassPosts(null)
    }
    Scaffold(containerColor = Canvas, bottomBar = { TeacherBottomBar(nav, Destinations.TeacherCircle) }) { padding -> Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.TopCenter) { Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight().verticalScroll(rememberScrollState())) {
        if (!state.repositoryAcknowledged) {
            Surface(Modifier.padding(16.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) { Column(Modifier.padding(16.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Campaign, null, tint = Blue); Spacer(Modifier.width(7.dp)); Text("班级公告", color = Navy, fontWeight = FontWeight.Bold); Spacer(Modifier.weight(1f)); Text("全部公告 ›", color = Blue, fontSize = 16.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "查看全部班级公告" }.clickable { notice = "全部班级公告\n请家长于 9 月 12 日前完成孩子健康信息确认，并留意测评时间与场地安排。" }) }; Text("秋季综合测评通知", color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.padding(top = 10.dp).semantics { role = Role.Button; contentDescription = "查看秋季综合测评通知" }.clickable { notice = "秋季综合测评通知\n请家长于 9 月 12 日前完成孩子健康信息确认。测评当天请为孩子准备舒适运动服和饮水。" }); Text("请家长于 9 月 12 日前完成孩子健康信息确认。", color = Color.Gray, fontSize = 16.sp) } }
        }
        Row(Modifier.fillMaxWidth().background(Color.White).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Image(painterResource(R.drawable.teacher_avatar), null, Modifier.size(38.dp).clip(CircleShape), contentScale = ContentScale.Crop)
            Spacer(Modifier.width(8.dp))
            Column(Modifier.weight(1f)) {
                Text("$primaryClassName · 班级圈", color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                Text("${state.profile?.schoolName ?: "学校"} · ${primaryClassCount}名学生", color = Color.Gray, fontSize = 16.sp)
            }
            IconButton(onClick = { nav.navigateSingleTop(RoleMessageDestination.resolve(UserRole.Teacher)) }) {
                Icon(Icons.Filled.Notifications, contentDescription = "消息通知", tint = Blue)
            }
        }
        Row(Modifier.padding(horizontal = 18.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { clearWorkflow(currentTeacherKey); composer = true }, modifier = Modifier.weight(1f)) { Icon(Icons.Filled.Edit, null); Spacer(Modifier.width(5.dp)); Text("发布动态") }
            OutlinedButton(onClick = { clearWorkflow("notice:${primaryClassId.orEmpty()}"); noticeComposer = true }, enabled = primaryClassId != null, modifier = Modifier.weight(1f)) { Icon(Icons.Filled.Campaign, null); Spacer(Modifier.width(5.dp)); Text("发班级通知") }
        }
        Text("班级动态", color = Blue, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.padding(16.dp))
        when {
            state.repositoryAcknowledged && state.classPostsLoading && state.local.classPosts.isEmpty() -> LoadingState()
            state.repositoryAcknowledged && state.classPostsError != null && state.local.classPosts.isEmpty() -> ErrorState(state.classPostsError, retry = { loadClassPosts(null) })
            state.local.classPosts.isEmpty() -> EmptyState("暂无班级动态，发布或审核后会显示在这里。")
            else -> {
                state.local.classPosts.forEach { post ->
                    var menuExpanded by remember(post.id) { mutableStateOf(false) }
                    val canEditOrDelete = post.ownedByCurrentUser || post.postId == null
                    Surface(Modifier.padding(horizontal = 18.dp, vertical = 4.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) {
                        Column(Modifier.padding(14.dp)) {
                            Row(verticalAlignment = Alignment.Top) {
                                Column(Modifier.weight(1f)) {
                                    Text(post.displayName ?: post.author, color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                                    Text("${postSyncLabel(post.status)} · ${if (post.moderationStatus == "approved" || post.moderationStatus == "published") "已审核" else "待审核"}", color = if (post.status == LocalSubmissionStatus.Failed) Color.Red else Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(top = 2.dp))
                                }
                                Box {
                                    IconButton(onClick = { menuExpanded = true }, modifier = Modifier.size(40.dp)) { Icon(Icons.Filled.MoreVert, contentDescription = "管理班级动态", tint = Blue) }
                                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                                        if (canEditOrDelete) DropdownMenuItem(text = { Text("编辑") }, onClick = { menuExpanded = false; editingPost = post }, leadingIcon = { Icon(Icons.Filled.Edit, null) })
                                        if (state.teacherHasCapability("PUBLISH_CLASS_NOTICE") && post.postId != null) DropdownMenuItem(text = { Text(if (post.pinned) "取消置顶" else "置顶") }, onClick = { menuExpanded = false; setClassPostPinned(post, !post.pinned) }, leadingIcon = { Icon(Icons.Filled.PushPin, null) })
                                        DropdownMenuItem(text = { Text("举报") }, onClick = { menuExpanded = false; reportClassPost(post) }, leadingIcon = { Icon(Icons.Filled.Report, null) })
                                        if (canEditOrDelete) DropdownMenuItem(text = { Text("删除") }, onClick = { menuExpanded = false; deleteClassPost(post) }, leadingIcon = { Icon(Icons.Filled.Delete, null) })
                                    }
                                }
                            }
                            Text(post.content, color = Navy, fontSize = 16.sp, modifier = Modifier.padding(top = 8.dp))
                            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (post.pinned) Text("置顶", color = Color(0xFFFF8B1F), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                                if (post.reportStatus == "reported") Text("已举报", color = Color(0xFFFF8B1F), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
                if (state.repositoryAcknowledged && state.classPostsNextCursor != null) {
                    OutlinedButton(onClick = { loadClassPosts(state.classPostsNextCursor) }, enabled = !state.classPostsLoading, modifier = Modifier.padding(16.dp).fillMaxWidth()) {
                        Text(if (state.classPostsLoading) "加载中…" else "加载更多动态", fontSize = 15.sp)
                    }
                } else if (state.repositoryAcknowledged && state.classPostsError != null) {
                    ErrorState(state.classPostsError, retry = { loadClassPosts(state.classPostsNextCursor) })
                }
            }
        }
        if (!state.repositoryAcknowledged) listOf("今日体能活动" to "孩子们完成了侧向滑步与障碍跳练习，表现很棒！", "家校共育小贴士" to "建议每天安排 20 分钟亲子运动时间。").forEach { (title, detail) -> Surface(Modifier.padding(horizontal = 18.dp, vertical = 4.dp).fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看$title" }.clickable { notice = "$title\n$detail" }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp); Text(detail, color = Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(top = 3.dp)); Text("$currentTeacherName · 今天", color = Green, fontSize = 16.sp, modifier = Modifier.padding(top = 5.dp)) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.size(16.dp)) } } }
    } } }
    if (composer) TeacherPostEditorDialog(
        title = "发布班级动态",
        initialContent = state.local.drafts[composerDraftKey].orEmpty(),
        confirmLabel = "发布",
        command = state.workflowStates[currentTeacherKey] ?: WorkflowCommandState(),
        commandDriven = true,
        onConfirm = { content -> submitPost(currentTeacherName, content) },
        onSuccess = { clearDraft(composerDraftKey) },
        onDraftChanged = { saveDraft(composerDraftKey, it) },
        onDismiss = { composer = false }
    )
    if (noticeComposer) TeacherNoticeEditorDialog(
        state = state,
        initialClassId = primaryClassId,
        workflowStates = state.workflowStates,
        saveDraft = saveDraft,
        clearDraft = clearDraft,
        loadNotificationDrafts = loadNotificationDrafts,
        saveNotificationDraft = saveNotificationDraft,
        sendNotificationDraft = sendNotificationDraft,
        discardNotificationDraft = discardNotificationDraft,
        onSuccess = { noticeComposer = false },
        onDismiss = { noticeComposer = false }
    )
    editingPost?.let { post ->
        val draftKey = "teacher-class-circle-edit-${post.id}"
        TeacherPostEditorDialog(
            title = "编辑班级动态",
            initialContent = state.local.drafts[draftKey] ?: post.content,
            confirmLabel = "保存修改",
            onConfirm = { content -> updatePost(post.id, content); clearDraft(draftKey) },
            onDraftChanged = { saveDraft(draftKey, it) },
            onDismiss = { editingPost = null }
        )
    }
    notice?.let { item -> AlertDialog(onDismissRequest = { notice = null }, title = { Text(item.substringBefore('\n')) }, text = { Column { Text(item.substringAfter('\n', "暂无补充说明。")); Text("$currentTeacherName · 本班可见", color = Green, fontSize = 16.sp, modifier = Modifier.padding(top = 10.dp)) } }, confirmButton = { TextButton(onClick = { notice = null }) { Text("完成") } }) }
}

/** Keeps the root teacher tabs and notification entry usable while the first
 * dashboard load is pending or has failed. A full-screen spinner without any
 * navigation would strand the teacher on a cold-start error. */
@Composable
private fun TeacherUnavailableState(
    state: AppUiState,
    nav: NavHostController,
    error: String?,
    retry: () -> Unit,
    selected: String = Destinations.Teacher
) {
    Scaffold(containerColor = Canvas, bottomBar = { TeacherBottomBar(nav, selected) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            TeacherIdentity(state.activeDisplayName, false, nav, state.unreadMessageCount, error == null, retry)
            if (error != null) {
                ErrorState(error, retry = retry, dismiss = LocalDashboardClearError.current)
            } else {
                LoadingState()
            }
        }
    }
}

/** Empty data is distinct from a network failure: preserve the root tab bar
 * and useful teacher actions instead of rendering an un-navigable sentence. */
@Composable
private fun TeacherEmptyRootState(state: AppUiState, nav: NavHostController, selected: String, message: String) {
    Scaffold(containerColor = Canvas, bottomBar = { TeacherBottomBar(nav, selected) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            TeacherIdentity(state.activeDisplayName, false, nav, state.unreadMessageCount, false, {})
            EmptyState(message)
        }
    }
}

@Composable
private fun TeacherPostEditorDialog(
    title: String,
    initialContent: String,
    confirmLabel: String,
    command: WorkflowCommandState = WorkflowCommandState(),
    commandDriven: Boolean = false,
    onConfirm: (String) -> Unit,
    onSuccess: () -> Unit = {},
    onDraftChanged: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var content by rememberSaveable(initialContent) { mutableStateOf(initialContent) }
    var error by remember { mutableStateOf<String?>(null) }
    var success by remember { mutableStateOf(false) }
    LaunchedEffect(command.status) {
        if (commandDriven && command.status == WorkflowCommandStatus.Succeeded) {
            success = true
            onSuccess()
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            if (success) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Green, modifier = Modifier.size(42.dp))
                    Text("动态已保存，联网后自动同步到班级圈。", color = Navy, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
                }
            } else Column {
                OutlinedTextField(
                    value = content,
                    onValueChange = { content = it; onDraftChanged(it); error = null },
                    label = { Text("动态内容") },
                    placeholder = { Text("填写课堂动态或家长通知") },
                    minLines = 3
                )
                error?.let { Text(it, color = Color.Red, fontSize = 16.sp, modifier = Modifier.padding(top = 5.dp)) }
                if (commandDriven && command.status == WorkflowCommandStatus.Failed) Text(command.message ?: "提交失败，请重试。", color = Color.Red, fontSize = 16.sp, modifier = Modifier.padding(top = 5.dp))
                if (commandDriven && command.isSubmitting) Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 6.dp)) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(7.dp)); Text("正在提交动态…", color = Blue, fontSize = 16.sp) }
            }
        },
        confirmButton = {
            TextButton(enabled = !command.isSubmitting, onClick = {
                if (success) onDismiss() else if (content.trim().length < 4) error = "请至少输入 4 个字后再提交。" else {
                    onConfirm(content.trim())
                    if (!commandDriven) success = true
                }
            }) { if (command.isSubmitting) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(if (success) "完成" else if (command.status == WorkflowCommandStatus.Failed) "重新提交" else confirmLabel) }
        },
        dismissButton = if (success) null else ({ TextButton(onClick = onDismiss) { Text("取消") } })
    )
}
