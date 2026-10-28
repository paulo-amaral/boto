import KanbanCore
import SwiftUI

/// A project's sticky notes: free text on coloured squares, newest first, for annotations that are not tasks.
struct ProjectNotesView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var focusId: String?

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16, alignment: .top)]

    var body: some View {
        let notes = project.liveNotes
        VStack(spacing: 0) {
            HStack {
                Text("Notes: \(project.name)").font(Theme.font(16, weight: .semibold)).lineLimit(1)
                Spacer()
                Button { focusId = project.addNote().publicId } label: { Label("New note", systemImage: "plus") }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(22)

            if notes.isEmpty {
                Text("No notes yet. A note is free text for things that are not tasks: a phone call, a decision, a link. Use New note to start one.")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380, maxHeight: .infinity)
                    .padding(22)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(notes, id: \.publicId) { note in NoteCard(note: note, focusId: $focusId) }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 820, minHeight: 420, idealHeight: 600)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

/// One sticky note. The colour row and the delete button are always visible, so nothing depends on hovering.
private struct NoteCard: View {
    @Bindable var note: Note
    @Binding var focusId: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if note.text.isEmpty {
                    Text("Write a note...").font(Theme.font(14)).foregroundStyle(Theme.onLight.opacity(0.7))
                        .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $note.text)
                    .font(Theme.font(14))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .accessibilityLabel("Note text")
            }
            .frame(minHeight: 140)

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
            if focusId == note.publicId { focused = true; focusId = nil }
        }
    }
}
