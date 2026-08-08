import XCTest

/// Black-box smoke coverage for the first-run path.  This intentionally uses
/// only accessibility labels and visible copy so it remains useful when the
/// visual implementation evolves independently of the view model tests.
final class LaunchAndRoleFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // AppState clears its local store for this argument, keeping each UI
        // test independent from a developer's previous login session.
        app.launchArguments += ["-ui-testing"]
        app.launch()
    }

    func testLaunchLoginAndRoleSelection() {
        loginAndWaitForRoleSelection()

        XCTAssertTrue(button(containing: "家庭端").waitForExistence(timeout: 2))
        XCTAssertTrue(button(containing: "学校端").exists)
        XCTAssertTrue(button(containing: "校长端").exists)

        // The teacher dashboard bell is a real route, and returning from the
        // message list must restore the same root dashboard without exposing a
        // duplicate dashboard back-stack entry.
        button(containing: "学校端").tap()
        XCTAssertTrue(staticText(containing: "班级健康概览").waitForExistence(timeout: 5))
        // Teacher board drill-downs must remain in the teacher workbench.
        // A former route opened the principal risk page from “问题分布”.
        let classBoard = button(containing: "班级看板")
        XCTAssertTrue(classBoard.waitForExistence(timeout: 2))
        classBoard.tap()
        XCTAssertTrue(staticText(containing: "班级数据看板").waitForExistence(timeout: 3))
        let issueDistribution = button(containing: "问题分布")
        XCTAssertTrue(issueDistribution.waitForExistence(timeout: 2))
        issueDistribution.tap()
        XCTAssertTrue(staticText(containing: "预警中心").waitForExistence(timeout: 3))
        button(containing: "返回").tap()
        XCTAssertTrue(staticText(containing: "班级数据看板").waitForExistence(timeout: 3))
        button(containing: "返回").tap()
        XCTAssertTrue(staticText(containing: "班级健康概览").waitForExistence(timeout: 3))
        let teacherMessages = button(containing: "消息通知")
        XCTAssertTrue(teacherMessages.waitForExistence(timeout: 3))
        teacherMessages.tap()
        XCTAssertTrue(staticText(containing: "消息中心").waitForExistence(timeout: 3))
        let messageBack = button(containing: "返回")
        XCTAssertTrue(messageBack.waitForExistence(timeout: 2))
        messageBack.tap()
        XCTAssertTrue(staticText(containing: "班级健康概览").waitForExistence(timeout: 3))
        let teacherAccount = button(containing: "我的")
        XCTAssertTrue(teacherAccount.waitForExistence(timeout: 2))
        teacherAccount.tap()
        let returnToRoles = button(containing: "切换使用角色")
        XCTAssertTrue(returnToRoles.waitForExistence(timeout: 2))
        returnToRoles.tap()
        XCTAssertTrue(button(containing: "校长端").waitForExistence(timeout: 3))

        button(containing: "校长端").tap()
        XCTAssertTrue(staticText(containing: "学校运动健康总览").waitForExistence(timeout: 5))
        // A role workbench is a root state, never a pushed secondary page.
        // Keeping this assertion here prevents the old stray top-left back
        // affordance (and its blank-host dismissal path) from returning.
        XCTAssertFalse(button(containing: "返回").exists)

        // All four principal bottom tabs are application roots, not pushed
        // drill-down pages. Cover each one so a single tab cannot quietly
        // reintroduce the broken top-left back behavior.
        button(containing: "年级").tap()
        XCTAssertTrue(staticText(containing: "不同年级对比").waitForExistence(timeout: 3))
        XCTAssertFalse(button(containing: "返回").exists)
        button(containing: "班级").tap()
        XCTAssertTrue(staticText(containing: "班级完成率").waitForExistence(timeout: 3))
        XCTAssertFalse(button(containing: "返回").exists)
        button(containing: "风险").tap()
        XCTAssertTrue(staticText(containing: "重点风险学生").waitForExistence(timeout: 3))
        XCTAssertFalse(button(containing: "返回").exists)
        button(containing: "总览").tap()
        XCTAssertTrue(staticText(containing: "学校运动健康总览").waitForExistence(timeout: 3))

        // A role dashboard is a root state, so exiting it must return to role
        // selection instead of exposing a stale NavigationStack back route.
        let exitPrincipal = button(containing: "退出校长端")
        XCTAssertTrue(exitPrincipal.exists)
        exitPrincipal.tap()
        XCTAssertTrue(button(containing: "家庭端").waitForExistence(timeout: 3))

        button(containing: "家庭端").tap()
        XCTAssertTrue(staticText(containing: "综合测评").waitForExistence(timeout: 5))
    }

    func testParentBindingUnlocksReportAndKeepsReturnPath() {
        loginAndWaitForRoleSelection()

        button(containing: "家庭端").tap()
        let bindPrompt = button(containing: "去绑定孩子")
        XCTAssertTrue(bindPrompt.waitForExistence(timeout: 5))
        bindPrompt.tap()

        let beginBinding = button(containing: "绑定孩子")
        XCTAssertTrue(beginBinding.waitForExistence(timeout: 3))
        beginBinding.tap()
        XCTAssertTrue(app.textFields["child-name-field"].waitForExistence(timeout: 3))
        app.textFields["child-name-field"].tap()
        app.textFields["child-name-field"].typeText("王小明")
        app.textFields["child-binding-code-field"].tap()
        app.textFields["child-binding-code-field"].typeText("XS-S01")
        button(containing: "确认绑定").tap()

        // Binding is a family-scoped action.  It returns to the page that
        // requested it and unlocks the selected child's report rather than
        // stranding the user on an empty management screen.
        XCTAssertTrue(staticText(containing: "综合测评").waitForExistence(timeout: 4))
        button(containing: "我的测评").tap()
        let report = button(containing: "查看详细报告")
        XCTAssertTrue(report.waitForExistence(timeout: 3))
        report.tap()
        XCTAssertTrue(staticText(containing: "7项能力得分").waitForExistence(timeout: 5))
        let back = button(containing: "返回")
        XCTAssertTrue(back.waitForExistence(timeout: 2))
        back.tap()
        XCTAssertTrue(staticText(containing: "综合测评").waitForExistence(timeout: 3))

        // “孩子管理” is a durable family workspace.  It differs from a
        // report/assessment binding guard: after the first child is bound the
        // parent can still add a second child without being popped away.
        app.buttons["我的"].tap()
        let familyManager = button(containing: "已绑定孩子")
        XCTAssertTrue(familyManager.waitForExistence(timeout: 3))
        familyManager.tap()
        XCTAssertTrue(staticText(containing: "已绑定孩子 1 人").waitForExistence(timeout: 3))
        button(containing: "绑定孩子").tap()
        XCTAssertTrue(app.textFields["child-name-field"].waitForExistence(timeout: 3))
        app.textFields["child-name-field"].tap()
        app.textFields["child-name-field"].typeText("王小雨")
        app.textFields["child-binding-code-field"].tap()
        app.textFields["child-binding-code-field"].typeText("XS-S02")
        button(containing: "确认绑定").tap()
        XCTAssertTrue(staticText(containing: "已绑定孩子 2 人").waitForExistence(timeout: 4))
    }

    private func loginAndWaitForRoleSelection() {
        XCTAssertTrue(button(containing: "微信登录").waitForExistence(timeout: 10))
        XCTAssertTrue(button(containing: "注册新账号").exists)

        let consent = button(containing: "请阅读并同意")
        XCTAssertTrue(consent.exists)
        consent.tap()

        let login = button(containing: "微信登录")
        XCTAssertTrue(login.waitForExistence(timeout: 2))
        login.tap()
        XCTAssertTrue(button(containing: "家庭端").waitForExistence(timeout: 10))
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func staticText(containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
