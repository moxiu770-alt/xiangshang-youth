package com.xiangshang.youth.feature.parent

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.xiangshang.youth.app.AppUiState
import com.xiangshang.youth.app.Destinations
import com.xiangshang.youth.app.Blue
import com.xiangshang.youth.app.Canvas
import com.xiangshang.youth.app.Navy
import com.xiangshang.youth.core.model.*
import com.xiangshang.youth.core.service.FollowAlongSessionRecord
import com.xiangshang.youth.core.util.BusinessClock
import java.util.*

private fun restoredBodyAssessmentStage(draft: BodyAssessmentDraft?): Int {
    if (draft == null) return 0
    if (draft.guardianReady || draft.consentAcknowledged || draft.environmentReady) return draft.stage
    // Drafts created before the nine-step flow used 1=BMI, 2=capture and
    // 3=confirmation. Only migrate drafts carrying the old payload; an empty
    // new consent/profile draft must remain on its own step.
    return when {
        draft.stage == 1 && (draft.heightCm > 0 || draft.weightKg > 0) -> 3
        draft.stage == 2 && draft.captures.isNotEmpty() -> 5
        draft.stage == 3 && draft.captures.isNotEmpty() -> 6
        else -> draft.stage
    }
}

/**
 * The BMI step is the fourth step in the user-facing nine-step flow. Keep the
 * transition in one small pure function so a UI refactor cannot accidentally
 * send a valid measurement back to the child-profile step.
 */
