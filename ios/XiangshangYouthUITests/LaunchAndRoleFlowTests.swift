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

    func testPublicFamilyLoginOnlyOffersFamilyWorkbench() {
        loginAndWaitForRoleSelection()
        attachScreenshot("role-picker")

        XCTAssertTrue(button(containing: "家庭端").waitForExistence(timeout: 2))
        // Public registration and WeChat fallback create family accounts only.
        // A teacher workbench can only be supplied by a school-authorized
        // session, never by a role selector bundled in the public app.
        XCTAssertFalse(button(containing: "学校端").exists)
        XCTAssertFalse(button(containing: "校长端").exists)
        button(containing: "家庭端").tap()
        XCTAssertTrue(staticText(containing: "综合测评").waitForExistence(timeout: 5))
        XCTAssertFalse(button(containing: "返回").exists)
    }

    func testSchoolProvisionedTeacherFixtureCoversTeacherWorkbench() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launchEnvironment["XS_DEBUG_ROLE"] = "teacher"
        app.launch()
        XCTAssertTrue(staticText(containing: "班级健康概览").waitForExistence(timeout: 5))
        attachScreenshot("teacher-home")
        XCTAssertFalse(button(containing: "返回").exists)

        let classBoard = button(containing: "班级看板")
        XCTAssertTrue(classBoard.waitForExistence(timeout: 2))
        classBoard.tap()
        XCTAssertTrue(staticText(containing: "班级数据看板").waitForExistence(timeout: 3))
        button(containing: "返回").tap()
        XCTAssertTrue(staticText(containing: "班级健康概览").waitForExistence(timeout: 3))

        let tasks = button(containing: "查看延时课")
        XCTAssertTrue(tasks.waitForExistence(timeout: 2))
        tasks.tap()
        XCTAssertTrue(staticText(containing: "延时课程上传").waitForExistence(timeout: 3))
        let task = button(containing: "2026年秋季综合运动能力测评")
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        task.tap()
        XCTAssertTrue(staticText(containing: "点击学生按现场队列").waitForExistence(timeout: 3))
        // This student belongs to the fixture's authorized c31 scope. The
        // task route must render a scoped roster rather than a schoolwide list.
        // Command authorization and transition rules are unit-tested.
        let student = button(containing: "王小明")
        XCTAssertTrue(student.waitForExistence(timeout: 3))
        button(containing: "返回").tap()
        button(containing: "返回").tap()

        let review = button(containing: "预警中心")
        XCTAssertTrue(review.waitForExistence(timeout: 2))
        review.tap()
        XCTAssertTrue(staticText(containing: "预警中心").waitForExistence(timeout: 3))
        button(containing: "返回").tap()

        let teacherMessages = button(containing: "消息通知")
        XCTAssertTrue(teacherMessages.waitForExistence(timeout: 3))
        teacherMessages.tap()
        XCTAssertTrue(staticText(containing: "消息中心").waitForExistence(timeout: 3))
        let messageBack = button(containing: "返回")
        XCTAssertTrue(messageBack.waitForExistence(timeout: 2))
        messageBack.tap()
        XCTAssertTrue(staticText(containing: "班级健康概览").waitForExistence(timeout: 3))
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
