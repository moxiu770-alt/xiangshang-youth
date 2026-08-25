package com.xiangshang.youth.core.model
data class CourseSuggestion(val id: String, val title: String, val duration: String, val focus: String, val isPublicBenefit: Boolean, val courseId: String? = null, val lessonId: String? = null)
