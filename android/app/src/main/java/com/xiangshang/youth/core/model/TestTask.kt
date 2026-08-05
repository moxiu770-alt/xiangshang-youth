package com.xiangshang.youth.core.model
data class TestTask(
    val id: String,
    val title: String,
    val date: String,
    val location: String,
    val gradeName: String,
    val className: String,
    val completedCount: Int,
    val totalCount: Int,
    val status: TaskStatus,
    val ruleVersion: String,
    val items: List<TestItem> = TestItem.entries
)
