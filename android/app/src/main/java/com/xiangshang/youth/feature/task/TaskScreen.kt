package com.xiangshang.youth.feature.task
import androidx.compose.runtime.Composable
import com.xiangshang.youth.core.model.TestTask
import com.xiangshang.youth.shared.component.*
@Composable fun TaskScreen(task: TestTask) = AppScaffold("体测任务") { TestTaskCard(task) }
