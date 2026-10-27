import XCTest
@testable import KanbanCore

final class EmailTests: XCTestCase {
    private func parse(_ text: String) -> ParsedEmail? { EmailParser.parse(Data(text.utf8)) }

    // MARK: Message links

    func testReadsBothMailLinkForms() throws {
        let noSlashes = try XCTUnwrap(URL(string: "message:%3Cabc.123%40example.com%3E"))
        let slashes = try XCTUnwrap(URL(string: "message://%3cabc.123%40example.com%3e"))
        XCTAssertEqual(MailMessageLink.messageID(from: noSlashes), "abc.123@example.com")
        XCTAssertEqual(MailMessageLink.messageID(from: slashes), "abc.123@example.com")
    }

    func testRejectsOtherSchemesAndEmptyIds() throws {
        XCTAssertNil(MailMessageLink.messageID(from: try XCTUnwrap(URL(string: "https://example.com"))))
        XCTAssertNil(MailMessageLink.messageID(from: try XCTUnwrap(URL(string: "file:///tmp/a.eml"))))
        XCTAssertNil(MailMessageLink.messageID(from: try XCTUnwrap(URL(string: "message:%3C%3E"))))
    }

    func testBuildsTheSlashedFormAndRoundTripsAwkwardIds() throws {
        XCTAssertEqual(MailMessageLink.url(forMessageID: "abc@example.com")?.absoluteString, "message://%3Cabc%40example.com%3E")
        let id = "CAF+x=y/z_1@mail.gmail.com"
        let url = try XCTUnwrap(MailMessageLink.url(forMessageID: "<\(id)>"))
        XCTAssertEqual(MailMessageLink.messageID(from: url), id)
        XCTAssertNil(MailMessageLink.url(forMessageID: "  "))
    }

    // MARK: Headers

    func testSimpleMessage() throws {
        let email = try XCTUnwrap(parse("""
        From: Ana Souza <ana@example.com>
        Subject: Kickoff agenda
        Message-ID: <m1@example.com>
        Date: Mon, 26 Oct 2026 10:30:00 +0000

        Hello,

        Please review the agenda.
        """))
        XCTAssertEqual(email.subject, "Kickoff agenda")
        XCTAssertEqual(email.from, "Ana Souza <ana@example.com>")
        XCTAssertEqual(email.messageID, "m1@example.com")
        XCTAssertEqual(email.date, ISO8601DateFormatter().date(from: "2026-10-26T10:30:00Z"))
        XCTAssertEqual(email.snippet, "Hello,\n\nPlease review the agenda.")
    }

    func testFoldedHeadersAndWindowsLineEndings() throws {
        let email = try XCTUnwrap(parse("Subject: A very long\r\n subject line\r\nMessage-ID: <m2@x>\r\n\r\nbody"))
        XCTAssertEqual(email.subject, "A very long subject line")
        XCTAssertEqual(email.snippet, "body")
    }

    func testEncodedWordsInSubjectAndSender() throws {
        let email = try XCTUnwrap(parse("""
        From: =?UTF-8?B?QW5hIFNvdXphIOKAkyBPcsOnYW1lbnRv?= <ana@example.com>
        Subject: =?UTF-8?Q?Reuni=C3=A3o_de_planejamento?=
        Message-ID: <m3@x>

        x
        """))
        XCTAssertEqual(email.subject, "Reunião de planejamento")
        XCTAssertEqual(email.from, "Ana Souza – Orçamento <ana@example.com>")
    }

    func testAdjacentEncodedWordsJoinWithoutTheSpaceBetweenThem() throws {
        let email = try XCTUnwrap(parse("Subject: =?UTF-8?Q?Hel?= =?UTF-8?Q?lo?= world\nMessage-ID: <m@x>\n\nx"))
        XCTAssertEqual(email.subject, "Hello world")
    }

    func testIsoLatinCharsetIsHonoured() throws {
        let email = try XCTUnwrap(parse("Subject: =?ISO-8859-1?Q?Caf=E9?=\nMessage-ID: <m@x>\n\nx"))
        XCTAssertEqual(email.subject, "Café")
    }

    func testNeedsASubjectOrAMessageID() {
        XCTAssertNil(parse("From: a@b.c\n\nbody"))
        XCTAssertNil(parse("just some text without headers"))
        XCTAssertEqual(parse("Message-ID: <only@id>\n\nbody")?.subject, "(no subject)")
    }

    // MARK: Bodies

    func testMultipartAlternativePrefersPlainText() throws {
        let email = try XCTUnwrap(parse("""
        Subject: Multi
        Message-ID: <m@x>
        Content-Type: multipart/alternative; boundary="BOUND"

        --BOUND
        Content-Type: text/html; charset=utf-8

        <p>HTML <b>version</b></p>
        --BOUND
        Content-Type: text/plain; charset=utf-8

        Plain version
        --BOUND--
        """))
        XCTAssertEqual(email.snippet, "Plain version")
    }

    func testHTMLOnlyMessageIsStrippedToText() throws {
        let email = try XCTUnwrap(parse("""
        Subject: Html
        Message-ID: <m@x>
        Content-Type: text/html; charset=utf-8

        <html><style>p{color:red}</style><body><p>Hello&nbsp;<b>team</b></p><p>Bye</p></body></html>
        """))
        XCTAssertEqual(email.snippet, "Hello team\nBye")
    }

    func testBase64AndQuotedPrintableBodies() throws {
        let b64 = try XCTUnwrap(parse("""
        Subject: B
        Message-ID: <m@x>
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: base64

        T2zDoSwgbXVuZG8=
        """))
        XCTAssertEqual(b64.snippet, "Olá, mundo")

        let qp = try XCTUnwrap(parse("""
        Subject: Q
        Message-ID: <m@x>
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        Ol=C3=A1, snake_case is kept =
        on one line
        """))
        XCTAssertEqual(qp.snippet, "Olá, snake_case is kept on one line")
    }

    func testSnippetIsLimited() throws {
        let body = String(repeating: "word ", count: 600)
        let email = try XCTUnwrap(EmailParser.parse(Data("Subject: L\nMessage-ID: <m@x>\n\n\(body)".utf8), snippetLimit: 100))
        XCTAssertEqual(email.snippet.count, 103)
        XCTAssertTrue(email.snippet.hasSuffix("..."))
    }
}
