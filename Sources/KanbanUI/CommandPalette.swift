import AppKit
import KanbanCore
import SwiftUI

/// Search dialog: 550 pt wide, input on top, icon + title + context rows.
struct CommandPalette: View {
    let projects: [Project]
    let onSelect: (SearchResult) -> Void
    let onClose: () -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var results: [SearchResult] { Search.results(for: query, in: projects) }

    var body: some View {
        // One search per render: `results` walks every project, and the body reads it several times.
        let results = self.results
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search projects and cards...", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.font(14))
                    .focused($focused)
                    .onSubmit { choose(highlighted) }
                    .onChange(of: query) { highlighted = 0 }
                    .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(results.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
                    .onKeyPress(.escape) { onClose(); return .handled }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            if !results.isEmpty {
                Divider().overlay(Theme.divider)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            row(result, isHighlighted: index == highlighted)
                                .onTapGesture { choose(index) }
                                .accessibilityAddTraits(index == highlighted ? [.isButton, .isSelected] : .isButton)
                                .accessibilityAction(.default) { choose(index) }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 288)
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider().overlay(Theme.divider)
                Text("No results").font(Theme.font(12)).foregroundStyle(Theme.muted).padding(16)
            }
        }
        .foregroundStyle(Theme.text)
        .frame(width: 550)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.list.opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.5), radius: 35, y: 16)
        .onAppear { focused = true }
    }

    private func choose(_ index: Int) {
        guard results.indices.contains(index) else { return }
        onSelect(results[index])
    }

    private func row(_ result: SearchResult, isHighlighted: Bool) -> some View {
        let (icon, title, subtitle): (String, String, String?) = switch result {
        case .project(let project):
            ("folder", project.name, project.rootFolderURL?.path)
        case .card(let card):
            ("doc.text", card.title, [card.list?.board?.project?.name, card.list?.name].compactMap { $0 }.joined(separator: " / "))
        case .note(let note):
            ("note.text", note.title.isEmpty ? "Empty note" : note.title, note.project?.name)
        }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.muted).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(13, weight: .bold)).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(Theme.font(11)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHighlighted ? Theme.card : .clear)
        .contentShape(Rectangle())
    }
}

extension Notification.Name {
    static let botoNewList = Notification.Name("boto.newList")
    static let botoShowHelp = Notification.Name("boto.showHelp")
    static let botoGoToProjects = Notification.Name("boto.goToProjects")
}

/// Plain-key shortcuts (C, /, G then B). Notifications reach the live view, so no stale state is captured.
@MainActor
enum ShortcutMonitor {
    private static var installed = false
    private static var pendingGo: Date?

    static func install() {
        guard !installed else { return }
        installed = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    private static func handle(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              event.window?.sheetParent == nil,
              !(event.window?.firstResponder is NSText),
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return false }

        defer { if key != "g" { pendingGo = nil } }
        switch key {
        case "c":
            NotificationCenter.default.post(name: .botoNewList, object: nil)
        case "/":
            NotificationCenter.default.post(name: .botoShowHelp, object: nil)
        case "g":
            pendingGo = Date()
        case "b" where pendingGo.map({ Date().timeIntervalSince($0) < 1.5 }) == true:
            NotificationCenter.default.post(name: .botoGoToProjects, object: nil)
        default:
            return false
        }
        return true
    }
}
