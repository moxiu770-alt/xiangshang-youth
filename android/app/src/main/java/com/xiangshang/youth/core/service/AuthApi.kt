package com.xiangshang.youth.core.service

import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import com.squareup.moshi.Json

data class LoginRequest(val account: String, val verificationCode: String? = null, val password: String? = null)
data class RegisterRequest(val name: String, val phone: String, val verificationCode: String, val password: String, val roleCode: String)
data class ResetPasswordRequest(val phone: String, val verificationCode: String, val newPassword: String)
data class VerificationCodeRequest(val account: String, val purpose: String)
data class WechatAuthorizationStart(val state: String, val expiresAt: String, val authorizeUrl: String)
data class WechatExchangeRequest(val code: String, val state: String)
data class AuthRole(val code: String, val name: String, val schoolId: String? = null, val classId: String? = null, val classIds: List<String> = emptyList(), val capabilities: Set<String> = emptySet())
/** The authoritative mobile claim contract returned by /v1/auth/session. */
data class MobileAccountRole(val roleCode: String, val name: String, val schoolId: String? = null, val campusIds: List<String> = emptyList(), val authorizedGradeIds: List<String> = emptyList(), val authorizedClassIds: List<String> = emptyList(), val capabilities: Set<String> = emptySet(), val mobileEntryAllowed: Boolean = true)
data class BackendUser(val id: String, val name: String, val phone: String, val role: String, val roleCode: String? = null, val schoolId: String? = null, val schoolName: String = "", val avatarInitials: String? = null, val authorizedClassIds: List<String> = emptyList(), val capabilities: Set<String> = emptySet())
data class AuthResponse(val accessToken: String, val refreshToken: String? = null, val expiresAt: String? = null, val activeRole: String? = null, val user: BackendUser, val roles: List<AuthRole> = emptyList(), val accountRoles: List<MobileAccountRole>? = null, val claimsVersion: Int? = null)
data class AuthSessionClaims(val claimsVersion: Int, val activeRole: String, val user: BackendUser, val roles: List<AuthRole> = emptyList(), val accountRoles: List<MobileAccountRole>? = null)
data class MeResponse(val id: String, val name: String, val phone: String? = null, val roleCode: String, val schoolId: String? = null, val schoolName: String = "", val roles: List<MeRole> = emptyList()) {
    val displayPhone: String get() = phone?.takeIf { it.isNotBlank() } ?: "未绑定手机号"
}
data class MeRole(val code: String, @param:Json(name = "school_id") val schoolId: String? = null, @param:Json(name = "class_id") val classId: String? = null)

interface AuthApi {
    @POST("v1/auth/login")
    suspend fun login(@Body request: LoginRequest): ApiEnvelope<AuthResponse>

    @POST("v1/auth/register")
    suspend fun register(@Body request: RegisterRequest): ApiEnvelope<AuthResponse>

    @POST("v1/auth/reset-password")
    suspend fun resetPassword(@Body request: ResetPasswordRequest): ApiEnvelope<WriteAck>

    @POST("v1/auth/verification-codes")
    suspend fun sendVerificationCode(@Body request: VerificationCodeRequest): ApiEnvelope<WriteAck>

    @POST("v1/auth/oauth/wechat/start")
    suspend fun startWechatAuthorization(): ApiEnvelope<WechatAuthorizationStart>

    @POST("v1/auth/oauth/wechat/exchange")
    suspend fun exchangeWechat(@Body request: WechatExchangeRequest): ApiEnvelope<AuthResponse>

    @GET("v1/auth/session")
    suspend fun session(): ApiEnvelope<AuthSessionClaims>

    @GET("v1/me")
    suspend fun me(): ApiEnvelope<MeResponse>
}
