package com.xiangshang.youth.feature.principal

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
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
import com.xiangshang.youth.shared.component.*
import java.util.Locale

@Composable fun PrincipalHomeScreen(state: AppUiState, nav: NavHostController, switchRole: () -> Unit, refreshDashboard: () -> Unit = {}) = AppScaffold("学校运动健康总览", onNotifications = { nav.navigate(Destinations.Notifications) }, notificationCount = state.unreadMessageCount, onRefresh = refreshDashboard, isRefreshing = state.loading, errorMessage = state.error?.takeIf { state.data != null }, onRetry = refreshDashboard, onSwitchRole = { switchRole(); nav.navigate(Destinations.Role) { popUpTo(Destinations.Principal) { inclusive = true } } }) {
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    if (state.data.students.isEmpty()) { EmptyState("暂无学校测评数据，场地端上传后会显示在这里。"); return@AppScaffold }
    Surface(Modifier.fillMaxWidth().padding(bottom = 8.dp), color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Surface(Modifier.size(44.dp), color = Color(0xFF6EA7FF), shape = androidx.compose.foundation.shape.CircleShape) {
                Text("周", color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.padding(top = 9.dp))
            }
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text("周校长", color = Navy, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                Text("向上实验小学 · 南湖校区", color = Color.Gray, fontSize = 10.sp)
            }
            Text("本轮测评", color = Blue, fontSize = 9.sp, modifier = Modifier.background(Sky, RoundedCornerShape(12.dp)).padding(horizontal = 9.dp, vertical = 5.dp))
        }
    }
    val activeTask = state.data.tasks.firstOrNull()
    val activeTaskStudents = activeTask?.let { task ->
        state.data.students.filter { student ->
            student.grade == task.gradeName && task.className.split("、").contains(student.className)
        }
    }.orEmpty()
    val activeCompleted = if (activeTaskStudents.isEmpty()) activeTask?.completedCount ?: 0 else activeTaskStudents.count { student ->
        (state.local.studentTaskStatuses[student.id] ?: student.taskStatus) == com.xiangshang.youth.core.model.TaskStatus.Completed
    }
    val activeTotal = if (activeTaskStudents.isEmpty()) activeTask?.totalCount ?: 0 else activeTaskStudents.size
    val completion = if (activeTotal == 0) 0f else activeCompleted.toFloat() / activeTotal
    var regionDetailShown by rememberSaveable { mutableStateOf(false) }
    val risk = state.data?.students?.count { student ->
        val status = state.local.studentTaskStatuses[student.id] ?: student.taskStatus
        (student.totalScore ?: 35.0) < 25 || status.name == "Review" || status.name == "Retest"
    } ?: 6
    val averageScore = state.data.students.mapNotNull { it.totalScore }.average().takeIf { it.isFinite() } ?: 0.0
    val povertyCount = state.data.students.count { it.isPovertyArea }
    Surface(onClick = { nav.navigate(Destinations.Grades) }, modifier = Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) { Column(Modifier.padding(14.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.TrendingUp, null, tint = Blue); Spacer(Modifier.width(7.dp)); Text(activeTask?.title ?: "综合运动能力测评", color = Navy, fontWeight = FontWeight.Bold, fontSize = 13.sp); Spacer(Modifier.weight(1f)); Text(activeTask?.status?.label ?: "待开始", color = Blue, fontSize = 9.sp) }; Spacer(Modifier.height(10.dp)); Row(verticalAlignment = Alignment.Bottom) { Column(Modifier.weight(1f)) { Text("${(completion * 100).toInt()}%", color = Blue, fontWeight = FontWeight.Bold, fontSize = 30.sp); Text("全校测评完成率", color = Color.Gray, fontSize = 10.sp) }; Column(horizontalAlignment = Alignment.End) { Text("$activeCompleted / $activeTotal 人", color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp); Text("已完成 · ${activeTask?.ruleVersion ?: "规则 v1.0"}", color = Color.Gray, fontSize = 8.sp) } }; Spacer(Modifier.height(8.dp)); LinearProgressIndicator({ completion }, Modifier.fillMaxWidth().height(8.dp), color = Green, trackColor = Sky) } }
    Spacer(Modifier.height(9.dp)); Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) { PrincipalMetric("平均总分", String.format(Locale.US, "%.1f", averageScore), "35分制", Icons.Filled.SportsScore, Blue, Modifier.weight(1f)) { nav.navigate(Destinations.Grades) }; PrincipalMetric("风险学生", "$risk", "待及时跟进", Icons.Filled.WarningAmber, Color.Red, Modifier.weight(1f)) { nav.navigate(Destinations.Risk) }; PrincipalMetric("公益支持", "$povertyCount", "贫困地区", Icons.Filled.Favorite, Color(0xFFFF638E), Modifier.weight(1f)) { regionDetailShown = true } }
    Spacer(Modifier.height(10.dp)); Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(12.dp)) { Column(Modifier.padding(12.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Text("年级完成率对比", color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp); Spacer(Modifier.weight(1f)); TextButton(onClick = { nav.navigate(Destinations.Grades) }) { Text("全部年级 ›", fontSize = 9.sp) } }; state.data.grades.forEach { grade -> val gradeClasses = state.data.classes.filter { it.gradeId == grade.id }; val gradeStudents = state.data.students.filter { it.grade == grade.name }; val value = if (gradeStudents.isNotEmpty()) gradeStudents.count { (state.local.studentTaskStatuses[it.id] ?: it.taskStatus) == com.xiangshang.youth.core.model.TaskStatus.Completed }.toFloat() / gradeStudents.size else if (gradeClasses.isEmpty()) 0f else gradeClasses.map { it.completionRate }.average().toFloat() / 100f; Row(Modifier.fillMaxWidth().padding(vertical = 5.dp).semantics { role = Role.Button; contentDescription = "查看${grade.name}班级统计" }.clickable { nav.navigate("${Destinations.ClassStats}?grade=${android.net.Uri.encode(grade.name)}") }, verticalAlignment = Alignment.CenterVertically) { Text(grade.name, color = Navy, fontSize = 10.sp, modifier = Modifier.width(55.dp)); LinearProgressIndicator({ value }, Modifier.weight(1f).height(6.dp), color = if (value < .8f) Color(0xFFFF9D25) else Green, trackColor = Sky); Spacer(Modifier.width(7.dp)); Text("${(value * 100).toInt()}%", color = if (value < .8f) Color(0xFFFF9D25) else Green, fontWeight = FontWeight.Bold, fontSize = 10.sp) }; Text("7项平均分：跳跃 3.9 · 滑步 3.8 · 平衡 3.6", color = Color.Gray, fontSize = 8.sp) } } }
    Spacer(Modifier.height(9.dp)); Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) { PrincipalEntry("班级完成率", "6个班级实时进度", Icons.Filled.Groups, Color(0xFF8A5AF5), Modifier.weight(1f)) { nav.navigate(Destinations.ClassStats) }; PrincipalEntry("重点风险学生", "$risk 人需要跟进", Icons.Filled.PersonSearch, Color.Red, Modifier.weight(1f)) { nav.navigate(Destinations.Risk) } }
    Spacer(Modifier.height(9.dp)); Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看地区关怀明细" }.clickable { regionDetailShown = true }, color = Color.White, shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Map, null, tint = Color(0xFFFF9D25), modifier = Modifier.size(28.dp)); Spacer(Modifier.width(10.dp)); Column(Modifier.weight(1f)) { Text("区域关怀统计", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("粤北山区 · ${povertyCount}名贫困地区学生已纳入公益支持", color = Color.Gray, fontSize = 9.sp) }; Icon(Icons.Filled.ChevronRight, contentDescription = "查看地区关怀明细", tint = Color.Gray, modifier = Modifier.size(16.dp)) } }
    if (regionDetailShown) AlertDialog(
        onDismissRequest = { regionDetailShown = false },
        title = { Text("地区关怀明细") },
        text = { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { Text("南湖校区", color = Navy, fontWeight = FontWeight.Bold); Text("覆盖3个年级 · 6个班级 · ${state.data?.students?.size ?: 0}名学生", color = Color.Gray, fontSize = 11.sp); HorizontalDivider(); Text("粤北山区", color = Navy, fontWeight = FontWeight.Bold); Text("${state.data?.students?.count { it.isPovertyArea } ?: 0}名贫困地区学生已纳入公益运动课程支持", color = Color.Gray, fontSize = 11.sp); Text("地区标签和公益资格由学校管理端维护，场地端上传成绩后会自动刷新。", color = Color.Gray, fontSize = 10.sp) } },
        confirmButton = { TextButton(onClick = { regionDetailShown = false }) { Text("关闭") } }
    )
}

