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

    var canSignIn: Bool { !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty }
    var lastSyncedText: String { lastSynced.map { "Synced \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Pull to refresh your collection" }

    func restoreSession() async {
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

    private func sync(saveCredentialsOnSuccess: Bool) async {
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
