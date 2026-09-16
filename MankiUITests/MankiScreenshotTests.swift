import XCTest

final class MankiScreenshotTests: XCTestCase {
    @MainActor
    func testSignIn() throws {
        capture(fixture: "sign-in") { $0.staticTexts["make every review count"] }
    }

    @MainActor
    func testDeckList() throws {
        capture(fixture: "deck-list") { $0.staticTexts["your decks"] }
    }

    @MainActor
    func testSettings() throws {
        captureSettings(confirmingLogout: false)
    }

    @MainActor
    func testLogoutConfirmation() throws {
        captureSettings(confirmingLogout: true)
    }

    @MainActor
    func testReviewQuestion() throws {
        capture(fixture: "review-question") { $0.buttons["SHOW ANSWER"] }
    }

    @MainActor
    func testRevealedAnswer() throws {
        capture(fixture: "revealed-answer") { $0.staticTexts["Buenos Aires"] }
    }

    @MainActor
    private func capture(fixture: String, readyElement: (XCUIApplication) -> XCUIElement) {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-test-fixture", fixture, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        application.launch()

        XCTAssertTrue(readyElement(application).waitForExistence(timeout: 10), "The \(fixture) fixture did not become ready")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(fixture).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func captureSettings(confirmingLogout: Bool) {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-test-fixture", "deck-list", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        application.launch()

        let settingsButton = application.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "The deck-list fixture did not become ready")
        settingsButton.tap()

        let logoutButton = application.buttons["Log out of Manki"]
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 5), "The settings screen did not become ready")
        if confirmingLogout {
            logoutButton.tap()
            XCTAssertTrue(application.sheets.staticTexts["Log out of Manki?"].waitForExistence(timeout: 5), "The logout confirmation did not appear")
        }

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = confirmingLogout ? "logout-confirmation.png" : "settings.png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