@Composable private fun PrincipalMetric(title: String, value: String, note: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, modifier: Modifier, onClick: () -> Unit) = Surface(onClick = onClick, modifier = modifier.semantics { role = Role.Button; contentDescription = "$title：$value，$note" }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(9.dp)) { Icon(icon, null, tint = color, modifier = Modifier.size(17.dp)); Text(value, color = Navy, fontWeight = FontWeight.Bold, fontSize = 19.sp, modifier = Modifier.padding(top = 4.dp)); Text(title, color = Navy, fontSize = 10.sp); Text(note, color = Color.Gray, fontSize = 8.sp) } }
@Composable private fun PrincipalEntry(title: String, note: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, modifier: Modifier, onClick: () -> Unit) = Surface(onClick = onClick, modifier = modifier.semantics { role = Role.Button; contentDescription = "$title：$note" }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(9.dp), verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = color); Spacer(Modifier.width(7.dp)); Column { Text(title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 10.sp); Text(note, color = Color.Gray, fontSize = 8.sp) } } }
@Composable
fun GradeStatsScreen(state: AppUiState, nav: NavHostController) = AppScaffold("不同年级对比", onBack = { nav.popBackStack() }) {
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    if (state.data.grades.isEmpty()) { EmptyState("暂无年级统计数据。"); return@AppScaffold }
    var metric by rememberSaveable { mutableStateOf("完成率") }
    Text("规则版本 v1.0", color = Color.Gray, fontSize = 10.sp, modifier = Modifier.padding(top = 7.dp))
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf("完成率", "平均总分", "风险人数").forEach { item ->
            FilterChip(selected = metric == item, onClick = { metric = item }, label = { Text(item, fontSize = 10.sp) }, modifier = Modifier.weight(1f))
        }
    }
    Text("按小学综合运动能力标准 v1.0 汇总，点击年级查看班级进度。", color = Color.Gray, fontSize = 9.sp)
    state.data.grades.forEachIndexed { index, grade ->
        val gradeClasses = state.data.classes.filter { it.gradeId == grade.id }
        val gradeName = grade.name
        val gradeStudents = state.data.students.filter { it.grade == gradeName }
        val rate = if (gradeStudents.isNotEmpty()) {
            gradeStudents.count { (state.local.studentTaskStatuses[it.id] ?: it.taskStatus) == com.xiangshang.youth.core.model.TaskStatus.Completed } * 100 / gradeStudents.size
        } else if (gradeClasses.isEmpty()) 0 else gradeClasses.map { it.completionRate }.average().toInt()
        val totalStudents = if (gradeStudents.isEmpty()) gradeClasses.sumOf { it.studentCount } else gradeStudents.size
        val completedStudents = if (gradeStudents.isEmpty()) totalStudents * rate / 100 else gradeStudents.count { (state.local.studentTaskStatuses[it.id] ?: it.taskStatus) == com.xiangshang.youth.core.model.TaskStatus.Completed }
        val gradeAverage = gradeStudents.mapNotNull { it.totalScore }.average().takeIf { it.isFinite() } ?: 0.0
        val gradeRisk = gradeStudents.count { student ->
            val status = state.local.studentTaskStatuses[student.id] ?: student.taskStatus
            (student.totalScore ?: 35.0) < 25 || status == com.xiangshang.youth.core.model.TaskStatus.Review || status == com.xiangshang.youth.core.model.TaskStatus.Retest
        }
        val value = when (metric) { "平均总分" -> String.format(Locale.US, "%.1f", gradeAverage); "风险人数" -> "${gradeRisk}人"; else -> "$rate%" }
        Surface(
            Modifier.fillMaxWidth().padding(vertical = 5.dp).semantics { role = Role.Button; contentDescription = "查看${grade.name}班级统计，${value}${metric}" }.clickable { nav.navigate("${Destinations.ClassStats}?grade=${android.net.Uri.encode(grade.name)}") },
            color = Color.White, shape = RoundedCornerShape(11.dp), shadowElevation = 1.dp
        ) {
            Column(Modifier.padding(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text(grade.name, color = Navy, fontWeight = FontWeight.Bold); Text("${grade.standardVersion} · 2个班级", color = Color.Gray, fontSize = 9.sp) }
                    Column(horizontalAlignment = Alignment.End) { Text(value, color = if (metric == "风险人数") Color.Red else Green, fontWeight = FontWeight.Bold, fontSize = 18.sp); Text(metric, color = Color.Gray, fontSize = 9.sp) }
                    Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.padding(start = 5.dp))
                }
                LinearProgressIndicator({ rate / 100f }, Modifier.fillMaxWidth().padding(top = 9.dp).height(6.dp), color = if (index == 0) Color(0xFFFF9D25) else Green, trackColor = Sky)
                Row(Modifier.fillMaxWidth().padding(top = 5.dp)) { Text("已完成 $completedStudents 人", color = Color.Gray, fontSize = 8.sp); Spacer(Modifier.weight(1f)); Text("7项平均分 ${String.format(Locale.US, "%.1f", 3.5 + index * .1)}", color = Color.Gray, fontSize = 8.sp) }
            }
        }
    }
}

