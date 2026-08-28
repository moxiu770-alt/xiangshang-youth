package com.xiangshang.youth.feature.parent

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.speech.tts.TextToSpeech
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.android.gms.tasks.Tasks
import com.xiangshang.youth.R
import com.xiangshang.youth.app.Blue
import com.xiangshang.youth.app.Canvas
import com.xiangshang.youth.app.Green
import com.xiangshang.youth.app.Navy
import com.xiangshang.youth.core.model.AlgorithmReleaseGate
import com.xiangshang.youth.core.service.FollowAlongSessionRecord
import com.xiangshang.youth.core.util.BusinessClock
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.json.JSONObject
import kotlinx.coroutines.delay

data class FollowAlongExercise(
    val id: String,
    val title: String,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
    val target: Int,
    val unit: String,
    val cue: String,
    /** Remote/content-ops fields; defaults preserve the current bundled demo. */
    val videoAssetKey: String = "follow_along_training",
    val cadenceSeconds: Float = 1f,
    val minAgeMonths: Int = 72,
    val maxAgeMonths: Int = 216,
    val tags: List<String> = emptyList()
)

object FollowAlongContentCatalog {
    const val manifestVersion = "UY-CONTENT-MANIFEST-1.0"
    const val policy = "template-video-v1"
}

enum class FollowAlongStage(val label: String) { Setup("起始位"), Exertion("发力位"), Return("回位") }
enum class FollowAlongCaptureState(val label: String) { Waiting("等待取景"), Ready("已就绪"), Occluded("关键点被遮挡"), OutOfFrame("请全身入框"), MultiplePeople("检测到多人"), Error("识别暂不可用") }
enum class FollowAlongSide(val label: String) { Left("左侧"), Right("右侧"), Both("双侧"), Unknown("待确认") }

data class FollowAlongPoseFeedback(
    val visible: Boolean,
    val active: Boolean,
    val message: String,
    val confidence: Float,
    val repCount: Int,
    val activeSeconds: Int,
    val qualityScore: Int,
    val stage: FollowAlongStage = FollowAlongStage.Setup,
    val captureState: FollowAlongCaptureState = FollowAlongCaptureState.Waiting,
    val side: FollowAlongSide = FollowAlongSide.Unknown,
    val rangePercent: Int = 0,
    val tempoScore: Int = 0,
    val comboCount: Int = 0
) {
    companion object {
        val Waiting = FollowAlongPoseFeedback(false, false, "打开摄像头后，系统会给出动作提示", 0f, 0, 0, 0)
    }
}

data class FollowAlongDay(val id: Int, val title: String, val exercises: List<FollowAlongExercise>)

