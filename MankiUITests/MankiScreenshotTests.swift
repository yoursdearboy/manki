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
    func testCachedDecksRemainVisibleWhileSyncing() throws {
        capture(fixture: "cached-decks-syncing") { application in
            application.staticTexts["your decks"]
        }
    }

    @MainActor
    func testRetryableBackgroundSyncError() throws {
        capture(fixture: "sync-error") { application in
            application.buttons["Sync failed. Retry sync"]
        }
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
    func testTappingCardRevealsAnswer() throws {
        let application = launch(fixture: "review-question")
        let answerButton = application.buttons["SHOW ANSWER"]
        XCTAssertTrue(answerButton.waitForExistence(timeout: 10))
        application.staticTexts["What is the capital of Argentina?"].tap()
        XCTAssertTrue(application.staticTexts["Buenos Aires"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDeckSettings() throws {
        let application = launch(fixture: "review-question")
        let settingsButton = application.buttons["Deck settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()
        XCTAssertTrue(application.sliders["Vertical card size"].waitForExistence(timeout: 5))
        attachScreenshot(named: "deck-settings")
    }

    @MainActor
    func testRevealedAnswer() throws {
        capture(fixture: "revealed-answer") { $0.staticTexts["Buenos Aires"] }
    }

    @MainActor
    func testAllCaughtUpStaysInReviewer() throws {
        capture(fixture: "all-caught-up") { $0.staticTexts["all caught up"] }
    }

    @MainActor
    private func capture(fixture: String, readyElement: (XCUIApplication) -> XCUIElement) {
        let application = launch(fixture: fixture)

        XCTAssertTrue(readyElement(application).waitForExistence(timeout: 10), "The \(fixture) fixture did not become ready")
        attachScreenshot(named: fixture)
    }

    @MainActor
    private func launch(fixture: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-test-fixture", fixture, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        application.launch()
        return application
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name).png"
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
