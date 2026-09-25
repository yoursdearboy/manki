import Foundation
import XCTest
@testable import Manki

final class NoteActionMapperTests: XCTestCase {
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
}
