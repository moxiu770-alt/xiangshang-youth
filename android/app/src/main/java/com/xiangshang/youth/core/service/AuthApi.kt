package com.xiangshang.youth.core.service

import com.xiangshang.youth.core.model.UserProfile
import retrofit2.http.Body
import retrofit2.http.POST

data class LoginRequest(val account: String, val verificationCode: String? = null, val password: String? = null)

interface AuthApi {
    @POST("v1/auth/login")
    suspend fun login(@Body request: LoginRequest): UserProfile
}
