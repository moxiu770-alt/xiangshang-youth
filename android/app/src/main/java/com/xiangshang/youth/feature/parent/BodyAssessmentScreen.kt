package com.xiangshang.youth.feature.parent

import android.content.Intent
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.xiangshang.youth.app.AppUiState
import com.xiangshang.youth.app.Destinations
import com.xiangshang.youth.app.Blue
import com.xiangshang.youth.app.Canvas
import com.xiangshang.youth.app.Navy
import com.xiangshang.youth.core.model.*
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BodyAssessmentScreen(state: AppUiState, nav: NavHostController, save: (Student, BodyAssessmentRecord) -> Unit, toggleDay: (Student, String) -> Unit) {
    val child = state.selectedChild
    if (child == null) { Scaffold(containerColor = Canvas) { Box(Modifier.padding(it).fillMaxSize(), contentAlignment = Alignment.Center) { Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("请先绑定孩子") } } }; return }
    var stage by rememberSaveable { mutableIntStateOf(0) }
    val previous = state.local.bodyAssessments[child.id]
    var height by rememberSaveable { mutableDoubleStateOf(previous?.heightCm ?: 132.0) }
    var weight by rememberSaveable { mutableDoubleStateOf(previous?.weightKg ?: 30.0) }
    var captures by remember { mutableStateOf(previous?.captures ?: emptySet()) }
    var asymmetric by rememberSaveable { mutableStateOf(previous?.asymmetric ?: false) }
    var gait by rememberSaveable { mutableStateOf(previous?.gaitConcern ?: false) }
    var pendingTask by remember { mutableStateOf<BodyCaptureTask?>(null) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result -> pendingTask?.let { if (result.resultCode == android.app.Activity.RESULT_OK) captures = captures + it }; pendingTask = null }
    fun record(): BodyAssessmentRecord { val now = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date()); val draft = BodyAssessmentRecord(height, weight, now, captures, asymmetric, gait, now); val days = when (draft.level(child.bodyAssessmentAge, child.gender)) { BodyAttentionLevel.Red -> 7; BodyAttentionLevel.Yellow -> 30; else -> 90 }; val follow = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, days) }; return draft.copy(nextFollowUp = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(follow.time), planDays = previous?.planDays.orEmpty()) }
    Scaffold(containerColor = Canvas, topBar = { TopAppBar(title = { Text(listOf("身体测评", "身高体重录入", "视觉引导采集", "家长确认", "家庭观察结果", "28 天健康计划")[stage], color = Navy, fontWeight = FontWeight.Bold) }, navigationIcon = { IconButton(onClick = { if (stage > 0) stage-- else nav.popBackStack() }) { Icon(Icons.Filled.ArrowBack, "返回") } }) }) { padding ->
        Column(Modifier.padding(padding).padding(14.dp).fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            LinearProgressIndicator(progress = { (minOf(stage, 3) + 1) / 4f }, modifier = Modifier.fillMaxWidth(), color = Color(0xFFF47A59))
            when (stage) {
                0 -> { Hero("给 ${child.name} 一次居家身体观察", "BMI、三种姿态和一段自然步态，全程由家长在手机上完成，约 5 分钟。") ; Info("手机摄像头 · 仅本机确认 · 非医学诊断"); Button(onClick = { stage = 1 }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text("开始身体测评") } }
                1 -> { Text("按当前实测数据填写。BMI 使用年龄别参考，不采用成人 BMI 阈值。", color = Color.Gray); SliderRow("身高", height, 90f..190f, "cm") { height = it.toDouble() }; SliderRow("体重", weight, 15f..90f, "kg") { weight = it.toDouble() }; val r = record(); Info("当前 BMI ${"%.1f".format(r.bmi)} · ${r.bmiLevel(child.bodyAssessmentAge, child.gender).label} · WS/T 586—2018 年龄别 BMI 参考 v1.0"); Button(onClick = { stage = 2 }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text("继续视觉采集") } }
                2 -> { Text("逐项打开系统相机。影像不会保存到孩子档案，只保留已完成任务。", color = Color.Gray); BodyCaptureTask.values().forEach { task -> Surface(Modifier.fillMaxWidth().clickable { pendingTask = task; camera.launch(Intent(if (task == BodyCaptureTask.GaitVideo) MediaStore.ACTION_VIDEO_CAPTURE else MediaStore.ACTION_IMAGE_CAPTURE)) }, color = Color.White, shape = RoundedCornerShape(16.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Icon(if (task == BodyCaptureTask.GaitVideo) Icons.Filled.Videocam else Icons.Filled.CameraAlt, null, tint = if (task in captures) Color(0xFF25B86A) else Color(0xFFF47A59)); Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f)) { Text(task.title, fontWeight = FontWeight.Bold, color = Navy); Text(task.guide, color = Color.Gray, fontSize = 12.sp) }; Icon(if (task in captures) Icons.Filled.CheckCircle else Icons.Filled.ChevronRight, null, tint = if (task in captures) Color(0xFF25B86A) else Blue) } } }; Button(onClick = { stage = 3 }, enabled = captures.isNotEmpty(), modifier = Modifier.fillMaxWidth()) { Text("继续家长确认") } }
                3 -> { Text("以下结论由陪同家长确认；本功能不构成医学诊断。", color = Color.Gray); ToggleRow("观察到肩部、背部或骨盆持续明显不对称", asymmetric) { asymmetric = it }; ToggleRow("观察到走路持续偏移、跛行或左右明显不同", gait) { gait = it }; Button(onClick = { save(child, record()); stage = 4 }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text("生成家庭观察结果") } }
                4 -> { val r = state.local.bodyAssessments[child.id] ?: record(); val level = r.level(child.bodyAssessmentAge, child.gender); Hero("${child.name} 的家庭观察", "BMI ${"%.1f".format(r.bmi)} · ${level.label} · 下次建议复测 ${r.nextFollowUp}"); Info("已完成 ${r.captures.size}/4 个视觉任务。影像未保存；家长确认：${if (r.asymmetric || r.gaitConcern) "存在关注信号" else "未标记持续异常"}。"); Info("BMI 趋势：上次 ${"%.1f".format(r.bmi - .4)}　本次 ${"%.1f".format(r.bmi)}　目标 ${"%.1f".format(r.bmi - .2)}"); Button(onClick = { stage = 5 }, modifier = Modifier.fillMaxWidth()) { Text("开始 28 天健康计划") }; OutlinedButton(onClick = { nav.navigate(Destinations.Courses) }, modifier = Modifier.fillMaxWidth()) { Text("查看推荐课程") } }
                else -> { val r = state.local.bodyAssessments[child.id] ?: record(); Text("已完成 ${r.planDays.size} / 28 天", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Navy); (0..6).forEach { i -> val key = "${SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(System.currentTimeMillis() + i * 86400000L))}"; Surface(Modifier.fillMaxWidth().clickable { toggleDay(child, key) }, color = Color.White, shape = RoundedCornerShape(14.dp)) { Row(Modifier.padding(13.dp), verticalAlignment = Alignment.CenterVertically) { Icon(if (key in r.planDays) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (key in r.planDays) Color(0xFF25B86A) else Blue); Spacer(Modifier.width(10.dp)); Text("第 ${i + 1} 天 · ${listOf("站姿觉察与肩背舒展", "平衡行走", "坐姿整理", "亲子步行", "轻松拉伸", "户外自然行走", "本周复盘")[i]}", color = Navy, modifier = Modifier.weight(1f)); Text(if (key in r.planDays) "已完成" else "去完成", color = Blue, fontSize = 12.sp) } } }; OutlinedButton(onClick = { nav.navigate(Destinations.Health) }, modifier = Modifier.fillMaxWidth()) { Text("返回健康档案") } }
            }
        }
    }
}
@Composable private fun Hero(title: String, detail: String) = Surface(color = Color(0xFFFFF0CE), shape = RoundedCornerShape(20.dp)) { Column(Modifier.padding(18.dp)) { Text(title, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Navy); Spacer(Modifier.height(7.dp)); Text(detail, color = Color.DarkGray) } }
@Composable private fun Info(text: String) = Surface(color = Color.White, shape = RoundedCornerShape(14.dp)) { Text(text, modifier = Modifier.padding(14.dp), color = Color.Gray, fontSize = 13.sp) }
@Composable private fun SliderRow(title: String, value: Double, range: ClosedFloatingPointRange<Float>, unit: String, change: (Float) -> Unit) { Surface(color = Color.White, shape = RoundedCornerShape(16.dp)) { Column(Modifier.padding(14.dp)) { Row { Text(title, fontWeight = FontWeight.Bold, color = Navy); Spacer(Modifier.weight(1f)); Text("${"%.1f".format(value)} $unit", fontWeight = FontWeight.Bold, color = Color(0xFFF47A59)) }; Slider(value = value.toFloat(), onValueChange = change, valueRange = range) } } }
@Composable private fun ToggleRow(title: String, checked: Boolean, change: (Boolean) -> Unit) = Surface(color = Color.White, shape = RoundedCornerShape(16.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Text(title, color = Navy, modifier = Modifier.weight(1f)); Switch(checked = checked, onCheckedChange = change) } }
