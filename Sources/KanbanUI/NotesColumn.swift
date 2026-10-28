import KanbanCore
import SwiftUI

/// The project's sticky notes as a column at the start of the board, in the same panel as a list. It shows only when
/// there is a note, and the Note button in the board header adds one. Notes are for things worth remembering that are
/// not tasks, so they live beside the lists and never inside them.
struct NotesColumn: View {
    let project: Project
    @Binding var focusId: String?
    var fill = false
    @Environment(\.isCompactWindow) private var compact

    private var width: CGFloat { compact ? Theme.compactListWidth : Theme.listWidth }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Notes").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.text).padding(.leading, 8)
                Spacer()
                NoteSizeMenu()
                Button { focusId = project.addNote().publicId } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .help("New note")
                    .accessibilityLabel("New note")
            }
            // As tall as its notes, like a list; only when they no longer fit does the scroll view win.
            ViewThatFits(in: .vertical) {
                VStack(spacing: 12) { noteRows }.padding(.horizontal, 2).padding(.vertical, 4)
                ScrollView { LazyVStack(spacing: 12) { noteRows }.padding(.horizontal, 2).padding(.vertical, 4) }.scrollIndicators(.hidden)
            }
        }
        .padding(8)
        .frame(width: fill ? nil : width)
        .frame(maxWidth: fill ? .infinity : nil)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.list))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.card, lineWidth: 1))
        .frame(maxHeight: fill ? nil : .infinity, alignment: .top)
    }

    @ViewBuilder
    private var noteRows: some View {
        ForEach(project.liveNotes, id: \.publicId) { NoteCard(note: $0, focusId: $focusId) }
    }
}

/// The same notes as a row, for the importance view, which has no room for a column at the start.
struct NotesStrip: View {
    let project: Project
    @Binding var focusId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Notes").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.text)
                Button { focusId = project.addNote().publicId } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .help("New note")
                    .accessibilityLabel("New note")
                NoteSizeMenu()
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(project.liveNotes, id: \.publicId) { NoteCard(note: $0, focusId: $focusId).frame(width: 240) }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }
}

enum NoteStyle {
    /// The two faces a note can use, both steps of the type scale. Small is the default, so a note holds more.
    static let sizes: [(name: String, size: Double)] = [("Small", 12), ("Medium", 14)]
    static let storageKey = "noteFontSize"
}

/// Chooses the text size of every note. It lives in the column and the row so it sits next to what it changes.
struct NoteSizeMenu: View {
    @AppStorage(NoteStyle.storageKey) private var size: Double = NoteStyle.sizes[0].size

    var body: some View {
        Menu {
            ForEach(NoteStyle.sizes, id: \.size) { option in
                Button { size = option.size } label: {
                    if size == option.size { Label(option.name, systemImage: "checkmark") } else { Text(option.name) }
                }
            }
        } label: { Image(systemName: "textformat.size") }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Theme.muted)
        .help("Note text size")
        .accessibilityLabel("Note text size")
    }
}

/// One sticky note. The colour row and the delete button are always visible, so nothing depends on hovering.
struct NoteCard: View {
    @Bindable var note: Note
    @AppStorage(NoteStyle.storageKey) private var fontSize: Double = NoteStyle.sizes[0].size
    @Binding var focusId: String?
    @State private var focusToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A small face, so a note holds more. A fixed height makes it a post-it and not a panel that grows to fill the
            // column; long text scrolls inside.
            LinkedTextField(
                text: $note.text, placeholder: "Write a note...", accessibilityLabel: "Note text", fontSize: CGFloat(fontSize),
                textColor: Theme.onLight, placeholderColor: Theme.onLight.opacity(0.7), linkColor: Theme.linkOnLight, showsEditHint: false, focusToken: focusToken
            )
            .frame(height: 112)

            HStack(spacing: 6) {
                ForEach(NoteColors.all, id: \.hex) { colour in
                    Button { note.colorHex = colour.hex } label: {
                        Circle().fill(Color(hex: colour.hex))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(Theme.onLight.opacity(note.colorHex == colour.hex ? 0.9 : 0.25), lineWidth: note.colorHex == colour.hex ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .help(colour.name)
                    .accessibilityLabel("\(colour.name) note")
                    .accessibilityAddTraits(note.colorHex == colour.hex ? .isSelected : [])
                }
                Spacer(minLength: 4)
                Button { note.deletedAt = Date() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .help("Delete this note. It stays in Recently deleted.")
                    .accessibilityLabel("Delete this note")
            }
        }
        .padding(12)
        .foregroundStyle(Theme.onLight)
        // The shadow belongs to the paper only; on the whole note it would blur the text.
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: note.colorHex)).shadow(color: .black.opacity(0.35), radius: 6, y: 3))
        .onChange(of: note.text) { note.updatedAt = Date() }
        .onAppear {
            if focusId == note.publicId { focusToken += 1; focusId = nil }
        }
    }
}
