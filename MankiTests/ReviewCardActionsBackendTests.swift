import Foundation
import XCTest
@testable import Manki

final class ReviewCardActionsBackendTests: XCTestCase {
    func testBuildNewFieldsByFieldName() {
        let notetypeFields = [
            BackendNotetypeField(ord: 0, name: "Front"),
            BackendNotetypeField(ord: 1, name: "Back"),
            BackendNotetypeField(ord: 2, name: "Extra")
        ]
        let values = ["Front": "Hola", "Back": "Hello"]
        let fields = NoteActionMapper.buildNewFields(notetypeFields: notetypeFields, values: values)

        XCTAssertEqual(fields, ["Hola", "Hello", ""])
    }

    func testUpdateFieldsPreservesUntouchedFields() {
        let notetypeFields = [
            BackendNotetypeField(ord: 0, name: "Front"),
            BackendNotetypeField(ord: 1, name: "Back"),
            BackendNotetypeField(ord: 2, name: "Notes/Media")
        ]
        let existingFields = ["Old Front", "Old Back", "<img src=\"audio.mp3\">"]
        let updates = ["Front": "New Front"]

        let updated = NoteActionMapper.updateFields(
            existingFields: existingFields,
            notetypeFields: notetypeFields,
            updates: updates
        )

        XCTAssertEqual(updated, ["New Front", "Old Back", "<img src=\"audio.mp3\">"])
    }

    func testUpdateFieldsCaseInsensitiveMatch() {
        let notetypeFields = [
            BackendNotetypeField(ord: 0, name: "front"),
            BackendNotetypeField(ord: 1, name: "back")
        ]
        let existingFields = ["Q", "A"]
        let updates = ["Front": "Updated Q", "BACK": "Updated A"]

        let updated = NoteActionMapper.updateFields(
            existingFields: existingFields,
            notetypeFields: notetypeFields,
            updates: updates
        )

        XCTAssertEqual(updated, ["Updated Q", "Updated A"])
    }

    func testProtoWriterAndReaderRoundtrip() {
        var writer = ProtoWriter()
        writer.writeVarintField(fieldNumber: 1, value: 12345)
        writer.writeStringField(fieldNumber: 2, value: "test-guid")
        writer.writeStringField(fieldNumber: 6, value: "tag1")
        writer.writeStringField(fieldNumber: 6, value: "tag2")

        let reader = ProtoReader(data: writer.data)
        XCTAssertEqual(reader.readInt64Field(fieldNumber: 1), 12345)
        XCTAssertEqual(reader.readRepeatedStringField(fieldNumber: 6), ["tag1", "tag2"])

        let rawNote = ProtoReader.parseRawNote(data: writer.data)
        XCTAssertEqual(rawNote.id, 12345)
        XCTAssertEqual(rawNote.guid, "test-guid")
        XCTAssertEqual(rawNote.tags, ["tag1", "tag2"])
    }
}
