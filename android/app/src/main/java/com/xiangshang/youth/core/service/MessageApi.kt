package com.xiangshang.youth.core.service

import com.xiangshang.youth.core.model.MessageItem
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

interface MessageApi {
    @GET("v1/users/{userId}/messages")
    suspend fun messages(@Path("userId") userId: String): ApiEnvelope<List<MessageItem>>

    @POST("v1/messages/{messageId}/read")
    suspend fun markRead(@Path("messageId") messageId: String): ApiEnvelope<WriteAck>
}
