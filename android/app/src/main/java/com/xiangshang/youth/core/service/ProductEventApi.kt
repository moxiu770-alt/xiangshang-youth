package com.xiangshang.youth.core.service

import retrofit2.http.Body
import retrofit2.http.POST

data class ProductEventInput(
    val eventId: String,
    val eventName: String,
    val coarseValue: String?,
    val platform: String,
    val appVersion: String,
    val clientSessionId: String,
    val occurredAt: String
)
data class ProductEventBatch(val events: List<ProductEventInput>)
data class ProductEventReceipt(val acceptedCount: Int, val duplicateCount: Int)

interface ProductEventApi {
    @POST("v1/mobile/events")
    suspend fun submit(@Body body: ProductEventBatch): ApiEnvelope<ProductEventReceipt>
}
