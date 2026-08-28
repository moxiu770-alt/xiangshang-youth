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

internal fun initialBodyAssessmentStage(
    draft: BodyAssessmentDraft?,
    hasPreviousRecord: Boolean,
    consentIsCurrent: Boolean
): Int {
    val restored = restoredBodyAssessmentStage(draft).coerceIn(0, 8)
    return when {
        draft == null && hasPreviousRecord -> 7
        draft != null && restored >= 2 && !consentIsCurrent -> 1
        else -> restored
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
fun BodyAssessmentScreen(state: AppUiState, nav: NavHostController, save: (Student, BodyAssessmentRecord) -> Unit, saveDraft: (Student, BodyAssessmentDraft) -> Unit, toggleDay: (Student, String) -> Unit, saveFollowAlongSession: (FollowAlongSessionRecord) -> Unit = {}, updateVoiceGuidance: (Boolean) -> Unit = {}, recordHealthConsent: (String) -> Unit = {}, refreshLatest: (Student) -> Unit = {}) {
    val child = state.selectedChild
    if (child == null) { Scaffold(containerColor = Canvas) { Box(Modifier.padding(it).fillMaxSize(), contentAlignment = Alignment.Center) { Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("请先绑定孩子") } } }; return }
    val persistedDraft = state.local.bodyAssessmentDrafts[child.id]
    val previous = state.local.bodyAssessments[child.id]
    LaunchedEffect(child.id, previous?.measuredAt) {
        if (persistedDraft == null && previous != null) refreshLatest(child)
    }
    val currentConsent = state.local.healthConsents[child.id]
    val consentIsCurrent = currentConsent != null && currentConsent.revokedAt == null &&
        currentConsent.privacyPolicyVersion == LegalPolicy.PRIVACY_POLICY_VERSION &&
        currentConsent.cameraConsentVersion == LegalPolicy.CAMERA_CONSENT_VERSION &&
        currentConsent.algorithmNoticeVersion == LegalPolicy.ALGORITHM_NOTICE_VERSION
    // A completed record is a long-term family health asset. Re-entering this
    // page should show the saved result first, rather than forcing a parent
    // through consent and all eight capture segments again. An in-progress draft still
    // wins so unfinished work resumes at the exact step where it was left.
    var stage by rememberSaveable {
        mutableIntStateOf(initialBodyAssessmentStage(persistedDraft, previous != null, consentIsCurrent))
    }
    var height by rememberSaveable { mutableDoubleStateOf(persistedDraft?.heightCm ?: previous?.heightCm ?: 0.0) }
    var weight by rememberSaveable { mutableDoubleStateOf(persistedDraft?.weightKg ?: previous?.weightKg ?: 0.0) }
    var fatherHeight by rememberSaveable { mutableDoubleStateOf(persistedDraft?.fatherHeightCm ?: previous?.fatherHeightCm ?: 0.0) }
    var motherHeight by rememberSaveable { mutableDoubleStateOf(persistedDraft?.motherHeightCm ?: previous?.motherHeightCm ?: 0.0) }
    var captureNames by rememberSaveable { mutableStateOf((persistedDraft?.captures ?: previous?.captures ?: emptySet()).map { it.name }) }
    val captures = captureNames.mapNotNull { runCatching { BodyCaptureTask.valueOf(it) }.getOrNull() }.toSet()
    var asymmetric by rememberSaveable { mutableStateOf(persistedDraft?.asymmetric ?: previous?.asymmetric ?: false) }
    var gait by rememberSaveable { mutableStateOf(persistedDraft?.gaitConcern ?: previous?.gaitConcern ?: false) }
    var adultReady by rememberSaveable { mutableStateOf(if (persistedDraft != null && !consentIsCurrent) false else persistedDraft?.guardianReady ?: false) }
    var spaceReady by rememberSaveable { mutableStateOf(persistedDraft?.environmentReady ?: false) }
    var consentAcknowledged by rememberSaveable { mutableStateOf(if (persistedDraft != null && !consentIsCurrent) false else persistedDraft?.consentAcknowledged ?: false) }
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
    val previousStanding = previous?.postureReport?.snapshots?.get(BodyCaptureTask.StandingBack)
    val previousForward = previous?.postureReport?.snapshots?.get(BodyCaptureTask.ForwardBend)
    val previousGait = previous?.postureReport?.snapshots?.get(BodyCaptureTask.GaitVideo)
    val previousSeated = previous?.postureReport?.snapshots?.get(BodyCaptureTask.Seated)
    var standingShoulderText by rememberSaveable { mutableStateOf(persistedDraft?.standingShoulderDifferenceCm?.let { "%.1f".format(Locale.US, it) } ?: previousStanding?.shoulderHeightDifferenceCm?.let { "%.1f".format(Locale.US, it) }.orEmpty()) }
    var standingPelvisText by rememberSaveable { mutableStateOf(persistedDraft?.standingPelvisDifferenceCm?.let { "%.1f".format(Locale.US, it) } ?: previousStanding?.pelvicHeightDifferenceCm?.let { "%.1f".format(Locale.US, it) }.orEmpty()) }
    var standingHeadTiltText by rememberSaveable { mutableStateOf(persistedDraft?.standingHeadTiltDegrees?.let { "%.1f".format(Locale.US, it) } ?: previousStanding?.headTiltDegrees?.let { "%.1f".format(Locale.US, it) }.orEmpty()) }
    var adamsObservedResult by rememberSaveable { mutableStateOf(persistedDraft?.adamsObservedResult ?: previousForward?.adamsObservedResult ?: "unrecorded") }
    var adamsProminenceSide by rememberSaveable { mutableStateOf(persistedDraft?.adamsProminenceSide ?: previousForward?.adamsProminenceSide ?: "无") }
    var gaitObservedResult by rememberSaveable { mutableStateOf(persistedDraft?.gaitObservedAbnormal?.let { if (it) "abnormal" else "normal" } ?: previousGait?.gaitObservedAbnormal?.let { if (it) "abnormal" else "normal" } ?: "unrecorded") }
    var gaitObservationNote by rememberSaveable { mutableStateOf(persistedDraft?.gaitObservationNote ?: previousGait?.gaitObservationNote.orEmpty()) }
    var seatedMidlineText by rememberSaveable { mutableStateOf(persistedDraft?.seatedMidlineDifferenceCm?.let { "%.1f".format(Locale.US, it) } ?: previousSeated?.spinalMidlineDeviationCm?.let { "%.1f".format(Locale.US, it) }.orEmpty()) }
    var seatedShoulderText by rememberSaveable { mutableStateOf(persistedDraft?.seatedShoulderDifferenceCm?.let { "%.1f".format(Locale.US, it) } ?: previousSeated?.shoulderHeightDifferenceCm?.let { "%.1f".format(Locale.US, it) }.orEmpty()) }
    var seatedKyphosisResult by rememberSaveable { mutableStateOf(persistedDraft?.seatedThoracicKyphosisObserved?.let { if (it) "abnormal" else "normal" } ?: previousSeated?.seatedThoracicKyphosisObserved?.let { if (it) "abnormal" else "normal" } ?: "unrecorded") }
    var thoracicAtrText by rememberSaveable { mutableStateOf(persistedDraft?.thoracicAtrDegrees?.let { "%.1f".format(Locale.US, it) } ?: previous?.postureReport?.snapshots?.get(BodyCaptureTask.ForwardBend)?.thoracicAtrDegrees?.let { "%.1f".format(Locale.US, it) }.orEmpty()) }
    var lumbarAtrText by rememberSaveable { mutableStateOf(persistedDraft?.lumbarAtrDegrees?.let { "%.1f".format(Locale.US, it) } ?: previous?.postureReport?.snapshots?.get(BodyCaptureTask.ForwardBend)?.lumbarAtrDegrees?.let { "%.1f".format(Locale.US, it) }.orEmpty()) }
    var thoracicAtrSide by rememberSaveable { mutableStateOf(persistedDraft?.thoracicAtrSide ?: previous?.postureReport?.snapshots?.get(BodyCaptureTask.ForwardBend)?.thoracicAtrSide ?: "无") }
    var lumbarAtrSide by rememberSaveable { mutableStateOf(persistedDraft?.lumbarAtrSide ?: previous?.postureReport?.snapshots?.get(BodyCaptureTask.ForwardBend)?.lumbarAtrSide ?: "无") }
    var atrRetestEnabled by rememberSaveable { mutableStateOf(persistedDraft?.atrRetestEnabled ?: (previous?.postureReport?.snapshots?.get(BodyCaptureTask.ForwardBend)?.thoracicAtrSecondDegrees != null || previous?.postureReport?.snapshots?.get(BodyCaptureTask.ForwardBend)?.lumbarAtrSecondDegrees != null)) }
    var thoracicAtrRepeatText by rememberSaveable { mutableStateOf(persistedDraft?.thoracicAtrRepeatDegrees?.let { "%.1f".format(Locale.US, it) } ?: previous?.postureReport?.snapshots?.get(BodyCaptureTask.ForwardBend)?.thoracicAtrSecondDegrees?.let { "%.1f".format(Locale.US, it) }.orEmpty()) }
    var lumbarAtrRepeatText by rememberSaveable { mutableStateOf(persistedDraft?.lumbarAtrRepeatDegrees?.let { "%.1f".format(Locale.US, it) } ?: previous?.postureReport?.snapshots?.get(BodyCaptureTask.ForwardBend)?.lumbarAtrSecondDegrees?.let { "%.1f".format(Locale.US, it) }.orEmpty()) }
    var seatedForwardBendAtrText by rememberSaveable { mutableStateOf(persistedDraft?.seatedForwardBendAtrDegrees?.let { "%.1f".format(Locale.US, it) } ?: previous?.postureReport?.snapshots?.get(BodyCaptureTask.ForwardBend)?.seatedForwardBendAtrDegrees?.let { "%.1f".format(Locale.US, it) }.orEmpty()) }
    val previousOtwdText = previous?.postureReport?.snapshots?.get(BodyCaptureTask.Seated)?.occiputWallDistanceCm?.let { "%.1f".format(Locale.US, it) }.orEmpty()
    var occiputWallDistanceText by rememberSaveable { mutableStateOf(persistedDraft?.occiputWallDistanceFirstCm?.let { "%.1f".format(Locale.US, it) } ?: persistedDraft?.occiputWallDistanceCm?.let { "%.1f".format(Locale.US, it) } ?: previousOtwdText) }
    var occiputWallDistanceRepeatText by rememberSaveable { mutableStateOf(persistedDraft?.occiputWallDistanceSecondCm?.let { "%.1f".format(Locale.US, it) } ?: persistedDraft?.occiputWallDistanceCm?.let { "%.1f".format(Locale.US, it) } ?: previousOtwdText) }
    val hasValidCoreMeasurements = height in 90.0..190.0 && weight in 15.0..90.0
    val spineStandardApplicable = SpineScreeningStandard.isApplicable(child.bodyAssessmentAgeMonths)
    val thoracicAtrFirst = standardMeasurement(thoracicAtrText, 0.0..30.0)
    val lumbarAtrFirst = standardMeasurement(lumbarAtrText, 0.0..30.0)
    val thoracicAtrRepeat = standardMeasurement(thoracicAtrRepeatText, 0.0..30.0)
    val lumbarAtrRepeat = standardMeasurement(lumbarAtrRepeatText, 0.0..30.0)
    val seatedForwardBendAtr = standardMeasurement(seatedForwardBendAtrText, 0.0..30.0)
    val thoracicAtr = averageAtr(thoracicAtrFirst, thoracicAtrRepeat, atrRetestEnabled)
    val lumbarAtr = averageAtr(lumbarAtrFirst, lumbarAtrRepeat, atrRetestEnabled)
    val occiputWallDistanceFirst = standardMeasurement(occiputWallDistanceText, 0.0..15.0)
    val occiputWallDistanceSecond = standardMeasurement(occiputWallDistanceRepeatText, 0.0..15.0)
    val occiputWallDistance = SpineScreeningStandard.maximumOcciputWallDistance(occiputWallDistanceFirst, occiputWallDistanceSecond)
    val atrRecorded = thoracicAtr != null && lumbarAtr != null && (thoracicAtr == 0.0 || thoracicAtrSide != "无") && (lumbarAtr == 0.0 || lumbarAtrSide != "无")
    val otwdRecorded = occiputWallDistance != null
    val standingShoulder = standardMeasurement(standingShoulderText, 0.0..10.0)
    val standingPelvis = standardMeasurement(standingPelvisText, 0.0..10.0)
    val standingHeadTilt = standardMeasurement(standingHeadTiltText, 0.0..30.0)
    val seatedMidline = standardMeasurement(seatedMidlineText, 0.0..10.0)
    val seatedShoulder = standardMeasurement(seatedShoulderText, 0.0..10.0)
    val standingMeasured = standingShoulder != null && standingPelvis != null && standingHeadTilt != null
    val adamsObserved = adamsObservedResult != "unrecorded" && (adamsObservedResult == "negative" || adamsProminenceSide != "无")
    val gaitObserved = gaitObservedResult != "unrecorded"
    val seatedMeasured = seatedMidline != null && seatedShoulder != null && seatedKyphosisResult != "unrecorded"
    fun snapshotsForReport(): Map<BodyCaptureTask, PostureMetricSnapshot> {
        val merged = postureSnapshots.toMutableMap()
        merged[BodyCaptureTask.StandingBack]?.let { standing ->
            if (standingMeasured) merged[BodyCaptureTask.StandingBack] = standing.copy(shoulderHeightDifferenceCm = standingShoulder, pelvicHeightDifferenceCm = standingPelvis, headTiltDegrees = standingHeadTilt)
        }
        merged[BodyCaptureTask.ForwardBend]?.let { forward ->
            if (thoracicAtr != null && lumbarAtr != null) merged[BodyCaptureTask.ForwardBend] = forward.copy(
                instrumentAtrDegrees = maxOf(thoracicAtr, lumbarAtr), thoracicAtrDegrees = thoracicAtr, lumbarAtrDegrees = lumbarAtr,
                thoracicAtrSide = thoracicAtrSide.takeIf { thoracicAtr > 0 }, lumbarAtrSide = lumbarAtrSide.takeIf { lumbarAtr > 0 },
                thoracicAtrFirstDegrees = thoracicAtrFirst, thoracicAtrSecondDegrees = thoracicAtrRepeat.takeIf { atrRetestEnabled },
                lumbarAtrFirstDegrees = lumbarAtrFirst, lumbarAtrSecondDegrees = lumbarAtrRepeat.takeIf { atrRetestEnabled },
                seatedForwardBendAtrDegrees = seatedForwardBendAtr,
                adamsObservedResult = adamsObservedResult.takeIf { it != "unrecorded" },
                adamsProminenceSide = adamsProminenceSide.takeIf { adamsObservedResult != "negative" && it != "无" }
            )
        }
        merged[BodyCaptureTask.GaitVideo]?.let { gaitSnapshot -> if (gaitObserved) merged[BodyCaptureTask.GaitVideo] = gaitSnapshot.copy(gaitObservedAbnormal = gaitObservedResult == "abnormal", gaitObservationNote = gaitObservationNote.trim().takeIf(String::isNotEmpty)) }
        merged[BodyCaptureTask.Seated]?.let { seated -> if (occiputWallDistance != null && seatedMeasured) merged[BodyCaptureTask.Seated] = seated.copy(occiputWallDistanceCm = occiputWallDistance, spinalMidlineDeviationCm = seatedMidline, shoulderHeightDifferenceCm = seatedShoulder, seatedThoracicKyphosisObserved = seatedKyphosisResult == "abnormal") }
        return merged
    }
    val assessmentSteps = listOf("使用说明", "监护人授权", "孩子身体信息", "身高体重和BMI", "拍摄环境检查", "摄像头测评", "质量确认", "结果报告", "训练计划")
    val displayStep = stage.coerceIn(0, assessmentSteps.lastIndex)
    fun record(): BodyAssessmentRecord { val now = BusinessClock.day(); val ageAtMeasurement = child.bodyAssessmentAgeMonths; val mergedSnapshots = snapshotsForReport(); val draft = BodyAssessmentRecord(height, weight, now, captures, asymmetric, gait, now, visualObservationHint = visualHints.toSortedMap().values.joinToString("\n"), fatherHeightCm = fatherHeight, motherHeightCm = motherHeight, captureObservationHints = visualHints, postureReport = mergedSnapshots.takeIf { it.isNotEmpty() }?.let { PostureAssessmentReport.make(it, now, ageAtMeasurement) }, ageMonthsAtMeasurement = ageAtMeasurement); val days = when (draft.level(ageAtMeasurement, child.gender)) { BodyAttentionLevel.Red -> 7; BodyAttentionLevel.Yellow -> 30; BodyAttentionLevel.Pending -> 3; BodyAttentionLevel.Green -> 90; BodyAttentionLevel.Unavailable -> 30 }; val follow = Calendar.getInstance(BusinessClock.timeZone).apply { add(Calendar.DAY_OF_YEAR, days) }; return draft.copy(nextFollowUp = BusinessClock.day(follow.time), planDays = previous?.planDays.orEmpty()) }
    LaunchedEffect(stage, height, weight, fatherHeight, motherHeight, captureNames, asymmetric, gait, visualHints, postureSnapshots, standingShoulderText, standingPelvisText, standingHeadTiltText, adamsObservedResult, adamsProminenceSide, gaitObservedResult, gaitObservationNote, seatedMidlineText, seatedShoulderText, seatedKyphosisResult, thoracicAtrText, lumbarAtrText, thoracicAtrSide, lumbarAtrSide, atrRetestEnabled, thoracicAtrRepeatText, lumbarAtrRepeatText, seatedForwardBendAtrText, occiputWallDistanceText, occiputWallDistanceRepeatText) {
        if (stage <= 6) saveDraft(child, BodyAssessmentDraft(stage = stage, guardianReady = adultReady, consentAcknowledged = consentAcknowledged, environmentReady = spaceReady, heightCm = height, weightKg = weight, captures = captures, asymmetric = asymmetric, gaitConcern = gait, visualObservationHint = visualHints.toSortedMap().values.joinToString("\n"), fatherHeightCm = fatherHeight, motherHeightCm = motherHeight, captureObservationHints = visualHints, postureSnapshots = postureSnapshots, standingShoulderDifferenceCm = standingShoulder, standingPelvisDifferenceCm = standingPelvis, standingHeadTiltDegrees = standingHeadTilt, adamsObservedResult = adamsObservedResult.takeIf { it != "unrecorded" }, adamsProminenceSide = adamsProminenceSide.takeIf { it != "无" }, gaitObservedAbnormal = gaitObservedResult.takeIf { it != "unrecorded" }?.let { it == "abnormal" }, gaitObservationNote = gaitObservationNote.trim().takeIf(String::isNotEmpty), seatedMidlineDifferenceCm = seatedMidline, seatedShoulderDifferenceCm = seatedShoulder, seatedThoracicKyphosisObserved = seatedKyphosisResult.takeIf { it != "unrecorded" }?.let { it == "abnormal" }, thoracicAtrDegrees = thoracicAtrFirst, lumbarAtrDegrees = lumbarAtrFirst, thoracicAtrSide = thoracicAtrSide.takeIf { it != "无" }, lumbarAtrSide = lumbarAtrSide.takeIf { it != "无" }, atrRetestEnabled = atrRetestEnabled, thoracicAtrRepeatDegrees = thoracicAtrRepeat, lumbarAtrRepeatDegrees = lumbarAtrRepeat, seatedForwardBendAtrDegrees = seatedForwardBendAtr, occiputWallDistanceFirstCm = occiputWallDistanceFirst, occiputWallDistanceSecondCm = occiputWallDistanceSecond, occiputWallDistanceCm = occiputWallDistance))
    }
    Scaffold(containerColor = Canvas, topBar = { TopAppBar(title = { Text(assessmentSteps[displayStep], color = Navy, fontWeight = FontWeight.Bold) }, navigationIcon = { IconButton(onClick = { if (viewingSavedRecord && stage == 7) nav.popBackStack() else if (stage > 0) stage-- else nav.popBackStack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } }) }) { padding ->
        Column(Modifier.padding(padding).padding(14.dp).fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("家庭身体测评 · ${assessmentSteps[displayStep]}", color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                Text("${displayStep + 1} / ${assessmentSteps.size}", color = Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp)
            }
            LinearProgressIndicator(progress = { (displayStep + 1) / assessmentSteps.size.toFloat() }, modifier = Modifier.fillMaxWidth(), color = Color(0xFFF47A59))
            when (stage) {
                0 -> { Hero("给 ${child.name} 完成一次家庭身体测评", "记录身高、体重，并通过八段家庭相机采集观察全身姿态与动作质量。无需标定板或专业测量器械。") ; Info("App 内相机 · 人形框对齐 · 双次重复性校验"); Info(if (spineStandardApplicable) "家庭姿态观察适用年龄为 6–12 岁；孩子当前档案年龄在适用范围内。" else "当前档案年龄不在范围或出生日期缺失，请先联系学校核对档案。"); previous?.let { saved -> Surface(onClick = { viewingSavedRecord = true; stage = 7 }, modifier = Modifier.fillMaxWidth(), color = Color.White, shape = RoundedCornerShape(16.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Assessment, null, tint = Blue); Spacer(Modifier.width(10.dp)); Column(Modifier.weight(1f)) { Text("查看最近一次筛查记录", color = Navy, fontWeight = FontWeight.Bold); Text("BMI ${"%.1f".format(saved.bmi)} · ${saved.level(child.bodyAssessmentAgeMonths, child.gender).label} · 建议复测 ${saved.nextFollowUp}", color = Color.Gray, fontSize = 12.sp, maxLines = 2) }; Icon(Icons.Filled.ChevronRight, null, tint = Blue) } } }; Info("完成授权、孩子资料、BMI、环境检查、八段双次相机采集和质量确认后生成结果与训练计划。每一步按当前孩子单独保存，可随时返回。"); Button(onClick = { stage = 1 }, enabled = spineStandardApplicable, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text(if (spineStandardApplicable) "开始授权" else "请先核对孩子出生日期") } }
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
                4 -> {
                    Text("请核验家庭拍摄空间和机位。打开相机后系统会继续检查角度、距离、遮挡、光线和多人入镜。", color = Color.Gray)
                    Info(SpineScreeningStandard.mainCameraPlacement)
                    Info("准备约 3 米安全步态通道、硬质无靠背凳和防滑地面；光线均匀，背景简洁，画面内只出现一名孩子。")
                    Info("使用后置 1× 主摄并保持稳定；没有支架时可固定靠放。孩子按人形框站位，每项连续采集两次。")
                    Info("已排除近期外伤/手术、持续腰背痛、发热头晕和无法维持标准动作等暂缓情形。")
                    Info("家庭端不测量 ATR、Cobb 角或器械厘米值，也不会给出医疗诊断；这些属于学校或专业机构增强流程。")
                    ReadyRow("我已确认拍摄距离、光线、安全空间、健康暂缓条件和隐私遮挡。", spaceReady) { spaceReady = it }
                    Button(onClick = { stage = 5 }, enabled = spaceReady, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text(if (spaceReady) "进入八段相机采集" else "请完成环境核验") }
                }
                5 -> StandardScreeningCaptureStage(
                    captures = captures,
                    postureSnapshots = postureSnapshots,
                    captureFeedback = captureFeedback,
                    standingShoulderText = standingShoulderText,
                    standingPelvisText = standingPelvisText,
                    standingHeadTiltText = standingHeadTiltText,
                    adamsObservedResult = adamsObservedResult,
                    adamsProminenceSide = adamsProminenceSide,
                    gaitObservedResult = gaitObservedResult,
                    gaitObservationNote = gaitObservationNote,
                    seatedMidlineText = seatedMidlineText,
                    seatedShoulderText = seatedShoulderText,
                    seatedKyphosisResult = seatedKyphosisResult,
                    thoracicAtrText = thoracicAtrText,
                    lumbarAtrText = lumbarAtrText,
                    thoracicAtrSide = thoracicAtrSide,
                    lumbarAtrSide = lumbarAtrSide,
                    atrRetestEnabled = atrRetestEnabled,
                    thoracicAtrRepeatText = thoracicAtrRepeatText,
                    lumbarAtrRepeatText = lumbarAtrRepeatText,
                    seatedForwardBendAtrText = seatedForwardBendAtrText,
                    occiputWallDistanceText = occiputWallDistanceText,
                    occiputWallDistanceRepeatText = occiputWallDistanceRepeatText,
                    onStandingShoulderChanged = { standingShoulderText = it },
                    onStandingPelvisChanged = { standingPelvisText = it },
                    onStandingHeadTiltChanged = { standingHeadTiltText = it },
                    onAdamsResultChanged = { adamsObservedResult = it; if (it == "negative") adamsProminenceSide = "无" },
                    onAdamsSideChanged = { adamsProminenceSide = it },
                    onGaitResultChanged = { gaitObservedResult = it },
                    onGaitNoteChanged = { gaitObservationNote = it },
                    onSeatedMidlineChanged = { seatedMidlineText = it },
                    onSeatedShoulderChanged = { seatedShoulderText = it },
                    onSeatedKyphosisChanged = { seatedKyphosisResult = it },
                    onThoracicAtrChanged = { thoracicAtrText = it },
                    onLumbarAtrChanged = { lumbarAtrText = it },
                    onThoracicSideChanged = { thoracicAtrSide = it },
                    onLumbarSideChanged = { lumbarAtrSide = it },
                    onAtrRetestChanged = { atrRetestEnabled = it },
                    onThoracicAtrRepeatChanged = { thoracicAtrRepeatText = it },
                    onLumbarAtrRepeatChanged = { lumbarAtrRepeatText = it },
                    onSeatedForwardBendAtrChanged = { seatedForwardBendAtrText = it },
                    onOcciputWallDistanceChanged = { occiputWallDistanceText = it },
                    onOcciputWallDistanceRepeatChanged = { occiputWallDistanceRepeatText = it },
                    onOpenCamera = { activeCaptureTask = it },
                    onContinue = { stage = 6 }
                )
                6 -> { Text("八段相机采集已完成。请核对双次采集质量和孩子近期身体感受。", color = Color.Gray); visualHints.toSortedMap().forEach { (task, hint) -> Info("${runCatching { BodyCaptureTask.valueOf(task).title }.getOrDefault("拍摄记录任务")}：$hint") }; ToggleRow("孩子近期有肩背、腰背或坐姿疼痛/不适", asymmetric) { asymmetric = it }; ToggleRow("孩子近期有行走困难、跛行或活动受限", gait) { gait = it }; Button(onClick = { save(child, record()); stage = 7 }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF47A59))) { Text("查看家庭观察结果") } }
                7 -> {
                    val r = state.local.bodyAssessments[child.id] ?: record()
                    val level = r.level(child.bodyAssessmentAgeMonths, child.gender)
                    val history = state.local.bodyAssessmentHistory[child.id].orEmpty()
                    val summaryLabel = if (r.postureReport?.canPublishClassification == false) "姿态算法验证中" else level.label
                    Hero("${child.name} 的身体测评结果", "BMI ${"%.1f".format(r.bmi)} · $summaryLabel · 下次建议复测 ${r.nextFollowUp}")
                    if (state.repositoryAcknowledged) state.local.bodyAssessmentSyncStates[child.id]?.let { syncStatus ->
                        Info(when (syncStatus) {
                            com.xiangshang.youth.core.service.LocalSubmissionStatus.PendingSync -> "测评结果已保存，联网后自动同步。"
                            com.xiangshang.youth.core.service.LocalSubmissionStatus.Submitting -> "正在同步测评结果…"
                            com.xiangshang.youth.core.service.LocalSubmissionStatus.Submitted -> "测评结果已同步。"
                            com.xiangshang.youth.core.service.LocalSubmissionStatus.Failed -> "同步失败，结果仍已保存。请稍后重试。"
                            com.xiangshang.youth.core.service.LocalSubmissionStatus.Draft -> "测评结果尚未完成保存。"
                        })
                    }
                    r.geneticHeightReference(child.gender)?.let { Info("遗传身高参考 ${"%.1f".format(it)} cm · ${r.geneticHeightFormula(child.gender)}。仅供健康管理参考。") }
                    r.postureReport?.let { report ->
                        Surface(color = Color.White, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text("人体姿态观察记录", color = Navy, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                    Text(report.validationStatus.label, color = if (report.canPublishClassification) Color(0xFF25B86A) else Color(0xFFFF8A24), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                }
                                if (!report.canPublishClassification) Info(com.xiangshang.youth.core.model.AlgorithmReleaseGate.pendingPostureNotice)
                                report.screeningDecision?.let { decision ->
                                    val tint = when (decision.route) {
                                        com.xiangshang.youth.core.model.BodyScreeningRoute.AutoArchive -> Color(0xFF25B86A)
                                        com.xiangshang.youth.core.model.BodyScreeningRoute.RecaptureRequired -> Color(0xFFF47A59)
                                        com.xiangshang.youth.core.model.BodyScreeningRoute.ProfessionalReview -> Color(0xFFFF8A24)
                                    }
                                    Surface(color = tint.copy(alpha = 0.09f), shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = "身体筛查状态：${decision.route.label}。${decision.route.detail}" }) {
                                        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Text(decision.route.label, color = tint, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                            decision.outcomeLevel?.let { outcome ->
                                                Text("筛查建议：${outcome.label}", color = Navy, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                                            }
                                            Text(decision.route.detail, color = Navy, fontSize = 14.sp)
                                            Text("分流规则：${decision.decisionPolicyVersion}", color = Color.Gray, fontSize = 12.sp)
                                            val review = decision.reviewDecision
                                            if (review != null) {
                                                HorizontalDivider()
                                                Text(review.label, color = Navy, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                                                decision.reviewComment?.takeIf { it.isNotBlank() }?.let { Text(it, color = Navy, fontSize = 14.sp) }
                                                if (review == com.xiangshang.youth.core.model.BodyScreeningReviewDecision.Recapture) {
                                                    val taskLabels = decision.requestedRecaptureTasks.orEmpty().map { code -> com.xiangshang.youth.core.model.BodyCaptureTask.entries.firstOrNull { it.apiCode == code }?.title ?: code }
                                                    if (taskLabels.isNotEmpty()) Text("需要重采：${taskLabels.joinToString("、")}", color = Color.Gray, fontSize = 12.sp)
                                                }
                                            } else if (decision.route == com.xiangshang.youth.core.model.BodyScreeningRoute.ProfessionalReview) {
                                                Text("当前状态：等待学校专业人员复核", color = Color(0xFFFF8A24), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                            }
                                            if (decision.route == com.xiangshang.youth.core.model.BodyScreeningRoute.RecaptureRequired || decision.reviewDecision == com.xiangshang.youth.core.model.BodyScreeningReviewDecision.Recapture) {
                                                Button(onClick = { stage = 5 }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Blue)) { Text("按提示重新采集") }
                                            }
                                        }
                                    }
                                }
                                Text("本次观察 · ${report.snapshots.values.sumOf { it.sampleCount }} 条记录", color = Color.Gray, fontSize = 12.sp)
                                report.snapshots.toSortedMap(compareBy { it.name }).values.forEach { snapshot -> PostureSnapshotDetail(snapshot) }
                                report.reasons.filterNot { it == com.xiangshang.youth.core.model.AlgorithmReleaseGate.pendingPostureNotice }.forEach { Text("• $it", color = Navy, fontSize = 12.sp) }
                                Text(report.disclaimer, color = Color.Gray, fontSize = 12.sp)
                            }
                        }
                    }
                    Info("本次记录包含 8 段相机观察和双次重复性校验。原始画面未保存，仅保留结构化姿态参考值、质量摘要和版本信息。")
                    r.visualObservationSummary?.let { Info(it) }
                    Info(if (history.size < 2) "完成下一次实测后，将显示真实 BMI 趋势；不会虚构历史或目标数据。" else "BMI 实测趋势：${history.takeLast(3).joinToString(" → ") { "%.1f".format(it.bmi) }}")
                    Button(onClick = { stage = 8 }, modifier = Modifier.fillMaxWidth()) { Text("开始 28 天健康计划") }
                    OutlinedButton(onClick = { viewingSavedRecord = false; stage = 0; adultReady = false; spaceReady = false; consentAcknowledged = false }, modifier = Modifier.fillMaxWidth()) { Text("重新开始一次测评") }
                    OutlinedButton(onClick = { nav.navigate(Destinations.Courses) }, modifier = Modifier.fillMaxWidth()) { Text("查看推荐课程") }
                }
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
            visualHints = analysis.observationHint?.let { visualHints + (task.name to it) } ?: (visualHints - task.name)
            val snapshot = analysis.postureSnapshot
            if (analysis.accepted && snapshot != null) {
                val first = postureSnapshots[task]
                if (first?.repeatabilityStatus == "awaiting-second-take") {
                    val repeatability = PostureCaptureRepeatability.verify(first, snapshot)
                    if (repeatability.passed) {
                        val verified = PostureCaptureRepeatability.merged(first, snapshot, repeatability)
                        postureSnapshots = postureSnapshots + (task to verified)
                        captureNames = (captures + task).map { it.name }
                        captureFeedback = captureFeedback + (task.name to "两次独立采集一致性通过，已完成该项记录。")
                    } else {
                        postureSnapshots = postureSnapshots + (task to snapshot.copy(
                            captureAttemptCount = 1,
                            repeatabilityStatus = "awaiting-second-take",
                            repeatabilityMaximumDifference = repeatability.maximumDifference.takeIf { it.isFinite() }
                        ))
                        captureNames = (captures - task).map { it.name }
                        captureFeedback = captureFeedback + (task.name to "两次记录差异较大，请离开人型框后重新入镜，再完成第 2 次采集。")
                    }
                } else {
                    postureSnapshots = postureSnapshots + (task to snapshot.copy(
                        captureAttemptCount = 1,
                        repeatabilityStatus = "awaiting-second-take",
                        repeatabilityMaximumDifference = null
                    ))
                    captureNames = (captures - task).map { it.name }
                    captureFeedback = captureFeedback + (task.name to "第 1 次采集已保存。请离开人型框后重新入镜，完成第 2 次独立采集。")
                }
            } else {
                captureFeedback = captureFeedback + (task.name to analysis.message)
            }
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

private fun standardMeasurement(raw: String, range: ClosedFloatingPointRange<Double>): Double? =
    raw.trim().replace(',', '.').toDoubleOrNull()?.takeIf { it.isFinite() && it in range }?.let { kotlin.math.round(it * 10.0) / 10.0 }

private fun averageAtr(first: Double?, repeat: Double?, retestEnabled: Boolean): Double? {
    if (first == null) return null
    if (!retestEnabled) return first
    if (repeat == null) return null
    return kotlin.math.round((first + repeat) / 2.0 * 10.0) / 10.0
}

private fun standardMeasurementInput(raw: String): String {
    val normalized = raw.replace(',', '.').filter { it.isDigit() || it == '.' }
    val firstDot = normalized.indexOf('.')
    return if (firstDot < 0) normalized.take(2) else normalized.take(firstDot + 1) + normalized.drop(firstDot + 1).replace(".", "").take(1)
}

@Composable
private fun StandardScreeningCaptureStage(
    captures: Set<BodyCaptureTask>,
    postureSnapshots: Map<BodyCaptureTask, PostureMetricSnapshot>,
    captureFeedback: Map<String, String>,
    standingShoulderText: String,
    standingPelvisText: String,
    standingHeadTiltText: String,
    adamsObservedResult: String,
    adamsProminenceSide: String,
    gaitObservedResult: String,
    gaitObservationNote: String,
    seatedMidlineText: String,
    seatedShoulderText: String,
    seatedKyphosisResult: String,
    thoracicAtrText: String,
    lumbarAtrText: String,
    thoracicAtrSide: String,
    lumbarAtrSide: String,
    atrRetestEnabled: Boolean,
    thoracicAtrRepeatText: String,
    lumbarAtrRepeatText: String,
    seatedForwardBendAtrText: String,
    occiputWallDistanceText: String,
    occiputWallDistanceRepeatText: String,
    onStandingShoulderChanged: (String) -> Unit,
    onStandingPelvisChanged: (String) -> Unit,
    onStandingHeadTiltChanged: (String) -> Unit,
    onAdamsResultChanged: (String) -> Unit,
    onAdamsSideChanged: (String) -> Unit,
    onGaitResultChanged: (String) -> Unit,
    onGaitNoteChanged: (String) -> Unit,
    onSeatedMidlineChanged: (String) -> Unit,
    onSeatedShoulderChanged: (String) -> Unit,
    onSeatedKyphosisChanged: (String) -> Unit,
    onThoracicAtrChanged: (String) -> Unit,
    onLumbarAtrChanged: (String) -> Unit,
    onThoracicSideChanged: (String) -> Unit,
    onLumbarSideChanged: (String) -> Unit,
    onAtrRetestChanged: (Boolean) -> Unit,
    onThoracicAtrRepeatChanged: (String) -> Unit,
    onLumbarAtrRepeatChanged: (String) -> Unit,
    onSeatedForwardBendAtrChanged: (String) -> Unit,
    onOcciputWallDistanceChanged: (String) -> Unit,
    onOcciputWallDistanceRepeatChanged: (String) -> Unit,
    onOpenCamera: (BodyCaptureTask) -> Unit,
    onContinue: () -> Unit
) {
    val thoracicFirst = standardMeasurement(thoracicAtrText, 0.0..30.0)
    val lumbarFirst = standardMeasurement(lumbarAtrText, 0.0..30.0)
    val thoracicRepeat = standardMeasurement(thoracicAtrRepeatText, 0.0..30.0)
    val lumbarRepeat = standardMeasurement(lumbarAtrRepeatText, 0.0..30.0)
    val thoracicAtr = averageAtr(thoracicFirst, thoracicRepeat, atrRetestEnabled)
    val lumbarAtr = averageAtr(lumbarFirst, lumbarRepeat, atrRetestEnabled)
    val atrRecorded = thoracicAtr != null && lumbarAtr != null && (thoracicAtr == 0.0 || thoracicAtrSide != "无") && (lumbarAtr == 0.0 || lumbarAtrSide != "无")
    val otwdFirst = standardMeasurement(occiputWallDistanceText, 0.0..15.0)
    val otwdSecond = standardMeasurement(occiputWallDistanceRepeatText, 0.0..15.0)
    val otwdRecorded = otwdFirst != null && otwdSecond != null
    val standingRecorded = standardMeasurement(standingShoulderText, 0.0..10.0) != null && standardMeasurement(standingPelvisText, 0.0..10.0) != null && standardMeasurement(standingHeadTiltText, 0.0..30.0) != null
    val adamsRecorded = adamsObservedResult != "unrecorded" && (adamsObservedResult == "negative" || adamsProminenceSide != "无")
    val gaitRecorded = gaitObservedResult != "unrecorded"
    val seatedRecorded = standardMeasurement(seatedMidlineText, 0.0..10.0) != null && standardMeasurement(seatedShoulderText, 0.0..10.0) != null && seatedKyphosisResult != "unrecorded"
    val completed = SpineScreeningStandard.homeCameraItems.count { item ->
        item.task?.let(captures::contains) == true
    }

    Hero("八段家庭相机采集", "已完成 $completed / ${SpineScreeningStandard.homeCameraItems.size}")
    Info("${SpineScreeningStandard.mainCameraPlacement}；动态步态沿约 3 米安全直线自然往返 1 次。每项需完成两次稳定采集。")
    SpineScreeningStandard.homeCameraItems.forEach { item ->
        if (item.method == SpineScreeningStandard.Method.Camera) {
            val task = item.task ?: return@forEach
            val captured = task in captures
            val awaitingSecondTake = postureSnapshots[task]?.repeatabilityStatus == "awaiting-second-take"
            Surface(
                modifier = Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "第${item.number}项，${item.title}，${if (captured) "两次采集已通过，可重新采集" else if (awaitingSecondTake) "第1次已完成，还需第2次" else "打开相机"}" }.clickable { onOpenCamera(task) },
                color = Color.White,
                shape = RoundedCornerShape(16.dp)
            ) {
                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
                    Surface(color = (if (captured) Color(0xFF25B86A) else Blue).copy(alpha = .10f), shape = RoundedCornerShape(13.dp), modifier = Modifier.size(46.dp)) {
                        Box(contentAlignment = Alignment.Center) { Text(if (captured) "✓" else item.number.toString(), color = if (captured) Color(0xFF25B86A) else Blue, fontWeight = FontWeight.Bold, fontSize = 18.sp) }
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(item.title, color = Navy, fontWeight = FontWeight.Bold)
                        if (captured) Text("两次采集已通过", color = Color(0xFF25B86A), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        else if (awaitingSecondTake) Text("第 1 次已保存 · 还需第 2 次", color = Color(0xFFFF8A24), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        Text(item.purpose, color = Blue, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        Text(item.instruction, color = Color.Gray, fontSize = 12.sp)
                        if (task == BodyCaptureTask.ForwardBend) Text(SpineScreeningStandard.forwardBendAuxiliaryPlacement, color = Color(0xFFFF8A24), fontSize = 12.sp)
                        captureFeedback[task.name]?.let { Text(it, color = if (captured) Color(0xFF25B86A) else Color(0xFFFF8A24), fontSize = 12.sp) }
                    }
                    Icon(if (captured) Icons.Filled.Refresh else if (task == BodyCaptureTask.GaitVideo) Icons.Filled.Videocam else Icons.Filled.CameraAlt, null, tint = if (captured) Color(0xFF25B86A) else Blue)
                }
            }
        } else {
            Surface(color = Color.White, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.Top) {
                        Surface(color = (if (atrRecorded) Color(0xFF25B86A) else Blue).copy(alpha = .10f), shape = RoundedCornerShape(13.dp), modifier = Modifier.size(46.dp)) { Box(contentAlignment = Alignment.Center) { Text(if (atrRecorded) "✓" else "3", color = if (atrRecorded) Color(0xFF25B86A) else Blue, fontWeight = FontWeight.Bold, fontSize = 18.sp) } }
                        Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f)) { Text(item.title, color = Navy, fontWeight = FontWeight.Bold); Text(item.purpose, color = Blue, fontSize = 12.sp, fontWeight = FontWeight.SemiBold); Text(item.instruction, color = Color.Gray, fontSize = 12.sp) }
                    }
                    AtrInputRow("胸段 T4-T8", thoracicAtrText, thoracicAtrSide, onThoracicAtrChanged, onThoracicSideChanged)
                    AtrInputRow("腰段 T12-L3", lumbarAtrText, lumbarAtrSide, onLumbarAtrChanged, onLumbarSideChanged)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("读数波动较大，启用复测并取算术平均值", color = Navy, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        Switch(checked = atrRetestEnabled, onCheckedChange = onAtrRetestChanged)
                    }
                    if (atrRetestEnabled) {
                        AtrInputRow("胸段复测", thoracicAtrRepeatText, thoracicAtrSide, { onThoracicAtrRepeatChanged(standardMeasurementInput(it)) }, onThoracicSideChanged)
                        AtrInputRow("腰段复测", lumbarAtrRepeatText, lumbarAtrSide, { onLumbarAtrRepeatChanged(standardMeasurementInput(it)) }, onLumbarSideChanged)
                        Text("保留两次原始读数，最终胸段和腰段分别取算术平均值。", color = Color.Gray, fontSize = 12.sp)
                    }
                    Text(if (atrRecorded) "ATR 读数完整 · 最大值 ${"%.1f".format(Locale.US, maxOf(thoracicAtr ?: 0.0, lumbarAtr ?: 0.0))}°" else "两段均需录入；非 0° 时选择左/右偏向", color = if (atrRecorded) Color(0xFF25B86A) else Color(0xFFFF8A24), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    val standingMaximum = listOfNotNull(thoracicAtr, lumbarAtr).maxOrNull()
                    if (standingMaximum != null && standingMaximum >= SpineScreeningStandard.atrAttentionDegrees) {
                        HorizontalDivider()
                        Text("坐位前屈 ATR 复核（手册建议）", color = Navy, fontWeight = FontWeight.Bold)
                        Text("让孩子坐于凳上再次前屈，录入最大 ATR。较站位下降 ≥3° 记录为功能性偏斜可能；变化不足 3° 进入结构异常复核提示。", color = Color.Gray, fontSize = 12.sp)
                        OutlinedTextField(
                            value = seatedForwardBendAtrText,
                            onValueChange = { onSeatedForwardBendAtrChanged(standardMeasurementInput(it)) },
                            label = { Text("坐位前屈 ATR") }, suffix = { Text("°") }, singleLine = true,
                            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }
        }
    }
    Info("ATR、枕墙距和软尺厘米值需要受训人员及专用器械。家庭相机不会生成 ATR、Cobb 角或医疗诊断。")
    Button(onClick = onContinue, enabled = completed == SpineScreeningStandard.homeCameraItems.size, modifier = Modifier.fillMaxWidth()) {
        Text(if (completed == SpineScreeningStandard.homeCameraItems.size) "继续质量确认" else "还需完成 ${SpineScreeningStandard.homeCameraItems.size - completed} 项")
    }
}

@Composable
private fun SupervisedStandingCard(shoulder: String, pelvis: String, headTilt: String, onShoulder: (String) -> Unit, onPelvis: (String) -> Unit, onHeadTilt: (String) -> Unit) {
    val ready = standardMeasurement(shoulder, 0.0..10.0) != null && standardMeasurement(pelvis, 0.0..10.0) != null && standardMeasurement(headTilt, 0.0..30.0) != null
    Surface(color = Color.White, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("项目 1 现场实测", color = Navy, fontWeight = FontWeight.Bold)
            Text("指尖轻触双侧肩峰、髂后上棘标记，用 0.1 cm 软尺测量与地面的垂直高度差。", color = Color.Gray, fontSize = 12.sp)
            ManualNumberInput("双肩高度差", shoulder, "cm", onShoulder)
            ManualNumberInput("骨盆高度差", pelvis, "cm", onPelvis)
            ManualNumberInput("头部侧倾", headTilt, "°", onHeadTilt)
            Text(if (ready) "实测数值已完整记录" else "请录入三项现场实测值", color = if (ready) Color(0xFF25B86A) else Color(0xFFFF8A24), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun SupervisedAdamsCard(result: String, side: String, onResult: (String) -> Unit, onSide: (String) -> Unit) {
    Surface(color = Color.White, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("项目 2 主检员定性记录", color = Navy, fontWeight = FontWeight.Bold)
            Text("双侧等高为阴性，单侧隆起＜1 cm 为可疑阳性，≥1 cm 为阳性。", color = Color.Gray, fontSize = 12.sp)
            listOf("unrecorded" to "未记录", "negative" to "阴性 −", "equivocal" to "可疑 ±", "positive" to "阳性 +").chunked(2).forEach { choices ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
                    choices.forEach { (value, label) -> FilterChip(selected = result == value, onClick = { onResult(value) }, label = { Text(label, fontSize = 12.sp) }, modifier = Modifier.weight(1f)) }
                }
            }
            if (result == "equivocal" || result == "positive") Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("左", "右").forEach { value -> FilterChip(selected = side == value, onClick = { onSide(value) }, label = { Text("${value}侧隆起") }) }
            }
        }
    }
}

@Composable
private fun SupervisedGaitCard(result: String, note: String, onResult: (String) -> Unit, onNote: (String) -> Unit) {
    Surface(color = Color.White, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("项目 4 步态人工观察", color = Navy, fontWeight = FontWeight.Bold)
            Text("从后方、侧方同步观察肩部摆动、骨盆上下摆动和躯干中线。", color = Color.Gray, fontSize = 12.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                listOf("unrecorded" to "未记录", "normal" to "无异常", "abnormal" to "存在异常").forEach { (value, label) -> FilterChip(selected = result == value, onClick = { onResult(value) }, label = { Text(label, fontSize = 12.sp) }, modifier = Modifier.weight(1f)) }
            }
            OutlinedTextField(value = note, onValueChange = { onNote(it.take(200)) }, label = { Text("异常描述（选填）") }, minLines = 2, modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun SupervisedSeatedCard(midline: String, shoulder: String, kyphosis: String, onMidline: (String) -> Unit, onShoulder: (String) -> Unit, onKyphosis: (String) -> Unit) {
    Surface(color = Color.White, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("项目 5 坐姿现场实测", color = Navy, fontWeight = FontWeight.Bold)
            ManualNumberInput("棘突中线偏移", midline, "cm", onMidline)
            ManualNumberInput("双肩高度差", shoulder, "cm", onShoulder)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                listOf("unrecorded" to "未记录", "normal" to "未见明显", "abnormal" to "圆肩驼背").forEach { (value, label) -> FilterChip(selected = kyphosis == value, onClick = { onKyphosis(value) }, label = { Text(label, fontSize = 12.sp) }, modifier = Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun ManualNumberInput(title: String, value: String, unit: String, onValue: (String) -> Unit) {
    OutlinedTextField(value = value, onValueChange = { onValue(standardMeasurementInput(it)) }, label = { Text(title) }, suffix = { Text(unit) }, singleLine = true, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth())
}

@Composable
private fun AtrInputRow(title: String, value: String, side: String, onValueChanged: (String) -> Unit, onSideChanged: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, color = Navy, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
        OutlinedTextField(value = value, onValueChange = { onValueChanged(standardMeasurementInput(it)) }, label = { Text("最大读数") }, suffix = { Text("°") }, singleLine = true, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth())
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("无", "左", "右").forEach { option -> FilterChip(selected = side == option, onClick = { onSideChanged(option) }, label = { Text(option) }) }
        }
    }
}

@Composable private fun PostureSnapshotDetail(snapshot: PostureMetricSnapshot) {
    val metrics = buildList {
        if (snapshot.task == BodyCaptureTask.FootArch) add("当前仅记录足部画面质量与足跟投影；足弓分类待专用足部模型完成人工标注验证")
        snapshot.shoulderHeightDifferenceCm?.let { add("肩线投影参考值 %.1f".format(it)) }
        snapshot.pelvicHeightDifferenceCm?.let { add("骨盆线投影参考值 %.1f".format(it)) }
        snapshot.headTiltDegrees?.let { add("头部侧倾 %.1f°".format(it)) }
        snapshot.spinalMidlineDeviationCm?.let { add("躯干中线投影参考值 %.1f".format(it)) }
        snapshot.kneeAlignmentProxyRatio?.let { add("站立膝部轨迹参考值 %.2f".format(it)) }
        snapshot.lowerLimbAxisAsymmetryDegrees?.let { add("下肢左右差参考值 %.1f°".format(it)) }
        snapshot.movementRepetitionCount?.let { add("完整下蹲回位 %.0f 次".format(it)) }
        snapshot.kneeTrackingAsymmetryRatio?.let { add("动态膝轨迹左右差 %.2f".format(it)) }
        snapshot.squatDepthRatio?.let { add("动作幅度参考值 %.2f".format(it)) }
        snapshot.footArchVisibilityScore?.let { add("足部画面可见度 %.0f%%".format(it * 100)) }
        snapshot.heelAlignmentProxyDegrees?.let { add("足跟线投影参考值 %.1f°".format(it)) }
        snapshot.adamsResult?.let { add("Adams ${it.label}") }
        snapshot.adamsProminenceSide?.let { add("隆起侧 $it") }
        snapshot.cameraProxyAtrDegrees?.let { add("旋转代理 %.1f°".format(it)) }
        snapshot.thoracicAtrDegrees?.let { add("胸段 ATR %.1f°%s".format(it, snapshot.thoracicAtrSide?.let { side -> " · ${side}侧" }.orEmpty())) }
        snapshot.lumbarAtrDegrees?.let { add("腰段 ATR %.1f°%s".format(it, snapshot.lumbarAtrSide?.let { side -> " · ${side}侧" }.orEmpty())) }
        if (snapshot.thoracicAtrFirstDegrees != null && snapshot.thoracicAtrSecondDegrees != null) add("胸段复测原始值 %.1f° / %.1f°".format(snapshot.thoracicAtrFirstDegrees, snapshot.thoracicAtrSecondDegrees))
        if (snapshot.lumbarAtrFirstDegrees != null && snapshot.lumbarAtrSecondDegrees != null) add("腰段复测原始值 %.1f° / %.1f°".format(snapshot.lumbarAtrFirstDegrees, snapshot.lumbarAtrSecondDegrees))
        snapshot.seatedForwardBendAtrDegrees?.let { add("坐位前屈 ATR %.1f°".format(it)) }
        snapshot.occiputWallDistanceCm?.let { add("枕墙距 %.1f cm".format(it)) }
        snapshot.gaitTrunkSwayCm?.let { add("步态摆动投影参考值 %.1f".format(it)) }
        snapshot.gaitObservedAbnormal?.let { add(if (it) "步态人工观察异常" else "步态人工观察未见异常") }
        snapshot.seatedThoracicKyphosisObserved?.let { add(if (it) "坐姿圆肩驼背" else "坐姿未见明显圆肩驼背") }
    }
    Surface(color = Canvas, shape = RoundedCornerShape(10.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(9.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(snapshot.task.title, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp, modifier = Modifier.weight(1f))
                Text("记录稳定度 %.0f%% · %d 条".format(snapshot.confidence * 100, snapshot.sampleCount), color = if (snapshot.confidence >= PostureScreeningRules.minimumConfidence && snapshot.sampleCount >= PostureScreeningRules.minimumSamples) Color(0xFF25B86A) else Color(0xFFF47A59), fontSize = 12.sp)
            }
            Text(metrics.ifEmpty { listOf("该段尚未形成有效结构化记录，请重新拍摄") }.joinToString(" · "), color = Color.Gray, fontSize = 12.sp)
            snapshot.captureProtocolVersion?.let { protocol ->
                val camera = if (snapshot.cameraFacing == "rear-1x") "后置 1×" else "引导镜头"
                val trace = when (snapshot.repeatabilityStatus) {
                    "passed" -> "$camera · 两次独立采集一致性已通过并融合 · ${snapshot.qualityChecks?.size ?: 0} 项质量门 · $protocol"
                    "awaiting-second-take" -> "$camera · 第 1 次已保存，尚需独立第 2 次采集 · $protocol"
                    else -> "$camera · ${snapshot.qualityChecks?.size ?: 0} 项质量门已通过 · $protocol"
                }
                Text(trace, color = Blue, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
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
