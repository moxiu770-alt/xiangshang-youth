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

private fun teacherCapabilitySummary(state: AppUiState): String {
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
        Text(name, color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp)
        Text(schoolName, color = Color(0xFF7B8798), fontSize = 12.sp)
        Text(if (sportsTeacher) "延时课程工作台" else classSubtitle, color = Green, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
    }
    onSwitchRole?.let { action ->
        AssistChip(onClick = action, label = { Text("切换角色", fontSize = 12.sp) }, modifier = Modifier.heightIn(min = 44.dp))
        Spacer(Modifier.width(7.dp))
    }
    IconButton(onClick = onRefresh, enabled = !isRefreshing) { if (isRefreshing) CircularProgressIndicator(Modifier.size(17.dp), color = Blue, strokeWidth = 2.dp) else Icon(Icons.Filled.Refresh, contentDescription = "刷新数据", tint = Navy, modifier = Modifier.size(19.dp)) }
        IconButton(onClick = { nav.navigateSingleTop(RoleMessageDestination.resolve(UserRole.Teacher)) }) { BadgedBox(badge = { if (unreadCount > 0) Badge(containerColor = Color.Red, modifier = Modifier.size(6.dp)) {} }) { Icon(Icons.Filled.NotificationsNone, contentDescription = "消息通知", tint = Navy, modifier = Modifier.size(20.dp)) } }
}

@Composable
private fun TeacherRoleSwitch(sports: Boolean, onSelect: (Boolean) -> Unit, canUseSports: Boolean) = Row(
    Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)
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
            Spacer(Modifier.width(9.dp)); Text(label, color = if (selected) Color.White else color, fontWeight = FontWeight.Bold, fontSize = 14.sp)
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
    Text("▣  仅查看所有测评数据及授权数据", Modifier.fillMaxWidth(), color = Color(0xFF7F8792), fontSize = 12.sp, textAlign = TextAlign.Center)
    Surface(Modifier.padding(horizontal = 12.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
        Column(Modifier.padding(vertical = 10.dp)) {
            SectionHeader("班级健康概览", "查看班级看板") { nav.navigateSingleTop(Destinations.TeacherBoard) }
            Row(Modifier.fillMaxWidth().padding(top = 9.dp)) {
                TeacherMetric("班级人数", "${classStudents.size}", Icons.Filled.Groups, Blue) { primaryClassId?.let { nav.navigateSingleTop("${Destinations.Students}?classId=$it") } }
                TeacherMetric("已测评", "$measured", Icons.Filled.Visibility, Green) { nav.navigateSingleTop(Destinations.Tasks) }
                TeacherMetric("测评率", "${if (classStudents.isEmpty()) 0 else measured * 100 / classStudents.size}%", Icons.Filled.Refresh, Green) { nav.navigateSingleTop(Destinations.TeacherBoard) }
                TeacherMetric("待处理预警", "$risk", Icons.Filled.WarningAmber, Color(0xFFFF4242)) { nav.navigateSingleTop(Destinations.Review) }
            }
            HorizontalDivider(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), color = Color(0xFFF0F2F7))
            Text("问题分布（人）", Modifier.padding(horizontal = 12.dp), color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp)
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
        Surface(Modifier.padding(horizontal = 12.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp), shadowElevation = 1.dp) {
            Column(Modifier.padding(vertical = 9.dp)) {
                SectionHeader("今日任务", "查看全部") { nav.navigateSingleTop(Destinations.Tasks) }
                SportsTask("16:30", "16:30 · 17:10", "$primaryClassName 综合测评", Green) { nav.navigateSingleTop(Destinations.Tasks) }
                SportsTask("17:20", "17:20 · 18:00", "体能提升课", Blue) { nav.navigateSingleTop(Destinations.Tasks) }
            }
        }
    }
}

@Composable
private fun RowScope.TeacherMetric(label: String, value: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, onClick: () -> Unit) = Surface(onClick = onClick, modifier = Modifier.weight(1f).semantics { role = Role.Button; contentDescription = "$label：$value，查看详情" }, color = Color.Transparent, shape = RoundedCornerShape(8.dp)) {
    Column(Modifier.fillMaxWidth().padding(vertical = 3.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, color = Color(0xFF798699), fontSize = 12.sp)
        Row(verticalAlignment = Alignment.CenterVertically) { Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 19.sp); Spacer(Modifier.width(3.dp)); Icon(icon, null, tint = color, modifier = Modifier.size(15.dp)) }
    }
}

