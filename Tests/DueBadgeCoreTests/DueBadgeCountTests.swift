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
}

private struct Counts: BadgeCountProviding {
    let newCount: Int
    let learnCount: Int
    let dueCount: Int
    var contributesToBadge = true
}
