import Foundation

struct BadgePreferences {
    static let includeNewKey = "badge.includeNew"
    static let includeLearnKey = "badge.includeLearn"
    static let includeDueKey = "badge.includeDue"
    static let excludedDecksKey = "badge.excludedDeckIDs"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Self.includeNewKey: true,
            Self.includeLearnKey: true,
            Self.includeDueKey: true,
        ])
    }

    var includesNew: Bool {
        get { defaults.bool(forKey: Self.includeNewKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.includeNewKey) }
    }

    var includesLearn: Bool {
        get { defaults.bool(forKey: Self.includeLearnKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.includeLearnKey) }
    }

    var includesDue: Bool {
        get { defaults.bool(forKey: Self.includeDueKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.includeDueKey) }
    }

    func includesDeck(_ deckID: Int64) -> Bool {
        !excludedDeckIDs.contains(deckID)
    }

    func setIncludesDeck(_ included: Bool, deckID: Int64) {
        var ids = excludedDeckIDs
        if included { ids.remove(deckID) } else { ids.insert(deckID) }
        defaults.set(ids.map(String.init), forKey: Self.excludedDecksKey)
    }

    func total<Decks: Sequence>(for decks: Decks) -> Int where Decks.Element: BadgeCountProviding & Identifiable, Decks.Element.ID == Int64 {
        decks.reduce(0) { total, deck in
            guard deck.contributesToBadge, includesDeck(deck.id) else { return total }
            let values = [includesNew ? deck.newCount : 0, includesLearn ? deck.learnCount : 0, includesDue ? deck.dueCount : 0]
            return values.reduce(total, DueBadgeCount.addingWithoutOverflow)
        }
    }

    private var excludedDeckIDs: Set<Int64> {
        Set(defaults.stringArray(forKey: Self.excludedDecksKey)?.compactMap(Int64.init) ?? [])
    }
}
