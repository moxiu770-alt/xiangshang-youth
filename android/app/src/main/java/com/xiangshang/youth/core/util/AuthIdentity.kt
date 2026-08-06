package com.xiangshang.youth.core.util

/**
 * Keeps third-party authorization identifiers out of display profiles.
 * The backend will replace the fallback with the verified mobile returned by
 * the authorization bind endpoint.
 */
object AuthIdentity {
    const val wechatAuthorizationIdentifier = "wechat_authorization"
    private const val fallbackPhone = "13800138000"

    fun displayPhone(identifier: String): String {
        val normalized = identifier.trim()
        return when {
            normalized.isBlank() -> fallbackPhone
            normalized == wechatAuthorizationIdentifier -> fallbackPhone
            else -> normalized
        }
    }
}
