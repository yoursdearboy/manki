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
    private let badgeController: AppIconBadgeController

    init(badgeSetter: any AppIconBadgeSetting = UserNotificationBadgeSetter()) {
        badgeController = AppIconBadgeController(setter: badgeSetter)
    }

    var canSignIn: Bool { !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty }
    var lastSyncedText: String { lastSynced.map { "Synced \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Pull to refresh your collection" }

    func restoreSession() async {
        guard let saved = credentials.read() else {
            await updateBadge()
            return
        }
        username = saved.username
        password = saved.password
        isAuthenticated = true
        await sync()
        if errorMessage != nil {
            await refreshDueCounts()
        }
    }

    func signIn() async {
        guard canSignIn else { return }
        isAuthenticated = true
        await sync(saveCredentialsOnSuccess: true)
        if errorMessage != nil {
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
        lastSynced = nil
        isAuthenticated = false
        reviewCard = nil
        await updateBadge()
    }

    /// Refreshes scheduler counts from the existing collection without a
    /// network sync. This keeps time-sensitive counts current on foregrounding
    /// and after a review while leaving scheduling decisions to rslib.
    func refreshDueCounts() async {
        guard isAuthenticated else {
            await updateBadge()
            return
        }
        do {
            let fetched = try await Task.detached(priority: .utility) {
                try AnkiRSLibBackend.loadDecks()
            }.value
            apply(fetched)
            await updateBadge()
        } catch {
            errorMessage = error.localizedDescription
        }
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
            await refreshDueCounts()
            await loadNextCard(in: deck)
        } catch {
            errorMessage = error.localizedDescription
            isReviewLoading = false
        }
    }

    private func sync(saveCredentialsOnSuccess: Bool) async {
        isSyncing = true
        errorMessage = nil
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password
        do {
            let fetched = try await Task.detached(priority: .userInitiated) {
                try AnkiRSLibBackend.fetchDecks(username: username, password: password)
            }.value
            apply(fetched)
            lastSynced = .now
            if saveCredentialsOnSuccess { try credentials.save(username: username, password: password) }
            await updateBadge()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSyncing = false
    }

    private func apply(_ fetched: [Deck]) {
        decks = fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func updateBadge() async {
        await badgeController.update(decks: decks, isAuthenticated: isAuthenticated)
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
