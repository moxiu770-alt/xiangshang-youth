package com.xiangshang.youth.core.util

import com.xiangshang.youth.core.model.UserRole

/** Keeps notification buttons inside the active role's own message surface. */
object RoleMessageDestination {
    fun resolve(role: UserRole?): String = when (role) {
        UserRole.Parent -> "messages"
        UserRole.Teacher -> "teacherMessages"
        UserRole.Principal, null -> "notifications"
    }
}
