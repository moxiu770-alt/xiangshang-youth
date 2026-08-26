package com.xiangshang.youth.core.sync

import android.app.Application
import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.xiangshang.youth.BuildConfig
import com.xiangshang.youth.app.AppUiState
import com.xiangshang.youth.app.AppViewModel
import com.xiangshang.youth.core.service.ApiClient
import com.xiangshang.youth.core.service.LocalFeatureStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit

object PendingSyncScheduler {
    private const val UNIQUE_WORK = "xiangshang-pending-record-sync"

    fun enqueue(context: Context) {
        if (!BuildConfig.USE_REMOTE_DATA_SOURCE) return
        val request = OneTimeWorkRequestBuilder<PendingSyncWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(UNIQUE_WORK, ExistingWorkPolicy.KEEP, request)
    }
}

/** Uses the same repository and state transitions as the foreground UI while
 * WorkManager supplies durable network constraints across process death and
 * reboot. Camera frames are never part of the persisted sync payload. */
class PendingSyncWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        if (!BuildConfig.USE_REMOTE_DATA_SOURCE) return Result.success()
        ApiClient.initialize(applicationContext)
        val local = LocalFeatureStore(applicationContext).load()
        val snapshot = AppUiState(local = local, repositoryAcknowledged = true)
        if (!local.sessionActive || snapshot.pendingSyncCount == 0 || !ApiClient.hasToken()) return Result.success()

        val application = applicationContext as? Application ?: return Result.failure()
        val viewModel = withContext(Dispatchers.Main.immediate) { AppViewModel(application) }
        return try {
            val ready = withTimeoutOrNull(30_000) {
                viewModel.state.first { !it.restoringSession && !it.loading }
            } ?: return Result.retry()
            if (ready.profile == null) return if (runAttemptCount < 5) Result.retry() else Result.failure()
            val job = withContext(Dispatchers.Main.immediate) { viewModel.syncPendingRecords() }
            job.join()
            if (viewModel.state.value.pendingSyncCount == 0) Result.success()
            else if (runAttemptCount < 5) Result.retry()
            else Result.failure()
        } finally {
            withContext(Dispatchers.Main.immediate) { viewModel.releaseBackgroundResources() }
        }
    }
}
