import Foundation
import XCTest

final class ReviewCardActionsUITests: XCTestCase {
    @MainActor
    func testCardActionsMenuContainsAddAndEdit() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-test-fixture", "review-question", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        application.launch()

        let actions = application.buttons["Card actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(application.buttons["Add new card"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["Edit card"].exists)
        XCTAssertTrue(application.buttons["Flag card"].exists)
        XCTAssertTrue(application.buttons["Deck settings"].exists)
    }

    @MainActor
    func testOpeningAddCardSheet() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-test-fixture", "review-question", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        application.launch()

        let actions = application.buttons["Card actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let addBtn = application.buttons["Add new card"]
        XCTAssertTrue(addBtn.waitForExistence(timeout: 5))
        addBtn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(application.navigationBars["Add Card"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["Cancel"].exists)
        XCTAssertTrue(application.buttons["Save"].exists)
    }
}
