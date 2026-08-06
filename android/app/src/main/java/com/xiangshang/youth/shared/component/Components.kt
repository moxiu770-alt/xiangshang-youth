package com.xiangshang.youth.shared.component

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun AppScaffold(title: String, onBack: (() -> Unit)? = null, onSwitchRole: (() -> Unit)? = null, onNotifications: (() -> Unit)? = null, notificationCount: Int = 0, onRefresh: (() -> Unit)? = null, isRefreshing: Boolean = false, errorMessage: String? = null, onRetry: (() -> Unit)? = null, bottomBar: @Composable () -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    Scaffold(containerColor = Canvas, topBar = {
        CenterAlignedTopAppBar(
            title = { Text(title, color = Navy, fontSize = 16.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) },
            navigationIcon = {
                onBack?.let { action ->
                    IconButton(onClick = action) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回") }
                }
            },
            actions = {
                onNotifications?.let { action ->
                    IconButton(onClick = action) {
                        BadgedBox(badge = { if (notificationCount > 0) Badge(containerColor = Color.Red, modifier = Modifier.size(6.dp)) {} }) {
                            Icon(Icons.Filled.NotificationsNone, contentDescription = "消息通知", tint = Navy, modifier = Modifier.size(20.dp))
                        }
                    }
                }
                onRefresh?.let { action ->
                    IconButton(onClick = action, enabled = !isRefreshing) {
                        if (isRefreshing) CircularProgressIndicator(Modifier.size(17.dp), color = Blue, strokeWidth = 2.dp)
                        else Icon(Icons.Filled.Refresh, contentDescription = "刷新数据", tint = Navy, modifier = Modifier.size(19.dp))
                    }
                }
                onSwitchRole?.let { action ->
                    TextButton(onClick = action) { Text("切换身份", color = Blue, fontSize = 11.sp) }
                }
            }
        )
    }, bottomBar = bottomBar) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().padding(horizontal = 12.dp).verticalScroll(rememberScrollState())) {
            if (errorMessage != null) {
                ErrorState(errorMessage, retry = onRetry ?: {})
            }
            content()
        }
    }
}
@Composable fun OfflineBanner(message: String = "当前处于离线模式，本地数据仍可查看；联网后可刷新最新数据。") {
    Surface(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp).semantics { contentDescription = message },
        color = Color(0xFFFFF0D6),
        shape = RoundedCornerShape(10.dp),
        shadowElevation = 1.dp
    ) { Text(message, color = Color(0xFF7A4B00), fontSize = 10.sp, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
}
@Composable fun RoleBadge(role: UserRole) { Text(role.label, color = Blue, fontSize = 12.sp, modifier = Modifier.background(Sky, RoundedCornerShape(14.dp)).padding(horizontal = 9.dp, vertical = 4.dp)) }
@Composable fun StudentCard(student: Student, onClick: () -> Unit) { Card(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看学生${student.name}，${student.grade}${student.className}，${if (student.isPovertyArea) "贫困地区学生" else student.region}" }.clickable(onClick = onClick), shape = RoundedCornerShape(12.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Text(student.name.take(1), color = Color.White, modifier = Modifier.background(Blue, RoundedCornerShape(22.dp)).padding(12.dp)); Spacer(Modifier.width(10.dp)); Column(Modifier.weight(1f)) { Text(student.name, color = Navy); Text(student.grade + " · " + student.className, fontSize = 11.sp, color = Color.Gray); Text(if (student.isPovertyArea) "贫困地区学生" else student.region, fontSize = 10.sp, color = if (student.isPovertyArea) Color.Red else Color.Gray) }; Text((student.totalScore ?: 0.0).toString(), color = Blue) } } }
@Composable fun TestTaskCard(task: TestTask, onClick: (() -> Unit)? = null) {
    val description = "查看体测任务${task.title}，状态${task.status.label}，已完成${task.completedCount}人，共${task.totalCount}人"
    val base = Modifier.fillMaxWidth().semantics { if (onClick != null) role = Role.Button; contentDescription = description }
    val cardModifier = if (onClick == null) base else base.clickable(onClick = onClick)
    Card(cardModifier, shape = RoundedCornerShape(12.dp)) {
        Column(Modifier.padding(12.dp)) {
            Row { Text(task.title, color = Navy, modifier = Modifier.weight(1f)); Text(task.status.label, color = Blue, fontSize = 11.sp) }
            Text(task.date + " · " + task.location, fontSize = 11.sp, color = Color.Gray)
            LinearProgressIndicator(progress = { if (task.totalCount == 0) 0f else task.completedCount.toFloat() / task.totalCount }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
            Text("已完成 " + task.completedCount + " / " + task.totalCount + " 人 · " + task.items.size + " 项体测", fontSize = 10.sp, color = Color.Gray)
        }
    }
}
@Composable fun ScoreSummaryCard(title: String, value: String, note: String, onClick: (() -> Unit)? = null) {
    val cardModifier = Modifier.fillMaxWidth().semantics {
        contentDescription = "$title，$value，$note"
        if (onClick != null) role = Role.Button
    }.let { base -> if (onClick != null) base.clickable(onClick = onClick) else base }
    Card(cardModifier) { Column(Modifier.padding(10.dp)) { Text(title, fontSize = 11.sp, color = Color.Gray); Text(value, color = Navy, fontSize = 20.sp); Text(note, fontSize = 10.sp, color = Green) } }
}
@Composable fun ReportMetricCard(score: ScoreResult) { Card(Modifier.fillMaxWidth().semantics { contentDescription = "${score.item.label}，${score.score}分，满分5分" }) { Column(Modifier.padding(10.dp)) { Text(score.item.label, fontSize = 11.sp); Text(score.score.toString(), color = Blue, fontSize = 18.sp); Text("满分5分", fontSize = 10.sp, color = Color.Gray) } } }
@Composable fun EmptyState(text: String = "暂无数据") { Box(Modifier.fillMaxWidth().padding(32.dp).semantics { contentDescription = text }, contentAlignment = Alignment.Center) { Text(text, color = Color.Gray) } }
@Composable fun LoadingState() { Box(Modifier.fillMaxWidth().padding(32.dp).semantics { contentDescription = "正在加载" }, contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
@Composable fun ErrorState(text: String, retry: () -> Unit = {}, dismiss: (() -> Unit)? = null) {
    Column(
        Modifier.fillMaxWidth().padding(24.dp).semantics { contentDescription = "加载失败：$text" },
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("加载失败", color = Color.Red, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
        Text(text, color = Color.Red, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
            TextButton(onClick = retry) { Text("重试") }
            dismiss?.let { action -> TextButton(onClick = action) { Text("关闭") } }
        }
    }
}

@Composable fun FilterBar(options: List<String> = listOf("本轮综合测评", "2026秋季"), selected: String = options.firstOrNull().orEmpty(), onSelected: (String) -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        options.forEach { option ->
            FilterChip(selected = option == selected, onClick = { onSelected(option) }, label = { Text(option, fontSize = 10.sp) }, modifier = Modifier.semantics { contentDescription = "筛选：$option" })
        }
    }
}
@Composable fun GradeClassSelector(grades: List<String> = listOf("三年级"), classes: List<String> = listOf("三年级2班"), selectedGrade: String = grades.firstOrNull().orEmpty(), selectedClass: String = classes.firstOrNull().orEmpty(), onGradeSelected: (String) -> Unit = {}, onClassSelected: (String) -> Unit = {}) {
    Row(Modifier.fillMaxWidth().background(Color.White, RoundedCornerShape(10.dp)).padding(horizontal = 8.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        DropdownSelector(selectedGrade, grades, onGradeSelected, "选择年级")
        HorizontalDivider(Modifier.height(22.dp).padding(horizontal = 4.dp))
        DropdownSelector(selectedClass, classes, onClassSelected, "选择班级")
    }
}
@Composable private fun DropdownSelector(selected: String, options: List<String>, onSelected: (String) -> Unit, description: String) {
    var expanded by androidx.compose.runtime.remember { mutableStateOf(false) }
    Box {
        TextButton(onClick = { expanded = true }, modifier = Modifier.semantics { contentDescription = description }) { Text(selected, color = Navy, fontSize = 11.sp) }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) { options.forEach { option -> DropdownMenuItem(text = { Text(option) }, onClick = { onSelected(option); expanded = false }) } }
    }
}
