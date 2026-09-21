import Foundation
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
    func testFullSyncDirectionChoice() throws {
        capture(fixture: "full-sync-choice") { application in
            application.alerts.staticTexts["Choose which collection to keep"]
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
        capture(fixture: "review-question") { application in
            XCTAssertTrue(application.buttons["Replay audio"].waitForExistence(timeout: 10))
            return application.buttons["SHOW ANSWER"]
        }
    }

    @MainActor
    func testRedFlagCard() throws {
        capture(fixture: "red-flag-card") { $0.images["Red flag"] }
    }

    @MainActor
    func testCardActionsMenu() throws {
        let application = launch(fixture: "review-question")
        let actions = application.buttons["Card actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        tapCenter(of: actions)
        let flagCard = application.buttons["Flag card"]
        XCTAssertTrue(flagCard.waitForExistence(timeout: 5))
        tapCenter(of: flagCard)
        XCTAssertTrue(application.buttons["Red"].waitForExistence(timeout: 5))

        attachScreenshots(named: "card-actions", application: application)
    }

    @MainActor
    func testTappingReviewCardRevealsAnswer() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-test-fixture", "review-question", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        application.launch()

        let question = application.staticTexts["What is the capital of Argentina?"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        question.tap()
        XCTAssertTrue(application.staticTexts["Buenos Aires"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["Replay audio"].exists)
    }

    @MainActor
    func testDeckContextMenu() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-test-fixture", "deck-list", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        application.launch()

        openDeckContextMenu(in: application)
        let settingsAction = application.buttons["Deck settings"]
        XCTAssertTrue(settingsAction.waitForExistence(timeout: 5))

        attachScreenshots(named: "deck-context-menu", application: application)
    }

    @MainActor
    func testDeckSettingsWithExtraReminders() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-test-fixture", "deck-list", "--ui-test-deck-reminders", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        application.launch()

        openDeckContextMenu(in: application)
        let settingsAction = application.buttons["Deck settings"]
        XCTAssertTrue(settingsAction.waitForExistence(timeout: 5))
        settingsAction.tap()
        XCTAssertTrue(application.switches["Include this deck in count"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["deck-reminder-delete-09-00"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["deck-reminder-delete-18-00"].exists)

        attachScreenshots(named: "deck-settings-extra-reminders", application: application)
    }

    @MainActor
    private func openDeckContextMenu(in application: XCUIApplication) {
        let deck = application.staticTexts["Spanish Essentials"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        deck.press(forDuration: 1)
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testRevealedAnswer() throws {
        capture(fixture: "revealed-answer") { application in
            XCTAssertTrue(application.buttons["Replay audio"].waitForExistence(timeout: 10))
            return application.staticTexts["Buenos Aires"]
        }
    }

    @MainActor
    func testAllCaughtUpStaysInReviewer() throws {
        capture(fixture: "all-caught-up") { $0.staticTexts["all caught up"] }
    }

    @MainActor
    private func capture(fixture: String, readyElement: (XCUIApplication) -> XCUIElement) {
        let application = launch(fixture: fixture)

        XCTAssertTrue(readyElement(application).waitForExistence(timeout: 10), "The \(fixture) fixture did not become ready")
        attachScreenshots(named: fixture, application: application)
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

        attachScreenshots(named: confirmingLogout ? "logout-confirmation" : "settings", application: application)
    }

    @MainActor
    private func launch(fixture: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let application = XCUIApplication()
        application.launchArguments = ["--ui-test-fixture", fixture, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        application.launch()
        return application
    }

    @MainActor
    private func attachScreenshots(named name: String, application: XCUIApplication) {
        attachScreenshot(named: "\(name)-portrait.png")
        guard ProcessInfo.processInfo.environment["MANKI_CAPTURE_LANDSCAPE"] == "1" else {
            return
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(application.wait(for: .runningForeground, timeout: 5))
        sleep(1)
        attachScreenshot(named: "\(name)-landscape.png")
        XCUIDevice.shared.orientation = .portrait
    }

    /// SwiftUI menu labels can have a valid accessibility frame while XCTest
    /// still reports no synthesized hit point. Tapping the element's explicit
    /// center avoids XCTest's failing scroll-to-visible fallback.
    @MainActor
    private func tapCenter(of element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
