import Foundation
import Security

struct Deck: Identifiable, Decodable, Hashable, BadgeCountProviding {
    let id: Int64
    let name: String
    let newCount: Int
    let learnCount: Int
    let dueCount: Int
    let contributesToBadge: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name
        case newCount = "new"
        case learnCount = "learn"
        case dueCount = "due"
        case contributesToBadge
    }

    init(id: Int64, name: String, newCount: Int, learnCount: Int, dueCount: Int, contributesToBadge: Bool = true) {
        self.id = id
        self.name = name
        self.newCount = newCount
        self.learnCount = learnCount
        self.dueCount = dueCount
        self.contributesToBadge = contributesToBadge
    }

    /// Older copies of the bundled Rust framework only returned an id and
    /// name. Keep those collections usable while treating unavailable
    /// scheduler counts as zero; a rebuilt framework supplies the real counts.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        newCount = try values.decodeIfPresent(Int.self, forKey: .newCount) ?? 0
        learnCount = try values.decodeIfPresent(Int.self, forKey: .learnCount) ?? 0
        dueCount = try values.decodeIfPresent(Int.self, forKey: .dueCount) ?? 0
        contributesToBadge = try values.decodeIfPresent(Bool.self, forKey: .contributesToBadge) ?? true
    }
}

struct ReviewCard: Decodable, Identifiable, Equatable {
    let id: Int64
    let question: String
    let answer: String
    let flag: UInt8

    init(id: Int64, question: String, answer: String, flag: UInt8 = 0) {
        self.id = id
        self.question = question
        self.answer = answer
        self.flag = flag
    }

    private enum CodingKeys: String, CodingKey { case id, question, answer, flag }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        question = try values.decode(String.self, forKey: .question)
        answer = try values.decode(String.self, forKey: .answer)
        flag = try values.decodeIfPresent(UInt8.self, forKey: .flag) ?? 0
    }
}

enum CardFlag: UInt8, CaseIterable, Identifiable {
    case none = 0, red, orange, green, blue, pink, turquoise, purple

    var id: Self { self }
    var title: String {
        switch self {
        case .none: return "No Flag"
        case .red: return "Red"
        case .orange: return "Orange"
        case .green: return "Green"
        case .blue: return "Blue"
        case .pink: return "Pink"
        case .turquoise: return "Turquoise"
        case .purple: return "Purple"
        }
    }

    var systemImage: String { self == .none ? "flag.slash" : "flag.fill" }
}

enum CardRating: Int32, CaseIterable, Identifiable {
    case again = 0, hard, good, easy
    var id: Self { self }
    var title: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

@MainActor
final class RSLibViewModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published private(set) var decks: [Deck] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var syncErrorMessage: String?
    @Published private(set) var lastSynced: Date?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var reviewCard: ReviewCard?
    @Published private(set) var isReviewLoading = false

    private let credentials = KeychainCredentials()
    private let fixture: UITestFixture?
    private let loadCachedDecks: () throws -> [Deck]
    private let fetchDecks: (String, String) throws -> [Deck]
    private let fetchNextCard: (Deck) throws -> ReviewCard?
    private let submitAnswer: (ReviewCard, Deck, CardRating, UInt32) throws -> Void
    private let setCardFlag: (ReviewCard, CardFlag) throws -> Void
    private let badgeController: AppIconBadgeController
    private var hasRestoredSession = false
    private var isLoadingCache = false
    private var activeReviewDeckID: Int64?
    private var reviewRequestID = UUID()

    @Published private(set) var completedReviewDeckID: Int64?

    init(
        fixture: UITestFixture? = UITestFixture.current,
        decks: [Deck] = [],
        isAuthenticated: Bool = false,
        loadCachedDecks: @escaping () throws -> [Deck] = AnkiRSLibBackend.loadCachedDecks,
        fetchDecks: @escaping (String, String) throws -> [Deck] = AnkiRSLibBackend.fetchDecks,
        fetchNextCard: @escaping (Deck) throws -> ReviewCard? = AnkiRSLibBackend.nextCard,
        submitAnswer: @escaping (ReviewCard, Deck, CardRating, UInt32) throws -> Void = AnkiRSLibBackend.answer,
        setCardFlag: @escaping (ReviewCard, CardFlag) throws -> Void = AnkiRSLibBackend.setFlag,
        badgeSetter: any AppIconBadgeSetting = UserNotificationBadgeSetter()
    ) {
        self.fixture = fixture
        self.decks = decks
        self.isAuthenticated = isAuthenticated
        self.loadCachedDecks = loadCachedDecks
        self.fetchDecks = fetchDecks
        self.fetchNextCard = fetchNextCard
        self.submitAnswer = submitAnswer
        self.setCardFlag = setCardFlag
        badgeController = AppIconBadgeController(setter: badgeSetter)

        guard let fixture, fixture != .signIn else { return }
        self.isAuthenticated = true
        self.decks = Self.fixtureDecks
        lastSynced = Date(timeIntervalSince1970: 1_700_000_000)
        if fixture == .cachedDecksSyncing { isSyncing = true }
        if fixture == .syncError { syncErrorMessage = "You appear to be offline." }
        if fixture == .reviewQuestion || fixture == .reviewAnswer {
            reviewCard = Self.fixtureCard
        }
    }

