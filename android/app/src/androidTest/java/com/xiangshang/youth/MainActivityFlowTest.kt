package com.xiangshang.youth

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onAllNodesWithContentDescription
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
    // Freshly booted AVDs may take over 20 seconds to create the first
    // Compose frame after the splash. Keep this distinct from normal UI waits
    // so real navigation regressions still fail fast once the app is warm.
    private val coldStartTimeout = 35_000L

    @Test
    fun launchShowsBrandedSplashContent() {
        // The launch image is intentionally exposed for TalkBack and test discovery.
        composeRule.onNodeWithContentDescription("向上少年启动页").assertIsDisplayed()
    }

    @Test
    fun loginFlowsThroughAllRolesAndParentBinding() {
        // Instrumentation does not guarantee an empty encrypted preference
        // sandbox. Clear the active ViewModel session as well as its store;
        // recreating an Activity alone would retain the old ViewModel.
        composeRule.activity.runOnUiThread {
            composeRule.activity.resetSessionForUiTest()
        }
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("微信登录").fetchSemanticsNodes().isNotEmpty() ||
                composeRule.onAllNodesWithText("退出当前账号").fetchSemanticsNodes().isNotEmpty()
        }
        if (composeRule.onAllNodesWithText("退出当前账号").fetchSemanticsNodes().isNotEmpty()) {
            composeRule.onNodeWithText("退出当前账号").performClick()
        }
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("微信登录").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("请阅读并同意相关协议").performClick()
        composeRule.onNodeWithText("微信登录").performClick()
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
        // Historical period selection must affect the board rather than merely
        // tinting a chip. It intentionally opens a protected aggregate view
        // instead of leaking current student reports as historical records.
        composeRule.onNodeWithContentDescription("班级看板").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("2026春季").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("2026春季").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("历史归档完成率 90%").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("查看归档说明").performClick()
        composeRule.onNodeWithText("2026春季测评归档").assertIsDisplayed()
        composeRule.onNodeWithText("关闭").performClick()
        composeRule.onNodeWithContentDescription("返回").performClick()
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

        // Principal workbench: every bottom item is a root page. A regression
        // once made only the overview root safe while grade/class pages showed
        // a dead back affordance.
        composeRule.onNodeWithText("校长端").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("学校运动健康总览").fetchSemanticsNodes().isNotEmpty()
        }
        // Role dashboards are application roots.  A back affordance here used
        // to expose the previous workbench instead of the role picker.
        composeRule.onAllNodesWithContentDescription("返回").assertCountEquals(0)
        composeRule.onNodeWithContentDescription("年级").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("不同年级对比").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onAllNodesWithContentDescription("返回").assertCountEquals(0)
        composeRule.onNodeWithContentDescription("班级").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("班级完成率").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onAllNodesWithContentDescription("返回").assertCountEquals(0)
        composeRule.onNodeWithContentDescription("风险").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("重点风险学生").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onAllNodesWithContentDescription("返回").assertCountEquals(0)
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
        composeRule.onNodeWithText("学校绑定码").performTextInput("XS-S01")
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

        // “孩子管理” is a family-management entry point, not a one-shot
        // binding guard.  After the first child is bound, it must stay open
        // so the same household can add another child without losing context.
        composeRule.onNodeWithContentDescription("我的").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("孩子管理").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onAllNodesWithText("孩子管理")[0].performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("已绑定孩子 1 人").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("绑定孩子").performClick()
        composeRule.onNodeWithText("孩子姓名").performTextInput("王小雨")
        composeRule.onNodeWithText("学校绑定码").performTextInput("XS-S02")
        composeRule.onNodeWithText("确认绑定").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("已绑定孩子 2 人").fetchSemanticsNodes().isNotEmpty()
        }

        // Course cards must not manufacture a completed progress value merely
        // because they were opened. The learner starts the course explicitly,
        // then the locally persisted progress becomes visible in the dialog.
        composeRule.onNodeWithContentDescription("返回").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithContentDescription("我的课程").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithContentDescription("我的课程").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("体质成长课").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("体质成长课").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("播放课程").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("播放课程").performClick()
        composeRule.onNodeWithText("暂停学习").assertIsDisplayed()
        // The card and lesson dialog both expose the persisted value; either
        // one alone would prove too little, so assert the duplicated update.
        composeRule.onAllNodesWithText("学习进度 25%").assertCountEquals(2)
        composeRule.onNodeWithText("完成").performClick()
    }
}
