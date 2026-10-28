import AppKit
import KanbanCore
import SwiftUI

/// Text that is typed and also has links that open, in notes and in card descriptions. While it is being edited it is
/// plain text, with Markdown links as typed. When it is not and it holds links, it shows them as links: a click on a
/// link opens it, a click anywhere else edits. Text with no links is always the plain editor. Pasting rich text, such
/// as from an e-mail, keeps its links as `[title](address)`. The same text view handles every click, so a link can never
/// lose the click to the surrounding view.
struct LinkedTextField: View {
    @Binding var text: String
    var placeholder: String
    var accessibilityLabel: String
    var fontSize: CGFloat = 14
    var textColor: Color = Theme.text
    var placeholderColor: Color = Theme.muted
    var linkColor: Color = Theme.info
    /// A small "Edit" label in the corner. A narrow note has no room for it; clicking the text still edits.
    var showsEditHint = true
    /// Bumped by the parent to move keyboard focus here, for a note that was just created.
    var focusToken = 0
    @State private var rendered = false
    @State private var editToken = 0

    var body: some View {
        LinkAwareTextEditor(
            text: $text, fontSize: fontSize, textColor: NSColor(textColor), linkColor: NSColor(linkColor),
            focusToken: focusToken &+ editToken, label: accessibilityLabel, onRenderedChange: { rendered = $0 }
        )
        .overlay(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).font(Theme.font(fontSize)).foregroundStyle(placeholderColor)
                    .padding(.leading, 13).padding(.top, 8).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if rendered && showsEditHint {
                Button("Edit") { editToken &+= 1 }
                    .buttonStyle(.plain)
                    .font(Theme.font(11))
                    .foregroundStyle(placeholderColor)
                    .padding(8)
                    .help("Edit the text")
            }
        }
    }
}

/// The text view behind `LinkedTextField`, on `NSTextView` because SwiftUI's `TextEditor` can neither change what a
/// paste inserts nor show links that open.
struct LinkAwareTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var textColor: NSColor
    var linkColor: NSColor
    /// A change in this number moves keyboard focus into the editor, and so into editing.
    var focusToken: Int
    var label: String
    var onRenderedChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder

        let view = PasteLinkTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.setAccessibilityLabel(label)
        view.onRenderedChange = { rendered in DispatchQueue.main.async { context.coordinator.parent.onRenderedChange(rendered) } }
        view.style(font: font, color: textColor, linkColor: linkColor)
        view.load(text)
        scroll.documentView = view
        context.coordinator.lastFocusToken = focusToken
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? PasteLinkTextView else { return }
        view.style(font: font, color: textColor, linkColor: linkColor)
        if view.rawText != text { view.load(text) }
        if focusToken != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { view.beginEditing() }
        }
    }

    private var font: NSFont {
        NSFont(name: Theme.fontFamily, size: TypeScale.snap(fontSize)) ?? .systemFont(ofSize: TypeScale.snap(fontSize))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LinkAwareTextEditor
        var lastFocusToken = 0
        init(_ parent: LinkAwareTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? PasteLinkTextView else { return }
            view.rawText = view.string
            parent.text = view.string
        }
    }
}

final class PasteLinkTextView: NSTextView {
    /// The general pasteboard; a test supplies its own so it never touches the person's clipboard.
    var pasteboard: NSPasteboard = .general
    /// How a link is opened; a test supplies its own so it never launches a browser.
    var openLink: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var onRenderedChange: (Bool) -> Void = { _ in }

    /// The text as it is stored, with Markdown links as typed. `string` shows this while editing and the links as
    /// titles while rendered.
    var rawText = ""
    private(set) var isRendered = false

    private var plainFont = NSFont.systemFont(ofSize: 14)
    private var plainColor = NSColor.textColor
    private var linkColor = NSColor.linkColor

