package com.xiangshang.youth.feature.parent

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.SystemClock
import android.provider.Settings
import android.speech.tts.TextToSpeech
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions
import com.xiangshang.youth.core.model.BodyCaptureQualityGate
import com.xiangshang.youth.core.model.BodyCaptureTask
import com.xiangshang.youth.core.model.PostureMetricCalculator
import com.xiangshang.youth.core.model.PostureMetricSnapshot
import com.xiangshang.youth.core.model.SpineScreeningStandard
import java.util.ArrayDeque
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Full-screen camera guidance. Frames stay in memory and are never recorded. */
@Composable
fun LivePostureCaptureDialog(
    task: BodyCaptureTask,
    measuredHeightCm: Double,
    childAgeMonths: Int?,
    voiceGuidanceEnabled: Boolean = true,
    onVoiceGuidanceChanged: (Boolean) -> Unit = {},
    onComplete: (CaptureAnalysis) -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    var permitted by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    var permissionRequestInFlight by remember { mutableStateOf(false) }
    var permissionResolved by remember { mutableStateOf(permitted) }

    val requestCamera = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        permitted = granted
        permissionRequestInFlight = false
        permissionResolved = true
    }

    LaunchedEffect(Unit) {
        if (!permitted && !permissionResolved && !permissionRequestInFlight) {
            permissionRequestInFlight = true
            requestCamera.launch(Manifest.permission.CAMERA)
        }
    }

    if (!permitted) {
        // While Android's native prompt owns focus, keep this composable blank
        // instead of stacking another dialog behind it.
        if (permissionRequestInFlight || !permissionResolved) return

        AlertDialog(
            onDismissRequest = onDismiss,
            confirmButton = {
                TextButton(
                    onClick = {
                        context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                    }
                ) { Text("前往设置") }
            },
            dismissButton = {
                TextButton(onClick = onDismiss) { Text("暂不使用") }
            },
            title = { Text("需要相机权限") },
            text = { Text("拍摄记录在 App 内完成；请在系统设置中允许相机后返回重试。") }
        )
        return
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        LiveCaptureContent(task, measuredHeightCm, childAgeMonths, voiceGuidanceEnabled, onVoiceGuidanceChanged, onComplete, onDismiss)
    }
}

