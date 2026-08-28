package com.xiangshang.youth.feature.parent

import com.xiangshang.youth.core.model.PostureMetricSnapshot

data class CaptureAnalysis(
    val accepted: Boolean,
    val message: String,
    val observationHint: String? = null,
    val postureSnapshot: PostureMetricSnapshot? = null
)
