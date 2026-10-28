import Foundation
import SwiftData

/// A sticky note on a project: free text on a coloured square, for annotations that are not tasks. Notes belong to the
/// project, not to a board, and deleting one only sets `deletedAt`, so it can come back from Recently deleted.
@Model
public final class Note {
    @Attribute(.unique) public var publicId: String
    public var text: String
    public var colorHex: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var project: Project?

    public init(text: String = "", colorHex: String = NoteColors.all[0].hex) {
        self.publicId = makePublicId()
        self.text = text
        self.colorHex = colorHex
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Back into a project that still exists; a note restored into a deleted project would never be seen.
    public var canRestore: Bool {
        guard deletedAt != nil, let project else { return false }
        return project.deletedAt == nil
    }

    /// The first line, for lists that have room for one.
    public var title: String {
        text.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }
}

/// Pastel colours that keep near-black text above 4.5:1 (a test checks it).
public enum NoteColors {
    public static let all: [(name: String, hex: String)] = [
        ("Yellow", "#fde68a"), ("Pink", "#fbcfe8"), ("Green", "#bbf7d0"),
        ("Blue", "#bfdbfe"), ("Orange", "#fed7aa"), ("Violet", "#ddd6fe"),
    ]
}

extension Project {
    /// Newest first, like a pile of notes with the latest on top.
    public var liveNotes: [Note] { notes.filter { $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt } }

    /// A blank note in the next colour of the palette, so a run of new notes does not come out all one colour.
    @discardableResult
    public func addNote(text: String = "") -> Note {
        let note = Note(text: text, colorHex: NoteColors.all[notes.count % NoteColors.all.count].hex)
        notes.append(note)
        return note
    }
}