@Composable
private fun LiveCaptureContent(
    task: BodyCaptureTask,
    measuredHeightCm: Double,
    childAgeMonths: Int?,
    voiceGuidanceEnabled: Boolean,
    onVoiceGuidanceChanged: (Boolean) -> Unit,
    onComplete: (CaptureAnalysis) -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var front by remember { mutableStateOf(false) }
    var prompt by remember { mutableStateOf("正在启动相机…") }
    var previewView by remember { mutableStateOf<PreviewView?>(null) }
    var speakerEnabled by remember(task, voiceGuidanceEnabled) { mutableStateOf(voiceGuidanceEnabled) }
    var captureProgress by remember { mutableFloatStateOf(0f) }
    var captureArmed by remember { mutableStateOf(false) }
    var bodyAlignment by remember { mutableStateOf(CaptureBodyAlignment()) }
    val deviceAlignment by rememberCaptureDeviceAlignment()
    // The analyzer runs on a worker thread, so it reads this atomic mirror
    // instead of reading Compose snapshot state off main thread.
    val captureArmedRef = remember { AtomicBoolean(false) }
    // CameraX binding is asynchronous. A capture may start only after the
    // selected lens has actually become live, never against prior lens.
    var cameraReady by remember { mutableStateOf(false) }
    var lastPromptSpokenAt by remember { mutableLongStateOf(0L) }
    var cameraError by remember { mutableStateOf<String?>(null) }
    // Front camera remains available for parent guidance only. A formal
    // record must be made by the rear 1× camera according to the protocol.
    val calibrationReady = !front && cameraReady && deviceAlignment.isLevel && bodyAlignment.isReady
    val capturePhaseIndex = when {
        !captureArmed || captureProgress < .25f -> 0
        captureProgress < .85f -> 1
        else -> 2
    }

    val mainExecutor = remember(context) { ContextCompat.getMainExecutor(context) }
    val coach = rememberVoiceCoach(context)
    val detector = remember {
        PoseDetection.getClient(AccuratePoseDetectorOptions.Builder().setDetectorMode(AccuratePoseDetectorOptions.STREAM_MODE).build())
    }
    val cameraEpoch = remember { AtomicInteger(0) }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }

    LaunchedEffect(task, speakerEnabled) {
        if (speakerEnabled) {
            val number = SpineScreeningStandard.homeCameraItems.firstOrNull { it.task == task }?.number ?: 1
            coach.say("开始第${number}项，${task.title}。${task.guide}。${SpineScreeningStandard.mainCameraPlacement}。")
        }
    }

    LaunchedEffect(prompt, speakerEnabled) {
        val now = SystemClock.elapsedRealtime()
        if (speakerEnabled && prompt.startsWith("请") && now - lastPromptSpokenAt >= 2_200L) {
            lastPromptSpokenAt = now
            coach.say(prompt)
        }
    }

    LaunchedEffect(front, task) {
        captureArmed = false
        captureArmedRef.set(false)
        captureProgress = 0f
        cameraReady = false
        bodyAlignment = CaptureBodyAlignment()
    }

    LaunchedEffect(deviceAlignment) {
        if (!deviceAlignment.available || deviceAlignment.isLevel) return@LaunchedEffect
        if (captureArmed) {
            captureArmed = false
            captureArmedRef.set(false)
            captureProgress = 0f
            prompt = "手机角度发生变化，记录已暂停。请重新调平手机并完成人体对齐。"
            if (speakerEnabled) coach.say("手机角度发生变化，记录已暂停，请重新调平手机。")
        } else {
            prompt = "请先调平手机：左右不超过 2 度，前后不超过 5 度。"
        }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE || event == Lifecycle.Event.ON_STOP) {
                if (captureArmed) {
                    captureArmed = false
                    captureArmedRef.set(false)
                    captureProgress = 0f
                    prompt = "记录已暂停，返回后请确认动作并重新开始。"
                }
                cameraReady = false
                coach.stop()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    // Rebind only when the camera facing or preview changes. Guidance
    // updates should not restart the entire camera pipeline.
    LaunchedEffect(previewView, front, task, lifecycleOwner) {
        val epoch = cameraEpoch.incrementAndGet()
        previewView?.let {
            bindLiveCamera(
                context,
                lifecycleOwner,
                it,
                front,
                task,
                measuredHeightCm,
                detector,
                { text -> mainExecutor.execute { if (cameraEpoch.get() == epoch) prompt = text } },
                { value -> mainExecutor.execute { if (cameraEpoch.get() == epoch) captureProgress = value } },
                { ready -> mainExecutor.execute { if (cameraEpoch.get() == epoch) cameraReady = ready } },
                { alignment -> mainExecutor.execute { if (cameraEpoch.get() == epoch) bodyAlignment = alignment } },
                { message -> mainExecutor.execute { if (cameraEpoch.get() == epoch) cameraError = message } },
                { result -> mainExecutor.execute { if (cameraEpoch.get() == epoch) onComplete(result) } },
                analysisExecutor,
                childAgeMonths,
                isCurrent = { cameraEpoch.get() == epoch },
                isCaptureArmed = { captureArmedRef.get() }
            )
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            cameraEpoch.incrementAndGet()
            coach.close()
            detector.close()
            analysisExecutor.shutdownNow()
            val providerFuture = ProcessCameraProvider.getInstance(context)
            providerFuture.addListener(
                { runCatching { providerFuture.get().unbindAll() } },
                ContextCompat.getMainExecutor(context)
            )
        }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { viewContext ->
                PreviewView(viewContext).apply {
                    // Preserve the complete camera frame instead of cropping it
                    // into a visually enlarged close-up.
                    scaleType = PreviewView.ScaleType.FIT_CENTER
                    previewView = this
                }
            },
            modifier = Modifier.fillMaxSize()
        )

        CaptureHumanCalibrationGuide(task, bodyAlignment, deviceAlignment, captureArmed)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(20.dp)
                .then(if (cameraError == null) Modifier else Modifier.zIndex(-1f)),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                CircleIcon(Icons.Filled.Close, "关闭") { onDismiss() }
                Row {
                    CircleIcon(
                        if (speakerEnabled) Icons.AutoMirrored.Filled.VolumeUp else Icons.AutoMirrored.Filled.VolumeOff,
                        if (speakerEnabled) "关闭语音指导" else "开启语音指导"
                    ) {
                        speakerEnabled = !speakerEnabled
                        onVoiceGuidanceChanged(speakerEnabled)
                        if (!speakerEnabled) coach.stop()
                    }
                    Spacer(Modifier.width(8.dp))
                    CircleIcon(Icons.Filled.Cameraswitch, if (front) "切换后置" else "切换前置") {
                        captureArmed = false
                        captureArmedRef.set(false)
                        captureProgress = 0f
                        cameraReady = false
                        bodyAlignment = CaptureBodyAlignment()
                        front = !front
                    }
                }
            }

            Surface(color = Color.Black.copy(alpha = 0.58f), shape = RoundedCornerShape(20.dp), modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(task.title, color = Color.White, style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                    Text(task.guide, color = Color.White, fontSize = 14.sp)
                    Spacer(Modifier.height(6.dp))
                    Text(
                        when (task) {
                            BodyCaptureTask.GaitVideo -> "后置主摄固定机位 · 3 米直线自然往返 1 次"
                            BodyCaptureTask.FootArch -> SpineScreeningStandard.footCameraPlacement
                            else -> "后置 1× 主摄 · ${SpineScreeningStandard.mainCameraPlacement}"
                        },
                        color = Color.White.copy(alpha = .76f),
                        fontSize = 12.sp
                    )
                    Spacer(Modifier.height(8.dp))
                    if (captureArmed) {
                        CapturePhaseRow(task, capturePhaseIndex)
                    } else {
                        CaptureCalibrationStatusRow(cameraReady, deviceAlignment.isLevel, bodyAlignment.isReady)
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(prompt, color = Color(0xFFFFD54F), fontSize = 12.sp)
                    Spacer(Modifier.height(10.dp))
                    LinearProgressIndicator(progress = { captureProgress }, modifier = Modifier.fillMaxWidth(), color = Color(0xFFFFD54F), trackColor = Color.White.copy(alpha = 0.24f))
                    Text(
                        if (!cameraReady) "正在连接所选摄像头…"
                        else if (captureArmed) {
                            if (captureProgress == 0f) "正在确认取景与画面完整性" else "记录稳定度 ${(captureProgress * 100).toInt()}%"
                        } else {
                            "请先完成取景，再开始记录"
                        },
                        color = Color.White.copy(alpha = 0.72f),
                        fontSize = 12.sp,
                        modifier = Modifier.padding(top = 5.dp)
                    )
                    Spacer(Modifier.height(9.dp))
                    if (captureArmed) {
                        Text(
                            if (task == BodyCaptureTask.ForwardBend) "正在识别前屈，请完成动作后保持" else "正在记录，请保持当前姿势",
                            color = Color(0xFFFFD54F),
                            fontSize = 12.sp
                        )
                    } else {
                        Button(
                            onClick = {
                                if (!calibrationReady) return@Button
                                captureProgress = 0f
                                captureArmed = true
                                captureArmedRef.set(true)
                                if (speakerEnabled) coach.say(
                                    if (task == BodyCaptureTask.ForwardBend) {
                                        "开始记录。双脚并拢，膝关节完全伸直，双手合十自然下垂，缓慢向前弯腰至躯干接近水平，头部自然放松，不要屈膝或做弓步。"
                                    } else {
                                        "开始记录，请保持当前姿势。"
                                    }
                                )
                            },
                            enabled = calibrationReady,
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFFD54F), contentColor = Color.Black)
                        ) {
                            Text(
                                when {
                                    calibrationReady -> "引导质量门已通过，开始记录"
                                    !cameraReady -> "正在连接相机"
                                    front -> "正式记录请切回后置主摄"
                                    !deviceAlignment.isLevel -> "请将左右调至 2°、前后调至 5°内"
                                    !bodyAlignment.bodyDetected -> "请进入人型框"
                                    !bodyAlignment.distanceReady -> "请调整拍摄距离"
                                    else -> "请对齐头肩髋膝脚"
                                }
                            )
                        }
                    }
                    Text("App 内实时记录，不保存照片或视频", color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp))
                }
            }
        }

        cameraError?.let { message ->
            Surface(
                color = Color(0xFFFDFDFF),
                shape = RoundedCornerShape(24.dp),
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(30.dp)
                    .zIndex(2f)
            ) {
                Column(Modifier.padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Filled.Cameraswitch, null, tint = Color(0xFFFFB000))
                    Spacer(Modifier.height(10.dp))
                    Text("暂时无法启动相机", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(7.dp))
                    Text(message, color = Color.Gray, fontSize = 13.sp)
                    Spacer(Modifier.height(16.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedButton(onClick = onDismiss) { Text("暂不使用") }
                        Button(onClick = {
                            cameraError = null
                            captureArmed = false
                            captureArmedRef.set(false)
                            captureProgress = 0f
                            cameraReady = false
                            front = !front
                        }) { Text("重试") }
                    }
                }
            }
        }
    }
}

