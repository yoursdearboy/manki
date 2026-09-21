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

    func testFullSyncConflictPromptsForDirectionAndUploadsSelection() async throws {
        let localDeck = try deck(id: 1, name: "Local", due: 2)
        let uploadedDeck = try deck(id: 1, name: "Uploaded", due: 2)
        var selectedDirection: FullSyncDirection?
        let model = RSLibViewModel(
            decks: [localDeck],
            isAuthenticated: true,
            fetchDecks: { _, _ in
                throw AnkiRSLibError.syncFailed(
                    "Anki requires a full-sync direction choice; refusing to overwrite either collection"
                )
            },
            resolveFullSync: { _, _, direction in
                selectedDirection = direction
                return [uploadedDeck]
            },
            badgeSetter: NoopBadgeSetter()
        )

        await model.sync()

        XCTAssertTrue(model.needsFullSyncChoice)
        XCTAssertNil(model.syncErrorMessage)
        XCTAssertEqual(model.decks, [localDeck])

        await model.resolveFullSync(.upload)

        XCTAssertEqual(selectedDirection, .upload)
        XCTAssertFalse(model.needsFullSyncChoice)
        XCTAssertEqual(model.decks, [uploadedDeck])
        XCTAssertNotNil(model.lastSynced)
    }

    func testCancellingFullSyncChoiceKeepsCollectionUnchanged() async throws {
        let localDeck = try deck(id: 1, name: "Local", due: 2)
        let model = RSLibViewModel(
            decks: [localDeck],
            isAuthenticated: true,
            fetchDecks: { _, _ in
                throw AnkiRSLibError.syncFailed("Anki requires a full-sync direction choice")
            },
            badgeSetter: NoopBadgeSetter()
        )

        await model.sync()
        model.cancelFullSync()

        XCTAssertFalse(model.needsFullSyncChoice)
        XCTAssertEqual(model.decks, [localDeck])
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

    func testPeriodicSyncRunsWhenNotReviewing() async {
        var syncs = 0
        let model = RSLibViewModel(isAuthenticated: true, loadCachedDecks: { [] }, fetchDecks: { _, _ in
            syncs += 1
            return []
        }, badgeSetter: NoopBadgeSetter())

        await model.restoreSession()
        await model.periodicSync()

        XCTAssertEqual(syncs, 1)
    }

    func testPeriodicSyncWaitsUntilReviewCloses() async throws {
        let deck = try deck(id: 1, name: "Deck")
        let card = ReviewCard(id: 10, question: "Question", answer: "Answer")
        var syncs = 0
        let model = RSLibViewModel(
            decks: [deck],
            isAuthenticated: true,
            loadCachedDecks: { [] },
            fetchDecks: { _, _ in syncs += 1; return [deck] },
            fetchNextCard: { _ in card },
            badgeSetter: NoopBadgeSetter()
        )
        await model.restoreSession()
        await model.loadNextCard(in: deck)

        await model.periodicSync()
        XCTAssertEqual(syncs, 0)

        await model.stopReviewing(deckID: deck.id)
        XCTAssertEqual(syncs, 1)
    }

    func testOpeningDeckDuringSyncWaitsForSyncBeforeLoadingCard() async throws {
        let deck = try deck(id: 1, name: "Deck", due: 1)
        let expectedCard = ReviewCard(id: 10, question: "Question", answer: "Answer")
        let gate = DispatchSemaphore(value: 0)
        let syncStarted = expectation(description: "background sync started")
        var cacheLoads = 0
        let model = RSLibViewModel(
            decks: [deck],
            isAuthenticated: true,
            loadCachedDecks: { cacheLoads += 1; return [deck] },
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

        XCTAssertEqual(cacheLoads, 1)
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

    func testDueDeckRetriesAnUnexpectedEmptyQueue() async throws {
        let deck = try deck(id: 1, name: "Deck", due: 1)
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

    func testAnswerImmediatelyShowsPrefetchedCard() async throws {
        let deck = try deck(id: 1, name: "Deck", due: 2)
        let first = ReviewCard(id: 10, question: "First", answer: "Answer")
        let second = ReviewCard(id: 20, question: "Second", answer: "Answer")
        let answerStarted = expectation(description: "answer started")
        let gate = DispatchSemaphore(value: 0)
        let model = RSLibViewModel(
            decks: [deck],
            isAuthenticated: true,
            loadCachedDecks: { [deck] },
            fetchReviewQueue: { _ in [first, second] },
            submitAnswer: { _, _, _, _ in
                answerStarted.fulfill()
                gate.wait()
            },
            badgeSetter: NoopBadgeSetter()
        )
        await model.loadNextCard(in: deck)

        let answering = Task { await model.answer(first, in: deck, rating: .good, elapsed: 1) }
        await fulfillment(of: [answerStarted], timeout: 2)

        XCTAssertEqual(model.reviewCard, second)
        XCTAssertFalse(model.isReviewLoading)
        gate.signal()
        await answering.value
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

    func testSettingFlagPersistsAndUpdatesVisibleCard() async throws {
        let deck = try deck(id: 1, name: "Deck")
        let card = ReviewCard(id: 10, question: "Question", answer: "Answer")
        var persistedFlag: CardFlag?
        let model = RSLibViewModel(
            isAuthenticated: true,
            fetchNextCard: { _ in card },
            setCardFlag: { _, flag in persistedFlag = flag },
            badgeSetter: NoopBadgeSetter()
        )
        await model.loadNextCard(in: deck)

        await model.setFlag(.purple, on: card)

        XCTAssertEqual(persistedFlag, .purple)
        XCTAssertEqual(model.reviewCard?.flag, CardFlag.purple.rawValue)
    }

    func testReviewCardDecodesMissingFlagAsNone() throws {
        let data = try JSONSerialization.data(withJSONObject: ["id": 10, "question": "Question", "answer": "Answer"])
        let card = try JSONDecoder().decode(ReviewCard.self, from: data)

        XCTAssertEqual(card.flag, CardFlag.none.rawValue)
        XCTAssertTrue(card.questionAudio.isEmpty)
        XCTAssertTrue(card.answerAudio.isEmpty)
    }

    func testReviewCardDecodesAudioForEachSide() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": 10,
            "question": "Question",
            "answer": "Answer",
            "questionAudio": ["front.mp3"],
            "answerAudio": ["back-a.mp3", "back-b.ogg"],
        ])

        let card = try JSONDecoder().decode(ReviewCard.self, from: data)

        XCTAssertEqual(card.questionAudio, ["front.mp3"])
        XCTAssertEqual(card.answerAudio, ["back-a.mp3", "back-b.ogg"])
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
