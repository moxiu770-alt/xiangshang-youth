package com.xiangshang.youth

import android.app.Application
import com.xiangshang.youth.app.AppUiState
import com.xiangshang.youth.core.monitoring.CrashMonitoring
import com.xiangshang.youth.core.service.ApiClient
import com.xiangshang.youth.core.service.FeatureRollout
import com.xiangshang.youth.core.service.LocalFeatureStore
import com.xiangshang.youth.core.sync.PendingSyncScheduler
import com.xiangshang.youth.core.util.FrontendTelemetry

/** Process services must also exist when WorkManager starts the app without
 * creating MainActivity. No student content or health values are logged here. */
class XiangshangYouthApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        CrashMonitoring.initialize(this)
        FeatureRollout.initialize(this)
        ApiClient.initialize(this)
        val local = LocalFeatureStore(this).load()
        FrontendTelemetry.configure(local.settings.analyticsEnabled && BuildConfig.USE_REMOTE_DATA_SOURCE)
        if (AppUiState(local = local, repositoryAcknowledged = BuildConfig.USE_REMOTE_DATA_SOURCE).pendingSyncCount > 0) {
            PendingSyncScheduler.enqueue(this)
        }
    }
}