@Composable
fun ClassStatsScreen(state: AppUiState, nav: NavHostController, initialGrade: String?) = AppScaffold("班级完成率", onBack = { nav.popBackStack() }) {
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    var selectedGrade by rememberSaveable { mutableStateOf(initialGrade ?: "全部年级") }
    val allClasses = state.data.classes
    val classes = if (selectedGrade == "全部年级") allClasses else allClasses.filter { item -> state.data.grades.firstOrNull { grade -> grade.id == item.gradeId }?.name == selectedGrade }
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        (listOf("全部年级") + state.data.grades.map { it.name }).forEach { grade -> FilterChip(selected = selectedGrade == grade, onClick = { selectedGrade = grade }, label = { Text(grade, fontSize = 9.sp) }) }
    }
    Text("${classes.size}个班级 · 点击班级查看需要重点跟进的学生", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.padding(bottom = 4.dp))
    classes.forEach { item ->
        val classStudents = state.data.students.filter { it.className == item.name }
        val completionRate = if (classStudents.isEmpty()) item.completionRate else classStudents.count { (state.local.studentTaskStatuses[it.id] ?: it.taskStatus) == com.xiangshang.youth.core.model.TaskStatus.Completed } * 100 / classStudents.size
        Surface(Modifier.fillMaxWidth().padding(vertical = 5.dp).semantics { role = Role.Button; contentDescription = "查看${item.name}风险学生，完成率${completionRate}%" }.clickable { nav.navigate("${Destinations.Risk}?className=${android.net.Uri.encode(item.name)}") }, color = Color.White, shape = RoundedCornerShape(11.dp), shadowElevation = 1.dp) {
            Column(Modifier.padding(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(item.name, color = Navy, fontWeight = FontWeight.Bold); Text("${item.teacherName} · ${item.studentCount}人", color = Color.Gray, fontSize = 9.sp) }; Text("${completionRate}%", color = if (completionRate < 80) Color.Red else Green, fontWeight = FontWeight.Bold, fontSize = 18.sp); Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.padding(start = 5.dp)) }
                LinearProgressIndicator({ completionRate / 100f }, Modifier.fillMaxWidth().padding(top = 9.dp).height(6.dp), color = if (completionRate < 80) Color(0xFFFF9D25) else Green, trackColor = Sky)
                Text(if (completionRate < 80) "建议班主任跟进" else "进度正常", color = if (completionRate < 80) Color(0xFFFF8B1F) else Color.Gray, fontSize = 8.sp, modifier = Modifier.padding(top = 5.dp))
            }
        }
    }
    if (classes.isEmpty()) EmptyState("暂无班级数据，请调整年级筛选后重试。")
}

