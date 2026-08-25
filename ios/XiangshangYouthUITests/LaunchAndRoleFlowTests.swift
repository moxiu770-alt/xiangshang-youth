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
        attachScreenshot("role-picker")

        XCTAssertTrue(button(containing: "家庭端").waitForExistence(timeout: 2))
        XCTAssertTrue(button(containing: "学校端").exists)
        // School management analytics are delivered by the backend dashboard;
        // the mobile app intentionally exposes only family and teacher roles.
        XCTAssertFalse(button(containing: "校长端").exists)

        // The teacher dashboard bell is a real route, and returning from the
        // message list must restore the same root dashboard without exposing a
        // duplicate dashboard back-stack entry.
        button(containing: "学校端").tap()
        XCTAssertTrue(staticText(containing: "班级健康概览").waitForExistence(timeout: 5))
        attachScreenshot("teacher-home")
        // A teacher workbench is a role root, not a pushed page. This guards
        // against a top-bar change reintroducing the dead back affordance that
        // previously trapped users after they selected a different identity.
        XCTAssertFalse(button(containing: "返回").exists)
        // Teacher board drill-downs must remain in the teacher workbench.
        // A former route opened the principal risk page from “问题分布”.
        let classBoard = button(containing: "班级看板")
        XCTAssertTrue(classBoard.waitForExistence(timeout: 2))
        classBoard.tap()
        XCTAssertTrue(staticText(containing: "班级数据看板").waitForExistence(timeout: 3))
        // The archived period is intentionally aggregate-only. Switching it
        // must change the board and show the protected-history explanation,
        // never reuse current student reports as historical records.
        let historicalPeriod = button(containing: "2026春季")
        XCTAssertTrue(historicalPeriod.waitForExistence(timeout: 2))
        historicalPeriod.tap()
        XCTAssertTrue(staticText(containing: "已归档汇总").waitForExistence(timeout: 3))
        let archiveInfo = button(containing: "归档说明")
        XCTAssertTrue(archiveInfo.waitForExistence(timeout: 2))
        archiveInfo.tap()
        XCTAssertTrue(staticText(containing: "历史测评归档").waitForExistence(timeout: 3))
        button(containing: "关闭").tap()
        button(containing: "本轮综合测评").tap()
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

        // The assignment shortcut has its own data scope. Mock fixtures have
        // no unassigned students, so it must present the truthful empty state
        // instead of silently opening the generic student list.
        let unassignedStudents = button(containing: "待分班学生")
        XCTAssertTrue(unassignedStudents.waitForExistence(timeout: 2))
        unassignedStudents.tap()
        XCTAssertTrue(staticText(containing: "暂无待分班学生").waitForExistence(timeout: 3))
        button(containing: "返回").tap()
        XCTAssertTrue(staticText(containing: "班级健康概览").waitForExistence(timeout: 3))

        // Keep the dedicated class-management page exposed directly from the
        // teacher workbench instead of regressing into a duplicate roster card.
        let classManagement = button(containing: "班级管理")
        XCTAssertTrue(classManagement.waitForExistence(timeout: 2))
        classManagement.tap()
        XCTAssertTrue(staticText(containing: "我管理的班级").waitForExistence(timeout: 3))
        button(containing: "返回").tap()
        XCTAssertTrue(staticText(containing: "班级健康概览").waitForExistence(timeout: 3))

        let teacherAccount = button(containing: "我的")
        XCTAssertTrue(teacherAccount.waitForExistence(timeout: 2))
        teacherAccount.tap()
        let returnToRoles = button(containing: "切换使用角色")
        XCTAssertTrue(returnToRoles.waitForExistence(timeout: 2))
        returnToRoles.tap()
        XCTAssertTrue(button(containing: "家庭端").waitForExistence(timeout: 3))
        XCTAssertTrue(button(containing: "学校端").exists)
        XCTAssertFalse(button(containing: "校长端").exists)

        button(containing: "家庭端").tap()
        XCTAssertTrue(staticText(containing: "综合测评").waitForExistence(timeout: 5))
        attachScreenshot("parent-home")
        // The family workbench is also a role root. Child/report drill-downs
        // get a back control; the home itself must never show one.
        XCTAssertFalse(button(containing: "返回").exists)
    }

    /// Keep the commercial login alternatives independently covered.  This is
    /// intentionally shorter than the end-to-end role traversal so a future
    /// accessibility-container change cannot hide dynamically inserted form
    /// controls behind an otherwise tappable login button.
    func testLoginMethodSwitchesExposeTheirFormControls() {
        XCTAssertTrue(button(containing: "微信登录").waitForExistence(timeout: 10))

        button(containing: "手机号登录").tap()
        XCTAssertTrue(app.textFields["手机号"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["短信验证码"].exists)

        button(containing: "账号密码登录").tap()
        XCTAssertTrue(app.textFields["账号 / 手机号"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 3))
    }

    func testAccessibilityLargeTextKeepsLoginActionsReachable() {
        // Re-launch with the system accessibility content-size override. The
        // login page is intentionally scrollable; this guards against a
        // future visual refactor placing consent or registration below an
        // unreachable fixed-height container.
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        XCTAssertTrue(button(containing: "微信登录").waitForExistence(timeout: 10))
        XCTAssertTrue(button(containing: "家长注册").exists)
        XCTAssertTrue(button(containing: "忘记密码").exists)
        button(containing: "手机号登录").tap()
        XCTAssertTrue(app.textFields["手机号"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["短信验证码"].exists)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        attachScreenshot("report-detail")
        XCTAssertTrue(staticText(containing: "规则依据与适用范围").waitForExistence(timeout: 3))
        XCTAssertTrue(staticText(containing: "规则生效日期").exists)
        let back = button(containing: "返回")
        XCTAssertTrue(back.waitForExistence(timeout: 2))
        back.tap()
        // Report detail is opened from the “我的测评” root tab.  Returning
        // should preserve that tab, whose stable page title is the school
        // assessment title rather than the landing-page campaign copy.
        XCTAssertTrue(staticText(containing: "学校运动能力测评").waitForExistence(timeout: 3))

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

    /// Regression coverage for the two compact-width defects reported from a
    /// physical iPhone: status text overlapping the evaluation ring and the
    /// activity sheet expanding wider than the screen because of its hero image.
    func testParentEvaluationAndActivityStayInsideScreenBounds() {
        loginAndWaitForRoleSelection()
        button(containing: "家庭端").tap()
        button(containing: "去绑定孩子").tap()
        button(containing: "绑定孩子").tap()
        app.textFields["child-name-field"].tap()
        app.textFields["child-name-field"].typeText("王小明")
        app.textFields["child-binding-code-field"].tap()
        app.textFields["child-binding-code-field"].typeText("XS-S01")
        button(containing: "确认绑定").tap()

        button(containing: "我的测评").tap()
        XCTAssertTrue(staticText(containing: "学校运动能力测评").waitForExistence(timeout: 4))
        attachScreenshot("parent-evaluation-compact")

        button(containing: "首页").tap()
        let campaign = button(containing: "向上少年健康成长季")
        XCTAssertTrue(campaign.waitForExistence(timeout: 4))
        campaign.tap()
        XCTAssertTrue(staticText(containing: "活动说明").waitForExistence(timeout: 4))
        assertInsideScreen(staticText(containing: "活动说明"))
        assertInsideScreen(button(containing: "确认报名"))
        attachScreenshot("activity-detail-compact")
    }

    private func loginAndWaitForRoleSelection() {
        XCTAssertTrue(button(containing: "微信登录").waitForExistence(timeout: 10))
        XCTAssertTrue(button(containing: "手机号登录").exists)
        XCTAssertTrue(button(containing: "账号密码登录").exists)
        XCTAssertTrue(button(containing: "家长注册").exists)
        XCTAssertTrue(button(containing: "忘记密码").exists)

        // Keep all commercial login routes alive. A prior implementation
        // visually showed these choices but only left the phone route usable.
        button(containing: "手机号登录").tap()
        XCTAssertTrue(app.textFields["手机号"].waitForExistence(timeout: 2))
        button(containing: "账号密码登录").tap()
        XCTAssertTrue(app.textFields["账号 / 手机号"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.secureTextFields.firstMatch.exists)
        // This tap only selects WeChat because the account method is active;
        // the actual authorization attempt remains below the consent check.
        button(containing: "微信登录").tap()

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

    private func assertInsideScreen(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, file: file, line: line)
        let screen = XCUIScreen.main.screenshot().image.size
        XCTAssertGreaterThanOrEqual(element.frame.minX, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, screen.width, file: file, line: line)
    }
}
