package com.xiangshang.youth.core.util

/**
 * Keeps third-party authorization identifiers out of display profiles.
 * The backend must replace the authorization identifier with a verified
 * mobile before it is displayed. Never invent a phone number for a third-party
 * identity, even in Mock mode.
 */
object AuthIdentity {
    const val wechatAuthorizationIdentifier = "wechat_authorization"
    private const val unboundPhone = "未绑定手机号"

    fun displayPhone(identifier: String): String {
        val normalized = identifier.trim()
        return when {
            normalized.isBlank() -> unboundPhone
            normalized == wechatAuthorizationIdentifier -> unboundPhone
            else -> normalized
        }
    }
}
