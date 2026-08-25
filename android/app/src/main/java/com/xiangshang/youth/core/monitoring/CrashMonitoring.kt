package com.xiangshang.youth.core.monitoring

import android.content.Context
import com.xiangshang.youth.BuildConfig
import io.sentry.Sentry
import io.sentry.android.core.SentryAndroid

/**
 * Production crash boundary. The Sentry DSN is injected at build time by CI,
 * never stored in source. With the default blank DSN this class is a strict
 * no-op, which keeps local builds and student data entirely on-device.
 */
object CrashMonitoring {
    @Volatile private var enabled = false

    fun initialize(context: Context) {
        if (enabled) return
        val dsn = BuildConfig.SENTRY_DSN.trim()
        if (dsn.isBlank()) return

        SentryAndroid.init(context.applicationContext) { options ->
            options.dsn = dsn
            options.environment = BuildConfig.RELEASE_CHANNEL
            options.release = "${BuildConfig.APPLICATION_ID}@${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}"
            // Health assessment data, images, and identifiers must never be
            // attached to error events by default.
            options.isSendDefaultPii = false
            options.isEnableUserInteractionBreadcrumbs = false
        }
        enabled = true
    }

    fun record(error: Throwable, feature: String) {
        if (!enabled) return
        Sentry.withScope { scope ->
            scope.setTag("feature", feature)
            Sentry.captureException(error)
        }
    }
}
