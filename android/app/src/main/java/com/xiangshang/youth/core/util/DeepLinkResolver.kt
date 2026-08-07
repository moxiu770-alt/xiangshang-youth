package com.xiangshang.youth.core.util

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

/**
 * Keeps browser/notification deep-link parsing outside Compose so the routing
 * contract can be tested on the JVM and shared by future notification code.
 */
enum class DeepLinkTarget { Report, Review, Tasks, Risk }

data class AppDeepLink(val target: DeepLinkTarget, val studentId: String? = null)

object DeepLinkResolver {
    /** A link is not permission: a parent may open only an already bound child. */
    fun isBoundFamilyStudent(studentId: String?, boundChildIds: Set<String>): Boolean =
        studentId != null && studentId in boundChildIds

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
            else -> null
        }
    }.getOrNull()

    private fun decode(value: String): String = URLDecoder.decode(value, StandardCharsets.UTF_8.name())
}
