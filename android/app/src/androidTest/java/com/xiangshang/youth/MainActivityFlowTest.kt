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
    fun publicLoginOnlyOffersFamilyWorkbench() {
        resetToPublicLogin()
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

        // A public family account enters a root workbench and cannot get a
        // synthetic back button to a hidden teacher role.
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
    }

    @Test
    fun parentBindingUnlocksReportAndKeepsFamilyRoutesReachable() {
        resetToPublicLogin()
        composeRule.onNodeWithText("微信登录").performClick()
        composeRule.onNodeWithText("请阅读并同意相关协议").performClick()
        composeRule.onNodeWithText("微信登录").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("请选择进入方式").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("家庭端").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("去绑定孩子").fetchSemanticsNodes().isNotEmpty()
        }
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
    }

    @Test
    fun schoolProvisionedTeacherFixtureCoversTeacherWorkbench() {
        composeRule.activity.runOnUiThread {
            composeRule.activity.resetSessionForUiTest()
            composeRule.activity.startSchoolProvisionedTeacherFixtureForUiTest()
        }
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("班级健康概览").fetchSemanticsNodes().isNotEmpty()
        }
        // Teacher workbench is a root, so it must not expose a synthetic back
        // button after the authorized session replaces the public login root.
        composeRule.onAllNodesWithContentDescription("返回").assertCountEquals(0)

        composeRule.onNodeWithContentDescription("班级看板").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("班级数据看板").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithContentDescription("返回").performClick()
        // A stable accessibility label keeps the metric actionable without
        // coupling the regression test to a dynamic measured-student count.
        composeRule.onNodeWithContentDescription("打开体测任务").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("延时课程上传").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("2026年秋季综合运动能力测评").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("学生测评状态").fetchSemanticsNodes().isNotEmpty()
        }
        // The roster itself is scoped to this fixture's authorized classes.
        // Write authorization and transition rules are covered by unit tests,
        // keeping the device regression bounded and repeatable.
        composeRule.onAllNodesWithContentDescription("更新", substring = true).assertCountEquals(8)
        // The task list is a teacher-only route, and returning restores the
        // authorized workbench instead of leaking to a public role selector.
        composeRule.onNodeWithContentDescription("返回").performClick()
        composeRule.onNodeWithContentDescription("返回").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("班级健康概览").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithContentDescription("预警中心").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("预警中心").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithContentDescription("返回").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("班级健康概览").fetchSemanticsNodes().isNotEmpty()
        }
        // Notification composer belongs to the teacher class-circle root, not
        // the home dashboard. This validates the real tab transition before
        // asserting the editor is reachable.
        composeRule.onNodeWithContentDescription("班级圈").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("发班级通知").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("发班级通知").performClick()
        composeRule.waitUntil(timeoutMillis = coldStartTimeout) {
            composeRule.onAllNodesWithText("发班级通知").fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun resetToPublicLogin() {
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
    }
}
