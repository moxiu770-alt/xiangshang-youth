package com.xiangshang.youth.core.util

import android.util.Log

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
    fun record(event: FrontendEvent, value: String? = null) {
        Log.i("XiangshangEvents", "event=${event.wireName} value=${value ?: "none"}")
    }
}
