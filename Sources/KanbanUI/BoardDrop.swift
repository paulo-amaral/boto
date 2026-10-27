import AppKit
import KanbanCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension ModelContext {
    func card(publicId: String) -> Card? {
        try? fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.publicId == publicId })).first
    }
}

/// The single drop handler for lists, cards and importance cells. A drop is either one of our own cards, which are
/// dragged as plain text, or a message from Mail, which also offers its subject as plain text. Having two handlers of
/// different kinds on nested views let the text one take Mail's drag and fail silently, so one handler decides by what
/// the drag contains: anything with a link or an email type is a message, plain text alone is a card.
enum BoardDrop {
    static let types: [UTType] = [.url, .emailMessage, .plainText]

    @MainActor
    static func handle(_ providers: [NSItemProvider],
                       pasteboard: NSPasteboard? = NSPasteboard(name: .drag),
                       moveCard: @escaping (String) -> Void,
                       addEmails: @escaping ([ParsedEmail]) -> Void,
                       enrich: @escaping ([ParsedEmail]) -> Void,
                       problem: @escaping (String?) -> Void) -> Bool {

        if EmailDrop.looksLikeMail(providers) {
            // The link and subject are on the drag pasteboard right now, so the cards appear instantly.
            var linked = pasteboard.map(EmailDrop.readPasteboard) ?? []
            if !linked.isEmpty {
                problem(nil)
                addEmails(linked)
            }
            Task { @MainActor in
                if linked.isEmpty {
                    linked = await EmailDrop.readLinks(from: providers)
                    if !linked.isEmpty { problem(nil); addEmails(linked) }
                }
                // The .eml adds sender, date and text, or is the only source when there is no link.
                let rich = await EmailDrop.readFiles(from: providers)
                if !linked.isEmpty {
                    if !rich.isEmpty { enrich(rich) }
                } else if rich.isEmpty {
                    problem(EmailDrop.Failure(offered: EmailDrop.offeredTypes(providers)).localizedDescription)
                } else {
                    problem(nil)
                    addEmails(rich)
                }
            }
            return true
        }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let id = (object as? NSString).map({ $0 as String }) else { return }
                Task { @MainActor in moveCard(id) }
            }
            return true
        }
        return false
    }
}

private struct BoardDropTarget: ViewModifier {
    @Binding var targeted: Bool
    @Binding var problem: String?
    let moveCard: (String) -> Void
    let addEmails: ([ParsedEmail]) -> Void
    let enrich: ([ParsedEmail]) -> Void

    func body(content: Content) -> some View {
        content.onDrop(of: BoardDrop.types, isTargeted: $targeted) { providers, _ in
            BoardDrop.handle(providers, moveCard: moveCard, addEmails: addEmails, enrich: enrich) { text in
                problem = text
                guard text != nil else { return }
                Task {
                    try? await Task.sleep(for: .seconds(10))
                    if problem == text { problem = nil }
                }
            }
        }
    }
}

extension View {
    func boardDrop(targeted: Binding<Bool>, problem: Binding<String?>,
                   moveCard: @escaping (String) -> Void,
                   addEmails: @escaping ([ParsedEmail]) -> Void,
                   enrich: @escaping ([ParsedEmail]) -> Void) -> some View {
        modifier(BoardDropTarget(targeted: targeted, problem: problem, moveCard: moveCard, addEmails: addEmails, enrich: enrich))
    }
}
