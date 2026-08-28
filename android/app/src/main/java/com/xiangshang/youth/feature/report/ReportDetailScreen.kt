package com.xiangshang.youth.feature.report

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.model.CourseSuggestion
import com.xiangshang.youth.core.model.DiagnosisReport
import com.xiangshang.youth.core.model.ScoreResult
import com.xiangshang.youth.core.model.BodyAssessmentRecord
import com.xiangshang.youth.core.model.BodyCaptureTask
import com.xiangshang.youth.core.model.Student
import com.xiangshang.youth.shared.component.AppScaffold
import com.xiangshang.youth.shared.component.EmptyState
import com.xiangshang.youth.shared.component.ErrorState
import androidx.navigation.NavHostController
import java.util.Locale

/** Full report parity with iOS: student context, seven metrics and actionable advice. */
@Composable
fun ReportDetailScreen(
    report: DiagnosisReport,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    reportError: String? = null,
    onDismissReportError: (() -> Unit)? = null,
    bodyAssessment: BodyAssessmentRecord? = null,
    bodyAgeMonths: Int? = null,
    studentGender: String = "",
    nav: NavHostController? = null,
    openRecommendedCourse: ((CourseSuggestion) -> Unit)? = null
) = AppScaffold("体测报告", onBack = nav?.let { { it.popBackStack() } }) {
    var selectedDetail by remember { mutableStateOf<String?>(null) }
    Column(
        Modifier.fillMaxSize().padding(vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(11.dp)
    ) {
        ReportHero(report, isRefreshing, onRefresh)
        reportError?.let { message ->
            ErrorState(
                text = message,
                retry = onRefresh,
                dismiss = onDismissReportError
            )
        }
        Text("7项能力得分", color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp)
        // Keep the approved two-up layout at normal type. Large system text
        // gets a full-width row so each test name and review state remains
        // readable instead of being compressed into a narrow tile.
        val scoreColumns = if (LocalDensity.current.fontScale > 1.25f) 1 else 2
        report.scores.chunked(scoreColumns).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                row.forEach { score -> ReportScoreCard(score, Modifier.weight(1f)) { selectedDetail = "${score.item.label}：${String.format(Locale.US, "%.1f", score.score)}分\n${score.note}\n状态：${score.reviewStatus.label}" } }
                repeat(scoreColumns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        ReportSection("能力标签", Icons.Filled.LocalOffer) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                report.abilityTags.forEach { tag -> Text(tag, color = Green, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.background(Green.copy(alpha = .12f), RoundedCornerShape(14.dp)).padding(horizontal = 9.dp, vertical = 6.dp)) }
            }
        }
        ReportSection("风险提示", Icons.Filled.WarningAmber) {
            report.riskAlerts.forEach { alert -> Row(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看风险提示：$alert" }.clickable { selectedDetail = "风险提示\n$alert" }, verticalAlignment = Alignment.Top) { Icon(Icons.Filled.Circle, null, tint = if (alert == "暂无高风险提示") Green else Color.Red, modifier = Modifier.size(8.dp).padding(top = 4.dp)); Spacer(Modifier.width(7.dp)); Text(alert, color = if (alert == "暂无高风险提示") Green else Color.Red, fontSize = 16.sp) } }
        }
        ReportSection("训练建议", Icons.AutoMirrored.Filled.DirectionsRun) {
            report.trainingAdvice.forEach { advice -> Text("• $advice", color = Navy, fontSize = 16.sp, modifier = Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看训练建议：$advice" }.clickable { selectedDetail = "训练建议\n$advice" }.padding(vertical = 3.dp)) }
        }
        ReportSection("课程建议", Icons.Filled.PlayCircleFilled) {
            report.courseSuggestions.forEach { course -> CourseSuggestionRow(course) {
                if (openRecommendedCourse != null) openRecommendedCourse(course)
                else selectedDetail = "课程建议\n${course.title}\n${course.focus} · ${course.duration}"
            } }
        }
        bodyAssessment?.let { body ->
            ReportSection("家庭身体观察（家长记录）", Icons.Filled.AccessibilityNew) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(String.format(Locale.US, "BMI %.1f", body.bmi), color = Navy, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.weight(1f))
                        Text(body.level(bodyAgeMonths, studentGender).label, color = Green, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                    }
                    Text("记录日期：${body.measuredAt} · 已完成 ${body.captures.size} 项拍摄任务", color = Color.Gray, fontSize = 16.sp)
                    body.geneticHeightReference(studentGender)?.let { reference ->
                        Text("遗传靶身高参考：${String.format(Locale.US, "%.1f", reference)} cm（${body.geneticHeightFormula(studentGender)}，仅供健康管理参考）", color = Color.Gray, fontSize = 16.sp)
                    }
                    body.heightDevelopmentAssessment(bodyAgeMonths, studentGender)?.let { height ->
                        Text("当前身高发育：${height.level.label} · ${height.ageYears}岁参考中位 ${String.format(Locale.US, "%.1f", height.median)} cm", color = Color.Gray, fontSize = 16.sp)
                    }
                    val visualHint = body.captureObservationHints.toSortedMap().mapNotNull { (task, hint) -> runCatching { "${BodyCaptureTask.valueOf(task).title}：$hint" }.getOrNull() }.joinToString("\n").ifBlank { body.visualObservationHint.orEmpty() }
                    visualHint.takeIf { it.isNotBlank() }?.let { hint -> Text(hint, color = Color(0xFFFF8A24), fontSize = 16.sp) }
                    Text("该记录为家长居家观察与年龄别 BMI 筛查，不属于学校体测的 7 项能力得分，也不构成医学诊断。", color = Color.Gray, fontSize = 16.sp)
                }
            }
        }
        ReportSection("评测标准与适用范围", Icons.Filled.VerifiedUser) {
            Column(
                verticalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier.semantics {
                    contentDescription = "评测标准：${report.ruleVersion}，适用地区${report.regionPolicy.region}，政策${report.regionPolicy.povertyAreaLabel ?: "通用学生政策"}，生效日期${report.regionPolicy.effectiveDate}"
                }
            ) {
                ReportRuleRow("年级标准", report.ruleVersion)
                ReportRuleRow("适用地区", report.regionPolicy.region)
                ReportRuleRow("地区政策", report.regionPolicy.povertyAreaLabel ?: "通用学生政策")
                ReportRuleRow("评测生效日期", report.regionPolicy.effectiveDate)
                Text("报告保留本次测评采用的评测标准；场地端成绩或地区政策更新后可查看最新依据。", color = Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(top = 3.dp))
            }
        }
        Text("报告数据会在学校场地端上传成绩后显示最新结果。", color = Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(bottom = 8.dp))
    }
    selectedDetail?.let { detail -> AlertDialog(onDismissRequest = { selectedDetail = null }, title = { Text("报告详情") }, text = { Text(detail) }, confirmButton = { TextButton(onClick = { selectedDetail = null }) { Text("知道了") } }) }
}

/** Shared report waiting screen for family, teacher and principal routes. */
@Composable
fun SchoolReportPendingScreen(student: Student, nav: NavHostController) = AppScaffold(
    title = "体测报告",
    onBack = { nav.popBackStack() }
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 72.dp, start = 20.dp, end = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(Icons.Filled.PendingActions, null, tint = Blue, modifier = Modifier.size(48.dp))
        Text("报告暂未发布", color = Navy, fontWeight = FontWeight.Bold, fontSize = 19.sp)
        Text(
            "${student.name}的学校运动体测报告将在场地端完成成绩核验并发布后显示。家庭身体测评记录不影响学校 7 项体测报告。",
            color = Color.Gray,
            fontSize = 16.sp
        )
        TextButton(onClick = { nav.popBackStack() }) { Text("返回上一页") }
    }
}

@Composable
private fun ReportHero(report: DiagnosisReport, isRefreshing: Boolean, onRefresh: () -> Unit) = Surface(color = Color.Transparent, shape = RoundedCornerShape(19.dp)) {
    Column(
        Modifier.fillMaxWidth().background(Brush.linearGradient(listOf(Blue, Color(0xFF10B7A5))), RoundedCornerShape(19.dp)).padding(17.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(report.student.name, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 23.sp)
                Text("${report.student.grade} · ${report.student.className}", color = Color.White.copy(alpha = .88f), fontSize = 16.sp)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(if (report.isComplete) String.format(Locale.US, "%.1f / 35", report.totalScore) else "待完成 ${report.scoredItemCount}/7 项", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 21.sp)
                TextButton(onClick = onRefresh, enabled = !isRefreshing, contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)) {
                    if (isRefreshing) CircularProgressIndicator(Modifier.size(11.dp), color = Color.White, strokeWidth = 1.5.dp)
                    else Icon(Icons.Filled.Refresh, null, tint = Color.White, modifier = Modifier.size(12.dp))
                    Spacer(Modifier.width(3.dp))
                    Text(if (isRefreshing) "同步中" else "同步报告", color = Color.White, fontSize = 16.sp)
                }
            }
        }
        HorizontalDivider(color = Color.White.copy(alpha = .28f))
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.LocationOn, null, tint = Color.White.copy(alpha = .9f), modifier = Modifier.size(14.dp)); Spacer(Modifier.width(4.dp)); Text(report.student.region, color = Color.White.copy(alpha = .9f), fontSize = 16.sp) }
        Text("测评日期：${report.date} · 评测标准已应用", color = Color.White.copy(alpha = .82f), fontSize = 16.sp)
    }
}

