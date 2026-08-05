package com.xiangshang.youth

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
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
    fun loginFlowsToRoleChoiceAndParentHome() {
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
        composeRule.onNodeWithText("家庭端").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            // A new family session must bind a child before child-specific
            // reports and assessments are exposed.
            composeRule.onAllNodesWithText("去绑定孩子").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("去绑定孩子").assertIsDisplayed()
        composeRule.onNodeWithText("去绑定孩子").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("绑定孩子").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("绑定孩子").performClick()
        composeRule.onNodeWithText("绑定码在哪找？").performClick()
        composeRule.onNodeWithText("绑定码获取说明").assertIsDisplayed()
    }
}
