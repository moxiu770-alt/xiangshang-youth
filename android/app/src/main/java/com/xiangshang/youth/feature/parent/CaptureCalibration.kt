package com.xiangshang.youth.feature.parent

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material.icons.filled.AccessibilityNew
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiangshang.youth.core.model.BodyCaptureQualityGate
import com.xiangshang.youth.core.model.BodyCaptureTask
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.sqrt

data class CaptureDeviceAlignment(
    val rollDegrees: Double = 0.0,
    val pitchDegrees: Double = 0.0,
    val available: Boolean = false
) {
    val isLevel: Boolean get() = available && abs(rollDegrees) <= CaptureCalibrationRules.maximumRollDegrees && abs(pitchDegrees) <= CaptureCalibrationRules.maximumPitchDegrees
}

data class CaptureBodyAlignment(
    val bodyDetected: Boolean = false,
    val distanceState: BodyCaptureQualityGate.BodyScaleState = BodyCaptureQualityGate.BodyScaleState.Invalid,
    val centered: Boolean = false,
    val headReady: Boolean = false,
    val shouldersReady: Boolean = false,
    val hipsReady: Boolean = false,
    val kneesReady: Boolean = false,
    val feetReady: Boolean = false
) {
    val distanceReady: Boolean get() = distanceState == BodyCaptureQualityGate.BodyScaleState.Ready
    val isReady: Boolean get() = bodyDetected && distanceReady && centered && headReady && shouldersReady && hipsReady && kneesReady && feetReady
}

object CaptureCalibrationRules {
    /** Initial commercial fixed-pose capture bounds. They gate collection;
     * they do not make a medical or accuracy claim. */
    const val maximumRollDegrees = 2.0
    const val maximumPitchDegrees = 5.0

    fun deviceAlignment(gravityX: Double, gravityY: Double, gravityZ: Double): CaptureDeviceAlignment {
        if (!listOf(gravityX, gravityY, gravityZ).all(Double::isFinite)) return CaptureDeviceAlignment()
        val magnitude = sqrt(gravityX * gravityX + gravityY * gravityY + gravityZ * gravityZ)
        if (magnitude < .5) return CaptureDeviceAlignment()
        val x = gravityX / magnitude
        val y = gravityY / magnitude
        val z = gravityZ / magnitude
        val roll = Math.toDegrees(atan2(x, y))
        val pitch = Math.toDegrees(atan2(z, hypot(x, y).coerceAtLeast(.001)))
        return CaptureDeviceAlignment(roll, pitch, true)
    }
}

@Composable
fun rememberCaptureDeviceAlignment(): State<CaptureDeviceAlignment> {
    val context = LocalContext.current
    val state = remember { mutableStateOf(CaptureDeviceAlignment()) }
    DisposableEffect(context) {
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensor = manager.getDefaultSensor(Sensor.TYPE_GRAVITY) ?: manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val next = CaptureCalibrationRules.deviceAlignment(event.values[0].toDouble(), event.values[1].toDouble(), event.values[2].toDouble())
                if (!next.available) return
                val old = state.value
                state.value = if (old.available) {
                    CaptureDeviceAlignment(old.rollDegrees * .72 + next.rollDegrees * .28, old.pitchDegrees * .72 + next.pitchDegrees * .28, true)
                } else next
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        if (sensor != null) manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
        onDispose { manager.unregisterListener(listener) }
    }
    return state
}

