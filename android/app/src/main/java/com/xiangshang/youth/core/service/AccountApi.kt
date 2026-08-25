package com.xiangshang.youth.core.service

import retrofit2.http.POST

interface AccountApi {
    @POST("v1/me/deletion-request")
    suspend fun submitDeletionRequest(@retrofit2.http.Body request: EmptyAccountRequest = EmptyAccountRequest()): ApiEnvelope<AccountDeletionReceipt>
}

data class EmptyAccountRequest(val confirm: Boolean = true)
data class AccountDeletionReceipt(val id: String, val status: String, val createdAt: String, val completedAt: String? = null)
