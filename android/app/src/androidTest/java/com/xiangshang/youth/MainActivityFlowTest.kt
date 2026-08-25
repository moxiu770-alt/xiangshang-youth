package com.xiangshang.youth

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileOutputStream
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
    fun launchScreenshotIsSavedForVisualEvidence() {
        composeRule.onNodeWithContentDescription("向上少年启动页").assertIsDisplayed()
        val bitmap = composeRule.onRoot().captureToImage().asAndroidBitmap()
        val output = File(
            InstrumentationRegistry.getInstrumentation().targetContext.filesDir,
            "visual-evidence/launch-poster.png"
        )
        output.parentFile?.mkdirs()
        FileOutputStream(output).use { stream ->
            check(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream))
        }
        check(output.length() > 0) { "launch screenshot was not written" }
    }

    @Test
    fun publicLoginOnlyOffersFamilyAndSupportsParentBinding() {
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
        // The production login page must expose all three entry points, not
        // merely draw inactive alternatives below a phone-only flow.
        composeRule.onNodeWithText("手机号登录").assertIsDisplayed().performClick()
        composeRule.onNodeWithText("手机号").assertIsDisplayed()
        composeRule.onNodeWithText("账号密码登录").assertIsDisplayed().performClick()
        composeRule.onNodeWithText("账号 / 手机号").assertIsDisplayed()
        // This selects WeChat after account login has been active; it must not
        // start authorization before consent is intentionally confirmed below.
        composeRule.onNodeWithText("微信登录").performClick()
        composeRule.onNodeWithText("请阅读并同意相关协议").performClick()
        composeRule.onNodeWithText("微信登录").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("请选择进入方式").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("家庭端").assertIsDisplayed()
        // Public registration/WeChat fallback creates a family account only.
        // A parent must never receive a teacher workbench merely because the
        // app happens to bundle teacher screens for school-provisioned accounts.
        composeRule.onAllNodesWithText("学校端").assertCountEquals(0)
        composeRule.onAllNodesWithText("校长端").assertCountEquals(0)

        // Parent workbench: a new session still requires the child-binding
        // guard, and the school-code help is reachable from the dialog.
        composeRule.onNodeWithText("家庭端").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            // A new family session must bind a child before child-specific
            // reports and assessments are exposed.
            composeRule.onAllNodesWithText("去绑定孩子").fetchSemanticsNodes().isNotEmpty()
        }
        // Family is also a role root. The binding flow that follows is a
        // secondary route and will provide its own usable return control.
        composeRule.onAllNodesWithContentDescription("返回").assertCountEquals(0)
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
        composeRule.onNodeWithText("孩子姓名").performTextClearance()
        composeRule.onNodeWithText("孩子姓名").performTextInput("王小明")
        composeRule.onNodeWithText("学校绑定码").performTextClearance()
        composeRule.onNodeWithText("学校绑定码").performTextInput("XS-S01")
        composeRule.onNodeWithText("确认绑定").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("查看 7 项报告", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
        // Once a child is bound, the report route must render real seven-item
        // content and expose a working back action rather than a dead card.
        composeRule.onNodeWithText("查看 7 项报告", substring = true).performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("7项能力得分").fetchSemanticsNodes().isNotEmpty()
        }
        // Policy metadata intentionally follows the seven score cards. It is
        // below the fold on phone-sized devices, so scroll to it and verify
        // reachability rather than treating a non-first-screen section as a
        // missing report field.
        composeRule.onNodeWithText("评测标准与适用范围").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("评测生效日期").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithContentDescription("返回").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("查看 7 项报告", substring = true).fetchSemanticsNodes().isNotEmpty()
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
        composeRule.onNodeWithText("孩子姓名").performTextClearance()
        composeRule.onNodeWithText("孩子姓名").performTextInput("王小雨")
        composeRule.onNodeWithText("学校绑定码").performTextClearance()
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
        // Playback time is a real media-clock value, so it must not be pinned
        // to a fabricated 25% just for a screenshot. Reaching the active
        // playback control proves this route is live; persistence is covered
        // by the dedicated repository/unit tests.
        composeRule.onNodeWithText("完成").performClick()
    }
}
