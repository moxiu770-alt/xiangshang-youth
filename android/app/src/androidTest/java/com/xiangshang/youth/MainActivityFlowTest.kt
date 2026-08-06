package com.xiangshang.youth

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import org.junit.Rule
import org.junit.Test

/** Smoke test for the real Activity. It runs on a connected emulator or device in CI. */
class MainActivityFlowTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    // A cold AVD can spend several seconds creating the Compose runtime after
    // the native launch window. Keep the UI assertion honest without making it
    // flaky on slower CI/emulator hosts.
    private val coldStartTimeout = 15_000L

    @Test
    fun launchShowsBrandedSplashContent() {
        // The launch image is intentionally exposed for TalkBack and test discovery.
        composeRule.onNodeWithContentDescription("向上少年启动页").assertIsDisplayed()
    }

    @Test
    fun loginFlowsThroughAllRolesAndParentBinding() {
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("微信登录").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("微信登录").performClick()
        composeRule.onNodeWithText("请阅读并同意相关协议").performClick()
        composeRule.onNodeWithText("微信授权登录").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("请选择进入方式").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("家庭端").assertIsDisplayed()
        composeRule.onNodeWithText("学校端").assertIsDisplayed()
        composeRule.onNodeWithText("校长端").assertIsDisplayed()
        // Teacher workbench: verify the dashboard is reachable and that the
        // account switch returns to the full role picker instead of forcing a
        // parent account.
        composeRule.onNodeWithText("学校端").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("班级健康概览").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithContentDescription("消息通知").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("消息中心").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithContentDescription("返回").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("班级健康概览").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithContentDescription("我的").performClick()
        composeRule.onNodeWithText("切换使用角色").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("请选择进入方式").fetchSemanticsNodes().isNotEmpty()
        }

        // Principal workbench: verify the dedicated risk tab is a real route.
        composeRule.onNodeWithText("校长端").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("学校运动健康总览").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithContentDescription("风险").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("重点风险学生").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithContentDescription("总览").performClick()
        composeRule.onNodeWithText("退出校长端").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("请选择进入方式").fetchSemanticsNodes().isNotEmpty()
        }

        // Parent workbench: a new session still requires the child-binding
        // guard, and the school-code help is reachable from the dialog.
        composeRule.onNodeWithText("家庭端").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            // A new family session must bind a child before child-specific
            // reports and assessments are exposed.
            composeRule.onAllNodesWithText("去绑定孩子").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("去绑定孩子").assertIsDisplayed()
        // Secondary parent tabs must preserve the same actionable binding guard;
        // an empty report/health page must never strand a family account.
        composeRule.onNodeWithContentDescription("我的评测").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("去绑定孩子").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("去绑定孩子").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("绑定孩子").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("绑定孩子").performClick()
        composeRule.onNodeWithText("绑定码在哪找？").performClick()
        composeRule.onNodeWithText("绑定码获取说明").assertIsDisplayed()
        composeRule.onNodeWithText("知道了").performClick()
        composeRule.onNodeWithText("孩子姓名").performTextInput("王小明")
        composeRule.onNodeWithText("绑定码（Mock 示例 XS-S01）").performTextInput("XS-S01")
        composeRule.onNodeWithText("确认绑定").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("查看详细报告", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
        // Once a child is bound, the report route must render real seven-item
        // content and expose a working back action rather than a dead card.
        composeRule.onNodeWithText("查看详细报告", substring = true).performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("7项能力得分").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithContentDescription("返回").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("查看详细报告", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
    }
}