@Composable
fun RiskStudentsScreen(state: AppUiState, nav: NavHostController, className: String?, onOpenReport: (com.xiangshang.youth.core.model.Student) -> Unit) = AppScaffold("重点风险学生", onBack = { nav.popBackStack() }) {
    if (state.loading || state.data == null) { LoadingState(); return@AppScaffold }
    var riskFilter by rememberSaveable { mutableStateOf("全部") }
    val students = state.data?.students.orEmpty().filter { student ->
        val status = state.local.studentTaskStatuses[student.id] ?: student.taskStatus
        (className == null || student.className == className) && when (riskFilter) {
            "待复核" -> status.name == "Review"
            "待补测" -> status.name == "Retest"
            "低分" -> (student.totalScore ?: 35.0) < 25
            else -> (student.totalScore ?: 35.0) < 25 || status.name == "Review" || status.name == "Retest"
        }
    }
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) { listOf("全部", "待复核", "待补测", "低分").forEach { item -> FilterChip(selected = riskFilter == item, onClick = { riskFilter = item }, label = { Text(item, fontSize = 9.sp) }) } }
    Text("共${students.size}人 · 点击学生查看7项测评、风险提示和训练建议。", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.padding(bottom = 5.dp))
    students.forEach { StudentCard(it, onClick = { onOpenReport(it) }); Spacer(Modifier.height(7.dp)) }
    if (students.isEmpty()) EmptyState("当前筛选暂无学生，该类预警已处理完成。")
}
