import Foundation
import MankiAnkiRust

/// Thread-safe owner of an Anki `rslib` backend handle.
///
/// The bridge deliberately transports only protobuf bytes. Higher-level
/// collection, scheduler, and sync features must use rslib's generated
/// service contracts rather than recreating them in Swift.
final class AnkiRSLibBackend {
    private let handle: Int64
    private let lock = NSLock()

    init() throws {
        var rawHandle: Int64 = 0
        let status = manki_anki_open_backend(nil, 0, &rawHandle)
        guard status == 0, rawHandle != 0 else {
            throw AnkiRSLibError.initializationFailed(status)
        }
        handle = rawHandle
    }

    deinit {
        manki_anki_close_backend(handle)
    }

    static func fetchDecks(username: String, password: String) throws -> [Deck] {
        let collection = try collectionPath()
        var output: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        let status = collection.withCString { collection in
            "https://sync.ankiweb.net".withCString { endpoint in
                username.withCString { username in
                    password.withCString { password in
                        manki_anki_fetch_decks(collection, endpoint, username, password, &output, &outputLength)
                    }
                }
            }
        }
        defer { if let output { manki_anki_free_response(output, outputLength) } }
        let data = output.map { Data(bytes: $0, count: outputLength) } ?? Data()
        guard status == 0 else {
            throw AnkiRSLibError.syncFailed(String(data: data, encoding: .utf8) ?? "AnkiWeb sync failed.")
        }
        return try JSONDecoder().decode([Deck].self, from: data)
    }

    static func nextCard(in deck: Deck) throws -> ReviewCard? {
        let collection = try collectionPath()
        let data = try reviewCall { output, outputLength in
            collection.withCString { manki_anki_get_next_card($0, deck.id, output, outputLength) }
        }
        return try JSONDecoder().decode(ReviewCard?.self, from: data)
    }

    static func answer(_ card: ReviewCard, in deck: Deck, rating: CardRating, millisecondsTaken: UInt32) throws {
        let collection = try collectionPath()
        _ = try reviewCall { output, outputLength in
            collection.withCString { manki_anki_answer_card($0, deck.id, card.id, rating.rawValue, millisecondsTaken, output, outputLength) }
        }
    }

    private static func collectionPath() throws -> String {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "Manki/collection.anki2").path
    }

    private static func reviewCall(_ call: (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, UnsafeMutablePointer<Int>) -> Int32) throws -> Data {
        var output: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        let status = call(&output, &outputLength)
        defer { if let output { manki_anki_free_response(output, outputLength) } }
        let data = output.map { Data(bytes: $0, count: outputLength) } ?? Data()
        guard status == 0 else {
            throw AnkiRSLibError.reviewFailed(String(data: data, encoding: .utf8) ?? "Anki could not update this card.")
        }
        return data
    }

    /// Dispatches one serialized request to Anki's backend.
    func run(service: UInt32, method: UInt32, request: Data = Data()) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        var responsePointer: UnsafeMutablePointer<UInt8>?
        var responseLength = 0
        let status = request.withUnsafeBytes { bytes in
            manki_anki_run_method(
                handle,
                service,
                method,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                bytes.count,
                &responsePointer,
                &responseLength
            )
        }
        defer {
            if let responsePointer {
                manki_anki_free_response(responsePointer, responseLength)
            }
        }

        let response = responsePointer.map { Data(bytes: $0, count: responseLength) } ?? Data()
        switch status {
        case 0:
            return response
        case 1:
            throw AnkiRSLibError.backend(response)
        default:
            throw AnkiRSLibError.bridgeFailed(status)
        }
    }
}

enum AnkiRSLibError: LocalizedError {
    case initializationFailed(Int32)
    case bridgeFailed(Int32)
    case backend(Data)
    case syncFailed(String)
    case reviewFailed(String)

    var errorDescription: String? {
        switch self {
        case let .initializationFailed(status):
            return "Could not initialize Anki rslib (status \(status))."
        case let .bridgeFailed(status):
            return "Anki rslib bridge failed (status \(status))."
        case .backend:
            return "Anki rslib rejected the request. Decode the returned BackendError protobuf for details."
        case let .syncFailed(message):
            return message
        case let .reviewFailed(message):
            return message
        }
    }
}
