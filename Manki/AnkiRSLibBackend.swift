import Foundation
import MankiAnkiRust

struct ProtoWriter {
    private(set) var data = Data()

    mutating func writeVarintField(fieldNumber: Int, value: UInt64) -> ProtoWriter {
        let key = UInt64((fieldNumber << 3) | 0)
        writeVarint(key)
        writeVarint(value)
        return self
    }

    mutating func writeStringField(fieldNumber: Int, value: String) -> ProtoWriter {
        let key = UInt64((fieldNumber << 3) | 2)
        let utf8 = Data(value.utf8)
        writeVarint(key)
        writeVarint(UInt64(utf8.count))
        data.append(utf8)
        return self
    }

    mutating func writeMessageField(fieldNumber: Int, messageData: Data) -> ProtoWriter {
        let key = UInt64((fieldNumber << 3) | 2)
        writeVarint(key)
        writeVarint(UInt64(messageData.count))
        data.append(messageData)
        return self
    }

    private mutating func writeVarint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        data.append(UInt8(v & 0x7F))
    }
}

struct ProtoReader {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func readInt64Field(fieldNumber: Int) -> Int64? {
        var offset = 0
        while offset < data.count {
            guard let (key, nextOffset) = readVarint(at: offset) else { break }
            offset = nextOffset
            let field = Int(key >> 3)
            let wireType = Int(key & 7)

            if field == fieldNumber, wireType == 0 {
                if let (val, _) = readVarint(at: offset) {
                    return Int64(bitPattern: val)
                }
            }
            guard let skipped = skipField(wireType: wireType, at: offset) else { break }
            offset = skipped
        }
        return nil
    }

    func readRepeatedStringField(fieldNumber: Int) -> [String] {
        var results: [String] = []
        var offset = 0
        while offset < data.count {
            guard let (key, nextOffset) = readVarint(at: offset) else { break }
            offset = nextOffset
            let field = Int(key >> 3)
            let wireType = Int(key & 7)

            if field == fieldNumber, wireType == 2 {
                if let (len, lengthOffset) = readVarint(at: offset) {
                    let start = lengthOffset
                    let end = start + Int(len)
                    if end <= data.count, let str = String(data: data.subdata(in: start..<end), encoding: .utf8) {
                        results.append(str)
                    }
                }
            }
            guard let skipped = skipField(wireType: wireType, at: offset) else { break }
            offset = skipped
        }
        return results
    }

    struct RawNote {
        var id: Int64 = 0
        var guid: String?
        var notetypeID: Int64 = 0
        var mtimeSecs: UInt32?
        var usn: Int32?
        var tags: [String] = []
        var fields: [String] = []
    }

    static func parseRawNote(data: Data) -> RawNote {
        var note = RawNote()
        var offset = 0
        while offset < data.count {
            guard let (key, nextOffset) = readVarint(data: data, at: offset) else { break }
            offset = nextOffset
            let field = Int(key >> 3)
            let wireType = Int(key & 7)

            switch (field, wireType) {
            case (1, 0):
                if let (val, _) = readVarint(data: data, at: offset) { note.id = Int64(bitPattern: val) }
            case (2, 2):
                if let (str, _) = readString(data: data, at: offset) { note.guid = str }
            case (3, 0):
                if let (val, _) = readVarint(data: data, at: offset) { note.notetypeID = Int64(bitPattern: val) }
            case (4, 0):
                if let (val, _) = readVarint(data: data, at: offset) { note.mtimeSecs = UInt32(val) }
            case (5, 0):
                if let (val, _) = readVarint(data: data, at: offset) { note.usn = Int32(bitPattern: UInt32(val & 0xFFFFFFFF)) }
            case (6, 2):
                if let (str, _) = readString(data: data, at: offset) { note.tags.append(str) }
            case (7, 2):
                if let (str, _) = readString(data: data, at: offset) { note.fields.append(str) }
            default:
                break
            }
            guard let skipped = skipField(data: data, wireType: wireType, at: offset) else { break }
            offset = skipped
        }
        return note
    }

