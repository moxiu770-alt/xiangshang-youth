package com.xiangshang.youth.core.util

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import com.xiangshang.youth.core.model.UserRole

/**
 * Keeps browser/notification deep-link parsing outside Compose so the routing
 * contract can be tested on the JVM and shared by future notification code.
 */
enum class DeepLinkTarget { Report, Review, Tasks, Risk, WechatCallback }

data class AppDeepLink(val target: DeepLinkTarget, val studentId: String? = null, val code: String? = null, val state: String? = null)

object DeepLinkResolver {
    /** A link is not permission: a parent may open only an already bound child. */
    fun isBoundFamilyStudent(studentId: String?, boundChildIds: Set<String>): Boolean =
        studentId != null && studentId in boundChildIds

    /** A deep link selects a destination; it never grants a workbench role. */
    fun isAuthorized(target: DeepLinkTarget, repositoryAcknowledged: Boolean, availableRoles: Set<UserRole>): Boolean =
        // Mock mode still has an account identity. A notification URL must not
        // manufacture teacher access merely because the Remote repository is
        // disabled. Keep the parameter for API compatibility with callers.
        when (target) {
            DeepLinkTarget.Report -> UserRole.Parent in availableRoles
            DeepLinkTarget.Review, DeepLinkTarget.Tasks -> UserRole.Teacher in availableRoles
            DeepLinkTarget.Risk -> UserRole.Principal in availableRoles
            DeepLinkTarget.WechatCallback -> true
        }

    fun parse(value: String): AppDeepLink? = runCatching {
        val uri = URI(value)
        if (uri.scheme != "xiangshang-youth" || uri.host != "open") return null
        val query = uri.rawQuery.orEmpty()
            .split("&")
            .filter { it.isNotBlank() }
            .associate { part ->
                val pieces = part.split("=", limit = 2)
                decode(pieces[0]) to decode(pieces.getOrElse(1) { "" })
            }
        when (query["target"]) {
            "report" -> AppDeepLink(DeepLinkTarget.Report, query["studentId"]?.takeIf { it.isNotBlank() })
            "review" -> AppDeepLink(DeepLinkTarget.Review)
            "tasks" -> AppDeepLink(DeepLinkTarget.Tasks)
            "risk" -> AppDeepLink(DeepLinkTarget.Risk)
            "wechat-callback" -> AppDeepLink(DeepLinkTarget.WechatCallback, code = query["code"], state = query["state"])
            else -> null
        }
    }.getOrNull()

    private fun decode(value: String): String = URLDecoder.decode(value, StandardCharsets.UTF_8.name())
}