@Composable
private fun RowScope.TeacherIssue(icon: androidx.compose.ui.graphics.vector.ImageVector, value: String, label: String, color: Color, onClick: () -> Unit) = Surface(onClick = onClick, modifier = Modifier.weight(1f).semantics { role = Role.Button; contentDescription = "$label：$value，查看详情" }, color = Color.Transparent, shape = RoundedCornerShape(8.dp)) {
    Column(Modifier.fillMaxWidth().padding(vertical = 3.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, contentDescription = label, tint = color, modifier = Modifier.size(20.dp)); Text(value, color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp); Text(label, color = Color(0xFF7D8797), fontSize = 12.sp)
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
    Column(Modifier.padding(horizontal = 12.dp).fillMaxWidth().background(Color.White, RoundedCornerShape(10.dp)).padding(9.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        actions.chunked(columns).forEach { row -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            row.forEach { (title, icon, color) ->
                Surface(Modifier.weight(1f).heightIn(min = 67.dp).semantics { role = Role.Button; contentDescription = title }.clickable { nav.navigate(when (title) { "班级看板" -> Destinations.TeacherBoard; "班级管理" -> Destinations.Classes; "预警中心" -> Destinations.Review; "优秀学生评选" -> Destinations.OutstandingStudents; "待分班学生" -> Destinations.UnassignedStudents; "学生列表" -> Destinations.Students; else -> Destinations.Tasks }) }, color = color.copy(alpha = .055f), shape = RoundedCornerShape(9.dp)) {
                    Column(Modifier.fillMaxSize().padding(vertical = 7.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) { Surface(color = color, shape = RoundedCornerShape(12.dp), modifier = Modifier.size(31.dp)) { Icon(icon, null, tint = Color.White, modifier = Modifier.padding(7.dp)) }; Spacer(Modifier.height(4.dp)); Text(title, color = Navy, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = if (columns == 2) 2 else 1, textAlign = TextAlign.Center) }
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
    Surface(Modifier.padding(horizontal = 12.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
        Column(Modifier.padding(vertical = 10.dp)) {
                SectionHeader("近日测评提醒", "查看全部") { nav.navigateSingleTop(Destinations.Tasks) }
            Row(Modifier.fillMaxWidth().padding(top = 9.dp)) { TeacherMetric("待测班级", "${tasks.count { it.completedCount < it.totalCount }}", Icons.Filled.Folder, Blue) { nav.navigateSingleTop(Destinations.Tasks) }; TeacherMetric("测评学生", "$total", Icons.Filled.Person, Green) { nav.navigateSingleTop(Destinations.Students) }; TeacherMetric("今日排班", "${tasks.size}", Icons.Filled.CalendarMonth, Color(0xFFFF9D28)) { nav.navigateSingleTop(Destinations.Tasks) }; TeacherMetric("待上传", "${tasks.count { it.completedCount < it.totalCount }}", Icons.Filled.CloudUpload, Color(0xFF8B5AF5)) { nav.navigateSingleTop(Destinations.Tasks) } }
            Row(Modifier.padding(horizontal = 13.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) { Text("进度", color = Color(0xFF738094), fontSize = 12.sp); Spacer(Modifier.width(8.dp)); LinearProgressIndicator({ completed.toFloat() / total }, Modifier.weight(1f).height(5.dp).clip(CircleShape), color = Green, trackColor = Color(0xFFDEF1E8)); Spacer(Modifier.width(8.dp)); Text("${completed * 100 / total}%", color = Green, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
        }
    }
    Row(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { SportsShortcut("学生管理", Icons.Filled.Groups, Green, Modifier.weight(1f)) { nav.navigateSingleTop(Destinations.Students) }; SportsShortcut("班级排课", Icons.Filled.CalendarMonth, Blue, Modifier.weight(1f)) { nav.navigateSingleTop(Destinations.Tasks) } }
    Surface(Modifier.padding(horizontal = 12.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(vertical = 10.dp)) { SectionHeader("今日任务", "查看全部") { nav.navigateSingleTop(Destinations.Tasks) }; if (tasks.isEmpty()) { Text("暂无已排期任务", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 13.dp, vertical = 10.dp)) } else { tasks.take(2).forEachIndexed { index, task -> val color = if (index == 0) Green else Blue; SportsTask(task.date.substringAfter(" ").take(5), task.date, "${task.className} · ${task.title}", color) { nav.navigateSingleTop(Destinations.TaskDetailRoute.replace("{taskId}", task.id)) } } } } }
    Surface(Modifier.padding(horizontal = 12.dp).fillMaxWidth().semantics { role = Role.Button; contentDescription = "上传课后测评结果和照片" }.clickable { nav.navigateSingleTop(Destinations.Tasks) }, color = Color(0xFFFFAA25), shape = RoundedCornerShape(9.dp)) { Row(Modifier.padding(vertical = 10.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.CameraAlt, null, tint = Color.White, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(7.dp)); Text("课后上传测评结果记录与照片", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp) } }
}

@Composable private fun SportsShortcut(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, modifier: Modifier, onClick: () -> Unit) = Surface(modifier.height(66.dp).semantics { role = Role.Button; contentDescription = "查看$label" }.clickable(onClick = onClick), color = color.copy(alpha = .065f), shape = RoundedCornerShape(10.dp)) { Row(Modifier.fillMaxSize().padding(10.dp), verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = color, modifier = Modifier.size(27.dp)); Spacer(Modifier.width(9.dp)); Column { Text(label, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("查看详情 ›", color = color, fontSize = 12.sp) } } }
@Composable private fun SportsTask(time: String, duration: String, title: String, color: Color, onClick: (() -> Unit)? = null) = Row(Modifier.padding(horizontal = 13.dp, vertical = 6.dp).then(if (onClick == null) Modifier else Modifier.clickable(onClick = onClick).semantics { role = Role.Button; contentDescription = "查看任务：$title，$duration" }), verticalAlignment = Alignment.CenterVertically) { Surface(color = color.copy(alpha = .13f), shape = CircleShape, modifier = Modifier.size(28.dp)) { Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, tint = color, modifier = Modifier.padding(6.dp)) }; Spacer(Modifier.width(8.dp)); Column(Modifier.weight(1f)) { Text(duration, color = Color(0xFF778497), fontSize = 12.sp); Text(title, color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 12.sp) }; Text(time, color = color, fontWeight = FontWeight.Bold, fontSize = 12.sp); if (onClick != null) { Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.size(15.dp)) } }
@Composable private fun SectionHeader(title: String, action: String, onClick: () -> Unit) = Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) { Text(title, color = Blue, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.semantics { heading() }); Spacer(Modifier.weight(1f)); Text(action + "  ›", color = Blue, fontSize = 12.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "$title：$action" }.clickable(onClick = onClick)) }

@Composable
private fun TeacherBottomBar(nav: NavHostController, selected: String = Destinations.Teacher, sportsTeacher: Boolean = false) = NavigationBar(containerColor = Color.White, tonalElevation = 1.dp) {
    fun go(route: String) { nav.navigate(route) { popUpTo(Destinations.Teacher) { saveState = true }; launchSingleTop = true; restoreState = true } }
    NavigationBarItem(selected = selected == Destinations.Teacher, onClick = { go(Destinations.Teacher) }, icon = { Icon(Icons.Filled.Home, null) }, label = { Text("首页", fontSize = 12.sp, maxLines = 1) }, modifier = Modifier.semantics { contentDescription = "首页${if (selected == Destinations.Teacher) "，当前页面" else ""}" })
    val secondary = if (sportsTeacher) Destinations.SportsUpload else Destinations.TeacherCircle
    NavigationBarItem(selected = selected == secondary, onClick = { go(secondary) }, icon = { Icon(if (sportsTeacher) Icons.Filled.CameraAlt else Icons.Filled.Dashboard, null) }, label = { Text(if (sportsTeacher) "延时上传" else "班级圈", fontSize = 12.sp, maxLines = 1) }, modifier = Modifier.semantics { contentDescription = "${if (sportsTeacher) "延时上传" else "班级圈"}${if (selected == secondary) "，当前页面" else ""}" })
    NavigationBarItem(selected = selected == Destinations.Account, onClick = { go(Destinations.Account) }, icon = { Icon(Icons.Filled.PersonOutline, null) }, label = { Text("我的", fontSize = 12.sp, maxLines = 1) }, modifier = Modifier.semantics { contentDescription = "我的${if (selected == Destinations.Account) "，当前页面" else ""}" })
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
            Surface(Modifier.padding(12.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) { Column(Modifier.padding(12.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Campaign, null, tint = Blue); Spacer(Modifier.width(7.dp)); Text("班级公告", color = Navy, fontWeight = FontWeight.Bold); Spacer(Modifier.weight(1f)); Text("全部公告 ›", color = Blue, fontSize = 12.sp, modifier = Modifier.semantics { role = Role.Button; contentDescription = "查看全部班级公告" }.clickable { notice = "全部班级公告\n请家长于 9 月 12 日前完成孩子健康信息确认，并留意测评时间与场地安排。" }) }; Text("秋季综合测评通知", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp).semantics { role = Role.Button; contentDescription = "查看秋季综合测评通知" }.clickable { notice = "秋季综合测评通知\n请家长于 9 月 12 日前完成孩子健康信息确认。测评当天请为孩子准备舒适运动服和饮水。" }); Text("请家长于 9 月 12 日前完成孩子健康信息确认。", color = Color.Gray, fontSize = 12.sp) } }
        }
        Row(Modifier.fillMaxWidth().background(Color.White).padding(13.dp), verticalAlignment = Alignment.CenterVertically) {
            Image(painterResource(R.drawable.teacher_avatar), null, Modifier.size(38.dp).clip(CircleShape), contentScale = ContentScale.Crop)
            Spacer(Modifier.width(8.dp))
            Column(Modifier.weight(1f)) {
                Text("$primaryClassName · 班级圈", color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                Text("${state.profile?.schoolName ?: "学校"} · ${primaryClassCount}名学生", color = Color.Gray, fontSize = 12.sp)
            }
            IconButton(onClick = { nav.navigateSingleTop(RoleMessageDestination.resolve(UserRole.Teacher)) }) {
                Icon(Icons.Filled.Notifications, contentDescription = "消息通知", tint = Blue)
            }
        }
        Row(Modifier.padding(horizontal = 12.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { clearWorkflow(currentTeacherKey); composer = true }, modifier = Modifier.weight(1f)) { Icon(Icons.Filled.Edit, null); Spacer(Modifier.width(5.dp)); Text("发布动态") }
            OutlinedButton(onClick = { clearWorkflow("notice:${primaryClassId.orEmpty()}"); noticeComposer = true }, enabled = primaryClassId != null, modifier = Modifier.weight(1f)) { Icon(Icons.Filled.Campaign, null); Spacer(Modifier.width(5.dp)); Text("发班级通知") }
        }
        Text("班级动态", color = Blue, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.padding(12.dp))
        when {
            state.repositoryAcknowledged && state.classPostsLoading && state.local.classPosts.isEmpty() -> LoadingState()
            state.repositoryAcknowledged && state.classPostsError != null && state.local.classPosts.isEmpty() -> ErrorState(state.classPostsError, retry = { loadClassPosts(null) })
            state.local.classPosts.isEmpty() -> EmptyState("暂无班级动态，发布或审核后会显示在这里。")
            else -> {
                state.local.classPosts.forEach { post ->
                    var menuExpanded by remember(post.id) { mutableStateOf(false) }
                    Surface(Modifier.padding(horizontal = 12.dp, vertical = 4.dp).fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) {
                        Column(Modifier.padding(14.dp)) {
                            Row(verticalAlignment = Alignment.Top) {
                                Column(Modifier.weight(1f)) {
                                    Text(post.displayName ?: post.author, color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                    Text("${postSyncLabel(post.status)} · ${if (post.moderationStatus == "approved" || post.moderationStatus == "published") "已审核" else "待审核"}", color = if (post.status == LocalSubmissionStatus.Failed) Color.Red else Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 2.dp))
                                }
                                Box {
                                    IconButton(onClick = { menuExpanded = true }, modifier = Modifier.size(40.dp)) { Icon(Icons.Filled.MoreVert, contentDescription = "管理班级动态", tint = Blue) }
                                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                                        if (post.status != LocalSubmissionStatus.Submitted) DropdownMenuItem(text = { Text("编辑") }, onClick = { menuExpanded = false; editingPost = post }, leadingIcon = { Icon(Icons.Filled.Edit, null) })
                                        if (state.teacherHasCapability("PUBLISH_CLASS_NOTICE") && post.postId != null) DropdownMenuItem(text = { Text(if (post.pinned) "取消置顶" else "置顶") }, onClick = { menuExpanded = false; setClassPostPinned(post, !post.pinned) }, leadingIcon = { Icon(Icons.Filled.PushPin, null) })
                                        DropdownMenuItem(text = { Text("举报") }, onClick = { menuExpanded = false; reportClassPost(post) }, leadingIcon = { Icon(Icons.Filled.Report, null) })
                                        DropdownMenuItem(text = { Text("删除") }, onClick = { menuExpanded = false; deleteClassPost(post) }, leadingIcon = { Icon(Icons.Filled.Delete, null) })
                                    }
                                }
                            }
                            Text(post.content, color = Navy, fontSize = 14.sp, modifier = Modifier.padding(top = 8.dp))
                            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (post.pinned) Text("置顶", color = Color(0xFFFF8B1F), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                if (post.reportStatus == "reported") Text("已举报", color = Color(0xFFFF8B1F), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
                if (state.repositoryAcknowledged && state.classPostsNextCursor != null) {
                    OutlinedButton(onClick = { loadClassPosts(state.classPostsNextCursor) }, enabled = !state.classPostsLoading, modifier = Modifier.padding(12.dp).fillMaxWidth()) {
                        Text(if (state.classPostsLoading) "加载中…" else "加载更多动态", fontSize = 15.sp)
                    }
                } else if (state.repositoryAcknowledged && state.classPostsError != null) {
                    ErrorState(state.classPostsError, retry = { loadClassPosts(state.classPostsNextCursor) })
                }
            }
        }
        if (!state.repositoryAcknowledged) listOf("今日体能活动" to "孩子们完成了侧向滑步与障碍跳练习，表现很棒！", "家校共育小贴士" to "建议每天安排 20 分钟亲子运动时间。").forEach { (title, detail) -> Surface(Modifier.padding(horizontal = 12.dp, vertical = 4.dp).fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看$title" }.clickable { notice = "$title\n$detail" }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text(detail, color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 3.dp)); Text("$currentTeacherName · 今天", color = Green, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp)) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.size(16.dp)) } } }
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
    notice?.let { item -> AlertDialog(onDismissRequest = { notice = null }, title = { Text(item.substringBefore('\n')) }, text = { Column { Text(item.substringAfter('\n', "暂无补充说明。")); Text("$currentTeacherName · 本班可见", color = Green, fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp)) } }, confirmButton = { TextButton(onClick = { notice = null }) { Text("完成") } }) }
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
                error?.let { Text(it, color = Color.Red, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp)) }
                if (commandDriven && command.status == WorkflowCommandStatus.Failed) Text(command.message ?: "提交失败，请重试。", color = Color.Red, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp))
                if (commandDriven && command.isSubmitting) Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 6.dp)) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(7.dp)); Text("正在提交动态…", color = Blue, fontSize = 12.sp) }
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

/** Dedicated class-notice editor. Notice drafts and delivery states are kept
 * separate from class-circle posts so a teacher cannot accidentally publish a
 * family-facing notice as a social update. */
 @Composable
fun TeacherAccountScreen(state: AppUiState, nav: NavHostController, logout: () -> Unit, updateSettings: (Boolean?, Boolean?, Boolean?) -> Unit, onChooseAnotherRole: () -> Unit, syncPending: () -> Unit = {}, submitAccountDeletionRequest: () -> Unit = {}) {
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
    if (settingsOpen) SettingsDialog(state.local.settings.notificationsEnabled, state.local.settings.reduceMotion, state.local.settings.voiceGuidanceEnabled, state.pendingSyncCount, state.workflowStates["sync-pending"] ?: WorkflowCommandState(), updateSettings, syncPending, clearLocalData = { logout(); nav.navigate(Destinations.Login) { popUpTo(nav.graph.id) { inclusive = true } } }) { settingsOpen = false }
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
    val totalStudents = if (isHistorical) 0 else classStudents.size
    val completed = if (isHistorical) 0 else state.teacherOverview?.completedCount ?: classStudents.count { state.taskStatus(it, currentTask?.id).name == "Completed" }
    val completionRate = if (totalStudents == 0) 0 else state.teacherOverview?.let { it.completedCount * 100 / it.totalCount.coerceAtLeast(1) } ?: completed * 100 / totalStudents
    val officialReports = classStudents.filter(state::hasPublishedSchoolReport).mapNotNull(reportForStudent)
    val lowScoreStudentIds = officialReports.filter { it.requiresFollowUp }.map { it.student.id }.toSet()
    val risk = if (isHistorical) 0 else state.teacherOverview?.riskCount ?: classStudents.count { val status = state.taskStatus(it, currentTask?.id); it.id in lowScoreStudentIds || status.name == "Review" || status.name == "Retest" }
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
                                val metric = state.teacherOverview?.itemStats?.firstOrNull { it.itemCode == item.label }
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
    Spacer(Modifier.height(8.dp)); BoardCard("测评平均完成趋势", if (isHistorical) "归档说明" else "查看详情", onClick = { drillDown { nav.navigateSingleTop(Destinations.Tasks) } }) { LinearProgressIndicator(progress = { completionRate / 100f }, modifier = Modifier.fillMaxWidth().height(8.dp).clip(CircleShape), color = Green, trackColor = Sky); Text("${if (isHistorical) "历史归档" else "当前班级"}完成率 $completionRate%", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.fillMaxWidth().padding(top = 6.dp), textAlign = TextAlign.Center) }
    Spacer(Modifier.height(8.dp)); BoardCard("重点关注学生", if (isHistorical) "归档说明" else "查看全部", onClick = { drillDown { nav.navigateSingleTop(Destinations.Review) } }) { if (isHistorical) Text("历史周期数据尚未同步，不展示演示统计或学生明细。", color = Color.Gray, fontSize = 12.sp) else { classStudents.filter { student -> val status = state.taskStatus(student, state.data.tasks.firstOrNull()?.id); student.id in lowScoreStudentIds || status.name == "Review" || status.name == "Retest" }.take(3).forEach { student -> val status = state.taskStatus(student, state.data.tasks.firstOrNull()?.id); Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).semantics { role = Role.Button; contentDescription = "查看${student.name}报告，状态${status.label}" }.clickable { onOpenReport(student) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { Text("${student.name}   ${student.className}   ${status.label}", color = Navy, fontSize = 12.sp, modifier = Modifier.weight(1f)); Icon(Icons.Filled.ChevronRight, contentDescription = "查看${student.name}报告", tint = Color.Gray, modifier = Modifier.size(16.dp)) } }; if (risk == 0) Text("当前班级暂无重点风险学生", color = Color.Gray, fontSize = 12.sp) } }
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
            val completionRate = if (classStudents.isEmpty()) item.completionRate else classStudents.count { state.taskStatus(it, data.tasks.firstOrNull()?.id) == com.xiangshang.youth.core.model.TaskStatus.Completed } * 100 / classStudents.size
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
        state.taskRosterRecords[task.id] == null -> LoadingState()
        else -> state.taskRosterStudents(task.id, task).filter { student ->
            val query = rosterSearch.trim()
            (query.isEmpty() || student.name.contains(query, ignoreCase = true) || student.className.contains(query, ignoreCase = true)) && (rosterStatus == null || state.taskStatus(student, task.id) == rosterStatus)
        }.forEach { student ->
            val taskStatus = state.taskStatus(student, task.id)
            TeacherStudentStatusRow(student, taskStatus, state.taskSyncStatus(student, task.id)) { selectedStudent = student }
            Spacer(Modifier.height(5.dp))
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
fun ReviewListScreen(state: AppUiState, nav: NavHostController, submitDecision: (String, com.xiangshang.youth.core.model.TaskStatus, String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, submitStatus: (String, com.xiangshang.youth.core.model.TaskStatus, String?, String?) -> Unit = { studentId, status, note, _ -> submitDecision(studentId, status, note.orEmpty()) }) = AppScaffold("预警中心", onBack = { nav.popBackStack() }) {
    var selectedStudent by remember { mutableStateOf<com.xiangshang.youth.core.model.Student?>(null) }
    val dashboardError = state.error
    if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@AppScaffold }
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
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
            state.workflowStates["task-status:${reviewTaskId ?: "unscoped"}|${student.id}"] ?: WorkflowCommandState(),
            onDraftChanged = { saveDraft(draftKey, it) },
            onSubmit = { status, note -> submitStatus(student.id, status, note, reviewTaskId) },
            onSuccess = { clearDraft(draftKey); selectedStudent = null },
            dismiss = { selectedStudent = null }
        )
    }
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
