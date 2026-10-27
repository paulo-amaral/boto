import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class EmailCardTests: XCTestCase {
    private var container: ModelContainer?

    private func makeList() throws -> BoardList {
        let container = try ModelContainer(
            for: Schema(KanbanSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let list = BoardList(name: "To do", index: 0)
        container.mainContext.insert(list)
        return list
    }

    private let email = ParsedEmail(
        subject: "Kickoff agenda",
        from: "Ana <ana@example.com>",
        date: ISO8601DateFormatter().date(from: "2026-10-26T10:30:00Z"),
        messageID: "m1@example.com",
        snippet: "Please review the agenda."
    )

    func testCardFromEmailGetsTitleDescriptionAndFromEmailReference() throws {
        let card = try makeList().addCard(fromEmail: email)
        XCTAssertEqual(card.title, "Kickoff agenda")
        XCTAssertTrue(card.details.hasPrefix("From: Ana <ana@example.com>\nDate: "))
        XCTAssertTrue(card.details.hasSuffix("\n\nPlease review the agenda."))
        let reference = try XCTUnwrap(card.references.first)
        XCTAssertEqual(reference.kind, .email)
        XCTAssertEqual(reference.remoteTitle, "Kickoff agenda")
        XCTAssertEqual(reference.remoteState, "Ana <ana@example.com>")
        XCTAssertEqual(reference.displayPath, "message://%3Cm1%40example.com%3E")
        XCTAssertEqual(reference.resolvedURL(projectRoot: nil)?.absoluteString, "message://%3Cm1%40example.com%3E")
    }

    func testAttachingTheSameMessageTwiceKeepsOneReference() throws {
        let card = try makeList().addCard(title: "A")
        XCTAssertTrue(card.attach(email))
        XCTAssertFalse(card.attach(email))
        XCTAssertEqual(card.references.count, 1)
    }

    func testMessageWithoutAnIdStillMakesACardButNoReference() throws {
        var noId = email
        noId.messageID = nil
        let card = try makeList().addCard(fromEmail: noId)
        XCTAssertEqual(card.title, "Kickoff agenda")
        XCTAssertTrue(card.references.isEmpty)
        XCTAssertFalse(card.attach(noId))
    }

    func testLinkOnlyDropKeepsDescriptionEmpty() throws {
        let linkOnly = ParsedEmail(subject: "Subject from Mail", messageID: "x@y")
        let card = try makeList().addCard(fromEmail: linkOnly)
        XCTAssertEqual(card.details, "")
        XCTAssertEqual(card.references.count, 1)
    }

    func testEnrichFillsSenderAndAnEmptyDescriptionOnly() throws {
        let card = try makeList().addCard(fromEmail: ParsedEmail(subject: "Kickoff agenda", messageID: "m1@example.com"))
        XCTAssertEqual(card.details, "")
        XCTAssertNil(card.references.first?.remoteState)

        card.enrich(with: email, fillDescription: true)
        XCTAssertEqual(card.references.first?.remoteState, "Ana <ana@example.com>")
        XCTAssertTrue(card.details.hasPrefix("From: Ana"))

        card.details = "my own notes"
        card.enrich(with: email, fillDescription: true)
        XCTAssertEqual(card.details, "my own notes", "the user's text is never overwritten")
    }

    func testEnrichOnAnExistingCardLeavesTheDescriptionAlone() throws {
        let card = try makeList().addCard(title: "Existing")
        card.attach(ParsedEmail(subject: "Kickoff agenda", messageID: "m1@example.com"))
        card.enrich(with: email, fillDescription: false)
        XCTAssertEqual(card.details, "")
        XCTAssertEqual(card.references.first?.remoteState, "Ana <ana@example.com>")
        XCTAssertEqual(card.title, "Existing")
    }

    func testEnrichIgnoresMessagesNotOnTheCard() throws {
        let card = try makeList().addCard(fromEmail: ParsedEmail(subject: "Other", messageID: "other@x"))
        card.enrich(with: email, fillDescription: true)
        XCTAssertEqual(card.details, "")
        XCTAssertNil(card.references.first?.remoteState)
    }

    func testPlaceholderTitleIsReplacedWhenTheRealSubjectArrives() throws {
        let card = try makeList().addCard(fromEmail: ParsedEmail(subject: "(no subject)", messageID: "m1@example.com"))
        card.enrich(with: email, fillDescription: true)
        XCTAssertEqual(card.title, "Kickoff agenda")
    }

    func testEmailReferencesCountAsRemote() {
        XCTAssertTrue(ReferenceKind.email.isRemote)
        XCTAssertFalse(ReferenceKind.email.isGitHub)
        XCTAssertFalse(ReferenceKind.file.isRemote)
    }
}
