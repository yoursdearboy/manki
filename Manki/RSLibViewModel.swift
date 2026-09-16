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
    @Published private(set) var syncErrorMessage: String?
    @Published private(set) var lastSynced: Date?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var reviewCard: ReviewCard?
    @Published private(set) var isReviewLoading = false

    private let credentials = KeychainCredentials()
    private let loadCachedDecks: () throws -> [Deck]
    private let fetchDecks: (String, String) throws -> [Deck]
    private var hasRestoredSession = false

    init(
        decks: [Deck] = [],
        isAuthenticated: Bool = false,
        loadCachedDecks: @escaping () throws -> [Deck] = AnkiRSLibBackend.loadCachedDecks,
        fetchDecks: @escaping (String, String) throws -> [Deck] = AnkiRSLibBackend.fetchDecks
    ) {
        self.decks = decks
        self.isAuthenticated = isAuthenticated
        self.loadCachedDecks = loadCachedDecks
        self.fetchDecks = fetchDecks
    }

    var canSignIn: Bool { !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty }
    var lastSyncedText: String { lastSynced.map { "Synced \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Pull to refresh your collection" }

    func restoreSession() async {
        guard !hasRestoredSession else { return }
        hasRestoredSession = true
        guard let saved = credentials.read() else { return }
        username = saved.username
        password = saved.password
        isAuthenticated = true
        await loadCache()
        await sync()
    }

    /// Called for foreground transitions after initial session restoration.
    func syncWhenActive() async {
        guard hasRestoredSession, isAuthenticated else { return }
        await sync()
    }

    func signIn() async {
        guard canSignIn else { return }
        isAuthenticated = true
        await sync(saveCredentialsOnSuccess: true)
        if syncErrorMessage != nil { isAuthenticated = false }
    }

    func sync() async { await sync(saveCredentialsOnSuccess: false) }

    func logout() {
        credentials.delete()
        username = ""
        password = ""
        decks = []
        errorMessage = nil
        syncErrorMessage = nil
        lastSynced = nil
        isAuthenticated = false
        reviewCard = nil
    }

    func loadNextCard(in deck: Deck) async {
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

    private func loadCache() async {
        do {
            let cached = try await Task.detached(priority: .userInitiated) { [loadCachedDecks] in
                try loadCachedDecks()
            }.value
            decks = sorted(cached)
        } catch {
            // A cache read failure should be retryable in the same way as a
            // network failure, while leaving any already displayed data alone.
            syncErrorMessage = error.localizedDescription
        }
    }

    private func sync(saveCredentialsOnSuccess: Bool) async {
        guard !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        syncErrorMessage = nil
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password
        do {
            let fetched = try await Task.detached(priority: .userInitiated) { [fetchDecks] in
                try fetchDecks(username, password)
            }.value
            decks = sorted(fetched)
            lastSynced = .now
            if saveCredentialsOnSuccess { try credentials.save(username: username, password: password) }
        } catch {
            syncErrorMessage = error.localizedDescription
        }
        isSyncing = false
    }

    private func sorted(_ decks: [Deck]) -> [Deck] {
        decks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