@Composable
fun CaptureHumanCalibrationGuide(task: BodyCaptureTask, body: CaptureBodyAlignment, device: CaptureDeviceAlignment, recording: Boolean) {
    BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val guideWidth = minOf(maxWidth * if (task == BodyCaptureTask.FootArch) .78f else .66f, if (task == BodyCaptureTask.Seated) 280.dp else 300.dp)
        val guideHeight = minOf(maxHeight * .46f, if (task == BodyCaptureTask.FootArch || task == BodyCaptureTask.Seated) 300.dp else 430.dp)
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.offset(y = (-42).dp)) {
            DeviceLevelBubble(device)
            Canvas(
                Modifier
                    .width(guideWidth)
                    .height(guideHeight)
                    .alpha(if (recording) .42f else 1f)
                    .semantics { contentDescription = if (task == BodyCaptureTask.FootArch) "足部近景框，${if (body.isReady) "已经对齐" else "等待膝踝足跟对齐"}" else "人体对齐框，${if (body.isReady) "已经对齐" else "等待头肩髋脚对齐"}" }
            ) {
                val base = if (body.isReady) Color(0xFF28C76F) else Color.White.copy(alpha = .84f)
                if (task == BodyCaptureTask.FootArch) {
                    val lk = Offset(size.width * .34f, size.height * .14f); val rk = Offset(size.width * .66f, size.height * .14f)
                    val la = Offset(size.width * .36f, size.height * .72f); val ra = Offset(size.width * .64f, size.height * .72f)
                    val lh = Offset(size.width * .31f, size.height * .84f); val rh = Offset(size.width * .59f, size.height * .84f)
                    val lt = Offset(size.width * .47f, size.height * .90f); val rt = Offset(size.width * .75f, size.height * .90f)
                    fun footLine(a: Offset, b: Offset, ready: Boolean) = drawLine(if (ready) Color(0xFF28C76F) else base, a, b, 5.dp.toPx(), StrokeCap.Round)
                    drawRoundRect(if (body.distanceReady) Color(0xFF28C76F) else Color.White.copy(alpha = .72f), style = Stroke(2.dp.toPx()), cornerRadius = androidx.compose.ui.geometry.CornerRadius(34.dp.toPx()))
                    footLine(lk, la, body.kneesReady); footLine(rk, ra, body.kneesReady)
                    footLine(la, lh, body.feetReady); footLine(lh, lt, body.feetReady)
                    footLine(ra, rh, body.feetReady); footLine(rh, rt, body.feetReady)
                    listOf(lk, rk, la, ra, lh, rh, lt, rt).forEach { point -> drawCircle(if (body.isReady) Color(0xFF28C76F) else Color(0xFFFFD54F), 6.dp.toPx(), point) }
                } else {
                val showsAdamsPose = task == BodyCaptureTask.ForwardBend && recording
                val shoulderY = when {
                    task == BodyCaptureTask.Seated -> size.height * .38f
                    showsAdamsPose -> size.height * .49f
                    else -> size.height * .30f
                }
                val hipY = if (task == BodyCaptureTask.Seated) size.height * .68f else size.height * .55f
                val head = Offset(size.width * .5f, size.height * when {
                    task == BodyCaptureTask.Seated -> .20f
                    showsAdamsPose -> .43f
                    else -> .12f
                })
                val ls = Offset(size.width * .34f, shoulderY); val rs = Offset(size.width * .66f, shoulderY)
                val lh = Offset(size.width * .42f, hipY); val rh = Offset(size.width * .58f, hipY)
                val isAdams = task == BodyCaptureTask.ForwardBend
                val lk = Offset(size.width * if (isAdams) .47f else .40f, size.height * if (task == BodyCaptureTask.Seated) .82f else .73f)
                val rk = Offset(size.width * if (isAdams) .53f else .60f, size.height * if (task == BodyCaptureTask.Seated) .82f else .73f)
                val lf = Offset(size.width * if (isAdams) .47f else .39f, size.height * .91f); val rf = Offset(size.width * if (isAdams) .53f else .61f, size.height * .91f)
                fun line(a: Offset, b: Offset, ready: Boolean) = drawLine(if (ready) Color(0xFF28C76F) else base, a, b, 3.dp.toPx(), StrokeCap.Round)
                drawRoundRect(if (body.distanceReady) Color(0xFF28C76F) else Color.White.copy(alpha = .72f), style = Stroke(2.dp.toPx()), cornerRadius = androidx.compose.ui.geometry.CornerRadius(34.dp.toPx()))
                drawCircle(if (body.headReady) Color(0xFF28C76F) else base, size.minDimension * .07f, head, style = Stroke(3.dp.toPx()))
                line(Offset(size.width * .5f, head.y + size.height * if (showsAdamsPose) .025f else .07f), Offset(size.width * .5f, hipY), body.centered)
                line(ls, rs, body.shouldersReady)
                line(ls, Offset(size.width * if (isAdams) .49f else .24f, size.height * if (isAdams && showsAdamsPose) .70f else .50f), body.shouldersReady)
                line(rs, Offset(size.width * if (isAdams) .51f else .76f, size.height * if (isAdams && showsAdamsPose) .70f else .50f), body.shouldersReady)
                line(lh, rh, body.hipsReady)
                if (task == BodyCaptureTask.Seated) {
                    line(lh, Offset(size.width * .35f, size.height * .88f), false)
                    line(rh, Offset(size.width * .65f, size.height * .88f), false)
                } else {
                    line(lh, lk, body.kneesReady); line(rh, rk, body.kneesReady)
                    line(lk, lf, body.feetReady); line(rk, rf, body.feetReady)
                }
                listOf(head to body.headReady, ls to body.shouldersReady, rs to body.shouldersReady, lh to body.hipsReady, rh to body.hipsReady, lk to body.kneesReady, rk to body.kneesReady, lf to body.feetReady, rf to body.feetReady).forEach { (point, ready) ->
                    drawCircle(if (ready) Color(0xFF28C76F) else Color(0xFFFFD54F), 5.dp.toPx(), point)
                }
                }
            }
            Surface(color = Color.Black.copy(alpha = .52f), shape = RoundedCornerShape(50)) {
                Text(
                    if (task == BodyCaptureTask.FootArch) {
                        if (recording) "正在记录足部近景：保持双脚平行站稳" else "仅将双膝以下、双踝、足跟和双脚放入近景框"
                    } else if (recording) {
                        if (task == BodyCaptureTask.ForwardBend) "对准前屈轮廓：双脚并拢、双膝伸直、头部放松" else "正在记录：保持手机固定，按语音完成动作"
                    } else "将头、肩、髋、膝和双脚对准标定点",
                    color = if (body.isReady) Color(0xFF55E392) else Color.White,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp)
                )
            }
        }
    }
}

