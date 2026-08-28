package com.xiangshang.youth.feature.parent

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.model.*
import com.xiangshang.youth.core.util.FrontendEvent
import com.xiangshang.youth.core.util.FrontendTelemetry

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GrowthInsightDialog(state: AppUiState, officialSchoolScore: Double?, dismiss: () -> Unit, openCourses: () -> Unit) {
    val child = state.selectedChild ?: return
    var period by remember { mutableStateOf(GrowthReportPeriod.Week) }
    val body = state.local.bodyAssessments[child.id]
    var didLogOpen by remember { mutableStateOf(false) }
    val insight = GrowthInsight.make(
        period = period,
        checkInDates = state.local.checkedInDates,
        planDates = body?.planDays.orEmpty(),
        assessmentCount = state.local.completedAssessments.count { it.startsWith(child.id) },
        bodyAttention = body?.level(child.bodyAssessmentAgeMonths, child.gender),
        // A growth plan may react only to an official school result. An absent
        // report is unknown data, not a score of zero.
        totalScore = officialSchoolScore
    )
    val reduceMotion = LocalReduceMotion.current
    val progress by animateFloatAsState(insight.consistencyPercent / 100f, tween(if (reduceMotion) 0 else 700), label = "growth-consistency")
    LaunchedEffect(period) {
        FrontendTelemetry.record(if (didLogOpen) FrontendEvent.GrowthReportPeriodChanged else FrontendEvent.GrowthReportOpened, period.label)
        didLogOpen = true
    }

    Dialog(onDismissRequest = dismiss) {
        Surface(
            modifier = Modifier.fillMaxWidth().widthIn(max = 720.dp).fillMaxHeight(.92f),
            color = Canvas,
            shape = RoundedCornerShape(24.dp)
        ) {
            Column {
                Row(Modifier.fillMaxWidth().background(Color.White).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("成长报告", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.weight(1f))
                    IconButton(onClick = dismiss) { Icon(Icons.Filled.Close, "关闭成长报告") }
                }
                Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        GrowthReportPeriod.values().forEachIndexed { index, item ->
                            SegmentedButton(selected = period == item, onClick = { period = item }, shape = SegmentedButtonDefaults.itemShape(index, GrowthReportPeriod.values().size)) { Text(item.label) }
                        }
                    }
                    Surface(color = Color.White, shape = RoundedCornerShape(16.dp)) {
                        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(104.dp)) {
                                CircularProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxSize(), color = Blue, trackColor = Sky, strokeWidth = 10.dp)
                                Column(horizontalAlignment = Alignment.CenterHorizontally) { Text("${insight.consistencyPercent}%", color = Navy, fontWeight = FontWeight.Bold, fontSize = 20.sp); Text("完成率", color = Color.Gray, fontSize = 16.sp) }
                            }
                            Spacer(Modifier.width(16.dp))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                                Text("${child.name}的${period.label}成长报告", color = Navy, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                Text("来自运动打卡、家庭计划和已完成测评，不使用虚构训练数据。", color = Color.Gray, fontSize = 16.sp)
                                Text("活跃 ${insight.activeDays} / ${insight.targetActiveDays} 天", color = Blue, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                            }
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        GrowthMetric("运动活跃", "${insight.activeDays} 天", Icons.AutoMirrored.Filled.DirectionsRun, Blue, Modifier.weight(1f))
                        GrowthMetric("计划完成", "${insight.planDays} 天", Icons.Filled.Verified, Green, Modifier.weight(1f))
                        GrowthMetric("健康测评", "${insight.assessmentCount} 项", Icons.Filled.Favorite, Color(0xFFFF6D9B), Modifier.weight(1f))
                    }
                    Surface(color = Color.White, shape = RoundedCornerShape(16.dp)) {
                        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                            Text("计划已更新", color = Green, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                            Text(insight.planTitle, color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                            Text(insight.planReason, color = Color.Gray, fontSize = 16.sp)
                            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                                PlanInfoPill("每周 ${insight.sessionsPerWeek} 次", Icons.Filled.CalendarMonth)
                                PlanInfoPill("每次 ${insight.minutesPerSession} 分钟", Icons.Filled.Schedule)
                            }
                            HorizontalDivider()
                            insight.actions.forEachIndexed { index, action ->
                                Row(verticalAlignment = Alignment.Top) {
                                    Text("${index + 1}", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.size(20.dp).clip(CircleShape).background(Blue).padding(top = 3.dp))
                                    Spacer(Modifier.width(8.dp)); Text(action, color = Navy, fontSize = 16.sp)
                                }
                            }
                        }
                    }
                    Button(onClick = { FrontendTelemetry.record(FrontendEvent.AdaptivePlanOpenedCourses, period.label); dismiss(); openCourses() }, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Filled.PlayArrow, null); Spacer(Modifier.width(5.dp)); Text("开始今日训练") }
                    Text("计划调整属于健康管理建议，不替代医疗诊断；出现疼痛、麻木、无力或持续异常时请停止训练并咨询专业人员。", color = Color.Gray, fontSize = 16.sp)
                }
            }
        }
    }
}

/** Informational only: avoid exposing a chip affordance for values that the
 * adaptive plan owns and cannot be edited in this release. */
@Composable
private fun PlanInfoPill(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Surface(color = Sky, shape = RoundedCornerShape(20.dp)) {
        Row(Modifier.padding(horizontal = 9.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = Blue, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(5.dp))
            Text(label, color = Blue, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun GrowthMetric(title: String, value: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, modifier: Modifier) {
    Surface(modifier, color = Color.White, shape = RoundedCornerShape(13.dp)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(icon, null, tint = color, modifier = Modifier.size(19.dp)); Text(value, color = Navy, fontWeight = FontWeight.Bold, fontSize = 16.sp); Text(title, color = Color.Gray, fontSize = 16.sp)
        }
    }
}
