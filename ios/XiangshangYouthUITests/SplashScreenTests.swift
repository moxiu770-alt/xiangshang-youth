import XCTest

/// Guards the agreed pure-poster launch experience.  The hold argument is a
/// test-only timing seam; it never changes the production two-second splash.
final class SplashScreenTests: XCTestCase {
    func testLaunchShowsTheBrandedPurePoster() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-splash-hold"]
        app.launch()

        XCTAssertTrue(app.images["向上少年启动页"].waitForExistence(timeout: 2))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "launch-poster"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