    var canSignIn: Bool { !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty }
    var lastSyncedText: String {
        if fixture != nil { return "Synced with UI test fixtures" }
        return lastSynced.map { "Synced \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Pull to refresh your collection"
    }

    func restoreSession() async {
        guard fixture == nil else { return }
        guard !hasRestoredSession else { return }
        hasRestoredSession = true
        guard let saved = credentials.read() else {
            await updateBadge()
            return
        }
        username = saved.username
        password = saved.password
        isAuthenticated = true
        await loadCache()
        await sync()
    }

    func syncWhenActive() async {
        guard fixture == nil, hasRestoredSession, isAuthenticated else { return }
        await sync()
    }

    func signIn() async {
        guard canSignIn else { return }
        isAuthenticated = true
        await sync(saveCredentialsOnSuccess: true)
        if syncErrorMessage != nil {
            isAuthenticated = false
            await updateBadge()
        }
    }

    func sync() async { await sync(saveCredentialsOnSuccess: false) }

    func logout() async {
        credentials.delete()
        username = ""
        password = ""
        decks = []
        errorMessage = nil
        syncErrorMessage = nil
        lastSynced = nil
        isAuthenticated = false
        reviewCard = nil
        activeReviewDeckID = nil
        completedReviewDeckID = nil
        await updateBadge()
    }

    func loadNextCard(in deck: Deck) async {
        if fixture != nil {
            reviewCard = fixture == .allCaughtUp ? nil : Self.fixtureCard
            if fixture == .allCaughtUp { completedReviewDeckID = deck.id }
            return
        }
        activeReviewDeckID = deck.id
        completedReviewDeckID = nil
        reviewCard = nil
        errorMessage = nil
        // Sync updates rslib's scheduler and collection together. Do not ask
        // for a card from that transient state, where an empty queue could be
        // mistaken for a completed deck. sync() resumes this request instead.
        guard !isSyncing else {
            isReviewLoading = true
            return
        }
        isReviewLoading = true
        let requestID = UUID()
        reviewRequestID = requestID
        do {
            let card = try await Task.detached(priority: .userInitiated) { [fetchNextCard] in
                let card = try fetchNextCard(deck)
                guard card == nil,
                      deck.newCount > 0 || deck.learnCount > 0 || deck.dueCount > 0 else {
                    return card
                }
                // The deck list and scheduler queue are loaded by separate
                // rslib calls. Retry once when their snapshots briefly differ
                // instead of presenting a false "all caught up" state.
                return try fetchNextCard(deck)
            }.value
            guard reviewRequestID == requestID, activeReviewDeckID == deck.id else { return }
            reviewCard = card
            if card == nil { completedReviewDeckID = deck.id }
        } catch {
            guard reviewRequestID == requestID, activeReviewDeckID == deck.id else { return }
            errorMessage = error.localizedDescription
            reviewCard = nil
        }
        if reviewRequestID == requestID { isReviewLoading = false }
    }

    func stopReviewing(deckID: Int64) {
        guard activeReviewDeckID == deckID else { return }
        activeReviewDeckID = nil
        reviewRequestID = UUID()
        reviewCard = nil
        isReviewLoading = false
        completedReviewDeckID = nil
    }

    func answer(_ card: ReviewCard, in deck: Deck, rating: CardRating, elapsed: TimeInterval) async {
        guard fixture == nil else {
            reviewCard = Self.fixtureCard
            return
        }
        isReviewLoading = true
        errorMessage = nil
        do {
            let milliseconds = UInt32(min(max(elapsed * 1_000, 1), Double(UInt32.max)))
            try await Task.detached(priority: .userInitiated) { [submitAnswer] in
                try submitAnswer(card, deck, rating, milliseconds)
            }.value
            await refreshDueCounts()
            if activeReviewDeckID == deck.id { await loadNextCard(in: deck) }
        } catch {
            errorMessage = error.localizedDescription
            isReviewLoading = false
        }
    }

    func setFlag(_ flag: CardFlag, on card: ReviewCard) async {
        guard fixture == nil else {
            reviewCard = ReviewCard(id: card.id, question: card.question, answer: card.answer, flag: flag.rawValue)
            return
        }
        errorMessage = nil
        do {
            try await Task.detached(priority: .userInitiated) { [setCardFlag] in
                try setCardFlag(card, flag)
            }.value
            guard reviewCard?.id == card.id else { return }
            reviewCard = ReviewCard(id: card.id, question: card.question, answer: card.answer, flag: flag.rawValue)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadCache() async {
        guard !isLoadingCache else { return }
        isLoadingCache = true
        defer { isLoadingCache = false }
        do {
            let cached = try await Task.detached(priority: .userInitiated) { [loadCachedDecks] in
                try loadCachedDecks()
            }.value
            decks = sorted(cached)
            await updateBadge()
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    private func sync(saveCredentialsOnSuccess: Bool) async {
        guard fixture == nil else { return }
        guard !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        syncErrorMessage = nil
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password
        var didSync = false
        do {
            let fetched = try await Task.detached(priority: .userInitiated) { [fetchDecks] in
                try fetchDecks(username, password)
            }.value
            decks = sorted(fetched)
            lastSynced = .now
            didSync = true
            if saveCredentialsOnSuccess { try credentials.save(username: username, password: password) }
            await updateBadge()
        } catch {
            syncErrorMessage = error.localizedDescription
        }
        // Reopen the collection only when a reviewer was opened during sync.
        // That refreshes the scheduler snapshot before resuming it, without
        // replacing the freshly synced deck list in ordinary sync flows.
        let shouldResumeReview = activeReviewDeckID != nil && reviewCard == nil && isReviewLoading
        if didSync && shouldResumeReview { await loadCache() }
        isSyncing = false
        await resumeReviewAfterSync()
    }

    private func resumeReviewAfterSync() async {
        guard reviewCard == nil,
              let activeReviewDeckID,
              let deck = decks.first(where: { $0.id == activeReviewDeckID }) else { return }
        await loadNextCard(in: deck)
    }

    private func sorted(_ decks: [Deck]) -> [Deck] {
        decks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func refreshDueCounts() async {
        guard fixture == nil, isAuthenticated else {
            await updateBadge()
            return
        }
        await loadCache()
    }

    func deckListDidAppear() async {
        guard !isSyncing else { return }
        await refreshDueCounts()
    }

    private func updateBadge() async {
        await badgeController.update(decks: decks, isAuthenticated: isAuthenticated)
    }

    func refreshBadge() async {
        await updateBadge()
    }
    static let fixtureDecks = [
        Deck(id: 10, name: "Spanish Essentials", newCount: 12, learnCount: 3, dueCount: 24),
        Deck(id: 20, name: "Human Anatomy", newCount: 5, learnCount: 0, dueCount: 18),
        Deck(id: 30, name: "World Capitals", newCount: 0, learnCount: 2, dueCount: 7),
    ]

    static let fixtureCard = ReviewCard(
        id: 101,
        question: "What is the capital of Argentina?",
        answer: "What is the capital of Argentina?<hr id=answer><b>Buenos Aires</b>"
    )
}

enum UITestFixture: String {
    case signIn = "sign-in"
    case deckList = "deck-list"
    case reviewQuestion = "review-question"
    case reviewAnswer = "revealed-answer"
    case allCaughtUp = "all-caught-up"
    case cachedDecksSyncing = "cached-decks-syncing"
    case syncError = "sync-error"

    static var current: Self? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--ui-test-fixture"),
              arguments.indices.contains(flag + 1) else { return nil }
        return Self(rawValue: arguments[flag + 1])
    }
}

private struct KeychainCredentials {
    private let service = "com.example.manki.ankiweb"
    private let account = "ankiweb-credentials"

    func save(username: String, password: String) throws {
        let value = try JSONEncoder().encode(Credentials(username: username, password: password))
        delete()
        let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecValueData: value, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func read() -> Credentials? {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary
        var item: CFTypeRef?
        guard SecItemCopyMatching(query, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    func delete() { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary) }
}

private struct Credentials: Codable { let username: String; let password: String }
private enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    var errorDescription: String? { "Unable to save your credentials securely (Keychain error \(String(describing: self)))." }
}
