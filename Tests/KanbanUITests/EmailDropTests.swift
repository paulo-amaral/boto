import XCTest
@testable import KanbanCore
@testable import KanbanUI

/// Drives the drop logic with item providers shaped like real drags. The Mail shape comes from a real drag on macOS 27:
/// item 0 has the link, the subject and the subject again as plain text; item 1 is a file promise for the .eml. A real
/// drag cannot be scripted, so what the window hands to the handler still has to be confirmed by hand.
@MainActor
final class EmailDropTests: XCTestCase {
    private func provider(link: String? = nil, subject: String? = nil, text: String? = nil, eml: String? = nil,
                          emlType: String = "public.email-message", neverDeliverEML: Bool = false) -> NSItemProvider {
        let provider = NSItemProvider()
        if let link, let url = URL(string: link) { provider.registerObject(url as NSURL, visibility: .all) }
        if let subject {
            provider.registerDataRepresentation(forTypeIdentifier: "public.url-name", visibility: .all) { completion in
                completion(Data(subject.utf8), nil)
                return nil
            }
        }
        if let text { provider.registerObject(text as NSString, visibility: .all) }
        if eml != nil || neverDeliverEML {
            provider.registerFileRepresentation(forTypeIdentifier: emlType, fileOptions: [], visibility: .all) { completion in
                if neverDeliverEML { return nil }
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).eml")
                try? eml?.write(to: file, atomically: true, encoding: .utf8)
                completion(file, false, nil)
                return nil
            }
        }
        return provider
    }

    private let eml = """
    From: Ana Souza <ana@example.com>
    Subject: Kickoff agenda
    Message-ID: <m1@example.com>
    Date: Mon, 26 Oct 2026 10:30:00 +0000

    Please review the agenda.
    """

    /// What `BoardDrop.handle` did, for assertions.
    private final class Recorder {
        var moved: [String] = []
        var added: [[ParsedEmail]] = []
        var enriched: [[ParsedEmail]] = []
        var problems: [String?] = []
    }

    /// A private pasteboard in the shape of Mail's drag: item 0 carries the link and subject (the file promise is item 1
    /// and shows up only as a provider). Tests never read the system's real drag pasteboard.
    private func pasteboard(link: String? = nil, subject: String? = nil) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("boto-test-\(UUID().uuidString)"))
        board.clearContents()
        if let link {
            let item = NSPasteboardItem()
            item.setString(link, forType: .URL)
            if let subject { item.setString(subject, forType: NSPasteboard.PasteboardType("public.url-name")) }
            board.writeObjects([item])
        }
        return board
    }

    private func drop(_ providers: [NSItemProvider], recorder: Recorder, pasteboard: NSPasteboard? = nil) -> Bool {
        BoardDrop.handle(
            providers,
            pasteboard: pasteboard ?? self.pasteboard(),
            moveCard: { recorder.moved.append($0) },
            addEmails: { recorder.added.append($0) },
            enrich: { recorder.enriched.append($0) },
            problem: { recorder.problems.append($0) }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(30)) }
    }

    // MARK: Reading

    func testLinkAndSubjectMakeAnEmail() async {
        let emails = await EmailDrop.readLinks(from: [provider(link: "message:%3Cm1%40example.com%3E", subject: "Kickoff agenda")])
        XCTAssertEqual(emails, [ParsedEmail(subject: "Kickoff agenda", messageID: "m1@example.com")])
    }

    func testWebLinksAndMissingSubjects() async {
        let web = await EmailDrop.readLinks(from: [provider(link: "https://example.com/page")])
        XCTAssertTrue(web.isEmpty)
        let bare = await EmailDrop.readLinks(from: [provider(link: "message:%3Ca%40x%3E")])
        XCTAssertEqual(bare.first?.subject, "(no subject)")
    }

    func testTheEMLProvidesSenderDateAndText() async throws {
        for type in ["public.email-message", "com.apple.mail.email"] {
            let emails = await EmailDrop.readFiles(from: [provider(eml: eml, emlType: type)])
            let email = try XCTUnwrap(emails.first, type)
            XCTAssertEqual(email.from, "Ana Souza <ana@example.com>")
            XCTAssertEqual(email.snippet, "Please review the agenda.")
        }
    }

    func testEMLWithoutAMessageIDTakesItFromTheLinkOnTheSameItem() async {
        let noId = "From: a@b.c\nSubject: No id header\n\nbody"
        let emails = await EmailDrop.readFiles(from: [provider(link: "message:%3Cfrom-link%40x%3E", eml: noId)])
        XCTAssertEqual(emails.first?.messageID, "from-link@x")
    }

    func testAFileThatNeverArrivesGivesUpAfterTheTimeLimit() async {
        let started = Date()
        let emails = await EmailDrop.readFiles(from: [provider(neverDeliverEML: true)], timeout: 0.3)
        XCTAssertTrue(emails.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testMergeFillsGapsKeepsOrderAndNeverMergesMessagesWithoutIds() {
        let merged = EmailDrop.merge([
            ParsedEmail(subject: "(no subject)", messageID: "a"),
            ParsedEmail(subject: "B", messageID: "b"),
            ParsedEmail(subject: "Real subject", from: "x", messageID: "a", snippet: "text"),
        ])
        XCTAssertEqual(merged.map(\.messageID), ["a", "b"])
        XCTAssertEqual(merged[0].subject, "Real subject")
        XCTAssertEqual(merged[0].snippet, "text")
        XCTAssertEqual(EmailDrop.merge([ParsedEmail(subject: "One"), ParsedEmail(subject: "Two")]).map(\.subject), ["One", "Two"])
    }

    // MARK: Routing

    /// The bug seen on a real Mac: Mail also offers the subject as plain text, and a text-based "move card" handler
    /// took the drag and failed silently. A drag with a link must be a message, whatever else it carries.
    func testAMailDragThatAlsoOffersPlainTextIsAMessageNotACard() async {
        let recorder = Recorder()
        let accepted = drop([
            provider(link: "message:%3Cm1%40example.com%3E", subject: "Kickoff agenda", text: "Kickoff agenda"),
            provider(eml: eml, emlType: "com.apple.mail.email"),
        ], recorder: recorder)
        XCTAssertTrue(accepted)
        await waitUntil { !recorder.enriched.isEmpty }
        XCTAssertTrue(recorder.moved.isEmpty, "must not be treated as a card id")
        XCTAssertEqual(recorder.added.count, 1)
        XCTAssertEqual(recorder.added.first?.map(\.subject), ["Kickoff agenda"])
        XCTAssertNil(recorder.added.first?.first?.from, "the card is created first from the link alone")
        XCTAssertEqual(recorder.enriched.first?.first?.from, "Ana Souza <ana@example.com>", "then details arrive")
    }

    /// The shape of the real log: SwiftUI delivers only the file promise as providers, the link is on the pasteboard.
    func testTheCardAppearsInstantlyFromThePasteboardWhileTheSlowEMLIsStillPending() async {
        let recorder = Recorder()
        let board = pasteboard(link: "message:%3Cm1%40example.com%3E", subject: "Kickoff agenda")
        _ = drop([provider(emlType: "com.apple.mail.email", neverDeliverEML: true)], recorder: recorder, pasteboard: board)
        // No waiting: the cards must already be there when the drop callback returns.
        XCTAssertEqual(recorder.added.first?.map(\.subject), ["Kickoff agenda"])
        XCTAssertNil(recorder.added.first?.first?.from)
        XCTAssertTrue(recorder.moved.isEmpty)
    }

    func testTheEMLEnrichesAnAlreadyCreatedCardWhenItArrives() async {
        let recorder = Recorder()
        let board = pasteboard(link: "message:%3Cm1%40example.com%3E", subject: "Kickoff agenda")
        _ = drop([provider(eml: eml, emlType: "com.apple.mail.email")], recorder: recorder, pasteboard: board)
        await waitUntil { !recorder.enriched.isEmpty }
        XCTAssertEqual(recorder.added.count, 1, "one card, not a second one from the .eml")
        XCTAssertEqual(recorder.enriched.first?.first?.from, "Ana Souza <ana@example.com>")
    }

    func testAStalePasteboardIsIgnoredForADropThatIsNotFromMail() async {
        let recorder = Recorder()
        let stale = pasteboard(link: "message:%3Cold%40example.com%3E", subject: "An old drag")
        XCTAssertTrue(drop([provider(text: "card-123")], recorder: recorder, pasteboard: stale))
        await waitUntil { !recorder.moved.isEmpty }
        XCTAssertEqual(recorder.moved, ["card-123"])
        XCTAssertTrue(recorder.added.isEmpty)
    }

    func testTwoFilePromisesAreRequestedAtOnceSoTheWaitsDoNotAdd() async {
        let started = Date()
        let emails = await EmailDrop.readFiles(
            from: (0..<3).map { _ in provider(emlType: "com.apple.mail.email", neverDeliverEML: true) }, timeout: 0.5
        )
        XCTAssertTrue(emails.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.2, "sequential reads would take 1.5 s")
    }

    func testReadingThePasteboardAloneNeverTouchesTheFilePromise() {
        let emails = EmailDrop.readPasteboard(pasteboard(link: "message:%3Ca%40x%3E", subject: "Hello"))
        XCTAssertEqual(emails, [ParsedEmail(subject: "Hello", messageID: "a@x")])
        XCTAssertTrue(EmailDrop.readPasteboard(pasteboard(link: "https://example.com", subject: "Web")).isEmpty)
        XCTAssertTrue(EmailDrop.readPasteboard(pasteboard()).isEmpty)
    }

    func testTheCardIsCreatedEvenWhenTheEMLNeverArrives() async {
        let recorder = Recorder()
        _ = drop([provider(link: "message:%3Cm1%40example.com%3E", subject: "Kickoff agenda"), provider(neverDeliverEML: true)],
                 recorder: recorder)
        await waitUntil { !recorder.added.isEmpty }
        XCTAssertEqual(recorder.added.first?.map(\.subject), ["Kickoff agenda"])
        XCTAssertTrue(recorder.problems.allSatisfy { $0 == nil })
    }

    func testOurOwnCardDragIsPlainTextAndMovesTheCard() async {
        let recorder = Recorder()
        XCTAssertTrue(drop([provider(text: "card-123")], recorder: recorder))
        await waitUntil { !recorder.moved.isEmpty }
        XCTAssertEqual(recorder.moved, ["card-123"])
        XCTAssertTrue(recorder.added.isEmpty)
    }

    func testADropWithNothingUsableIsRefusedAndAWebLinkExplainsItself() async {
        let recorder = Recorder()
        XCTAssertFalse(drop([NSItemProvider()], recorder: recorder))

        XCTAssertTrue(drop([provider(link: "https://example.com/page")], recorder: recorder))
        await waitUntil { !recorder.problems.isEmpty }
        XCTAssertTrue(recorder.added.isEmpty)
        XCTAssertTrue(recorder.problems.compactMap { $0 }.first?.contains("public.url") == true)
    }
}