val followAlongDays = listOf(
    FollowAlongDay(1, "上肢唤醒", listOf(
        FollowAlongExercise("front_raise", "前平举", Icons.Filled.AccessibilityNew, 15, "次", "手臂抬到肩膀高度，保持呼吸平稳"),
        FollowAlongExercise("lateral_raise", "侧平举", Icons.Filled.AccessibilityNew, 12, "次", "肩膀放松，手臂沿身体两侧打开")
    )),
    FollowAlongDay(2, "下肢基础", listOf(
        FollowAlongExercise("squat", "深蹲", Icons.Filled.FitnessCenter, 20, "次", "膝盖对准脚尖，臀部向后坐"),
        FollowAlongExercise("lunge", "交替弓步", Icons.AutoMirrored.Filled.DirectionsWalk, 12, "次/腿", "前脚踩稳，后膝缓慢下沉")
    )),
    FollowAlongDay(3, "恢复日", emptyList()),
    FollowAlongDay(4, "全身燃脂", listOf(
        FollowAlongExercise("jumping_jack", "开合跳", Icons.Filled.Star, 60, "秒", "手脚同时打开，落地时膝盖微屈"),
        FollowAlongExercise("high_knee", "高抬腿", Icons.AutoMirrored.Filled.DirectionsRun, 45, "秒", "上身保持挺直，膝盖抬到舒适高度")
    )),
    FollowAlongDay(5, "核心稳定", listOf(
        FollowAlongExercise("plank", "平板支撑", Icons.Filled.AccessibilityNew, 30, "秒", "肩、髋、脚踝保持一条线"),
        FollowAlongExercise("sit_up", "仰卧起坐", Icons.Filled.AccessibilityNew, 15, "次", "用腹部发力，颈部保持放松")
    )),
    FollowAlongDay(6, "综合挑战", listOf(
        FollowAlongExercise("burpee", "波比跳", Icons.Filled.LocalFireDepartment, 10, "次", "动作连贯，按孩子体力调整节奏"),
        FollowAlongExercise("squat_challenge", "深蹲挑战", Icons.Filled.FitnessCenter, 25, "次", "动作质量优先，不追求速度")
    )),
    FollowAlongDay(7, "恢复日", emptyList())
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FollowAlongTrainingDialog(
    studentId: String = "",
    studentName: String,
    childAgeMonths: Int?,
    dayIndex: Int,
    voiceGuidanceEnabled: Boolean = true,
    onVoiceGuidanceChanged: (Boolean) -> Unit = {},
    onComplete: () -> Unit,
    onSessionSaved: (FollowAlongSessionRecord) -> Unit = {},
    onDismiss: () -> Unit
) {
    val day = followAlongDays[((dayIndex % followAlongDays.size) + followAlongDays.size) % followAlongDays.size]
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var selectedExercise by rememberSaveable(day.id) { mutableIntStateOf(0) }
    var cameraEnabled by rememberSaveable { mutableStateOf(false) }
    var cameraFront by rememberSaveable { mutableStateOf(true) }
    var cameraPreview by remember { mutableStateOf<PreviewView?>(null) }
    var cameraMessage by remember { mutableStateOf<String?>(null) }
    var completed by rememberSaveable { mutableStateOf(false) }
    val completionScale by animateFloatAsState(if (completed) 1f else .92f, label = "completionPulse")
    var speakerEnabled by rememberSaveable(day.id, voiceGuidanceEnabled) { mutableStateOf(voiceGuidanceEnabled) }
    var templatePositionMs by rememberSaveable(day.id) { mutableLongStateOf(0L) }
    var templatePlaybackStatus by remember { mutableStateOf(CoursePlaybackStatus.Preparing) }
    var templateVideoRetryToken by rememberSaveable(day.id) { mutableIntStateOf(0) }
    var exerciseProgress by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var poseFeedback by remember { mutableStateOf(FollowAlongPoseFeedback.Waiting) }
    var lastSpokenGuide by rememberSaveable { mutableStateOf("") }
    var lastSpokenGuideAt by rememberSaveable { mutableLongStateOf(0L) }
    var exerciseQualityScores by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var showPartialCompletionAlert by rememberSaveable { mutableStateOf(false) }
    var cameraUsedDuringSession by rememberSaveable { mutableStateOf(false) }
    var visualUnits by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var manualUnits by rememberSaveable { mutableIntStateOf(0) }
    var startedAtMillis by rememberSaveable { mutableLongStateOf(0L) }
    var sessionSaved by rememberSaveable { mutableStateOf(false) }
    val poseAnalyzer = remember { FollowAlongPoseAnalyzer(context.applicationContext) }
    val latestProgress by rememberUpdatedState(exerciseProgress)
    val coach = rememberFollowAlongCoach(context)
    val requestCamera = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) cameraEnabled = true else cameraMessage = "请在系统设置中允许相机权限，也可以直接使用示范视频跟练。"
    }
    val saveSession: () -> Unit = saveSession@{
        if (sessionSaved) return@saveSession
        sessionSaved = true
        val totalTarget = day.exercises.sumOf { it.target }
        val totalDone = day.exercises.sumOf { exerciseProgress[it.id] ?: 0 }
        val ratio = if (totalTarget > 0) (totalDone.toFloat() / totalTarget).coerceIn(0f, 1f) else 1f
        onSessionSaved(FollowAlongSessionRecord(childId = studentId, dayId = day.id, completedAt = BusinessClock.format("yyyy-MM-dd'T'HH:mm:ssXXX"), durationSeconds = if (startedAtMillis > 0L) ((System.currentTimeMillis() - startedAtMillis) / 1000L).toInt().coerceAtLeast(0) else 0, completionRatio = ratio, qualityScore = 0, cameraVerified = false, visualUnits = visualUnits, manualUnits = manualUnits, modelVersion = ChildFollowAlongTuning.algorithmVersion, mode = "parentConfirmedAssistedTraining"))
    }

    LaunchedEffect(day.id, speakerEnabled) {
        if (speakerEnabled) coach.say(if (day.exercises.isEmpty()) "今天是恢复日，请做轻松舒展和散步。" else "开始${day.title}。先看示范，再跟着做。")
    }
    LaunchedEffect(day.id, selectedExercise, speakerEnabled) {
        val exercise = day.exercises.getOrNull(selectedExercise)
        lastSpokenGuide = ""
        lastSpokenGuideAt = 0L
        poseAnalyzer.update(exercise?.id ?: "unknown", childAgeMonths) { feedback ->
            poseFeedback = feedback
            if (feedback.visible) cameraUsedDuringSession = true
            exercise?.let { currentExercise ->
                val previous = exerciseQualityScores[currentExercise.id] ?: 0
                if (feedback.qualityScore > previous) {
                    exerciseQualityScores = exerciseQualityScores + (currentExercise.id to feedback.qualityScore)
                }
            }
            val now = System.currentTimeMillis()
            if (speakerEnabled && feedback.message.isNotBlank() && feedback.message != lastSpokenGuide && now - lastSpokenGuideAt >= 2_200L) {
                lastSpokenGuide = feedback.message
                lastSpokenGuideAt = now
                coach.say(feedback.message)
            }
            exercise ?: return@update
            val current = latestProgress[exercise.id] ?: 0
            val next = if (exercise.unit == "秒") {
                max(current, min(exercise.target, feedback.activeSeconds))
            } else {
                max(current, min(exercise.target, feedback.repCount))
            }
            if (next != current) exerciseProgress = exerciseProgress + (exercise.id to next)
            if (feedback.visible) {
                val verified = if (exercise.unit == "秒") feedback.activeSeconds else feedback.repCount
                visualUnits = visualUnits + (exercise.id to maxOf(visualUnits[exercise.id] ?: 0, verified.coerceAtMost(exercise.target)))
                if (startedAtMillis == 0L) startedAtMillis = System.currentTimeMillis()
            }
        }
    }
    val templateBeat = day.exercises.getOrNull(selectedExercise)?.let { exercise ->
        (((templatePositionMs / 1000f) / exercise.cadenceSeconds.coerceAtLeast(.4f)).toInt() % 4) + 1
    } ?: 1
    DisposableEffect(cameraEnabled, cameraFront, cameraPreview, lifecycleOwner, selectedExercise) {
        if (cameraEnabled) {
            cameraPreview?.let { preview ->
                bindFollowAlongCamera(context, lifecycleOwner, preview, cameraFront, poseAnalyzer)
            }
        } else if (!cameraEnabled) {
            unbindFollowAlongCamera(context)
        }
        onDispose { }
    }
    DisposableEffect(Unit) {
        onDispose {
            coach.close()
            poseAnalyzer.close()
            unbindFollowAlongCamera(context)
        }
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(
            modifier = Modifier.fillMaxWidth().fillMaxHeight(0.94f),
            color = Canvas,
            shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
        ) {
            Column(Modifier.fillMaxSize()) {
                TopAppBar(
                    title = { Text("训练跟练", color = Navy, fontWeight = FontWeight.Bold) },
                    navigationIcon = { IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, "关闭", tint = Navy) } },
                    actions = {
                        IconButton(onClick = {
                            speakerEnabled = !speakerEnabled
                            onVoiceGuidanceChanged(speakerEnabled)
                            if (!speakerEnabled) coach.stop()
                        }) {
                            Icon(if (speakerEnabled) Icons.AutoMirrored.Filled.VolumeUp else Icons.AutoMirrored.Filled.VolumeOff, if (speakerEnabled) "关闭语音" else "开启语音", tint = Navy)
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Canvas)
                )
                Column(
                    Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Surface(color = Color.White, shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text("给 $studentName 的今日训练", color = Navy, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                                    Text("第 ${day.id} 天 · ${day.title}", color = Blue, fontWeight = FontWeight.SemiBold)
                                }
                                Text("家长陪同", color = Blue, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            }
                            Text(if (day.exercises.isEmpty()) "今天以恢复和身体感受记录为主，不需要强行训练。" else "先看示范，再打开摄像头跟着做。动作质量优先，出现不适请立即停止。", color = Color.Gray, fontSize = 16.sp)
                        }
                    }
                    Surface(color = Color(0xFFFFF4E8), shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth()) {
                        Text(AlgorithmReleaseGate.pendingFollowAlongNotice, color = Navy, fontSize = 16.sp, modifier = Modifier.padding(16.dp))
                    }
                    if (day.exercises.isEmpty()) {
                        RecoveryCard(onComplete = { completed = true; saveSession(); onComplete(); onDismiss() })
                    } else {
                        Surface(color = Color.White, shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text("示范视频", color = Navy, fontSize = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                    Text("跟做模式", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.background(Blue, RoundedCornerShape(50)).padding(horizontal = 9.dp, vertical = 5.dp))
                                }
                                Box(Modifier.fillMaxWidth().aspectRatio(9f / 16f).clip(RoundedCornerShape(16.dp)).background(Color(0xFF101828))) {
                                    CourseVideoPlayer(
                                        source = "android.resource://${context.packageName}/${R.raw.follow_along_training}",
                                        captions = emptyList(),
                                        initialPositionMs = 0,
                                        playRequested = true,
                                        retryToken = templateVideoRetryToken,
                                        onSnapshot = { snapshot ->
                                            templatePositionMs = snapshot.positionMs
                                            templatePlaybackStatus = snapshot.status
                                        },
                                        onCheckpoint = { _, _ -> },
                                        onEnded = {},
                                        repeat = true,
                                        showController = false,
                                        snapshotIntervalMs = 250,
                                        accessibilityLabel = "训练动作示范视频，循环播放",
                                        modifier = Modifier.fillMaxSize()
                                    )
                                    if (templatePlaybackStatus == CoursePlaybackStatus.Failed) {
                                        Surface(
                                            modifier = Modifier.align(Alignment.Center),
                                            color = Color.Black.copy(alpha = .72f),
                                            shape = RoundedCornerShape(12.dp)
                                        ) {
                                            Column(Modifier.padding(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                                Text("示范视频暂时无法播放", color = Color.White, fontSize = 16.sp)
                                                TextButton(onClick = { templateVideoRetryToken += 1 }) { Text("重新加载") }
                                            }
                                        }
                                    }
                                    if (cameraEnabled) {
                                        Box(
                                            modifier = Modifier.padding(14.dp).size(width = 118.dp, height = 166.dp).clip(RoundedCornerShape(12.dp))
                                        ) {
                                            AndroidView(
                                                factory = { cameraContext ->
                                                    PreviewView(cameraContext).also {
                                                        it.scaleType = PreviewView.ScaleType.FIT_CENTER
                                                        cameraPreview = it
                                                    }
                                                },
                                                modifier = Modifier.fillMaxSize()
                                            )
                                            Box(
                                                modifier = Modifier.fillMaxSize().padding(7.dp).border(
                                                    1.5.dp,
                                                    if (poseFeedback.visible) (if (poseFeedback.active) Green else Color.White) else Color.White.copy(alpha = .8f),
                                                    RoundedCornerShape(9.dp)
                                                )
                                            )
                                            Surface(
                                                modifier = Modifier.align(Alignment.TopStart).padding(8.dp),
                                                color = Color.Black.copy(alpha = .48f),
                                                shape = RoundedCornerShape(50)
                                            ) {
                                                Row(Modifier.padding(horizontal = 7.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                                    Icon(if (poseFeedback.visible) Icons.Filled.CenterFocusStrong else Icons.Filled.Person, null, tint = Color.White, modifier = Modifier.size(11.dp))
                                                    Spacer(Modifier.width(3.dp))
                                                    Text(if (poseFeedback.visible) "全身远景" else "取景准备", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                                }
                                            }
                                        }
                                    }
                                }
                                if (cameraEnabled) {
                                    Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Surface(color = if (poseFeedback.visible) (if (poseFeedback.active) Green else Color(0xFFFFA726)) else Color.Gray, shape = RoundedCornerShape(50)) { Spacer(Modifier.size(8.dp)) }
                                        Spacer(Modifier.width(7.dp))
                                        Text(poseFeedback.message, color = Navy, fontSize = 16.sp, modifier = Modifier.weight(1f), maxLines = 2)
                                        Text("辅助计数 ${poseFeedback.repCount} 次 · 连击 ${poseFeedback.comboCount}", color = Blue, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                    }
                                    FollowAlongGuideCard(poseFeedback = poseFeedback, exercise = day.exercises.getOrNull(selectedExercise), templateBeat = templateBeat)
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                                    Button(onClick = {
                                        if (cameraEnabled) cameraEnabled = false else if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) cameraEnabled = true else requestCamera.launch(Manifest.permission.CAMERA)
                                    }, modifier = Modifier.weight(1f), colors = ButtonDefaults.buttonColors(containerColor = Blue)) {
                                        Icon(Icons.Filled.CameraAlt, null, modifier = Modifier.size(17.dp)); Spacer(Modifier.width(5.dp)); Text(if (cameraEnabled) "关闭我的画面" else "打开我的画面")
                                    }
                                    if (cameraEnabled) OutlinedButton(onClick = { cameraFront = !cameraFront }, modifier = Modifier.size(48.dp), contentPadding = PaddingValues(0.dp)) { Icon(Icons.Filled.Cameraswitch, "切换摄像头", tint = Blue) }
                                }
                            }
                        }
                        Text("今日动作", color = Navy, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                        day.exercises.forEachIndexed { index, exercise ->
                            val selected = selectedExercise == index
                            Surface(
                                color = if (selected) Blue.copy(alpha = .08f) else Color.White,
                                shape = RoundedCornerShape(14.dp),
                                modifier = Modifier.fillMaxWidth().semantics {
                                    role = Role.Button
                                    contentDescription = "${exercise.title}，目标 ${exercise.target}${exercise.unit}，${if (selected) "当前已选择" else "点击选择"}"
                                }.clickable {
                                    selectedExercise = index
                                    if (speakerEnabled) coach.say("${exercise.title}，目标 ${exercise.target}${exercise.unit}。${exercise.cue}")
                                }
                            ) {
                                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(exercise.icon, null, tint = if (selected) Blue else Blue.copy(alpha = .7f), modifier = Modifier.size(34.dp))
                                    Spacer(Modifier.width(10.dp))
                                    Column(Modifier.weight(1f)) {
                                        Text(exercise.title, color = Navy, fontWeight = FontWeight.Bold)
                                        Text(exercise.cue, color = Color.Gray, fontSize = 16.sp)
                                    }
                                    Text("${exercise.target} ${exercise.unit}", color = Blue, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                }
                            }
                        }
                        day.exercises.getOrNull(selectedExercise)?.let { exercise ->
                            val progress = exerciseProgress[exercise.id] ?: 0
                            Surface(color = Green.copy(alpha = .08f), shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth()) {
                                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text("跟做进度", color = Navy, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                        Text("$progress / ${exercise.target} ${exercise.unit}", color = Blue, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                    }
                                    LinearProgressIndicator(progress = { (progress.toFloat() / exercise.target.coerceAtLeast(1)).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth(), color = Green)
                                    if (poseFeedback.visible) {
                                        Text(if (poseFeedback.active) "动作已开始" else "画面已就绪，等待动作幅度", color = if (poseFeedback.active) Green else Color.Gray, fontSize = 16.sp)
                                    }
                                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                                        Button(onClick = {
                                            val amount = if (exercise.unit == "秒") 10 else 1
                                            val next = (progress + amount).coerceAtMost(exercise.target)
                                            exerciseProgress = exerciseProgress + (exercise.id to next)
                                            manualUnits += (next - progress).coerceAtLeast(0)
                                            if (startedAtMillis == 0L) startedAtMillis = System.currentTimeMillis()
                                            if (speakerEnabled) coach.say(if (next >= exercise.target) "${exercise.title} 已达标，可以进入下一个动作。" else exercise.cue)
                                        }, modifier = Modifier.weight(1f), colors = ButtonDefaults.buttonColors(containerColor = Blue)) {
                                            Icon(Icons.Filled.AddCircle, null, modifier = Modifier.size(17.dp)); Spacer(Modifier.width(4.dp)); Text(if (exercise.unit == "秒") "手动记录 10 秒" else "手动记录 1 次")
                                        }
                                        OutlinedButton(onClick = {
                                            manualUnits += (exercise.target - progress).coerceAtLeast(0)
                                            exerciseProgress = exerciseProgress + (exercise.id to exercise.target)
                                            if (startedAtMillis == 0L) startedAtMillis = System.currentTimeMillis()
                                            if (speakerEnabled) coach.say("${exercise.title} 已完成，做得很好。")
                                        }) { Text("本组完成") }
                                    }
                                    Text("家长记录用于确认实际完成量；摄像头仅显示待验证的辅助计数，不作为准确率或标准动作证明。", color = Color.Gray, fontSize = 16.sp)
                                }
                            }
                        }
                        Text("家长陪同提示：保持镜头稳定、留出安全距离；孩子疲劳、疼痛或头晕时马上暂停。跟做数据只用于健康习惯记录，不构成医疗诊断。", color = Navy, fontSize = 16.sp, modifier = Modifier.fillMaxWidth().background(Blue.copy(alpha = .08f), RoundedCornerShape(14.dp)).padding(16.dp))
                    }
                }
                if (day.exercises.isNotEmpty()) {
                    if (completed) {
                        val total = day.exercises.sumOf { exerciseProgress[it.id] ?: 0 }
                        val sessionQualityScore = exerciseQualityScores.values.takeIf { it.isNotEmpty() }?.average()?.roundToInt() ?: 0
                        Surface(color = Green.copy(alpha = .10f), shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth().padding(14.dp).scale(completionScale)) {
                            Column(Modifier.padding(15.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Filled.SupervisedUserCircle, null, tint = Green, modifier = Modifier.size(24.dp))
                                    Spacer(Modifier.width(8.dp))
                                    Text("本次训练已由家长确认", color = Navy, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                }
                                    Text("已记录 $total 个动作单位（辅助识别 ${visualUnits.values.sum()}，家长补录 $manualUnits）。辅助识别尚未通过人工标注验证，不作为标准动作评分。", color = Color.Gray, fontSize = 16.sp)
                                Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Green)) { Text("返回 28 天计划") }
                            }
                        }
                    } else {
                        Button(
                            onClick = {
                                if (isPlanComplete(day, exerciseProgress)) {
                                    completed = true
                                    saveSession()
                                    onComplete()
                                    if (speakerEnabled) coach.say("本次训练已按家长确认保存。")
                                } else {
                                    showPartialCompletionAlert = true
                                }
                            },
                            modifier = Modifier.fillMaxWidth().padding(14.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = Green)
                        ) { Icon(Icons.Filled.CheckCircle, null); Spacer(Modifier.width(7.dp)); Text("完成今日跟做") }
                    }
                }
            }
        }
    }
    if (showPartialCompletionAlert) {
        AlertDialog(
            onDismissRequest = { showPartialCompletionAlert = false },
            confirmButton = {
                TextButton(onClick = {
                    showPartialCompletionAlert = false
                    completed = true
                    saveSession()
                    onComplete()
                    if (speakerEnabled) coach.say("本次训练已按家长确认保存。")
                }) { Text("结束并保存") }
            },
            dismissButton = { TextButton(onClick = { showPartialCompletionAlert = false }) { Text("继续训练") } },
            title = { Text("还有动作未完成") },
            text = { Text("当前只记录已完成的动作，确定现在结束本次跟做吗？") }
        )
    }
    cameraMessage?.let { message ->
        AlertDialog(onDismissRequest = { cameraMessage = null }, confirmButton = { TextButton(onClick = { cameraMessage = null }) { Text("知道了") } }, title = { Text("相机暂不可用") }, text = { Text(message) })
    }

}

