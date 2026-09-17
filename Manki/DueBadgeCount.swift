protocol BadgeCountProviding {
    var newCount: Int { get }
    var learnCount: Int { get }
    var dueCount: Int { get }
    var contributesToBadge: Bool { get }
}

enum DueBadgeCount {
    /// Anki presents new, learning, and review cards as the three parts of the
    /// currently available study queue. Use those scheduler-provided values
    /// rather than attempting to reproduce scheduling rules in the app.
    static func total<Decks: Sequence>(for decks: Decks) -> Int where Decks.Element: BadgeCountProviding {
        decks.reduce(0) { total, deck in
            guard deck.contributesToBadge else { return total }
            return [deck.newCount, deck.learnCount, deck.dueCount].reduce(total, addingWithoutOverflow)
        }
    }

    static func addingWithoutOverflow(_ lhs: Int, _ rhs: Int) -> Int {
        guard rhs > 0, lhs <= Int.max - rhs else { return rhs > 0 ? Int.max : lhs }
        return lhs + rhs
    }
}
