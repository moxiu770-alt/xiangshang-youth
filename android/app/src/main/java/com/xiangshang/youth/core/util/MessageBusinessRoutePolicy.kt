package com.xiangshang.youth.core.util

import com.xiangshang.youth.core.model.MessageItem
import com.xiangshang.youth.core.model.UserRole
import java.time.Instant

data class MessageCourseTarget(
    val childId: String,
    val courseId: String?,
    val lessonId: String?,
    val title: String
)

enum class MessageTaskScope { Parent, Teacher }
data class MessageTaskTarget(val taskId: String, val scope: MessageTaskScope)

object MessageBusinessRoutePolicy {
    fun normalizeRoute(route: String?): String {
        return route
            ?.trim()
            ?.lowercase()
            ?.replace("-", "")
            ?.replace("_", "")
            .orEmpty()
    }

    fun isExpired(expiresAt: String?, now: Instant = Instant.now()): Boolean {
        val expires = expiresAt?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: return false
        return expires.isBefore(now)
    }

    fun courseTarget(item: MessageItem): MessageCourseTarget? {
        val route = normalizeRoute(item.businessRoute).ifBlank { return null }
        if (route != "course" && route != "lesson") return null
        val childId = item.childId?.takeIf { it.isNotBlank() } ?: return null
        val courseId = item.courseId ?: if (route == "course") item.businessId else null
        val lessonId = item.lessonId ?: if (route == "lesson") item.businessId else null
        if (courseId.isNullOrBlank() && lessonId.isNullOrBlank()) return null
        return MessageCourseTarget(childId, courseId, lessonId, item.actionLabel ?: item.title)
    }

    fun hasRequiredBusinessId(item: MessageItem): Boolean = !item.businessId.isNullOrBlank()

    fun taskTarget(item: MessageItem, role: UserRole, taskExists: Boolean, roleAuthorized: Boolean): MessageTaskTarget? {
        val route = normalizeRoute(item.businessRoute)
        if (route != "task" && route != "retest") return null
        val taskId = item.taskId ?: item.businessId ?: return null
        if (!taskExists || !roleAuthorized) return null
        val scope = when (role) {
            UserRole.Parent -> MessageTaskScope.Parent
            UserRole.Teacher -> MessageTaskScope.Teacher
            else -> return null
        }
        return MessageTaskTarget(taskId, scope)
    }
}