@Composable
private fun RecoveryCard(onComplete: () -> Unit) {
    Surface(color = Color.White, shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.Bedtime, null, tint = Blue, modifier = Modifier.size(34.dp))
            Text("今天是恢复日", color = Navy, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            Text("做 5 分钟轻松呼吸、肩背舒展和户外散步即可。让身体恢复，是训练计划的一部分。", color = Color.Gray, fontSize = 15.sp)
            Button(onClick = onComplete, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Green)) { Text("记录今天已恢复") }
        }
    }
}

@Composable
private fun FollowAlongGuideCard(
    poseFeedback: FollowAlongPoseFeedback,
    exercise: FollowAlongExercise?,
    templateBeat: Int = 1
) {
    Surface(
        color = Blue.copy(alpha = .07f),
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = "动作引导。${poseFeedback.message}。请竖屏、保持全身远景并静止两秒完成准备。"
            }
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (poseFeedback.visible) Icons.Filled.VerifiedUser else Icons.Filled.CenterFocusStrong,
                    null,
                    tint = if (poseFeedback.visible) Green else Blue,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(7.dp))
                Text(
                    if (poseFeedback.captureState == FollowAlongCaptureState.Ready) "取景已就绪，跟随语音完成动作" else poseFeedback.captureState.label,
                    color = Navy,
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp,
                    modifier = Modifier.weight(1f)
                )
                Text(if (poseFeedback.captureState == FollowAlongCaptureState.Ready) "已连接" else "需调整", color = if (poseFeedback.captureState == FollowAlongCaptureState.Ready) Green else Color.Gray, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            }
            Text(poseFeedback.message, color = Color.Gray, fontSize = 16.sp, maxLines = 2)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
                FollowAlongStage.values().forEach { stage ->
                    Surface(color = if (poseFeedback.stage == stage) Blue else Blue.copy(alpha = .10f), shape = RoundedCornerShape(50), modifier = Modifier.weight(1f)) {
                        Text(stage.label, color = if (poseFeedback.stage == stage) Color.White else Navy, fontSize = 16.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(vertical = 6.dp).fillMaxWidth())
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("动作范围", color = Navy, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.width(6.dp))
                LinearProgressIndicator(progress = { poseFeedback.rangePercent / 100f }, modifier = Modifier.weight(1f), color = if (poseFeedback.rangePercent >= 70) Green else Blue)
                Spacer(Modifier.width(6.dp))
                Text("${poseFeedback.rangePercent}% · ${poseFeedback.side.label}", color = Blue, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            }
            Text(if (poseFeedback.tempoScore > 0) "节奏匹配 ${poseFeedback.tempoScore}% · 跟随示范停顿后再回位" else "先完成一整次动作，系统会校准你的节奏", color = Color.Gray, fontSize = 16.sp)
            exercise?.let { Text("模板第 $templateBeat 拍 · ${"%.1f".format(Locale.US, it.cadenceSeconds)} 秒/拍 · 实时节拍同步", color = Blue, fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
                GuideStep(number = "1", title = "竖屏", detail = "手机稳定", modifier = Modifier.weight(1f))
                GuideStep(number = "2", title = "全身", detail = "头肩髋脚", modifier = Modifier.weight(1f))
                GuideStep(number = "3", title = "准备", detail = "保持 2 秒", modifier = Modifier.weight(1f))
            }
            exercise?.let {
                Row(verticalAlignment = Alignment.Top) {
                    Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, tint = Navy, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("当前动作：${it.title} · ${it.cue}", color = Navy, fontSize = 16.sp, maxLines = 2)
                }
            }
        }
    }
}

