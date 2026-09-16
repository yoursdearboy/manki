import XCTest
@testable import Manki

@MainActor
final class RSLibViewModelTests: XCTestCase {
    func testCachedDecksRemainVisibleWhileSyncing() async throws {
        let cached = try deck(id: 1, name: "Cached", due: 2)
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "background sync started")
        let model = RSLibViewModel(decks: [cached], isAuthenticated: true, loadCachedDecks: { [] }, fetchDecks: { _, _ in
            started.fulfill()
            gate.wait()
            return []
        }, badgeSetter: NoopBadgeSetter())

        let sync = Task { await model.sync() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(model.isSyncing)
        XCTAssertEqual(model.decks, [cached])
        gate.signal()
        await sync.value
    }

    func testSuccessfulSyncRefreshesDeckNamesAndCounts() async throws {
        let cached = try deck(id: 1, name: "Old", due: 1)
        let refreshed = try deck(id: 1, name: "Renamed", new: 3, learn: 2, due: 4)
        let model = RSLibViewModel(decks: [cached], isAuthenticated: true, loadCachedDecks: { [] }, fetchDecks: { _, _ in [refreshed] }, badgeSetter: NoopBadgeSetter())

        await model.sync()

        XCTAssertEqual(model.decks, [refreshed])
        XCTAssertNotNil(model.lastSynced)
        XCTAssertNil(model.syncErrorMessage)
    }

    func testFailedSyncRetainsCachedDecksAndCanBeRetried() async throws {
        let cached = try deck(id: 1, name: "Cached", due: 2)
        let model = RSLibViewModel(decks: [cached], isAuthenticated: true, loadCachedDecks: { [] }, fetchDecks: { _, _ in
            throw TestError.offline
        }, badgeSetter: NoopBadgeSetter())

        await model.sync()

        XCTAssertEqual(model.decks, [cached])
        XCTAssertNotNil(model.syncErrorMessage)
        XCTAssertFalse(model.isSyncing)
    }

    func testRepeatedSyncDoesNotOverlap() async throws {
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "one background sync started")
        started.assertForOverFulfill = true
        let model = RSLibViewModel(isAuthenticated: true, loadCachedDecks: { [] }, fetchDecks: { _, _ in
            started.fulfill()
            gate.wait()
            return []
        }, badgeSetter: NoopBadgeSetter())

        let first = Task { await model.sync() }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { await model.sync() }
        await second.value
        XCTAssertTrue(model.isSyncing)
        gate.signal()
        await first.value
    }

    private func deck(id: Int64, name: String, new: Int = 0, learn: Int = 0, due: Int = 0) throws -> Deck {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "name": name, "new": new, "learn": learn, "due": due])
        return try JSONDecoder().decode(Deck.self, from: data)
    }

    private enum TestError: LocalizedError {
        case offline
        var errorDescription: String? { "You appear to be offline. Try again." }
    }

    private struct NoopBadgeSetter: AppIconBadgeSetting {
        func setBadgeCount(_ count: Int) async {}
    }
}
