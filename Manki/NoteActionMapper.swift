import Foundation

struct BackendCard: Equatable {
    let id: Int64
    let noteID: Int64
    let deckID: Int64
}

struct BackendNote: Equatable {
    let id: Int64
    let guid: String
    let notetypeID: Int64
    let mtimeSecs: UInt32
    let usn: Int32
    let tags: [String]
    let fields: [String]
}

struct BackendNotetypeField: Equatable {
    let ord: UInt32
    let name: String
}

struct BackendNotetype: Equatable {
    let id: Int64
    let name: String
    let fields: [BackendNotetypeField]
}

enum NoteActionMapper {
    /// Maps field names (e.g., "Front", "Back") to field indices in `Notetype.fields`.
    /// Returns a new array of field strings updating target fields while preserving untouched fields.
    static func updateFields(
        existingFields: [String],
        notetypeFields: [BackendNotetypeField],
        updates: [String: String]
    ) -> [String] {
        var result = existingFields
        while result.count < notetypeFields.count {
            result.append("")
        }

        for (fieldName, newValue) in updates {
            if let field = notetypeFields.first(where: { $0.name.lowercased() == fieldName.lowercased() }) {
                let idx = Int(field.ord)
                if idx < result.count {
                    result[idx] = newValue
                }
            }
        }
        return result
    }

    /// Generates field array for a new note matching notetype field order.
    static func buildNewFields(
        notetypeFields: [BackendNotetypeField],
        values: [String: String]
    ) -> [String] {
        var fields = Array(repeating: "", count: notetypeFields.count)
        for (fieldName, value) in values {
            if let field = notetypeFields.first(where: { $0.name.lowercased() == fieldName.lowercased() }) {
                let idx = Int(field.ord)
                if idx < fields.count {
                    fields[idx] = value
                }
            }
        }
        return fields
    }
}
