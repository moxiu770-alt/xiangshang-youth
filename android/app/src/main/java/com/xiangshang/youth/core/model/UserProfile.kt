package com.xiangshang.youth.core.model
data class UserProfile(
    val id: String,
    val name: String,
    val phone: String,
    val role: UserRole,
    val schoolName: String,
    val avatarInitials: String = name.take(1)
)