    func style(font: NSFont, color: NSColor, linkColor: NSColor) {
        let changed = font != plainFont || color != plainColor || linkColor != self.linkColor
        plainFont = font
        plainColor = color
        self.linkColor = linkColor
        insertionPointColor = color
        self.linkTextAttributes = [.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        if changed { refresh() }
    }

    /// New text from outside, such as a note whose text changed elsewhere.
    func load(_ text: String) {
        rawText = text
        refresh()
    }

    /// Links show as links when the text has any and it is not being edited; everything else is the plain editor.
    /// `editing` is passed in when the caller knows better than the window: during `resignFirstResponder` the window
    /// still lists this view as the first responder, so asking it would always answer "editing".
    func refresh(editing: Bool? = nil) {
        let isEditing = editing ?? (window?.firstResponder === self && !isRendered)
        if !isEditing && LinkedText.hasLinks(rawText) { renderLinks() } else { renderPlain() }
    }

    private func renderPlain() {
        let wasRendered = isRendered
        isRendered = false
        isEditable = true
        typingAttributes = [.font: plainFont, .foregroundColor: plainColor]
        let selection = selectedRange()
        textStorage?.setAttributedString(NSAttributedString(string: rawText, attributes: typingAttributes))
        setSelectedRange(NSRange(location: min(selection.location, (rawText as NSString).length), length: 0))
        if wasRendered { onRenderedChange(false) }
    }

    private func renderLinks() {
        let shown = NSMutableAttributedString()
        for segment in LinkedText.segments(in: rawText) {
            var attributes: [NSAttributedString.Key: Any] = [.font: plainFont, .foregroundColor: plainColor]
            if let url = segment.url { attributes[.link] = url }
            shown.append(NSAttributedString(string: segment.text, attributes: attributes))
        }
        let wasRendered = isRendered
        isRendered = true
        isEditable = false
        isSelectable = true
        textStorage?.setAttributedString(shown)
        if !wasRendered { onRenderedChange(true) }
    }

    /// Moves into editing, from the keyboard or from the "Edit" label.
    func beginEditing() {
        if isRendered { switchToEditing() }
        window?.makeFirstResponder(self)
    }

    private func switchToEditing() {
        guard isRendered else { return }
        renderPlain()
        setSelectedRange(NSRange(location: (rawText as NSString).length, length: 0))
    }

    /// The address under a point, when the point is on the text of a link and not just near it.
    func link(at point: NSPoint) -> URL? {
        guard let layoutManager, let textContainer else { return nil }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: inContainer, in: textContainer)
        guard layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(inContainer) else { return nil }
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        guard let storage = textStorage, character < storage.length else { return nil }
        return storage.attribute(.link, at: character, effectiveRange: nil) as? URL
    }

    override func mouseDown(with event: NSEvent) {
        guard isRendered else { super.mouseDown(with: event); return }
        if let url = link(at: convert(event.locationInWindow, from: nil)) {
            openLink(url)
        } else {
            beginEditing()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        // Arriving from the keyboard, not by a click, which `mouseDown` already handled.
        if accepted, isRendered { switchToEditing() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { rawText = string; refresh(editing: false) }
        return accepted
    }

    override func paste(_ sender: Any?) {
        if let text = PastedText.withLinks(from: pasteboard) {
            insertText(text, replacementRange: selectedRange())
        } else {
            super.paste(sender)
        }
    }
}

enum PastedText {
    /// The plain text on the pasteboard with its hidden links written out, or nil when there are none, so an ordinary
    /// paste stays an ordinary paste. RTF is read as a document; HTML is only read for its links, never rendered.
    static func withLinks(from pasteboard: NSPasteboard) -> String? {
        guard let plain = pasteboard.string(forType: .string), !plain.isEmpty else { return nil }
        var links: [LinkedText.HiddenLink] = []
        if let rtf = pasteboard.data(forType: .rtf), let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            links = LinkedText.hiddenLinks(in: attributed)
        }
        if links.isEmpty, let html = pasteboard.string(forType: .html) { links = LinkedText.hiddenLinks(inHTML: html) }
        return links.isEmpty ? nil : LinkedText.markdown(text: plain, links: links)
    }
}