@Composable
private fun ReportScoreCard(score: ScoreResult, modifier: Modifier, onClick: () -> Unit) = Surface(onClick = onClick, modifier = modifier.semantics { contentDescription = "${score.item.label} ${score.score}分，满分5分，状态${score.reviewStatus.label}" }, color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
    Column(Modifier.padding(11.dp)) { Text(score.item.label, color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 16.sp); Text(String.format(Locale.US, "%.1f", score.score), color = Blue, fontWeight = FontWeight.Bold, fontSize = 21.sp, modifier = Modifier.padding(top = 5.dp)); Text("满分5分 · ${score.note}", color = Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(top = 2.dp)); Text("状态 · ${score.reviewStatus.label}", color = if (score.reviewStatus.name == "Passed") Green else Color(0xFFFF8B1F), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 5.dp)) }
}

@Composable
private fun ReportSection(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, body: @Composable ColumnScope.() -> Unit) = Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(15.dp), shadowElevation = 1.dp) {
    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = Blue, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(7.dp)); Text(title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp) }; body() }
}

@Composable
private fun ReportRuleRow(label: String, value: String) = Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
    Text(label, color = Color.Gray, fontSize = 16.sp, modifier = Modifier.width(78.dp))
    Text(value, color = Navy, fontSize = 16.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
}

@Composable
private fun CourseSuggestionRow(course: CourseSuggestion, onClick: () -> Unit) = Row(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "打开课程建议：${course.title}" }.clickable(onClick = onClick).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(Icons.Filled.PlayCircleFilled, null, tint = Color(0xFF10B7A5), modifier = Modifier.size(27.dp)); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text(course.title, color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 16.sp); Text("${course.focus} · ${course.duration}", color = Color.Gray, fontSize = 16.sp) }; Text(if (course.isPublicBenefit) "公益" else "推荐", color = Blue, fontSize = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.background(Sky, RoundedCornerShape(10.dp)).padding(horizontal = 7.dp, vertical = 4.dp))
}
