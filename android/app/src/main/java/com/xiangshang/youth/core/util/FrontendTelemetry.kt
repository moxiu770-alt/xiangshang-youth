package com.xiangshang.youth.core.util

import android.util.Log
import com.xiangshang.youth.BuildConfig
import com.xiangshang.youth.core.service.ApiClient
import com.xiangshang.youth.core.service.ProductEventApi
import com.xiangshang.youth.core.service.ProductEventBatch
import com.xiangshang.youth.core.service.ProductEventInput
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID

enum class FrontendEvent(val wireName: String) {
    GrowthReportOpened("growth_report_opened"),
    GrowthReportPeriodChanged("growth_report_period_changed"),
    AdaptivePlanOpenedCourses("adaptive_plan_opened_courses")
}

/**
 * Privacy-safe event boundary. Values must be coarse UI states and must never
 * include student ids, names, phone numbers or health measurements.
 */
object FrontendTelemetry {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val clientSessionId = UUID.randomUUID().toString()
    @Volatile private var enabled = false

    fun configure(enabled: Boolean) { this.enabled = enabled }

    fun record(event: FrontendEvent, value: String? = null) {
        if (!enabled) return
        val coarse = value?.takeIf { it == "本周" || it == "本月" }
        Log.i("XiangshangEvents", "event=${event.wireName} value=${coarse ?: "none"}")
        val item = ProductEventInput(
            UUID.randomUUID().toString(), event.wireName, coarse, "android",
            BuildConfig.VERSION_NAME, clientSessionId, Instant.now().toString()
        )
        // Product analytics is non-critical: it cannot block or mutate a
        // family, teacher, report, assessment or training workflow.
        scope.launch {
            runCatching { ApiClient.retrofit.create(ProductEventApi::class.java).submit(ProductEventBatch(listOf(item))) }
        }
    }
}
