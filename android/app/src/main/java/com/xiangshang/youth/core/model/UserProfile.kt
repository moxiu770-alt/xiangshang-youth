package com.xiangshang.youth.core.model
data class UserProfile(
    val id: String,
    val name: String,
    val phone: String,
    val role: UserRole,
    val schoolName: String,
    val avatarInitials: String = name.take(1),
    val roleCode: String? = null,
    val schoolId: String? = null,
    val availableRoles: List<UserRole> = listOf(role),
    /** Stable authorization claims; display names are presentation-only. */
    val authorizedClassIds: List<String> = emptyList(),
    val capabilities: Set<String> = emptySet()
)
