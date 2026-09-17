import Foundation
import XCTest
@testable import DueBadgeCore

final class ReviewCardSettingsTests: XCTestCase {
    func testUsesFiftyPercentByDefault() {
        let defaults = makeDefaults()
        XCTAssertEqual(ReviewCardSettings(defaults: defaults).height(for: 12), 0.5)
    }

    func testStoresHeightSeparatelyForEachDeck() {
        let defaults = makeDefaults()
        let settings = ReviewCardSettings(defaults: defaults)

        settings.setHeight(0.4, for: 12)
        settings.setHeight(0.7, for: 34)

        XCTAssertEqual(settings.height(for: 12), 0.4)
        XCTAssertEqual(settings.height(for: 34), 0.7)
    }

    func testClampsHeightToSliderBounds() {
        let defaults = makeDefaults()
        let settings = ReviewCardSettings(defaults: defaults)

        settings.setHeight(0.1, for: 12)
        settings.setHeight(1, for: 34)

        XCTAssertEqual(settings.height(for: 12), 0.3)
        XCTAssertEqual(settings.height(for: 34), 0.8)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ReviewCardSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
