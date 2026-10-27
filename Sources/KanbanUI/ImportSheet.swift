import KanbanCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// "New import" dialog: pick a source, preview what will be created, then import as a new project.
struct ImportSheet: View {
    enum Source: String, CaseIterable, Identifiable {
        case trello = "Trello", github = "GitHub"
        var id: String { rawValue }
        var icon: String { self == .trello ? "rectangle.split.2x1" : "chevron.left.forwardslash.chevron.right" }
    }

    let onImported: (Project) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var source = Source.trello
    @State private var preview: ImportedBoard?
    @State private var repoText = ""
    @State private var includeClosed = false
    @State private var includeArchived = false
    @State private var fileData: Data?
    @State private var message: String?
    @State private var loading = false

    private let maxFileSize = 50_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("New import").font(Theme.font(15, weight: .semibold))
                Image(systemName: "questionmark.circle").foregroundStyle(Theme.muted)
                    .help("Imports create a new project. Nothing is changed in Trello or GitHub.")
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.muted)
            }

            Picker("Source", selection: $source) {
                ForEach(Source.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
            }
            .labelsHidden()
            .onChange(of: source) { preview = nil; message = nil; fileData = nil }

            switch source {
            case .trello: trelloPane
            case .github: githubPane
            }

            if let message { Text(message).font(Theme.font(11)).foregroundStyle(Theme.overdue) }
            if let preview { previewRow(preview) }

            Divider().overlay(Theme.divider)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Import", action: runImport)
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview == nil || preview?.cardCount == 0)
            }
        }
        .padding(22)
        .frame(width: 480)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private var trelloPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In Trello, open the board menu, choose Print, Export, and Share, then export as JSON.")
                .font(Theme.font(11)).foregroundStyle(Theme.muted)
            Button("Choose Trello JSON export...", action: chooseTrelloFile)
            Toggle("Include archived lists and cards (they arrive archived)", isOn: $includeArchived)
                .onChange(of: includeArchived) { reparseTrello() }
        }
    }

    private var githubPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Imports the issues of one repository as cards. Pull requests are skipped. Up to 1000 issues. Private repositories need a token in the GitHub settings.")
                .font(Theme.font(11)).foregroundStyle(Theme.muted)
            HStack {
                TextField("owner/repo", text: $repoText).textFieldStyle(.roundedBorder).onSubmit(fetchIssues)
                Button(loading ? "Loading..." : "Load issues", action: fetchIssues)
                    .disabled(parsedRepo == nil || loading)
            }
            Toggle("Include closed issues", isOn: $includeClosed)
        }
    }

    private var parsedRepo: (owner: String, repo: String)? {
        let parts = repoText.trimmingCharacters(in: .whitespaces).split(separator: "/").map(String.init)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty ? (parts[0], parts[1]) : nil
    }

    private func previewRow(_ board: ImportedBoard) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(board.name).font(Theme.font(13, weight: .semibold))
            Text("\(board.lists.count) list\(board.lists.count == 1 ? "" : "s"), \(board.cardCount) card\(board.cardCount == 1 ? "" : "s")")
                .font(Theme.font(11)).foregroundStyle(Theme.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.card))
    }

    private func chooseTrelloFile() {
        guard let url = FilePanel.choose(files: true, directories: false, multiple: false, types: [.json]).first else { return }
        preview = nil
        message = nil
        do {
            let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= maxFileSize else { message = "That file is larger than 50 MB."; return }
            let data = try Data(contentsOf: url)
            fileData = data
            preview = try TrelloImporter.parse(data, includeArchived: includeArchived)
        } catch {
            message = error.localizedDescription
        }
    }

    private func reparseTrello() {
        guard let fileData else { return }
        message = nil
        do { preview = try TrelloImporter.parse(fileData, includeArchived: includeArchived) }
        catch { message = error.localizedDescription }
    }

    private func fetchIssues() {
        guard let target = parsedRepo, !loading else { return }
        loading = true
        preview = nil
        message = nil
        Task {
            defer { loading = false }
            do {
                let issues = try await GitHubAccess.client().issues(owner: target.owner, repo: target.repo, includeClosed: includeClosed)
                preview = GitHubImporter.board(repo: "\(target.owner)/\(target.repo)", issues: issues)
                if issues.isEmpty { message = "No issues found." }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func runImport() {
        guard let preview else { return }
        let project = Project(name: preview.name)
        context.insert(project)
        project.addBoard(from: preview)
        onImported(project)
        dismiss()
    }
}
