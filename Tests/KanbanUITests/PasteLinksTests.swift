import AppKit
import XCTest
@testable import KanbanCore
@testable import KanbanUI

@MainActor
final class PasteLinksTests: XCTestCase {
    /// A pasteboard of its own, so the test never reads or overwrites the person's clipboard.
    private func privatePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("boto-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        addTeardownBlock { pasteboard.releaseGlobally() }
        return pasteboard
    }

    private func richWithLink() throws -> Data {
        let text = NSMutableAttributedString(string: "Read ")
        text.append(NSAttributedString(string: "the brief", attributes: [LinkedText.linkKey: URL(string: "https://example.com/brief")!]))
        text.append(NSAttributedString(string: " today"))
        return try XCTUnwrap(text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]))
    }

    func testRTFWithAHiddenLinkKeepsIt() throws {
        let pasteboard = privatePasteboard()
        pasteboard.setString("Read the brief today", forType: .string)
        pasteboard.setData(try richWithLink(), forType: .rtf)
        XCTAssertEqual(PastedText.withLinks(from: pasteboard), "Read [the brief](https://example.com/brief) today")
    }

    func testHTMLWithAHiddenLinkKeepsItWithoutRenderingTheHTML() {
        let pasteboard = privatePasteboard()
        pasteboard.setString("Open the report", forType: .string)
        pasteboard.setString(#"<p>Open <a href="https://example.com/report">the report</a><img src="https://tracker.example/pixel.gif"></p>"#, forType: .html)
        XCTAssertEqual(PastedText.withLinks(from: pasteboard), "Open [the report](https://example.com/report)")
    }

    func testAnOrdinaryPasteIsLeftAlone() {
        let pasteboard = privatePasteboard()
        pasteboard.setString("Just words, and https://example.com/x", forType: .string)
        XCTAssertNil(PastedText.withLinks(from: pasteboard), "no hidden link: the normal paste runs")
        let withMarkup = privatePasteboard()
        withMarkup.setString("bold text", forType: .string)
        withMarkup.setString("<p><b>bold</b> text</p>", forType: .html)
        XCTAssertNil(PastedText.withLinks(from: withMarkup))
        XCTAssertNil(PastedText.withLinks(from: privatePasteboard()), "an empty pasteboard")
    }

    func testPastingIntoTheEditorInsertsTheLinkAtTheCursor() throws {
        let view = PasteLinkTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        view.pasteboard = privatePasteboard()
        view.pasteboard.setString("the brief", forType: .string)
        view.pasteboard.setString(#"<a href="https://example.com/brief">the brief</a>"#, forType: .html)
        view.string = "Start  end"
        view.setSelectedRange(NSRange(location: 6, length: 0))
        view.paste(nil)
        XCTAssertEqual(view.string, "Start [the brief](https://example.com/brief) end")
        XCTAssertEqual(LinkedText.segments(in: view.string).compactMap { $0.url?.absoluteString }, ["https://example.com/brief"])
    }

    func testPastingOverASelectionReplacesIt() {
        let view = PasteLinkTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        view.pasteboard = privatePasteboard()
        view.pasteboard.setString("Ana", forType: .string)
        view.pasteboard.setString(#"<a href="mailto:ana@example.com">Ana</a>"#, forType: .html)
        view.string = "Ask NAME now"
        view.setSelectedRange(NSRange(location: 4, length: 4))
        view.paste(nil)
        XCTAssertEqual(view.string, "Ask [Ana](mailto:ana@example.com) now")
    }
}