@Composable
private fun CircleIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, description: String, click: () -> Unit) =
    IconButton(onClick = click, modifier = Modifier.background(Color.Black.copy(alpha = 0.42f), CircleShape)) {
        Icon(icon, description, tint = Color.White)
    }

@Composable
private fun CapturePhaseRow(task: BodyCaptureTask, phaseIndex: Int) {
    val labels = when (task) {
        BodyCaptureTask.ForwardBend -> listOf("起始位", "前屈位", "完成")
        BodyCaptureTask.DynamicKneeControl -> listOf("站稳", "下蹲", "回位")
        BodyCaptureTask.StandingSide -> listOf("左侧", "右侧", "完成")
        BodyCaptureTask.FootArch -> listOf("左足", "右足", "完成")
        else -> listOf("站稳", "保持", "完成")
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        labels.forEachIndexed { index, label ->
            Surface(
                color = Color.White.copy(alpha = if (index == phaseIndex) .12f else .05f),
                shape = RoundedCornerShape(50),
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    text = when {
                        index < phaseIndex -> "✓ $label"
                        index == phaseIndex -> "● $label"
                        else -> "○ $label"
                    },
                    color = if (index <= phaseIndex) Color(0xFFFFD54F) else Color.White.copy(alpha = .52f),
                    fontSize = 12.sp,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 7.dp)
                )
            }
        }
    }
}
