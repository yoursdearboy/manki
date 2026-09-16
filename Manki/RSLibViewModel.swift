import Foundation
import Security

struct Deck: Identifiable, Decodable, Hashable {
    let id: Int64
    let name: String
    let newCount: Int
    let learnCount: Int
    let dueCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, name
        case newCount = "new"
        case learnCount = "learn"
        case dueCount = "due"
    }

    init(id: Int64, name: String, newCount: Int, learnCount: Int, dueCount: Int) {
        self.id = id
        self.name = name
        self.newCount = newCount
        self.learnCount = learnCount
        self.dueCount = dueCount
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
    }
}

struct ReviewCard: Decodable, Identifiable, Equatable {
    let id: Int64
    let question: String
    let answer: String
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
    @Published private(set) var lastSynced: Date?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var reviewCard: ReviewCard?
    @Published private(set) var isReviewLoading = false

    private let credentials = KeychainCredentials()
    private let fixture: UITestFixture?

    init(fixture: UITestFixture? = UITestFixture.current) {
        self.fixture = fixture

        guard let fixture, fixture != .signIn else { return }
        isAuthenticated = true
        decks = Self.fixtureDecks
        lastSynced = Date(timeIntervalSince1970: 1_700_000_000)
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
        guard let saved = credentials.read() else { return }
        username = saved.username
        password = saved.password
        isAuthenticated = true
        await sync()
    }

    func signIn() async {
        guard canSignIn else { return }
        isAuthenticated = true
        await sync(saveCredentialsOnSuccess: true)
        if errorMessage != nil { isAuthenticated = false }
    }

    func sync() async { await sync(saveCredentialsOnSuccess: false) }

    func logout() {
        credentials.delete()
        username = ""
        password = ""
        decks = []
        errorMessage = nil
        lastSynced = nil
        isAuthenticated = false
        reviewCard = nil
    }

    func loadNextCard(in deck: Deck) async {
        if fixture != nil {
            reviewCard = Self.fixtureCard
            return
        }
        isReviewLoading = true
        errorMessage = nil
        do {
            reviewCard = try await Task.detached(priority: .userInitiated) {
                try AnkiRSLibBackend.nextCard(in: deck)
            }.value
        } catch {
            errorMessage = error.localizedDescription
            reviewCard = nil
        }
        isReviewLoading = false
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
            try await Task.detached(priority: .userInitiated) {
                try AnkiRSLibBackend.answer(card, in: deck, rating: rating, millisecondsTaken: milliseconds)
            }.value
            await loadNextCard(in: deck)
        } catch {
            errorMessage = error.localizedDescription
            isReviewLoading = false
        }
    }

    private func sync(saveCredentialsOnSuccess: Bool) async {
        guard fixture == nil else { return }
        isSyncing = true
        errorMessage = nil
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password
        do {
            let fetched = try await Task.detached(priority: .userInitiated) {
                try AnkiRSLibBackend.fetchDecks(username: username, password: password)
            }.value
            decks = fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            lastSynced = .now
            if saveCredentialsOnSuccess { try credentials.save(username: username, password: password) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSyncing = false
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
