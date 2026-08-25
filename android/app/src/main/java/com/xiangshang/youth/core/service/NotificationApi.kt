package com.xiangshang.youth.core.service

import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.POST
import retrofit2.http.Query
import retrofit2.http.Header

data class NotificationCampaign(
    val notificationId: String,
    val schoolId: String,
    val senderTeacherId: String? = null,
    val title: String,
    val content: String,
    val targetClassIds: List<String> = emptyList(),
    val recipientScope: String = "class",
    val scheduledAt: String? = null,
    val status: String = "draft",
    val draftVersion: Int = 1,
    val sentAt: String? = null,
    val failureReason: String? = null,
    val idempotencyKey: String? = null,
    val parentReceiptEnabled: Boolean = false
)

data class NotificationCampaignRequest(
    val schoolId: String,
    val classId: String,
    val title: String,
    val content: String,
    val status: String? = null,
    val targetClassIds: List<String> = listOf(classId),
    val recipientScope: String = "class",
    val scheduledAt: String? = null,
    val audienceType: String = "class",
    val channel: String = "in_app",
    val parentReceiptEnabled: Boolean = false,
    val draftVersion: Int? = null
)

data class NotificationCampaignReceipt(
    val id: String,
    val title: String,
    val status: String,
    val sentCount: Int = 0,
    val failureReason: String? = null,
    val scheduledAt: String? = null,
    val draftVersion: Int = 1,
    val parentReceiptEnabled: Boolean = false
)

data class NotificationCampaignDetail(
    val notificationId: String,
    val schoolId: String,
    val senderTeacherId: String? = null,
    val title: String,
    val content: String,
    val targetClassIds: List<String> = emptyList(),
    val recipientScope: String = "class",
    val status: String = "sent",
    val draftVersion: Int = 1,
    val scheduledAt: String? = null,
    val sentAt: String? = null,
    val failureReason: String? = null,
    val parentReceiptEnabled: Boolean = false,
    val userReceiptStatus: String? = null,
    val acknowledgedAt: String? = null,
    val receiptStats: NotificationReceiptStats? = null
)

data class NotificationReceiptStats(val pending: Int = 0, val acknowledged: Int = 0, val total: Int = 0)

data class NotificationReceiptAck(
    val id: String? = null,
    val notificationId: String,
    val receiverUserId: String? = null,
    val status: String,
    val acknowledgedAt: String? = null,
    val version: Int? = null
)

interface NotificationApi {
    @GET("v1/classes/notifications/drafts")
    suspend fun drafts(@Query("schoolId") schoolId: String): ApiEnvelope<List<NotificationCampaign>>

    @GET("v1/classes/notifications/{notificationId}")
    suspend fun detail(@Path("notificationId") notificationId: String): ApiEnvelope<NotificationCampaignDetail>

    @POST("v1/classes/notifications")
    suspend fun send(@Body body: NotificationCampaignRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<NotificationCampaignReceipt>

    @POST("v1/classes/notifications")
    suspend fun createDraft(@Body body: NotificationCampaignRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<NotificationCampaign>

    @PUT("v1/classes/notifications/{notificationId}")
    suspend fun updateDraft(@Path("notificationId") notificationId: String, @Body body: NotificationCampaignRequest, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<NotificationCampaign>

    @POST("v1/classes/notifications/{notificationId}/send")
    suspend fun sendDraft(@Path("notificationId") notificationId: String, @Body body: EmptyNotificationRequest = EmptyNotificationRequest(), @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<NotificationCampaignReceipt>

    @POST("v1/classes/notifications/{notificationId}/retry")
    suspend fun retry(@Path("notificationId") notificationId: String, @Body body: EmptyNotificationRequest = EmptyNotificationRequest(), @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<NotificationCampaignReceipt>

    @DELETE("v1/classes/notifications/{notificationId}")
    suspend fun discard(@Path("notificationId") notificationId: String, @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<NotificationDiscardReceipt>

    @POST("v1/classes/notifications/{notificationId}/receipt")
    suspend fun acknowledgeReceipt(@Path("notificationId") notificationId: String, @Body body: EmptyNotificationRequest = EmptyNotificationRequest(), @Header("Idempotency-Key") idempotencyKey: String? = null): ApiEnvelope<NotificationReceiptAck>
}

data class EmptyNotificationRequest(val value: String? = null)
data class NotificationDiscardReceipt(val notificationId: String, val status: String)
