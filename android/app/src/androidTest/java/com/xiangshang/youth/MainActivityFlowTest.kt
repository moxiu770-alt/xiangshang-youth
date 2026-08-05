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

    @Test
    fun launchShowsBrandedSplashContent() {
        // The launch image is intentionally exposed for TalkBack and test discovery.
        composeRule.onNodeWithContentDescription("向上少年启动页").assertIsDisplayed()
    }

    @Test
    fun loginFlowsToRoleChoiceAndParentHome() {
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithText("微信登录").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("微信登录").performClick()
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithText("请选择进入方式").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("家庭端").performClick()
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithText("综合测评").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("综合测评").assertIsDisplayed()
    }
}
