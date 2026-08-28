package com.xiangshang.youth.feature.parent

import android.content.Context
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.pose.PoseDetector
import com.xiangshang.youth.core.model.BodyCaptureTask
import java.util.concurrent.ExecutorService

/** Stable UI-facing camera binding; analysis lives in the dedicated engine. */
internal fun bindLiveCamera(
    context: Context,
    lifecycleOwner: LifecycleOwner,
    previewView: PreviewView,
    front: Boolean,
    task: BodyCaptureTask,
    measuredHeightCm: Double,
    detector: PoseDetector,
    onPrompt: (String) -> Unit,
    onProgress: (Float) -> Unit,
    onReady: (Boolean) -> Unit,
    onAlignment: (CaptureBodyAlignment) -> Unit,
    onFailure: (String) -> Unit,
    onComplete: (CaptureAnalysis) -> Unit,
    analysisExecutor: ExecutorService,
    childAgeMonths: Int?,
    isCurrent: () -> Boolean,
    isCaptureArmed: () -> Boolean
) = bindLiveCameraEngine(
    context = context,
    lifecycleOwner = lifecycleOwner,
    previewView = previewView,
    front = front,
    task = task,
    measuredHeightCm = measuredHeightCm,
    detector = detector,
    onPrompt = onPrompt,
    onProgress = onProgress,
    onReady = onReady,
    onAlignment = onAlignment,
    onFailure = onFailure,
    onComplete = onComplete,
    analysisExecutor = analysisExecutor,
    childAgeMonths = childAgeMonths,
    isCurrent = isCurrent,
    isCaptureArmed = isCaptureArmed
)
