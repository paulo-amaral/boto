import KanbanCore
import SwiftUI

/// A card's description. A plain text editor does not make links clickable, and a clickable view cannot be typed in, so
/// the field is both: it edits while it has focus, and when it does not and the text holds links, it shows them as
/// links. Clicking the text starts editing again. Text with no links is always the plain editor.
struct DescriptionField: View {
    @Binding var text: String
    @State private var editing = false
    @FocusState private var focused: Bool

    private var showsLinks: Bool { !editing && LinkedText.hasLinks(text) }

    var body: some View {
        Group {
            if showsLinks { rendered } else { editor }
        }
        .frame(minHeight: 110, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(Theme.font(14))
            .scrollContentBackground(.hidden)
            .padding(8)
            .focused($focused)
            // Focus decides the mode, so typing an address never swaps the editor away under the cursor.
            .onChange(of: focused) { editing = focused }
            .onAppear { if editing { focused = true } }
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Add a more detailed description...").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .padding(.leading, 13).padding(.top, 8).allowsHitTesting(false)
                }
            }
    }

    private var rendered: some View {
        Text(attributed)
            .font(Theme.font(14))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(13)
            .contentShape(Rectangle())
            // A click on a link opens it; a click anywhere else on the text edits the description.
            .onTapGesture { editing = true }
            .overlay(alignment: .topTrailing) {
                Button("Edit") { editing = true }
                    .buttonStyle(.plain)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.muted)
                    .padding(8)
                    .help("Edit the description")
            }
            .accessibilityHint("Links open in your browser. Activate the text to edit it.")
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for segment in LinkedText.segments(in: text) {
            var piece = AttributedString(segment.text)
            if let url = segment.url {
                piece.link = url
                piece.foregroundColor = Theme.info
                piece.underlineStyle = .single
            }
            result += piece
        }
        return result
    }
}
