import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class NoteTests: XCTestCase {
    private var container: ModelContainer?

    private func makeProject() throws -> Project {
        let container = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        let project = Project(name: "Client")
        container.mainContext.insert(project)
        return project
    }

    func testEveryNoteColourReadsWithDarkText() throws {
        let dark = try XCTUnwrap(ColorContrast.luminance(ofHex: "#161616"))
        for colour in NoteColors.all {
            let light = try XCTUnwrap(ColorContrast.luminance(ofHex: colour.hex), colour.name)
            XCTAssertGreaterThanOrEqual((light + 0.05) / (dark + 0.05), 4.5, colour.name)
        }
        XCTAssertEqual(Set(NoteColors.all.map(\.hex)).count, NoteColors.all.count)
    }

    func testNewNotesTakeTurnsWithTheColours() throws {
        let project = try makeProject()
        let first = project.addNote()
        let second = project.addNote()
        XCTAssertNotEqual(first.colorHex, second.colorHex)
        XCTAssertEqual(first.colorHex, NoteColors.all[0].hex)
        for _ in 0..<NoteColors.all.count { project.addNote() }
        XCTAssertEqual(project.notes.count, NoteColors.all.count + 2)
    }

    func testLiveNotesAreNewestFirstAndSkipDeletedOnes() throws {
        let project = try makeProject()
        let old = project.addNote(text: "old"); old.createdAt = Date().addingTimeInterval(-100)
        let new = project.addNote(text: "new")
        let gone = project.addNote(text: "gone"); gone.deletedAt = Date()
        XCTAssertEqual(project.liveNotes.map(\.text), ["new", "old"])
        XCTAssertTrue(project.notes.contains { $0 === gone }, "soft delete keeps the row")
        _ = new
    }

    func testTitleIsTheFirstNonEmptyLine() {
        XCTAssertEqual(Note(text: "Call the client\nabout the scope").title, "Call the client")
        XCTAssertEqual(Note(text: "\n  Second line first \nmore").title, "Second line first")
        XCTAssertEqual(Note(text: "").title, "")
    }

    func testANoteComesBackOnlyIntoAProjectThatStillExists() throws {
        let project = try makeProject()
        let note = project.addNote(text: "x")
        XCTAssertFalse(note.canRestore, "not deleted")
        note.deletedAt = Date()
        XCTAssertTrue(note.canRestore)
        project.deletedAt = Date()
        XCTAssertFalse(note.canRestore)
    }

    func testNotesSurviveASaveAndAReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("boto-notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Boto.store")
        do {
            let container = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(url: url))
            let project = Project(name: "Client")
            container.mainContext.insert(project)
            project.addNote(text: "Remember the invoice").colorHex = "#bfdbfe"
            try container.mainContext.save()
        }
        let reopened = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(url: url))
        let project = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(project.liveNotes.map(\.text), ["Remember the invoice"])
        XCTAssertEqual(project.liveNotes.first?.colorHex, "#bfdbfe")
    }

    func testDuplicatingCopiesNotesUnlessOnlyTheStructureIsWanted() throws {
        let project = try makeProject()
        let context = try XCTUnwrap(container).mainContext
        project.addNote(text: "first").colorHex = "#fbcfe8"
        project.addNote(text: "second")
        project.addNote(text: "deleted").deletedAt = Date()

        let full = project.duplicate(named: "Full", in: context)
        XCTAssertEqual(Set(full.liveNotes.map(\.text)), ["first", "second"], "deleted notes stay behind")
        XCTAssertEqual(full.liveNotes.first { $0.text == "first" }?.colorHex, "#fbcfe8")
        full.liveNotes.first?.text = "changed in the copy"
        XCTAssertEqual(Set(project.liveNotes.map(\.text)), ["first", "second"], "the copy is independent")

        let template = project.duplicate(named: "Template", withCards: false, in: context)
        XCTAssertTrue(template.liveNotes.isEmpty)
    }
}
