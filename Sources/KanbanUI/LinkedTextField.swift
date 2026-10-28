import AppKit
import KanbanCore
import SwiftUI

/// Text that is typed and also has links that open. A plain text editor does not make links clickable, and a clickable
/// view cannot be typed in, so the field is both: it edits while it has focus, and when it does not and the text holds
/// links, it shows them as links. Clicking the text starts editing again. Text with no links is always the editor.
/// Pasting rich text, such as from an e-mail, keeps its links as `[title](address)`.
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
    @State private var editing = false
    @State private var ownToken = 0

    private var showsLinks: Bool { !editing && LinkedText.hasLinks(text) }

    var body: some View {
        Group {
            if showsLinks { rendered } else { editor }
        }
        .onChange(of: focusToken) { editing = true }
    }

    private var editor: some View {
        LinkAwareTextEditor(
            text: $text, fontSize: fontSize, textColor: NSColor(textColor), focusToken: focusToken &+ ownToken,
            label: accessibilityLabel, onFocusChange: { editing = $0 }
        )
        .onAppear { if editing { ownToken &+= 1 } }
        .overlay(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).font(Theme.font(fontSize)).foregroundStyle(placeholderColor)
                    .padding(.leading, 13).padding(.top, 8).allowsHitTesting(false)
            }
        }
    }

    private var rendered: some View {
        ScrollView {
            Text(attributed)
                .font(Theme.font(fontSize))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .contentShape(Rectangle())
        // A click on a link opens it; a click anywhere else on the text edits it.
        .onTapGesture { editing = true }
        .overlay(alignment: .topTrailing) {
            if showsEditHint {
                Button("Edit") { editing = true }
                    .buttonStyle(.plain)
                    .font(Theme.font(11))
                    .foregroundStyle(placeholderColor)
                    .padding(8)
                    .help("Edit the text")
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: "Edit") { editing = true }
        .accessibilityHint("Links open in your browser. Activate the text to edit it.")
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for segment in LinkedText.segments(in: text) {
            var piece = AttributedString(segment.text)
            if let url = segment.url {
                piece.link = url
                piece.foregroundColor = linkColor
                piece.underlineStyle = .single
            }
            result += piece
        }
        return result
    }
}

/// A plain-text editor on `NSTextView`, because SwiftUI's `TextEditor` gives no way to change what a paste inserts.
struct LinkAwareTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var textColor: NSColor
    /// A change in this number moves keyboard focus into the editor.
    var focusToken: Int
    var label: String
    var onFocusChange: (Bool) -> Void

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
        view.string = text
        view.setAccessibilityLabel(label)
        view.onFocusChange = { focused in DispatchQueue.main.async { context.coordinator.parent.onFocusChange(focused) } }
        scroll.documentView = view
        context.coordinator.lastFocusToken = focusToken
        style(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? PasteLinkTextView else { return }
        if view.string != text { view.string = text }
        style(view)
        if focusToken != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }

    private func style(_ view: NSTextView) {
        view.font = NSFont(name: Theme.fontFamily, size: TypeScale.snap(fontSize)) ?? .systemFont(ofSize: TypeScale.snap(fontSize))
        view.textColor = textColor
        view.insertionPointColor = textColor
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LinkAwareTextEditor
        var lastFocusToken = 0
        init(_ parent: LinkAwareTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

final class PasteLinkTextView: NSTextView {
    var onFocusChange: (Bool) -> Void = { _ in }
    /// The general pasteboard; a test supplies its own so it never touches the person's clipboard.
    var pasteboard: NSPasteboard = .general

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange(false) }
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
