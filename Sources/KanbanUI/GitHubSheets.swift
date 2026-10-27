import KanbanCore
import SwiftUI

/// Token comes from the Keychain only; it is never stored in the database or shown after saving.
enum GitHubAccess {
    static let store = KeychainSecretStore()

    static func client() -> GitHubClient {
        GitHubClient(token: (try? store.read()) ?? nil)
    }
}

struct GitHubSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var hasToken = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub").font(Theme.font(15, weight: .semibold))
            Text("Boto reads issues and pull requests to link them to cards. It never writes to GitHub.")
                .font(Theme.font(12)).foregroundStyle(Theme.mutedStrong)
            Text("Create a fine-grained personal access token in GitHub (Settings, Developer settings) with read-only access to Issues and Pull requests on the repositories you need. Public items work without a token.")
                .font(Theme.font(11)).foregroundStyle(Theme.muted)
            SecureField(hasToken ? "Token saved. Paste a new one to replace it" : "Paste token", text: $token)
                .textFieldStyle(.roundedBorder)
            Text("Stored in the macOS Keychain.").font(Theme.font(11)).foregroundStyle(Theme.muted)
            if let message { Text(message).font(Theme.font(11)).foregroundStyle(Theme.overdue) }
            HStack {
                if hasToken { Button("Remove token", role: .destructive, action: remove) }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear { hasToken = ((try? GitHubAccess.store.read()) ?? nil) != nil }
    }

    private func save() {
        do {
            try GitHubAccess.store.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch { message = error.localizedDescription }
    }

    private func remove() {
        do {
            try GitHubAccess.store.delete()
            hasToken = false
        } catch { message = error.localizedDescription }
    }
}

struct AddGitHubSheet: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var message: String?
    @State private var loading = false

    private var link: GitHubLink? { GitHubLink.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link a GitHub issue or pull request").font(Theme.font(15, weight: .semibold))
            TextField("https://github.com/owner/repo/issues/12 or owner/repo#12", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            if !text.isEmpty && link == nil {
                Text("Not a recognised issue or pull request link.").font(Theme.font(11)).foregroundStyle(Theme.muted)
            }
            if let message { Text(message).font(Theme.font(11)).foregroundStyle(Theme.overdue) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(loading ? "Adding..." : "Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(link == nil || loading)
            }
        }
        .padding(22)
        .frame(width: 460)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private func add() {
        guard let link, !loading else { return }
        loading = true
        message = nil
        Task {
            defer { loading = false }
            do {
                let item = try await GitHubAccess.client().fetch(link)
                // Compare the real URL: a short link of unknown kind may be a pull request.
                if card.references.contains(where: { $0.displayPath == item.url.absoluteString }) {
                    message = "This item is already linked to the card."
                    return
                }
                card.references.append(Reference.make(item: item))
                dismiss()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
