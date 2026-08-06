package com.xiangshang.youth.core.repository
import com.xiangshang.youth.core.mock.MockRepository
import com.xiangshang.youth.core.model.*
import com.xiangshang.youth.core.service.ApiClient
import com.xiangshang.youth.core.service.StatsApi

/**
 * Remote endpoints are enabled by RepositoryProvider when backend wiring is available.
 * Report rendering keeps a typed local fallback so a temporarily unavailable endpoint never
 * crashes a student-detail route during a staged rollout.
 */
class RemoteRepository(
    private val statsApi: StatsApi = ApiClient.retrofit.create(StatsApi::class.java),
    private val reportFallback: YouthRepository = MockRepository()
) : YouthRepository {
    override suspend fun dashboard(): DashboardData = statsApi.dashboard("school-1")
    override fun report(student: Student): DiagnosisReport = reportFallback.report(student)
}
