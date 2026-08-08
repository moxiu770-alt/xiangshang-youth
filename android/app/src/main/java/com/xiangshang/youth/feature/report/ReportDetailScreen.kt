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
import com.xiangshang.youth.shared.component.AppScaffold
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
    nav: NavHostController? = null
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
        report.scores.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                row.forEach { score -> ReportScoreCard(score, Modifier.weight(1f)) { selectedDetail = "${score.item.label}：${String.format(Locale.US, "%.1f", score.score)}分\n${score.note}\n置信度 ${(score.confidence * 100).toInt()}%" } }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
        ReportSection("能力标签", Icons.Filled.LocalOffer) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                report.abilityTags.forEach { tag -> Text(tag, color = Green, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.background(Green.copy(alpha = .12f), RoundedCornerShape(14.dp)).padding(horizontal = 9.dp, vertical = 6.dp)) }
            }
        }
        ReportSection("风险提示", Icons.Filled.WarningAmber) {
            report.riskAlerts.forEach { alert -> Row(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看风险提示：$alert" }.clickable { selectedDetail = "风险提示\n$alert" }, verticalAlignment = Alignment.Top) { Icon(Icons.Filled.Circle, null, tint = if (alert == "暂无高风险提示") Green else Color.Red, modifier = Modifier.size(8.dp).padding(top = 4.dp)); Spacer(Modifier.width(7.dp)); Text(alert, color = if (alert == "暂无高风险提示") Green else Color.Red, fontSize = 12.sp) } }
        }
        ReportSection("训练建议", Icons.AutoMirrored.Filled.DirectionsRun) {
            report.trainingAdvice.forEach { advice -> Text("• $advice", color = Navy, fontSize = 12.sp, modifier = Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "查看训练建议：$advice" }.clickable { selectedDetail = "训练建议\n$advice" }.padding(vertical = 3.dp)) }
        }
        ReportSection("课程建议", Icons.Filled.PlayCircleFilled) {
            report.courseSuggestions.forEach { course -> CourseSuggestionRow(course) { selectedDetail = "课程建议\n${course.title}\n${course.focus} · ${course.duration}" } }
        }
        ReportSection("规则依据与适用范围", Icons.Filled.VerifiedUser) {
            Column(
                verticalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier.semantics {
                    contentDescription = "规则依据：${report.ruleVersion}，适用地区${report.regionPolicy.region}，政策${report.regionPolicy.povertyAreaLabel ?: "通用学生政策"}，生效日期${report.regionPolicy.effectiveDate}"
                }
            ) {
                ReportRuleRow("年级标准", report.ruleVersion)
                ReportRuleRow("适用地区", report.regionPolicy.region)
                ReportRuleRow("地区政策", report.regionPolicy.povertyAreaLabel ?: "通用学生政策")
                ReportRuleRow("规则生效日期", report.regionPolicy.effectiveDate)
                Text("报告保留本次测评使用的规则版本；场地端成绩或地区政策更新后可同步刷新。", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.padding(top = 3.dp))
            }
        }
        Text("报告数据会在学校场地端上传成绩后自动刷新。", color = Color.Gray, fontSize = 9.sp, modifier = Modifier.padding(bottom = 8.dp))
    }
    selectedDetail?.let { detail -> AlertDialog(onDismissRequest = { selectedDetail = null }, title = { Text("报告详情") }, text = { Text(detail) }, confirmButton = { TextButton(onClick = { selectedDetail = null }) { Text("知道了") } }) }
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
                Text("${report.student.grade} · ${report.student.className}", color = Color.White.copy(alpha = .88f), fontSize = 11.sp)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(String.format(Locale.US, "%.1f / 35", report.totalScore), color = Color.White, fontWeight = FontWeight.Bold, fontSize = 21.sp)
                TextButton(onClick = onRefresh, enabled = !isRefreshing, contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)) {
                    if (isRefreshing) CircularProgressIndicator(Modifier.size(11.dp), color = Color.White, strokeWidth = 1.5.dp)
                    else Icon(Icons.Filled.Refresh, null, tint = Color.White, modifier = Modifier.size(12.dp))
                    Spacer(Modifier.width(3.dp))
                    Text(if (isRefreshing) "同步中" else "同步报告", color = Color.White, fontSize = 9.sp)
                }
            }
        }
        HorizontalDivider(color = Color.White.copy(alpha = .28f))
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.LocationOn, null, tint = Color.White.copy(alpha = .9f), modifier = Modifier.size(14.dp)); Spacer(Modifier.width(4.dp)); Text(report.student.region, color = Color.White.copy(alpha = .9f), fontSize = 10.sp) }
        if (report.student.isPovertyArea) Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Favorite, null, tint = Color.White, modifier = Modifier.size(14.dp)); Spacer(Modifier.width(4.dp)); Text("贫困地区专项帮扶标签", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.SemiBold) }
        Text("测评日期：${report.date} · 规则：${report.ruleVersion}", color = Color.White.copy(alpha = .82f), fontSize = 9.sp)
    }
}

@Composable
private fun ReportScoreCard(score: ScoreResult, modifier: Modifier, onClick: () -> Unit) = Surface(onClick = onClick, modifier = modifier.semantics { contentDescription = "${score.item.label} ${score.score}分，满分5分，置信度${(score.confidence * 100).toInt()}%，${score.reviewStatus.label}" }, color = Color.White, shape = RoundedCornerShape(12.dp), shadowElevation = 1.dp) {
    Column(Modifier.padding(11.dp)) { Text(score.item.label, color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 11.sp); Text(String.format(Locale.US, "%.1f", score.score), color = Blue, fontWeight = FontWeight.Bold, fontSize = 21.sp, modifier = Modifier.padding(top = 5.dp)); Text("满分5分 · ${score.note}", color = Color.Gray, fontSize = 8.sp, modifier = Modifier.padding(top = 2.dp)); Text("置信度 ${(score.confidence * 100).toInt()}% · ${score.reviewStatus.label}", color = if (score.reviewStatus.name == "Passed") Green else Color(0xFFFF8B1F), fontSize = 8.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 5.dp)) }
}

@Composable
private fun ReportSection(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, body: @Composable ColumnScope.() -> Unit) = Surface(Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(15.dp), shadowElevation = 1.dp) {
    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = Blue, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(7.dp)); Text(title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 14.sp) }; body() }
}

@Composable
private fun ReportRuleRow(label: String, value: String) = Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
    Text(label, color = Color.Gray, fontSize = 10.sp, modifier = Modifier.width(78.dp))
    Text(value, color = Navy, fontSize = 10.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
}

@Composable
private fun CourseSuggestionRow(course: CourseSuggestion, onClick: () -> Unit) = Row(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "打开课程建议：${course.title}" }.clickable(onClick = onClick).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(Icons.Filled.PlayCircleFilled, null, tint = Color(0xFF10B7A5), modifier = Modifier.size(27.dp)); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text(course.title, color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 12.sp); Text("${course.focus} · ${course.duration}", color = Color.Gray, fontSize = 9.sp) }; Text(if (course.isPublicBenefit) "公益" else "推荐", color = Blue, fontSize = 9.sp, fontWeight = FontWeight.Bold, modifier = Modifier.background(Sky, RoundedCornerShape(10.dp)).padding(horizontal = 7.dp, vertical = 4.dp))
}
