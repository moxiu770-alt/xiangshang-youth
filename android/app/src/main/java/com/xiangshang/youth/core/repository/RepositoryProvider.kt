package com.xiangshang.youth.core.repository

import com.xiangshang.youth.core.mock.MockRepository

/** Default is deterministic bundled data; flipping this flag does not change presentation APIs. */
object RepositoryProvider {
    @Volatile var useRemoteDataSource: Boolean = false

    fun create(): YouthRepository = if (useRemoteDataSource) RemoteRepository() else MockRepository()
}