@Composable
private fun DeviceLevelBubble(alignment: CaptureDeviceAlignment) {
    Surface(color = Color.Black.copy(alpha = .52f), shape = RoundedCornerShape(50)) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(34.dp).background(Color.White.copy(alpha = .10f), CircleShape), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    drawLine(Color.White.copy(alpha = .45f), Offset(size.width / 2, 3f), Offset(size.width / 2, size.height - 3f), 1f)
                    drawLine(Color.White.copy(alpha = .45f), Offset(3f, size.height / 2), Offset(size.width - 3f, size.height / 2), 1f)
                    drawCircle(
                        if (alignment.isLevel) Color(0xFF28C76F) else Color(0xFFFFD54F),
                        4.5.dp.toPx(),
                        Offset(size.width / 2 + alignment.rollDegrees.coerceIn(-10.0, 10.0).toFloat() * 1.2f, size.height / 2 + alignment.pitchDegrees.coerceIn(-10.0, 10.0).toFloat() * 1.2f)
                    )
                }
            }
            Column {
                Text(if (alignment.isLevel) "手机角度已校正" else "请调平手机", color = Color.White, fontSize = 13.sp)
                Text(if (alignment.available) "左右 ${alignment.rollDegrees.toInt()}° · 前后 ${alignment.pitchDegrees.toInt()}°" else "正在读取陀螺仪", color = Color.White.copy(alpha = .72f), fontSize = 12.sp)
            }
        }
    }
}

@Composable
fun CaptureCalibrationStatusRow(cameraReady: Boolean, deviceReady: Boolean, bodyReady: Boolean) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        CalibrationStatusItem("相机", cameraReady, Modifier.weight(1f), true)
        CalibrationStatusItem("手机角度", deviceReady, Modifier.weight(1f), false)
        CalibrationStatusItem("人体对齐", bodyReady, Modifier.weight(1f), false)
    }
}

@Composable
private fun CalibrationStatusItem(title: String, ready: Boolean, modifier: Modifier, camera: Boolean) {
    val icon = if (ready) Icons.Filled.CheckCircle else if (camera) Icons.Filled.CameraAlt else if (title == "手机角度") Icons.Filled.ScreenRotation else Icons.Filled.AccessibilityNew
    Row(modifier.heightIn(min = 32.dp).background(Color.White.copy(alpha = .07f), RoundedCornerShape(50)).padding(horizontal = 7.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        Icon(icon, null, tint = if (ready) Color(0xFF55E392) else Color.White.copy(alpha = .72f), modifier = Modifier.size(15.dp))
        Spacer(Modifier.width(3.dp)); Text(title, color = if (ready) Color(0xFF55E392) else Color.White.copy(alpha = .72f), fontSize = 12.sp)
    }
}
