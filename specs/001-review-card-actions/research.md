# Research: Review Card Actions Protobuf Requests and Generic Runner Mappings

## Pinned Anki `rslib` Revision
- Commit: `e64c6b1aee3e8d668fb8bbe084beada8e070d985`

## Service & Method Mappings

### CardsService (Service 10)
- `GetCard` (Method 0)
  - Request: `anki.cards.CardId` (`cid: int64`)
  - Response: `anki.cards.Card` (`id: int64`, `note_id: int64`, `deck_id: int64`, ...)

### NotetypesService (Service 12)
- `GetNotetype` (Method 6)
  - Request: `anki.notetypes.NotetypeId` (`ntid: int64`)
  - Response: `anki.notetypes.Notetype` (`id: int64`, `name: string`, `fields: repeated Field`)
    - `Field`: `ord: uint32` (wrapped), `name: string`

### NotesService (Service 42)
- `AddNote` (Method 1)
  - Request: `anki.notes.AddNoteRequest` (`note: Note`, `deck_id: int64`)
  - Response: `anki.notes.AddNoteResponse` (`changes: OpChangesWithCount`, `note_id: int64`)
- `DefaultsForAdding` (Method 3)
  - Request: `anki.notes.DefaultsForAddingRequest` (`home_deck_of_current_review_card: int64`)
  - Response: `anki.notes.DeckAndNotetype` (`deck_id: int64`, `notetype_id: int64`)
- `UpdateNotes` (Method 5)
  - Request: `anki.notes.UpdateNotesRequest` (`notes: repeated Note`, `skip_undo_entry: bool`)
  - Response: `anki.collection.OpChanges`
- `GetNote` (Method 6)
  - Request: `anki.notes.NoteId` (`nid: int64`)
  - Response: `anki.notes.Note` (`id: int64`, `guid: string`, `notetype_id: int64`, `mtime_secs: uint32`, `usn: int32`, `tags: repeated string`, `fields: repeated string`)

## Field Mapping Logic
- When creating or editing notes, field names in `Notetype.fields` are matched (e.g. "Front", "Back") rather than relying on fixed array indexes.
- In Edit mode:
  - Fetches `Card` by card ID -> obtains `note_id`.
  - Fetches `Note` by `note_id` -> obtains existing fields, tags, guid, notetype_id, usn, mtime_secs.
  - Fetches `Notetype` by `notetype_id` -> maps field positions by field name.
  - Updates only the fields corresponding to "Front" and "Back". All other fields, tags, and note identity are preserved intact.
