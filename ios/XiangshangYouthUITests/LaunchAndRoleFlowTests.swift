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

        button(containing: "校长端").tap()
        XCTAssertTrue(staticText(containing: "学校运动健康总览").waitForExistence(timeout: 5))

        // A role dashboard is a root state, so exiting it must return to role
        // selection instead of exposing a stale NavigationStack back route.
        let exitPrincipal = button(containing: "退出校长端")
        XCTAssertTrue(exitPrincipal.exists)
        exitPrincipal.tap()
        XCTAssertTrue(button(containing: "家庭端").waitForExistence(timeout: 3))

        button(containing: "家庭端").tap()
        XCTAssertTrue(staticText(containing: "综合测评").waitForExistence(timeout: 5))
    }

    private func loginAndWaitForRoleSelection() {
        XCTAssertTrue(button(containing: "微信登录").waitForExistence(timeout: 10))
        XCTAssertTrue(button(containing: "注册新账号").exists)

        let consent = button(containing: "请阅读并同意")
        XCTAssertTrue(consent.exists)
        consent.tap()

        let login = button(containing: "微信授权登录")
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
