import XCTest
@testable import Manki

@MainActor
final class RSLibViewModelActionTests: XCTestCase {
    func testAddCardValidatesTrimmedFront() async {
        let model = RSLibViewModel(isAuthenticated: true, badgeSetter: NoopBadgeSetter())
        do {
            try await model.addCard(deckID: 10, front: "   \n  ", back: "Back")
            XCTFail("Should have thrown emptyFront error")
        } catch RSLibViewModel.ValidationError.emptyFront {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAddCardAllowsBlankBack() async throws {
        var createdFront: String?
        var createdBack: String?
        let model = RSLibViewModel(
            isAuthenticated: true,
            createNote: { _, front, back in
                createdFront = front
                createdBack = back
            },
            badgeSetter: NoopBadgeSetter()
        )

        try await model.addCard(deckID: 10, front: " Question ", back: "")

        XCTAssertEqual(createdFront, "Question")
        XCTAssertEqual(createdBack, "")
    }

    func testUpdateCurrentCardRefreshesVisibleCard() async throws {
        let initialCard = ReviewCard(id: 101, question: "Old Q", answer: "Old A")
        var updatedFront: String?
        var updatedBack: String?
        let model = RSLibViewModel(
            isAuthenticated: true,
            fetchNextCard: { _ in initialCard },
            updateNote: { _, front, back in
                updatedFront = front
                updatedBack = back
            },
            badgeSetter: NoopBadgeSetter()
        )

        let deck = RSLibViewModel.fixtureDecks[0]
        await model.loadNextCard(in: deck)

        try await model.updateCurrentCard(cardID: 101, front: "New Q", back: "New A")

        XCTAssertEqual(updatedFront, "New Q")
        XCTAssertEqual(updatedBack, "New A")
        XCTAssertEqual(model.reviewCard?.question, "New Q")
        XCTAssertEqual(model.reviewCard?.answer, "New A")
    }

    private struct NoopBadgeSetter: AppIconBadgeSetting {
        func setBadgeCount(_ count: Int) async {}
    }
}
