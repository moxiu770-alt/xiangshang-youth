package com.xiangshang.youth.core.util

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Canonical business clock for records shared with the school backend.
 *
 * Dates such as check-ins, assessment receipts and growth windows are a
 * school-day concept, not the device's current timezone. Keep the formatter
 * short-lived because SimpleDateFormat is mutable and not thread-safe.
 */
object BusinessClock {
    const val timeZoneId = "Asia/Shanghai"
    val timeZone: TimeZone = TimeZone.getTimeZone(timeZoneId)

    fun format(pattern: String, date: Date = Date()): String =
        SimpleDateFormat(pattern, Locale.US).apply {
            isLenient = false
            timeZone = BusinessClock.timeZone
        }.format(date)

    fun day(date: Date = Date()): String = format("yyyy-MM-dd", date)
}
