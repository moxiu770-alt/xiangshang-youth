package com.xiangshang.youth.core.repository

import com.xiangshang.youth.core.mock.MockRepository
import com.xiangshang.youth.BuildConfig

/** Default is deterministic bundled data; flipping this flag does not change presentation APIs. */
object RepositoryProvider {
    /**
     * Mock is the safe default. Backend builds opt in with
     * `-PuseRemoteDataSource=true`, normally alongside `-PapiBaseUrl=...`.
     */
    @Volatile var useRemoteDataSource: Boolean = BuildConfig.USE_REMOTE_DATA_SOURCE

    fun create(): YouthRepository = if (useRemoteDataSource) RemoteRepository() else MockRepository()
}