internal fun bodyAssessmentStepAfterMetrics(hasValidCoreMeasurements: Boolean): Int =
    if (hasValidCoreMeasurements) 4 else 3

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BodyAssessmentScreen(state: AppUiState, nav: NavHostController, save: (Student, BodyAssessmentRecord) -> Unit, saveDraft: (Student, BodyAssessmentDraft) -> Unit, toggleDay: (Student, String) -> Unit, saveFollowAlongSession: (FollowAlongSessionRecord) -> Unit = {}, updateVoiceGuidance: (Boolean) -> Unit = {}, recordHealthConsent: (String) -> Unit = {}) {
    val child = state.selectedChild
    if (child == null) { Scaffold(containerColor = Canvas) { Box(Modifier.padding(it).fillMaxSize(), contentAlignment = Alignment.Center) { Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("请先绑定孩子") } } }; return }
    val persistedDraft = state.local.bodyAssessmentDrafts[child.id]
    val previous = state.local.bodyAssessments[child.id]
    // A completed record is a long-term family health asset. Re-entering this
    // page should show the saved result first, rather than forcing a parent
    // through consent and four capture tasks again. An in-progress draft still
    // wins so unfinished work resumes at the exact step where it was left.
    var stage by rememberSaveable { mutableIntStateOf(restoredBodyAssessmentStage(persistedDraft).coerceIn(0, 6).let { if (persistedDraft == null && previous != null) 7 else it }) }
    var height by rememberSaveable { mutableDoubleStateOf(persistedDraft?.heightCm ?: previous?.heightCm ?: 0.0) }
    var weight by rememberSaveable { mutableDoubleStateOf(persistedDraft?.weightKg ?: previous?.weightKg ?: 0.0) }
    var fatherHeight by rememberSaveable { mutableDoubleStateOf(persistedDraft?.fatherHeightCm ?: previous?.fatherHeightCm ?: 0.0) }
    var motherHeight by rememberSaveable { mutableDoubleStateOf(persistedDraft?.motherHeightCm ?: previous?.motherHeightCm ?: 0.0) }
    var captureNames by rememberSaveable { mutableStateOf((persistedDraft?.captures ?: previous?.captures ?: emptySet()).map { it.name }) }
    val captures = captureNames.mapNotNull { runCatching { BodyCaptureTask.valueOf(it) }.getOrNull() }.toSet()
    var asymmetric by rememberSaveable { mutableStateOf(persistedDraft?.asymmetric ?: previous?.asymmetric ?: false) }
    var gait by rememberSaveable { mutableStateOf(persistedDraft?.gaitConcern ?: previous?.gaitConcern ?: false) }
    var adultReady by rememberSaveable { mutableStateOf(persistedDraft?.guardianReady ?: false) }
    var spaceReady by rememberSaveable { mutableStateOf(persistedDraft?.environmentReady ?: false) }
    var consentAcknowledged by rememberSaveable { mutableStateOf(persistedDraft?.consentAcknowledged ?: false) }
    // A completed record opens as a read-only history entry. Back exits the
    // feature instead of walking into the old parent-confirmation step.
    var viewingSavedRecord by rememberSaveable { mutableStateOf(persistedDraft == null && previous != null) }
    var activeCaptureTask by remember { mutableStateOf<BodyCaptureTask?>(null) }
    var showFollowAlong by rememberSaveable { mutableStateOf(false) }
    var followAlongDayIndex by rememberSaveable { mutableIntStateOf(0) }
    var followAlongDateKey by rememberSaveable { mutableStateOf("") }
    var captureFeedback by rememberSaveable { mutableStateOf<Map<String, String>>(emptyMap()) }
    var visualHints by rememberSaveable { mutableStateOf((persistedDraft?.captureObservationHints ?: previous?.captureObservationHints).takeUnless { it.isNullOrEmpty() } ?: (persistedDraft?.visualObservationHint ?: previous?.visualObservationHint)?.let { hint -> captures.firstOrNull()?.let { mapOf(it.name to hint) } }.orEmpty()) }
    var postureSnapshots by remember { mutableStateOf(persistedDraft?.postureSnapshots ?: previous?.postureReport?.snapshots.orEmpty()) }
    val hasValidCoreMeasurements = height in 90.0..190.0 && weight in 15.0..90.0
    val assessmentSteps = listOf("使用说明", "监护人授权", "孩子身体信息", "身高体重和BMI", "拍摄环境检查", "摄像头测评", "质量确认", "结果报告", "训练计划")
    val displayStep = stage.coerceIn(0, assessmentSteps.lastIndex)
    fun record(): BodyAssessmentRecord { val now = BusinessClock.day(); val ageAtMeasurement = child.bodyAssessmentAgeMonths; val draft = BodyAssessmentRecord(height, weight, now, captures, asymmetric, gait, now, visualObservationHint = visualHints.toSortedMap().values.joinToString("\n"), fatherHeightCm = fatherHeight, motherHeightCm = motherHeight, captureObservationHints = visualHints, postureReport = postureSnapshots.takeIf { it.isNotEmpty() }?.let { PostureAssessmentReport.make(it, now, ageAtMeasurement) }, ageMonthsAtMeasurement = ageAtMeasurement); val days = when (draft.level(ageAtMeasurement, child.gender)) { BodyAttentionLevel.Red -> 7; BodyAttentionLevel.Yellow -> 30; BodyAttentionLevel.Pending -> 3; BodyAttentionLevel.Green -> 90; BodyAttentionLevel.Unavailable -> 30 }; val follow = Calendar.getInstance(BusinessClock.timeZone).apply { add(Calendar.DAY_OF_YEAR, days) }; return draft.copy(nextFollowUp = BusinessClock.day(follow.time), planDays = previous?.planDays.orEmpty()) }
    LaunchedEffect(stage, height, weight, fatherHeight, motherHeight, captureNames, asymmetric, gait, visualHints, postureSnapshots) {
        if (stage <= 6) saveDraft(child, BodyAssessmentDraft(stage = stage, guardianReady = adultReady, consentAcknowledged = consentAcknowledged, environmentReady = spaceReady, heightCm = height, weightKg = weight, captures = captures, asymmetric = asymmetric, gaitConcern = gait, visualObservationHint = visualHints.toSortedMap().values.joinToString("\n"), fatherHeightCm = fatherHeight, motherHeightCm = motherHeight, captureObservationHints = visualHints, postureSnapshots = postureSnapshots))
    }
    Scaffold(containerColor = Canvas, topBar = { TopAppBar(title = { Text(assessmentSteps[displayStep], color = Navy, fontWeight = FontWeight.Bold) }, navigationIcon = { IconButton(onClick = { if (viewingSavedRecord && stage == 7) nav.popBackStack() else if (stage > 0) stage-- else nav.popBackStack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } }) }) { padding ->
        Column(Modifier.padding(padding).padding(14.dp).fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("家庭身体测评 · ${assessmentSteps[displayStep]}", color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                Text("${displayStep + 1} / ${assessmentSteps.size}", color = Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp)
            }
            LinearProgressIndicator(progress = { (displayStep + 1) / assessmentSteps.size.toFloat() }, modifier = Modifier.fillMaxWidth(), color = Color(0xFFF47A59))
            when (stage) {
                0 -> { Hero("给 ${child.name} 一次居家身体观察", "BMI、三种姿态和一段自然步态，全程由家长在 App 内完成，约 5 分钟。") ; Info("App 内相机 · 实时记录 · 健康观察"); previous?.let { saved -> Surface(onClick = { viewingSavedRecord = true; stage = 7 }, modifier = Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(16.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Assessment, null, tint = Blue); Spacer(Modifier.width(10.dp)); Column(Modifier.weight(1f)) { Text("查看最近一次家庭观察", color = Navy, fontWeight = FontWeight.Bold); Text("BMI ${"%.1f".format(saved.bmi)} · ${saved.level(child.bodyAssessmentAgeMonths, child.gender).label} · 建议复测 ${saved.nextFollowUp}", color = Color.Gray, fontSize = 12.sp, maxLines = 2) }; Icon(Icons.Filled.ChevronRight, null, tint = Blue) } } }; Info("完成授权、孩子资料、BMI、环境检查、摄像头测评、质量确认后生成结果和训练计划。每一步按当前孩子单独保存，可随时返回。"); Button(onClick = { stage = 1 }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text("开始授权") } }
                1 -> { Text("身体测评仅用于家庭运动健康筛查和训练建议，不替代医疗诊断。App 不保存原始照片或视频，只保存测量值、动作结果和质量摘要。", color = Color.Gray); ReadyRow("我确认自己是孩子的监护人，并会全程陪同。", adultReady) { adultReady = it }; ReadyRow("我已阅读摄像头、算法和数据保留说明。", consentAcknowledged) { consentAcknowledged = it }; Button(onClick = { recordHealthConsent(child.id); stage = 2 }, enabled = adultReady && consentAcknowledged, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text(if (adultReady && consentAcknowledged) "继续确认孩子资料" else "请完成授权确认") } }
                2 -> { Text("请确认本次测评使用的孩子资料。年龄别 BMI 会根据孩子资料中的出生日期和本次测量日期计算。", color = Color.Gray); Surface(color = Color.White, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) { Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) { Text(child.name, color = Navy, fontWeight = FontWeight.Bold); Text("${child.grade} · ${child.className}", color = Color.Gray); Text("性别：${child.gender} · 年龄参考：${child.bodyAssessmentAgeLabel}", color = Color.Gray); Text("如资料有误，请先在家庭账户中联系学校更正。", color = Color.Gray, fontSize = 12.sp) } }; Button(onClick = { stage = 3 }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text("填写身高体重") } }
                3 -> {
                    Text("请填写本次实际测量值。BMI = 体重(kg) ÷ 身高²(m²)，不以固定年龄作为录入条件；若孩子资料已有出生日期，报告会额外显示${child.bodyAssessmentAgeLabel}的年龄别筛查参考。", color = Color.Gray)
                    Info("为避免相机成像缩放差异，身高和体重请按身高仪、体重秤的实际读数填写；相机只用于姿态与步态观察。")
                    SliderRow("身高", height, 90f..190f, "cm") { height = it.toDouble() }
                    SliderRow("体重", weight, 15f..90f, "kg") { weight = it.toDouble() }
                    Text("遗传靶身高参考（选填）", color = Navy, fontWeight = FontWeight.Bold)
                    Text("男孩＝（父亲身高＋母亲身高＋13 cm）÷ 2；女孩＝（父亲身高＋母亲身高−13 cm）÷ 2。区间按中位值 ±5 cm 展示，仅作健康管理参考，不代表成年身高预测。", color = Color.Gray, fontSize = 12.sp)
                    SliderRow("父亲身高", fatherHeight, 120f..230f, "cm") { fatherHeight = it.toDouble() }
                    SliderRow("母亲身高", motherHeight, 120f..230f, "cm") { motherHeight = it.toDouble() }
                    val r = record()
                    Info(if (hasValidCoreMeasurements) "当前 BMI ${"%.1f".format(r.bmi)} · ${r.bmiScreeningLabel(child.bodyAssessmentAgeMonths, child.gender)} · 儿童年龄别 BMI 标准" else "请填写有效的身高（90–190 cm）和体重（15–90 kg）；不会预置孩子的测量数据。")
                    r.geneticHeightReference(child.gender)?.let { reference -> val range = r.geneticHeightRange(child.gender); Info("遗传靶身高中位 ${"%.1f".format(reference)} cm · 区间 ${"%.1f".format(range?.start)}–${"%.1f".format(range?.endInclusive)} cm · ${r.geneticHeightFormula(child.gender)}") }
                    r.heightDevelopmentAssessment(child.bodyAssessmentAgeMonths, child.gender)?.let { height -> Info("当前身高发育：${height.level.label} · ${height.ageYears}岁参考中位 ${"%.1f".format(height.median)} cm · 儿童身高参考标准") }
                    Button(onClick = { stage = bodyAssessmentStepAfterMetrics(hasValidCoreMeasurements) }, enabled = hasValidCoreMeasurements, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text(if (hasValidCoreMeasurements) "继续拍摄记录" else "请填写有效身高和体重") }
                }
                4 -> { Text("拍摄前请确认环境安全，系统会在相机打开后继续检查光线、距离、遮挡和多人入镜。", color = Color.Gray); ReadyRow("光线充足，地面平整，孩子可以完整入镜。", spaceReady) { spaceReady = it }; Info("镜头距离约 2–3 米，手机保持稳定；画面中只出现一名孩子；穿着便于观察肩、髋和膝部位的衣物。"); Button(onClick = { stage = 5 }, enabled = spaceReady, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text(if (spaceReady) "打开摄像头测评" else "请完成环境确认") } }
                5 -> { Text("打开 App 内相机后可切换前后摄像头，并有语音提示。画面仅用于本次观察，不会保存为照片或视频。", color = Color.Gray); BodyCaptureTask.values().forEach { task -> Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "${task.title}，${if (task in captures) "已完成" else "打开相机"}" }.clickable { activeCaptureTask = task }, color = Color.White, shape = RoundedCornerShape(16.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Icon(if (task == BodyCaptureTask.GaitVideo) Icons.Filled.Videocam else Icons.Filled.CameraAlt, null, tint = if (task in captures) Color(0xFF25B86A) else Color(0xFFF47A59)); Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f)) { Text(task.title, fontWeight = FontWeight.Bold, color = Navy); Text(task.guide, color = Color.Gray, fontSize = 12.sp); captureFeedback[task.name]?.let { Text(it, color = if (task in captures) Color(0xFF25B86A) else Color(0xFFFF8A24), fontSize = 12.sp) } }; Icon(if (task in captures) Icons.Filled.CheckCircle else Icons.Filled.ChevronRight, null, tint = if (task in captures) Color(0xFF25B86A) else Blue) } } }; Button(onClick = { stage = 6 }, enabled = captures.size == BodyCaptureTask.values().size, modifier = Modifier.fillMaxWidth()) { Text(if (captures.size == BodyCaptureTask.values().size) "继续质量确认" else "请完成全部拍摄") } }
                6 -> { Text("请确认每项拍摄均清晰、身体完整入镜且没有多人或遮挡；家长再补充疼痛、不适或活动受限等安全信息。", color = Color.Gray); visualHints.toSortedMap().forEach { (task, hint) -> Info("${runCatching { BodyCaptureTask.valueOf(task).title }.getOrDefault("拍摄记录任务")}：$hint") }; ToggleRow("孩子近期有肩背、腰背或坐姿疼痛/不适", asymmetric) { asymmetric = it }; ToggleRow("孩子近期有行走困难、跛行或活动受限", gait) { gait = it }; Button(onClick = { save(child, record()); stage = 7 }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text("查看家庭观察结果") } }
                7 -> { val r = state.local.bodyAssessments[child.id] ?: record(); val level = r.level(child.bodyAssessmentAgeMonths, child.gender); val history = state.local.bodyAssessmentHistory[child.id].orEmpty(); Hero("${child.name} 的身体测评报告", "BMI ${"%.1f".format(r.bmi)} · ${level.label} · 下次建议复测 ${r.nextFollowUp}"); if (state.repositoryAcknowledged) state.local.bodyAssessmentSyncStates[child.id]?.let { syncStatus -> Info(when (syncStatus) { com.xiangshang.youth.core.service.LocalSubmissionStatus.PendingSync -> "测评结果已保存，联网后自动同步。"; com.xiangshang.youth.core.service.LocalSubmissionStatus.Submitting -> "正在同步测评结果…"; com.xiangshang.youth.core.service.LocalSubmissionStatus.Submitted -> "测评结果已同步。"; com.xiangshang.youth.core.service.LocalSubmissionStatus.Failed -> "同步失败，结果仍已保存。请稍后重试。"; com.xiangshang.youth.core.service.LocalSubmissionStatus.Draft -> "测评结果尚未完成保存。" }) }; r.geneticHeightReference(child.gender)?.let { Info("遗传身高参考 ${"%.1f".format(it)} cm · ${r.geneticHeightFormula(child.gender)}。仅供健康管理参考。") }; r.postureReport?.let { report -> Surface(color = Color.White, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) { Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Text("人体姿态测评报告", color = Navy, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)); Text(report.overallLevel.label, color = if (report.overallLevel == BodyAttentionLevel.Red) Color.Red else Blue, fontSize = 12.sp, fontWeight = FontWeight.Bold) }; Text("本次观察 · ${report.snapshots.values.sumOf { it.sampleCount }} 条记录", color = Color.Gray, fontSize = 12.sp); report.snapshots.toSortedMap(compareBy { it.name }).values.forEach { snapshot -> PostureSnapshotDetail(snapshot) }; report.reasons.forEach { Text("• $it", color = Navy, fontSize = 12.sp) }; Text(report.disclaimer, color = Color.Gray, fontSize = 12.sp) } } }; Info("已完成 ${r.captures.size}/4 个拍摄任务。画面未保存；家长只补充疼痛等安全信息，姿态指标为观察依据。"); r.visualObservationSummary?.let { Info(it) }; Info(if (history.size < 2) "完成下一次实测后，将显示真实 BMI 趋势；不会虚构历史或目标数据。" else "BMI 实测趋势：${history.takeLast(3).joinToString(" → ") { "%.1f".format(it.bmi) }}"); Button(onClick = { stage = 8 }, modifier = Modifier.fillMaxWidth()) { Text("开始 28 天健康计划") }; OutlinedButton(onClick = { viewingSavedRecord = false; stage = 0; adultReady = false; spaceReady = false; consentAcknowledged = false }, modifier = Modifier.fillMaxWidth()) { Text("重新开始一次测评") }; OutlinedButton(onClick = { nav.navigate(Destinations.Courses) }, modifier = Modifier.fillMaxWidth()) { Text("查看推荐课程") } }
                8 -> {
                    val r = state.local.bodyAssessments[child.id] ?: record()
                    val planTexts = followAlongDays.map { day -> if (day.exercises.isEmpty()) "恢复日：轻松呼吸、肩背舒展与户外散步" else day.exercises.joinToString(" + ") { "${it.title} ${it.target}${it.unit}" } }
                    Text("已完成 ${r.planDays.size} / 28 天", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Navy)
                    Info("计划进度已保存，联网后自动同步提醒。")
                    Button(onClick = {
                        val today = Calendar.getInstance(BusinessClock.timeZone).apply { set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }.time
                        followAlongDateKey = BusinessClock.day(today)
                        followAlongDayIndex = (Calendar.getInstance(BusinessClock.timeZone).get(Calendar.DAY_OF_WEEK) + 5) % 7
                        showFollowAlong = true
                    }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Blue)) {
                        Icon(Icons.Filled.PlayCircle, null); Spacer(Modifier.width(7.dp)); Column(horizontalAlignment = Alignment.Start) { Text("开始今日训练跟练", fontWeight = FontWeight.Bold); Text("示范视频 + 可选我的画面 + 语音动作提示", fontSize = 12.sp) }
                    }
                    (0 until 28).forEach { i ->
                        val date = Calendar.getInstance(BusinessClock.timeZone).apply { add(Calendar.DAY_OF_YEAR, i) }.time
                        val key = BusinessClock.day(date)
                        val done = key in r.planDays
                        Surface(
                            Modifier.fillMaxWidth()
                                .semantics {
                                    role = Role.Button
                                    contentDescription = if (done) "第 ${i + 1} 天训练已完成，可查看记录" else "第 ${i + 1} 天训练，进入跟做训练"
                                }
                                .clickable {
                                    if (done) toggleDay(child, key) else { followAlongDayIndex = i % 7; followAlongDateKey = key; showFollowAlong = true }
                                },
                            color = Color.White,
                            shape = RoundedCornerShape(14.dp)
                        ) {
                            Row(Modifier.padding(13.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(if (done) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (done) Color(0xFF25B86A) else Blue)
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) { Text("第 ${i + 1} 天 · ${planTexts[i % planTexts.size]}", color = Navy, fontWeight = FontWeight.SemiBold); Text(if (done) "已记录今日训练" else "点击进入跟做训练", color = Color.Gray, fontSize = 12.sp) }
                                Text(if (done) "已完成" else "去完成", color = if (done) Color(0xFF25B86A) else Blue, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                    OutlinedButton(onClick = { nav.navigate(Destinations.Health) }, modifier = Modifier.fillMaxWidth()) { Text("返回健康档案") }
                }
            }
        }
    }
    activeCaptureTask?.let { task ->
        LivePostureCaptureDialog(
            task = task,
            measuredHeightCm = height,
            childAgeMonths = child.bodyAssessmentAgeMonths,
            voiceGuidanceEnabled = state.local.settings.voiceGuidanceEnabled,
            onVoiceGuidanceChanged = updateVoiceGuidance,
            onComplete = { analysis ->
            captureFeedback = captureFeedback + (task.name to analysis.message)
            visualHints = analysis.observationHint?.let { visualHints + (task.name to it) } ?: (visualHints - task.name)
            analysis.postureSnapshot?.let { snapshot -> postureSnapshots = postureSnapshots + (task to snapshot) }
            if (analysis.accepted) captureNames = (captures + task).map { it.name }
            activeCaptureTask = null
        }, onDismiss = {
            captureFeedback = captureFeedback + (task.name to "已取消记录，可稍后继续。")
            activeCaptureTask = null
        })
    }
    if (showFollowAlong) {
        FollowAlongTrainingDialog(
            studentId = child.id,
            studentName = child.name,
            childAgeMonths = child.bodyAssessmentAgeMonths,
            dayIndex = followAlongDayIndex,
            voiceGuidanceEnabled = state.local.settings.voiceGuidanceEnabled,
            onVoiceGuidanceChanged = updateVoiceGuidance,
            onSessionSaved = saveFollowAlongSession,
            onComplete = { showFollowAlong = false },
            onDismiss = { showFollowAlong = false }
        )
    }
}
@Composable private fun PostureSnapshotDetail(snapshot: PostureMetricSnapshot) {
    val metrics = buildList {
        snapshot.shoulderHeightDifferenceCm?.let { add("双肩差 %.1f cm".format(it)) }
        snapshot.pelvicHeightDifferenceCm?.let { add("骨盆差 %.1f cm".format(it)) }
        snapshot.spinalMidlineDeviationCm?.let { add("中线偏移 %.1f cm".format(it)) }
        snapshot.cameraProxyAtrDegrees?.let { add("旋转代理 %.1f°".format(it)) }
        snapshot.gaitTrunkSwayCm?.let { add("步态摆动 %.1f cm".format(it)) }
    }
    Surface(color = Canvas, shape = RoundedCornerShape(10.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(9.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(snapshot.task.title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp, modifier = Modifier.weight(1f))
                Text("记录稳定度 %.0f%% · %d 条".format(snapshot.confidence * 100, snapshot.sampleCount), color = if (snapshot.confidence >= PostureScreeningRules.minimumConfidence && snapshot.sampleCount >= PostureScreeningRules.minimumSamples) Color(0xFF25B86A) else Color(0xFFF47A59), fontSize = 12.sp)
            }
            Text(metrics.ifEmpty { listOf("指标尚未完整，请重新拍摄") }.joinToString(" · "), color = Color.Gray, fontSize = 12.sp)
        }
    }
}
@Composable private fun Hero(title: String, detail: String) = Surface(color = Color(0xFFFFF0CE), shape = RoundedCornerShape(20.dp)) { Column(Modifier.padding(18.dp)) { Text(title, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Navy); Spacer(Modifier.height(7.dp)); Text(detail, color = Color.DarkGray) } }
@Composable private fun Info(text: String) = Surface(color = Color.White, shape = RoundedCornerShape(14.dp)) { Text(text, modifier = Modifier.padding(14.dp), color = Color.Gray, fontSize = 13.sp) }
@Composable private fun ReadyRow(text: String, checked: Boolean, change: (Boolean) -> Unit) = Surface(color = Color.White, shape = RoundedCornerShape(14.dp)) { Row(Modifier.padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Checkbox(checked = checked, onCheckedChange = change); Text(text, color = Navy, fontSize = 12.sp, modifier = Modifier.weight(1f)) } }
@Composable private fun SliderRow(title: String, value: Double, range: ClosedFloatingPointRange<Float>, unit: String, change: (Float) -> Unit) {
    var raw by rememberSaveable(title) { mutableStateOf("") }
    LaunchedEffect(value) { raw = if (value > 0) "%.1f".format(Locale.US, value) else "" }
    fun update(rawValue: String) {
        raw = rawValue
        rawValue.replace(',', '.').toDoubleOrNull()?.let { change(BodyMeasurementInput.normalized(it, range.start.toDouble()..range.endInclusive.toDouble(), if (unit == "kg") .1 else .5).toFloat()) }
    }
    fun nudge(delta: Float) { change(BodyMeasurementInput.normalized((if (value > 0) value else range.start.toDouble()) + delta, range.start.toDouble()..range.endInclusive.toDouble(), if (unit == "kg") .1 else .5).toFloat()) }
    Surface(color = Color.White, shape = RoundedCornerShape(16.dp)) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, fontWeight = FontWeight.Bold, color = Navy)
                Spacer(Modifier.weight(1f))
                OutlinedIconButton(onClick = { nudge(if (unit == "kg") -.1f else -.5f) }, modifier = Modifier.size(32.dp)) { Icon(Icons.Filled.Remove, "$title 减少", modifier = Modifier.size(15.dp)) }
                OutlinedTextField(value = raw, onValueChange = ::update, singleLine = true, placeholder = { Text("输入", fontSize = 12.sp) }, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.width(78.dp).padding(horizontal = 4.dp), textStyle = TextStyle(color = Color(0xFFF47A59), fontWeight = FontWeight.Bold, textAlign = androidx.compose.ui.text.style.TextAlign.End), suffix = { Text(unit, color = Color(0xFFF47A59), fontSize = 12.sp) })
                OutlinedIconButton(onClick = { nudge(if (unit == "kg") .1f else .5f) }, modifier = Modifier.size(32.dp)) { Icon(Icons.Filled.Add, "$title 增加", modifier = Modifier.size(15.dp)) }
            }
            Slider(value = if (value > 0) value.toFloat() else range.start, onValueChange = { change(BodyMeasurementInput.normalized(it.toDouble(), range.start.toDouble()..range.endInclusive.toDouble(), if (unit == "kg") .1 else .5).toFloat()) }, valueRange = range)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text("%.0f".format(range.start), color = Color.Gray, fontSize = 12.sp); Text("滑动 / 输入 / 微调", color = Color.Gray, fontSize = 12.sp); Text("%.0f".format(range.endInclusive), color = Color.Gray, fontSize = 12.sp) }
        }
    }
}
@Composable private fun ToggleRow(title: String, checked: Boolean, change: (Boolean) -> Unit) = Surface(color = Color.White, shape = RoundedCornerShape(16.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Text(title, color = Navy, modifier = Modifier.weight(1f)); Switch(checked = checked, onCheckedChange = change) } }
