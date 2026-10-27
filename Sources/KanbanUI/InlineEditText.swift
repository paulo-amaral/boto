import SwiftUI

/// Text that becomes a field on double-click. An always-editable field grabs keyboard focus when the window opens,
/// with its text selected, and the first stray keystroke renames something.
struct InlineEditText: View {
    @Binding var text: String
    let font: Font
    let placeholder: String
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(font)
                .focused($focused)
                .onSubmit { editing = false }
                .onChange(of: focused) { if !focused { editing = false } }
                .onAppear { focused = true }
        } else {
            Text(text.isEmpty ? placeholder : text)
                .font(font)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { editing = true }
                .help("Double-click to rename")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Rename") { editing = true }
        }
    }
}