    static func parseNotetypeFields(data: Data) -> [BackendNotetypeField] {
        var fields: [BackendNotetypeField] = []
        var offset = 0
        while offset < data.count {
            guard let (key, nextOffset) = readVarint(data: data, at: offset) else { break }
            offset = nextOffset
            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 7)

            if fieldNumber == 8, wireType == 2 { // Notetype.fields
                if let (len, msgOffset) = readVarint(data: data, at: offset) {
                    let fieldMsgEnd = msgOffset + Int(len)
                    if fieldMsgEnd <= data.count {
                        let fieldData = data.subdata(in: msgOffset..<fieldMsgEnd)
                        if let parsedField = parseSingleNotetypeField(data: fieldData) {
                            fields.append(parsedField)
                        }
                    }
                }
            }
            guard let skipped = skipField(data: data, wireType: wireType, at: offset) else { break }
            offset = skipped
        }
        return fields
    }

    private static func parseSingleNotetypeField(data: Data) -> BackendNotetypeField? {
        var ord: UInt32 = 0
        var name = ""
        var offset = 0
        while offset < data.count {
            guard let (key, nextOffset) = readVarint(data: data, at: offset) else { break }
            offset = nextOffset
            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 7)

            if fieldNumber == 1 { // ord (generic.UInt32 message or varint)
                if wireType == 0 {
                    if let (val, _) = readVarint(data: data, at: offset) { ord = UInt32(val) }
                } else if wireType == 2 {
                    if let (len, msgOffset) = readVarint(data: data, at: offset) {
                        let end = msgOffset + Int(len)
                        if end <= data.count {
                            let innerData = data.subdata(in: msgOffset..<end)
                            if let (val, _) = readVarint(data: innerData, at: 0) { ord = UInt32(val) }
                        }
                    }
                }
            } else if fieldNumber == 2, wireType == 2 { // name
                if let (str, _) = readString(data: data, at: offset) { name = str }
            }
            guard let skipped = skipField(data: data, wireType: wireType, at: offset) else { break }
            offset = skipped
        }
        return BackendNotetypeField(ord: ord, name: name)
    }

    private func readVarint(at startOffset: Int) -> (UInt64, Int)? {
        ProtoReader.readVarint(data: data, at: startOffset)
    }

    private static func readVarint(data: Data, at startOffset: Int) -> (UInt64, Int)? {
        var offset = startOffset
        var result: UInt64 = 0
        var shift = 0
        while offset < data.count {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return (result, offset)
            }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    private static func readString(data: Data, at startOffset: Int) -> (String, Int)? {
        guard let (len, offset) = readVarint(data: data, at: startOffset) else { return nil }
        let end = offset + Int(len)
        guard end <= data.count, let str = String(data: data.subdata(in: offset..<end), encoding: .utf8) else { return nil }
        return (str, end)
    }

    private func skipField(wireType: Int, at startOffset: Int) -> Int? {
        ProtoReader.skipField(data: data, wireType: wireType, at: startOffset)
    }

    private static func skipField(data: Data, wireType: Int, at startOffset: Int) -> Int? {
        switch wireType {
        case 0:
            return readVarint(data: data, at: startOffset)?.1
        case 1:
            let next = startOffset + 8
            return next <= data.count ? next : nil
        case 2:
            guard let (len, offset) = readVarint(data: data, at: startOffset) else { return nil }
            let next = offset + Int(len)
            return next <= data.count ? next : nil
        case 5:
            let next = startOffset + 4
            return next <= data.count ? next : nil
        default:
            return nil
        }
    }
}

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
        try fetchDecksImpl(username: username, password: password, fullSyncDirection: nil)
    }

    static func fetchDecks(username: String, password: String, fullSyncDirection: FullSyncDirection) throws -> [Deck] {
        try fetchDecksImpl(username: username, password: password, fullSyncDirection: fullSyncDirection)
    }

    private static func fetchDecksImpl(
        username: String,
        password: String,
        fullSyncDirection: FullSyncDirection?
    ) throws -> [Deck] {
        let collection = try collectionPath()
        var output: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        let status = collection.withCString { collection in
            "https://sync.ankiweb.net".withCString { endpoint in
                username.withCString { username in
                    password.withCString { password in
                        if let fullSyncDirection {
                            manki_anki_fetch_decks_full_sync(
                                collection,
                                endpoint,
                                username,
                                password,
                                fullSyncDirection == .upload,
                                &output,
                                &outputLength
                            )
                        } else {
                            manki_anki_fetch_decks(collection, endpoint, username, password, &output, &outputLength)
                        }
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

    static func loadCachedDecks() throws -> [Deck] {
        let collection = try collectionPath()
        var output: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        let status = collection.withCString {
            manki_anki_load_decks($0, &output, &outputLength)
        }
        defer { if let output { manki_anki_free_response(output, outputLength) } }
        let data = output.map { Data(bytes: $0, count: outputLength) } ?? Data()
        guard status == 0 else {
            throw AnkiRSLibError.collectionFailed(String(data: data, encoding: .utf8) ?? "Anki could not load scheduler counts.")
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

    static func reviewQueue(in deck: Deck) throws -> [ReviewCard] {
        let collection = try collectionPath()
        let data = try reviewCall { output, outputLength in
            collection.withCString { manki_anki_get_review_queue($0, deck.id, output, outputLength) }
        }
        return try JSONDecoder().decode([ReviewCard].self, from: data)
    }

    static func answer(_ card: ReviewCard, in deck: Deck, rating: CardRating, millisecondsTaken: UInt32) throws {
        let collection = try collectionPath()
        _ = try reviewCall { output, outputLength in
            collection.withCString { manki_anki_answer_card($0, deck.id, card.id, rating.rawValue, millisecondsTaken, output, outputLength) }
        }
    }

    static func setFlag(on card: ReviewCard, to flag: CardFlag) throws {
        let collection = try collectionPath()
        _ = try reviewCall { output, outputLength in
            collection.withCString { manki_anki_set_card_flag($0, card.id, flag.rawValue, output, outputLength) }
        }
    }

    static func addNote(deckID: Int64, front: String, back: String) throws {
        let backend = try AnkiRSLibBackend()
        let defaultsRequest = ProtoWriter()
            .writeVarintField(fieldNumber: 1, value: UInt64(bitPattern: deckID))
            .data
        let defaultsData = try backend.run(service: 42, method: 3, request: defaultsRequest)
        let defaults = ProtoReader(data: defaultsData)
        let notetypeID = defaults.readInt64Field(fieldNumber: 2) ?? 1

        let notetypeReq = ProtoWriter().writeVarintField(fieldNumber: 1, value: UInt64(bitPattern: notetypeID)).data
        let notetypeData = try backend.run(service: 12, method: 6, request: notetypeReq)
        let notetypeFields = ProtoReader.parseNotetypeFields(data: notetypeData)

        let fieldValues = NoteActionMapper.buildNewFields(notetypeFields: notetypeFields, values: ["Front": front, "Back": back])

        var noteWriter = ProtoWriter()
        noteWriter.writeVarintField(fieldNumber: 3, value: UInt64(bitPattern: notetypeID))
        for field in fieldValues {
            noteWriter.writeStringField(fieldNumber: 7, value: field)
        }

        var addNoteReqWriter = ProtoWriter()
        addNoteReqWriter.writeMessageField(fieldNumber: 1, messageData: noteWriter.data)
        addNoteReqWriter.writeVarintField(fieldNumber: 2, value: UInt64(bitPattern: deckID))

        _ = try backend.run(service: 42, method: 1, request: addNoteReqWriter.data)
    }

    static func fetchNoteFields(cardID: Int64) throws -> (front: String, back: String) {
        let backend = try AnkiRSLibBackend()
        let cardReq = ProtoWriter().writeVarintField(fieldNumber: 1, value: UInt64(bitPattern: cardID)).data
        let cardData = try backend.run(service: 10, method: 0, request: cardReq)
        let cardReader = ProtoReader(data: cardData)
        guard let noteID = cardReader.readInt64Field(fieldNumber: 2) else {
            throw AnkiRSLibError.reviewFailed("Card not found")
        }

        let noteReq = ProtoWriter().writeVarintField(fieldNumber: 1, value: UInt64(bitPattern: noteID)).data
        let noteData = try backend.run(service: 42, method: 6, request: noteReq)
        let rawNote = ProtoReader.parseRawNote(data: noteData)

        let notetypeReq = ProtoWriter().writeVarintField(fieldNumber: 1, value: UInt64(bitPattern: rawNote.notetypeID)).data
        let notetypeData = try backend.run(service: 12, method: 6, request: notetypeReq)
        let notetypeFields = ProtoReader.parseNotetypeFields(data: notetypeData)

        var front = ""
        var back = ""
        for (idx, fieldValue) in rawNote.fields.enumerated() {
            if let ntField = notetypeFields.first(where: { Int($0.ord) == idx }) {
                if ntField.name.lowercased() == "front" { front = fieldValue }
                if ntField.name.lowercased() == "back" { back = fieldValue }
            }
        }
        return (front, back)
    }

    static func updateNote(cardID: Int64, front: String, back: String) throws {
        let backend = try AnkiRSLibBackend()
        let cardReq = ProtoWriter().writeVarintField(fieldNumber: 1, value: UInt64(bitPattern: cardID)).data
        let cardData = try backend.run(service: 10, method: 0, request: cardReq)
        let cardReader = ProtoReader(data: cardData)
        guard let noteID = cardReader.readInt64Field(fieldNumber: 2) else {
            throw AnkiRSLibError.reviewFailed("Card not found")
        }

        let noteReq = ProtoWriter().writeVarintField(fieldNumber: 1, value: UInt64(bitPattern: noteID)).data
        let noteData = try backend.run(service: 42, method: 6, request: noteReq)
        let rawNote = ProtoReader.parseRawNote(data: noteData)

        let notetypeReq = ProtoWriter().writeVarintField(fieldNumber: 1, value: UInt64(bitPattern: rawNote.notetypeID)).data
        let notetypeData = try backend.run(service: 12, method: 6, request: notetypeReq)
        let notetypeFields = ProtoReader.parseNotetypeFields(data: notetypeData)

        let updatedFields = NoteActionMapper.updateFields(
            existingFields: rawNote.fields,
            notetypeFields: notetypeFields,
            updates: ["Front": front, "Back": back]
        )

        var noteWriter = ProtoWriter()
        noteWriter.writeVarintField(fieldNumber: 1, value: UInt64(bitPattern: rawNote.id))
        if let guid = rawNote.guid { noteWriter.writeStringField(fieldNumber: 2, value: guid) }
        noteWriter.writeVarintField(fieldNumber: 3, value: UInt64(bitPattern: rawNote.notetypeID))
        if let mtime = rawNote.mtimeSecs { noteWriter.writeVarintField(fieldNumber: 4, value: UInt64(mtime)) }
        if let usn = rawNote.usn { noteWriter.writeVarintField(fieldNumber: 5, value: UInt64(bitPattern: Int64(usn))) }
        for tag in rawNote.tags { noteWriter.writeStringField(fieldNumber: 6, value: tag) }
        for f in updatedFields { noteWriter.writeStringField(fieldNumber: 7, value: f) }

        var updateReqWriter = ProtoWriter()
        updateReqWriter.writeMessageField(fieldNumber: 1, messageData: noteWriter.data)

        _ = try backend.run(service: 42, method: 5, request: updateReqWriter.data)
    }

    static func mediaURL(for filename: String) -> URL? {
        guard !filename.isEmpty,
              filename == URL(fileURLWithPath: filename).lastPathComponent,
              let collection = try? collectionPath() else { return nil }
        let collectionURL = URL(fileURLWithPath: collection)
        return collectionURL
            .deletingLastPathComponent()
            .appending(path: "\(collectionURL.deletingPathExtension().lastPathComponent).media")
            .appending(path: filename)
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

enum FullSyncDirection: Equatable {
    case upload
    case download
}

enum AnkiRSLibError: LocalizedError {
    case initializationFailed(Int32)
    case bridgeFailed(Int32)
    case backend(Data)
    case syncFailed(String)
    case reviewFailed(String)
    case collectionFailed(String)

    var requiresFullSyncChoice: Bool {
        guard case let .syncFailed(message) = self else { return false }
        return message.contains("requires a full-sync direction choice")
    }

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
        case let .collectionFailed(message):
            return message
        }
    }
}