@Composable
private fun GuideStep(number: String, title: String, detail: String, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Surface(color = Blue, shape = androidx.compose.foundation.shape.CircleShape, modifier = Modifier.size(18.dp)) {
            Box(contentAlignment = Alignment.Center) {
                Text(number, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            }
        }
        Spacer(Modifier.width(4.dp))
        Column {
            Text(title, color = Navy, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            Text(detail, color = Color.Gray, fontSize = 16.sp)
        }
    }
}

private fun isPlanComplete(day: FollowAlongDay, progress: Map<String, Int>): Boolean =
    day.exercises.all { (progress[it.id] ?: 0) >= it.target }

private class FollowAlongVoiceCoach(context: Context) : TextToSpeech.OnInitListener {
    private val engine = TextToSpeech(context, this)
    private var ready = false
    override fun onInit(status: Int) { ready = status == TextToSpeech.SUCCESS; if (ready) engine.language = Locale.CHINA }
    fun say(message: String) { if (ready) engine.speak(message, TextToSpeech.QUEUE_FLUSH, null, "follow-along-coach") }
    fun stop() { engine.stop() }
    fun close() { engine.stop(); engine.shutdown() }
}

@Composable
private fun rememberFollowAlongCoach(context: Context) = remember { FollowAlongVoiceCoach(context.applicationContext) }
