import XCTest
@testable import KanbanCore

final class LinkedTextTests: XCTestCase {
    private func links(_ text: String) -> [String] {
        LinkedText.segments(in: text).compactMap { $0.url?.absoluteString }
    }

    private func shown(_ text: String) -> String { LinkedText.segments(in: text).map(\.text).joined() }

    func testAFullAddressBecomesALinkAndTheRestStaysText() {
        let segments = LinkedText.segments(in: "Read https://example.com/brief before Friday.")
        XCTAssertEqual(segments.map(\.text), ["Read ", "https://example.com/brief", " before Friday."])
        XCTAssertEqual(segments.map { $0.url?.absoluteString }, [nil, "https://example.com/brief", nil])
    }

    func testSentencePunctuationIsNotPartOfTheLink() {
        XCTAssertEqual(links("See https://example.com/a."), ["https://example.com/a"])
        XCTAssertEqual(links("(https://example.com/a)"), ["https://example.com/a"])
        XCTAssertEqual(links("Is it https://example.com/a?"), ["https://example.com/a"])
    }

    func testWwwAndAddressesWithAPathAreLinks() {
        XCTAssertEqual(links("www.example.com").count, 1)
        XCTAssertEqual(links("example.com/pricing").count, 1)
    }

    func testFileNamesAreNotMistakenForWebsites() {
        for name in ["README.md", "main.py", "run.sh", "notes.md and report.pl", "/Users/me/file.md", "v1.2.3"] {
            XCTAssertTrue(links(name).isEmpty, name)
        }
    }

    func testMailAddressesBecomeMailLinks() {
        XCTAssertEqual(links("Write to ana@example.com today"), ["mailto:ana@example.com"])
    }

    func testMarkdownLinksShowTheirTitle() {
        let segments = LinkedText.segments(in: "Open [the brief](https://example.com/brief) now")
        XCTAssertEqual(segments.map(\.text), ["Open ", "the brief", " now"])
        XCTAssertEqual(segments[1].url?.absoluteString, "https://example.com/brief")
    }

    func testMarkdownAndBareLinksCanShareALine() {
        let text = "[A](https://a.example) and https://b.example/x"
        XCTAssertEqual(links(text), ["https://a.example", "https://b.example/x"])
        XCTAssertEqual(shown(text), "A and https://b.example/x")
    }

    func testOnlyWebAndMailSchemesBecomeLinks() {
        XCTAssertTrue(links("javascript:alert(1)").isEmpty)
        XCTAssertTrue(links("file:///etc/passwd").isEmpty)
        XCTAssertTrue(links("[click](javascript:alert(1))").isEmpty)
        XCTAssertTrue(links("[click](file:///etc/passwd)").isEmpty)
        XCTAssertTrue(links("x-apple.systempreferences:com.apple.preference").isEmpty)
        XCTAssertEqual(shown("[click](javascript:alert(1))"), "[click](javascript:alert(1))", "an unsafe link stays as typed")
    }

    func testPlainTextAndEmptyTextHaveNoLinks() {
        XCTAssertTrue(LinkedText.segments(in: "").isEmpty)
        XCTAssertFalse(LinkedText.hasLinks("Nothing to click here, 3.5 hours at 10.50"))
        XCTAssertEqual(LinkedText.segments(in: "Just words").map(\.text), ["Just words"])
    }

    func testUnicodeAndLinesAreKeptIntact() {
        let text = "Reunião com a equipe\nhttps://example.com/ação 🚀\nfim"
        XCTAssertEqual(shown(text), text)
        XCTAssertEqual(links(text).count, 1)
    }

    func testTwoLinksOnSeparateLines() {
        XCTAssertEqual(links("https://a.example\nhttps://b.example").count, 2)
    }
}
