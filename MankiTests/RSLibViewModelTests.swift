import XCTest
@testable import Manki

@MainActor
final class RSLibViewModelTests: XCTestCase {
    func testCardSwipeMapsFourDirectionsToRatings() {
        XCTAssertEqual(CardSwipe.rating(for: CGSize(width: 0, height: 100)), .again)
        XCTAssertEqual(CardSwipe.rating(for: CGSize(width: -100, height: 0)), .hard)
        XCTAssertEqual(CardSwipe.rating(for: CGSize(width: 100, height: 0)), .good)
        XCTAssertEqual(CardSwipe.rating(for: CGSize(width: 0, height: -100)), .easy)
    }

    func testCardSwipeRequiresThresholdAndUsesDominantAxis() {
        XCTAssertNil(CardSwipe.rating(for: CGSize(width: 79, height: 20)))
        XCTAssertEqual(CardSwipe.rating(for: CGSize(width: -100, height: 90)), .hard)
        XCTAssertEqual(CardSwipe.rating(for: CGSize(width: 90, height: 100)), .again)
    }

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

    func testOpeningDeckDuringSyncWaitsForSyncBeforeLoadingCard() async throws {
        let deck = try deck(id: 1, name: "Deck", due: 1)
        let expectedCard = ReviewCard(id: 10, question: "Question", answer: "Answer")
        let gate = DispatchSemaphore(value: 0)
        let syncStarted = expectation(description: "background sync started")
        let model = RSLibViewModel(
            decks: [deck],
            isAuthenticated: true,
            loadCachedDecks: { [] },
            fetchDecks: { _, _ in
                syncStarted.fulfill()
                gate.wait()
                return [deck]
            },
            fetchNextCard: { _ in expectedCard },
            badgeSetter: NoopBadgeSetter()
        )

        let sync = Task { await model.sync() }
        await fulfillment(of: [syncStarted], timeout: 2)
        await model.loadNextCard(in: deck)

        XCTAssertNil(model.reviewCard)
        XCTAssertTrue(model.isReviewLoading)
        XCTAssertNil(model.completedReviewDeckID)

        gate.signal()
        await sync.value

        XCTAssertEqual(model.reviewCard, expectedCard)
        XCTAssertNil(model.completedReviewDeckID)
    }

    func testLoadingDeckClearsStaleCardBeforeRequestCompletes() async throws {
        let firstDeck = try deck(id: 1, name: "First")
        let secondDeck = try deck(id: 2, name: "Second")
        let staleCard = ReviewCard(id: 10, question: "Old", answer: "Old")
        let gate = DispatchSemaphore(value: 0)
        let secondStarted = expectation(description: "second deck request started")
        let model = RSLibViewModel(
            isAuthenticated: true,
            fetchNextCard: { deck in
                if deck.id == firstDeck.id { return staleCard }
                secondStarted.fulfill()
                gate.wait()
                return nil
            },
            badgeSetter: NoopBadgeSetter()
        )

        await model.loadNextCard(in: firstDeck)
        let loadingSecond = Task { await model.loadNextCard(in: secondDeck) }
        await fulfillment(of: [secondStarted], timeout: 2)

        XCTAssertNil(model.reviewCard)
        XCTAssertTrue(model.isReviewLoading)
        gate.signal()
        await loadingSecond.value
        XCTAssertEqual(model.completedReviewDeckID, secondDeck.id)
    }

    func testEmptyQueueRetriesWhenDeckSnapshotHasNoDueCount() async throws {
        let deck = try deck(id: 1, name: "Deck")
        let expectedCard = ReviewCard(id: 10, question: "Question", answer: "Answer")
        var attempts = 0
        let model = RSLibViewModel(
            isAuthenticated: true,
            fetchNextCard: { _ in
                attempts += 1
                return attempts == 1 ? nil : expectedCard
            },
            badgeSetter: NoopBadgeSetter()
        )

        await model.loadNextCard(in: deck)

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(model.reviewCard, expectedCard)
        XCTAssertNil(model.completedReviewDeckID)
    }

    func testObsoleteDeckRequestCannotReplaceCurrentCard() async throws {
        let slowDeck = try deck(id: 1, name: "Slow")
        let currentDeck = try deck(id: 2, name: "Current")
        let staleCard = ReviewCard(id: 10, question: "Old", answer: "Old")
        let currentCard = ReviewCard(id: 20, question: "Current", answer: "Current")
        let gate = DispatchSemaphore(value: 0)
        let slowStarted = expectation(description: "slow request started")
        let model = RSLibViewModel(
            isAuthenticated: true,
            fetchNextCard: { deck in
                if deck.id == slowDeck.id {
                    slowStarted.fulfill()
                    gate.wait()
                    return staleCard
                }
                return currentCard
            },
            badgeSetter: NoopBadgeSetter()
        )

        let slowLoad = Task { await model.loadNextCard(in: slowDeck) }
        await fulfillment(of: [slowStarted], timeout: 2)
        await model.loadNextCard(in: currentDeck)
        gate.signal()
        await slowLoad.value

        XCTAssertEqual(model.reviewCard, currentCard)
    }

    func testDeckListAppearanceReloadsCachedCounts() async throws {
        let oldDeck = try deck(id: 1, name: "Deck", due: 3)
        let refreshedDeck = try deck(id: 1, name: "Deck", due: 2)
        var loads = 0
        let model = RSLibViewModel(
            decks: [oldDeck],
            isAuthenticated: true,
            loadCachedDecks: { loads += 1; return [refreshedDeck] },
            badgeSetter: NoopBadgeSetter()
        )

        await model.deckListDidAppear()

        XCTAssertEqual(loads, 1)
        XCTAssertEqual(model.decks, [refreshedDeck])
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
