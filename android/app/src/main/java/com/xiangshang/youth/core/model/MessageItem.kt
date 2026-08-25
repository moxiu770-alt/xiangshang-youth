package com.xiangshang.youth.core.model
data class MessageItem(
    val id: String,
    val title: String,
    val content: String,
    val time: String,
    val category: String,
    val isRead: Boolean,
    val messageType: String? = null,
    val businessId: String? = null,
    val businessRoute: String? = null,
    val childId: String? = null,
    val taskId: String? = null,
    val courseId: String? = null,
    val lessonId: String? = null,
    val actionLabel: String? = null,
    val readAt: String? = null,
    val expiresAt: String? = null
)
