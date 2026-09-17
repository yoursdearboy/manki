import XCTest
@testable import DueBadgeCore

final class DueBadgeCountTests: XCTestCase {
    func testTotalIncludesEverySchedulerQueue() {
        let decks = [Counts(newCount: 2, learnCount: 3, dueCount: 5), Counts(newCount: 7, learnCount: 11, dueCount: 13)]
        XCTAssertEqual(DueBadgeCount.total(for: decks), 41)
    }

    func testNestedDeckAlreadyRepresentedByParentIsNotDoubleCounted() {
        let parent = Counts(newCount: 2, learnCount: 3, dueCount: 5)
        let child = Counts(newCount: 1, learnCount: 1, dueCount: 1, contributesToBadge: false)
        XCTAssertEqual(DueBadgeCount.total(for: [parent, child]), 10)
    }

    func testEmptyCollectionClearsBadgeCount() {
        XCTAssertEqual(DueBadgeCount.total(for: [Counts]()), 0)
    }

    func testTotalSaturatesInsteadOfOverflowing() {
        XCTAssertEqual(DueBadgeCount.total(for: [Counts(newCount: Int.max, learnCount: 1, dueCount: 1)]), Int.max)
    }

    func testPreferencesChooseQueuesAndDecks() {
        let defaults = makeDefaults()
        let preferences = BadgePreferences(defaults: defaults)
        preferences.includesNew = false
        preferences.includesLearn = true
        preferences.includesDue = true
        preferences.setIncludesDeck(false, deckID: 2)

        let decks = [IdentifiedCounts(id: 1, newCount: 10, learnCount: 2, dueCount: 3), IdentifiedCounts(id: 2, newCount: 10, learnCount: 20, dueCount: 30)]
        XCTAssertEqual(preferences.total(for: decks), 5)
    }

    func testPreferencesDefaultToAllQueuesAndDecks() {
        let preferences = BadgePreferences(defaults: makeDefaults())
        XCTAssertEqual(preferences.total(for: [IdentifiedCounts(id: 1, newCount: 2, learnCount: 3, dueCount: 5)]), 10)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DueBadgeCountTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct Counts: BadgeCountProviding {
    let newCount: Int
    let learnCount: Int
    let dueCount: Int
    var contributesToBadge = true
}

private struct IdentifiedCounts: BadgeCountProviding, Identifiable {
    let id: Int64
    let newCount: Int
    let learnCount: Int
    let dueCount: Int
    var contributesToBadge = true
}
