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

final class PastedLinksTests: XCTestCase {
    private func rich(_ parts: [(String, String?)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (text, link) in parts {
            let attributes: [NSAttributedString.Key: Any] = link.flatMap { URL(string: $0) }.map { [LinkedText.linkKey: $0] } ?? [:]
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        return result
    }

    func testAHiddenAddressBecomesAMarkdownLink() {
        let pasted = rich([("See the ", nil), ("project brief", "https://example.com/brief"), (" first.", nil)])
        XCTAssertEqual(LinkedText.markdown(from: pasted), "See the [project brief](https://example.com/brief) first.")
        XCTAssertEqual(LinkedText.segments(in: LinkedText.markdown(from: pasted)).compactMap { $0.url?.absoluteString }, ["https://example.com/brief"])
    }

    func testTextThatIsAlreadyTheAddressIsNotWrapped() {
        XCTAssertEqual(LinkedText.markdown(from: rich([("https://example.com/a", "https://example.com/a")])), "https://example.com/a")
        XCTAssertEqual(LinkedText.markdown(from: rich([("www.example.com", "http://www.example.com")])), "www.example.com")
        XCTAssertEqual(LinkedText.markdown(from: rich([("ana@example.com", "mailto:ana@example.com")])), "ana@example.com")
    }

    func testBracketsAndLineBreaksInTheTitleCannotBreakTheLink() {
        let pasted = rich([("Q3 [draft]\nreport", "https://example.com/q3")])
        let text = LinkedText.markdown(from: pasted)
        XCTAssertEqual(text, "[Q3 (draft) report](https://example.com/q3)")
        XCTAssertEqual(LinkedText.segments(in: text).compactMap { $0.url?.absoluteString }, ["https://example.com/q3"])
    }

    func testUnsafeAddressesAreDroppedToTheirText() {
        XCTAssertEqual(LinkedText.markdown(from: rich([("click me", "javascript:alert(1)")])), "click me")
        XCTAssertEqual(LinkedText.markdown(from: rich([("open", "file:///etc/passwd")])), "open")
    }

    func testRichTextNoiseIsTrimmed() {
        XCTAssertEqual(LinkedText.markdown(from: rich([("Line\u{00A0}one\n\n", nil)])), "Line one")
        XCTAssertEqual(LinkedText.markdown(from: NSAttributedString(string: "")), "")
    }
}

final class PastedHTMLLinksTests: XCTestCase {
    func testAnchorsInHTMLAreAppliedToThePlainText() {
        let html = #"<p>See <a href="https://example.com/brief">the brief</a> and <a href="https://x.example">https://x.example</a>.</p>"#
        let text = LinkedText.markdown(fromHTML: html, plainText: "See the brief and https://x.example.")
        XCTAssertEqual(text, "See [the brief](https://example.com/brief) and https://x.example.")
    }

    func testEntitiesTagsAndQuotesInAnAnchorAreHandled() {
        let html = "<A CLASS='x' HREF='https://example.com/a?x=1&amp;y=2'><b>Q3</b> &amp; Q4\nreport</A>"
        let links = LinkedText.hiddenLinks(inHTML: html)
        XCTAssertEqual(links.first?.url.absoluteString, "https://example.com/a?x=1&y=2")
        XCTAssertEqual(links.first?.title, "Q3 & Q4\nreport")
        XCTAssertEqual(LinkedText.markdown(fromHTML: html, plainText: "Q3 & Q4 report"), "[Q3 & Q4 report](https://example.com/a?x=1&y=2)", "line breaks may differ between the page and its plain text")
        XCTAssertEqual(LinkedText.markdown(fromHTML: html, plainText: "something else entirely"), "something else entirely", "a title the plain text does not hold is skipped, never invented")
    }

    func testTheSameTitleTwiceLinksTheRightOccurrences() {
        let html = #"<a href="https://a.example">here</a> and <a href="https://b.example">here</a>"#
        XCTAssertEqual(LinkedText.markdown(fromHTML: html, plainText: "here and here"), "[here](https://a.example) and [here](https://b.example)")
    }

    func testUnsafeAnchorsAndAnchorsWithoutHrefAreIgnored() {
        let html = #"<a href="javascript:alert(1)">click</a> <a name="top">anchor</a> <a href="mailto:ana@example.com">Ana</a>"#
        XCTAssertEqual(LinkedText.markdown(fromHTML: html, plainText: "click anchor Ana"), "click anchor [Ana](mailto:ana@example.com)")
    }

    func testPlainTextWithoutLinksComesBackUnchanged() {
        XCTAssertEqual(LinkedText.markdown(fromHTML: "<p>Just text</p>", plainText: "Just text"), "Just text")
        XCTAssertEqual(LinkedText.markdown(fromHTML: "", plainText: ""), "")
    }
}
