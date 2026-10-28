import AppKit
import XCTest
@testable import KanbanCore
@testable import KanbanUI

/// Drives the text view behind notes and descriptions with real mouse events, because a link that only looks right in a
/// picture can still lose its click.
@MainActor
final class LinkedTextViewTests: XCTestCase {
    private var window: NSWindow?

    private func makeView(_ text: String) -> PasteLinkTextView {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let view = PasteLinkTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.textContainerInset = NSSize(width: 8, height: 8)
        window.contentView = view
        self.window = window
        view.style(font: .systemFont(ofSize: 14), color: .white, linkColor: .systemBlue)
        view.load(text)
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        return view
    }

    private func click(_ view: PasteLinkTextView, at point: NSPoint) {
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [],
                                       timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        view.mouseDown(with: event)
    }

    /// The middle of a piece of text, in the view's own coordinates.
    private func center(of text: String, in view: PasteLinkTextView) -> NSPoint {
        let range = (view.string as NSString).range(of: text)
        let layout = view.layoutManager!
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: view.textContainer!)
        return NSPoint(x: rect.midX + view.textContainerOrigin.x, y: rect.midY + view.textContainerOrigin.y)
    }

    func testTextWithLinksShowsThemAsLinks() {
        let view = makeView("See [the brief](https://example.com/brief) now")
        XCTAssertTrue(view.isRendered)
        XCTAssertEqual(view.string, "See the brief now", "a Markdown link shows as its title")
        let range = (view.string as NSString).range(of: "the brief")
        XCTAssertEqual(view.textStorage?.attribute(.link, at: range.location, effectiveRange: nil) as? URL, URL(string: "https://example.com/brief"))
        XCTAssertNil(view.textStorage?.attribute(.link, at: 0, effectiveRange: nil), "the words around it are not links")
    }

    func testClickingALinkOpensItAndDoesNotEdit() {
        let view = makeView("Call the CFO. Brief: https://example.com/brief and more")
        var opened: [URL] = []
        view.openLink = { opened.append($0) }
        click(view, at: center(of: "https://example.com/brief", in: view))
        XCTAssertEqual(opened, [URL(string: "https://example.com/brief")!])
        XCTAssertTrue(view.isRendered, "opening a link leaves the text as it was")
        XCTAssertFalse(view.isEditable)
    }

    func testClickingAMarkdownTitleOpensItsAddress() {
        let view = makeView("Open [the report](https://example.com/q3) first")
        var opened: [URL] = []
        view.openLink = { opened.append($0) }
        click(view, at: center(of: "the report", in: view))
        XCTAssertEqual(opened, [URL(string: "https://example.com/q3")!])
    }

    func testClickingPlainTextOrEmptySpaceStartsEditing() {
        let view = makeView("Call the CFO. Brief: https://example.com/brief")
        var opened: [URL] = []
        view.openLink = { opened.append($0) }
        click(view, at: center(of: "Call", in: view))
        XCTAssertTrue(opened.isEmpty)
        XCTAssertFalse(view.isRendered)
        XCTAssertTrue(view.isEditable)
        XCTAssertEqual(view.string, "Call the CFO. Brief: https://example.com/brief", "editing shows the text as stored")

        let second = makeView("Brief: https://example.com/brief")
        click(second, at: NSPoint(x: 300, y: 180))
        XCTAssertFalse(second.isRendered, "a click below the text edits too")
    }

    func testEditingShowsMarkdownAsTypedAndBlurringShowsLinksAgain() {
        let view = makeView("Open [the report](https://example.com/q3) first")
        view.beginEditing()
        XCTAssertEqual(view.string, "Open [the report](https://example.com/q3) first")
        XCTAssertTrue(view.isEditable)
        XCTAssertTrue(window?.makeFirstResponder(nil) ?? false)
        XCTAssertTrue(view.isRendered)
        XCTAssertEqual(view.string, "Open the report first")
    }

    func testTypingAnAddressAndLeavingTheFieldMakesItALink() throws {
        let view = makeView("")
        XCTAssertFalse(view.isRendered, "empty text is the plain editor")
        XCTAssertTrue(window?.makeFirstResponder(view) ?? false)
        view.insertText("Docs at https://example.com/docs", replacementRange: NSRange(location: 0, length: 0))
        view.rawText = view.string
        XCTAssertFalse(view.isRendered, "typing an address does not swap the editor away under the cursor")
        XCTAssertTrue(window?.makeFirstResponder(nil) ?? false)
        XCTAssertTrue(view.isRendered)
        let range = (view.string as NSString).range(of: "https://example.com/docs")
        XCTAssertEqual(view.textStorage?.attribute(.link, at: range.location, effectiveRange: nil) as? URL, URL(string: "https://example.com/docs"))
    }

    func testTextWithoutLinksStaysAnEditorAndNeverRenders() {
        let view = makeView("Just a reminder, README.md and ledger.xlsx")
        XCTAssertFalse(view.isRendered)
        XCTAssertTrue(view.isEditable)
        XCTAssertEqual(view.string, "Just a reminder, README.md and ledger.xlsx")
    }

    func testTextChangedFromOutsideIsShownRight() {
        let view = makeView("Plain")
        view.load("Now https://example.com/x")
        XCTAssertTrue(view.isRendered)
        view.load("Plain again")
        XCTAssertFalse(view.isRendered)
        XCTAssertEqual(view.rawText, "Plain again")
    }

    func testAnUnsafeLinkIsNeverClickable() {
        let view = makeView("Run [this](javascript:alert(1)) or file:///etc/passwd")
        XCTAssertFalse(view.isRendered, "nothing in it is a link, so it stays a plain editor showing the text as typed")
        XCTAssertEqual(view.string, "Run [this](javascript:alert(1)) or file:///etc/passwd")
    }
}
